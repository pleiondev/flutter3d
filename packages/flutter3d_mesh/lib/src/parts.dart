/// Taking a mesh apart, and putting copies of pieces back.
///
/// **Four operations that are one question asked four ways: what belongs with
/// what.** Deleting takes a piece away and everything left standing on nothing
/// with it. Splitting leaves a piece where it is and stops it sharing anything
/// with its neighbours. Duplicating makes a second copy of a piece in the same
/// mesh. Separating hands each island back as a mesh of its own.
///
/// **Deleting cleans up after itself, and that is the whole difference between
/// this and marking a face dead.** A face removed from a box leaves four
/// corners still in use by the faces around it and nothing to tidy; the same
/// face removed from a lone quad leaves four corners no face reaches, and a
/// mesh carrying those is a mesh whose vertex count, bounding box and export
/// all describe geometry that is not there.
library;

import 'dart:typed_data';

import 'attributes.dart';
import 'edit_mesh.dart';
import 'operations.dart';
import 'selection.dart';

/// Removes what is selected, and whatever is left holding nothing up.
///
/// **What "delete" means depends on the level, and the three answers are not
/// variations of one.** Deleting faces takes the faces; the vertices stay
/// wherever another face still uses them. Deleting vertices takes every face
/// that named them, because a face missing a corner is not a face. Deleting
/// edges is the same argument one level down. This is what every modeller does
/// and the reason is the same in all of them: the level a person is working at
/// is the level they mean.
OpResult deleteSelection(EditMesh mesh, Selection selection) {
  if (selection.isEmpty) {
    return OpResult.refused('nothing is selected', selection: selection);
  }

  final doomed = <int>{};
  switch (selection.level) {
    case ElementLevel.face:
      doomed.addAll(selection.ids);
    case ElementLevel.vertex:
      final standing = _verticesOf(mesh, selection);
      for (var face = 0; face < mesh.faceSlotCount; face++) {
        if (!mesh.isFaceAlive(face)) continue;
        mesh.forEachVertex(face, (int vertex) {
          if (standing[vertex]) doomed.add(face);
        });
      }
    case ElementLevel.edge:
      // The faces that use the edge, not the faces that touch its ends. On a
      // box the difference is two faces against four: the two more are the
      // ones standing on a corner of it, which nobody asked about.
      for (var face = 0; face < mesh.faceSlotCount; face++) {
        if (!mesh.isFaceAlive(face)) continue;
        mesh.forEachHalfEdge(face, (int half) {
          if (selection.contains(mesh.edgeOf(half))) doomed.add(face);
        });
      }
  }

  for (final face in doomed) {
    mesh.deleteFace(face);
  }

  // Everything a live face still names stays; the rest goes, whether it was
  // selected or was only holding up something that was.
  final kept = List<bool>.filled(mesh.vertexSlotCount, false);
  for (var face = 0; face < mesh.faceSlotCount; face++) {
    if (!mesh.isFaceAlive(face)) continue;
    mesh.forEachVertex(face, (int vertex) => kept[vertex] = true);
  }
  for (var vertex = 0; vertex < mesh.vertexSlotCount; vertex++) {
    if (mesh.isVertexAlive(vertex) && !kept[vertex]) mesh.deleteVertex(vertex);
  }
  mesh.repairVertexLinks();

  return OpResult.done(
    selection: Selection.empty(selection.level),
    topologyChanged: true,
  );
}

/// Makes a second copy of the selected faces in the same mesh.
///
/// The copy stands exactly where the original does and shares nothing with it —
/// which is what a person expects to then drag away. Everything the faces
/// carried comes with them.
OpResult duplicateSelection(EditMesh mesh, Selection selection) {
  final faces = selection.convertedTo(mesh, ElementLevel.face);
  if (faces.isEmpty) {
    return OpResult.refused(
      'no faces are selected to duplicate',
      selection: selection,
    );
  }

  final copyOf = <int, int>{};
  final made = <int>[];
  final sources = <List<int>>[];
  final firsts = <int>[];

  for (final face in faces.ids) {
    final loop = <int>[];
    final corners = <int>[];
    mesh.forEachHalfEdge(face, (int half) {
      final vertex = mesh.originOf(half);
      loop.add(
        copyOf.putIfAbsent(
          vertex,
          () => mesh.addVertex(mesh.positionOf(vertex)),
        ),
      );
      corners.add(half);
    });
    final first = mesh.halfEdgeSlotCount;
    made.add(mesh.addFace(loop));
    firsts.add(first);
    sources.add(corners);
  }

  // The copies are joined to each other wherever the originals were joined to
  // each other, and to nothing else — a copied region comes away as one piece
  // rather than a heap of loose faces.
  final copyHalf = <int, int>{};
  for (var i = 0; i < made.length; i++) {
    for (var corner = 0; corner < sources[i].length; corner++) {
      copyHalf[sources[i][corner]] = firsts[i] + corner;
    }
  }
  for (final entry in copyHalf.entries) {
    if (!mesh.hasLiveTwin(entry.key)) continue;
    final partner = copyHalf[mesh.twinOf(entry.key)];
    if (partner != null) mesh.weldTwins(entry.value, partner);
  }

  for (var i = 0; i < made.length; i++) {
    _carryFace(mesh, mesh, faces.ids[i], made[i], sources[i], firsts[i]);
  }
  for (final entry in copyOf.entries) {
    _carryVertex(mesh, mesh, entry.key, entry.value);
  }

  return OpResult.done(
    selection: Selection.of(ElementLevel.face, made),
    movedVertices: Int32List.fromList(copyOf.values.toList()..sort()),
    topologyChanged: true,
  );
}

