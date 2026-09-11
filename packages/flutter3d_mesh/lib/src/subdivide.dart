/// Catmull-Clark subdivision, with Pixar's semi-sharp crease, and the plain
/// linear subdivision it falls back to when nothing should smooth at all.
///
/// **Three new points per original face-corner, and the whole algorithm
/// follows from naming them.** Each live face gets one *face point* (the
/// average of its own vertices); each live edge gets one *edge point*; each
/// original vertex gets a repositioned *vertex point*. A face of `n`
/// vertices becomes `n` quads, one per corner, each touching a vertex
/// point, the edge point of the edge leaving it, the face point, and the
/// edge point of the edge entering it — which is why a cube subdivided once
/// has exactly `8 + 12 + 6 = 26` vertices (one point of each of the three
/// kinds) and `6 × 4 = 24` quads (one per corner of the original six faces),
/// the acceptance number `mesh-45`'s own row names.
///
/// **Crease decides two of the three points, not one.** An edge with
/// [EditMesh.creaseOf] at or above `1.0` holds its own edge point at the
/// plain midpoint through every level — [EditMesh.setCrease]'s own doc
/// comment says as much — while a value between 0 and 1 blends linearly
/// between the smooth edge point and the midpoint at the level it is asked
/// for, then decays to `max(crease - 1, 0)` on the two child edges that
/// replace it — zero for anything under `1.0`, so a fractional crease softens
/// exactly one level and is fully smooth from the next one on, the same rule
/// a value of `1.0` and above never triggers at all. A vertex
/// counts its own *hard* incident edges — creased at `1.0` or higher, or on
/// a boundary with no live twin — and takes one of three rules: zero hard
/// edges is the plain smooth rule, exactly two is the crease rule (an
/// ordinary boundary vertex is this case too), three or more is a corner
/// and does not move at all. **The vertex rule itself does not blend for a
/// fractional crease** — only the edge point does — which is why a cube
/// creased `1.0` everywhere keeps its exact shape (every vertex is a
/// three-hard-edge corner, so none of them move, and every edge and face
/// point sits at a plain midpoint or centroid of a flat quad) while a cube
/// creased `0.5` everywhere softens its edges but not, at this level, the
/// vertices they meet at.
///
/// **UV is bilinear per face-corner, not smoothed.** A face's own UV point
/// is the average of its corners' UVs; an edge point's UV, asked once per
/// face that touches it, is the average of that face's own two corners on
/// that edge — never the far face's, so a seam stays a seam — and a vertex
/// point simply keeps the UV each face already had at that corner. Only
/// position gets the Catmull-Clark treatment; carrying a second smoothing
/// pass for UV as well is not something this row's own acceptance (vertex
/// and face counts, and a volume) asks for.
///
/// **What this does not attempt.** A vertex touching exactly one hard edge —
/// not zero, two, or three or more — is a shape no closed, two-manifold
/// input can produce and is treated as smooth rather than refused; colour,
/// skin weights and material slot are not carried, the same gap
/// `mesh-42`'s `ArrayModifier` documents and for the same reason: nothing
/// yet asks for them, and copying a per-corner attribute correctly needs
/// its own pass.
library;

import 'package:vector_math/vector_math.dart';

import 'attributes.dart';
import 'edit_mesh.dart';

/// One level of [catmullClark], every vertex point held at its own original
/// position and every edge point at its own plain midpoint — the linear
/// subdivision a full Catmull-Clark pass reduces to when every edge is
/// creased at `1.0`, offered on its own for a caller that wants the same
/// four-quads-per-face topology without the smoothing, or a mesh whose
/// shape the smooth rules are not meant for.
EditMesh subdivideSimple(EditMesh mesh) => _subdivideOnce(mesh, smooth: false);

/// [mesh], Catmull-Clark subdivided [levels] times — once by default. See the
/// library doc comment for the vertex, edge and face rules, and for how
/// [EditMesh.creaseOf] bends them.
EditMesh catmullClark(EditMesh mesh, {int levels = 1}) {
  if (levels < 1) {
    throw ArgumentError('catmullClark needs at least one level, was $levels');
  }
  var result = mesh;
  for (var i = 0; i < levels; i++) {
    result = _subdivideOnce(result, smooth: true);
  }
  return result;
}

