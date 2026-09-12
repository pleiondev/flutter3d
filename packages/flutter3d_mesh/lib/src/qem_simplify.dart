/// Quadric-error-metric edge collapse — Garland–Heckbert — over `MeshData`.
/// `pro-lod-01`'s own row, absorbing `mesh-70`.
///
/// **Operates on `MeshData` directly, not `EditMesh`.** An LOD generator reads
/// a finished mesh and writes a smaller one; it has no need of `EditMesh`'s
/// selections, undo journal or per-operation invariants, and building one for
/// a 200,000-triangle mesh only to throw it away after one pass would be pure
/// overhead. The output carries positions only ([VertexLayout.positionOnly]):
/// blending normals, UVs and skin weights through a collapse is real work a
/// later row can add: this one simplifies shape, and a caller regenerates
/// attributes on the result the same way it would on any other mesh.
///
/// **No `Job` here — a plain callback instead.** The plan's own `Job<T>`
/// (`pro-job-01`) lives at `apps/flutter3d_modeler/lib/src/job_runner.dart`,
/// an application-layer type `flutter3d_mesh` cannot import — this package
/// sits *under* the app, not above it. [simplifyMesh] instead takes
/// [onProgress] (called every 1000 collapses, the row's own batch size) and
/// [isCancelled] (polled at the same cadence), a dependency-free surface the
/// app's own `Job` can wrap without this package ever knowing `Job` exists —
/// the same boundary call `anim-15`, `anim-20` and `anim-10` already made for
/// the engine's `Pose`/`MorphSink`/`SkinBlend`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:vector_math/vector_math.dart';

/// [mesh] reduced to at most [targetTriangleCount] triangles by repeated
/// least-error edge collapse.
///
/// Returns [mesh] unchanged when it already has [targetTriangleCount] or
/// fewer triangles — asking for more detail than there is should cost
/// nothing rather than degrade something.
///
/// [flipThreshold] rejects a collapse that would turn any triangle still
/// touching the merged vertex more than roughly this far from its own
/// original facing — `0.0` (a right angle) is the standard Garland–Heckbert
/// safeguard against a collapse folding the surface back on itself.
///
/// [onProgress] is called every 1000 collapses with the number done and an
/// upper-bound estimate of how many are needed — the triangle-count gap
/// itself, which overstates the true figure by roughly two (each collapse
/// ordinarily removes two triangles, not one), close enough for a progress
/// bar without pretending to know the exact count before the run finishes.
/// [isCancelled], polled at the same cadence, stops the pass early and
/// returns whatever has been simplified so far — still a valid mesh, just
/// not yet at [targetTriangleCount].
MeshData simplifyMesh(
  MeshData mesh, {
  required int targetTriangleCount,
  double flipThreshold = 0.0,
  void Function(int collapsesDone, int collapsesTotal)? onProgress,
  bool Function()? isCancelled,
}) {
  if (mesh.triangleCount <= targetTriangleCount) return mesh;

  final simplifier = _Simplifier.fromMesh(mesh);
  simplifier.run(
    targetTriangleCount: targetTriangleCount,
    flipThreshold: flipThreshold,
    onProgress: onProgress,
    isCancelled: isCancelled,
  );
  return simplifier.toMeshData();
}

/// One vertex's error quadric, the 10 unique entries of the symmetric 4×4
/// matrix `sum(planeᵀ · plane)` over every triangle touching it — stored flat
/// rather than as `Matrix4` because a `Float64List` of these is one
/// allocation for the whole mesh where an object per vertex would be
/// thousands.
///
/// Order: `a2, ab, ac, ad, b2, bc, bd, c2, cd, dd` for a plane `[a, b, c, d]`
/// with `ax + by + cz + d = 0`.
const int _quadricSize = 10;

class _Simplifier {
  _Simplifier._(
    this._positions,
    this._triangles,
    this._triangleAlive,
    this._vertexAlive,
    this._vertexVersion,
    this._quadrics,
    this._vertexTriangles,
  );

