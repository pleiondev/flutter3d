import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import '../scene/bvh.dart';
import '../scene/mesh_node.dart';
import '../scene/scene.dart';
import '../scene/scene_node.dart';
import '../scene/scene_spheres.dart';
import 'key_sort.dart';
import 'material.dart';
import 'packed_keys.dart';
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

  /// Where [bvhThreshold] starts.
  ///
  /// Set from measurement rather than taste, and the measurement moved when the
  /// tree learned to refit. `tool/bench_scene_bvh.dart` on 2026-09-18 — Dart
  /// 3.13.0 AOT, Apple M3 Pro, macOS 27 — timing the whole render list, which
  /// is the thing being decided, rather than a bare sphere test:
  ///
  /// | meshes | on screen | walk | tree |
  /// |---|---|---|---|
  /// | 128 | all | 7.0 us | 6.5 us |
  /// | 128 | a tenth | 5.4 us | 5.4 us |
  /// | 256 | all | 13.3 us | 13.8 us |
  /// | 256 | a tenth | 11.6 us | 8.8 us |
  /// | 1024 | a tenth | 42 us | 29 us |
  /// | 4096 | a tenth | 162 us | 70 us |
  /// | 50 000 | a tenth | 4646 us | 896 us |
  ///
  /// The scene there is flat — every mesh hangs off the root — which is the
  /// walk's worst case since `gfx-66n`, because there is no branch to reject
  /// and it pays the descent anyway: about 6.6 ns a node at these sizes, so at
  /// most a microsecond and a half below the threshold. A scene with rooms or
  /// vehicles in it is the case the walk exists for and does not appear here.
  ///
  /// The day is written down because these numbers decide a threshold and
  /// nothing else recounts them: without it there is no telling a figure that
  /// still holds from one taken on an SDK the repository has since left.
  ///
  /// **A tree only pays when it can reject**, and that is the whole shape of
  /// the table. With most of the scene off screen it wins from 256 meshes and
  /// keeps winning by more, because a mesh the tree never visits costs nothing,
  /// while the walk pays for the visibility flags, the layer mask and a bounds
  /// refresh before it can reject anything. With everything on screen it loses
  /// by about a fifth from a thousand meshes up, and that is the trade taken
  /// here: a scene with four thousand meshes all on screen is GPU-bound on the
  /// draw calls long before fifty microseconds of culling matters, while the
  /// same scene seen from inside saves ninety.
  ///
  /// `gfx-62n` asked for a hundred. Three changes moved the number down from
  /// 2048: the tree is refitted rather than rebuilt when things merely move, so
  /// the figure to clear is traversal rather than a 23 ms rebuild; a node the
  /// frustum fully contains hands over its whole subtree as one flat range,
  /// which is what stopped the all-on-screen column being a rout; and
  /// `gfx-66n`'s hierarchy walk gave the other side a small cost of its own. By
  /// 128 the two are within noise of each other and 256 is where the tree wins
  /// outright, so 256 is the number rather than the hundred the row asked for —
  /// a threshold set where one side clearly wins, not where they are level.
  static const int defaultBvhThreshold = 256;

  /// Above this many meshes, culling goes through the tree.
  ///
  /// A field rather than a constant because [defaultBvhThreshold] is one
  /// machine's answer, and an application that knows its own scenes — a viewer
  /// where nothing ever moves, a simulation where everything does — has better
  /// information than a number measured here. It is also what lets the
  /// benchmark run both paths over the same scene.
  int bvhThreshold = defaultBvhThreshold;

  /// Shared with the raycaster, so the tree is built once per frame rather than
  /// once per consumer.
  final SceneBvh bvh = SceneBvh();

  /// Whether the last [build] went through the tree.
  bool usedBvh = false;

  /// How many meshes the last [build] looked at one at a time.
  ///
  /// The reading `gfx-66n` is about, and it needs a number because a branch
  /// rejected whole and a branch rejected mesh by mesh draw the same picture.
  /// Against `scene.meshes.length` it says what the cull skipped: the tree's
  /// candidates on the accelerated path, and the meshes under branches the
  /// frustum kept on the other.
  int considered = 0;

  final Aabb3 _bvhScratch = Aabb3();
  Float32List _bvhSpheres = Float32List(0);

  /// [SceneNode.changeEpoch] and the mesh count as of the last pack, so a frame
  /// where nothing was touched skips it. -1 is "never packed".
  int _bvhEpoch = -1;
  int _bvhCount = -1;

  final List<DrawItem> _pool = <DrawItem>[];
  int _used = 0;

  final List<int> opaque = <int>[];
  final List<int> transparent = <int>[];

  /// Packed key-plus-index entries, and the alternate buffer radix passes need.
  /// Reused between frames so sorting allocates nothing.
  final PackedKeys _keys = PackedKeys();

  int get length => _used;

  DrawItem itemAt(int index) => _pool[index];

  void reset() {
    _used = 0;
    considered = 0;
    opaque.clear();
    transparent.clear();
  }

  DrawItem _claim() {
    if (_used == _pool.length) _pool.add(DrawItem());
    return _pool[_used++];
  }

  /// Collects the visible meshes of [scene] for [view].
  ///
  /// Below [bvhThreshold] meshes, a walk down the hierarchy that rejects a
  /// whole branch whose subtree bounds miss the frustum — `gfx-66n`; at or
  /// above it, a query of the scene's spatial tree. Either way every candidate
  /// goes through the same per-mesh tests.
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

    /// The per-mesh work, identical whichever way the candidates arrived.
    ///
    /// Shared on purpose: the tree is only allowed to skip meshes it can prove
    /// are outside the frustum, so every candidate it does produce must go
    /// through exactly the same tests the linear pass applies. That is what
    /// makes "the tree returns the same visible set" a property rather than a
    /// hope.
    void consider(MeshNode node) {
      considered++;
      if (!node.visibleInHierarchy) return;
      // A proxy occluder casts and is never seen. Filtered here rather than in
      // the shadow pass because this is the pass it is absent from: the shadow
      // passes walk the scene's registry themselves and want it.
      if (!node.shadowCasting.drawsColour) return;
      if ((node.layerMask & view.layerMask) == 0) return;
      if (node.mesh.indexCount == 0) return;

      // The centre is still wanted for the depth sort below, and reading it
      // is what refreshes the bounds the cull then tests.
      centre.setFrom(node.worldBoundsCentre);

      if (node.frustumCulled) {
        // **The box, not the sphere around it — `gfx-61n`.**
        // `MeshNode._refreshBounds` fills both in one call, and the two reads
        // above have already triggered it, so the exact world AABB is sitting
        // there costing nothing extra. Testing the sphere instead threw that
        // away: a sphere around a box has up to `sqrt(3)` times its half
        // extent, so a long thin mesh — a wall, a corridor floor, a fence —
        // reads as a ball the length of its longest side and survives the
        // frustum from well outside it.
        //
        // The sphere is still what the BVH is built over, which is `gfx-62n`'s
        // row rather than this one.
        if (!frustum.intersectsWithAabb3(node.worldBounds)) return;
      }

      // Eye-space depth is the third row of the view matrix applied to the
      // centre, negated because the camera looks down -Z. Computing it inline
      // avoids transforming a whole vector.
      final eyeZ =
          viewRow[2] * centre.x +
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
      // **A frame where nothing was touched packs nothing — `gfx-62n`.**
      // Repacking is how the tree found out whether anything had moved, and it
      // is a full pass over every mesh with three version-checked getters
      // apiece: measured at 3.3 ms on 50 000 meshes, which is the whole cost of
      // the linear cull it exists to avoid. So the tree could not win at any
      // size, and no threshold was going to fix that.
      //
      // `changeEpoch` answers the same question in one comparison. It
      // over-reports — a node set to the position it already had advances
      // it — which costs a frame of repacking and can never miss a move.
      final epoch = SceneNode.changeEpoch;
      if (epoch != _bvhEpoch || meshes.length != _bvhCount) {
        _bvhSpheres = ensureSphereCapacity(_bvhSpheres, meshes.length);
        bvh.refresh(
          _bvhSpheres,
          meshes.length,
          packSceneSpheres(meshes, _bvhSpheres),
        );
        _bvhEpoch = epoch;
        _bvhCount = meshes.length;
      }
      bvh.queryFrustum(
        frustum,
        (index) => consider(meshes[index]),
        scratch: _bvhScratch,
      );
      return;
    }

    // **Down the hierarchy rather than along the registry — `gfx-66n`.** The
    // registry is flat and that is what made it fast; what it cannot do is
    // reject a branch. A room, a vehicle or a character is one node holding
    // dozens or hundreds, and every one of them was a frustum test even with
    // the whole room behind the camera.
    //
    // **The order is the same order**, which is the part that had to be true
    // before this could land. `SortMode.manual` and every tie in the other
    // modes fall back to the order draws were claimed in, and the registry is
    // filled by `onAttachedToScene`, which a subtree reaches in pre-order —
    // the order this walk visits in.
    //
    // An explicit stack, pushed in reverse so children come off it in order.
    _walk
      ..clear()
      ..add(scene.root);
    while (_walk.isNotEmpty) {
      final node = _walk.removeLast();
      if (!node.visible) continue;

      final children = node.childrenView;
      if (children.isNotEmpty) {
        final box = node.subtreeBounds;
        if (box == null) continue;
        if (!node.subtreeAlwaysDrawn && !frustum.intersectsWithAabb3(box)) {
          continue;
        }
      }

      if (node is MeshNode) consider(node);
      for (var i = children.length - 1; i >= 0; i--) {
        _walk.add(children[i]);
      }
    }
  }

  /// The hierarchy walk's stack, kept between frames so a cull allocates none.
  final List<SceneNode> _walk = <SceneNode>[];

  /// Sorts both halves according to the view's sort modes.
  void sort(RenderView view) {
    _sortRange(opaque, view.opaqueSort);
    _sortRange(transparent, view.transparentSort);
  }

  void _sortRange(List<int> indices, SortMode mode) {
    final count = indices.length;
    if (mode == SortMode.none || count < 2) return;

    _keys.ensure(count);

    // One key per draw, carrying the draw's slot as its payload. Sorting these
    // directly avoids the comparator closure and the double indirection that
    // made this the most expensive step in the frame. How a key and its payload
    // are stored differs by platform — see packed_keys.dart — and this loop is
    // the same either way.
    for (var i = 0; i < count; i++) {
      final index = indices[i];
      _keys.setEntry(i, _sortKey(_pool[index], mode), index);
    }

    _keys.sort(count);

    for (var i = 0; i < count; i++) {
      indices[i] = _keys.payloadAt(i);
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
  /// Pipeline outranks material because pipelines are built ahead of
  /// time and switching one mid-pass is the costliest state change available.
  /// In a web engine this term would be a nice-to-have; here it is the point.
  ///
  /// The draw index sits below every field, so the sort's stability makes equal
  /// keys fall back to submission order — which is exactly what `manual` mode
  /// means, and it gets it for free.
  int _sortKey(DrawItem item, SortMode mode) {
    final material = item.material;
    // Biased and clamped, not masked. The field is signed and the point of it
    // is to force something out of the ordinary order — and the ordinary order
    // is bucket zero, so the only way to be *before* everything is a negative
    // bucket. `& 0xFF` sent −1 to 255 and drew the thing dead last, silently:
    // a sky asked to go first went behind nothing and in front of everything.
    // Clamping rather than wrapping for the same reason at the other end.
    final bucket = (material.drawBucket + 128).clamp(0, 255);

    switch (mode) {
      case SortMode.stateThenDepth:
        // LightingModel is open, so there is no ordinal to take. See
        // [LightingModel.pipelineGroup] for why this is not the string's own
        // hashCode: that is not stable between runs, and an unstable sort key
        // is an unstable picture.
        final pipeline = material.lighting.pipelineGroup;
        final materialId = materialIds.idOf(material, limit: 0x7FFF) & 0x7FFF;
        // Depth is the least significant term here and only serves early-z, so
        // 14 bits of range is ample even though it saturates past 256 units.
        return bucket * _b35 +
            pipeline * _b29 +
            materialId * _b14 +
            _quantize(item.viewDepth, 64.0, _b14 - 1, invert: false);

      case SortMode.frontToBack:
        return bucket * _b35 +
            _quantize(item.viewDepth, 1024.0, _b35 - 1, invert: false);

      case SortMode.backToFront:
        return bucket * _b35 +
            _quantize(item.viewDepth, 1024.0, _b35 - 1, invert: true);

      case SortMode.manual:
        return bucket * _b35;

      case SortMode.none:
        return 0;
    }
  }

  // Multiplied by a power of two rather than shifted, and added rather than
  // or-ed. Both look like the long way round and are the only portable one:
  // JavaScript's bitwise operators are 32-bit, so `bucket << 35` is not a wide
  // shift there, it is a wrong number — and `|` above 32 bits is wrong the same
  // way. The fields do not overlap by construction, so addition is exactly
  // or-ing, and the products are exact on both platforms because the whole key
  // is kSortKeyBits wide and that fits a double.
  //
  // Written as constants because `1 << 35` is itself the bug being avoided.
  static const int _b14 = 16384;
  static const int _b29 = 536870912;
  static const int _b35 = 34359738368;

  /// Quantizes a view depth into `[0, limit]`, optionally reversed for
  /// far-to-near.
  ///
  /// [limit] is one of the field widths above less one — a constant rather
  /// than a width turned into a power of two per call, which was a loop of
  /// thirty-five multiplications for every draw of every sort.
  ///
  /// A depth that is not finite — a node whose transform went to NaN — is
  /// clamped like any other rather than rounded: `double.round` refuses NaN
  /// and infinity, and one bad node would otherwise take the whole frame down
  /// in the sort. NaN lands at the near end, an infinity at its own end.
  int _quantize(double depth, double scale, int limit, {required bool invert}) {
    final product = depth * scale;
    final scaled = !product.isFinite
        ? (product == double.infinity ? limit : 0)
        : product.round().clamp(0, limit);
    return invert ? limit - scaled : scaled;
  }
}