/// Stops the selected faces sharing anything with the faces around them,
/// leaving both pieces exactly where they are.
///
/// **The counts do not change and the picture does not either**, which is what
/// makes this hard to see and worth reporting: what changes is that a vertex
/// somebody drags now takes one side with it and not the other. A vertex the
/// selection shares with a face outside it is duplicated; a vertex only the
/// selection uses is already its own.
OpResult splitSelection(EditMesh mesh, Selection selection) {
  final faces = selection.convertedTo(mesh, ElementLevel.face);
  if (faces.isEmpty) {
    return OpResult.refused(
      'no faces are selected to split off',
      selection: selection,
    );
  }
  final region = faces.ids.toSet();

  // A vertex is shared when some face outside the region stands on it.
  final outside = List<bool>.filled(mesh.vertexSlotCount, false);
  for (var face = 0; face < mesh.faceSlotCount; face++) {
    if (!mesh.isFaceAlive(face) || region.contains(face)) continue;
    mesh.forEachVertex(face, (int vertex) => outside[vertex] = true);
  }

  final ownCopy = <int, int>{};
  for (final face in faces.ids) {
    mesh.forEachVertex(face, (int vertex) {
      if (!outside[vertex]) return;
      ownCopy.putIfAbsent(vertex, () {
        final copy = mesh.addVertex(mesh.positionOf(vertex));
        _carryVertex(mesh, mesh, vertex, copy);
        return copy;
      });
    });
  }
  if (ownCopy.isEmpty) {
    return OpResult.refused(
      'the selected faces already share nothing with the rest',
      selection: selection,
    );
  }

  for (final face in faces.ids) {
    mesh.forEachHalfEdge(face, (int half) {
      final copy = ownCopy[mesh.originOf(half)];
      if (copy != null) mesh.setOrigin(half, copy);
      // Whatever was on the far side of this edge is no longer behind it.
      if (mesh.hasLiveTwin(half) &&
          !region.contains(mesh.faceOf(mesh.twinOf(half)))) {
        mesh.cutTwin(half);
      }
    });
  }
  mesh.repairVertexLinks();

  return OpResult.done(
    selection: faces,
    movedVertices: Int32List.fromList(ownCopy.values.toList()..sort()),
    topologyChanged: true,
  );
}

/// Every island of [mesh] as a mesh of its own, with the map from the old
/// numbers to the new.
///
/// **In the order their lowest-numbered face appears**, so a document that
/// separates a model twice gets the same pieces in the same order both times —
/// which is what makes a test of it possible and a file that names them stable.
List<(EditMesh, IdRemap)> separateComponents(EditMesh mesh) {
  final island = Int32List(mesh.faceSlotCount)
    ..fillRange(0, mesh.faceSlotCount, EditMesh.none);
  final parts = <List<int>>[];

  for (var seed = 0; seed < mesh.faceSlotCount; seed++) {
    if (!mesh.isFaceAlive(seed) || island[seed] != EditMesh.none) continue;
    // Joined through vertices rather than through edges, which is what
    // `Selection.linked` means by an island and what a person means by a loose
    // part: two boxes meeting at one corner are one thing to pick up.
    final reached = Selection.of(ElementLevel.face, <int>[seed]).linked(mesh);
    final id = parts.length;
    parts.add(<int>[]);
    for (final face in reached.ids) {
      island[face] = id;
      parts[id].add(face);
    }
  }

  return <(EditMesh, IdRemap)>[for (final part in parts) subMesh(mesh, part)];
}