  factory _Simplifier.fromMesh(MeshData mesh) {
    final offset = mesh.layout.floatOffsetOf(VertexLayout.position.name);
    final stride = mesh.layout.floatsPerVertex;
    final vertexCount = mesh.vertexCount;
    final positions = Float64List(vertexCount * 3);
    for (var i = 0; i < vertexCount; i++) {
      positions[i * 3] = mesh.vertices[i * stride + offset];
      positions[i * 3 + 1] = mesh.vertices[i * stride + offset + 1];
      positions[i * 3 + 2] = mesh.vertices[i * stride + offset + 2];
    }
    final triangles = Int32List.fromList(mesh.indices);
    final triangleCount = triangles.length ~/ 3;

    final canonical = _weldCoincidentVertices(positions);
    for (var i = 0; i < triangles.length; i++) {
      triangles[i] = canonical[triangles[i]];
    }

    final triangleAlive = Uint8List(triangleCount);
    final vertexAlive = Uint8List(vertexCount);
    final vertexVersion = Int32List(vertexCount);
    final vertexTriangles = List<Set<int>>.generate(vertexCount, (_) => <int>{});
    for (var t = 0; t < triangleCount; t++) {
      final i0 = triangles[t * 3], i1 = triangles[t * 3 + 1], i2 = triangles[t * 3 + 2];
      // A triangle that straddled a welded seam on all three corners, or lost
      // a corner to it, is degenerate now and was never real geometry — drop
      // it the same way any other zero-area triangle is dropped.
      if (i0 == i1 || i1 == i2 || i0 == i2) continue;
      triangleAlive[t] = 1;
      vertexAlive[i0] = 1;
      vertexAlive[i1] = 1;
      vertexAlive[i2] = 1;
      vertexTriangles[i0].add(t);
      vertexTriangles[i1].add(t);
      vertexTriangles[i2].add(t);
    }

    final quadrics = Float64List(vertexCount * _quadricSize);
    for (var t = 0; t < triangleCount; t++) {
      _accumulatePlaneQuadric(positions, triangles, t, quadrics);
    }

    return _Simplifier._(
      positions,
      triangles,
      triangleAlive,
      vertexAlive,
      vertexVersion,
      quadrics,
      vertexTriangles,
    );
  }

  /// One representative index per position, for every vertex that shares it —
  /// most vertices are their own representative.
  ///
  /// **Why this has to happen before anything else.** A shape built by
  /// revolving a profile — a sphere among them — seams where the wrap closes:
  /// the first and last column of vertices sit at the same point but are
  /// different indices, since they carried different UVs. This algorithm
  /// only ever asked `MeshData` for positions and knows nothing about UV, so
  /// without this pass the seam reads as two free boundaries that happen to
  /// coincide rather than one interior edge — and a collapse near either
  /// boundary can walk it away from the other, opening a crack that the
  /// triangle-flip check does not exist to catch, since a widening seam is
  /// not a flipped normal. Welding first turns the seam
  /// into an ordinary shared edge, the same as everywhere else on the mesh.
  ///
  /// Grid-quantized rather than a full nearest-neighbour search: a seam's
  /// two sides are the same floating-point computation done twice, so they
  /// agree far closer than [epsilonScale] needs to assume, and a hash join
  /// costs one pass instead of a spatial tree.
  static Int32List _weldCoincidentVertices(Float64List positions, {double epsilonScale = 1e-5}) {
    final vertexCount = positions.length ~/ 3;
    final canonical = Int32List.fromList(List<int>.generate(vertexCount, (i) => i));
    if (vertexCount == 0) return canonical;

    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity, maxZ = -double.infinity;
    for (var i = 0; i < vertexCount; i++) {
      final x = positions[i * 3], y = positions[i * 3 + 1], z = positions[i * 3 + 2];
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (z < minZ) minZ = z;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
      if (z > maxZ) maxZ = z;
    }
    final diagonal = math.sqrt(
      (maxX - minX) * (maxX - minX) + (maxY - minY) * (maxY - minY) + (maxZ - minZ) * (maxZ - minZ),
    );
    final cellSize = math.max(diagonal * epsilonScale, 1e-12);

    int cellKeyOf(double x, double y, double z) {
      final gx = (x / cellSize).round();
      final gy = (y / cellSize).round();
      final gz = (z / cellSize).round();
      return Object.hash(gx, gy, gz);
    }

    final byCell = <int, List<int>>{};
    for (var i = 0; i < vertexCount; i++) {
      final key = cellKeyOf(positions[i * 3], positions[i * 3 + 1], positions[i * 3 + 2]);
      (byCell[key] ??= <int>[]).add(i);
    }

    for (final bucket in byCell.values) {
      if (bucket.length < 2) continue;
      for (var a = 0; a < bucket.length; a++) {
        final va = bucket[a];
        if (canonical[va] != va) continue; // Already welded onto an earlier one.
        for (var b = a + 1; b < bucket.length; b++) {
          final vb = bucket[b];
          if (canonical[vb] != vb) continue;
          final dx = positions[va * 3] - positions[vb * 3];
          final dy = positions[va * 3 + 1] - positions[vb * 3 + 1];
          final dz = positions[va * 3 + 2] - positions[vb * 3 + 2];
          if (dx * dx + dy * dy + dz * dz <= cellSize * cellSize) {
            canonical[vb] = va;
          }
        }
      }
    }
    return canonical;
  }

