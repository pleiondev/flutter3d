/// The commands that change what is selected rather than what is in the
/// project.
///
/// **Selecting is a command for the three reasons every other edit is one, and
/// it was not, which is the bug this file closes.** The interface used to
/// assign `ModelHistory.selection` directly, and the cost of that showed up in
/// three places at once: ⌘Z could not take back a click that lost a careful
/// hand-picked region, the journal a project file writes had no record of how
/// the region was arrived at, and an agent driving the modeller could ask for
/// an extrusion but had no way of saying what to extrude. A command fixes all
/// three at once because the history, the journal and the tool table are all
/// fed from the same sealed set.
///
/// **The project comes back unchanged, and that is deliberate.** Every command
/// here hands [ModelHistory] the very same [ModelProject] it was given, so
/// `identical` still says the document has not moved and a file that was saved
/// stays saved — selecting is not an edit to the model. What the step carries
/// is the selection before it, which is all an undo needs.
///
/// **Not one of these implements a walk.** Growing, shrinking, linking, loops,
/// rings and material slots are all on `Selection` in `flutter3d_mesh`, where
/// they are tested against meshes rather than against projects. What is here is
/// the half that knows about modes, objects and refusals.
part of 'command.dart';

/// Every live element of [level] in [mesh].
///
/// **Not on `Selection` one package down, because "everything" is the one
/// answer that needs no selection to start from.** `grown`, `linked` and the
/// rest are walks outward from what is already picked; this is a sweep of the
/// mesh, and the only caller that ever wants it is a command like these.
///
/// The edge case is edges: an edge is not stored, so the sweep visits every
/// half-edge of every live face and asks [EditMesh.edgeOf] which of a twinned
/// pair stands for the edge. `Selection.of` sorts and drops the duplicate that
/// comes back from the other side.
Selection _everything(EditMesh mesh, ElementLevel level) => switch (level) {
  ElementLevel.vertex => Selection.of(level, <int>[
    for (var vertex = 0; vertex < mesh.vertexSlotCount; vertex++)
      if (mesh.isVertexAlive(vertex)) vertex,
  ]),
  ElementLevel.face => Selection.of(level, <int>[
    for (var face = 0; face < mesh.faceSlotCount; face++)
      if (mesh.isFaceAlive(face)) face,
  ]),
  ElementLevel.edge => _everyEdge(mesh),
};

Selection _everyEdge(EditMesh mesh) {
  final found = <int>[];
  for (var face = 0; face < mesh.faceSlotCount; face++) {
    if (!mesh.isFaceAlive(face)) continue;
    mesh.forEachHalfEdge(face, (int half) => found.add(mesh.edgeOf(half)));
  }
  return Selection.of(ElementLevel.edge, found);
}

/// [next] as the outcome, or a refusal when it is what was selected already.
///
/// **A step that changes nothing is worse than no step**, for the reason
/// `MergeByDistance` gives: it goes on the stack, ⌘Z walks past it, and the
/// person watching sees a keystroke do nothing. Pressing "select all" twice is
/// the ordinary way to produce one.
Outcome _keep(
  ModelProject project,
  ProjectSelection was,
  ProjectSelection next,
) => _sameSelection(was, next)
    ? Outcome.refused('that is what is selected already')
    : Outcome.done(project, selection: next);

/// Whether two selections name the same things in the same order.
///
/// Order counts because the last object picked is the active one — the one a
/// mesh command acts on — so a selection of the same three objects in a
/// different order is a different selection to everything downstream of it.
bool _sameSelection(ProjectSelection a, ProjectSelection b) =>
    a.mode == b.mode &&
    a.level == b.level &&
    _sameIds(a.objects, b.objects) &&
    _sameIds(a.elements, b.elements);

