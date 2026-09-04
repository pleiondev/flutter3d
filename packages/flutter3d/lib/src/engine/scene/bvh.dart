import 'dart:typed_data';

import 'package:vector_math/vector_math.dart' hide Ray;

import '../math/intersections.dart';

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
/// is traversed millions of times; here it is rebuilt whenever the scene moves,
/// so build time is on the frame's critical path and the split heuristic is not
/// where the win is.
///
/// The tree is over **world** bounds, so it goes stale whenever anything moves.
/// That is what the version stamp handed to [refresh] is for, and it is why the
/// renderer only uses the tree above a threshold: for a handful of objects the
/// rebuild costs more than the culling it saves.
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
  /// follows the parent. For a leaf, -1.
  Int32List _rightChild = Int32List(0);

  /// First entry in [_order] belonging to this node.
  Int32List _start = Int32List(0);

  /// How many entries; zero for an inner node.
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

  bool get isEmpty => _nodeCount == 0;

  /// Rebuilds the tree when [stamp] differs from what it was built from.
  ///
  /// [spheres] holds four floats per entry: centre xyz then radius. [stamp] is
  /// any value that changes when the contents do; the caller owns the question
  /// of what "changed" means, because only it knows whether a transform moved.
  void refresh(Float32List spheres, int count, int stamp) {
    if (stamp == _versionStamp && count == _meshCount && stamp != 0) return;
    _spheres = spheres;
    _build(count);
    _versionStamp = stamp;
  }

  /// Forces a rebuild on the next [refresh].
  void invalidate() => _versionStamp = 0;

  void _build(int count) {
    _rebuilds++;
    _meshCount = count;

    if (count == 0) {
      _nodeCount = 0;
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
    _count[node] = 0;
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
  void queryFrustum(
    Frustum frustum,
    void Function(int index) visit, {
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
      return frustum.intersectsWithAabb3(box);
    }, visit);
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
      return distance != kNoHit && distance <= maxDistance;
    }, visit);
  }

  /// Depth-first descent with an explicit stack.
  ///
  /// Explicit rather than recursive so a degenerate tree — everything at one
  /// point, which builds a maximally deep chain — cannot overflow the stack
  /// during a frame.
  void _visit(
    int root,
    bool Function(int node) accepts,
    void Function(int index) visit,
  ) {
    final stack = <int>[root];
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      if (!accepts(node)) continue;

      final count = _count[node];
      if (count > 0) {
        final start = _start[node];
        for (var i = start; i < start + count; i++) {
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
      'rebuilds)';
}