  final Float64List _positions;
  final Int32List _triangles;
  final Uint8List _triangleAlive;
  final Uint8List _vertexAlive;
  final Int32List _vertexVersion;
  final Float64List _quadrics;
  final List<Set<int>> _vertexTriangles;

  int get _vertexCount => _vertexAlive.length;

  static void _accumulatePlaneQuadric(
    Float64List positions,
    Int32List triangles,
    int triangle,
    Float64List quadrics,
  ) {
    final i0 = triangles[triangle * 3];
    final i1 = triangles[triangle * 3 + 1];
    final i2 = triangles[triangle * 3 + 2];
    final ax = positions[i0 * 3], ay = positions[i0 * 3 + 1], az = positions[i0 * 3 + 2];
    final bx = positions[i1 * 3], by = positions[i1 * 3 + 1], bz = positions[i1 * 3 + 2];
    final cx = positions[i2 * 3], cy = positions[i2 * 3 + 1], cz = positions[i2 * 3 + 2];

    final ux = bx - ax, uy = by - ay, uz = bz - az;
    final vx = cx - ax, vy = cy - ay, vz = cz - az;
    var nx = uy * vz - uz * vy;
    var ny = uz * vx - ux * vz;
    var nz = ux * vy - uy * vx;
    final length = math.sqrt(nx * nx + ny * ny + nz * nz);
    if (length < 1e-20) return; // A degenerate triangle contributes no plane.
    nx /= length;
    ny /= length;
    nz /= length;
    final d = -(nx * ax + ny * ay + nz * az);

    void addTo(int vertex) {
      final o = vertex * _quadricSize;
      quadrics[o + 0] += nx * nx;
      quadrics[o + 1] += nx * ny;
      quadrics[o + 2] += nx * nz;
      quadrics[o + 3] += nx * d;
      quadrics[o + 4] += ny * ny;
      quadrics[o + 5] += ny * nz;
      quadrics[o + 6] += ny * d;
      quadrics[o + 7] += nz * nz;
      quadrics[o + 8] += nz * d;
      quadrics[o + 9] += d * d;
    }

    addTo(i0);
    addTo(i1);
    addTo(i2);
  }

  /// The optimal collapse position for combined quadric [q] (10 entries at
  /// [offset]) and its cost there — solving the 3×3 linear system for the
  /// quadric's minimum, falling back to the better of [ax]/[bx]/midpoint when
  /// that system is too close to singular to trust.
  ({double x, double y, double z, double cost}) _solve(
    Float64List q,
    int offset,
    double ax,
    double ay,
    double az,
    double bx,
    double by,
    double bz,
  ) {
    final a2 = q[offset + 0], ab = q[offset + 1], ac = q[offset + 2], ad = q[offset + 3];
    final b2 = q[offset + 4], bc = q[offset + 5], bd = q[offset + 6];
    final c2 = q[offset + 7], cd = q[offset + 8], dd = q[offset + 9];

    double costAt(double x, double y, double z) =>
        a2 * x * x + b2 * y * y + c2 * z * z +
        2 * ab * x * y + 2 * ac * x * z + 2 * bc * y * z +
        2 * ad * x + 2 * bd * y + 2 * cd * z + dd;

    final det = a2 * (b2 * c2 - bc * bc) -
        ab * (ab * c2 - bc * ac) +
        ac * (ab * bc - b2 * ac);

    if (det.abs() > 1e-9) {
      final invDet = 1.0 / det;
      // Cramer's rule for A x = -[ad, bd, cd].
      final rx = -ad, ry = -bd, rz = -cd;
      final x = invDet *
          (rx * (b2 * c2 - bc * bc) - ab * (ry * c2 - bc * rz) + ac * (ry * bc - b2 * rz));
      final y = invDet *
          (a2 * (ry * c2 - bc * rz) - rx * (ab * c2 - bc * ac) + ac * (ab * rz - ry * ac));
      final z = invDet *
          (a2 * (b2 * rz - ry * bc) - ab * (ab * rz - ry * ac) + rx * (ab * bc - b2 * ac));
      return (x: x, y: y, z: z, cost: costAt(x, y, z));
    }

    final mx = (ax + bx) / 2, my = (ay + by) / 2, mz = (az + bz) / 2;
    final costA = costAt(ax, ay, az);
    final costB = costAt(bx, by, bz);
    final costM = costAt(mx, my, mz);
    if (costA <= costB && costA <= costM) return (x: ax, y: ay, z: az, cost: costA);
    if (costB <= costA && costB <= costM) return (x: bx, y: by, z: bz, cost: costB);
    return (x: mx, y: my, z: mz, cost: costM);
  }

