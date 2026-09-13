/// Isotropic remeshing — the Botsch–Kobbelt loop of split, collapse, flip and
/// tangential smoothing, over `EditMesh`. `mesh-73`'s own spike.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'edit_mesh.dart';
import 'merge.dart';
import 'selection.dart';

/// How close a triangle is to equilateral: the ratio of its circumradius to
/// twice its inradius, so an equilateral triangle reads `1.0` and a sliver
/// reads far larger. Degenerate (zero-area) reads [double.infinity] rather
/// than throwing, which is what lets a caller average this over a mesh that
/// is mid-repair without a special case for the one triangle that is wrong.
double triangleAspectRatio(Vector3 p0, Vector3 p1, Vector3 p2) {
  final a = (p1 - p2).length;
  final b = (p0 - p2).length;
  final c = (p0 - p1).length;
  final s = (a + b + c) / 2;
  final area = (p1 - p0).cross(p2 - p0).length / 2;
  if (area < 1e-12) return double.infinity;
  return (a * b * c * s) / (8 * area * area);
}

/// The edge lengths and triangle aspect ratios of a mesh, at one point in
/// time — what a before/after comparison of a remesh needs, kept as one
/// value rather than four so the two ends of that comparison cannot
/// accidentally be measured two different ways.
final class MeshQualityStats {
  const MeshQualityStats({
    required this.edgeCount,
    required this.triangleCount,
    required this.meanEdgeLength,
    required this.edgeLengthStdDev,
    required this.meanAspectRatio,
    required this.maxAspectRatio,
  });

  final int edgeCount;
  final int triangleCount;
  final double meanEdgeLength;
  final double edgeLengthStdDev;
  final double meanAspectRatio;
  final double maxAspectRatio;

  /// Standard deviation over the mean — scale-free, so a sphere of radius one
  /// and the same sphere at radius ten read the same number.
  double get edgeLengthCv =>
      meanEdgeLength == 0 ? 0 : edgeLengthStdDev / meanEdgeLength;

  /// Reads every live triangle of [mesh] once. Refuses a mesh that is not
  /// already pure triangles — an n-gon has no aspect ratio this metric
  /// means, and averaging over some triangles and skipping the rest would
  /// quietly answer a different question than the one asked.
  factory MeshQualityStats.of(EditMesh mesh) {
    final lengths = <double>[];
    final seenEdges = <int>{};
    for (var face = 0; face < mesh.faceSlotCount; face++) {
      if (!mesh.isFaceAlive(face)) continue;
      if (mesh.valencyOf(face) != 3) {
        throw ArgumentError(
          'face $face has ${mesh.valencyOf(face)} sides; '
          'MeshQualityStats.of wants a triangle mesh',
        );
      }
      mesh.forEachHalfEdge(face, (int half) {
        final edge = mesh.edgeOf(half);
        if (seenEdges.add(edge)) {
          lengths.add(_edgeLength(mesh, half));
        }
      });
    }

    final meanLength = lengths.isEmpty
        ? 0.0
        : lengths.reduce((double a, double b) => a + b) / lengths.length;
    final variance = lengths.isEmpty
        ? 0.0
        : lengths
                  .map((double l) => (l - meanLength) * (l - meanLength))
                  .reduce((double a, double b) => a + b) /
              lengths.length;

    var totalAspect = 0.0;
    var maxAspect = 0.0;
    var triangles = 0;
    for (final loop in mesh.faces()) {
      final ratio = triangleAspectRatio(
        mesh.positionOf(loop[0]),
        mesh.positionOf(loop[1]),
        mesh.positionOf(loop[2]),
      );
      totalAspect += ratio;
      if (ratio > maxAspect) maxAspect = ratio;
      triangles++;
    }

    return MeshQualityStats(
      edgeCount: lengths.length,
      triangleCount: triangles,
      meanEdgeLength: meanLength,
      edgeLengthStdDev: math.sqrt(variance),
      meanAspectRatio: triangles == 0 ? 0 : totalAspect / triangles,
      maxAspectRatio: maxAspect,
    );
  }

