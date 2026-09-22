/// Least Squares Conformal Maps UV unwrapping — `pro-uv-02`'s own row,
/// absorbing `mesh-71`.
///
/// **Two functions, one for topology and one for geometry.** [splitIslands]
/// answers "which faces are cut apart from which" by walking face adjacency
/// and refusing to cross a seam (`pro-uv-01`'s own `EdgeFlags.seam`) or a
/// mesh boundary; [lscm] answers "what UV does this one connected group of
/// faces get" by solving a linear system per island. Neither reaches for the
/// other — a caller with its own island (a plain selection, say) can call
/// [lscm] directly, the same freedom `projectUv` already gives.
///
/// **The linear system, briefly.** For each triangle, a local isometric 2D
/// embedding is built directly from its own 3D edge lengths — a copy of the
/// triangle's true shape, just flattened into a plane. The Cauchy–Riemann
/// condition for a map from that local plane to UV space to be conformal
/// (angle-preserving) gives two real linear equations per triangle in the
/// six UV unknowns of its three corners, built from the standard
/// piecewise-linear gradient formula. Summed over every triangle in an
/// island, minimizing the sum of squared residuals is a least-squares
/// problem `Aᵀ x ≈ 0`; two vertices are pinned to fixed UV values (the
/// two-degree similarity ambiguity — rotation and scale — that a pure
/// conformal energy never resolves on its own) and moved to the right-hand
/// side, leaving `AᵀA x = b` — symmetric positive semi-definite, solved by
/// conjugate gradients over a CSR matrix built directly as a sum of
/// per-triangle outer products, never materializing `A` itself.
///
/// **No `Job` here — a plain callback instead**, the same boundary call
/// `qem_simplify.dart` already made for `pro-lod-01`/`pro-lod-02`: the plan's
/// own `Job<T>` (`pro-job-01`) lives at
/// `apps/flutter3d_modeler/lib/src/job_runner.dart`, an application-layer
/// type this package sits under and cannot import. [unwrapMesh] instead
/// takes [onProgress] (called once per island) and [isCancelled] (polled the
/// same way), a dependency-free surface the app's own `Job` can wrap.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'attributes.dart';
import 'edit_mesh.dart';

/// [mesh] split into UV islands: connected groups of live faces, cut apart
/// wherever an edge carries [EdgeFlags.seam] or has no live twin (an
/// existing mesh boundary is already a cut nothing needs to mark).
///
/// Each island is a plain list of face indices — the same shape `projectUv`'s
/// own `island` parameter already expects, and the shape [lscm] takes here.
///
/// [restrictToFaces], when given, walks only those faces — a neighbour not in
/// the set is treated exactly like a dead one, so a selection unwrapped on
/// its own never spills onto a face nobody asked to touch. Null (the
/// default) walks every live face, unchanged from before this parameter
/// existed.
List<List<int>> splitIslands(EditMesh mesh, {Set<int>? restrictToFaces}) {
  final visited = Uint8List(mesh.faceSlotCount);
  final islands = <List<int>>[];
  bool included(int face) =>
      restrictToFaces == null || restrictToFaces.contains(face);

  for (var start = 0; start < mesh.faceSlotCount; start++) {
    if (!mesh.isFaceAlive(start) || visited[start] != 0 || !included(start)) {
      continue;
    }

    final island = <int>[];
    final stack = <int>[start];
    visited[start] = 1;
    while (stack.isNotEmpty) {
      final face = stack.removeLast();
      island.add(face);
      mesh.forEachHalfEdge(face, (half) {
        if (!mesh.hasLiveTwin(half)) return;
        if (mesh.edgeHas(half, EdgeFlags.seam)) return;
        final neighbor = mesh.faceOf(mesh.twinOf(half));
        if (!included(neighbor)) return;
        if (visited[neighbor] == 0) {
          visited[neighbor] = 1;
          stack.add(neighbor);
        }
      });
    }
    islands.add(island);
  }
  return islands;
}