  /// Every triangle touching [a] or [b] that survives their collapse — i.e.
  /// not one of the (at most two) triangles that has both as two of its three
  /// corners, which degenerate to a line and vanish instead.
  List<int> _survivingNeighborTriangles(int a, int b) {
    final result = <int>[];
    for (final t in _vertexTriangles[a]) {
      final i0 = _triangles[t * 3], i1 = _triangles[t * 3 + 1], i2 = _triangles[t * 3 + 2];
      final hasB = i0 == b || i1 == b || i2 == b;
      if (!hasB) result.add(t);
    }
    for (final t in _vertexTriangles[b]) {
      final i0 = _triangles[t * 3], i1 = _triangles[t * 3 + 1], i2 = _triangles[t * 3 + 2];
      final hasA = i0 == a || i1 == a || i2 == a;
      if (!hasA) result.add(t);
    }
    return result;
  }

  Vector3 _triangleNormal(int i0, int i1, int i2, {int? replace, Vector3? withPosition}) {
    Vector3 posOf(int i) {
      if (i == replace) return withPosition!;
      return Vector3(_positions[i * 3], _positions[i * 3 + 1], _positions[i * 3 + 2]);
    }

    final a = posOf(i0), b = posOf(i1), c = posOf(i2);
    return (b - a).cross(c - a);
  }

  /// Whether collapsing [from] into [to] at [target] leaves every triangle
  /// still touching [to] facing (within [flipThreshold]) the way it did
  /// before — the standard normal-flip guard against a collapse folding the
  /// surface back on itself.
  bool _wouldFlip(int from, int to, Vector3 target, double flipThreshold) {
    for (final t in _survivingNeighborTriangles(to, from)) {
      final i0 = _triangles[t * 3], i1 = _triangles[t * 3 + 1], i2 = _triangles[t * 3 + 2];
      final replaced = (i0 == to || i0 == from)
          ? i0
          : (i1 == to || i1 == from)
              ? i1
              : i2;
      final before = _triangleNormal(i0, i1, i2);
      final after = _triangleNormal(i0, i1, i2, replace: replaced, withPosition: target);
      final beforeLength = before.length;
      final afterLength = after.length;
      if (afterLength < 1e-20) return true; // Degenerates to a line or point.
      if (beforeLength < 1e-20) continue; // Was already degenerate; nothing to compare to.
      final cos = before.dot(after) / (beforeLength * afterLength);
      if (cos < flipThreshold) return true;
    }
    return false;
  }

