import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import '../scene/bvh.dart';
import '../scene/scene_spheres.dart';
import '../scene/mesh_node.dart';
import '../scene/scene.dart';
import 'key_sort.dart';
import 'material.dart';
import 'render_view.dart';

/// One entry in a render list.
///
/// Mutable and pooled: entries are reused across frames so building a render
/// list allocates nothing after the first few frames. That matters more in Dart
/// than in JS — a fresh object per visible mesh per frame is exactly the
/// allocation pattern that turns into GC pauses inside the frame budget.
final class DrawItem {
  MeshNode? node;

  /// Distance from the camera along its forward axis, used by every depth sort.
  double viewDepth = 0.0;

  MeshNode get requireNode => node!;

  Material get material => node!.material;
}

/// Visible draws for one view, split into opaque and transparent halves.
///
/// The split mirrors PlayCanvas sub-layers: the two halves need different sort
/// orders, so separating them is simpler than one list with a mixed comparator.
final class RenderList {
  /// Material ids for the state sort term. Owned here because this is the only
  /// place they are used.
  final MaterialSortIds materialIds = MaterialSortIds();

  /// Above this many meshes, culling goes through the tree.
  ///
  /// Set from measurement rather than taste, and the measurement is not
  /// flattering. `tool/bench/bench.dart` on 200 000 spheres:
  ///
  /// | case | linear | BVH |
  /// |---|---|---|
  /// | everything on screen | 2.4 ms | 4.6 ms |
  /// | nothing on screen | 1.6 ms | 0.0 ms |
  ///
  /// A tree only pays when it can reject. With every object visible it adds
  /// traversal on top of the same leaf tests and loses outright — and a rebuild
  /// of that scene costs 93 ms, which no frame can absorb. So the threshold is
  /// high, the rebuild is skipped unless a transform actually changed, and a
  /// scene that both is large and moves constantly is still better served by
  /// the linear pass. Getting past that is what clustered culling and a
  /// refittable tree are for; neither is here yet.
  static const int bvhThreshold = 2048;

  /// Shared with the raycaster, so the tree is built once per frame rather than
  /// once per consumer.
  final SceneBvh bvh = SceneBvh();

  /// Whether the last [build] went through the tree.
  bool usedBvh = false;

  final Aabb3 _bvhScratch = Aabb3();
  Float32List _bvhSpheres = Float32List(0);

  final List<DrawItem> _pool = <DrawItem>[];
  int _used = 0;

  final List<int> opaque = <int>[];
  final List<int> transparent = <int>[];

  /// Packed key-plus-index entries, and the alternate buffer radix passes need.
  /// Reused between frames so sorting allocates nothing.
  Int64List _sortBuffer = Int64List(128);
  Int64List _sortScratch = Int64List(128);
  final Uint32List _histogram = Uint32List(256);

  int get length => _used;

  DrawItem itemAt(int index) => _pool[index];

  void reset() {
    _used = 0;
    opaque.clear();
    transparent.clear();
  }

  DrawItem _claim() {
    if (_used == _pool.length) _pool.add(DrawItem());
    return _pool[_used++];
  }

  /// Collects the visible meshes of [scene] for [view].
  ///
  /// A linear pass over the scene's flat mesh registry — the hierarchy is never
  /// walked here.
  void build(
    Scene scene,
    RenderView view, {
    required Matrix4 viewMatrix,
    required Frustum frustum,
  }) {
    reset();

    final meshes = scene.meshes;
    final viewRow = viewMatrix.storage;
    final centre = Vector3.zero();
    final sphere = Sphere.centerRadius(Vector3.zero(), 1.0);

    /// The per-mesh work, identical whichever way the candidates arrived.
    ///
    /// Shared on purpose: the tree is only allowed to skip meshes it can prove
    /// are outside the frustum, so every candidate it does produce must go
    /// through exactly the same tests the linear pass applies. That is what
    /// makes "the tree returns the same visible set" a property rather than a
    /// hope.
    void consider(MeshNode node) {
      if (!node.visibleInHierarchy) return;
      if ((node.layerMask & view.layerMask) == 0) return;
      if (node.mesh.indexCount == 0) return;

      centre.setFrom(node.worldBoundsCentre);
      final radius = node.worldBoundsRadius;

      if (node.frustumCulled) {
        sphere.center.setFrom(centre);
        sphere.radius = radius;
        if (!frustum.intersectsWithSphere(sphere)) return;
      }

      // Eye-space depth is the third row of the view matrix applied to the
      // centre, negated because the camera looks down -Z. Computing it inline
      // avoids transforming a whole vector.
      final eyeZ = viewRow[2] * centre.x +
          viewRow[6] * centre.y +
          viewRow[10] * centre.z +
          viewRow[14];

      _claim()
        ..node = node
        ..viewDepth = -eyeZ;

      final index = _used - 1;
      // More draws than the packed payload can address would alias one entry onto
      // another's slot. Six figures of draws is far past anything this renderer
      // can submit, so an assert is the right level of defence.
      assert(index <= kMaxPayload, 'Too many draws to pack into a sort key.');

      if (node.material.isTransparent) {
        transparent.add(index);
      } else {
        opaque.add(index);
      }
    }

    usedBvh = meshes.length >= bvhThreshold;
    if (usedBvh) {
      _bvhSpheres = ensureSphereCapacity(_bvhSpheres, meshes.length);
      bvh.refresh(
        _bvhSpheres,
        meshes.length,
        packSceneSpheres(meshes, _bvhSpheres),
      );
      bvh.queryFrustum(
        frustum,
        (index) => consider(meshes[index]),
        scratch: _bvhScratch,
      );
      return;
    }

    for (var i = 0; i < meshes.length; i++) {
      consider(meshes[i]);
    }
  }

