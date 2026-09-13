/// `pro-rt-01`'s own row: `retopologize(source, targetQuads)` — simplify,
/// greedily pair triangles into quads, shrink-wrap the result back onto
/// [source]'s own surface. "quadriflow — после" is this row's own words for
/// what is deliberately not here: a real global quad-flow optimizer is a
/// research project of its own, and this row's acceptance (≥70% quad faces,
/// not "every face a quad") asks for the greedy pass that pairing adjacent
/// triangles by how nearly coplanar they are already gives.
///
/// **Three existing pieces, not a fourth mesh representation.**
/// [simplifyMesh] (`pro-lod-01`) reduces the triangle count; [importMeshData]
/// (`mesh-13`) welds the simplified soup back into an [EditMesh] with real
/// half-edge topology; [EditMesh.dissolveEdge] (`mesh-45`) is, by its own doc
/// comment, "the operation that turns a triangulated import back into
/// quads" — already built, already the right primitive, so quadrifying here
/// is choosing *which* edges to dissolve, not a second implementation of
/// dissolving one.
library;

import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:vector_math/vector_math.dart' hide Ray;

import 'edit_mesh.dart';
import 'import_mesh.dart';
import 'qem_simplify.dart';

/// [source] simplified to about [targetQuads] quads and shrink-wrapped back
/// onto its own surface.
///
/// [coplanarThreshold] is the dot product two triangles' own face normals
/// must clear to be merged into one quad — `1.0` is exactly coplanar, and
/// the default asks for "within about 45 degrees" (`cos(45°) ≈ 0.707`), the
/// same reasoning a smoothing-angle threshold elsewhere in this package
/// already uses: two triangles closer than that read as one surface bending
/// gently, not a real edge a quad ought to keep.
EditMesh retopologize(
  EditMesh source, {
  required int targetQuads,
  double coplanarThreshold = 0.7,
}) {
  final sourceData = source.toMeshData();
  final simplified = simplifyMesh(
    sourceData,
    targetTriangleCount: (targetQuads * 2).clamp(1, 1 << 30),
  );
  final (mesh, _, _) = importMeshData(simplified);

  _greedyQuadrangulate(mesh, coplanarThreshold);
  _shrinkWrap(mesh, TriangleBvh.fromMesh(sourceData));

  return mesh;
}

/// The outward normal of [face]'s own first three corners. Exact for the
/// triangles [_greedyQuadrangulate] asks about; an approximation — good
/// enough for [_shrinkWrap]'s own vertex-normal average, not used for
/// anything drawn — for the quads [_vertexNormal] asks about afterwards,
/// since a real quad from this pass is close enough to planar that three of
/// its four corners already name its normal.
Vector3 _triangleNormal(EditMesh mesh, int face) {
  final vertices = mesh.verticesOf(face);
  final a = mesh.positionOf(vertices[0]);
  final b = mesh.positionOf(vertices[1]);
  final c = mesh.positionOf(vertices[2]);
  final normal = (b - a).cross(c - a);
  final length = normal.length;
  return length < 1e-12 ? Vector3.zero() : normal
    ..scale(1 / length);
}

/// Walks every triangle once, dissolving the first live, still-triangular,
/// near-coplanar neighbour it finds across one of its own edges.
///
/// **First fit, not best fit.** A face already merged into this pass's own
/// quad is skipped by [EditMesh.isFaceAlive]/[EditMesh.valencyOf] — the
/// slot [EditMesh.dissolveEdge] keeps is exactly one of the two triangles
/// that met there, so a later face in slot order never revisits a quad
/// this loop already made. Choosing the *best* of up to three neighbours
/// instead of the first workable one would raise the quad fraction further,
/// which this row's own acceptance (≥70%, not 100%) does not ask for.
void _greedyQuadrangulate(EditMesh mesh, double coplanarThreshold) {
  mesh.beginStep();
  for (var face = 0; face < mesh.faceSlotCount; face++) {
    if (!mesh.isFaceAlive(face) || mesh.valencyOf(face) != 3) continue;

    final normal = _triangleNormal(mesh, face);
    final halfEdges = <int>[];
    mesh.forEachHalfEdge(face, halfEdges.add);

    for (final half in halfEdges) {
      final edge = mesh.edgeOf(half);
      if (!mesh.hasLiveTwin(edge)) continue;
      final neighbourFace = mesh.faceOf(mesh.twinOf(edge));
      if (neighbourFace == face) continue;
      if (!mesh.isFaceAlive(neighbourFace) ||
          mesh.valencyOf(neighbourFace) != 3) {
        continue;
      }
      if (normal.dot(_triangleNormal(mesh, neighbourFace)) <
          coplanarThreshold) {
        continue;
      }
      if (mesh.dissolveEdge(half)) break;
    }
  }
  mesh.endStep();
}

