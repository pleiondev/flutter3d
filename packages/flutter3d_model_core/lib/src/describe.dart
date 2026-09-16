/// Elements said in numbers — where each one is, which way it faces, how big
/// it is (`ux-19`).
///
/// **The call that makes an agent's first edit something other than a
/// guess.** `list` names objects and `select` takes element ids, and between
/// those two there was nothing: an agent asked to extrude the top face of a
/// cube could select face 0, 1, 2, 3, 4 or 5 and had no way at all to find out
/// which of them pointed up. The review (§5.1) watched it pick one, render,
/// look at the picture and try again — three calls and a rasterised image to
/// answer a question the mesh already knows the answer to.
///
/// **Numbers, not a picture.** Every field here is something [EditMesh]
/// already computes for its own operations — [EditMesh.normalOf],
/// [EditMesh.areaOf], [EditMesh.positionOf] — so describing a face costs what
/// extruding it costs to set up, and nothing has to be drawn.
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:vector_math/vector_math.dart';

/// One element, in the object's own space.
///
/// **One record for all three levels rather than three types**, because the
/// question is the same at each — where is it, which way does it face, how big
/// is it — and only the answer to the last one changes name. [area] is a
/// face's; [length] is an edge's; a vertex has neither, and says so by leaving
/// both null rather than by being a different type an agent has to branch on.
typedef DescribedElement = ({
  int id,
  Vector3 at,
  Vector3? normal,
  double? area,
  double? length,
});

/// [ids] of [level] in [mesh], described — or, with no [ids], every live
/// element of that level up to [limit].
///
/// **[limit] is a cap on the answer, not a page.** An agent describing a
/// 200 000-face import wants to know what the first few faces look like and
/// then to ask about the ones it cares about by id; handing it two hundred
/// thousand records would cost more context than the whole rest of the
/// session. A caller that knows which elements it means passes [ids] and gets
/// all of them, [limit] or no [limit] — naming an element is already knowing
/// how many came back.
///
/// A dead element — a face somebody deleted, a vertex left over from a merge —
/// is skipped rather than described as a row of zeroes, whether it was named
/// in [ids] or swept up by the sweep. An id that names nothing simply is not
/// in the answer, which is how a caller finds out it was stale.
List<DescribedElement> describeElements(
  EditMesh mesh,
  ElementLevel level, {
  Iterable<int>? ids,
  int limit = 50,
}) {
  final List<int> wanted = ids == null
      ? liveElements(mesh, level).take(limit).toList()
      : ids.toList();
  return <DescribedElement>[
    for (final int id in wanted)
      if (_describe(mesh, level, id) case final DescribedElement described)
        described,
  ];
}

/// Every live element of [level], each exactly once, in id order.
///
/// **Lazy, so a caller that wants the first ten pays for ten.** That is what
/// [describeElements]'s own cap does with it; a selection command that wants
/// all of them walks all of them and allocates nothing but the ids it keeps.
Iterable<int> liveElements(EditMesh mesh, ElementLevel level) sync* {
  switch (level) {
    case ElementLevel.vertex:
      for (var vertex = 0; vertex < mesh.vertexSlotCount; vertex++) {
        if (mesh.isVertexAlive(vertex)) yield vertex;
      }
    case ElementLevel.face:
      for (var face = 0; face < mesh.faceSlotCount; face++) {
        if (mesh.isFaceAlive(face)) yield face;
      }
    case ElementLevel.edge:
      // An edge is not stored — see `EditMesh.edgeOf`. Sweeping the live
      // faces' own half-edges and keeping only the canonical one of each
      // twinned pair visits every edge exactly once, which is the same walk
      // `selection_commands.dart`'s own `_everyEdge` does and for the same
      // reason.
      final seen = <int>{};
      for (var face = 0; face < mesh.faceSlotCount; face++) {
        if (!mesh.isFaceAlive(face)) continue;
        final List<int> halves = <int>[];
        mesh.forEachHalfEdge(face, halves.add);
        for (final int half in halves) {
          final int edge = mesh.edgeOf(half);
          if (seen.add(edge)) yield edge;
        }
      }
  }
}

/// Where [id] of [level] is, in the object's own space — a vertex's position,
/// an edge's midpoint, a face's centroid — or null when nothing there is
/// alive.
///
/// **Public because a selection command wants exactly this and nothing
/// else.** `SelectNear` measures a distance per element and `SelectFacing`
/// takes a dot product per face; building a whole [DescribedElement] for each
/// one to read a single field out of it would allocate a record per element on
/// a mesh with two hundred thousand of them. So the two facts a caller can
/// want on their own have names of their own, and [describeElements] is what
/// gathers all of them at once.
Vector3? elementCentre(EditMesh mesh, ElementLevel level, int id) =>
    switch (level) {
      ElementLevel.vertex =>
        _liveVertex(mesh, id) ? mesh.positionOf(id) : null,
      ElementLevel.face =>
        _liveFace(mesh, id) ? _centre(mesh, mesh.verticesOf(id)) : null,
      ElementLevel.edge => _edgeMidpoint(mesh, id),
    };

