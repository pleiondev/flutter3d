import 'dart:typed_data';

import 'package:vector_math/vector_math.dart' hide Ray;

import 'intersections.dart';
import 'mesh_data.dart';
import 'vertex_layout.dart';

/// A bounding-volume hierarchy over the triangles of one mesh.
///
/// **What it is for, and why the scene's own BVH is not it.** `SceneBvh` bounds
/// *nodes* with spheres, which is the right question for culling a scene and
/// the wrong one for a modeller: clicking a face means finding which of two
/// hundred thousand triangles a ray hits, and a sphere around the whole mesh
/// answers "this one" every time. So this indexes the triangles themselves,
/// and a click becomes a walk of a tree rather than a scan of an array.
///
/// **Arrays, not nodes.** Every field is a typed array indexed by node number:
/// a tree of objects for a mesh this size is a hundred thousand allocations
/// that a garbage collector then walks on every frame that allocates anything
/// else. Left and right children are `2i + 1` and `2i + 2` in spirit but stored
/// explicitly, because the tree is not complete.
///
/// Built by the median split along the widest axis, which is the cheapest build
/// that gives a usable tree — the surface-area heuristic buys perhaps a third
/// on query time for several times the build, and a modeller rebuilds after
/// every topological edit. [refit] is the answer for the other case: moving
/// vertices without changing the topology, where the tree's *shape* is still
/// right and only the boxes have moved.
final class TriangleBvh {
  TriangleBvh._(
    this._min,
    this._max,
    this._left,
    this._start,
    this._count,
    this._order,
    this._centroids,
    this.positions,
    this.indices,
  );

  /// Builds a tree over [mesh]'s triangles.
  ///
  /// [leafSize] is how many triangles a leaf may hold before it splits. Four is
  /// measured rather than assumed: below it the tree is deeper than the scan it
  /// saves, above it a leaf costs more than a level.
  factory TriangleBvh.fromMesh(MeshData mesh, {int leafSize = 4}) {
    final offset = mesh.layout.floatOffsetOf(VertexLayout.position.name);
    final stride = mesh.layout.floatsPerVertex;
    final positions = Float32List(mesh.vertexCount * 3);
    for (var i = 0; i < mesh.vertexCount; i++) {
      positions[i * 3] = mesh.vertices[i * stride + offset];
      positions[i * 3 + 1] = mesh.vertices[i * stride + offset + 1];
      positions[i * 3 + 2] = mesh.vertices[i * stride + offset + 2];
    }
    return TriangleBvh.fromArrays(
      positions,
      Uint32List.fromList(mesh.indices),
      leafSize: leafSize,
    );
  }

  /// Builds a tree over triangles given as positions and indices.
  ///
  /// The form an editable mesh hands over: `mesh-20` builds one of these from a
  /// layout plan without going through `MeshData` at all.
  factory TriangleBvh.fromArrays(
    Float32List positions,
    Uint32List indices, {
    int leafSize = 4,
  }) {
    final triangles = indices.length ~/ 3;
    // A tree over n leaves of at most `leafSize` has fewer than 2 * n / leafSize
    // internal nodes; the bound is generous because a median split can be
    // uneven when many centroids coincide.
    final capacity = triangles == 0 ? 1 : 4 * (triangles ~/ leafSize + 1);

    // Centroids by axis, computed once. Three arrays rather than one of
    // vectors: the split reads one axis at a time, and a `Vector3` per triangle
    // is a million allocations on the mesh this is sized for.
    final centroids = <Float32List>[
      Float32List(triangles),
      Float32List(triangles),
      Float32List(triangles),
    ];
    for (var triangle = 0; triangle < triangles; triangle++) {
      final base = triangle * 3;
      final a = indices[base] * 3;
      final b = indices[base + 1] * 3;
      final c = indices[base + 2] * 3;
      for (var axis = 0; axis < 3; axis++) {
        centroids[axis][triangle] =
            (positions[a + axis] + positions[b + axis] + positions[c + axis]) /
            3.0;
      }
    }

    final bvh = TriangleBvh._(
      Float32List(capacity * 3),
      Float32List(capacity * 3),
      Int32List(capacity)..fillRange(0, capacity, -1),
      Int32List(capacity),
      Int32List(capacity),
      Int32List(triangles),
      centroids,
      positions,
      indices,
    );
    for (var i = 0; i < triangles; i++) {
      bvh._order[i] = i;
    }
    if (triangles > 0) bvh._build(0, 0, triangles, leafSize);
    return bvh;
  }

  /// Vertex positions, three floats each. Held rather than copied: [refit] is
  /// what a caller runs after moving them in place.
  final Float32List positions;