/// Moves every live vertex of [mesh] onto the nearest point [sourceBvh]
/// answers with, along the vertex's own current normal — the "shrink-wrap"
/// [retopologize]'s own row asks for once quadrangulation is done.
///
/// **Along the normal both ways, not a nearest-point query.** [TriangleBvh]
/// answers a raycast, not "the closest point on the surface to this one" —
/// building the second query would duplicate most of the first's own
/// traversal. A vertex fresh out of [simplifyMesh] already sits close to
/// [sourceBvh]'s own surface (that function's whole job is staying close to
/// it), so a short ray along the local normal, cast from a little behind the
/// vertex in each direction, reaches the surface it approximates almost
/// every time; a vertex neither ray reaches is left exactly where
/// simplification put it, which is this function's only fallback and
/// already within the tolerance a caller checks.
void _shrinkWrap(EditMesh mesh, TriangleBvh sourceBvh) {
  // A vertex's own position, once, so nearby corners agree on where it is —
  // the same reasoning `_flatten` gives in `sculpt_mesh_bvh.dart`.
  final bounds = sourceBvh.positions.isEmpty
      ? 1.0
      : _diagonalOf(sourceBvh.positions);
  final margin = bounds * 0.05;

  mesh.beginStep();
  for (var vertex = 0; vertex < mesh.vertexSlotCount; vertex++) {
    if (!mesh.isVertexAlive(vertex)) continue;
    final normal = _vertexNormal(mesh, vertex);
    if (normal.length2 < 1e-12) continue;
    final position = mesh.positionOf(vertex);

    final outward = Ray(position - normal * margin, normal);
    final inward = Ray(position + normal * margin, -normal);
    final fromOutward = sourceBvh.raycast(outward, maxDistance: margin * 2);
    final fromInward = sourceBvh.raycast(inward, maxDistance: margin * 2);

    final Vector3? landed = switch ((fromOutward, fromInward)) {
      (final o?, final i?) =>
        (o.distance - margin).abs() <= (i.distance - margin).abs()
            ? o.point
            : i.point,
      (final o?, null) => o.point,
      (null, final i?) => i.point,
      (null, null) => null,
    };
    if (landed != null) mesh.moveVertex(vertex, landed);
  }
  mesh.endStep();
}

/// The average of every live face's own normal that touches [vertex] — a
/// vertex normal cheap enough to compute on demand for a one-off pass like
/// [_shrinkWrap], not kept as a layer the way `faceNormals`/`cornerNormals`
/// are for drawing.
///
/// The same half-edge fan walk [EditMesh.neighborsOf] itself uses —
/// `nextOf(twinOf(half))` from [EditMesh.outgoingOf] — reading
/// [EditMesh.faceOf] at each stop instead of a neighbouring vertex.
Vector3 _vertexNormal(EditMesh mesh, int vertex) {
  final sum = Vector3.zero();
  final start = mesh.outgoingOf(vertex);
  if (start == EditMesh.none) return sum;
  var half = start;
  while (true) {
    sum.add(_triangleNormal(mesh, mesh.faceOf(half)));
    if (!mesh.hasLiveTwin(half)) break;
    half = mesh.nextOf(mesh.twinOf(half));
    if (half == start) break;
  }
  final length = sum.length;
  return length < 1e-12 ? sum : sum
    ..scale(1 / length);
}

/// The length of the diagonal of [positions]' own bounding box — three
/// floats per vertex, [TriangleBvh.positions]' own shape.
double _diagonalOf(List<double> positions) {
  var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity, maxZ = -double.infinity;
  for (var i = 0; i < positions.length; i += 3) {
    final x = positions[i], y = positions[i + 1], z = positions[i + 2];
    if (x < minX) minX = x;
    if (y < minY) minY = y;
    if (z < minZ) minZ = z;
    if (x > maxX) maxX = x;
    if (y > maxY) maxY = y;
    if (z > maxZ) maxZ = z;
  }
  return Vector3(maxX - minX, maxY - minY, maxZ - minZ).length;
}
