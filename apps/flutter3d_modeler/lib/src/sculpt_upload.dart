/// `pro-sc-05`: the chunks a stroke touched, onto the GPU, once a frame.
///
/// **A stroke touches about one chunk in a hundred, and the mesh it is
/// touching is a million vertices.** `pro-sc-02` made the chunks so that
/// number could be small; this is the half that spends it — the upload
/// copies the chunks a brush actually moved, not the buffer they sit in.
///
/// **Once a frame, whatever the pointer does.** A brush reports every
/// pointer sample, and a finger crossing a tablet at speed reports a few
/// hundred a second; uploading per sample would queue five copies of the
/// same chunk for the frame that draws one of them. So the strokes
/// accumulate into `SculptMesh.dirtyChunks`, which is a set, and the upload
/// drains it at most once per frame number it is handed.
///
/// **And a fallback that is honest about its cost.** An incremental
/// overwrite is only legal where the mesh's vertices are exactly the three
/// floats a chunk holds — `VertexLayout.positionOnly`'s own stride. Any
/// other layout interleaves attributes a chunk does not carry, so writing
/// positions into it would write them over somebody's normals; that case
/// rebuilds the whole `DeviceMesh` from the sculpt mesh instead, which is
/// the slow path the row names and which no measurement is allowed to hide
/// behind — [SculptUploadReport.rebuilt] says which of the two ran.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';

/// What one call to [SculptUpload.sync] did.
typedef SculptUploadReport = ({
  /// How many chunks were written this frame. Zero for a frame with no
  /// stroke in it, and for a second call inside one frame.
  int chunks,

  /// How many vertices those chunks hold — what the measurement compares
  /// against the mesh's own vertex count.
  int vertices,

  /// Whether the whole mesh was rebuilt rather than patched.
  bool rebuilt,
});

/// Three floats per vertex: the layout a chunk's own rows already are.
const int kSculptStride = 12;

/// Keeps a [DeviceMesh] in step with a [SculptMesh] being sculpted.
final class SculptUpload {
  SculptUpload({required this.device});

  final GraphicsDevice device;

  /// The frame number the last upload ran on, so a second call inside one
  /// frame does nothing rather than uploading the same chunks again.
  int? _uploadedOn;

  /// The mesh currently on the GPU, when this has rebuilt one.
  DeviceMesh? _rebuilt;

  /// What the viewport should draw: the rebuilt mesh where the slow path
  /// has run, and whatever it was handed otherwise.
  DeviceMesh? get rebuiltMesh => _rebuilt;

  /// Writes [mesh]'s dirty chunks into [into] and clears them.
  ///
  /// [frame] is the frame counter the viewport already keeps; two calls
  /// with the same number do the work once. [normals] rebuilds rather than
  /// patches, because a normal is derived from vertices a chunk does not
  /// own — its neighbours' — and patching positions alone would leave the
  /// lighting describing the shape as it was.
  SculptUploadReport sync(
    SculptMesh mesh,
    DeviceMesh into, {
    required int frame,
    bool normals = false,
  }) {
    if (_uploadedOn == frame) {
      return (chunks: 0, vertices: 0, rebuilt: false);
    }
    _uploadedOn = frame;
    final Set<int> dirty = mesh.dirtyChunks;
    if (dirty.isEmpty) return (chunks: 0, vertices: 0, rebuilt: false);

    final int stride = into.vertexCount == 0
        ? 0
        : into.vertices.lengthInBytes ~/ into.vertexCount;
    if (stride != kSculptStride || normals) {
      _rebuild(mesh);
      mesh.clearDirtyChunks();
      return (chunks: dirty.length, vertices: mesh.vertexCount, rebuilt: true);
    }

    var vertices = 0;
    for (final int chunk in dirty) {
      final int first = chunk * SculptMesh.chunkSize;
      if (first >= mesh.vertexCount) continue;
      final int count = (mesh.vertexCount - first)
          .clamp(0, SculptMesh.chunkSize)
          .toInt();
      final Float32List rows = mesh.chunkPositions(chunk);
      // The last chunk is partly filled: its array is a whole chunk wide
      // and only `count` of its rows are vertices of this mesh.
      final ByteData bytes = rows.buffer.asByteData(
        rows.offsetInBytes,
        count * kSculptStride,
      );
      into.overwriteVertices(device, first, bytes);
      vertices += count;
    }
    mesh.clearDirtyChunks();
    return (chunks: dirty.length, vertices: vertices, rebuilt: false);
  }

  /// The slow path: a whole new `DeviceMesh` from the sculpt mesh as it
  /// stands. Kept here rather than at the call site so that a caller cannot
  /// take the fast path's answer and the slow path's mesh by accident.
  void _rebuild(SculptMesh mesh) {
    final Float32List positions = Float32List(mesh.vertexCount * 3);
    for (var v = 0; v < mesh.vertexCount; v++) {
      final int chunk = SculptMesh.chunkOf(v);
      final Float32List rows = mesh.chunkPositions(chunk);
      final int at = (v % SculptMesh.chunkSize) * 3;
      positions[v * 3] = rows[at];
      positions[v * 3 + 1] = rows[at + 1];
      positions[v * 3 + 2] = rows[at + 2];
    }
    _rebuilt = DeviceMesh.upload(
      device,
      MeshData(
        layout: VertexLayout.positionOnly,
        vertices: positions,
        indices: Uint32List.fromList(mesh.triangles),
      ),
    );
  }

  /// Forgets the frame a sync last ran on — what a caller runs when the
  /// document changes under it, so the next frame uploads rather than
  /// deciding it already has.
  void forget() => _uploadedOn = null;
}