  @override
  String toString() =>
      'MeshQualityStats($triangleCount triangles, $edgeCount edges, '
      'edge length ${meanEdgeLength.toStringAsFixed(4)} ± '
      '${edgeLengthStdDev.toStringAsFixed(4)} '
      '(cv ${edgeLengthCv.toStringAsFixed(3)}), aspect ratio mean '
      '${meanAspectRatio.toStringAsFixed(3)} max '
      '${maxAspectRatio.toStringAsFixed(3)})';
}

/// What [isotropicRemesh] did, and how the mesh measured before and after.
final class RemeshReport {
  const RemeshReport({
    required this.iterations,
    required this.targetEdgeLength,
    required this.edgeSplits,
    required this.edgeCollapses,
    required this.edgeFlips,
    required this.before,
    required this.after,
  });

  final int iterations;
  final double targetEdgeLength;
  final int edgeSplits;
  final int edgeCollapses;
  final int edgeFlips;
  final MeshQualityStats before;
  final MeshQualityStats after;

  @override
  String toString() =>
      'RemeshReport($iterations iterations toward edge length '
      '${targetEdgeLength.toStringAsFixed(4)}: $edgeSplits splits, '
      '$edgeCollapses collapses, $edgeFlips flips; before $before; '
      'after $after)';
}

