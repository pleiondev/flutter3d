/// Pushing faces and edges out, and walling in the gap behind them.
///
/// **The faces do not move; they are detached and then move.** An extrusion of
/// one face of a box is not "the face slides along its normal" — that would
/// stretch the four faces around it. It is: the face lets go of its neighbours,
/// grows its own copies of the vertices it shared with them, walls are built
/// across the gap, and the copies move. A box's face extruded that way gives
/// twelve vertices, twenty edges and ten faces where there were eight, twelve
/// and six, and χ is still 2.
///
/// **A region is extruded as one thing.** Two faces side by side share an edge
/// that is inside the selection, and no wall is built there — six walls for two
/// quads, not eight, and the seam between them stays a seam. Extruding them one
/// at a time is a different operation and a different answer, so it is a
/// different argument.
///
/// **What the walls inherit, and what they do not.** Colour, material slot and
/// the smoothing flag come from the face the wall grew out of; that is
/// `mesh-12`'s rule, and a wall that shaded differently from the face above it
/// would be visible immediately. Texture coordinates do not: a wall is a
/// surface that did not exist, and the source face's place in a texture says
/// nothing about it. So a wall is unwrapped as its own unit square — across the
/// edge in u, up the extrusion in v — which is `mesh-23`'s own rule and the one
/// a person can predict. Laying the walls of a region out as one continuous
/// strip is an unwrap, and `pro-uv-02` is where unwraps live.
library;

import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'attributes.dart';
import 'edit_mesh.dart';
import 'operations.dart';
import 'selection.dart';

/// Pushes the selected faces out along their own normal by [distance].
///
/// With [individual], each face is extruded on its own — every one of them gets
/// its own copies of every corner and its own four walls, so a row of quads
/// becomes a row of separate boxes rather than one raised slab.
///
/// A distance of zero is not a no-op: the faces are still detached and the
/// walls are still built, standing at no height. That is what an interactive
/// extrusion is — press the key, then drag — and `translateSelection` over the
/// result is the drag.
OpResult extrudeFaces(
  EditMesh mesh,
  Selection selection, {
  required double distance,
  bool individual = false,
}) {
  final faces = selection.convertedTo(mesh, ElementLevel.face);
  if (faces.isEmpty) {
    return OpResult.refused(
      'no faces are selected to extrude',
      selection: selection,
    );
  }

  final moved = <int>{};
  if (individual) {
    for (final face in faces.ids) {
      final report = _extrudeRegion(mesh, <int>[face], distance);
      if (report != null) return OpResult.refused(report, selection: selection);
      moved.addAll(_lastMoved);
    }
  } else {
    final report = _extrudeRegion(mesh, faces.ids, distance);
    if (report != null) return OpResult.refused(report, selection: selection);
    moved.addAll(_lastMoved);
  }

  return OpResult.done(
    // The same faces: they were rewired onto new vertices rather than replaced,
    // so what a person selected is what they can now drag.
    selection: faces,
    movedVertices: Int32List.fromList(moved.toList()..sort()),
    topologyChanged: true,
  );
}