/// Which way [id] of [level] faces, or null when nothing decides it: a vertex
/// in no face, an edge whose two sides cancel out.
Vector3? elementNormal(EditMesh mesh, ElementLevel level, int id) =>
    switch (level) {
      ElementLevel.vertex =>
        _liveVertex(mesh, id) ? _vertexNormal(mesh, id) : null,
      ElementLevel.face => _liveFace(mesh, id) ? mesh.normalOf(id) : null,
      ElementLevel.edge => _describeEdge(mesh, id)?.normal,
    };

bool _liveVertex(EditMesh mesh, int id) =>
    id >= 0 && id < mesh.vertexSlotCount && mesh.isVertexAlive(id);

bool _liveFace(EditMesh mesh, int id) =>
    id >= 0 && id < mesh.faceSlotCount && mesh.isFaceAlive(id);

Vector3? _edgeMidpoint(EditMesh mesh, int id) => _describeEdge(mesh, id)?.at;

DescribedElement? _describe(EditMesh mesh, ElementLevel level, int id) =>
    switch (level) {
      ElementLevel.vertex =>
        !_liveVertex(mesh, id)
            ? null
            : (
                id: id,
                at: mesh.positionOf(id),
                normal: _vertexNormal(mesh, id),
                area: null,
                length: null,
              ),
      ElementLevel.face =>
        !_liveFace(mesh, id)
            ? null
            : (
                id: id,
                at: _centre(mesh, mesh.verticesOf(id)),
                normal: mesh.normalOf(id),
                area: mesh.areaOf(id),
                length: null,
              ),
      ElementLevel.edge => _describeEdge(mesh, id),
    };

DescribedElement? _describeEdge(EditMesh mesh, int id) {
  if (id < 0 || id >= mesh.halfEdgeSlotCount) return null;
  final int half = mesh.edgeOf(id);
  final int face = mesh.faceOf(half);
  if (face == EditMesh.none || !mesh.isFaceAlive(face)) return null;
  final Vector3 from = mesh.positionOf(mesh.originOf(half));
  final Vector3 to = mesh.positionOf(mesh.originOf(mesh.nextOf(half)));
  // Both sides, because an edge between two faces faces neither of them: the
  // direction a person means by "which way does this edge face" is the way
  // the surface goes there, which is the average.
  final normals = <Vector3>[
    mesh.normalOf(face),
    if (mesh.hasLiveTwin(half))
      mesh.normalOf(mesh.faceOf(mesh.twinOf(half))),
  ];
  return (
    id: half,
    at: (from + to)..scale(0.5),
    normal: _averaged(normals),
    area: null,
    length: (to - from).length,
  );
}

/// The average of the normals of every live face this vertex is a corner of,
/// or null for a vertex in no face at all — the loose one a merge left
/// behind, which has a position and nothing else.
Vector3? _vertexNormal(EditMesh mesh, int vertex) {
  final int start = mesh.outgoingOf(vertex);
  if (start == EditMesh.none) return null;
  final normals = <Vector3>[];
  var half = start;
  while (true) {
    final int face = mesh.faceOf(half);
    if (face != EditMesh.none && mesh.isFaceAlive(face)) {
      normals.add(mesh.normalOf(face));
    }
    if (!mesh.hasLiveTwin(half)) break;
    half = mesh.nextOf(mesh.twinOf(half));
    if (half == start) break;
  }
  return _averaged(normals);
}

Vector3? _averaged(List<Vector3> normals) {
  if (normals.isEmpty) return null;
  final sum = Vector3.zero();
  for (final Vector3 each in normals) {
    sum.add(each);
  }
  // A sum that cancels out — the two sides of a zero-thickness sheet — has no
  // direction to report, and normalising it would report a random one.
  return sum.length2 < 1e-12 ? null : (sum..normalize());
}

Vector3 _centre(EditMesh mesh, List<int> vertices) {
  if (vertices.isEmpty) return Vector3.zero();
  final sum = Vector3.zero();
  for (final int vertex in vertices) {
    sum.add(mesh.positionOf(vertex));
  }
  return sum..scale(1.0 / vertices.length);
}

/// The box around every live vertex of [mesh], or null for a mesh with none.
///
/// What `describe` says about an object as a whole: an agent that knows a
/// model is two metres tall and centred on the origin can place a light, aim a
/// camera and pick a bevel width without rendering anything first.
Aabb3? boundsOfMesh(EditMesh mesh) {
  var found = false;
  final min = Vector3.all(double.infinity);
  final max = Vector3.all(double.negativeInfinity);
  final at = Vector3.zero();
  for (var vertex = 0; vertex < mesh.vertexSlotCount; vertex++) {
    if (!mesh.isVertexAlive(vertex)) continue;
    mesh.positionOf(vertex, at);
    found = true;
    Vector3.min(min, at, min);
    Vector3.max(max, at, max);
  }
  return found ? Aabb3.minMax(min, max) : null;
}