/// Remeshes [mesh] toward uniform triangles of edge length [targetEdgeLength],
/// the Botsch–Kobbelt loop: split what is too long, collapse what is too
/// short, flip edges to push vertex valence toward six, and smooth each
/// vertex within its own tangent plane. Returns the remeshed mesh — which is
/// **not** [mesh] once a single edge has collapsed, see below — paired with
/// what the pass measured.
///
/// **What this is.** A working, tested implementation of the textbook
/// algorithm (Botsch & Kobbelt, *A Remeshing Approach to Multiresolution
/// Modeling*, 2004) over this package's own `EditMesh`, run to convergence on
/// this package's own `ParametricSphere` — proof the approach holds up on
/// real geometry, not a sketch. `pro-rt-01` absorbed this row and took a
/// different path for its own retopology (simplify, then greedy
/// quadrification, then shrink-wrap the result onto a BVH of the source) —
/// this pass is not wired into that pipeline and is not meant to be; it is
/// the answer the spike was asked for, kept in case a later row wants
/// triangle-domain remeshing rather than the quad path `pro-rt-01` chose.
///
/// **Results, measured by `isotropic_remesh_test.dart`.** A triangulated
/// `ParametricSphere(radius: 1, segments: 24, rings: 12)` — 528 triangles,
/// mean edge length `0.254 ± 0.073` (coefficient of variation `0.287`) out of
/// the box, because a UV sphere's triangles shrink toward each pole — run
/// toward `targetEdgeLength` equal to that starting mean: after a single
/// iteration the CV is already down to `0.174` and mean aspect ratio from
/// `1.466` to `1.080`; by 8 iterations CV is `0.096` (a third of where it
/// started) and mean/max aspect ratio are `1.016`/`1.097`, against
/// `1.466`/`2.418` before. A second case starts from the same sphere stretched
/// 4× along one axis into an ellipsoid — mean aspect ratio `3.631`, max
/// `13.974`, entirely from the stretch rather than the poles — and remeshing
/// it back toward its own new mean edge length brings mean/max aspect ratio
/// to `1.016`/`1.084` by 8 iterations, with the same one-iteration jump doing
/// most of the work (`1.068`/`1.980` after the first pass alone). Both cases
/// keep Euler characteristic 2 and pass `EditMesh.validate` throughout —
/// remeshing a topological sphere yields a topological sphere — and both
/// converge rather than oscillate: CV and aspect ratio fall monotonically
/// with more iterations, flattening out rather than overshooting.
///
/// **What made this easier than the textbook assumes.** `EditMesh.splitEdge`
/// already does the geometric half of a split — new vertex, attributes
/// carried, both sides of the twin handled — so "split an edge and
/// retriangulate" is that plus one call to `EditMesh.splitFace` per side to
/// cut the resulting quad along the diagonal to the vertex the split did not
/// touch. `merge.dart`'s `mergeAt` turns out to already *be* a correct edge
/// collapse: welding an edge's two endpoints to their midpoint drops the
/// (up to two) triangles that degenerate to a line automatically, by the same
/// path that drops a degenerate face after any other weld — nothing
/// remeshing-specific had to be written for it.
///
/// **What made it harder.** Two things this package has no primitive for at
/// all. First, **edge flip** — needed to push vertex valence toward six,
/// which is what keeps triangles from staying skewed even after lengths
/// converge — does not exist as an operation anywhere in this package, and
/// is not obviously one `EditMesh` should grow for this alone: it is composed
/// here from two that already exist, `dissolveEdge` (merge the two triangles
/// across the edge into a quad) followed by `splitFace` across the *other*
/// diagonal of that quad. It works, and it is indirect enough that it took
/// tracing through both operations' half-edge bookkeeping by hand to find
/// which two corners of the merged quad are the new diagonal. Second,
/// **there is no in-place edge collapse.** `mergeAt` is correct but it is not
/// a mesh edit — it is a whole-mesh rebuild through `EditMeshBuilder` that
/// hands back an `IdRemap`, because welding can turn a manifold edge
/// non-manifold and repairing that is exactly the rebuild `EditMeshBuilder`
/// already does for an import. That is the right trade for a person merging
/// a handful of vertices by hand; for a remeshing pass that might collapse
/// hundreds of edges per iteration on a dense scan, paying for a full
/// `O(vertices + faces)` rebuild per collapse is real cost this spike is
/// flagging for `pro-rt-01` rather than paying for silently — an in-place
/// "collapse this one edge, relink its neighbourhood, tombstone the rest"
/// operation, guarded the way `dissolveVertex` already guards its own
/// non-manifold cases, would turn this from a prototype into something a
/// dense mesh could run through directly.
///
/// **What this spike left out, on purpose.** No re-projection onto the
/// original surface (a BVH shrink-wrap, the way `pro-rt-01` closes its own
/// loop) — tangential smoothing alone drifts a curved surface inward a
/// little every pass, which is exactly why `pro-rt-01`'s own answer ends
/// with a shrink-wrap rather than trusting smoothing to hold shape. No
/// boundary handling — every collapse, flip and smoothing step here assumes
/// a closed, two-manifold mesh, because that is what `ParametricSphere` is
/// and what the acceptance test needed; a boundary edge is skipped by the
/// flip and smoothing passes rather than handled, and collapsing one is left
/// to `mergeAt`'s own general-purpose behaviour rather than a boundary-aware
/// target valence of four. Both are exactly the kind of thing a spike is for
/// finding before the real row pays to discover them.
(EditMesh, RemeshReport) isotropicRemesh(
  EditMesh mesh, {
  required double targetEdgeLength,
  int iterations = 5,
  double tangentialLambda = 1.0,
}) {
  if (targetEdgeLength <= 0) {
    throw ArgumentError.value(
      targetEdgeLength,
      'targetEdgeLength',
      'must be positive',
    );
  }
  if (iterations < 1) {
    throw ArgumentError.value(iterations, 'iterations', 'must be at least 1');
  }

  final before = MeshQualityStats.of(mesh);
  final longThreshold = targetEdgeLength * 4 / 3;
  final shortThreshold = targetEdgeLength * 4 / 5;

  var current = mesh;
  var splits = 0;
  var collapses = 0;
  var flips = 0;

  for (var iter = 0; iter < iterations; iter++) {
    current.beginStep();
    splits += _splitLongEdges(current, longThreshold);
    current.endStep();

    final collapsed = _collapseShortEdges(current, shortThreshold);
    current = collapsed.mesh;
    collapses += collapsed.count;

    current.beginStep();
    flips += _equalizeValence(current);
    _tangentialSmoothPass(current, lambda: tangentialLambda);
    current.endStep();
  }

  return (
    current,
    RemeshReport(
      iterations: iterations,
      targetEdgeLength: targetEdgeLength,
      edgeSplits: splits,
      edgeCollapses: collapses,
      edgeFlips: flips,
      before: before,
      after: MeshQualityStats.of(current),
    ),
  );
}

