/// `pro-sc-05`: only the chunks a stroke touched reach the GPU, and only
/// once a frame.
///
///     flutter test test/sculpt_upload_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_modeler/src/sculpt_upload.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import 'support/fake_graphics_backend.dart';

/// A grid big enough to sit in several chunks — a chunk is 1024 vertices,
/// so 64×64 is four of them and a brush lands in one or two.
SculptMesh _grid({int side = 64}) {
  final points = <Vector3>[];
  for (var z = 0; z < side; z++) {
    for (var x = 0; x < side; x++) {
      points.add(Vector3(x.toDouble(), 0, z.toDouble()));
    }
  }
  final faces = <List<int>>[
    for (var z = 0; z < side - 1; z++)
      for (var x = 0; x < side - 1; x++)
        <int>[
          z * side + x,
          z * side + x + 1,
          (z + 1) * side + x + 1,
          (z + 1) * side + x,
        ],
  ];
  return SculptMesh.fromEditMesh(EditMesh.fromFaces(points, faces));
}

/// A position-only device mesh of [count] vertices — the layout an
/// incremental overwrite is legal on.
DeviceMesh _positionOnly(GraphicsDevice device, SculptMesh mesh) =>
    DeviceMesh.upload(
      device,
      MeshData(
        layout: VertexLayout.positionOnly,
        vertices: Float32List(mesh.vertexCount * 3),
        indices: Uint32List.fromList(mesh.triangles),
      ),
    );

void main() {
  test('a stroke uploads its own chunks and no others', () {
    final it = fakeTestDevice(width: 8, height: 8);
    final SculptMesh mesh = _grid();
    final DeviceMesh gpu = _positionOnly(it.device, mesh);
    final upload = SculptUpload(device: it.device);

    mesh.applyBrush(
      center: Vector3(3, 0, 3),
      radius: 2.0,
      displace: (int _, Vector3 at, double falloff) =>
          at + Vector3(0, falloff * 0.5, 0),
    );
    final int touched = mesh.dirtyChunks.length;
    expect(touched, greaterThan(0));

    final SculptUploadReport report = upload.sync(mesh, gpu, frame: 1);

    // **Mutation: upload the whole buffer.** The measurement the row names
    // is "the frame only differs inside the brush area", and a whole-buffer
    // copy passes that while costing a million vertices per stroke sample —
    // which is the thing `pro-sc-02`'s chunks exist to avoid.
    expect(report.rebuilt, isFalse);
    expect(report.chunks, touched);
    expect(report.vertices, lessThan(mesh.vertexCount));
    expect(mesh.dirtyChunks, isEmpty);
  });

  test('and a second call in the same frame does nothing', () {
    final it = fakeTestDevice(width: 8, height: 8);
    final SculptMesh mesh = _grid();
    final DeviceMesh gpu = _positionOnly(it.device, mesh);
    final upload = SculptUpload(device: it.device);

    mesh.applyBrush(
      center: Vector3(3, 0, 3),
      radius: 2.0,
      displace: (int _, Vector3 at, double falloff) =>
          at + Vector3(0, falloff * 0.5, 0),
    );
    expect(upload.sync(mesh, gpu, frame: 7).chunks, greaterThan(0));

    // A brush reports every pointer sample — a few hundred a second on a
    // tablet — and all of them land in one frame. Mutation: upload per
    // sample, and the frame that draws one copy has queued five.
    mesh.applyBrush(
      center: Vector3(4, 0, 4),
      radius: 2.0,
      displace: (int _, Vector3 at, double falloff) =>
          at + Vector3(0, falloff * 0.5, 0),
    );
    final SculptUploadReport again = upload.sync(mesh, gpu, frame: 7);
    expect(again.chunks, 0);
    // The work is not lost, only deferred: the chunks stay dirty and the
    // next frame takes them.
    expect(mesh.dirtyChunks, isNotEmpty);
    expect(upload.sync(mesh, gpu, frame: 8).chunks, greaterThan(0));
  });

  test('a mesh with normals in it is rebuilt rather than patched', () {
    final it = fakeTestDevice(width: 8, height: 8);
    final SculptMesh mesh = _grid();
    final DeviceMesh gpu = _positionOnly(it.device, mesh);
    final upload = SculptUpload(device: it.device);

    mesh.applyBrush(
      center: Vector3(3, 0, 3),
      radius: 2.0,
      displace: (int _, Vector3 at, double falloff) =>
          at + Vector3(0, falloff * 0.5, 0),
    );
    final SculptUploadReport report = upload.sync(
      mesh,
      gpu,
      frame: 1,
      normals: true,
    );

    // **A normal belongs to a vertex's neighbours, not to its own chunk.**
    // Mutation: patch positions anyway. The shape changes and the lighting
    // goes on describing the shape as it was, which reads as a dent that
    // is lit like a flat.
    expect(report.rebuilt, isTrue);
    expect(upload.rebuiltMesh, isNotNull);
    expect(upload.rebuiltMesh!.vertexCount, mesh.vertexCount);
  });

  test('nothing to upload is not an upload', () {
    final it = fakeTestDevice(width: 8, height: 8);
    final SculptMesh mesh = _grid();
    final DeviceMesh gpu = _positionOnly(it.device, mesh);
    final upload = SculptUpload(device: it.device);

    expect(upload.sync(mesh, gpu, frame: 1).chunks, 0);
    expect(upload.rebuiltMesh, isNull);
  });
}