  /// Sorts both halves according to the view's sort modes.
  void sort(RenderView view) {
    _sortRange(opaque, view.opaqueSort);
    _sortRange(transparent, view.transparentSort);
  }

  void _sortRange(List<int> indices, SortMode mode) {
    final count = indices.length;
    if (mode == SortMode.none || count < 2) return;

    if (count > _sortBuffer.length) {
      var capacity = _sortBuffer.length;
      while (capacity < count) {
        capacity *= 2;
      }
      _sortBuffer = Int64List(capacity);
      _sortScratch = Int64List(capacity);
    }

    // One packed integer per draw: the sort key in the high bits, the draw's slot
    // in the low bits. Sorting the packed values directly avoids the comparator
    // closure and the double indirection that made this the most expensive step
    // in the frame.
    final buffer = _sortBuffer;
    for (var i = 0; i < count; i++) {
      final index = indices[i];
      buffer[i] = (_sortKey(_pool[index], mode) << kPayloadBits) | index;
    }

    sortPackedKeys(buffer, _sortScratch, count, counts: _histogram);

    for (var i = 0; i < count; i++) {
      indices[i] = buffer[i] & kPayloadMask;
    }
  }

  /// Layout of the 43 bits available to a key, above the 20-bit draw index:
  ///
  /// ```
  /// stateThenDepth : bucket:8 | pipeline:6 | material:15 | depth:14
  /// frontToBack    : bucket:8 |                 depth:35
  /// backToFront    : bucket:8 |              invDepth:35
  /// manual         : bucket:8 |                       0
  /// ```
  ///
  /// Pipeline outranks material because flutter_gpu builds pipelines ahead of
  /// time and switching one mid-pass is the costliest state change available.
  /// In a web engine this term would be a nice-to-have; here it is the point.
  ///
  /// The draw index sits below every field, so the sort's stability makes equal
  /// keys fall back to submission order — which is exactly what `manual` mode
  /// means, and it gets it for free.
  int _sortKey(DrawItem item, SortMode mode) {
    final material = item.material;
    final bucket = material.drawBucket & 0xFF;

    switch (mode) {
      case SortMode.stateThenDepth:
        final pipeline = material.lighting.index & 0x3F;
        final materialId = materialIds.idOf(material, limit: 0x7FFF) & 0x7FFF;
        // Depth is the least significant term here and only serves early-z, so
        // 14 bits of range is ample even though it saturates past 256 units.
        return (bucket << 35) |
            (pipeline << 29) |
            (materialId << 14) |
            _quantize(item.viewDepth, 64.0, 14, invert: false);

      case SortMode.frontToBack:
        return (bucket << 35) | _quantize(item.viewDepth, 1024.0, 35, invert: false);

      case SortMode.backToFront:
        return (bucket << 35) | _quantize(item.viewDepth, 1024.0, 35, invert: true);

      case SortMode.manual:
        return bucket << 35;

      case SortMode.none:
        return 0;
    }
  }

  /// Quantizes a view depth into [bits] bits, optionally reversed for far-to-near.
  int _quantize(double depth, double scale, int bits, {required bool invert}) {
    final limit = (1 << bits) - 1;
    var scaled = (depth * scale).round();
    if (scaled < 0) scaled = 0;
    if (scaled > limit) scaled = limit;
    return invert ? limit - scaled : scaled;
  }
}
