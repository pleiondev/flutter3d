/// Moving a loop along the edges that cross it — `ux-39`.
///
/// **Topology never changes.** That is the whole of what makes this
/// different from every other way of moving a vertex: a slid loop keeps its
/// own faces, keeps the faces either side of it, and only ever travels the
/// rails it is already attached to. It is how a seam is nudged to where a
/// detail wants it without re-cutting the mesh around it.
///
/// **Which rail is "forward" is decided by the mesh, not by the camera.**
/// Each vertex has exactly two rails — the two edges leaving it that are not
/// part of the selection — and the lower-numbered of the two is the positive
/// direction. That is arbitrary in the sense that any rule would be, and it
/// is stable in the sense that matters: the same drag on the same loop slides
/// the same way every time, whichever direction the model is being viewed
/// from and however many times the operation has been undone.
library;

import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'edit_mesh.dart';
import 'operations.dart';
import 'selection.dart';

/// Slides the loop [selection] names along its rails by [amount], a fraction
/// of the rail's own length in `[-1, 1]`.
///
/// **A fraction, not a distance.** The rails around a loop are rarely all
/// the same length, and sliding each vertex the same number of millimetres
/// would pull a loop out of shape wherever the mesh is denser on one side.
/// A fraction keeps the loop's own proportions, which is what somebody
/// dragging it is watching.
OpResult slideEdges(
  EditMesh mesh,
  Selection selection, {
  required double amount,
}) {
  final edges = selection.convertedTo(mesh, ElementLevel.edge);
  if (edges.isEmpty) {
    return OpResult.refused(
      'no edges are selected to slide',
      selection: selection,
    );
  }

  // Both ends of every selected edge move, and a vertex named twice moves
  // once: a loop's own vertices are each shared by two of its edges.
  final onLoop = <int>{};
  final selected = <int>{};
  for (final int edge in edges.ids) {
    selected.add(mesh.edgeOf(edge));
    onLoop
      ..add(mesh.originOf(edge))
      ..add(mesh.originOf(mesh.nextOf(edge)));
  }

  final Map<int, Vector3> destinations = <int, Vector3>{};
  for (final int vertex in onLoop) {
    final List<int> rails = <int>[
      for (final int neighbor in _wholeFanOf(mesh, vertex))
        if (!onLoop.contains(neighbor)) neighbor,
    ]..sort();
    if (rails.length != 2) {
      return OpResult.refused(
        'a vertex on the loop has ${rails.length} '
        '${rails.length == 1 ? 'edge' : 'edges'} to slide along, and a slide '
        'needs two',
        selection: selection,
      );
    }
    final int rail = amount >= 0 ? rails[0] : rails[1];
    final Vector3 here = mesh.positionOf(vertex);
    // Clamped to the rail rather than allowed past it: a vertex slid off
    // the end of its own edge would leave the surface it belongs to, and
    // the acceptance this row states — a slid vertex stays on its edge — is
    // exactly this line.
    final double along = amount.abs().clamp(0.0, 1.0);
    destinations[vertex] = here + (mesh.positionOf(rail) - here) * along;
  }

  destinations.forEach(mesh.moveVertex);
  return OpResult.done(
    selection: Selection.of(ElementLevel.edge, selected.toList()..sort()),
    movedVertices: Int32List.fromList(destinations.keys.toList()..sort()),
  );
}

/// Every vertex sharing an edge with [vertex], both ways round the fan.
///
/// **`EditMesh.neighborsOf` walks one direction only**, which its own doc
/// comment is explicit about: a vertex on a border runs out of twins partway
/// round and misses everything on the other side. That is the right answer
/// for a smoothing pass, which wants the fan it can rotate through; it is
/// the wrong one here, where a border vertex with a rail on each side is
/// exactly the case a slide has to handle — a loop that ends on a border is
/// the commonest loop there is.
Set<int> _wholeFanOf(EditMesh mesh, int vertex) {
  final found = <int>{};
  final int start = mesh.outgoingOf(vertex);
  if (start == EditMesh.none) return found;
  var half = start;
  while (true) {
    found.add(mesh.originOf(mesh.nextOf(half)));
    if (!mesh.hasLiveTwin(half)) break;
    half = mesh.nextOf(mesh.twinOf(half));
    // A closed fan comes back to where it started, and there is no other
    // side to walk.
    if (half == start) return found;
  }
  half = start;
  while (true) {
    final int into = _prevOf(mesh, half);
    found.add(mesh.originOf(into));
    if (!mesh.hasLiveTwin(into)) break;
    half = mesh.twinOf(into);
    if (half == start) break;
  }
  return found;
}

/// The half-edge whose `next` is [half] — walked round the loop, since a
/// half-edge structure stores only the way forward.
int _prevOf(EditMesh mesh, int half) {
  var walk = half;
  while (mesh.nextOf(walk) != half) {
    walk = mesh.nextOf(walk);
  }
  return walk;
}
