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
///
/// **[by] is the transform at the pivot, not the transform to apply to the
/// vertices.** The command puts the pivot in, the same way `rotateSelection`
/// and `scaleSelection` do one package down — so a caller hands over a turn
/// about the origin and says where the origin should be, rather than composing
/// three matrices and getting the order wrong. A caller that has already
/// wrapped its own pivot in will find it applied twice.
final class TransformElements extends ModelCommand {
  const TransformElements(
    this.by, {
    this.what = 'move',
    this.pivot = TransformPivot.median,
    this.space = TransformSpace.global,
  });

  final Matrix4 by;

  /// The word the history offers: `move`, `turn` or `scale`.
  final String what;

  /// The point the transform happens about. [TransformPivot.individual] is
  /// refused — see [apply].
  final TransformPivot pivot;

  /// Whose axes [by] is given in. The elements are stored in the object's own
  /// frame, so [TransformSpace.local] is the cheap case and
  /// [TransformSpace.global] is the one that has to undo the object's rotation
  /// first — which is why an object nobody has turned behaves identically under
  /// both.
  final TransformSpace space;

  @override
  String get name => 'transformElements';

  @override
  String get says => what;

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'by': by.storage.toList(),
    'what': what,
    'pivot': pivot.name,
    'space': space.name,
  };

  /// **[TransformPivot.individual] is refused rather than approximated.**
  /// Turning every face about its own centre means the faces stop sharing their
  /// corners, and `transformSelection` moves each vertex exactly once — so the
  /// honest version of this is a split first and a transform after, which is
  /// two operations and one of them does not exist yet. Doing it by moving
  /// shared vertices twice would tear the mesh in a way no step of the history
  /// describes.
  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    if (pivot == TransformPivot.individual) {
      return Outcome.refused(
        'turning each element about its own centre needs them pulled apart '
        'first: a corner two faces share cannot follow both of them',
      );
    }
    return _asMeshStep(project, selection, (_MeshTarget target) {
      // The median of the selected vertices, in the object's own frame, which
      // is the frame the positions are stored in.
      final Vector3 about = medianOf(target.mesh, target.elements);
      return transformSelection(
        target.mesh,
        target.elements,
        by: _sandwiched(
          about,
          // The inverse, because what is wanted is the world's axes *read in*
          // the object's frame: `R⁻¹ · by · R` turns a world X into whatever
          // direction that is on an object somebody has already turned.
          space == TransformSpace.global
              ? Matrix4.inverted(_basisOf(target.object.transform))
              : null,
          by,
        ),
      );
    });
  }
}

/// Welds vertices closer together than [distance].
///
/// **The one mesh command that does not take a journal step, because
/// `mergeByDistance` hands back a different mesh.** Rebuilding is how it drops
/// the coincident walls a weld leaves behind and splits a vertex the weld made
/// non-manifold — neither of which is a sequence of in-place edits. So the
/// object gets the new mesh as its geometry, the history keeps the object that
/// held the old one, and undo is a pointer rather than a rollback. It is also
/// why the mesh's own journal is thrown away by a merge: the old mesh keeps
/// its, and the new one starts with none.
final class MergeByDistance extends ModelCommand {
  const MergeByDistance({this.distance});

  /// How close is close enough, or null for the mesh's own guess — a fraction
  /// of its size, which is the only answer that means the same thing on a bolt
  /// and on a building.
  final double? distance;

  @override
  String get name => 'mergeByDistance';

  @override
  String get says => 'merge';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    if (distance case final double how) 'distance': how,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final found = _meshTarget(project, selection);
    if (found.target == null) return Outcome.refused(found.refused!);
    final _MeshTarget target = found.target!;

    final (EditMesh merged, MergeReport report) = mergeByDistance(
      target.mesh,
      distance: distance,
      within: target.elements.isEmpty ? null : target.elements,
    );
    if (report.vertices == report.sourceVertices) {
      // Nothing welded. Refused rather than accepted as a no-op, because a new
      // mesh with the same contents is still a new mesh: the object would get a
      // version, the buffers would be uploaded again and the journal would be
      // thrown away, all for a step that changed nothing.
      return Outcome.refused('nothing was close enough to weld');
    }
    return Outcome.done(
      project.withObject(
        target.object.copyWith(geometry: EditedGeometry(merged)),
      ),
      // The elements are named by numbers in the old mesh and the new one has
      // renumbered them. Emptied rather than remapped: `MergeReport` carries
      // the map, and using it is `doc-07`'s selection-follows-the-edit work —
      // showing a selection that names the wrong vertices would be worse than
      // showing none.
      selection: selection.copyWith(elements: const <int>[]),
    );
  }
}

/// Takes the selected edges out, leaving the faces either side joined.
final class DissolveEdges extends ModelCommand {
  const DissolveEdges();

  @override
  String get name => 'dissolveEdges';

  @override
  String get says => 'dissolve';

  @override
  Map<String, Object?> get arguments => const <String, Object?>{};

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) =>
      _asMeshStep(project, selection, (_MeshTarget target) {
        final edges = target.elements.convertedTo(
          target.mesh,
          ElementLevel.edge,
        );
        if (edges.isEmpty) {
          return OpResult.refused(
            'no edges are selected to dissolve',
            selection: target.elements,
          );
        }
        var dissolved = 0;
        for (final half in edges.ids) {
          if (target.mesh.dissolveEdge(half)) dissolved++;
        }
        if (dissolved == 0) {
          // Every one refused: a boundary edge has nothing on the other side,
          // and an edge whose two faces are the same face would leave a hole.
          return OpResult.refused(
            'none of those edges can go: an edge on a boundary has nothing to '
            'join to',
            selection: target.elements,
          );
        }
        return OpResult.done(
          selection: Selection.empty(ElementLevel.edge),
          topologyChanged: true,
        );
      });
}

/// Cuts every selected face into triangles.
final class Triangulate extends ModelCommand {
  const Triangulate();

  @override
  String get name => 'triangulate';

  @override
  String get says => 'triangulate';

  @override
  Map<String, Object?> get arguments => const <String, Object?>{};

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) =>
      _asMeshStep(
        project,
        selection,
        (_MeshTarget target) => triangulateFaces(target.mesh, target.elements),
      );
}

/// Makes every face wind the same way as its neighbours.
///
/// **What "recalculate normals" means when the normals are computed.** Nothing
/// here stores a normal: `MeshNormals` works one out from the winding every
/// time the mesh is drawn. So the thing a person is asking for when a face
/// looks inside out is not a recomputation — it is the winding being made
/// consistent, which is what this does. [flip] turns the whole mesh inside out
/// instead, which is the other half of what the menu item is for.
final class RecalculateNormals extends ModelCommand {
  const RecalculateNormals({this.flip = false});

  final bool flip;

  @override
  String get name => 'recalculateNormals';

  @override
  String get says => flip ? 'flip the normals' : 'recalculate the normals';

  @override
  Map<String, Object?> get arguments => <String, Object?>{'flip': flip};

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) =>
      _asMeshStep(project, selection, (_MeshTarget target) {
        if (flip) {
          target.mesh.flipNormals();
          return OpResult.done(
            selection: target.elements,
            topologyChanged: true,
          );
        }
        if (!target.mesh.makeConsistent()) {
          return OpResult.refused(
            'every face already agrees with its neighbours',
            selection: target.elements,
          );
        }
        return OpResult.done(selection: target.elements, topologyChanged: true);
      });
}
