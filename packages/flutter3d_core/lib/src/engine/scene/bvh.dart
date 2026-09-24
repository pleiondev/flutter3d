import 'dart:typed_data';

import 'package:flutter3d_core/geometry.dart';
import 'package:vector_math/vector_math.dart' hide Ray;

/// A bounding volume hierarchy over bounding spheres.
///
/// Culling is linear today: 50 000 objects cost 0.73 ms, and 200 000 would cost
/// three. The answer to that is not a faster sphere test — it is to stop doing
/// most of them. A tree turns "test every object" into "test a few boxes and
/// then the handful inside them", which is a change in complexity rather than
/// in constant factor.
///
/// Deliberately a plain median-split binary tree in flat typed arrays. A SAH
/// build produces measurably better trees for ray tracing, where the same tree
/// is traversed millions of times; here it is rebuilt whenever the scene's
/// shape changes, so build time is on the frame's critical path and the split
/// heuristic is not where the win is.
///
/// The tree is over **world** bounds, so it goes stale whenever anything moves.
/// That is what the version stamp handed to [refresh] is for. A scene that
/// merely moved is refitted rather than rebuilt — see [refresh] — which is what
/// makes a tree affordable on a frame where things are animating at all, and it
/// is why the renderer's threshold for using one is 256 meshes rather than the
/// 2048 a rebuild-per-move forced.
///
/// It indexes spheres and yields indices, and knows nothing about scene nodes.
/// That is not abstraction for its own sake: `MeshNode` reaches the graphics backend
/// through its material, and a spatial index that dragged `dart:ui` in with it
/// could not be compiled ahead of time by `tool/bench/bench.dart` — which is
/// where its cost is actually measured. `sceneSpheres` does the mapping.
final class SceneBvh {
  /// Meshes per leaf. Small enough that a leaf test is cheap, large enough that
  /// the tree does not become mostly pointers.
  static const int leafSize = 4;

  /// Node bounds, six floats each: min xyz then max xyz.
  Float32List _bounds = Float32List(0);

  /// For an inner node, the index of its right child; the left child always
  /// follows the parent. For a leaf, -1 — which is also how a leaf is told
  /// apart from an inner node, now that both carry a count.
  Int32List _rightChild = Int32List(0);

  /// First entry in [_order] belonging to this node.
  Int32List _start = Int32List(0);

  /// How many entries the node's whole subtree holds, inner nodes included.
  ///
  /// It used to be zero for an inner node, which read as "a leaf has meshes and
  /// an inner node has children". Carrying the real figure is what lets a node
  /// the frustum fully contains emit its subtree as one range of [_order].
  Int32List _count = Int32List(0);

  /// Mesh indices, permuted so each node's meshes are contiguous.
  Int32List _order = Int32List(0);

  /// The spheres the tree is built over: centre xyz then radius, four floats
  /// each.
  ///
  /// Copied out of the meshes rather than read through them during the build.
  /// The build touches every element several times — once for bounds, once per
  /// partition level — and going through `worldBoundsCentre` each time means a
  /// version check and a possible eight-corner recompute per touch.
  Float32List _spheres = Float32List(0);

  int _nodeCount = 0;
  int _meshCount = 0;

  /// Checksum of the transform versions the tree was built from.
  int _versionStamp = 0;

  int _rebuilds = 0;
  int _refits = 0;

  /// Summed surface area of every node, as the build left it, and as the last
  /// refit found it. Their ratio is how far the tree has drifted — see
  /// [rebuildAbove].
  double _builtArea = 0.0;
  double _area = 0.0;

  /// Set by [invalidate], cleared by a build.
  bool _topologyStale = true;

  /// How far the summed node area may grow under refitting before the tree is
  /// rebuilt instead.
  ///
  /// The sum of every node's surface area is the standard proxy for what a
  /// hierarchy costs to traverse: a query reaches a node roughly in proportion
  /// to that node's area, so the sum is what the tree charges for an average
  /// query. A refit keeps the bounds honest and the partition fixed, so the
  /// figure can only rise, and it rises exactly when the objects a leaf holds
  /// have wandered apart from each other.
  ///
  /// Twice is deliberately loose. The point of refitting is that a scene where
  /// things move pays nothing, and a tight bound would hand most of those
  /// frames back to the rebuild it was meant to avoid; a tree costing twice
  /// what it did is still enormously better than the linear pass it replaced.
  static const double rebuildAbove = 2.0;

