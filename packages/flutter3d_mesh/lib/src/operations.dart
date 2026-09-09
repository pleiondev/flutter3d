/// Moving what is selected, and the shape every operation on a mesh has.
///
/// **One shape: a mesh, a selection, the parameters, and an [OpResult].** Every
/// edit a person can invoke is that — an extrusion, a loop cut, a delete, a
/// transform — and the reason to write it down here rather than let each one
/// grow its own is the layer above. A command needs to run an operation it was
/// handed without knowing which one it is, put the result in front of somebody
/// when it was refused, and hand the viewport the rows to refill; an agent over
/// MCP needs the same. Three functions with three different return types is
/// three of each of those.
///
/// **The result says what to redraw, not just whether it worked.** A transform
/// moves vertices and changes no topology at all, so the layout plan a viewport
/// is holding is still correct and only some of its rows are stale —
/// [MeshLayoutPlan.fillVerticesOf] over [OpResult.movedVertices] is a
/// microsecond, and rebuilding the plan is sixty-eight milliseconds on a mesh
/// of any size. An extrusion is the other case, and says so.
///
/// **An operation writes inside a step somebody else opened.** That is the rule
/// everywhere in this package, and it is what lets a tool that drags a gizmo
/// put forty frames of movement into one undo — or a command put two operations
/// into one. What an operation must not do is decide on its own where the
/// history boundaries are.
library;

import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'edit_mesh.dart';
import 'selection.dart';

/// What an operation did, or why it did not.
final class OpResult {
  const OpResult._({
    required this.selection,
    required this.movedVertices,
    required this.topologyChanged,
    this.reason,
  });

  /// It worked.
  ///
  /// [movedVertices] are the vertices whose positions are no longer what a
  /// buffer built earlier holds; [topologyChanged] says whether a layout plan
  /// or a BVH built against this mesh is still describing it.
  factory OpResult.done({
    required Selection selection,
    Int32List? movedVertices,
    bool topologyChanged = false,
  }) => OpResult._(
    selection: selection,
    movedVertices: movedVertices ?? _nothing,
    topologyChanged: topologyChanged,
  );

  /// It did not, and this is what to tell somebody.
  ///
  /// **A sentence rather than an exception or a false.** Half the operations
  /// here refuse for reasons a person can act on — nothing selected, the edge
  /// is on a boundary, the faces do not form a region — and a modeller that
  /// answers those with a silent no-op is a modeller people think is broken.
  /// Throwing would be worse: a refusal is an ordinary outcome, not a fault.
  factory OpResult.refused(String reason, {required Selection selection}) =>
      OpResult._(
        selection: selection,
        movedVertices: _nothing,
        topologyChanged: false,
        reason: reason,
      );

  static final Int32List _nothing = Int32List(0);

  /// What is selected now. An operation that adds geometry selects what it
  /// made, which is what a person expects to be able to move next.
  final Selection selection;

  /// The vertices whose positions changed, ascending.
  final Int32List movedVertices;

  /// Whether anything but positions changed.
  final bool topologyChanged;

  /// Why the operation was refused, or null.
  final String? reason;

  bool get ok => reason == null;

  @override
  String toString() => ok
      ? 'OpResult(${movedVertices.length} vertices moved, '
            'topology ${topologyChanged ? 'changed' : 'untouched'})'
      : 'OpResult(refused: $reason)';
}

/// Moves the vertices [selection] stands on by [by].
OpResult translateSelection(
  EditMesh mesh,
  Selection selection, {
  required Vector3 by,
}) => transformSelection(mesh, selection, by: Matrix4.translation(by));

/// Turns the vertices [selection] stands on about [pivot].
OpResult rotateSelection(
  EditMesh mesh,
  Selection selection, {
  required Quaternion by,
  Vector3? pivot,
}) => _about(
  mesh,
  selection,
  Matrix4.compose(Vector3.zero(), by, Vector3(1, 1, 1)),
  pivot,
);

/// Scales the vertices [selection] stands on about [pivot].
OpResult scaleSelection(
  EditMesh mesh,
  Selection selection, {
  required Vector3 by,
  Vector3? pivot,
}) => _about(mesh, selection, Matrix4.diagonal3Values(by.x, by.y, by.z), pivot);

/// Applies [by] to the vertices [selection] stands on.
///
/// **Positions and nothing else.** A transform is the one edit where the mesh's
/// topology is not merely unchanged but *known* to be unchanged, and saying so
/// is what lets a viewport skip everything but a handful of rows. The one thing
/// it does not do is renormalise anything: a scale by a negative number turns
/// the surface inside out, and `EditMesh.makeConsistent` is where a caller that
/// minds says so.
OpResult transformSelection(
  EditMesh mesh,
  Selection selection, {
  required Matrix4 by,
}) {
  final vertices = selection.convertedTo(mesh, ElementLevel.vertex);
  if (vertices.isEmpty) {
    return OpResult.refused('nothing is selected', selection: selection);
  }

  final at = Vector3.zero();
  for (final vertex in vertices.ids) {
    mesh.positionOf(vertex, at);
    mesh.moveVertex(vertex, by.transform3(at));
  }
  return OpResult.done(selection: selection, movedVertices: vertices.ids);
}

/// The same transform, wrapped in a move to a pivot and back.
OpResult _about(
  EditMesh mesh,
  Selection selection,
  Matrix4 transform,
  Vector3? pivot,
) {
  final vertices = selection.convertedTo(mesh, ElementLevel.vertex);
  if (vertices.isEmpty) {
    return OpResult.refused('nothing is selected', selection: selection);
  }
  final about = pivot ?? medianOf(mesh, vertices);
  return transformSelection(
    mesh,
    selection,
    by: Matrix4.translation(about)
      ..multiply(transform)
      ..multiply(Matrix4.translation(-about)),
  );
}

/// The middle of what [selection] stands on, which is where a rotation or a
/// scale happens when nobody said otherwise.
///
/// **The median of the vertices, not the centre of their bounding box.** The
/// two differ on anything that is not symmetric, and the median is the one a
/// person is thinking of when they scale a face they have selected: it stays
/// put when the selection grows in one direction only.
Vector3 medianOf(EditMesh mesh, Selection selection) {
  final vertices = selection.convertedTo(mesh, ElementLevel.vertex);
  if (vertices.isEmpty) return Vector3.zero();
  final middle = Vector3.zero();
  final at = Vector3.zero();
  for (final vertex in vertices.ids) {
    middle.add(mesh.positionOf(vertex, at));
  }
  return middle..scale(1 / vertices.length);
}