  void run({
    required int targetTriangleCount,
    required double flipThreshold,
    void Function(int collapsesDone, int collapsesTotal)? onProgress,
    bool Function()? isCancelled,
  }) {
    var liveTriangleCount = _triangleAlive.fold<int>(0, (sum, alive) => sum + alive);
    final collapsesNeeded = liveTriangleCount - targetTriangleCount;
    if (collapsesNeeded <= 0) return;

    final heap = _EdgeHeap(math.max(64, _triangles.length));
    final seenEdges = <int>{};
    void offer(int a, int b) {
      if (a == b) return; // A welded-degenerate triangle's own dead edge.
      final lo = math.min(a, b), hi = math.max(a, b);
      final key = lo * _vertexCount + hi;
      if (!seenEdges.add(key)) return;
      _pushEdge(heap, lo, hi);
    }

    for (var t = 0; t < _triangleAlive.length; t++) {
      if (_triangleAlive[t] == 0) continue;
      offer(_triangles[t * 3], _triangles[t * 3 + 1]);
      offer(_triangles[t * 3 + 1], _triangles[t * 3 + 2]);
      offer(_triangles[t * 3 + 2], _triangles[t * 3]);
    }

    var collapsesDone = 0;
    while (liveTriangleCount > targetTriangleCount && !heap.isEmpty) {
      final entry = heap.pop();
      final a = entry.a, b = entry.b;
      if (_vertexAlive[a] == 0 ||
          _vertexAlive[b] == 0 ||
          _vertexVersion[a] != entry.verA ||
          _vertexVersion[b] != entry.verB) {
        continue; // Stale: one side changed since this entry was queued.
      }

      final target = Vector3(entry.tx, entry.ty, entry.tz);
      if (_wouldFlip(b, a, target, flipThreshold)) {
        continue; // Reject outright rather than requeue at another cost.
      }

      // b merges into a; a survives at the solved position.
      final removedTriangles = <int>[];
      for (final t in _vertexTriangles[a]) {
        final i0 = _triangles[t * 3], i1 = _triangles[t * 3 + 1], i2 = _triangles[t * 3 + 2];
        if (i0 == b || i1 == b || i2 == b) removedTriangles.add(t);
      }
      for (final t in removedTriangles) {
        _triangleAlive[t] = 0;
        _vertexTriangles[a].remove(t);
        _vertexTriangles[b].remove(t);
        final i0 = _triangles[t * 3], i1 = _triangles[t * 3 + 1], i2 = _triangles[t * 3 + 2];
        for (final v in [i0, i1, i2]) {
          if (v != a && v != b) _vertexTriangles[v].remove(t);
        }
        liveTriangleCount--;
      }

      for (final t in _vertexTriangles[b].toList()) {
        for (var k = 0; k < 3; k++) {
          if (_triangles[t * 3 + k] == b) _triangles[t * 3 + k] = a;
        }
        _vertexTriangles[a].add(t);
      }
      _vertexTriangles[b].clear();
      _vertexAlive[b] = 0;

      _positions[a * 3] = target.x;
      _positions[a * 3 + 1] = target.y;
      _positions[a * 3 + 2] = target.z;
      for (var k = 0; k < _quadricSize; k++) {
        _quadrics[a * _quadricSize + k] += _quadrics[b * _quadricSize + k];
      }
      _vertexVersion[a]++;

      final neighbors = <int>{};
      for (final t in _vertexTriangles[a]) {
        final i0 = _triangles[t * 3], i1 = _triangles[t * 3 + 1], i2 = _triangles[t * 3 + 2];
        if (i0 != a) neighbors.add(i0);
        if (i1 != a) neighbors.add(i1);
        if (i2 != a) neighbors.add(i2);
      }
      for (final n in neighbors) {
        _pushEdge(heap, math.min(a, n), math.max(a, n));
      }

      collapsesDone++;
      if (collapsesDone % 1000 == 0) {
        onProgress?.call(collapsesDone, collapsesNeeded);
        if (isCancelled?.call() ?? false) return;
      }
    }
    onProgress?.call(collapsesDone, collapsesNeeded);
  }

  void _pushEdge(_EdgeHeap heap, int a, int b) {
    final combined = Float64List(_quadricSize);
    for (var k = 0; k < _quadricSize; k++) {
      combined[k] = _quadrics[a * _quadricSize + k] + _quadrics[b * _quadricSize + k];
    }
    final solved = _solve(
      combined,
      0,
      _positions[a * 3],
      _positions[a * 3 + 1],
      _positions[a * 3 + 2],
      _positions[b * 3],
      _positions[b * 3 + 1],
      _positions[b * 3 + 2],
    );
    heap.push(
      solved.cost,
      a,
      b,
      _vertexVersion[a],
      _vertexVersion[b],
      solved.x,
      solved.y,
      solved.z,
    );
  }

  MeshData toMeshData() {
    final remap = Int32List(_vertexCount)..fillRange(0, _vertexCount, -1);
    var nextIndex = 0;
    for (var v = 0; v < _vertexCount; v++) {
      if (_vertexAlive[v] == 1) remap[v] = nextIndex++;
    }
    final vertices = Float32List(nextIndex * 3);
    for (var v = 0; v < _vertexCount; v++) {
      if (_vertexAlive[v] != 1) continue;
      final o = remap[v] * 3;
      vertices[o] = _positions[v * 3].toDouble();
      vertices[o + 1] = _positions[v * 3 + 1].toDouble();
      vertices[o + 2] = _positions[v * 3 + 2].toDouble();
    }

    final indices = <int>[];
    for (var t = 0; t < _triangleAlive.length; t++) {
      if (_triangleAlive[t] != 1) continue;
      indices.add(remap[_triangles[t * 3]]);
      indices.add(remap[_triangles[t * 3 + 1]]);
      indices.add(remap[_triangles[t * 3 + 2]]);
    }

    return MeshData(
      layout: VertexLayout.positionOnly,
      vertices: vertices,
      indices: Uint32List.fromList(indices),
    );
  }
}