/// Pushes the selected boundary edges out by [by], leaving a quad behind each.
///
/// **Boundary edges only, and the refusal is the point.** An edge with a face
/// on both sides has no free side to grow a quad into; extruding it would mean
/// splitting the surface open, which is a different operation nobody asked for.
/// An edge on the rim of a sheet has exactly one, and widening a sheet by
/// pulling its rim is what this is for.
OpResult extrudeEdges(
  EditMesh mesh,
  Selection selection, {
  required Vector3 by,
}) {
  final edges = selection.convertedTo(mesh, ElementLevel.edge);
  final rim = <int>[
    for (final edge in edges.ids)
      if (!mesh.hasLiveTwin(edge)) edge,
  ];
  if (rim.isEmpty) {
    return OpResult.refused(
      edges.isEmpty
          ? 'no edges are selected to extrude'
          : 'every selected edge has a face on both sides',
      selection: selection,
    );
  }

  // The old vertices stay on the sheet; the copies are what moves, so the quad
  // between them is the new surface rather than a stretched old one.
  final copy = <int, int>{};
  int copied(int vertex) =>
      copy.putIfAbsent(vertex, () => mesh.addVertex(mesh.positionOf(vertex)));

  final made = <int>[];
  final firsts = <int>[];
  final from = <int>[];
  final to = <int>[];
  for (final edge in rim) {
    from.add(mesh.originOf(edge));
    to.add(mesh.originOf(mesh.nextOf(edge)));
    final liftedFrom = copied(from.last);
    final liftedTo = copied(to.last);
    final first = mesh.halfEdgeSlotCount;
    // Wound the other way round from the edge, because the quad is on the far
    // side of it from the face that already uses it.
    final wall = mesh.addFace(<int>[to.last, from.last, liftedFrom, liftedTo]);
    mesh.weldTwins(first, edge);
    _inheritWall(mesh, wall, first, mesh.faceOf(edge), mesh.nextOf(edge), edge);
    made.add(wall);
    firsts.add(first);
  }

  // Two rim edges meeting at a corner leave two uprights standing on it: the
  // one arriving on the earlier wall and the one leaving on the later.
  final wallAt = <int, int>{for (var i = 0; i < from.length; i++) from[i]: i};
  for (var i = 0; i < rim.length; i++) {
    final next = wallAt[to[i]];
    if (next == null || next == i) continue;
    mesh.weldTwins(firsts[i] + 3, firsts[next] + 1);
  }

  for (final vertex in copy.values) {
    mesh.moveVertex(vertex, mesh.positionOf(vertex)..add(by));
  }

  return OpResult.done(
    selection: Selection.of(ElementLevel.face, made),
    movedVertices: Int32List.fromList(copy.values.toList()..sort()),
    topologyChanged: true,
  );
}

/// The vertices the last region left standing in a new place.
List<int> _lastMoved = <int>[];

/// Detaches [faces] from everything around them, walls the gap and lifts them.
///
/// Returns null when it worked, or the sentence to show somebody.
String? _extrudeRegion(EditMesh mesh, List<int> faces, double distance) {
  final region = faces.toSet();

  // The half-edges of the region that have something other than the region on
  // the far side. These are where walls go; everything else stays joined.
  final boundary = <int>[];
  final outside = <int>[];
  final from = <int>[];
  final to = <int>[];
  final startsAt = <int, int>{};
  for (final face in faces) {
    if (!mesh.isFaceAlive(face)) return 'a selected face is no longer there';
    String? refusal;
    mesh.forEachHalfEdge(face, (int half) {
      final twin = mesh.twinOf(half);
      final behind = mesh.hasLiveTwin(half) ? mesh.faceOf(twin) : EditMesh.none;
      if (behind != EditMesh.none && region.contains(behind)) return;
      final origin = mesh.originOf(half);
      if (startsAt.containsKey(origin)) {
        refusal = 'the selected region touches itself at a corner';
        return;
      }
      startsAt[origin] = boundary.length;
      boundary.add(half);
      outside.add(mesh.hasLiveTwin(half) ? twin : EditMesh.none);
      from.add(origin);
      to.add(mesh.originOf(mesh.nextOf(half)));
    });
    if (refusal != null) return refusal;
  }
  if (boundary.isEmpty) {
    return 'the selected faces are a closed surface with no rim to wall in';
  }

  // Which vertices leave the old surface behind. A vertex inside the region
  // belongs to nothing else, so it simply moves; one on the rim is shared, and
  // the copy is what the region keeps.
  final lifted = <int, int>{};
  for (final vertex in from) {
    lifted[vertex] = mesh.addVertex(mesh.positionOf(vertex));
  }
  final interior = <int>[];
  for (final face in faces) {
    mesh.forEachVertex(face, (int vertex) {
      if (lifted.containsKey(vertex)) return;
      lifted[vertex] = vertex;
      interior.add(vertex);
    });
  }

  final normal = _regionNormal(mesh, faces);
  for (final face in faces) {
    mesh.forEachHalfEdge(face, (int half) {
      mesh.setOrigin(half, lifted[mesh.originOf(half)]!);
    });
  }

  final firsts = <int>[];
  for (var i = 0; i < boundary.length; i++) {
    final first = mesh.halfEdgeSlotCount;
    final wall = mesh.addFace(<int>[
      from[i],
      to[i],
      lifted[to[i]]!,
      lifted[from[i]]!,
    ]);
    firsts.add(first);
    // The wall takes over from the region on both sides: the outside keeps the
    // edge it always had, and the region's own half-edge now faces the wall.
    if (outside[i] != EditMesh.none) mesh.weldTwins(first, outside[i]);
    mesh.weldTwins(first + 2, boundary[i]);
    _inheritWall(
      mesh,
      wall,
      first,
      mesh.faceOf(boundary[i]),
      boundary[i],
      mesh.nextOf(boundary[i]),
    );
    // The old vertex is no longer on any face of the region, so its way into
    // the mesh has to be the wall.
    mesh.setOutgoing(from[i], first);
  }

  // The wall over the boundary edge leaving each corner, so the wall arriving
  // there knows what its upright meets. Read from the vertices the walk wrote
  // down, not from the half-edges: those have just been moved onto the copies.
  final wallAt = <int, int>{for (var i = 0; i < from.length; i++) from[i]: i};
  for (var i = 0; i < boundary.length; i++) {
    final next = wallAt[to[i]];
    if (next == null || next == i) continue;
    mesh.weldTwins(firsts[i] + 1, firsts[next] + 3);
  }

  final offset = normal..scale(distance);
  final at = Vector3.zero();
  final moved = <int>[];
  for (final entry in lifted.entries) {
    mesh.moveVertex(entry.value, mesh.positionOf(entry.value, at)..add(offset));
    moved.add(entry.value);
  }
  _lastMoved = moved;
  return null;
}