  /// Triangle indices into [positions].
  final Uint32List indices;

  final Float32List _min;
  final Float32List _max;

  /// The left child of a node, or −1 where the node is a leaf.
  final Int32List _left;

  /// For a leaf, where its triangles start in [_order] and how many there are.
  final Int32List _start;
  final Int32List _count;

  /// Triangle numbers, permuted so a leaf's triangles are contiguous.
  final Int32List _order;

  /// Triangle centroids, one array per axis, indexed by triangle number.
  ///
  /// Kept rather than recomputed because a rebuild after an edit reads them
  /// again — and dropped from a refit, which does not split anything.
  final List<Float32List> _centroids;

  int _nodes = 0;

  /// How many nodes the tree holds, which is what a test compares builds with.
  int get nodeCount => _nodes;

  void _build(int node, int start, int end, int leafSize) {
    _nodes = node + 1 > _nodes ? node + 1 : _nodes;
    _start[node] = start;
    _count[node] = end - start;
    _left[node] = -1;

    if (end - start <= leafSize) {
      _boundsOf(node, start, end);
      return;
    }

    // **The axis comes from the centroids, not from the triangle box.** Both
    // answer "which way does this node spread", and one of them costs three
    // floats per triangle where the other costs nine — and the triangle box is
    // then computed a second time anyway, from the children, once they exist.
    // Building a tree over a million triangles spent most of its time in that
    // duplicate pass.
    var axis = 0;
    var widest = -1.0;
    for (var candidate = 0; candidate < 3; candidate++) {
      final centroids = _centroids[candidate];
      var low = double.infinity;
      var high = double.negativeInfinity;
      for (var i = start; i < end; i++) {
        final value = centroids[_order[i]];
        if (value < low) low = value;
        if (value > high) high = value;
      }
      final extent = high - low;
      if (extent > widest) {
        widest = extent;
        axis = candidate;
      }
    }

    final middle = start + (end - start) ~/ 2;
    _partitionAtMedian(start, end, axis);

    final left = _nodes;
    final right = _nodes + 1;
    _nodes += 2;
    _left[node] = left;
    _build(left, start, middle, leafSize);
    _build(right, middle, end, leafSize);
    // The union of the two children, which is exactly the box over these
    // triangles and costs two boxes rather than another pass over them.
    for (var i = 0; i < 3; i++) {
      _min[node * 3 + i] = _min[left * 3 + i] < _min[right * 3 + i]
          ? _min[left * 3 + i]
          : _min[right * 3 + i];
      _max[node * 3 + i] = _max[left * 3 + i] > _max[right * 3 + i]
          ? _max[left * 3 + i]
          : _max[right * 3 + i];
    }
  }

