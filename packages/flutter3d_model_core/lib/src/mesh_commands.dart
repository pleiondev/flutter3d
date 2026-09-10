/// The commands that act on the parts of one mesh.
///
/// **These are the ones that do not keep a document, and the reason is
/// measured.** `p0-05` timed the two ways of making an `EditMesh` a value:
/// copy-on-write chunks cost 92–100 per cent of a full copy the moment an edit
/// is scattered — a thousand vertices picked out of a model touch nearly every
/// chunk — while a flat array with a journal of previous values costs two per
/// cent in both distributions. The journal won, and a journal has no old
/// versions to hold: the previous state exists only by rolling back.
///
/// So a mesh command opens a step on the mesh, edits in place, and hands the
/// history the mesh and the fact that it took a step. `ModelHistory` rolls the
/// journal back on undo and forward on redo, in step with the document it keeps
/// for everything else. The object still becomes a new [ModelObject] with a new
/// version, so a viewport knows to upload again — the value that changed is the
/// object, and the mesh inside it is the same mesh at a different point in its
/// own history.
///
/// **Every one of them refuses a shape that still knows its parameters**, with
/// the sentence that says what to do about it. Pulling a face out of a cylinder
/// is exactly the thing that stops it being a cylinder, and doing it silently
/// would throw away the radius and the segment count with no step in the
/// history to say so.
part of 'command.dart';

/// What every mesh command needs before it can do anything: the object, its
/// mesh, and the selection as the mesh package spells it.
typedef _MeshTarget = ({ModelObject object, EditMesh mesh, Selection elements});

/// The object a mesh command acts on, or the sentence to refuse with.
///
/// One function rather than five copies of the same four checks, because the
/// four are the same four every time and the fourth — "this is still a
/// cylinder" — is the one with something useful to say.
({_MeshTarget? target, String? refused}) _meshTarget(
  ModelProject project,
  ProjectSelection selection,
) {
  final int? id = selection.activeObject;
  if (id == null) {
    return (target: null, refused: 'no object is selected');
  }
  final ModelObject? object = project[id];
  if (object == null) {
    return (target: null, refused: 'the selected object has gone');
  }
  return switch (object.geometry) {
    EditedGeometry(:final mesh) => (
      target: (object: object, mesh: mesh, elements: selection.asMeshSelection),
      refused: null,
    ),
    ParametricGeometry(:final shape) => (
      target: null,
      refused:
          '"${object.name}" is still a ${shape.name}. Convert it to a mesh '
          'first, which is a step you can take back',
    ),
    ImportedGeometry() => (
      target: null,
      refused:
          '"${object.name}" came from a file and has no topology to edit yet',
    ),
  };
}

/// Runs [edit] against the selected object's mesh as one journal step.
///
/// The whole of the bookkeeping is here: open the step, run, close it, and roll
/// back if the operation refused after writing something — which several of
/// them do, because a refusal can be found halfway through a walk. What comes
/// back names the mesh, so the history knows whose journal to move.
Outcome _asMeshStep(
  ModelProject project,
  ProjectSelection selection,
  OpResult Function(_MeshTarget target) edit,
) {
  final found = _meshTarget(project, selection);
  if (found.target == null) return Outcome.refused(found.refused!);
  final _MeshTarget target = found.target!;

  target.mesh.beginStep();
  final OpResult result = edit(target);
  if (!result.ok) {
    // `endStep` discards a step that wrote nothing and says so, so an
    // unconditional undo here would take back the *previous* edit — the loop
    // cut before the extrude that was refused.
    if (target.mesh.endStep()) target.mesh.undo();
    return Outcome.refused(result.reason!);
  }
  target.mesh.endStep();
  return Outcome.done(
    project.withObject(
      // A new `EditedGeometry` round the same mesh: the value that changed is
      // the object, and its version is what tells a viewport to upload again.
      target.object.copyWith(geometry: EditedGeometry(target.mesh)),
    ),
    selection: selection.copyWith(
      elements: result.selection.ids.toList(),
      level: result.selection.level,
    ),
    meshTouched: target.mesh,
  );
}

/// Pulls the selected faces out along their own normal.
final class Extrude extends ModelCommand {
  const Extrude(this.distance);

  final double distance;

  @override
  String get name => 'extrude';

  @override
  String get says => 'extrude';

  @override
  Map<String, Object?> get arguments => <String, Object?>{'distance': distance};

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) =>
      _asMeshStep(
        project,
        selection,
        (_MeshTarget target) =>
            extrudeFaces(target.mesh, target.elements, distance: distance),
      );
}

/// Cuts a ring of edges across the quads the selected edge runs through.
final class LoopCut extends ModelCommand {
  const LoopCut({this.cuts = 1, this.factor = 0.5});

  final int cuts;
  final double factor;

  @override
  String get name => 'loopCut';

  @override
  String get says => cuts == 1 ? 'cut a loop' : 'cut $cuts loops';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'cuts': cuts,
    'factor': factor,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) =>
      _asMeshStep(
        project,
        selection,
        (_MeshTarget target) =>
            loopCut(target.mesh, target.elements, cuts: cuts, factor: factor),
      );
}

/// Takes the selected elements out of the mesh.
final class DeleteElements extends ModelCommand {
  const DeleteElements();

  @override
  String get name => 'deleteElements';

  @override
  String get says => 'delete';

  @override
  Map<String, Object?> get arguments => const <String, Object?>{};

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) =>
      _asMeshStep(
        project,
        selection,
        (_MeshTarget target) => deleteSelection(target.mesh, target.elements),
      );
}

/// Moves, turns or scales the selected elements.
///
/// **One command for the three, because the difference is a matrix.** Three
/// commands with the same body is three chances for two of them to drift from
/// the third; what a person sees is decided by [says], which is the only place
/// the three are actually different.
final class TransformElements extends ModelCommand {
  const TransformElements(this.by, {this.what = 'move'});

  final Matrix4 by;

  /// The word the history offers: `move`, `turn` or `scale`.
  final String what;

  @override
  String get name => 'transformElements';

  @override
  String get says => what;

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'by': by.storage.toList(),
    'what': what,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) =>
      _asMeshStep(
        project,
        selection,
        (_MeshTarget target) =>
            transformSelection(target.mesh, target.elements, by: by),
      );
}