  int get nodeCount => _nodeCount;

  /// How many meshes are in the tree, as against [nodeCount] of tree nodes.
  ///
  /// The two together are what a profiler reads to judge the build: meshes per
  /// node falling towards one means the tree has stopped separating anything and
  /// is costing more than the loop it replaced. Nothing here reads either;
  /// [rebuildCount] is the one the engine's own tests watch.
  int get meshCount => _meshCount;

  /// How many times the tree has been rebuilt, so a scene that thrashes it is
  /// visible rather than merely slow.
  int get rebuildCount => _rebuilds;

  /// How many times the tree has been refitted instead — the cheap path, and
  /// the one a scene where things merely move should be taking every frame.
  int get refitCount => _refits;

  bool get isEmpty => _nodeCount == 0;

  /// Brings the tree up to date with [spheres] when [stamp] says they moved.
  ///
  /// [spheres] holds four floats per entry: centre xyz then radius. [stamp] is
  /// any value that changes when the contents do; the caller owns the question
  /// of what "changed" means, because only it knows whether a transform moved.
  ///
  /// **A moved scene refits; a changed one rebuilds — `gfx-62n`.** A rebuild
  /// partitions every object and costs 92 ms on 200 000 of them, which is not a
  /// price a frame can pay for one node turning. A refit keeps the partition
  /// and recomputes the boxes bottom up, which is one linear pass, and the
  /// answer stays exactly as correct: a node's box still encloses everything
  /// beneath it, which is the only thing a cull relies on. What goes is the
  /// tree's *quality*, and [rebuildAbove] is where that is caught.
  ///
  /// The condition for refitting is only that the count is unchanged, which
  /// looks too weak and is not. The partition is over index positions, not over
  /// identities: any assignment of `0..count - 1` to leaves is a valid tree, so
  /// a frame that swapped what index 7 refers to gets a correct answer from a
  /// refit as surely as one that only moved it. A scene that adds or removes a
  /// mesh changes the count, and that is the case the partition cannot absorb.
  void refresh(Float32List spheres, int count, int stamp) {
    if (stamp == _versionStamp && count == _meshCount && stamp != 0) return;
    _spheres = spheres;

    if (!_topologyStale && count == _meshCount && _nodeCount != 0) {
      _refit();
      _versionStamp = stamp;
      // Refitted and still a good tree, so that is the whole frame's cost.
      // Otherwise the pass is spent and the rebuild happens anyway: paying one
      // linear walk on the frame that rebuilds is cheaper than measuring drift
      // some other way, because there is no other way that does not walk it.
      if (_area <= _builtArea * rebuildAbove) return;
    }

    _build(count);
    _versionStamp = stamp;
  }

  /// Forces a full rebuild on the next [refresh], rather than the refit a scene
  /// that merely moved would get.
  void invalidate() {
    _versionStamp = 0;
    _topologyStale = true;
  }

