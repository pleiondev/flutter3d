/// Every change to a project is one of these.
///
/// **Sealed, named, and able to write itself down.** Three things fall out of
/// that and none of them can be had from a closure that edits a document:
///
///  * **A history that says what it holds.** `undoSays` on a menu item is the
///    difference between "Undo" and "Undo move three objects", and only a
///    command that carries a sentence can produce it.
///  * **A journal.** A project file records the commands that made it, so a
///    file that fails to open can still be replayed up to the step before the
///    one that broke — which is `doc-31d`, and is why [toJson] is on the
///    command rather than on some writer that knows about all of them.
///  * **An agent that can drive the modeller.** The MCP server's tool table is
///    this list: one tool per command name, arguments straight from
///    [arguments]. A closure cannot be listed, described or called by name.
///
/// **Applying returns a new project or nothing at all.** Nothing is a refusal —
/// with a sentence, because a refusal a person cannot act on is a bug report —
/// and the history leaves its stack alone. There is no third case: a command
/// that half-worked is a command that has to be split.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

// `EnumHint` hidden: `flutter3d_formats`' own is `MaterialHintKind`'s, for a
// material's fields, and this library's `param_hint.dart` names a command
// argument's the same word for the same reason — nothing here reads a
// material's, and the collision is the one the plan's own critique (Г4/Ж2)
// gives for keeping the two hierarchies apart in the first place.
import 'package:flutter3d_core/formats.dart' hide EnumHint;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:vector_math/vector_math.dart';

import 'describe.dart';
import 'job.dart';
import 'key_table.dart';
import 'lod_spec.dart';
import 'material.dart';
import 'modifier_slot.dart';
import 'param_hint.dart';
import 'parametric_json.dart';
import 'project.dart';
import 'project_animation.dart';
import 'project_morphs.dart';
import 'scene_lighting.dart';
import 'selection.dart';
import 'shape_driver.dart';
import 'simulation_bake.dart';
import 'simulation_cache.dart';
import 'texture_bake.dart';
import 'texture_graph.dart';
import 'world_transform.dart';

part 'job_commands.dart';
part 'joint_commands.dart';
part 'keyframe_commands.dart';
part 'lighting_commands.dart';
part 'lod_commands.dart';
part 'material_commands.dart';
part 'mesh_commands.dart';
part 'modifier_commands.dart';
part 'object_commands.dart';
part 'paint_weights.dart';
part 'profile_commands.dart';
part 'rig_job_commands.dart';
part 'root_motion_commands.dart';
part 'selection_commands.dart';
part 'set_rig.dart';
part 'shape_commands.dart';
part 'simulation_commands.dart';
part 'source_commands.dart';
part 'texture_graph_commands.dart';
part 'uv_commands.dart';

/// What a command did.
final class Outcome {
  const Outcome._(this.project, this.selection, this.refused, this.meshTouched);

  /// It worked, and this is the project now.
  ///
  /// [selection] is what should be selected afterwards, which is not always
  /// what was selected before: a command that makes something selects what it
  /// made, because that is what a person wants to move next.
  /// [meshTouched] is the mesh that took a journal step, when one did. See
  /// `mesh_commands.dart`: a mesh is not a value with old versions in it, so
  /// the history has to roll its journal in step with the documents it keeps.
  factory Outcome.done(
    ModelProject project, {
    ProjectSelection? selection,
    EditMesh? meshTouched,
  }) => Outcome._(project, selection, null, meshTouched);

  /// It did not, and this is what to tell somebody.
  factory Outcome.refused(String said) => Outcome._(null, null, said, null);

  final ModelProject? project;
  final ProjectSelection? selection;
  final String? refused;

  /// The mesh whose journal moved on, or null when the command only touched
  /// the document.
  final EditMesh? meshTouched;

  bool get ok => refused == null;
}

/// The point a turn or a scale happens about.
///
/// **An argument on the command rather than a setting the command cannot
/// see.** A journal entry that said "turn ninety degrees" and left the pivot to
/// whatever a toolbar happened to be showing would replay differently from the
/// way it ran — which is the same reason the selection travels with the step
/// rather than being read fresh. An agent driving the modeller has no toolbar
/// at all and has to be able to say which point it means.
///
/// Machinery: these are the pivots the arithmetic in `object_commands.dart` has
/// a branch for. A pivot somebody works out for themselves is a `Vector3`
/// handed over, not a name added here.
enum TransformPivot {
  /// The middle of everything selected. Three objects turned together swing
  /// round each other, which is what a person watching the gizmo expects.
  median,

  /// Each object about its own origin, which leaves the objects where they are
  /// and points them somewhere else.
  individual,
}

/// Whose axes a transform is expressed in.
///
/// **The difference only shows on something already turned, and then it shows
/// every time.** "A metre along X" means one thing to a person reading the
/// world grid and another to a person looking at a car parked sideways, and a
/// tool that offers only the first leaves the second to do the arithmetic by
/// hand.
///
/// Machinery, for the reason [TransformPivot] is: two is what a basis can be
/// taken from — the world, or the thing being moved — and a third would be
/// somebody else's matrix, which is a matrix rather than a name.
enum TransformSpace {
  /// The world's axes: the same X for everything selected, whatever each of
  /// them is facing.
  global,

  /// The axes of the object being transformed, so two objects in one selection
  /// can go different ways under one command.
  local,
}

/// [by] wrapped so that it happens at [about], along [basis]'s axes when one is
/// given and along the world's when it is not.
///
/// Written in steps because `Matrix4 * Matrix4` is declared to return `dynamic`
/// in vector_math, and a chain of them is a chain of dynamic calls that the
/// analyser is right to complain about: one wrong operand type and the failure
/// arrives at run time as a matrix full of NaN.
Matrix4 _sandwiched(Vector3 about, Matrix4? basis, Matrix4 by) {
  final Matrix4 out = Matrix4.translation(about);
  if (basis == null) {
    out.multiply(by);
  } else {
    out.multiply(basis);
    out.multiply(by);
    out.multiply(Matrix4.inverted(basis));
  }
  out.multiply(Matrix4.translation(-about));
  return out;
}

