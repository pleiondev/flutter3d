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
///
/// The mode is not compared, and that is not an oversight. A comparison of it
/// was written, run and found unreachable: every command in this file builds
/// the selection it hands to [_keep] with `copyWith` from the one it was given
/// and none of them passes a mode, so the two are the same object's mode every
/// time. The level *is* compared, because [_asSelection] does change it — an
/// edge loop asked for at vertex level comes back at edge level.
bool _sameSelection(ProjectSelection a, ProjectSelection b) =>
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
/// The number is put through [EditMesh.edgeOf] before it is looked up, and what
/// that buys is one thing rather than two: a click on the far side of a surface
/// names the same edge as the number a selection holds, because the twin
/// canonicalises to the same half-edge of the pair. The walk starting from a
/// half-edge that is on a live face is the `contains` test's doing and not
/// `edgeOf`'s — [_everything] is swept from live faces and holds nothing else,
/// so a number that survives it is live whether or not it was canonicalised
/// first.
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

/// Every face pointing the way [axis] does — `ux-19`.
///
/// **What "the top of the cube" is, said in a way a program can say it.** An
/// agent asked to extrude the top face could name a face id and had no way to
/// find out which id that was: `list` counts the faces and `describe` says
/// where each one points, but turning six normals into "the one that points
/// up" is arithmetic every caller was writing again. This is that arithmetic,
/// once, as a pick that lands on the undo stack like any other.
///
/// **Faces, and so face level, whatever level was live.** A normal is a
/// face's; a vertex has one only by averaging the faces around it and an edge
/// only by averaging its two sides, and "the vertices that point up" on a cube
/// is four vertices of the top face plus every vertex of every face that
/// leans upward — an answer nobody asked for. [_asSelection] carries the level
/// back out with the elements, so a caller in vertex mode lands in face mode
/// holding faces rather than holding face numbers under a vertex level.
final class SelectFacing extends ModelCommand {
  const SelectFacing({required this.axis, this.within = 45.0});

  /// The direction to face, in the object's own space. `[0, 1, 0]` is up.
  /// Need not be a unit vector: it is normalised here, because a caller
  /// typing a direction by hand is thinking about which way it points and not
  /// about its length.
  final Vector3 axis;

  /// How far off [axis] a face may point and still count, in degrees.
  ///
  /// **45° by default, which is the answer to "the top" on a box.** Wider
  /// takes in the sides of a cylinder's cap; narrower misses a face that has
  /// been bevelled. A caller that wants exactly the faces perpendicular to an
  /// axis says so with a small number rather than by post-filtering what came
  /// back.
  final double within;

  @override
  String get name => 'selectFacing';

  @override
  String get says =>
      'select the faces facing ${axis.x}, ${axis.y}, ${axis.z}';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'axis': <double>[axis.x, axis.y, axis.z],
    'within': within,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    if (selection.mode == SelectionMode.object) {
      return Outcome.refused(
        'a normal belongs to a face, so this needs mesh mode: select an '
        'object with a level first',
      );
    }
    if (axis.length2 < 1e-12) {
      return Outcome.refused('the axis has no direction — give a non-zero one');
    }
    if (!(within > 0) || within > 180) {
      return Outcome.refused('"within" is an angle in degrees, 0 to 180');
    }
    final Vector3 wanted = axis.normalized();
    final double least = math.cos(within * math.pi / 180.0);
    return _asSelection(project, selection, (_MeshTarget target) {
      final found = <int>[
        for (final int face in liveElements(target.mesh, ElementLevel.face))
          if (elementNormal(target.mesh, ElementLevel.face, face)
              case final Vector3 normal)
            if (normal.dot(wanted) >= least) face,
      ];
      return found.isEmpty
          ? OpResult.refused(
              'nothing in "${target.object.name}" points that way within '
              '$within°',
              selection: target.elements,
            )
          : OpResult.done(selection: Selection.of(ElementLevel.face, found));
    });
  }
}

/// Everything at the live level within [radius] of [point] — `ux-19`.
///
/// **A box-select for something with no screen.** A person rubber-bands a
/// region; an agent had `selectLinked` and `selectAll` and nothing in between,
/// so "the vertices around the hole at the top" was a list of ids read off
/// `describe` and typed back in. Measured in the object's own space, which is
/// the space `describe` answers in and the space `transformElements` moves in
/// — three coordinate systems for one region would be three chances to pick
/// the wrong one.
///
/// **At whatever level is live, unlike [SelectFacing].** "Within half a metre
/// of here" is a question with an answer at every level, and each answer is
/// the one the person asking that level's question wants: a vertex's position,
/// an edge's midpoint, a face's centroid.
final class SelectNear extends ModelCommand {
  const SelectNear({required this.point, required this.radius});