/// Assigns a UV to every corner of every face in [island] by solving for the
/// Least Squares Conformal Map, writing through [EditMesh.setUv].
///
/// [pinVertex1]/[pinVertex2] fix two vertices to [pinUv1]/[pinUv2] — pass
/// both to control the unwrap's own scale and orientation exactly (a caller
/// matching an existing layout, or a test proving an identity); when either
/// is omitted, the two vertices farthest apart along the island's own
/// longest bounding-box axis are picked, placed at the origin and along the
/// U axis at their true 3D distance apart, a reasonable default that fixes
/// the ambiguity without favouring any particular orientation.
///
/// Does nothing on an island with fewer than two vertices — there is no
/// ambiguity left to resolve and no system left to solve.
void lscm(
  EditMesh mesh,
  List<int> island, {
  int? pinVertex1,
  Vector2? pinUv1,
  int? pinVertex2,
  Vector2? pinUv2,
  int maxIterations = 300,
  double tolerance = 1e-6,
}) {
  if (island.isEmpty) return;

  final vertices = <int>{};
  for (final face in island) {
    mesh.forEachHalfEdge(face, (half) => vertices.add(mesh.originOf(half)));
  }
  if (vertices.length < 2) return;

  final int pin1, pin2;
  final Vector2 uv1, uv2;
  if (pinVertex1 != null && pinVertex2 != null) {
    pin1 = pinVertex1;
    pin2 = pinVertex2;
    uv1 = pinUv1 ?? Vector2.zero();
    uv2 = pinUv2 ?? Vector2(1, 0);
  } else {
    final (a, b) = _pickFarApartPair(mesh, vertices);
    pin1 = a;
    pin2 = b;
    final distance = mesh.positionOf(a).distanceTo(mesh.positionOf(b));
    uv1 = pinUv1 ?? Vector2.zero();
    uv2 = pinUv2 ?? Vector2(distance, 0);
  }

  final freeIndex = <int, int>{};
  for (final v in vertices) {
    if (v == pin1 || v == pin2) continue;
    freeIndex[v] = freeIndex.length;
  }
  final freeCount = freeIndex.length;

  final uvByVertex = <int, Vector2>{pin1: uv1, pin2: uv2};
  if (freeCount == 0) {
    _writeIslandUv(mesh, island, uvByVertex);
    return;
  }

  final dofCount = freeCount * 2;
  // Raw, unmerged (column, value) pairs per row — appended as they are found
  // rather than accumulated into a hash map keyed by column. A vertex shared
  // by many triangles names the same pair of columns many times over, so
  // this holds duplicates; [_Csr.fromRawRows] sorts and sums them once,
  // which is far cheaper here than hashing on every single contribution
  // (the difference that keeps a 50 000-face island's assembly inside a
  // couple of seconds rather than several times that).
  final rowCols = List<List<int>>.generate(dofCount, (_) => <int>[]);
  final rowVals = List<List<double>>.generate(dofCount, (_) => <double>[]);
  final rhs = Float64List(dofCount);

  Vector2? pinnedUvOf(int vertex) =>
      vertex == pin1 ? uv1 : (vertex == pin2 ? uv2 : null);

  // One row of the conformality system: a coefficient for each of the
  // triangle's three corners' `u` and `v`. A pinned corner's contribution is
  // a known number, moved to [rhs] with its sign flipped; a free corner's
  // contribution accumulates `coefficient_i * coefficient_j` into every pair
  // of degrees of freedom the row touches — `AᵀA`, built directly as a sum
  // of these per-row outer products, without ever forming `A`.
  void accumulateRow(List<(int vertex, double coefU, double coefV)> terms) {
    var constant = 0.0;
    final free = <(int dof, double coef)>[];
    for (final (vertex, coefU, coefV) in terms) {
      final pinned = pinnedUvOf(vertex);
      if (pinned != null) {
        constant += coefU * pinned.x + coefV * pinned.y;
        continue;
      }
      final k = freeIndex[vertex]!;
      if (coefU != 0) free.add((k * 2, coefU));
      if (coefV != 0) free.add((k * 2 + 1, coefV));
    }
    for (final (di, ci) in free) {
      rhs[di] += -ci * constant;
      for (final (dj, cj) in free) {
        rowCols[di].add(dj);
        rowVals[di].add(ci * cj);
      }
    }
  }

  final corners = <int>[];
  for (final face in island) {
    corners.clear();
    mesh.forEachHalfEdge(face, (half) => corners.add(mesh.originOf(half)));
    if (corners.length < 3) continue;
    for (var i = 1; i < corners.length - 1; i++) {
      _accumulateTriangle(
        mesh,
        corners[0],
        corners[i],
        corners[i + 1],
        accumulateRow,
      );
    }
  }

  final matrix = _Csr.fromRawRows(rowCols, rowVals);
  final x = _conjugateGradient(matrix, rhs, maxIterations, tolerance);
  freeIndex.forEach((vertex, k) {
    uvByVertex[vertex] = Vector2(x[k * 2], x[k * 2 + 1]);
  });

  _writeIslandUv(mesh, island, uvByVertex);
}

