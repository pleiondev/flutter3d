/// Running a new loop of edges across a strip of quads.
///
/// **A loop cut is two smaller operations repeated, and keeping them apart is
/// the point.** Every edge of the ring gets a vertex put on it
/// ([EditMesh.splitEdge]), and every quad between two of them gets cut in half
/// between the two new vertices ([EditMesh.splitFace]). Neither of those is a
/// loop cut on its own and both are useful on their own, so a cut that fused
/// them into one pass would be an operation nothing else could reuse.
///
/// **The ring decides where it stops, and quads are what it walks on.** A ring
/// steps across a face to the edge two along, which only means anything on a
/// four-sided face — so a cut through a strip of quads capped by a triangle
/// fan stops at the fan rather than running into it and cutting something
/// nobody pointed at. On a cylinder or a torus the ring closes and the cut goes
/// all the way round; on a flat strip it stops at both rims.
///
/// **Each rung is cut in the direction the walk arrived in.** Two quads in a
/// strip meet along an edge that one of them enters and the other leaves, and
/// splitting both at "a third of the way from the start" without minding which
/// end the start is would zig-zag the new loop across the strip. What keeps it
/// straight is that the half-edge the walk carries always begins on the same
/// side of the strip; the one place that is not available — the far rim of an
/// open strip, where there is no half-edge on the other side to carry — takes
/// the factor from the other end instead.
library;

import 'dart:typed_data';

import 'edit_mesh.dart';
import 'operations.dart';
import 'selection.dart';

/// Cuts one or more loops across the ring of quads the selected edge crosses.
///
/// [factor] is where the single cut goes, from the end of the edge a person
/// picked towards the other. With more than one cut they are spread evenly and
/// [factor] is not used: two cuts land at a third and two thirds, which is what
/// "two cuts" means everywhere it is offered.
OpResult loopCut(
  EditMesh mesh,
  Selection selection, {
  int cuts = 1,
  double factor = 0.5,
}) {
  if (cuts < 1) {
    return OpResult.refused(
      'a loop cut makes at least one loop',
      selection: selection,
    );
  }
  final edges = selection.convertedTo(mesh, ElementLevel.edge);
  if (edges.isEmpty) {
    return OpResult.refused(
      'no edge is selected to cut across',
      selection: selection,
    );
  }

  final picked = edges.active != EditMesh.none ? edges.active : edges.ids.first;
  var walking = _quadSideOf(mesh, picked);
  if (walking == EditMesh.none) {
    return OpResult.refused(
      'the edge has no four-sided face on it, so there is no ring to cut',
      selection: selection,
    );
  }

  final made = <int>[];
  for (var i = 0; i < cuts; i++) {
    // The cuts still to place, including this one, share what is left of the
    // edge: the first of three lands a third along, and the rest of the edge is
    // then two cuts wide.
    final along = cuts == 1 ? factor : 1 / (cuts - i + 1);
    final outcome = _cutOnce(mesh, walking, along);
    if (outcome == null) {
      return OpResult.refused(
        'the ring runs out before it comes back, and the cut would be partial',
        selection: selection,
      );
    }
    made.addAll(outcome.vertices);
    walking = outcome.far;
  }

  return OpResult.done(
    // What a person wants to move next is the loop they just made.
    selection: Selection.of(ElementLevel.vertex, made),
    movedVertices: Int32List.fromList(made..sort()),
    topologyChanged: true,
  );
}

/// The side of the edge [halfEdge] lies on that belongs to a four-sided face.
int _quadSideOf(EditMesh mesh, int halfEdge) {
  final face = mesh.faceOf(halfEdge);
  if (face != EditMesh.none &&
      mesh.isFaceAlive(face) &&
      mesh.valencyOf(face) == 4) {
    return halfEdge;
  }
  if (!mesh.hasLiveTwin(halfEdge)) return EditMesh.none;
  final twin = mesh.twinOf(halfEdge);
  return mesh.valencyOf(mesh.faceOf(twin)) == 4 ? twin : EditMesh.none;
}

/// What one loop left behind.
final class _Cut {
  const _Cut(this.vertices, this.far);

  /// The vertices the loop put on the ring's edges.
  final List<int> vertices;

  /// The half-edge covering the far part of the edge the walk started on, which
  /// is where the next cut of the same run begins.
  final int far;
}

_Cut? _cutOnce(EditMesh mesh, int halfEdge, double factor) {
  final rungs = <int>[];
  final along = <double>[];
  final guard = mesh.halfEdgeSlotCount + 1;

  rungs.add(halfEdge);
  along.add(factor);

  // Forward, quad by quad, until the ring closes or runs out.
  var closed = false;
  var walk = halfEdge;
  while (rungs.length <= guard) {
    final face = mesh.faceOf(walk);
    if (face == EditMesh.none || mesh.valencyOf(face) != 4) break;
    final across = mesh.nextOf(mesh.nextOf(walk));
    if (!mesh.hasLiveTwin(across)) {
      // The far rim: there is no half-edge on the other side to carry the
      // direction, so the factor is measured from the other end instead.
      rungs.add(across);
      along.add(1 - factor);
      break;
    }
    walk = mesh.twinOf(across);
    if (walk == halfEdge) {
      closed = true;
      break;
    }
    rungs.add(walk);
    along.add(factor);
  }
  if (rungs.length > guard) return null;

  if (!closed) {
    walk = halfEdge;
    while (rungs.length <= guard) {
      if (!mesh.hasLiveTwin(walk)) break;
      final behind = mesh.twinOf(walk);
      final face = mesh.faceOf(behind);
      if (face == EditMesh.none || mesh.valencyOf(face) != 4) break;
      final back = mesh.nextOf(mesh.nextOf(behind));
      rungs.insert(0, back);
      along.insert(0, factor);
      walk = back;
      if (walk == halfEdge) break;
    }
    if (rungs.length > guard) return null;
  }
  if (rungs.length < 2) return null;

  // Every rung gets its vertex before any face is cut: a face is cut between
  // two of them, and half a ring of vertices cannot say where.
  final middles = <int>[];
  var far = EditMesh.none;
  for (var i = 0; i < rungs.length; i++) {
    final middle = mesh.splitEdge(rungs[i], factor: along[i]);
    if (middle == EditMesh.none) return null;
    middles.add(middle);
    if (rungs[i] == halfEdge) far = mesh.nextOf(halfEdge);
  }

  final quads = closed ? rungs.length : rungs.length - 1;
  for (var i = 0; i < quads; i++) {
    final face = mesh.faceOf(rungs[i]);
    final from = _cornerAt(mesh, face, middles[i]);
    final to = _cornerAt(mesh, face, middles[(i + 1) % middles.length]);
    if (from == EditMesh.none || to == EditMesh.none) return null;
    mesh.splitFace(face, from, to);
  }

  return _Cut(middles, far);
}

/// The half-edge of [face] that starts at [vertex].
int _cornerAt(EditMesh mesh, int face, int vertex) {
  var found = EditMesh.none;
  mesh.forEachHalfEdge(face, (int half) {
    if (mesh.originOf(half) == vertex) found = half;
  });
  return found;
}