  /// Recomputes every node's box from the current spheres, keeping the shape.
  ///
  /// Bottom up, and children rather than spheres: a leaf reads the spheres it
  /// holds, an inner node is the union of two boxes already computed, so the
  /// whole pass is linear in nodes rather than in nodes times depth. Walking
  /// the node array backwards is enough to get that order, because [_buildNode]
  /// never gives a child a lower number than its parent.
  void _refit() {
    _refits++;
    var area = 0.0;

    for (var node = _nodeCount - 1; node >= 0; node--) {
      final base = node * 6;
      final count = _count[node];

      if (_rightChild[node] < 0) {
        var minX = double.infinity,
            minY = double.infinity,
            minZ = double.infinity;
        var maxX = -double.infinity,
            maxY = -double.infinity,
            maxZ = -double.infinity;
        final start = _start[node];
        for (var i = start; i < start + count; i++) {
          final o = _order[i] * 4;
          final cx = _spheres[o], cy = _spheres[o + 1], cz = _spheres[o + 2];
          final radius = _spheres[o + 3];
          if (cx - radius < minX) minX = cx - radius;
          if (cy - radius < minY) minY = cy - radius;
          if (cz - radius < minZ) minZ = cz - radius;
          if (cx + radius > maxX) maxX = cx + radius;
          if (cy + radius > maxY) maxY = cy + radius;
          if (cz + radius > maxZ) maxZ = cz + radius;
        }
        _bounds[base] = minX;
        _bounds[base + 1] = minY;
        _bounds[base + 2] = minZ;
        _bounds[base + 3] = maxX;
        _bounds[base + 4] = maxY;
        _bounds[base + 5] = maxZ;
      } else {
        final left = (node + 1) * 6;
        final right = _rightChild[node] * 6;
        for (var axis = 0; axis < 3; axis++) {
          final low = _bounds[left + axis] < _bounds[right + axis]
              ? _bounds[left + axis]
              : _bounds[right + axis];
          final high = _bounds[left + axis + 3] > _bounds[right + axis + 3]
              ? _bounds[left + axis + 3]
              : _bounds[right + axis + 3];
          _bounds[base + axis] = low;
          _bounds[base + axis + 3] = high;
        }
      }

      area += _areaOf(base);
    }

    _area = area;
  }

  /// Surface area of the box at [base] in [_bounds].
  double _areaOf(int base) {
    final dx = _bounds[base + 3] - _bounds[base];
    final dy = _bounds[base + 4] - _bounds[base + 1];
    final dz = _bounds[base + 5] - _bounds[base + 2];
    return 2.0 * (dx * dy + dy * dz + dz * dx);
  }

  void _build(int count) {
    _rebuilds++;
    _meshCount = count;
    _topologyStale = false;

    if (count == 0) {
      _nodeCount = 0;
      _builtArea = 0.0;
      _area = 0.0;
      return;
    }

    // A binary tree whose leaves each hold at least one mesh has at most
    // 2n - 1 nodes. Sizing by n / leafSize looks tighter and is wrong: a median
    // split does not fill its leaves, so the real leaf count depends on how the
    // objects are distributed. Over-allocating once beats growing mid-build.
    final maxNodes = 2 * count + 2;
    if (_bounds.length < maxNodes * 6) {
      _bounds = Float32List(maxNodes * 6);
      _rightChild = Int32List(maxNodes);
      _start = Int32List(maxNodes);
      _count = Int32List(maxNodes);
    }
    if (_order.length < count) {
      _order = Int32List(count);
    }
    for (var i = 0; i < count; i++) {
      _order[i] = i;
    }

    _nodeCount = 0;
    _buildNode(0, count);

    // What the tree costs while it is still the tree the build meant, which is
    // the baseline every later refit is measured against.
    var area = 0.0;
    for (var node = 0; node < _nodeCount; node++) {
      area += _areaOf(node * 6);
    }
    _builtArea = area;
    _area = area;
  }

