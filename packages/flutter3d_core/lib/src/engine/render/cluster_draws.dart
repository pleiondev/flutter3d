/// `C9`: which clusters of a split mesh a view draws, and the index buffer
/// that draws just those.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/geometry.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import '../geometry/device_mesh.dart';
import '../scene/mesh_node.dart';
import '../scene/occlusion/occlusion_test.dart';

/// Marks in [visible] (one byte per cluster) the clusters of [clusters] a
/// view may see, and returns how many.
///
/// Three tests, cheapest first, each only ever removing what the GPU would
/// not have drawn: the cluster's box, carried to the world through [world],
/// against [frustum]; its cone against [eye], the view's eye in the mesh's
/// own space (null for a view with no single eye, such as an orthographic
/// one, and for a draw that culls no back faces); and the world box against
/// [occlusion], when there is one.
int selectVisibleClusters({
  required MeshClusters clusters,
  required Matrix4 world,
  required Frustum frustum,
  required Uint8List visible,
  Vector3? eye,
  OcclusionTest? occlusion,
  Aabb3? scratch,
}) {
  final local = Aabb3();
  final box = scratch ?? Aabb3();
  var count = 0;
  for (var i = 0; i < clusters.length; i++) {
    clusters.boundsInto(i, local);
    box.copyFrom(local);
    box.transform(world);
    final keep =
        frustum.intersectsWithAabb3(box) &&
        (eye == null || !clusters.facesAwayFrom(i, eye.x, eye.y, eye.z)) &&
        (occlusion == null || occlusion.mayBeVisible(box));
    visible[i] = keep ? 1 : 0;
    if (keep) count++;
  }
  return count;
}

/// Where the eye of [viewProjection] stands in the space [world] maps from,
/// or null when the projection is orthographic and there is no one point.
///
/// Read from the matrix the draws use rather than from a camera node: the
/// eye is the one point every clip-space `x`, `y` and `w` is zero at, which
/// holds through an off-axis frustum, a tile of one and a jittered one alike.
/// So it is the null vector of those three rows, a point at infinity for an
/// orthographic view, and carried into the mesh by the inverse of [world].
Vector3? clusterEye(Matrix4 viewProjection, Matrix4 world) {
  final m = viewProjection.storage;
  // Rows 0, 1 and 3 of a column-major matrix.
  double at(int row, int column) => m[column * 4 + row];
  double minor(int skip) {
    final columns = <int>[
      for (var c = 0; c < 4; c++)
        if (c != skip) c,
    ];
    double e(int r, int c) => at(r, columns[c]);
    return e(0, 0) * (e(1, 1) * e(3, 2) - e(1, 2) * e(3, 1)) -
        e(0, 1) * (e(1, 0) * e(3, 2) - e(1, 2) * e(3, 0)) +
        e(0, 2) * (e(1, 0) * e(3, 1) - e(1, 1) * e(3, 0));
  }

  final homogeneous = Vector4(minor(0), -minor(1), minor(2), -minor(3));
  final inverse = Matrix4.copy(world);
  if (inverse.invert() == 0.0) return null;
  inverse.transform(homogeneous);
  final scale = homogeneous.xyz.length;
  if (!(homogeneous.w.abs() > scale * 1e-9)) return null;
  return homogeneous.xyz..scale(1.0 / homogeneous.w);
}

/// The index buffers the scene pass draws split meshes through, one per mesh
/// node and view, repacked only when the clusters that view sees change —
/// `C9`.
///
/// **One buffer the size of the mesh's, overwritten in place.** A view's
/// visible clusters are consecutive runs of the mesh's own indices, so the
/// subset is those runs end to end at the front of a buffer that could hold
/// them all, and the draw reads that prefix. A frame whose view sees the same
/// clusters as the last touches nothing; one that sees all of them binds the
/// mesh's own buffer, and one that sees none draws nothing. The cost is a
/// second copy of each split mesh's indices per view that draws it.
///
/// A slot no frame has drawn with for longer than the frames in flight is
/// given back to the device, so a node that left the scene, or a view that
/// went away, leaves nothing behind for long.
final class ClusterDraws {
  ClusterDraws(this._device, {this.framesInFlight = 3});

  final GraphicsDevice _device;

  /// How many frames a buffer may still be read by after its last draw.
  final int framesInFlight;

  final Map<(MeshNode, int), _ClusterSlot> _slots =
      <(MeshNode, int), _ClusterSlot>{};
  final Aabb3 _box = Aabb3();
  int _frame = 0;

  /// Clusters the draws of the current frame left out, across every view.
  int get culled => _culled;
  int _culled = 0;

  /// How many buffers are held, for a test that checks they are let go.
  int get slotCount => _slots.length;