/// [splitIslands] then [lscm] on each island in turn, [onProgress] called
/// once an island finishes (with how many of [splitIslands]'s own islands
/// are done and how many there are in total) and [isCancelled] polled the
/// same way — the row's own "`Job` по островам", without a `Job`.
///
/// A cancelled pass leaves every island unwrapped up to (not including) the
/// one it stopped on with whatever UV the mesh already carried there —
/// nothing already written is undone.
void unwrapMesh(
  EditMesh mesh, {
  void Function(int islandsDone, int islandsTotal)? onProgress,
  bool Function()? isCancelled,
}) {
  final islands = splitIslands(mesh);
  for (var i = 0; i < islands.length; i++) {
    if (isCancelled?.call() ?? false) return;
    lscm(mesh, islands[i]);
    onProgress?.call(i + 1, islands.length);
  }
}

void _writeIslandUv(
  EditMesh mesh,
  List<int> island,
  Map<int, Vector2> uvByVertex,
) {
  for (final face in island) {
    mesh.forEachHalfEdge(face, (half) {
      final uv = uvByVertex[mesh.originOf(half)];
      if (uv != null) mesh.setUv(half, uv);
    });
  }
}

/// The two vertices of [vertices] farthest apart along the island's own
/// longest bounding-box axis — an O(n) stand-in for the true farthest pair
/// (an O(n²) search), close enough for fixing an unwrap's own scale and
/// orientation and the only choice that stays fast on a 50 000-face island.
(int, int) _pickFarApartPair(EditMesh mesh, Set<int> vertices) {
  var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity, maxZ = -double.infinity;
  final p = Vector3.zero();
  for (final v in vertices) {
    mesh.positionOf(v, p);
    if (p.x < minX) minX = p.x;
    if (p.y < minY) minY = p.y;
    if (p.z < minZ) minZ = p.z;
    if (p.x > maxX) maxX = p.x;
    if (p.y > maxY) maxY = p.y;
    if (p.z > maxZ) maxZ = p.z;
  }
  final ex = maxX - minX, ey = maxY - minY, ez = maxZ - minZ;
  final axis = (ex >= ey && ex >= ez)
      ? Vector3(1, 0, 0)
      : (ey >= ez ? Vector3(0, 1, 0) : Vector3(0, 0, 1));

  int? lo, hi;
  var loProj = double.infinity, hiProj = -double.infinity;
  for (final v in vertices) {
    final proj = mesh.positionOf(v).dot(axis);
    if (proj < loProj) {
      loProj = proj;
      lo = v;
    }
    if (proj > hiProj) {
      hiProj = proj;
      hi = v;
    }
  }
  if (lo == hi) {
    final list = vertices.toList();
    return (list[0], list.length > 1 ? list[1] : list[0]);
  }
  return (lo!, hi!);
}