double _edgeLength(EditMesh mesh, int halfEdge) {
  final a = mesh.positionOf(mesh.originOf(halfEdge));
  final b = mesh.positionOf(mesh.originOf(mesh.nextOf(halfEdge)));
  return (a - b).length;
}

/// Splits every edge longer than [maxLength] at its midpoint, keeping the
/// mesh pure triangles by re-cutting each side's quad along the diagonal to
/// the vertex the split did not touch. One pass over a snapshot of the edges
/// that existed when it started — a split can leave one half still too long,
/// and the next call to [isotropicRemesh]'s own loop is what catches that,
/// the same way the textbook algorithm relies on more than one iteration
/// rather than a single pass converging on its own.
int _splitLongEdges(EditMesh mesh, double maxLength) {
  final edges = <int>{};
  for (var face = 0; face < mesh.faceSlotCount; face++) {
    if (!mesh.isFaceAlive(face)) continue;
    mesh.forEachHalfEdge(face, (int half) => edges.add(mesh.edgeOf(half)));
  }

  var splits = 0;
  for (final edge in edges) {
    final face = mesh.faceOf(edge);
    if (face == EditMesh.none || !mesh.isFaceAlive(face)) continue;
    if (_edgeLength(mesh, edge) > maxLength) {
      _splitEdgeKeepingTriangles(mesh, edge);
      splits++;
    }
  }
  return splits;
}

/// [EditMesh.splitEdge], plus the [EditMesh.splitFace] on each side that
/// turns the quad it leaves behind back into two triangles — see
/// [isotropicRemesh]'s own doc comment for why this composition and not a
/// new primitive.
int _splitEdgeKeepingTriangles(EditMesh mesh, int halfEdge) {
  final ahead = mesh.nextOf(halfEdge);
  final apexEdge = mesh.nextOf(ahead);
  final faceA = mesh.faceOf(halfEdge);

  final hasTwin = mesh.hasLiveTwin(halfEdge);
  var twin = EditMesh.none;
  var closerEdge = EditMesh.none;
  var faceB = EditMesh.none;
  if (hasTwin) {
    twin = mesh.twinOf(halfEdge);
    final beyond = mesh.nextOf(twin);
    closerEdge = mesh.nextOf(beyond);
    faceB = mesh.faceOf(twin);
  }

  final middle = mesh.splitEdge(halfEdge, factor: 0.5);

  final far = mesh.nextOf(halfEdge);
  mesh.splitFace(faceA, far, apexEdge);

  if (hasTwin) {
    final back = mesh.nextOf(twin);
    mesh.splitFace(faceB, back, closerEdge);
  }

  return middle;
}

/// Repeatedly welds the shortest live edge under [minLength] to its
/// midpoint, through [mergeAt], until none is left. Rescans the whole mesh
/// per collapse rather than tracking a priority queue across the
/// [mergeAt]-renumbered ids a queue would otherwise go stale against — see
/// [isotropicRemesh]'s own doc comment on the cost of that, which is real
/// and is exactly what a spike is for finding.
({EditMesh mesh, int count}) _collapseShortEdges(
  EditMesh startMesh,
  double minLength,
) {
  var current = startMesh;
  var count = 0;
  // A generous but finite ceiling: every collapse removes at least one edge,
  // so this cannot loop longer than the mesh had edges to begin with — a
  // guard against a bug turning a convergent pass into a hang, not a limit
  // this is expected to reach.
  final ceiling = current.edgeCount + 1;

  while (count < ceiling) {
    var bestEdge = EditMesh.none;
    var bestLength = minLength;
    for (var face = 0; face < current.faceSlotCount; face++) {
      if (!current.isFaceAlive(face)) continue;
      current.forEachHalfEdge(face, (int half) {
        final edge = current.edgeOf(half);
        final length = _edgeLength(current, edge);
        if (length < bestLength) {
          bestLength = length;
          bestEdge = edge;
        }
      });
    }
    if (bestEdge == EditMesh.none) break;

    final a = current.originOf(bestEdge);
    final b = current.originOf(current.nextOf(bestEdge));
    final midpoint = (current.positionOf(a) + current.positionOf(b)).scaled(
      0.5,
    );
    final (merged, report) = mergeAt(
      current,
      Selection.of(ElementLevel.vertex, <int>[a, b]),
      midpoint,
    );
    if (report.merged == 0) break; // Refused to collapse further; stop here.
    current = merged;
    count++;
  }
  return (mesh: current, count: count);
}