/// The faces [wanted] as a mesh of their own, and where everything went.
///
/// **A rebuild, so the numbering starts again**, which is why the [IdRemap]
/// comes with it: a selection or an id somebody was holding means nothing in
/// the piece that came out. The same rule `EditMesh.compact` follows, and the
/// same reason — a journal is indices into arrays that have just been
/// renumbered, so the piece has no history.
(EditMesh, IdRemap) subMesh(EditMesh mesh, Iterable<int> wanted) {
  final vertexMap = Int32List(mesh.vertexSlotCount)
    ..fillRange(0, mesh.vertexSlotCount, EditMesh.none);
  final faceMap = Int32List(mesh.faceSlotCount)
    ..fillRange(0, mesh.faceSlotCount, EditMesh.none);

  final builder = EditMeshBuilder();
  final sources = <int>[];
  final taken = <int>[];
  final corners = <List<int>>[];

  for (final face in wanted) {
    if (!mesh.isFaceAlive(face)) continue;
    final loop = <int>[];
    final from = <int>[];
    mesh.forEachHalfEdge(face, (int half) {
      final vertex = mesh.originOf(half);
      if (vertexMap[vertex] == EditMesh.none) {
        vertexMap[vertex] = builder.addVertex(mesh.positionOf(vertex));
        sources.add(vertex);
      }
      loop.add(vertexMap[vertex]);
      from.add(half);
    });
    faceMap[face] = builder.faceCount;
    builder.addFace(loop);
    taken.add(face);
    corners.add(from);
  }

  final part = _finish(builder, mesh, taken, corners, sources);
  return (part, IdRemap(vertices: vertexMap, faces: faceMap));
}

/// Builds the piece and gives it everything the mesh it came from carried.
///
/// Split out from [subMesh] only so the copying has a name: it is the half that
/// is easy to leave out, and leaving it out loses every material assignment and
/// every texture coordinate in the document the first time somebody separates
/// a model.
EditMesh _finish(
  EditMeshBuilder builder,
  EditMesh mesh,
  List<int> faces,
  List<List<int>> corners,
  List<int> vertices,
) {
  final part = builder.build();
  part.beginStep();
  for (var face = 0; face < faces.length; face++) {
    var corner = 0;
    part.forEachHalfEdge(face, (int half) {
      _carryCorner(mesh, part, corners[face][corner++], half);
    });
    _carryFaceOnly(mesh, part, faces[face], face);
  }
  for (var vertex = 0; vertex < vertices.length; vertex++) {
    _carryVertex(mesh, part, vertices[vertex], vertex);
  }
  part.endStep();
  part.clearJournal();
  return part;
}

/// Every vertex the selection stands on, as a flag per vertex slot.
List<bool> _verticesOf(EditMesh mesh, Selection selection) {
  final marked = List<bool>.filled(mesh.vertexSlotCount, false);
  final vertices = selection.convertedTo(mesh, ElementLevel.vertex);
  for (final vertex in vertices.ids) {
    marked[vertex] = true;
  }
  return marked;
}

void _carryFace(
  EditMesh from,
  EditMesh to,
  int source,
  int face,
  List<int> corners,
  int first,
) {
  _carryFaceOnly(from, to, source, face);
  for (var corner = 0; corner < corners.length; corner++) {
    _carryCorner(from, to, corners[corner], first + corner);
  }
}

void _carryFaceOnly(EditMesh from, EditMesh to, int source, int face) {
  if (from.hasLayer(MeshDomain.face, MeshAttribute.materialSlot)) {
    to.setMaterialSlot(face, from.materialSlotOf(source));
  }
  if (from.hasLayer(MeshDomain.face, MeshAttribute.flags)) {
    to.setFaceFlag(
      face,
      FaceFlags.smooth,
      on: from.faceHas(source, FaceFlags.smooth),
    );
  }
}

void _carryCorner(EditMesh from, EditMesh to, int source, int half) {
  if (from.hasLayer(MeshDomain.corner, MeshAttribute.uv0) ||
      from.hasLayer(MeshDomain.corner, MeshAttribute.colour)) {
    to.setCorner(half, from.cornerOf(source));
  }
  if (from.hasLayer(MeshDomain.edge, MeshAttribute.crease)) {
    to.setCrease(half, from.creaseOf(source));
  }
  if (from.hasLayer(MeshDomain.edge, MeshAttribute.flags)) {
    for (final flag in <int>[EdgeFlags.sharp, EdgeFlags.seam]) {
      to.setEdgeFlag(half, flag, on: from.edgeHas(source, flag));
    }
  }
}

void _carryVertex(EditMesh from, EditMesh to, int source, int vertex) {
  if (from.hasLayer(MeshDomain.vertex, MeshAttribute.weights) ||
      from.hasLayer(MeshDomain.vertex, MeshAttribute.joints)) {
    to.setSkin(vertex, from.skinOf(source));
  }
}