bool _sameIds(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Runs [choose] against the selected object's mesh and keeps what it picked.
///
/// The shape is `_asMeshStep`'s deliberately — the same `_meshTarget` behind
/// it, the same `OpResult` out of the closure — because the four checks before
/// a mesh command can act are the same four before a mesh *selection* can act,
/// and the sentence a parametric cylinder refuses with is as true of selecting
/// its edge loops as of extruding its faces. What it does not do is open a
/// journal step: nothing here writes to the mesh.
Outcome _asSelection(
  ModelProject project,
  ProjectSelection selection,
  OpResult Function(_MeshTarget target) choose,
) {
  final found = _meshTarget(project, selection);
  if (found.target == null) return Outcome.refused(found.refused!);
  final OpResult result = choose(found.target!);
  if (!result.ok) return Outcome.refused(result.reason!);
  return _keep(
    project,
    selection,
    // The level travels with the elements: an edge loop asked for at vertex
    // level comes back as edges, and a selection holding edge numbers under
    // `ElementLevel.vertex` would draw the wrong things and convert to
    // nonsense.
    selection.copyWith(
      level: result.selection.level,
      elements: result.selection.ids.toList(),
    ),
  );
}

/// [walk] from [edge], or the sentence to refuse with when there is no such
/// edge in the mesh.
///
/// **Checked against the mesh's own edges rather than against the array
/// bounds.** A half-edge number well inside the arrays can belong to a face
/// somebody has deleted, and both walks step straight into `nextOf` and
/// `twinOf` from wherever they are put down — so a stale number out of an
/// overlay built before a delete would walk a dead loop rather than refuse.
///
/// The number is put through [EditMesh.edgeOf] before it is looked up, which
/// buys two things: a click on the far side of a surface names the same edge as
/// the number a selection holds, and the walk always starts from a half-edge
/// that is on a live face.
OpResult _fromEdge(
  _MeshTarget target,
  int edge,
  Selection Function(EditMesh mesh, int halfEdge) walk,
) {
  final EditMesh mesh = target.mesh;
  final int at = edge >= 0 && edge < mesh.halfEdgeSlotCount
      ? mesh.edgeOf(edge)
      : EditMesh.none;
  return _everything(mesh, ElementLevel.edge).contains(at)
      ? OpResult.done(selection: walk(mesh, at))
      : OpResult.refused(
          'there is no edge $edge in "${target.object.name}"',
          selection: target.elements,
        );
}

/// Everything there is, at whatever the modeller is pointing at.
final class SelectAll extends ModelCommand {
  const SelectAll();

  @override
  String get name => 'selectAll';

  @override
  String get says => 'select everything';

  @override
  Map<String, Object?> get arguments => const <String, Object?>{};

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) =>
      switch (selection.mode) {
        SelectionMode.object =>
          project.objects.isEmpty
              ? Outcome.refused('there is nothing in the project to select')
              : _keep(
                  project,
                  selection,
                  selection.copyWith(
                    objects: <int>[
                      for (final ModelObject each in project.objects) each.id,
                    ],
                  ),
                ),
        SelectionMode.mesh => _asSelection(project, selection, (
          _MeshTarget target,
        ) {
          final Selection everything = _everything(
            target.mesh,
            target.elements.level,
          );
          return everything.isEmpty
              ? OpResult.refused(
                  '"${target.object.name}" has nothing left in it to select',
                  selection: target.elements,
                )
              : OpResult.done(selection: everything);
        }),
      };
}

/// Nothing, at whatever the modeller is pointing at.
///
/// **The one selection command that asks the mesh nothing.** Clearing works on
/// a cylinder nobody has converted and on an object that came out of a file,
/// neither of which has topology to look at — and refusing to *deselect*
/// because the geometry cannot be edited would be a refusal with nothing behind
/// it.
final class SelectNone extends ModelCommand {
  const SelectNone();

  @override
  String get name => 'selectNone';

  @override
  String get says => 'select nothing';

  @override
  Map<String, Object?> get arguments => const <String, Object?>{};

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) =>
      _keep(project, selection, switch (selection.mode) {
        SelectionMode.object => selection.copyWith(objects: const <int>[]),
        SelectionMode.mesh => selection.copyWith(elements: const <int>[]),
      });
}

/// Everything that was not selected, and nothing that was.
final class InvertSelection extends ModelCommand {
  const InvertSelection();

  @override
  String get name => 'invertSelection';

  @override
  String get says => 'invert the selection';

  @override
  Map<String, Object?> get arguments => const <String, Object?>{};

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) =>
      switch (selection.mode) {
        SelectionMode.object =>
          project.objects.isEmpty
              ? Outcome.refused('there is nothing in the project to invert')
              : _keep(
                  project,
                  selection,
                  selection.copyWith(
                    objects: <int>[
                      for (final ModelObject each in project.objects)
                        if (!selection.objects.contains(each.id)) each.id,
                    ],
                  ),
                ),
        SelectionMode.mesh => _asSelection(
          project,
          selection,
          (_MeshTarget target) => OpResult.done(
            selection: _everything(
              target.mesh,
              target.elements.level,
            ).difference(target.elements),
          ),
        ),
      };
}

/// The selection plus everything touching it.
final class GrowSelection extends ModelCommand {
  const GrowSelection();

  @override
  String get name => 'growSelection';

  @override
  String get says => 'grow the selection';

  @override
  Map<String, Object?> get arguments => const <String, Object?>{};

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) =>
      selection.mode == SelectionMode.object
      ? Outcome.refused(
          'growing a selection takes in what is next to it, and objects in a '
          'project are not next to anything. Switch to mesh mode to widen a '
          'region',
        )
      : _asSelection(
          project,
          selection,
          (_MeshTarget target) => target.elements.isEmpty
              ? OpResult.refused(
                  'nothing is selected to grow',
                  selection: target.elements,
                )
              : OpResult.done(selection: target.elements.grown(target.mesh)),
        );
}

/// The selection minus everything on its edge.
final class ShrinkSelection extends ModelCommand {
  const ShrinkSelection();