/// The conformality equations for one triangle `v0, v1, v2`, handed to
/// [accumulateRow] as a list of `(vertex, coefficient for u, coefficient for
/// v)` — once for each of the triangle's two real equations.
///
/// **The local basis.** `xAxis` runs along `v0→v1`; `yAxis` is perpendicular
/// to it within the triangle's own plane, chosen so `(xAxis, yAxis, normal)`
/// is right-handed for the same `normal` a CCW-wound face already has — so a
/// triangle already flat in world space (every vertex sharing one plane) has
/// `(x, y)` equal to its own world coordinates in that plane, up to one
/// shared rotation and translation for the whole island. That is what makes
/// an already-flat mesh's own [lscm] result reproduce its original layout: a
/// map that is the identity in every triangle's own local frame is trivially
/// conformal everywhere, so it is exactly what a correct least-squares fit
/// finds once the two pins remove the one remaining rotation/scale freedom.
///
/// **The two equations.** For a piecewise-linear function `f` over the
/// triangle, `grad(f) = Σ f_i · perp(p_{i+1} - p_{i-1})` (cyclic, [_perp]
/// rotating 90° so this is the standard finite-element gradient up to the
/// `1/(2·area)` this folds into the shared `1/√|2·area|` scale below).
/// Conformality is `grad(v) = perp(grad(u))`, which expands to the two rows
/// this returns.
void _accumulateTriangle(
  EditMesh mesh,
  int v0,
  int v1,
  int v2,
  void Function(List<(int vertex, double coefU, double coefV)> row)
  accumulateRow,
) {
  final p0 = mesh.positionOf(v0);
  final p1 = mesh.positionOf(v1);
  final p2 = mesh.positionOf(v2);

  final e1 = p1 - p0;
  final len1 = e1.length;
  if (len1 < 1e-12) return;
  final xAxis = e1 / len1;
  final normal = e1.cross(p2 - p0);
  final normalLength = normal.length;
  if (normalLength < 1e-20) return;
  normal.scale(1.0 / normalLength);
  final yAxis = normal.cross(xAxis);

  final e2 = p2 - p0;
  final x1 = len1;
  final x2 = e2.dot(xAxis);
  final y2 = e2.dot(yAxis);

  // `y1` is zero by this basis's own construction (`p1` sits on `xAxis`), so
  // the double area `x1·y2 - x2·y1` collapses to `x1·y2`.
  final doubleArea = x1 * y2;
  if (doubleArea.abs() < 1e-20) return;
  final scale = 1.0 / math.sqrt(doubleArea.abs());

  // `perp(p1local - p2local)`, `perp(p2local - p0local)`, `perp(p0local -
  // p1local)` — `p0local` is the origin and `p1local` is `(x1, 0)`, so each
  // reduces to the arithmetic below.
  final wx0 = y2 * scale, wy0 = (x1 - x2) * scale;
  final wx1 = -y2 * scale, wy1 = x2 * scale;
  final wx2 = 0.0, wy2 = -x1 * scale;

  accumulateRow(<(int, double, double)>[
    (v0, wy0, wx0),
    (v1, wy1, wx1),
    (v2, wy2, wx2),
  ]);
  accumulateRow(<(int, double, double)>[
    (v0, -wx0, wy0),
    (v1, -wx1, wy1),
    (v2, -wx2, wy2),
  ]);
}

/// A symmetric matrix in compressed sparse row form — the row's own
/// "разреженная система на CSR" — built once and then only ever read, which
/// is what [_conjugateGradient] does with it on every iteration.
class _Csr {
  _Csr(this._rowPtr, this._colIndex, this._values, this.size);

  final Int32List _rowPtr;
  final Int32List _colIndex;
  final Float64List _values;
  final int size;

  /// Builds a [_Csr] from unmerged (column, value) pairs per row — the same
  /// column can appear more than once in a row, and its values are summed.
  ///
  /// Sorting each row's own (typically small — a handful of neighbouring
  /// degrees of freedom) list of raw entries and merging in one pass is
  /// asymptotically the same cost as hashing every contribution as it
  /// arrives, but without a hash map's per-entry overhead — the difference
  /// that keeps assembly on a 50 000-face island inside its own time budget.
  factory _Csr.fromRawRows(List<List<int>> columns, List<List<double>> values) {
    final n = columns.length;
    final mergedColsPerRow = List<Int32List>.filled(n, Int32List(0));
    final mergedValsPerRow = List<Float64List>.filled(n, Float64List(0));
    var nnz = 0;

    for (var i = 0; i < n; i++) {
      final cols = columns[i];
      final vals = values[i];
      final count = cols.length;
      if (count == 0) continue;

      final sorted = List<int>.generate(count, (k) => k)
        ..sort((a, b) => cols[a].compareTo(cols[b]));

      final rowCols = <int>[];
      final rowVals = <double>[];
      var k = 0;
      while (k < count) {
        final column = cols[sorted[k]];
        var sum = vals[sorted[k]];
        k++;
        while (k < count && cols[sorted[k]] == column) {
          sum += vals[sorted[k]];
          k++;
        }
        rowCols.add(column);
        rowVals.add(sum);
      }
      mergedColsPerRow[i] = Int32List.fromList(rowCols);
      mergedValsPerRow[i] = Float64List.fromList(rowVals);
      nnz += rowCols.length;
    }

    final rowPtr = Int32List(n + 1);
    final colIndex = Int32List(nnz);
    final finalValues = Float64List(nnz);
    var offset = 0;
    for (var i = 0; i < n; i++) {
      rowPtr[i] = offset;
      final rowCols = mergedColsPerRow[i];
      final rowVals = mergedValsPerRow[i];
      colIndex.setRange(offset, offset + rowCols.length, rowCols);
      finalValues.setRange(offset, offset + rowVals.length, rowVals);
      offset += rowCols.length;
    }
    rowPtr[n] = offset;

    return _Csr(rowPtr, colIndex, finalValues, n);
  }

