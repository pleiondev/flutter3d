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
    SocketGeometry() => (
      target: null,
      refused: '"${object.name}" is a socket and has no topology to edit',
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
    // Abandoned rather than ended and undone: pushing the step would clear
    // the mesh's redo stack, so a refusal right after an undo would leave
    // `ModelHistory` offering a redo the mesh could no longer perform.
    target.mesh.abandonStep();
    return Outcome.refused(result.reason!);
  }
  target.mesh.endStep();
  return Outcome.done(
    project.withObject(
      // A new `EditedGeometry` round the same mesh: the value that changed is
      // the object, and its version is what tells a viewport to upload again.
      _resyncShapeSet(
        target.object,
        target.mesh,
      ).copyWith(geometry: EditedGeometry(target.mesh)),
    ),
    selection: selection.copyWith(
      elements: result.selection.ids.toList(),
      level: result.selection.level,
    ),
    meshTouched: target.mesh,
  );
}

/// [object], with every one of its own shape keys grown to [mesh]'s current
/// vertex slots — `anim-19`'s own remaining gap (see `mesh-61`'s "loop cut
/// сохраняет ключи"): a topology edit that adds vertices (a loop cut, an
/// extrusion) left a shape key's own positions one call to [ShapeKey
/// .grownTo] short of covering the mesh it was captured on, silently, until
/// the next sculpt on that key touched the new vertices' own default
/// (whatever `grownTo` would have seeded them to) rather than actually
/// seeding them.
///
/// Only [ShapeKey.grownTo] — never [ShapeKey.remappedBy] — because every
/// command that reaches [_asMeshStep] edits [mesh] in place and never
/// compacts it: a deleted vertex is tombstoned, its own slot held rather
/// than freed, so nothing here is ever renumbered out from under a shape
/// key. [EditMesh.compact] does not appear anywhere in this file.
ModelObject _resyncShapeSet(ModelObject object, EditMesh mesh) {
  final shapes = object.shapeSet;
  if (shapes.isEmpty) return object;
  return object.copyWith(
    shapeSet: shapes.copyWith(
      keys: <ShapeKey>[for (final key in shapes.keys) key.grownTo(mesh)],
    ),
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
  Map<String, ParamHint> get hints => const <String, ParamHint>{
    'distance': DoubleHint(unit: 'm', step: 0.1),
  };

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
  Map<String, ParamHint> get hints => const <String, ParamHint>{
    'cuts': IntHint(min: 1, max: 100),
    'factor': DoubleHint(min: 0.0, max: 1.0, step: 0.01),
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

/// Cuts a corner off every selected edge or vertex, walling the gap with a
/// new face per edge and a new n-gon per vertex — `flutter3d_mesh`'s own
/// [bevelEdges]/[bevelVertices] (`bevel.dart`), wired into the undo stack for
/// `tut-04`.
///
/// **Reads the selection's own level to choose between the two.** A vertex
/// selection means "the vertex and everywhere it touches" —
/// [bevelVertices]'s own walk of a vertex's edges, not the edges
/// [Selection.convertedTo] would give (only an edge whose *both* ends are
/// selected). Anything else goes through [bevelEdges], which converts the
/// selection to edges the ordinary way on its own.
final class BevelEdges extends ModelCommand {
  const BevelEdges(this.width, {this.segments = 1, this.clampOverlap = true});

  /// How far the new face wall sits from the original corner.
  final double width;

  /// Segments above `1` are not built yet — see [bevelEdges]'s own doc
  /// comment — so a value other than the default is refused by the mesh
  /// package itself, with a sentence, rather than silently flattened here.
  final int segments;

  /// Scales [width] down when the shortest beveled edge is not long enough
  /// to hold it, rather than building bevels that overlap and cross.
  final bool clampOverlap;

  @override
  String get name => 'bevelEdges';

  @override
  String get says => 'bevel';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'width': width,
    'segments': segments,
    'clampOverlap': clampOverlap,
  };

  @override
  Map<String, ParamHint> get hints => const <String, ParamHint>{
    'width': DoubleHint(min: 0.0, unit: 'm', step: 0.01),
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) =>
      _asMeshStep(project, selection, (_MeshTarget target) {
        final OpResult Function(
          EditMesh,
          Selection, {
          required double width,
          int segments,
          bool clampOverlap,
        })
        bevel = target.elements.level == ElementLevel.vertex
            ? bevelVertices
            : bevelEdges;
        return bevel(
          target.mesh,
          target.elements,
          width: width,
          segments: segments,
          clampOverlap: clampOverlap,
        );
      });
}

/// Shrinks every selected face inward and walls the ring it leaves —
/// `ux-39`.
final class InsetFaces extends ModelCommand {
  const InsetFaces(this.thickness, {this.depth = 0.0});

  /// How far the new ring sits inside the face's own border.
  final double thickness;

  /// How far the new ring is pushed along the face's own normal — nought
  /// for a flat inset, which is what a panel is.
  final double depth;

  @override
  String get name => 'insetFaces';

  @override
  String get says => 'inset';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'thickness': thickness,
    'depth': depth,
  };

  @override
  Map<String, ParamHint> get hints => const <String, ParamHint>{
    'thickness': DoubleHint(min: 0.0, unit: 'm', step: 0.01),
    'depth': DoubleHint(unit: 'm', step: 0.01),
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) =>
      _asMeshStep(
        project,
        selection,
        (_MeshTarget target) => insetFaces(
          target.mesh,
          target.elements,
          thickness: thickness,
          depth: depth,
        ),
      );
}

/// Joins the two open borders the selection names with a ring of quads —
/// `ux-39`.
final class BridgeLoops extends ModelCommand {
  const BridgeLoops();

  @override
  String get name => 'bridgeLoops';

  @override
  String get says => 'bridge';

  @override
  Map<String, Object?> get arguments => const <String, Object?>{};

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) =>
      _asMeshStep(
        project,
        selection,
        (_MeshTarget target) => bridgeLoops(target.mesh, target.elements),
      );
}