  /// Partitions `_order[start..end)` about its median along [axis].
  ///
  /// **Quickselect, not a sort, and the difference was measured.** Sorting each
  /// node's range with a comparator that recomputed centroids cost three
  /// seconds to build a tree over a million triangles — `p0-10`'s threshold is
  /// a hundred milliseconds. Only the median is needed, so the range is
  /// partitioned around it in linear time and the halves are left unordered,
  /// which is all a median split ever asked for. The centroids are computed
  /// once, in [_centroids], rather than three times per comparison.
  void _partitionAtMedian(int start, int end, int axis) {
    final centroids = _centroids[axis];
    final middle = start + (end - start) ~/ 2;

    var low = start;
    var high = end - 1;
    while (low < high) {
      // Hoare's partition about the value in the middle of the range, which
      // behaves on the sorted and reversed inputs a lattice actually produces.
      final pivot = centroids[_order[(low + high) ~/ 2]];
      var i = low;
      var j = high;
      while (i <= j) {
        while (centroids[_order[i]] < pivot) {
          i++;
        }
        while (centroids[_order[j]] > pivot) {
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
      // Only the half the median is in needs partitioning again.
      if (middle <= j) {
        high = j;
      } else if (middle >= i) {
        low = i;
      } else {
        break;
      }
    }
  }

  void _boundsOf(int node, int start, int end) {
    var minX = double.infinity;
    var minY = double.infinity;
    var minZ = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    var maxZ = double.negativeInfinity;
    for (var i = start; i < end; i++) {
      final base = _order[i] * 3;
      for (var corner = 0; corner < 3; corner++) {
        final vertex = indices[base + corner] * 3;
        final x = positions[vertex];
        final y = positions[vertex + 1];
        final z = positions[vertex + 2];
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (z < minZ) minZ = z;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
        if (z > maxZ) maxZ = z;
      }
    }
    _min[node * 3] = minX;
    _min[node * 3 + 1] = minY;
    _min[node * 3 + 2] = minZ;
    _max[node * 3] = maxX;
    _max[node * 3 + 1] = maxY;
    _max[node * 3 + 2] = maxZ;
  }

  /// Recomputes every box from the current [positions], keeping the tree's
  /// shape.
  ///
  /// **The operation that makes this usable while somebody is dragging.** A
  /// rebuild sorts every triangle; a refit walks the nodes once. The shape goes
  /// stale — vertices that moved far apart leave a tree that overlaps itself
  /// and queries slow down — which is the trade: refit inside a drag, rebuild
  /// when it ends or when the topology changes.
  void refit() {
    // **Bottom up, and children rather than triangles.** Recomputing every
    // node from its own triangles walks each triangle once per level of the
    // tree — forty milliseconds on 200 000, against a threshold of five. A leaf
    // reads its triangles; an internal node is the union of two boxes it has
    // already got, which makes the whole pass linear in the nodes.
    //
    // Backwards over the node array is enough to get the order right: `_build`
    // never gives a child a lower number than its parent.
    for (var node = _nodes - 1; node >= 0; node--) {
      final left = _left[node];
      if (left < 0) {
        _boundsOf(node, _start[node], _start[node] + _count[node]);
        continue;
      }
      final right = left + 1;
      for (var axis = 0; axis < 3; axis++) {
        final low = _min[left * 3 + axis] < _min[right * 3 + axis]
            ? _min[left * 3 + axis]
            : _min[right * 3 + axis];
        final high = _max[left * 3 + axis] > _max[right * 3 + axis]
            ? _max[left * 3 + axis]
            : _max[right * 3 + axis];
        _min[node * 3 + axis] = low;
        _max[node * 3 + axis] = high;
      }
    }
  }

  /// The nearest triangle [ray] hits, or null.
  ///
  /// Returns the triangle's number in the mesh's own index order — what a
  /// caller maps back to a face — with the distance and the point.
  ({int triangle, double distance, Vector3 point})? raycast(
    Ray ray, {
    double maxDistance = double.infinity,
  }) {
    if (_nodes == 0) return null;

    var bestDistance = maxDistance;
    var bestTriangle = -1;

    // An explicit stack, because a modeller's mesh is deep enough that
    // recursion here shows up in a profile and, on the web, in a stack limit.
    final stack = Int32List(64);
    var depth = 0;
    stack[depth++] = 0;

    while (depth > 0) {
      final node = stack[--depth];
      if (!_hitsBox(node, ray, bestDistance)) continue;

      final left = _left[node];
      if (left < 0) {
        final start = _start[node];
        final end = start + _count[node];
        for (var i = start; i < end; i++) {
          final triangle = _order[i];
          final base = triangle * 3;
          // `rayTriangle` answers a distance or a negative number, which is
          // the shape the engine's own raycaster reads it in.
          final hit = rayTriangle(
            ray,
            _vertex(indices[base]),
            _vertex(indices[base + 1]),
            _vertex(indices[base + 2]),
          );
          if (hit >= 0 && hit < bestDistance) {
            bestDistance = hit;
            bestTriangle = triangle;
          }
        }
        continue;
      }

      if (depth + 2 > stack.length) {
        throw StateError('the tree is deeper than the stack this walk carries');
      }
      stack[depth++] = left;
      stack[depth++] = left + 1;
    }

    if (bestTriangle < 0) return null;
    return (
      triangle: bestTriangle,
      distance: bestDistance,
      point: ray.origin + ray.direction * bestDistance,
    );
  }

  Vector3 _vertex(int index) => Vector3(
    positions[index * 3],
    positions[index * 3 + 1],
    positions[index * 3 + 2],
  );

  /// Slab test against a node's box, rejecting anything past [maxDistance].
  bool _hitsBox(int node, Ray ray, double maxDistance) {
    var near = 0.0;
    var far = maxDistance;
    for (var axis = 0; axis < 3; axis++) {
      final origin = ray.origin[axis];
      final direction = ray.direction[axis];
      final low = _min[node * 3 + axis];
      final high = _max[node * 3 + axis];
      if (direction.abs() < 1e-12) {
        // Parallel to this slab: inside it or nowhere.
        if (origin < low || origin > high) return false;
        continue;
      }
      final inverse = 1.0 / direction;
      var t0 = (low - origin) * inverse;
      var t1 = (high - origin) * inverse;
      if (t0 > t1) {
        final swap = t0;
        t0 = t1;
        t1 = swap;
      }
      if (t0 > near) near = t0;
      if (t1 < far) far = t1;
      if (near > far) return false;
    }
    return true;
  }
}