  Float64List multiply(Float64List x) => multiplyInto(x, Float64List(size));

  /// [multiply], writing into [out] instead of allocating a fresh result —
  /// what every one of [_conjugateGradient]'s own iterations calls, so a
  /// 50 000-face unwrap does not allocate a new 100 000-double array on
  /// every single one of them.
  Float64List multiplyInto(Float64List x, Float64List out) {
    for (var i = 0; i < size; i++) {
      var sum = 0.0;
      for (var k = _rowPtr[i]; k < _rowPtr[i + 1]; k++) {
        sum += _values[k] * x[_colIndex[k]];
      }
      out[i] = sum;
    }
    return out;
  }

  /// The matrix's own diagonal — the Jacobi preconditioner [_conjugateGradient]
  /// uses, cheap to read since a row's own diagonal entry is always present
  /// here (every degree of freedom appears in its own row's outer product).
  Float64List get diagonal {
    final result = Float64List(size);
    for (var i = 0; i < size; i++) {
      for (var k = _rowPtr[i]; k < _rowPtr[i + 1]; k++) {
        if (_colIndex[k] == i) {
          result[i] = _values[k];
          break;
        }
      }
    }
    return result;
  }
}

/// Jacobi-preconditioned conjugate gradients on `matrix · x = rhs`, starting
/// from `x = 0` — correct for the symmetric positive semi-definite system
/// [lscm] builds, since its `rhs` is always in `matrix`'s own range (it is
/// `-Aᵀ` applied to the pinned values, and `matrix` is `AᵀA`), so a solution
/// exists even where `matrix` itself is singular.
///
/// **Why Jacobi, and why this needs one at all.** Plain CG on this system
/// took over a hundred times longer than the row's own 50 000-face, 2-second
/// budget allows to reach a tight tolerance on a large, evenly-conditioned
/// grid — the well-known slow-converging case for an unpreconditioned
/// Laplacian-like matrix. Dividing by the diagonal every iteration is the
/// cheapest preconditioner there is, and enough here: this is a mesh
/// unwrap's own linear system, not a research paper's worst case.
Float64List _conjugateGradient(
  _Csr matrix,
  Float64List rhs,
  int maxIterations,
  double tolerance,
) {
  final n = rhs.length;
  final diagonal = matrix.diagonal;
  final z = Float64List(n);
  void preconditionInto(Float64List v) {
    for (var i = 0; i < n; i++) {
      z[i] = diagonal[i].abs() > 1e-300 ? v[i] / diagonal[i] : v[i];
    }
  }

  final x = Float64List(n);
  final r = Float64List.fromList(rhs);
  var rr = _dot(r, r);
  final residualTol2 = tolerance * tolerance * math.max(1.0, rr);
  if (rr <= residualTol2) return x;

  preconditionInto(r);
  final p = Float64List.fromList(z);
  var rzOld = _dot(r, z);
  final ap = Float64List(n);

  for (var iteration = 0; iteration < maxIterations; iteration++) {
    matrix.multiplyInto(p, ap);
    final pAp = _dot(p, ap);
    if (pAp.abs() < 1e-300) break;
    final alpha = rzOld / pAp;
    for (var i = 0; i < n; i++) {
      x[i] += alpha * p[i];
      r[i] -= alpha * ap[i];
    }
    rr = _dot(r, r);
    if (rr <= residualTol2) break;
    preconditionInto(r);
    final rzNew = _dot(r, z);
    final beta = rzNew / rzOld;
    for (var i = 0; i < n; i++) {
      p[i] = z[i] + beta * p[i];
    }
    rzOld = rzNew;
  }
  return x;
}

double _dot(Float64List a, Float64List b) {
  var sum = 0.0;
  for (var i = 0; i < a.length; i++) {
    sum += a[i] * b[i];
  }
  return sum;
}