/// Moves the selected loop along the edges that cross it — `ux-39`.
final class SlideEdges extends ModelCommand {
  const SlideEdges(this.amount);

  /// How far along the rail, as a fraction of its own length. Negative
  /// slides the other way.
  final double amount;

  @override
  String get name => 'slideEdges';

  @override
  String get says => 'slide';

  @override
  Map<String, Object?> get arguments => <String, Object?>{'amount': amount};

  @override
  Map<String, ParamHint> get hints => const <String, ParamHint>{
    'amount': DoubleHint(min: -1.0, max: 1.0, step: 0.01),
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) =>
      _asMeshStep(
        project,
        selection,
        (_MeshTarget target) =>
            slideEdges(target.mesh, target.elements, amount: amount),
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

  // No hint for `by`: it is the whole transform matrix rather than a single
  // number, and nothing here is asking a person to type sixteen floats into a
  // control. `pivot`/`space` are the two arguments an operation card can
  // actually offer a person a choice between.
  @override
  Map<String, ParamHint> get hints => <String, ParamHint>{
    'pivot': EnumHint(<String>[for (final p in TransformPivot.values) p.name]),
    'space': EnumHint(<String>[for (final s in TransformSpace.values) s.name]),
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

  // Conditional the same way `arguments` is: a hint for a key that is not
  // there when this instance's own `distance` is null would break the one
  // promise `ModelCommand.hints` makes about itself — that its keys are
  // always a subset of `arguments`'.
  @override
  Map<String, ParamHint> get hints => <String, ParamHint>{
    if (distance != null)
      'distance': const DoubleHint(min: 0.0, step: 0.001, unit: 'm'),
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

/// Marks or clears the UV seam flag on the selected edges — `pro-uv-01`.
///
/// **A flag, not a topology change**, which is why this is the shortest
/// command in the file: `EditMesh.setEdgeFlag` already writes both halves of
/// an edge (`mesh-12`), and marking one changes nothing a layout plan or a
/// BVH built against this mesh would need to hear about — the same
/// `topologyChanged: false` a transform answers with. The mesh a UV unwrap
/// walks later is unchanged in shape; only what it is willing to cut along
/// is.
final class MarkSeam extends ModelCommand {
  const MarkSeam({this.on = true});

  /// True to mark the selected edges as a seam, false to clear it — a caller
  /// choosing between a "mark seam" and a "clear seam" menu item is choosing
  /// this, not two different commands.
  final bool on;

  @override
  String get name => 'markSeam';

  @override
  String get says => on ? 'mark the seam' : 'clear the seam';

  @override
  Map<String, Object?> get arguments => <String, Object?>{'on': on};

  @override
  Map<String, ParamHint> get hints => const <String, ParamHint>{
    'on': BoolHint(),
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) =>
      _asMeshStep(project, selection, (_MeshTarget target) {
        final edges = target.elements.convertedTo(
          target.mesh,
          ElementLevel.edge,
        );
        if (edges.isEmpty) {
          return OpResult.refused(
            'no edges are selected to ${on ? 'mark as a seam' : 'clear'}',
            selection: target.elements,
          );
        }
        for (final half in edges.ids) {
          target.mesh.setEdgeFlag(half, EdgeFlags.seam, on: on);
        }
        return OpResult.done(selection: target.elements);
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
  Map<String, ParamHint> get hints => const <String, ParamHint>{
    'flip': BoolHint(),
  };

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

/// Takes the selected faces out of one object and makes them another.
///
/// **The one mesh command that is also a document command, and it cannot be
/// written as either half.** Everything above hands the history a mesh and a
/// count of journal steps; this also hands it a project with an object in it
/// that was not there before. Both have to move together on undo — a document
/// put back without the faces, holding a mesh that still has them, draws the
/// same triangles twice.
///
/// **The piece keeps the object's place in the world.** Same transform, same
/// parent, same material slots: separating is a statement about topology, and
/// a piece that jumped to the origin the moment it was cut loose would be a
/// statement about position as well. `subMesh` carries the texture coordinates
/// and the per-face material across, so the part looks like what it was part
/// of.
///
/// **What it refuses, and why each refusal is not a silent success.** Nothing
/// selected leaves nothing to move. Everything selected would empty the object
/// it came from — Blender leaves that husk behind, and a husk with no faces is
/// exactly what `ExportReadiness` calls an error, so the answer here is to say
/// the model is already one piece rather than to make a broken one.
final class Separate extends ModelCommand {
  const Separate();

  @override
  String get name => 'separate';

  @override
  String get says => 'separate';

  @override
  Map<String, Object?> get arguments => const <String, Object?>{};

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final found = _meshTarget(project, selection);
    if (found.target == null) return Outcome.refused(found.refused!);
    final _MeshTarget target = found.target!;

    // Whatever the person is working at, the thing that comes out is faces: a
    // vertex on its own has no area to be a piece of.
    final Selection faces = target.elements.convertedTo(
      target.mesh,
      ElementLevel.face,
    );
    if (faces.isEmpty) {
      return Outcome.refused(
        target.elements.isEmpty
            ? 'nothing is selected to separate'
            : 'no whole face is selected — a piece is made of faces, and the '
                  'selection covers none of them completely',
      );
    }
    if (faces.ids.length >= target.mesh.faceCount) {
      return Outcome.refused(
        '"${target.object.name}" is selected whole, so there is nothing to '
        'separate it from',
      );
    }

    final (EditMesh part, IdRemap _) = subMesh(target.mesh, faces.ids);

    target.mesh.beginStep();
    final OpResult cut = deleteSelection(target.mesh, faces);
    if (!cut.ok) {
      target.mesh.abandonStep();
      return Outcome.refused(cut.reason!);
    }
    target.mesh.endStep();

    final ModelObject source = target.object;
    final ModelProject next = project
        .withObject(source.copyWith(geometry: EditedGeometry(target.mesh)))
        .added(
          (int fresh) => ModelObject(
            id: fresh,
            name: '${source.name} part',
            geometry: EditedGeometry(part),
            transform: Matrix4.copy(source.transform),
            parent: source.parent,
            materialSlots: source.materialSlots,
          ),
        );

    return Outcome.done(
      next,
      // The piece is what the person is now holding, and it is a whole object:
      // the element numbers they had were numbers in a mesh that has just been
      // renumbered, and `subMesh` says so by handing back a remap.
      selection: selection.copyWith(
        mode: SelectionMode.object,
        objects: <int>[next.objects.last.id],
        elements: const <int>[],
      ),
      meshTouched: target.mesh,
    );
  }
}

/// Closes every open boundary loop in the selected object's own mesh with
/// one new face — `mesh-81n`'s own row, wiring `fillHoles` (`flutter3d_mesh`)
/// into the undo stack, the "button" its own doc comment says
/// `ExportReadiness`'s "won't load" leaves a person without. Selects the
/// faces it made, the same "an operation that adds geometry selects what it
/// made" rule every other mesh command here already follows.
///
/// **Not routed through `_asMeshStep`, on purpose.** `fillHoles` reports how
/// many holes it closed as a plain count, not an [OpResult] — a library
/// function that welds an existing boundary back together rather than
/// moving or adding vertices has no [Selection] of its own to report,
/// unlike `extrudeFaces` or `deleteSelection`. Building the step by hand
/// here, the same way [MergeByDistance] and [Separate] already do for the
/// identical reason, costs three lines and avoids forcing every future
/// caller of `fillHoles` itself to carry an `OpResult`'s own selection
/// machinery it would never use.
final class FillHoles extends ModelCommand {
  const FillHoles();

  @override
  String get name => 'fillHoles';

  @override
  String get says => 'fill holes';

  @override
  Map<String, Object?> get arguments => const <String, Object?>{};

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final found = _meshTarget(project, selection);
    if (found.target == null) return Outcome.refused(found.refused!);
    final _MeshTarget target = found.target!;

    target.mesh.beginStep();
    final firstNewFace = target.mesh.faceSlotCount;
    final closed = fillHoles(target.mesh);
    if (closed == 0) {
      target.mesh.abandonStep();
      return Outcome.refused(
        '"${target.object.name}" has no open boundary to close',
      );
    }
    target.mesh.endStep();

    // `fillHoles` only ever welds new faces to vertices the boundary
    // already named — it calls `addFace`, never `addVertex` — so unlike a
    // `LoopCut` or an `Extrude`, there is nothing here for a shape key to
    // grow into; `_resyncShapeSet` would be the identical dead call entry
    // 70 found and removed from `Separate`; not repeated.
    return Outcome.done(
      project.withObject(
        target.object.copyWith(geometry: EditedGeometry(target.mesh)),
      ),
      selection: selection.copyWith(
        elements: <int>[
          for (var f = firstNewFace; f < target.mesh.faceSlotCount; f++) f,
        ],
        level: ElementLevel.face,
      ),
      meshTouched: target.mesh,
    );
  }
}