/// The rotation in [transform], with the translation and the scale taken out.
///
/// **Decomposed rather than read straight off the upper three by three**, which
/// would be the rotation multiplied by the scale. Sandwiching a turn in a
/// matrix that also scales unevenly gives a shear, so an object stretched along
/// one axis would come out of a local-space turn bent rather than turned.
Matrix4 _basisOf(Matrix4 transform) {
  final translation = Vector3.zero();
  final rotation = Quaternion.identity();
  final scale = Vector3.zero();
  transform.decompose(translation, rotation, scale);
  return Matrix4.compose(Vector3.zero(), rotation, Vector3.all(1));
}

/// One change, as a value.
sealed class ModelCommand {
  const ModelCommand();

  /// The name this is written down and looked up under. Stable: it is in files
  /// and in an agent's tool table, and renaming one breaks both.
  String get name;

  /// What the history offers to undo, in words a person recognises. Present
  /// tense and lower case — the interface puts it after "Undo".
  String get says;

  /// The arguments, as the journal and an agent see them.
  Map<String, Object?> get arguments;

  /// What a control for one of [arguments] should look like, keyed the same
  /// way — a step, a range, a unit, or which of the four kinds it even is.
  ///
  /// **A subset of [arguments], not a mirror of it.** An id or an index has
  /// nothing here to say: a control for "which object" is a selection, not a
  /// number line, and `SetParametric`'s own shape parameters already carry
  /// their hints through `ParametricShape` rather than through this — giving
  /// them a second copy here would be two answers to "what step does this
  /// take" that a shape's own author could disagree with. Empty by default,
  /// so a command with nothing numeric in it — most of them — says nothing
  /// rather than an empty map somebody has to write out each time.
  Map<String, ParamHint> get hints => const <String, ParamHint>{};

  /// Applies this to [project], with [selection] as it was when the command was
  /// made.
  Outcome apply(ModelProject project, ProjectSelection selection);

  /// Whether a successful run of this should be written to whichever
  /// `CommandJournal` a [ModelHistory] has attached, when one is. True for
  /// every command except [ReplaceDocument] — see that class's own doc
  /// comment for why a line naming it could never be read back.
  ///
  /// **On the command rather than left to each call site to remember.**
  /// [ModelHistory.run] used to journal nothing itself — a caller recorded
  /// to its own `CommandJournal` by hand, and one that called [run] directly
  /// rather than through that wrapper (`ModelSession.import`'s own
  /// [ReplaceDocument] call, deliberately) simply never did. Once [run]
  /// journals on behalf of every caller (`tut-15`), that same exemption has
  /// to travel with the command itself, or every caller earns the exemption
  /// back by remembering which door to call [run] through — exactly the kind
  /// of thing this row exists to stop depending on.
  bool get isJournaled => true;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    ...arguments,
  };

  @override
  String toString() =>
      '$name(${arguments.entries.map((MapEntry<String, Object?> e) => '${e.key}: ${e.value}').join(', ')})';
}

/// Swaps the whole document for [next], as one undo step.
///
/// **Deliberately not in [modelCommandNames], not in [modelCommandFromJson],
/// and [isJournaled] is false.** Every other command describes an edit small
/// enough to write down and replay — a number, an id, a list of points; this
/// one carries a whole [ModelProject], which is what an importer builds from
/// a decoded file and a journal has no honest way to store — a line naming it
/// would read back only `{"name": "replaceDocument"}`, nothing of [next], and
/// [modelCommandFromJson] would refuse it anyway since it is not in that
/// table. It exists so that bringing in an external model —
/// `flutter3d_model_mcp`'s `import`, and later `doc-11a-n`'s `ImportInto` —
/// still goes through [ModelHistory] and can be undone as itself, rather than
/// needing a second, private way to push a step that every other command
/// already has for free.
final class ReplaceDocument extends ModelCommand {
  const ReplaceDocument(this.next, this.says);

  final ModelProject next;

  @override
  final String says;

  @override
  String get name => 'replaceDocument';

  @override
  Map<String, Object?> get arguments => const <String, Object?>{};

  @override
  bool get isJournaled => false;

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) =>
      Outcome.done(next);
}

/// Renames one object.
final class Rename extends ModelCommand {
  const Rename({required this.id, required this.to});

  final int id;
  final String to;

  @override
  String get name => 'rename';

  @override
  String get says => 'rename to "$to"';

  @override
  Map<String, Object?> get arguments => <String, Object?>{'id': id, 'to': to};

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final object = project[id];
    if (object == null) return Outcome.refused('there is no object $id');
    if (to.trim().isEmpty) {
      // Refused rather than accepted and shown as blank: an object with no name
      // is one a person cannot find in the outliner or name in a command.
      return Outcome.refused('an object needs a name');
    }
    return Outcome.done(project.withObject(object.copyWith(name: to)));
  }
}

/// Puts a transform on one object, replacing whatever it had.
final class SetTransform extends ModelCommand {
  const SetTransform({required this.id, required this.to});

  final int id;
  final Matrix4 to;

  @override
  String get name => 'setTransform';

  @override
  String get says => 'set the transform';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'id': id,
    'to': to.storage.toList(),
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final object = project[id];
    if (object == null) return Outcome.refused('there is no object $id');
    return Outcome.done(
      project.withObject(object.copyWith(transform: Matrix4.copy(to))),
    );
  }
}

/// Moves everything selected.
///
/// **By an amount rather than to a place, which is what makes a drag one step.**
/// A hundred `SetTransform`s coalesce into one only if the history knows they
/// are the same command; a hundred `MoveBy`s coalesce because adding them up is
/// what they mean. `ModelHistory.transaction` does the collapsing and this is
/// the shape that lets it.
final class MoveBy extends ModelCommand {
  const MoveBy(this.by, {this.space = TransformSpace.global});

  final Vector3 by;

  /// Whose axes [by] is measured along — `ux-12`.
  ///
  /// **A move has a space but no pivot.** Sliding something does not turn it,
  /// so where the turn would be centred makes no difference to the answer;
  /// which way "along X" points does, and under [TransformSpace.local] two
  /// objects facing different ways go different ways under one command, which
  /// is the whole reason the chip exists.
  final TransformSpace space;

  @override
  String get name => 'moveBy';