/// What a new quad's four corners carry once the base mesh's own arrays this
/// class is built from have gone out of scope: the crease each of its two
/// original-edge-aligned sides should hold, and the UV each of its four
/// corners should carry. Built face by face, applied in one pass after
/// [EditMeshBuilder.build] returns a mesh with real half-edge ids to write
/// them onto.
final class _NewQuad {
  const _NewQuad(
    this.face,
    this.creaseAfterVertex,
    this.creaseBeforeVertex,
    this.uvVertex,
    this.uvEdgeAfter,
    this.uvFace,
    this.uvEdgeBefore,
  );

  final int face;
  final double creaseAfterVertex;
  final double creaseBeforeVertex;
  final Vector2 uvVertex;
  final Vector2 uvEdgeAfter;
  final Vector2 uvFace;
  final Vector2 uvEdgeBefore;
}

EditMesh _subdivideOnce(EditMesh mesh, {required bool smooth}) {
  final hasUv = mesh.hasLayer(MeshDomain.corner, MeshAttribute.uv0);

  // Pass 1: one face point per live face, and each vertex's running sum of
  // the face points it touches (its own eventual `F` in the smooth rule).
  final facePoint = <int, Vector3>{};
  final faceSum = <int, Vector3>{};
  final faceCount = <int, int>{};
  for (var face = 0; face < mesh.faceSlotCount; face++) {
    if (!mesh.isFaceAlive(face)) continue;
    final loop = <int>[];
    mesh.forEachVertex(face, loop.add);
    final centre = Vector3.zero();
    for (final v in loop) {
      centre.add(mesh.positionOf(v));
    }
    centre.scale(1 / loop.length);
    facePoint[face] = centre;
    for (final v in loop) {
      faceSum[v] = (faceSum[v] ?? Vector3.zero())..add(centre);
      faceCount[v] = (faceCount[v] ?? 0) + 1;
    }
  }

  // Pass 2: one edge point per live edge (each processed exactly once, at
  // its own canonical half-edge), and each endpoint's running sum of the
  // original edge midpoints it touches (its `R`), plus the up-to-three hard
  // midpoints the crease rule and the corner rule read.
  final edgePoint = <int, Vector3>{};
  final edgeSum = <int, Vector3>{};
  final edgeCount = <int, int>{};
  final hardMidpoints = <int, List<Vector3>>{};
  for (var face = 0; face < mesh.faceSlotCount; face++) {
    if (!mesh.isFaceAlive(face)) continue;
    mesh.forEachHalfEdge(face, (int he) {
      if (mesh.edgeOf(he) != he) return; // the other side owns this edge
      final a = mesh.originOf(he);
      final b = mesh.originOf(mesh.nextOf(he));
      final midpoint = (mesh.positionOf(a) + mesh.positionOf(b)) / 2.0;
      final hasTwin = mesh.hasLiveTwin(he);
      final crease = mesh.creaseOf(he).clamp(0.0, 1.0);

      Vector3 point;
      if (!smooth || !hasTwin) {
        point = midpoint;
      } else {
        final f1 = facePoint[mesh.faceOf(he)]!;
        final f2 = facePoint[mesh.faceOf(mesh.twinOf(he))]!;
        final smoothPoint =
            (mesh.positionOf(a) + mesh.positionOf(b) + f1 + f2) / 4.0;
        point = smoothPoint.scaled(1 - crease) + midpoint.scaled(crease);
      }
      edgePoint[he] = point;

      for (final v in <int>[a, b]) {
        edgeSum[v] = (edgeSum[v] ?? Vector3.zero())..add(midpoint);
        edgeCount[v] = (edgeCount[v] ?? 0) + 1;
        if (!hasTwin || crease >= 1.0) {
          (hardMidpoints[v] ??= <Vector3>[]).add(midpoint);
        }
      }
    });
  }

  // Pass 3: one vertex point per live vertex, from `F`, `R`, the hard-edge
  // classification above and the vertex's own original position.
  final vertexPoint = <int, Vector3>{};
  for (var v = 0; v < mesh.vertexSlotCount; v++) {
    if (!mesh.isVertexAlive(v)) continue;
    final original = mesh.positionOf(v);
    if (!smooth) {
      vertexPoint[v] = original;
      continue;
    }
    final hard = hardMidpoints[v] ?? const <Vector3>[];
    if (hard.length >= 3) {
      vertexPoint[v] = original;
    } else if (hard.length == 2) {
      vertexPoint[v] = (original.scaled(6) + hard[0] + hard[1]) / 8.0;
    } else {
      final n = faceCount[v] ?? 0;
      if (n == 0) {
        vertexPoint[v] = original;
      } else {
        final f = faceSum[v]! / n.toDouble();
        final r = edgeSum[v]! / (edgeCount[v] ?? n).toDouble();
        vertexPoint[v] =
            (f + r.scaled(2) + original.scaled((n - 3).toDouble())) /
            n.toDouble();
      }
    }
  }

  // Pass 4: the new topology. One quad per original corner, built through
  // `EditMeshBuilder` the way every other whole-mesh modifier is, with a
  // fresh vertex per face point, per edge point and per vertex point.
  final builder = EditMeshBuilder();
  final facePointId = <int, int>{
    for (final entry in facePoint.entries)
      entry.key: builder.addVertex(entry.value),
  };
  final edgePointId = <int, int>{
    for (final entry in edgePoint.entries)
      entry.key: builder.addVertex(entry.value),
  };
  final vertexPointId = <int, int>{
    for (final entry in vertexPoint.entries)
      entry.key: builder.addVertex(entry.value),
  };

  final newQuads = <_NewQuad>[];
  for (var face = 0; face < mesh.faceSlotCount; face++) {
    if (!mesh.isFaceAlive(face)) continue;
    final halfEdges = <int>[];
    mesh.forEachHalfEdge(face, halfEdges.add);
    final n = halfEdges.length;
    final fp = facePointId[face]!;
    final faceUv = hasUv ? _averageUv(mesh, halfEdges) : Vector2.zero();

    for (var i = 0; i < n; i++) {
      final he = halfEdges[i];
      final prevHe = halfEdges[(i - 1 + n) % n];
      final v = mesh.originOf(he);
      final edgeAfter = mesh.edgeOf(he);
      final edgeBefore = mesh.edgeOf(prevHe);

      final loop = <int>[
        vertexPointId[v]!,
        edgePointId[edgeAfter]!,
        fp,
        edgePointId[edgeBefore]!,
      ];
      final newFace = builder.addFace(loop);

      final creaseAfter = _decay(mesh.creaseOf(edgeAfter));
      final creaseBefore = _decay(mesh.creaseOf(edgeBefore));
      final uvVertex = hasUv ? mesh.uvOf(he) : Vector2.zero();
      final uvAfter = hasUv
          ? _averageUv(mesh, <int>[he, mesh.nextOf(he)])
          : Vector2.zero();
      final uvBefore = hasUv
          ? _averageUv(mesh, <int>[prevHe, he])
          : Vector2.zero();

      newQuads.add(
        _NewQuad(
          newFace,
          creaseAfter,
          creaseBefore,
          uvVertex,
          uvAfter,
          faceUv,
          uvBefore,
        ),
      );
    }
  }

  final result = builder.build();
  result.beginStep();
  for (final quad in newQuads) {
    var he = result.halfEdgeOf(quad.face);
    result.setCrease(he, quad.creaseAfterVertex);
    if (hasUv) result.setUv(he, quad.uvVertex);
    he = result.nextOf(he);
    if (hasUv) result.setUv(he, quad.uvEdgeAfter);
    he = result.nextOf(he);
    if (hasUv) result.setUv(he, quad.uvFace);
    he = result.nextOf(he);
    result.setCrease(he, quad.creaseBeforeVertex);
    if (hasUv) result.setUv(he, quad.uvEdgeBefore);
  }
  result.endStep();
  return result;
}

/// `crease` held through every level once it reaches `1.0` —
/// [EditMesh.setCrease]'s own doc comment states this — or fully decayed to
/// smooth otherwise: a fractional crease's `max(crease - 1, 0)` is always
/// zero, since crease is never above `1.0` in the branch that reaches it.
double _decay(double crease) => crease >= 1.0 ? 1.0 : 0.0;

Vector2 _averageUv(EditMesh mesh, List<int> halfEdges) {
  final sum = Vector2.zero();
  for (final he in halfEdges) {
    sum.add(mesh.uvOf(he));
  }
  return sum / halfEdges.length.toDouble();
}