  final Vector3 point;
  final double radius;

  @override
  String get name => 'selectNear';

  @override
  String get says =>
      'select within $radius of ${point.x}, ${point.y}, ${point.z}';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'point': <double>[point.x, point.y, point.z],
    'radius': radius,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    if (selection.mode == SelectionMode.object) {
      return Outcome.refused(
        'this picks elements, so it needs mesh mode: select an object with a '
        'level first',
      );
    }
    if (!(radius > 0)) {
      return Outcome.refused('the radius has to be a positive distance');
    }
    final double reach = radius * radius;
    return _asSelection(project, selection, (_MeshTarget target) {
      final ElementLevel level = target.elements.level;
      final found = <int>[
        for (final int id in liveElements(target.mesh, level))
          if (elementCentre(target.mesh, level, id) case final Vector3 at)
            if ((at - point).length2 <= reach) id,
      ];
      return found.isEmpty
          ? OpResult.refused(
              'nothing in "${target.object.name}" is within $radius of there',
              selection: target.elements,
            )
          : OpResult.done(selection: Selection.of(level, found));
    });
  }
}

/// Picks whole objects by id, or switches to mesh mode on one object and
/// picks vertices, edges or faces of it by id — a click, named.
///
/// **`tut-05`, closed.** Every command above answers "everything"/"nothing"/
/// "the neighbours of what is already selected" — a walk relative to
/// whatever the selection already holds, needing no id of its own. Naming a
/// *specific* object or a *specific* set of elements is a different kind of
/// pick — the one a mouse click makes, and the one `ModelSession.select`
/// offers a program with no mouse — and it went straight to
/// `ModelHistory.selection =` rather than through any command here, which is
/// exactly what made a case whose edits depend on it (case 2's rim faces,
/// case 3's imported box) unrecoverable from a cold `CommandJournal.replay`:
/// the pick itself was never on the journal to replay. This command is that
/// pick, written down.
///
/// **[level] is a `String` rather than an `ElementLevel`, matching
/// `ModelSession.select`'s own argument** — an agent's JSON names a level by
/// word, and a name nothing recognises is a refusal with a sentence
/// ([apply]'s own "is not a level"), not a decode failure a caller never
/// sees.
final class SelectElements extends ModelCommand {
  const SelectElements({this.objects, this.object, this.level, this.elements});

  /// Object ids to select, in object mode. Ignored when [object] is given.
  final List<int>? objects;

  /// The one object to select elements of, switching to mesh mode. Null picks
  /// whole objects instead, from [objects].
  final int? object;

  /// `"vertex"`, `"edge"` or `"face"` — required together with [object].
  final String? level;

  /// Element ids at [level], within [object]. Meaningless without [object].
  final List<int>? elements;

  @override
  String get name => 'selectElements';

  @override
  String get says => object != null
      ? 'select ${elements?.length ?? 0} '
            '${level ?? 'element'}${(elements?.length ?? 0) == 1 ? '' : 's'}'
      : 'select ${objects?.length ?? 0} '
            'object${(objects?.length ?? 0) == 1 ? '' : 's'}';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    if (objects != null) 'objects': objects,
    if (object != null) 'object': object,
    if (level != null) 'level': level,
    if (elements != null) 'elements': elements,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    if (object != null) {
      final ElementLevel? at = _elementLevelNamed(level);
      if (at == null) {
        return Outcome.refused(
          '"$level" is not a level; it is vertex, edge or face',
        );
      }
      return Outcome.done(
        project,
        selection: ProjectSelection(
          mode: SelectionMode.mesh,
          objects: <int>[object!],
          level: at,
          elements: elements ?? const <int>[],
        ),
      );
    }
    return Outcome.done(
      project,
      selection: ProjectSelection(
        mode: SelectionMode.object,
        objects: objects ?? const <int>[],
      ),
    );
  }
}

ElementLevel? _elementLevelNamed(String? word) {
  for (final ElementLevel level in ElementLevel.values) {
    if (level.name == word) return level;
  }
  return null;
}