  @override
  String get says => 'move';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'by': <double>[by.x, by.y, by.z],
    if (space != TransformSpace.global) 'space': space.name,
  };

  @override
  Map<String, ParamHint> get hints => const <String, ParamHint>{
    'by': Vector3Hint(unit: 'm', step: 0.1),
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    if (selection.objects.isEmpty) {
      return Outcome.refused('nothing is selected to move');
    }
    if (space == TransformSpace.local) {
      // Through the same applier the turn and the scale use: a translation
      // sandwiched in each object's own basis is exactly "along its own
      // axes", and the pivot cancels out of a translation, which is why it
      // is not a parameter here.
      return _aboutThePivot(
        project,
        selection,
        'move',
        pivot: TransformPivot.individual,
        space: space,
        build: () => Matrix4.translation(by),
      );
    }
    var next = project;
    for (final int id in selection.objects) {
      final object = next[id];
      // Skipped rather than refused: a selection may name an object a previous
      // step deleted, and refusing the whole move because one member is gone
      // would make a drag stop working for reasons nobody can see.
      if (object == null) continue;
      next = next.withObject(
        object.copyWith(
          transform: Matrix4.copy(object.transform)..leftTranslateByVector3(by),
        ),
      );
    }
    return Outcome.done(next);
  }
}

/// Deletes everything selected, and everything under it.
final class DeleteObjects extends ModelCommand {
  const DeleteObjects();

  @override
  String get name => 'deleteObjects';

  @override
  String get says => 'delete';

  @override
  Map<String, Object?> get arguments => const <String, Object?>{};

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    if (selection.objects.isEmpty) {
      return Outcome.refused('nothing is selected to delete');
    }
    var next = project;
    for (final int id in selection.objects) {
      next = next.removed(id);
    }
    return Outcome.done(
      next,
      selection: selection.copyWith(objects: const <int>[]),
    );
  }
}

/// Copies everything selected, offset by nothing, and selects the copies.
final class DuplicateObjects extends ModelCommand {
  const DuplicateObjects();

  @override
  String get name => 'duplicateObjects';

  @override
  String get says => 'duplicate';

  @override
  Map<String, Object?> get arguments => const <String, Object?>{};

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    if (selection.objects.isEmpty) {
      return Outcome.refused('nothing is selected to duplicate');
    }
    var next = project;
    final made = <int>[];
    for (final int id in selection.objects) {
      final object = next[id];
      if (object == null) continue;
      // A parametric or an imported geometry is replaced whole by the
      // commands that touch it — `SetParametric` hands back a new
      // `ParametricGeometry`, an imported `MeshData` is never written to — so
      // two objects pointing at the same one is the same structural sharing
      // `ModelProject` itself uses, and free.
      //
      // **An edited mesh cannot share that way.** `EditMesh` is a journal
      // mutated in place — see `mesh_commands.dart` — so a copy sharing the
      // original's `EditMesh` would have every mesh command run against it
      // edit the original too. It is copied through `toBytes`/`fromBytes`
      // instead, which is a real copy at a real cost; there is no cheaper
      // correct one until `EditMesh` itself has a copy-on-write story.
      final Geometry geometry = switch (object.geometry) {
        EditedGeometry(:final mesh) => EditedGeometry(
          EditMesh.fromBytes(mesh.toBytes()),
        ),
        final Geometry shared => shared,
      };
      next = next.added(
        (int fresh) => ModelObject(
          id: fresh,
          name: '${object.name} copy',
          geometry: geometry,
          transform: Matrix4.copy(object.transform),
          parent: object.parent,
          materialSlots: object.materialSlots,
        ),
      );
      made.add(next.objects.last.id);
    }
    if (made.isEmpty) {
      return Outcome.refused('everything selected has already gone');
    }
    return Outcome.done(next, selection: selection.copyWith(objects: made));
  }
}

/// Every command a journal, a project file or an agent can name — the keys
/// of [_modelCommandReaders], in the order they are written there.
///
/// **One table rather than a list beside a `switch`.** A command's name and
/// the code that reads it back used to be written twice, ninety-odd lines
/// apart, and kept in step by a test; a name is now the key its reader sits
/// under, so there is nothing left to keep in step.
final List<String> modelCommandNames = List<String>.unmodifiable(
  _modelCommandReaders.keys,
);

/// Reads a command back out of a journal, or null.
///
/// **Null and not an exception**, for the reason `ProjectSelection.fromJson`
/// gives: a journal is replayed entry by entry and an entry from a newer
/// version of the application is one to skip, not one to fail the whole file
/// over.
ModelCommand? modelCommandFromJson(Object? json) {
  if (json is! Map<String, Object?>) return null;
  final Object? name = json['name'];
  return name is String ? _modelCommandReaders[name]?.call(json) : null;
}