  /// Starts frame [frame], giving back what nothing has drawn with lately.
  void beginFrame(int frame) {
    _frame = frame;
    _culled = 0;
    _slots.removeWhere((_, slot) {
      final stale = frame - slot.lastFrame > framesInFlight;
      if (stale) slot.release(_device);
      return stale;
    });
    _retiring.removeWhere((retired) {
      final done = frame - retired.frame > framesInFlight;
      if (done) _device.releaseGeometry(retired.buffer);
      return done;
    });
  }

  final List<({int frame, GeometryBuffer buffer})> _retiring =
      <({int frame, GeometryBuffer buffer})>[];

  void _retire(_ClusterSlot slot) {
    final buffer = slot.buffer;
    if (buffer != null) _retiring.add((frame: _frame, buffer: buffer));
    slot.buffer = null;
  }

  /// What [node], drawing [mesh] in view number [view] this frame, should
  /// bind: null for the mesh's own buffer (every cluster is in view), or a
  /// buffer and an index count, which is zero when nothing is.
  ///
  /// [eye] is [clusterEye]'s, or null where back faces are drawn.
  ({GeometryBuffer buffer, int count})? indicesFor({
    required MeshNode node,
    required DrawableGeometry mesh,
    required int view,
    required Frustum frustum,
    Vector3? eye,
    OcclusionTest? occlusion,
  }) {
    final clustered = mesh.clusters;
    if (clustered == null) return null;
    final table = clustered.table;
    final key = (node, view);
    final held = _slots[key];
    // A node given another mesh keeps the slot's key and nothing else; the
    // old buffer may still be read by a frame in flight.
    if (held != null && !identical(held.mesh, mesh)) _retire(held);
    final slot = held != null && identical(held.mesh, mesh)
        ? held
        : (_slots[key] = _ClusterSlot(mesh, table.length));
    if (slot.lastFrame != _frame) {
      slot
        ..lastFrame = _frame
        ..visibleCount = selectVisibleClusters(
          clusters: table,
          world: node.worldMatrix,
          frustum: frustum,
          visible: slot.visible,
          eye: eye,
          occlusion: occlusion,
          scratch: _box,
        );
      _culled += table.length - slot.visibleCount;
    }
    if (slot.visibleCount == table.length) return null;
    if (slot.visibleCount == 0) {
      return (buffer: slot.buffer ?? mesh.indices, count: 0);
    }
    if (!slot.writtenMatches()) slot.write(_device, table, clustered.indices);
    return (buffer: slot.buffer!, count: slot.writtenCount);
  }

  /// Gives every buffer back, for a renderer that is going away.
  void dispose() {
    for (final slot in _slots.values) {
      slot.release(_device);
    }
    _slots.clear();
    for (final retired in _retiring) {
      _device.releaseGeometry(retired.buffer);
    }
    _retiring.clear();
  }
}

/// One node's split mesh as one view draws it.
final class _ClusterSlot {
  _ClusterSlot(this.mesh, int clusters)
    : visible = Uint8List(clusters),
      written = Uint8List(clusters);

  final DrawableGeometry mesh;
  final Uint8List visible;

  /// The clusters whose runs [buffer] holds, front to back.
  final Uint8List written;
  int writtenCount = 0;
  GeometryBuffer? buffer;

  /// Keeps [indicesFor] from asking twice in one frame, and says when the
  /// slot was last drawn with.
  int lastFrame = -1;
  int visibleCount = 0;

  bool writtenMatches() {
    if (buffer == null) return false;
    for (var i = 0; i < visible.length; i++) {
      if (visible[i] != written[i]) return false;
    }
    return true;
  }

  /// Packs the visible runs of [indices] to the front of [buffer], making
  /// the buffer the first time. Its own bytes, not a view of the mesh's: a
  /// device that keeps what it was given would otherwise have the mesh's
  /// indices overwritten under it.
  void write(GraphicsDevice device, MeshClusters table, Uint32List indices) {
    final wide = mesh.indexType == IndexType.int32;
    final packed = wide
        ? Uint32List(indices.length)
        : Uint16List(indices.length);
    var at = 0;
    for (var i = 0; i < table.length; i++) {
      if (visible[i] == 0) continue;
      final from = table.firstIndex(i);
      final to = table.firstIndex(i + 1);
      for (var j = from; j < to; j++) {
        packed[at++] = indices[j];
      }
    }
    final bytes = packed.buffer.asByteData(0, at * packed.elementSizeInBytes);
    final existing = buffer;
    if (existing == null) {
      buffer = device.uploadGeometry(
        packed.buffer.asByteData(),
        GeometryUsage.indices,
      );
    } else {
      device.overwriteGeometry(existing, 0, bytes);
    }
    written.setAll(0, visible);
    writtenCount = at;
  }

  void release(GraphicsDevice device) {
    final existing = buffer;
    if (existing != null) device.releaseGeometry(existing);
    buffer = null;
  }
}