/// A binary min-heap of candidate edge collapses, backed by typed arrays
/// rather than a heap of boxed records — the row's own "куча на
/// `Float64List`/`Int32List`". Stale entries (an endpoint already merged
/// away, or superseded by a fresher quadric) are left in place and
/// discarded when popped rather than hunted down and removed — the standard
/// lazy-deletion trade for an edge-collapse heap, where an entry invalidated
/// mid-run is the common case, not the exception.
class _EdgeHeap {
  _EdgeHeap(int initialCapacity)
      : _cost = Float64List(math.max(1, initialCapacity)),
        _a = Int32List(math.max(1, initialCapacity)),
        _b = Int32List(math.max(1, initialCapacity)),
        _verA = Int32List(math.max(1, initialCapacity)),
        _verB = Int32List(math.max(1, initialCapacity)),
        _tx = Float64List(math.max(1, initialCapacity)),
        _ty = Float64List(math.max(1, initialCapacity)),
        _tz = Float64List(math.max(1, initialCapacity));

  Float64List _cost;
  Int32List _a, _b, _verA, _verB;
  Float64List _tx, _ty, _tz;
  int _size = 0;

  bool get isEmpty => _size == 0;

  void _grow() {
    final newCapacity = _cost.length * 2;
    Float64List growF(Float64List old) => Float64List(newCapacity)..setRange(0, _size, old);
    Int32List growI(Int32List old) => Int32List(newCapacity)..setRange(0, _size, old);
    _cost = growF(_cost);
    _a = growI(_a);
    _b = growI(_b);
    _verA = growI(_verA);
    _verB = growI(_verB);
    _tx = growF(_tx);
    _ty = growF(_ty);
    _tz = growF(_tz);
  }

  void push(double cost, int a, int b, int verA, int verB, double tx, double ty, double tz) {
    if (_size == _cost.length) _grow();
    var i = _size++;
    _cost[i] = cost;
    _a[i] = a;
    _b[i] = b;
    _verA[i] = verA;
    _verB[i] = verB;
    _tx[i] = tx;
    _ty[i] = ty;
    _tz[i] = tz;
    while (i > 0) {
      final parent = (i - 1) >> 1;
      if (_cost[parent] <= _cost[i]) break;
      _swap(parent, i);
      i = parent;
    }
  }

  void _swap(int i, int j) {
    final tc = _cost[i];
    _cost[i] = _cost[j];
    _cost[j] = tc;
    final ta = _a[i];
    _a[i] = _a[j];
    _a[j] = ta;
    final tb = _b[i];
    _b[i] = _b[j];
    _b[j] = tb;
    final tva = _verA[i];
    _verA[i] = _verA[j];
    _verA[j] = tva;
    final tvb = _verB[i];
    _verB[i] = _verB[j];
    _verB[j] = tvb;
    final ttx = _tx[i];
    _tx[i] = _tx[j];
    _tx[j] = ttx;
    final tty = _ty[i];
    _ty[i] = _ty[j];
    _ty[j] = tty;
    final ttz = _tz[i];
    _tz[i] = _tz[j];
    _tz[j] = ttz;
  }

  ({double cost, int a, int b, int verA, int verB, double tx, double ty, double tz}) pop() {
    final result = (
      cost: _cost[0],
      a: _a[0],
      b: _b[0],
      verA: _verA[0],
      verB: _verB[0],
      tx: _tx[0],
      ty: _ty[0],
      tz: _tz[0],
    );
    _size--;
    if (_size > 0) {
      _cost[0] = _cost[_size];
      _a[0] = _a[_size];
      _b[0] = _b[_size];
      _verA[0] = _verA[_size];
      _verB[0] = _verB[_size];
      _tx[0] = _tx[_size];
      _ty[0] = _ty[_size];
      _tz[0] = _tz[_size];
      var i = 0;
      while (true) {
        final l = 2 * i + 1, r = 2 * i + 2;
        var smallest = i;
        if (l < _size && _cost[l] < _cost[smallest]) smallest = l;
        if (r < _size && _cost[r] < _cost[smallest]) smallest = r;
        if (smallest == i) break;
        _swap(i, smallest);
        i = smallest;
      }
    }
    return result;
  }
}