  /// Builds a node covering `_order[start, start + count)` and returns its index.
  int _buildNode(int start, int count) {
    final node = _nodeCount++;

    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = -double.infinity,
        maxY = -double.infinity,
        maxZ = -double.infinity;
    var centreMinX = double.infinity,
        centreMinY = double.infinity,
        centreMinZ = double.infinity;
    var centreMaxX = -double.infinity,
        centreMaxY = -double.infinity,
        centreMaxZ = -double.infinity;

    for (var i = start; i < start + count; i++) {
      final o = _order[i] * 4;
      final cx = _spheres[o], cy = _spheres[o + 1], cz = _spheres[o + 2];
      final radius = _spheres[o + 3];

      if (cx - radius < minX) minX = cx - radius;
      if (cy - radius < minY) minY = cy - radius;
      if (cz - radius < minZ) minZ = cz - radius;
      if (cx + radius > maxX) maxX = cx + radius;
      if (cy + radius > maxY) maxY = cy + radius;
      if (cz + radius > maxZ) maxZ = cz + radius;

      if (cx < centreMinX) centreMinX = cx;
      if (cy < centreMinY) centreMinY = cy;
      if (cz < centreMinZ) centreMinZ = cz;
      if (cx > centreMaxX) centreMaxX = cx;
      if (cy > centreMaxY) centreMaxY = cy;
      if (cz > centreMaxZ) centreMaxZ = cz;
    }

    final base = node * 6;
    _bounds[base] = minX;
    _bounds[base + 1] = minY;
    _bounds[base + 2] = minZ;
    _bounds[base + 3] = maxX;
    _bounds[base + 4] = maxY;
    _bounds[base + 5] = maxZ;
    _start[node] = start;

    if (count <= leafSize) {
      _count[node] = count;
      _rightChild[node] = -1;
      return node;
    }

    // Split along the axis the centroids spread over most: splitting a thin
    // axis leaves both children covering nearly the parent's volume, which is
    // a tree that costs memory and rejects nothing.
    final spanX = centreMaxX - centreMinX;
    final spanY = centreMaxY - centreMinY;
    final spanZ = centreMaxZ - centreMinZ;
    final axis = spanX >= spanY && spanX >= spanZ
        ? 0
        : (spanY >= spanZ ? 1 : 2);

    double centreOf(int index) => _spheres[index * 4 + axis];

    final mid = start + count ~/ 2;
    _nthElement(mid, start, start + count, centreOf);

    // Every centroid identical — a pile of objects at one point. Splitting by
    // position cannot separate them, so fall back to splitting by count, which
    // at least keeps the tree balanced.
    //
    // The count an inner node carries is its whole subtree's, not zero, which
    // is what lets a node the frustum fully contains hand over its meshes as
    // one flat range of `_order` — see [queryFrustum].
    _count[node] = count;
    _buildNode(start, mid - start);
    _rightChild[node] = _buildNode(mid, start + count - mid);
    return node;
  }

  /// Partial sort: after this, `_order[nth]` holds the element it would hold in
  /// a fully sorted range, and everything before it compares no greater.
  ///
  /// Quickselect rather than a full sort, because a median split only needs the
  /// middle element to be in place — sorting the rest is work the build throws
  /// away.
  void _nthElement(int nth, int from, int to, double Function(int) key) {
    var low = from;
    var high = to - 1;

    while (low < high) {
      final pivot = key(_order[(low + high) >> 1]);
      var i = low;
      var j = high;
      while (i <= j) {
        while (key(_order[i]) < pivot) {
          i++;
        }
        while (key(_order[j]) > pivot) {
          j--;
        }
        if (i <= j) {
          final swap = _order[i];
          _order[i] = _order[j];
          _order[j] = swap;
          i++;
          j--;
        }
      }
      if (nth <= j) {
        high = j;
      } else if (nth >= i) {
        low = i;
      } else {
        return;
      }
    }
  }

  /// Visits every mesh whose bounds may intersect [frustum].
  ///
  /// "May" is the point: the tree rejects whole subtrees, and the leaves still
  /// get the same sphere test the linear path applies, so the visible set is
  /// identical either way.
  ///
  /// **A node the frustum fully contains stops being a tree — `gfx-62n`.** Its
  /// whole subtree is one contiguous run of [_order], so it is handed over as a
  /// flat loop with no descent and no further box tests. That is the answer to
  /// the tree's one bad case: with the camera holding the entire scene it used
  /// to pay traversal for nothing, losing to the plain loop by two thirds at
  /// 50 000 meshes. Now it tests the root, finds it inside, and walks an array.
  void queryFrustum(
    Frustum frustum,
    void Function(int index) visit, {
    Aabb3? scratch,
  }) => _queryFrustum(frustum, null, visit, scratch);

  /// [queryFrustum], with [accepts] asked of every tree node the frustum
  /// keeps — `C2`. A node it refuses is rejected with everything under it,
  /// which is how an occlusion test takes out a whole block of a city in one
  /// question rather than a question per building.
  ///
  /// [accepts] is handed the node's box, a scratch object reused for the
  /// next node, so it must not keep it. Refusing is a promise about every
  /// mesh under the box, and the meshes it lets through still get the same
  /// tests they would have had. The shortcut for a node the frustum fully
  /// contains is not taken here, since being in view is not being seen.
  void queryFrustumWhere(
    Frustum frustum,
    bool Function(Aabb3 box) accepts,
    void Function(int index) visit, {
    Aabb3? scratch,
  }) => _queryFrustum(frustum, accepts, visit, scratch);