/// How each command is read back out of its own [ModelCommand.toJson],
/// keyed by [ModelCommand.name]. A reader answers null for arguments it
/// cannot read, never a half-built command.
final Map<String, ModelCommand? Function(Map<String, Object?> json)>
_modelCommandReaders =
    <String, ModelCommand? Function(Map<String, Object?> json)>{
      'rename': (json) => switch ((json['id'], json['to'])) {
        (final int id, final String to) => Rename(id: id, to: to),
        _ => null,
      },
      'setTransform': (json) =>
          switch ((json['id'], _doubles(json['to'], 16))) {
            (final int id, final List<double> to) => SetTransform(
              id: id,
              to: Matrix4.fromList(to),
            ),
            _ => null,
          },
      'moveBy': (json) => switch (_doubles(json['by'], 3)) {
        final List<double> by => MoveBy(
          Vector3(by[0], by[1], by[2]),
          // `ux-12`: a move carries a space now. An entry written before it
          // did says nothing, and `_space` answers that with the global one
          // it always meant.
          space: _space(json['space']) ?? TransformSpace.global,
        ),
        _ => null,
      },
      'rotateBy': (json) => switch ((
        _doubles(json['axis'], 3),
        json['radians'],
        _pivot(json['pivot']),
        _space(json['space']),
      )) {
        (
          final List<double> axis,
          final num radians,
          final TransformPivot pivot,
          final TransformSpace space,
        ) =>
          RotateBy(
            axis: Vector3(axis[0], axis[1], axis[2]),
            radians: radians.toDouble(),
            pivot: pivot,
            space: space,
          ),
        _ => null,
      },
      'scaleBy': (json) => switch ((json['by'], _pivot(json['pivot']))) {
        (final num by, final TransformPivot pivot) => ScaleBy(
          by.toDouble(),
          pivot: pivot,
        ),
        _ => null,
      },
      'setParent': (json) => switch ((json['id'], json['to'])) {
        (final int id, final int? to) => SetParent(id: id, to: to),
        _ => null,
      },
      // `ux-14`'s own two.
      'setObjectVisible': (json) => switch ((json['id'], json['to'])) {
        (final int id, final bool to) => SetObjectVisible(id: id, to: to),
        _ => null,
      },
      'setObjectLocked': (json) => switch ((json['id'], json['to'])) {
        (final int id, final bool to) => SetObjectLocked(id: id, to: to),
        _ => null,
      },
      'setOrigin': (json) => switch ((json['id'], _placement(json['to']))) {
        (final int id, final OriginPlacement to) => SetOrigin(id: id, to: to),
        _ => null,
      },
      'applyTransform': (json) => switch (json['id']) {
        final int id => ApplyTransform(id),
        _ => null,
      },
      'addLathe': (json) => switch (_points(json['profile'])) {
        final List<Vector2> profile => AddLathe(
          profile: profile,
          segments: switch (json['segments']) {
            final int segments => segments,
            _ => 32,
          },
          closedProfile: json['closedProfile'] as bool? ?? false,
          shapeName: json['label'] as String? ?? 'lathe',
          at: switch (_doubles(json['at'], 3)) {
            final List<double> at => Vector3(at[0], at[1], at[2]),
            _ => null,
          },
        ),
        _ => null,
      },
      'addSocket': (json) => AddSocket(
        label: json['label'] as String? ?? 'socket',
        at: switch (_doubles(json['at'], 3)) {
          final List<double> at => Vector3(at[0], at[1], at[2]),
          _ => null,
        },
      ),
      'setParametric': (json) => switch ((json['id'], _shapeOf(json['to']))) {
        (final int id, final ParametricShape to) => SetParametric(
          id: id,
          to: to,
        ),
        _ => null,
      },
      'addPrimitive': (json) => switch (json['kind']) {
        final String kind => AddPrimitive(
          // `ux-43`: one shape, one meaning, whichever of its two names a
          // caller uses. The project format has written `cuboid` since the
          // first file it saved and cannot stop; `primitiveKinds` has said
          // `box` for as long, because that is the word on the menu. An
          // agent that read a `.f3dproj` and then asked for another one of
          // those was refused for spelling it the way the file did.
          kind: kind == 'cuboid' ? 'box' : kind,
          size: switch (json['size']) {
            final num size => size.toDouble(),
            _ => 1.0,
          },
          segments: switch (json['segments']) {
            final int segments => segments,
            _ => 32,
          },
          at: switch (_doubles(json['at'], 3)) {
            final List<double> at => Vector3(at[0], at[1], at[2]),
            _ => null,
          },
        ),
        _ => null,
      },
      'bakeToMesh': (json) => switch (json['id']) {
        final int id => BakeToMesh(id),
        _ => null,
      },
      // `ux-16`'s own: the import screen's weld, offered again on an object
      // already open.
      'buildTopology': (json) => switch (json['id']) {
        final int id => BuildTopology(
          id: id,
          weld: switch (json['weld']) {
            final num it => it.toDouble(),
            _ => null,
          },
        ),
        _ => null,
      },
      'deleteObjects': (json) => const DeleteObjects(),
      'duplicateObjects': (json) => const DuplicateObjects(),
      'extrude': (json) => switch (json['distance']) {
        final num distance => Extrude(distance.toDouble()),
        _ => null,
      },
      'loopCut': (json) => LoopCut(
        cuts: switch (json['cuts']) {
          final int cuts => cuts,
          _ => 1,
        },
        factor: switch (json['factor']) {
          final num factor => factor.toDouble(),
          _ => 0.5,
        },
      ),
      'bevelEdges': (json) => switch (json['width']) {
        final num width => BevelEdges(
          width.toDouble(),
          segments: switch (json['segments']) {
            final int segments => segments,
            _ => 1,
          },
          clampOverlap: json['clampOverlap'] as bool? ?? true,
        ),
        _ => null,
      },
      'deleteElements': (json) => const DeleteElements(),
      'mergeByDistance': (json) => MergeByDistance(
        distance: switch (json['distance']) {
          final num how => how.toDouble(),
          _ => null,
        },
      ),
      'dissolveEdges': (json) => const DissolveEdges(),
      'separate': (json) => const Separate(),
      'fillHoles': (json) => const FillHoles(),
      'triangulate': (json) => const Triangulate(),
      'recalculateNormals': (json) =>
          RecalculateNormals(flip: json['flip'] as bool? ?? false),
      'markSeam': (json) => MarkSeam(on: json['on'] as bool? ?? true),
      'unwrap': (json) => UnwrapCommand(
        margin: switch (json['margin']) {
          final num margin => margin.toDouble(),
          _ => 0.01,
        },
        autoPack: json['autoPack'] as bool? ?? true,
      ),
      'transformElements': (json) => switch ((
        _doubles(json['by'], 16),
        json['what'],
        _pivot(json['pivot']),
        _space(json['space']),
      )) {
        (
          final List<double> by,
          final String what,
          final TransformPivot pivot,
          final TransformSpace space,
        ) =>
          TransformElements(
            Matrix4.fromList(by),
            what: what,
            pivot: pivot,
            space: space,
          ),
        _ => null,
      },
      'selectAll': (json) => const SelectAll(),
      'selectNone': (json) => const SelectNone(),
      'invertSelection': (json) => const InvertSelection(),
      'growSelection': (json) => const GrowSelection(),
      'shrinkSelection': (json) => const ShrinkSelection(),
      'selectLinked': (json) => const SelectLinked(),
      'selectEdgeLoop': (json) => switch (json['edge']) {
        final int edge => SelectEdgeLoop(edge),
        _ => null,
      },
      'selectEdgeRing': (json) => switch (json['edge']) {
        final int edge => SelectEdgeRing(edge),
        _ => null,
      },
      'selectByMaterial': (json) => switch (json['slot']) {
        final int slot => SelectByMaterial(slot),
        _ => null,
      },
      // `ux-19`. `within` and `radius` are read the same way every other
      // number in this reader is — a `num` that may have arrived as an int
      // from JSON — and `within` falls back to the command's own default
      // rather than refusing, since a caller that did not name an angle is
      // asking for "the faces that point this way" and not for a syntax
      // error.
      'selectFacing': (json) => switch (_doubleListFrom(json['axis'])) {
        final List<double> axis when axis.length == 3 => SelectFacing(
          axis: Vector3(axis[0], axis[1], axis[2]),
          within: switch (json['within']) {
            final num within => within.toDouble(),
            _ => 45.0,
          },
        ),
        _ => null,
      },
      'selectNear': (json) =>
          switch ((_doubleListFrom(json['point']), json['radius'])) {
            (final List<double> point, final num radius)
                when point.length == 3 =>
              SelectNear(
                point: Vector3(point[0], point[1], point[2]),
                radius: radius.toDouble(),
              ),
            _ => null,
          },
      // `tut-05`: registered so a journal line — or an MCP `select` call,
      // read back through `_command`-style reader — replays a specific pick
      // rather than only the walks above. Every field is optional on
      // `SelectElements` itself, so there is nothing here for this reader to
      // refuse on.
      'selectElements': (json) => SelectElements(
        objects: _intListFrom(json['objects']),
        object: switch (json['object']) {
          final int object => object,
          _ => null,
        },
        level: switch (json['level']) {
          final String level => level,
          _ => null,
        },
        elements: _intListFrom(json['elements']),
      ),
      'addLight': (json) => AddLight(
        type: switch (json['type']) {
          final String type => ProjectLightType.values.firstWhere(
            (ProjectLightType t) => t.name == type,
            orElse: () => ProjectLightType.directional,
          ),
          _ => ProjectLightType.directional,
        },
        // `ux-23`. Absent is the identity transform a light has always had,
        // which is what a journal written before this existed replays to.
        at: switch (_doubleListFrom(json['at'])) {
          final List<double> at when at.length == 3 => Vector3(
            at[0],
            at[1],
            at[2],
          ),
          _ => null,
        },
      ),
      'removeLight': (json) => switch (json['index']) {
        final int index => RemoveLight(index),
        _ => null,
      },
      'setLightField': (json) => switch ((json['index'], json['field'])) {
        (final int index, final String field) => SetLightField(
          index: index,
          field: field,
          value: json['value'],
        ),
        _ => null,
      },
      'setLightTransform': (json) =>
          switch ((json['index'], _doubles(json['to'], 16))) {
            (final int index, final List<double> to) => SetLightTransform(
              index: index,
              to: Matrix4.fromList(to),
            ),
            _ => null,
          },
      'setEnvironment': (json) => switch (json['preset']) {
        final String preset => SetEnvironment(
          SceneEnvironmentPreset.values.firstWhere(
            (SceneEnvironmentPreset p) => p.name == preset,
            orElse: () => SceneEnvironmentPreset.none,
          ),
        ),
        _ => null,
      },
      'setSceneLightingField': (json) => switch (json['field']) {
        final String field => SetSceneLightingField(
          field: field,
          value: json['value'],
        ),
        _ => null,
      },
      'addMaterial': (json) =>
          AddMaterial(materialName: json['materialName'] as String?),
      'removeMaterial': (json) => switch (json['index']) {
        final int index => RemoveMaterial(index),
        _ => null,
      },
      'duplicateMaterial': (json) => switch (json['index']) {
        final int index => DuplicateMaterial(index),
        _ => null,
      },
      'setMaterialField': (json) => switch ((json['index'], json['field'])) {
        (final int index, final String field) => SetMaterialField(
          index: index,
          field: field,
          value: json['value'],
        ),
        _ => null,
      },
      'setTexture': (json) => switch ((json['materialIndex'], json['slot'])) {
        (final int materialIndex, final String slot) => SetTexture(
          materialIndex: materialIndex,
          slot: slot,
          imageIndex: json['imageIndex'] as int?,
          sampling: TextureSampling(
            magLinear: json['magLinear'] as bool? ?? true,
            minLinear: json['minLinear'] as bool? ?? true,
            useMipmaps: json['useMipmaps'] as bool? ?? true,
            wrapS: _wrapNamed(json['wrapS']),
            wrapT: _wrapNamed(json['wrapT']),
          ),
        ),
        _ => null,
      },
      'addImage': (json) => switch (json['bytes']) {
        final String encoded => AddImage(
          bytes: base64Decode(encoded),
          imageName: json['imageName'] as String?,
          mimeType: json['mimeType'] as String?,
        ),
        _ => null,
      },
      'assignMaterial': (json) => switch ((json['id'], json['to'])) {
        (final int id, final int? to) => AssignMaterial(id: id, to: to),
        _ => null,
      },
      'linkMaterialFile': (json) => switch ((json['index'], json['path'])) {
        (final int index, final String path) => LinkMaterialFile(
          index: index,
          path: path,
          bytes: switch (json['bytes']) {
            final String encoded => base64Decode(encoded),
            _ => null,
          },
        ),
        _ => null,
      },
      'embedMaterial': (json) => switch (json['index']) {
        final int index => EmbedMaterial(index),
        _ => null,
      },
      'setMaterialGraph': (json) => switch (json['materialIndex']) {
        final int materialIndex => SetMaterialGraph(
          materialIndex: materialIndex,
          graph: switch (json['graph']) {
            final Map<String, Object?> g => TextureGraph.fromJson(g),
            _ => null,
          },
        ),
        _ => null,
      },
      'bakeTextureGraph': (json) => switch (json['materialIndex']) {
        final int materialIndex => BakeTextureGraph(
          materialIndex: materialIndex,
          size: json['size'] as int? ?? 1024,
        ),
        _ => null,
      },
      'addNode': (json) => switch ((json['materialIndex'], json['kind'])) {
        (final int materialIndex, final String kind) => AddNode(
          materialIndex: materialIndex,
          kind: kind,
          fields: switch (json['fields']) {
            final Map<String, Object?> fields => fields,
            _ => const <String, Object?>{},
          },
          position: (
            (json['x'] as num?)?.toDouble() ?? 0.0,
            (json['y'] as num?)?.toDouble() ?? 0.0,
          ),
        ),
        _ => null,
      },
      'link': (json) => switch ((
        json['materialIndex'],
        json['nodeId'],
        json['input'],
        json['from'],
      )) {
        (
          final int materialIndex,
          final int nodeId,
          final String input,
          final int from,
        ) =>
          Link(
            materialIndex: materialIndex,
            nodeId: nodeId,
            input: input,
            from: from,
          ),
        _ => null,
      },
      'unlink': (json) => switch ((
        json['materialIndex'],
        json['nodeId'],
        json['input'],
      )) {
        (final int materialIndex, final int nodeId, final String input) =>
          Unlink(materialIndex: materialIndex, nodeId: nodeId, input: input),
        _ => null,
      },
      'setNodeField': (json) =>
          switch ((json['materialIndex'], json['nodeId'], json['field'])) {
            (final int materialIndex, final int nodeId, final String field) =>
              SetNodeField(
                materialIndex: materialIndex,
                nodeId: nodeId,
                field: field,
                value: json['value'],
              ),
            _ => null,
          },
      'moveNode': (json) => switch ((
        json['materialIndex'],
        json['nodeId'],
        json['x'],
        json['y'],
      )) {
        (final int materialIndex, final int nodeId, final num x, final num y) =>
          MoveNode(
            materialIndex: materialIndex,
            nodeId: nodeId,
            x: x.toDouble(),
            y: y.toDouble(),
          ),
        _ => null,
      },
      'removeNode': (json) => switch ((json['materialIndex'], json['nodeId'])) {
        (final int materialIndex, final int nodeId) => RemoveNode(
          materialIndex: materialIndex,
          nodeId: nodeId,
        ),
        _ => null,
      },
      'addModifier': (json) => switch ((json['id'], json['modifier'])) {
        (final int id, final Object? modifierJson) => switch (modifierFromJson(
          modifierJson,
        )) {
          final Modifier modifier => AddModifier(id: id, modifier: modifier),
          null => null,
        },
        _ => null,
      },
      'setModifierField': (json) => switch ((
        json['id'],
        json['index'],
        json['field'],
      )) {
        (final int id, final int index, final String field) => SetModifierField(
          id: id,
          index: index,
          field: field,
          value: json['value'],
        ),
        _ => null,
      },
      'toggleModifier': (json) => switch ((json['id'], json['index'])) {
        (final int id, final int index) => ToggleModifier(id: id, index: index),
        _ => null,
      },
      // `ux-13`'s own twin of it.
      'toggleModifierExport': (json) => switch ((json['id'], json['index'])) {
        (final int id, final int index) => ToggleModifierExport(
          id: id,
          index: index,
        ),
        _ => null,
      },
      'reorderModifier': (json) =>
          switch ((json['id'], json['from'], json['to'])) {
            (final int id, final int from, final int to) => ReorderModifier(
              id: id,
              from: from,
              to: to,
            ),
            _ => null,
          },
      'removeModifier': (json) => switch ((json['id'], json['index'])) {
        (final int id, final int index) => RemoveModifier(id: id, index: index),
        _ => null,
      },
      'applyModifier': (json) => switch ((json['id'], json['index'])) {
        (final int id, final int index) => ApplyModifier(id: id, index: index),
        _ => null,
      },
      // `ux-49`: the panorama beside the four presets. A null index is
      // "clear it", which is why `index` is read as `int?` rather than
      // refused when absent.
      'setPanorama': (json) => SetPanorama(index: json['index'] as int?),
      // `ux-48`: the three that link an object to the file it came from.
      'linkToSource': (json) =>
          switch ((json['id'], json['path'], json['sha'])) {
            (final int id, final String path, final String sha) => LinkToSource(
              id: id,
              path: path,
              sha: sha,
            ),
            _ => null,
          },
      'unlinkSource': (json) => switch (json['id']) {
        final int id => UnlinkSource(id: id),
        _ => null,
      },
      'reimport': (json) =>
          switch ((json['id'], json['sha'], json['meshBytes'])) {
            (final int id, final String sha, final String encoded) => Reimport(
              id: id,
              sha: sha,
              meshBytes: base64Decode(encoded),
            ),
            _ => null,
          },
      'applyJobResult': (json) =>
          switch ((json['objectId'], json['baseVersion'], json['meshBytes'])) {
            (final int objectId, final int baseVersion, final String encoded) =>
              ApplyJobResult(
                objectId: objectId,
                baseVersion: baseVersion,
                meshBytes: base64Decode(encoded),
              ),
            _ => null,
          },
      'applySimulationCache': (json) =>
          switch ((json['objectId'], json['baseVersion'], json['cache'])) {
            (
              final int objectId,
              final int baseVersion,
              final Map<String, Object?> cacheJson,
            ) =>
              switch (SimulationCache.fromJson(cacheJson)) {
                final SimulationCache cache => ApplySimulationCache(
                  objectId: objectId,
                  baseVersion: baseVersion,
                  cache: cache,
                ),
                null => null,
              },
            _ => null,
          },
      // `tut-14`: registered so a journal line — or an MCP `applyClipResult`
      // call — can name this command at all; `rig_job_commands.dart`'s own
      // doc comment on [ApplyClipResult] used to say this stayed out on
      // purpose, pending exactly this row.
      'applyClipResult': (json) => switch (_clipFromJson(json['clip'])) {
        final ProjectClip clip
            when json['clipIndex'] == null || json['clipIndex'] is int =>
          ApplyClipResult(clip: clip, clipIndex: json['clipIndex'] as int?),
        _ => null,
      },
      'bakeSimulationToShapes': (json) => switch (json['id']) {
        final int id => BakeSimulationToShapes(
          id: id,
          maxKeys: json['maxKeys'] as int? ?? 8,
        ),
        _ => null,
      },
      'setProfileLimits': (json) => SetProfileLimits(
        maxJoints: json['maxJoints'] as int?,
        maxInfluences: json['maxInfluences'] as int?,
      ),
      'setShapeWeight': (json) =>
          switch ((json['id'], json['shapeIndex'], json['weight'])) {
            (final int id, final int shapeIndex, final num weight) =>
              SetShapeWeight(
                id: id,
                shapeIndex: shapeIndex,
                weight: weight.toDouble(),
              ),
            _ => null,
          },
      'addShapeFromMesh': (json) => switch ((json['id'], json['shapeName'])) {
        (final int id, final String shapeName) => AddShapeFromMesh(
          id: id,
          shapeName: shapeName,
        ),
        _ => null,
      },
      'renameShape': (json) =>
          switch ((json['id'], json['shapeIndex'], json['to'])) {
            (final int id, final int shapeIndex, final String to) =>
              RenameShape(id: id, shapeIndex: shapeIndex, to: to),
            _ => null,
          },
      'deleteShape': (json) => switch ((json['id'], json['shapeIndex'])) {
        (final int id, final int shapeIndex) => DeleteShape(
          id: id,
          shapeIndex: shapeIndex,
        ),
        _ => null,
      },
      'keyShape': (json) =>
          switch ((json['id'], json['clipIndex'], json['time'])) {
            (final int id, final int clipIndex, final num time) => KeyShape(
              id: id,
              clipIndex: clipIndex,
              time: time.toDouble(),
            ),
            _ => null,
          },
      'addShapeDriver': (json) => switch ((json['id'], json['driver'])) {
        (final int id, final Object? driverJson) =>
          switch (ShapeDriver.fromJson(driverJson)) {
            final ShapeDriver driver => AddShapeDriver(id: id, driver: driver),
            null => null,
          },
        _ => null,
      },
      'removeShapeDriver': (json) => switch ((json['id'], json['index'])) {
        (final int id, final int index) => RemoveShapeDriver(
          id: id,
          index: index,
        ),
        _ => null,
      },
      'setShapeDriverField': (json) =>
          switch ((json['id'], json['index'], json['field'])) {
            (final int id, final int index, final String field) =>
              SetShapeDriverField(
                id: id,
                index: index,
                field: field,
                value: json['value'],
              ),
            _ => null,
          },
      'addSkeleton': (json) =>
          AddSkeleton(skeletonName: json['skeletonName'] as String?),
      'bindSkin': (json) => switch ((json['objectId'], json['skeletonIndex'])) {
        (final int objectId, final int skeletonIndex) => BindSkin(
          objectId: objectId,
          skeletonIndex: skeletonIndex,
        ),
        _ => null,
      },
      'addJoint': (json) => switch ((json['skeletonIndex'], json['objectId'])) {
        (final int skeletonIndex, final int objectId) => AddJoint(
          skeletonIndex: skeletonIndex,
          objectId: objectId,
          inverseBindMatrix: switch (_doubles(json['inverseBindMatrix'], 16)) {
            final List<double> m => Matrix4.fromList(m),
            null => null,
          },
        ),
        _ => null,
      },
      'removeJoint': (json) =>
          switch ((json['skeletonIndex'], json['jointIndex'])) {
            (final int skeletonIndex, final int jointIndex) => RemoveJoint(
              skeletonIndex: skeletonIndex,
              jointIndex: jointIndex,
            ),
            _ => null,
          },
      'renameJoint': (json) =>
          switch ((json['skeletonIndex'], json['jointIndex'], json['to'])) {
            (final int skeletonIndex, final int jointIndex, final String to) =>
              RenameJoint(
                skeletonIndex: skeletonIndex,
                jointIndex: jointIndex,
                to: to,
              ),
            _ => null,
          },
      'reparentJoint': (json) =>
          switch ((json['skeletonIndex'], json['jointIndex'])) {
            (final int skeletonIndex, final int jointIndex) => ReparentJoint(
              skeletonIndex: skeletonIndex,
              jointIndex: jointIndex,
              to: json['to'] as int?,
            ),
            _ => null,
          },
      'setRestPose': (json) => switch ((
        json['skeletonIndex'],
        json['jointIndex'],
        _doubles(json['worldTransform'], 16),
      )) {
        (
          final int skeletonIndex,
          final int jointIndex,
          final List<double> worldTransform,
        ) =>
          SetRestPose(
            skeletonIndex: skeletonIndex,
            jointIndex: jointIndex,
            worldTransform: Matrix4.fromList(worldTransform),
          ),
        _ => null,
      },
      'mirrorJoints': (json) =>
          switch ((json['skeletonIndex'], json['axis'], json['jointMirror'])) {
            (
              final int skeletonIndex,
              final int axis,
              final Map<String, Object?> jointMirror,
            ) =>
              MirrorJoints(
                skeletonIndex: skeletonIndex,
                axis: axis,
                jointMirror: jointMirror.map(
                  (key, value) => MapEntry(int.parse(key), value! as int),
                ),
              ),
            _ => null,
          },
      'setRig': (json) => switch ((
        _jointObjectsFrom(json['jointObjects']),
        _rigSkeletonFromJson(json['skeleton']),
        json['label'],
      )) {
        (
          final List<ModelObject> jointObjects,
          final ProjectSkeleton skeleton,
          final String label,
        ) =>
          switch (json['weights']) {
            null => SetRig(
              jointObjects: jointObjects,
              skeleton: skeleton,
              skinObjectId: json['skinObjectId'] as int?,
              label: label,
            ),
            final Object? weightsJson => switch (SkinWeightsBlob.fromJson(
              weightsJson,
            )) {
              final SkinWeightsBlob weights => SetRig(
                jointObjects: jointObjects,
                skeleton: skeleton,
                skinObjectId: json['skinObjectId'] as int?,
                weights: weights,
                label: label,
              ),
              null => null,
            },
          },
        _ => null,
      },
      'paintWeights': (json) => switch ((
        json['objectId'],
        json['skeletonIndex'],
        json['joint'],
        json['samples'],
        json['strength'],
      )) {
        (
          final int objectId,
          final int skeletonIndex,
          final int joint,
          final List<Object?> samplesJson,
          final num strength,
        ) =>
          switch (_brushSamplesFrom(samplesJson)) {
            final List<BrushSample> samples => switch (_paintMirrorFrom(
              json['mirror'],
            )) {
              (final PaintMirror? mirror, true) => PaintWeights(
                objectId: objectId,
                skeletonIndex: skeletonIndex,
                joint: joint,
                samples: samples,
                strength: strength.toDouble(),
                mode: json['mode'] == 'assign'
                    ? PaintWeightsMode.assign
                    : PaintWeightsMode.paint,
                mirror: mirror,
                normalize: json['normalize'] as bool? ?? true,
                maxInfluences: json['maxInfluences'] as int?,
              ),
              (_, false) => null,
            },
            null => null,
          },
        _ => null,
      },
      'setKey': (json) => switch ((
        json['clipIndex'],
        json['trackIndex'],
        json['time'],
        json['values'],
      )) {
        (
          final int clipIndex,
          final int trackIndex,
          final num time,
          final List<Object?> valuesJson,
        ) =>
          switch (_doubleListFrom(valuesJson)) {
            final List<double> values => SetKey(
              clipIndex: clipIndex,
              trackIndex: trackIndex,
              time: time.toDouble(),
              values: values,
              inTangent: _doubleListFrom(json['inTangent']),
              outTangent: _doubleListFrom(json['outTangent']),
            ),
            null => null,
          },
        _ => null,
      },
      'moveKeys': (json) => switch ((
        json['clipIndex'],
        json['trackIndex'],
        json['indices'],
        json['deltaTime'],
      )) {
        (
          final int clipIndex,
          final int trackIndex,
          final List<Object?> indicesJson,
          final num deltaTime,
        )
            when indicesJson.every((Object? each) => each is int) =>
          MoveKeys(
            clipIndex: clipIndex,
            trackIndex: trackIndex,
            indices: <int>[
              for (final Object? each in indicesJson) each! as int,
            ],
            deltaTime: deltaTime.toDouble(),
          ),
        _ => null,
      },
      'deleteKeys': (json) =>
          switch ((json['clipIndex'], json['trackIndex'], json['indices'])) {
            (
              final int clipIndex,
              final int trackIndex,
              final List<Object?> indicesJson,
            )
                when indicesJson.every((Object? each) => each is int) =>
              DeleteKeys(
                clipIndex: clipIndex,
                trackIndex: trackIndex,
                indices: <int>[
                  for (final Object? each in indicesJson) each! as int,
                ],
              ),
            _ => null,
          },
      'setInterpolation': (json) => switch ((
        json['clipIndex'],
        json['trackIndex'],
        _interpolationFrom(json['interpolation']),
      )) {
        (
          final int clipIndex,
          final int trackIndex,
          final AnimationInterpolation interpolation,
        ) =>
          SetInterpolation(
            clipIndex: clipIndex,
            trackIndex: trackIndex,
            interpolation: interpolation,
          ),
        _ => null,
      },
      'setTangent': (json) =>
          switch ((json['clipIndex'], json['trackIndex'], json['index'])) {
            (final int clipIndex, final int trackIndex, final int index) =>
              SetTangent(
                clipIndex: clipIndex,
                trackIndex: trackIndex,
                index: index,
                inTangent: _doubleListFrom(json['inTangent']),
                outTangent: _doubleListFrom(json['outTangent']),
              ),
            _ => null,
          },
      'poseJoint': (json) => switch ((
        json['joint'],
        _pathFrom(json['path']),
        json['clipIndex'],
        json['frame'],
      )) {
        (
          final int joint,
          final AnimationPath path,
          final int clipIndex,
          final int frame,
        ) =>
          PoseJoint(
            joint: joint,
            path: path,
            clipIndex: clipIndex,
            frame: frame,
          ),
        _ => null,
      },
      'extractRootMotion': (json) =>
          switch ((json['clipIndex'], json['rootJoint'])) {
            (final int clipIndex, final int rootJoint) => ExtractRootMotion(
              clipIndex: clipIndex,
              rootJoint: rootJoint,
            ),
            _ => null,
          },
      'bakeRootMotionIntoClip': (json) => switch ((
        json['clipIndex'],
        json['rootJoint'],
      )) {
        (final int clipIndex, final int rootJoint) => BakeRootMotionIntoClip(
          clipIndex: clipIndex,
          rootJoint: rootJoint,
        ),
        _ => null,
      },
      'addClip': (json) => AddClip(clipName: json['clipName'] as String?),
      'addLod': (json) => switch ((
        json['id'],
        json['ratio'],
        json['maxScreenFraction'],
      )) {
        (final int id, final num ratio, final num maxScreenFraction) => AddLod(
          id: id,
          ratio: ratio.toDouble(),
          maxScreenFraction: maxScreenFraction.toDouble(),
        ),
        _ => null,
      },
      'setLodRatio': (json) =>
          switch ((json['id'], json['lodIndex'], json['ratio'])) {
            (final int id, final int lodIndex, final num ratio) => SetLodRatio(
              id: id,
              lodIndex: lodIndex,
              ratio: ratio.toDouble(),
            ),
            _ => null,
          },
      'regenerateLods': (json) => switch (json['id']) {
        final int id => RegenerateLods(id),
        _ => null,
      },
    };