/// Gives a wall the shading and the material of the face it grew out of, and a
/// unit square of texture of its own.
void _inheritWall(
  EditMesh mesh,
  int wall,
  int first,
  int source,
  int atFrom,
  int atTo,
) {
  if (mesh.hasLayer(MeshDomain.face, MeshAttribute.materialSlot)) {
    mesh.setMaterialSlot(wall, mesh.materialSlotOf(source));
  }
  if (mesh.hasLayer(MeshDomain.face, MeshAttribute.flags)) {
    mesh.setFaceFlag(
      wall,
      FaceFlags.smooth,
      on: mesh.faceHas(source, FaceFlags.smooth),
    );
  }
  if (mesh.hasLayer(MeshDomain.corner, MeshAttribute.colour)) {
    final low = mesh.colourOf(atFrom);
    final high = mesh.colourOf(atTo);
    mesh
      ..setColour(first, low)
      ..setColour(first + 1, high)
      ..setColour(first + 2, high)
      ..setColour(first + 3, low);
  }
  if (mesh.hasLayer(MeshDomain.corner, MeshAttribute.uv0)) {
    mesh
      ..setUv(first, Vector2(0, 0))
      ..setUv(first + 1, Vector2(1, 0))
      ..setUv(first + 2, Vector2(1, 1))
      ..setUv(first + 3, Vector2(0, 1));
  }
}

/// The direction a region of faces faces, weighted by how much of it each face
/// is.
///
/// By area, so a big face and a sliver beside it do not get an equal say — the
/// same argument the corner normals use, and the same failure without it: a
/// region extruded along the average of its face normals would tilt towards
/// whichever part of it happened to be cut finer.
Vector3 _regionNormal(EditMesh mesh, List<int> faces) {
  final total = Vector3.zero();
  final normal = Vector3.zero();
  for (final face in faces) {
    mesh.normalOf(face, normal);
    total.add(normal..scale(mesh.areaOf(face)));
  }
  final length = total.length;
  return length == 0 ? Vector3(0, 1, 0) : (total..scale(1 / length));
}