/// One vertex's normal: the average of the normals of every live face around
/// it, which is what [_tangentialSmoothPass] projects onto rather than
/// `EditMesh`'s own per-face normal, since a vertex has none of its own.
Vector3 _vertexNormal(EditMesh mesh, int vertex) {
  final sum = Vector3.zero();
  final start = mesh.outgoingOf(vertex);
  if (start == EditMesh.none) return sum;
  var half = start;
  while (true) {
    final face = mesh.faceOf(half);
    if (face != EditMesh.none && mesh.isFaceAlive(face)) {
      sum.add(mesh.normalOf(face));
    }
    if (!mesh.hasLiveTwin(half)) break;
    half = mesh.nextOf(mesh.twinOf(half));
    if (half == start) break;
  }
  if (sum.length2 > 0) sum.normalize();
  return sum;
}

/// Moves every vertex [lambda] of the way toward its neighbours' centroid,
/// after dropping the part of that step along the vertex's own normal — the
/// "tangential" in tangential smoothing, and the reason this does not just
/// call `smoothVertices`: that one smooths along the full Laplacian, which
/// is what shrinks a sphere over enough iterations, and needs the HC
/// correction to fight it back. Projecting onto the tangent plane first
/// means a step here mostly slides a vertex sideways into a better-shaped
/// triangle instead of pulling it toward the surface's own centre — not
/// immune to drift over many iterations (nothing here reprojects onto the
/// original surface; see [isotropicRemesh]'s own doc comment), but far
/// slower than the plain Laplacian to shrink by.
void _tangentialSmoothPass(EditMesh mesh, {required double lambda}) {
  final targets = <int, Vector3>{};
  for (var vertex = 0; vertex < mesh.vertexSlotCount; vertex++) {
    if (!mesh.isVertexAlive(vertex)) continue;
    final neighbors = mesh.neighborsOf(vertex);
    if (neighbors.isEmpty) continue;

    final position = mesh.positionOf(vertex);
    final centroid = Vector3.zero();
    for (final neighbor in neighbors) {
      centroid.add(mesh.positionOf(neighbor));
    }
    centroid.scale(1 / neighbors.length);

    final laplacian = centroid - position;
    final normal = _vertexNormal(mesh, vertex);
    final tangential = normal.length2 > 0
        ? laplacian - normal.scaled(laplacian.dot(normal))
        : laplacian;
    targets[vertex] = position + tangential.scaled(lambda);
  }
  targets.forEach(mesh.moveVertex);
}

/// Whether flipping the shared edge of triangles (a, b, c) and (b, a, d) into
/// (c, a, d) / (d, b, c) leaves both new triangles facing roughly the way the
/// old pair did, with real area — the standard guard against a flip folding
/// the surface back on itself or degenerating a triangle to a line, the same
/// shape of check `qem_simplify.dart`'s own `_wouldFlip` runs before a
/// collapse.
bool _flipIsGeometricallySafe(Vector3 a, Vector3 b, Vector3 c, Vector3 d) {
  final reference = (b - a).cross(c - a) + (a - b).cross(d - b);
  if (reference.length2 < 1e-20) return false;
  reference.normalize();

  final newNormal1 = (a - c).cross(d - c);
  final newNormal2 = (b - d).cross(c - d);
  if (newNormal1.length2 < 1e-20 || newNormal2.length2 < 1e-20) return false;

  const cosineFloor = 0.2; // roughly 78°: generous, but rules out a fold.
  return newNormal1.normalized().dot(reference) > cosineFloor &&
      newNormal2.normalized().dot(reference) > cosineFloor;
}