/// The pivot [json] names, [TransformPivot.median] when it says nothing, or
/// null when it names one this version has never heard of.
///
/// **Three answers rather than two, and the third is the whole point.** A key
/// that is missing belongs to a journal written before there were pivots, and
/// median is what that entry meant. A key holding a word this version does not
/// know belongs to a journal written by a newer application — reading it back
/// as median would replay the step about a different point in silence, which is
/// worse than skipping the entry the way every other unreadable one is skipped.
TransformPivot? _pivot(Object? json) => json == null
    ? TransformPivot.median
    : TransformPivot.values
          .where((TransformPivot each) => each.name == json)
          .firstOrNull;

/// The shape [json] describes, or null when it is not a shape at all.
ParametricShape? _shapeOf(Object? json) =>
    json is Map<String, Object?> ? parametricShapeFrom(json) : null;

/// A list of pairs as points on the (radius, height) half-plane, or null.
///
/// Null on the first pair that is not two numbers rather than on a length,
/// because a profile with one bad point is not a profile that can be turned.
List<Vector2>? _points(Object? json) {
  if (json is! List<Object?>) return null;
  final out = <Vector2>[];
  for (final Object? each in json) {
    if (each case [final num x, final num y]) {
      out.add(Vector2(x.toDouble(), y.toDouble()));
      continue;
    }
    return null;
  }
  return out;
}

/// Where [json] puts an origin, the middle of the bounds by default, or null.
/// See [_pivot] for why an unknown word is null rather than the default.
OriginPlacement? _placement(Object? json) => json == null
    ? OriginPlacement.boundsCentre
    : OriginPlacement.values
          .where((OriginPlacement each) => each.name == json)
          .firstOrNull;

/// The space [json] names, [TransformSpace.global] by default, or null. See
/// [_pivot] for why an unknown word is null rather than the default.
TransformSpace? _space(Object? json) => json == null
    ? TransformSpace.global
    : TransformSpace.values
          .where((TransformSpace each) => each.name == json)
          .firstOrNull;

/// Exactly [length] numbers, or null.
///
/// Integers are accepted as well as doubles: JSON has one number type, and a
/// translation of exactly zero comes back from most encoders as `0` rather than
/// `0.0`. Refusing those would make a round trip fail on the commonest value
/// there is.
List<double>? _doubles(Object? json, int length) {
  if (json is! List || json.length != length) return null;
  final out = <double>[];
  for (final Object? each in json) {
    if (each is! num) return null;
    out.add(each.toDouble());
  }
  return out;
}