  void _queryFrustum(
    Frustum frustum,
    bool Function(Aabb3 box)? accepts,
    void Function(int index) visit,
    Aabb3? scratch,
  ) {
    if (_nodeCount == 0) return;
    final box = scratch ?? Aabb3();
    _visit(0, (node) {
      final base = node * 6;
      box.min.setValues(_bounds[base], _bounds[base + 1], _bounds[base + 2]);
      box.max.setValues(
        _bounds[base + 3],
        _bounds[base + 4],
        _bounds[base + 5],
      );
      if (!frustum.intersectsWithAabb3(box)) return _rejected;
      if (accepts == null) {
        return _containsBox(frustum, box) ? _contained : _straddles;
      }
      // With a test beside the frustum, containment says nothing about the
      // children: a block wholly in view may still be half hidden. So the
      // descent goes on, and each node gets its own answer.
      return accepts(box) ? _straddles : _rejected;
    }, visit);
  }

  static const int _rejected = 0;
  static const int _straddles = 1;
  static const int _contained = 2;

  /// Whether [box] lies entirely on the inside of every plane of [frustum].
  ///
  /// Checks the corner nearest each plane's back: if the corner that minimises
  /// the signed distance is still in front, every other corner is too. That is
  /// six dot products against one corner apiece, rather than thirty-six.
  static bool _containsBox(Frustum frustum, Aabb3 box) {
    for (var i = 0; i < 6; i++) {
      final plane = switch (i) {
        0 => frustum.plane0,
        1 => frustum.plane1,
        2 => frustum.plane2,
        3 => frustum.plane3,
        4 => frustum.plane4,
        _ => frustum.plane5,
      };
      final normal = plane.normal;
      final x = normal.x > 0.0 ? box.min.x : box.max.x;
      final y = normal.y > 0.0 ? box.min.y : box.max.y;
      final z = normal.z > 0.0 ? box.min.z : box.max.z;
      if (normal.x * x + normal.y * y + normal.z * z + plane.constant < 0.0) {
        return false;
      }
    }
    return true;
  }

  /// Visits every mesh whose bounds the ray may enter.
  void queryRay(
    Ray ray,
    void Function(int index) visit, {
    double maxDistance = double.infinity,
    Aabb3? scratch,
  }) {
    if (_nodeCount == 0) return;
    final box = scratch ?? Aabb3();
    _visit(0, (node) {
      final base = node * 6;
      box.min.setValues(_bounds[base], _bounds[base + 1], _bounds[base + 2]);
      box.max.setValues(
        _bounds[base + 3],
        _bounds[base + 4],
        _bounds[base + 5],
      );
      final distance = rayAabb(ray, box);
      // A ray has no use for containment: it enters the box or it does not, and
      // everything in a box it enters still has to be tested one at a time.
      return distance != kNoHit && distance <= maxDistance
          ? _straddles
          : _rejected;
    }, visit);
  }

  /// Depth-first descent with an explicit stack.
  ///
  /// Explicit rather than recursive so a degenerate tree — everything at one
  /// point, which builds a maximally deep chain — cannot overflow the stack
  /// during a frame.
  ///
  /// [accepts] answers [_rejected], [_straddles] or [_contained]; the last
  /// skips the rest of the descent and emits the subtree as a range.
  void _visit(
    int root,
    int Function(int node) accepts,
    void Function(int index) visit,
  ) {
    final stack = <int>[root];
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      final verdict = accepts(node);
      if (verdict == _rejected) continue;

      final isLeaf = _rightChild[node] < 0;
      if (isLeaf || verdict == _contained) {
        final start = _start[node];
        final end = start + _count[node];
        for (var i = start; i < end; i++) {
          visit(_order[i]);
        }
        continue;
      }

      stack.add(node + 1);
      final right = _rightChild[node];
      if (right > 0) stack.add(right);
    }
  }

  @override
  String toString() =>
      'SceneBvh($_nodeCount nodes over $_meshCount spheres, $_rebuilds '
      'rebuilds, $_refits refits)';
}