  @override
  String get name => 'shrinkSelection';

  @override
  String get says => 'shrink the selection';

  @override
  Map<String, Object?> get arguments => const <String, Object?>{};

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) =>
      selection.mode == SelectionMode.object
      ? Outcome.refused(
          'shrinking a selection drops what is on its border, and a project\'s '
          'objects have no border to be on. Switch to mesh mode to narrow a '
          'region',
        )
      : _asSelection(
          project,
          selection,
          (_MeshTarget target) => target.elements.isEmpty
              ? OpResult.refused(
                  'nothing is selected to shrink',
                  selection: target.elements,
                )
              : OpResult.done(selection: target.elements.shrunk(target.mesh)),
        );
}

/// Everything joined to the selection by a chain of edges.
final class SelectLinked extends ModelCommand {
  const SelectLinked();

  @override
  String get name => 'selectLinked';

  @override
  String get says => 'select linked';

  @override
  Map<String, Object?> get arguments => const <String, Object?>{};

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) =>
      selection.mode == SelectionMode.object
      ? Outcome.refused(
          'linked means joined by a chain of edges, which is a question about '
          'the inside of one mesh rather than about the objects in a project',
        )
      : _asSelection(
          project,
          selection,
          (_MeshTarget target) => target.elements.isEmpty
              ? OpResult.refused(
                  'nothing is selected to follow',
                  selection: target.elements,
                )
              : OpResult.done(selection: target.elements.linked(target.mesh)),
        );
}

/// The edges in line with one edge.
///
/// **The edge is named rather than read out of the selection**, for the reason
/// `object_commands.dart` opens with: a journal entry that said "the loop
/// through whatever is selected" would replay against a different selection and
/// pick a different loop. It is also what makes the command answerable by an
/// agent, which has a mesh and a number and no pointer.
final class SelectEdgeLoop extends ModelCommand {
  const SelectEdgeLoop(this.edge);

  /// The half-edge to walk from, as `EditMesh.edgeOf` numbers them — which is
  /// what the edge half of a selection already holds.
  final int edge;

  @override
  String get name => 'selectEdgeLoop';

  @override
  String get says => 'select the edge loop';

  @override
  Map<String, Object?> get arguments => <String, Object?>{'edge': edge};

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) =>
      selection.mode == SelectionMode.object
      ? Outcome.refused(
          'an edge loop is a walk over the inside of one mesh, and object mode '
          'is not pointing at one',
        )
      : _asSelection(
          project,
          selection,
          (_MeshTarget target) => _fromEdge(
            target,
            edge,
            (EditMesh mesh, int half) => Selection.edgeLoop(mesh, half),
          ),
        );
}

/// The edges across the strip of quads one edge runs through.
final class SelectEdgeRing extends ModelCommand {
  const SelectEdgeRing(this.edge);

  /// The half-edge to walk from. See [SelectEdgeLoop.edge].
  final int edge;

  @override
  String get name => 'selectEdgeRing';

  @override
  String get says => 'select the edge ring';

  @override
  Map<String, Object?> get arguments => <String, Object?>{'edge': edge};

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) =>
      selection.mode == SelectionMode.object
      ? Outcome.refused(
          'an edge ring is a walk over the inside of one mesh, and object mode '
          'is not pointing at one',
        )
      : _asSelection(
          project,
          selection,
          (_MeshTarget target) => _fromEdge(
            target,
            edge,
            (EditMesh mesh, int half) => Selection.edgeRing(mesh, half),
          ),
        );
}

/// Every face on one material slot.
final class SelectByMaterial extends ModelCommand {
  const SelectByMaterial(this.slot);

  /// The slot, as the mesh numbers them: an index into the object's
  /// `materialSlots`, not into the project's materials.
  final int slot;

  @override
  String get name => 'selectByMaterial';

  @override
  String get says => 'select by material';

  @override
  Map<String, Object?> get arguments => <String, Object?>{'slot': slot};

  /// **Refused in object mode, and the sentence says where to go.** A slot is
  /// carried by a face; an object carries a whole list of them, so "the objects
  /// on slot two" is a different question with a different answer and would be
  /// a different command. Answering the easier question under the same name is
  /// how a person ends up selecting a hundred objects when they asked for four
  /// faces.
  @override
  Outcome apply(ModelProject project, ProjectSelection selection) =>
      selection.mode == SelectionMode.object
      ? Outcome.refused(
          'a material slot is carried by a face, so this needs mesh mode: an '
          'object carries a list of slots rather than one',
        )
      : _asSelection(project, selection, (_MeshTarget target) {
          final Selection found = Selection.byMaterialSlot(target.mesh, slot);
          return found.isEmpty
              ? OpResult.refused(
                  'no face of "${target.object.name}" is on material slot '
                  '$slot',
                  selection: target.elements,
                )
              : OpResult.done(selection: found);
        });
}