/// Flips the edge [edge] lies on — composed from [EditMesh.dissolveEdge]
/// (merge the two triangles across it into a quad) and [EditMesh.splitFace]
/// (cut that quad along its other diagonal) — and says whether it happened.
bool _flipEdge(EditMesh mesh, int edge) {
  if (!mesh.hasLiveTwin(edge)) return false;
  final faceA = mesh.faceOf(edge);
  final twin = mesh.twinOf(edge);
  final faceB = mesh.faceOf(twin);
  if (mesh.valencyOf(faceA) != 3 || mesh.valencyOf(faceB) != 3) return false;

  // The corner opposite `edge` on each triangle — `c` on face A, `d` on face
  // B — found by walking two steps round a 3-cycle, which lands back at the
  // corner before the one this started from.
  final apexEdge = mesh.nextOf(mesh.nextOf(edge));
  final twinApex = mesh.nextOf(mesh.nextOf(twin));
  final c = mesh.originOf(apexEdge);
  final d = mesh.originOf(twinApex);
  if (c == d) return false; // The two triangles already share a second edge.

  if (!_flipIsGeometricallySafe(
    mesh.positionOf(mesh.originOf(edge)),
    mesh.positionOf(mesh.originOf(twin)),
    mesh.positionOf(c),
    mesh.positionOf(d),
  )) {
    return false;
  }

  if (!mesh.dissolveEdge(edge)) return false;
  final mergedFace = mesh.faceOf(apexEdge);
  return mesh.splitFace(mergedFace, apexEdge, twinApex) != EditMesh.none;
}

const int _targetValence = 6;

int _valenceDeviationOf(EditMesh mesh, int vertex) =>
    (mesh.neighborsOf(vertex).length - _targetValence).abs();

/// Flips every interior edge whose flip would bring its four corners' vertex
/// valence closer to six on average — the regular triangulation's own
/// valence, and the reason equalizing toward it is what keeps a remeshed
/// patch from staying visibly skewed even once every edge is close to
/// [isotropicRemesh]'s own target length. Boundary edges are left alone: see
/// [isotropicRemesh]'s own doc comment on why this spike does not chase a
/// boundary-aware target valence of four.
int _equalizeValence(EditMesh mesh) {
  final edges = <int>{};
  for (var face = 0; face < mesh.faceSlotCount; face++) {
    if (!mesh.isFaceAlive(face)) continue;
    mesh.forEachHalfEdge(face, (int half) => edges.add(mesh.edgeOf(half)));
  }

  var flips = 0;
  for (final edge in edges) {
    final faceA = mesh.faceOf(edge);
    if (faceA == EditMesh.none || !mesh.isFaceAlive(faceA)) continue;
    if (!mesh.hasLiveTwin(edge)) continue;
    final twin = mesh.twinOf(edge);
    final faceB = mesh.faceOf(twin);
    if (faceB == EditMesh.none || !mesh.isFaceAlive(faceB)) continue;
    if (mesh.valencyOf(faceA) != 3 || mesh.valencyOf(faceB) != 3) continue;

    final a = mesh.originOf(edge);
    final b = mesh.originOf(twin);
    final c = mesh.originOf(mesh.nextOf(mesh.nextOf(edge)));
    final d = mesh.originOf(mesh.nextOf(mesh.nextOf(twin)));
    if (c == d) continue;

    final before =
        _valenceDeviationOf(mesh, a) +
        _valenceDeviationOf(mesh, b) +
        _valenceDeviationOf(mesh, c) +
        _valenceDeviationOf(mesh, d);
    final after =
        (mesh.neighborsOf(a).length - 1 - _targetValence).abs() +
        (mesh.neighborsOf(b).length - 1 - _targetValence).abs() +
        (mesh.neighborsOf(c).length + 1 - _targetValence).abs() +
        (mesh.neighborsOf(d).length + 1 - _targetValence).abs();
    if (after >= before) continue;

    if (_flipEdge(mesh, edge)) flips++;
  }
  return flips;
}
