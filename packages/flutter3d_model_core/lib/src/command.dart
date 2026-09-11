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
import 'dart:typed_data';

// `EnumHint` hidden: `flutter3d_formats`' own is `MaterialHintKind`'s, for a
// material's fields, and this library's `param_hint.dart` names a command
// argument's the same word for the same reason — nothing here reads a
// material's, and the collision is the one the plan's own critique (Г4/Ж2)
// gives for keeping the two hierarchies apart in the first place.
import 'package:flutter3d_formats/flutter3d_formats.dart' hide EnumHint;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:vector_math/vector_math.dart';

import 'job.dart';
import 'key_table.dart';
import 'material.dart';
import 'modifier_slot.dart';
import 'param_hint.dart';
import 'parametric_json.dart';
import 'png_encoder.dart';
import 'project.dart';
import 'project_animation.dart';
import 'project_morphs.dart';
import 'selection.dart';
import 'texture_bake.dart';
import 'texture_graph.dart';
import 'world_transform.dart';

part 'job_commands.dart';
part 'joint_commands.dart';
part 'keyframe_commands.dart';
part 'material_commands.dart';
part 'mesh_commands.dart';
part 'modifier_commands.dart';
part 'object_commands.dart';
part 'profile_commands.dart';
part 'root_motion_commands.dart';
part 'selection_commands.dart';
part 'shape_commands.dart';

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
/// and not `record`-able through `CommandJournal`.** Every other command
/// describes an edit small enough to write down and replay — a number, an id,
/// a list of points; this one carries a whole [ModelProject], which is what an
/// importer builds from a decoded file and a journal has no honest way to
/// store. It exists so that bringing in an external model — `flutter3d_model_mcp`'s
/// `import`, and later `doc-11a-n`'s `ImportInto` — still goes through
/// [ModelHistory] and can be undone as itself, rather than needing a second,
/// private way to push a step that every other command already has for free.
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
  const MoveBy(this.by);

  final Vector3 by;

  @override
  String get name => 'moveBy';

  @override
  String get says => 'move';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'by': <double>[by.x, by.y, by.z],
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

/// Every command name there is, for the agent's tool table and for the test
/// that says each of them has a sample.
const List<String> modelCommandNames = <String>[
  'rename',
  'setTransform',
  'moveBy',
  'rotateBy',
  'scaleBy',
  'setParent',
  'setOrigin',
  'applyTransform',
  'addPrimitive',
  'addLathe',
  'addSocket',
  'setParametric',
  'bakeToMesh',
  'deleteObjects',
  'duplicateObjects',
  'extrude',
  'loopCut',
  'deleteElements',
  'transformElements',
  'mergeByDistance',
  'dissolveEdges',
  'separate',
  'triangulate',
  'recalculateNormals',
  'selectAll',
  'selectNone',
  'invertSelection',
  'growSelection',
  'shrinkSelection',
  'selectLinked',
  'selectEdgeLoop',
  'selectEdgeRing',
  'selectByMaterial',
  'addMaterial',
  'removeMaterial',
  'duplicateMaterial',
  'setMaterialField',
  'setTexture',
  'addImage',
  'assignMaterial',
  'setMaterialGraph',
  'bakeTextureGraph',
  'addModifier',
  'setModifierField',
  'toggleModifier',
  'reorderModifier',
  'removeModifier',
  'applyModifier',
  'applyJobResult',
  'setProfileLimits',
  'setShapeWeight',
  'addShapeFromMesh',
  'renameShape',
  'deleteShape',
  'keyShape',
  'addJoint',
  'removeJoint',
  'renameJoint',
  'reparentJoint',
  'setRestPose',
  'mirrorJoints',
  'setKey',
  'moveKeys',
  'deleteKeys',
  'setInterpolation',
  'setTangent',
  'fillHoles',
  'poseJoint',
  'extractRootMotion',
  'bakeRootMotionIntoClip',
  'addSkeleton',
  'bindSkin',
  'addClip',
];

/// Reads a command back out of a journal, or null.
///
/// **Null and not an exception**, for the reason `ProjectSelection.fromJson`
/// gives: a journal is replayed entry by entry and an entry from a newer
/// version of the application is one to skip, not one to fail the whole file
/// over.
ModelCommand? modelCommandFromJson(Object? json) {
  if (json is! Map<String, Object?>) return null;
  return switch (json['name']) {
    'rename' => switch ((json['id'], json['to'])) {
      (final int id, final String to) => Rename(id: id, to: to),
      _ => null,
    },
    'setTransform' => switch ((json['id'], _doubles(json['to'], 16))) {
      (final int id, final List<double> to) => SetTransform(
        id: id,
        to: Matrix4.fromList(to),
      ),
      _ => null,
    },
    'moveBy' => switch (_doubles(json['by'], 3)) {
      final List<double> by => MoveBy(Vector3(by[0], by[1], by[2])),
      _ => null,
    },
    'rotateBy' => switch ((
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
    'scaleBy' => switch ((json['by'], _pivot(json['pivot']))) {
      (final num by, final TransformPivot pivot) => ScaleBy(
        by.toDouble(),
        pivot: pivot,
      ),
      _ => null,
    },
    'setParent' => switch ((json['id'], json['to'])) {
      (final int id, final int? to) => SetParent(id: id, to: to),
      _ => null,
    },
    'setOrigin' => switch ((json['id'], _placement(json['to']))) {
      (final int id, final OriginPlacement to) => SetOrigin(id: id, to: to),
      _ => null,
    },
    'applyTransform' => switch (json['id']) {
      final int id => ApplyTransform(id),
      _ => null,
    },
    'addLathe' => switch (_points(json['profile'])) {
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
    'addSocket' => AddSocket(
      label: json['label'] as String? ?? 'socket',
      at: switch (_doubles(json['at'], 3)) {
        final List<double> at => Vector3(at[0], at[1], at[2]),
        _ => null,
      },
    ),
    'setParametric' => switch ((json['id'], _shapeOf(json['to']))) {
      (final int id, final ParametricShape to) => SetParametric(id: id, to: to),
      _ => null,
    },
    'addPrimitive' => switch (json['kind']) {
      final String kind => AddPrimitive(
        kind: kind,
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
    'bakeToMesh' => switch (json['id']) {
      final int id => BakeToMesh(id),
      _ => null,
    },
    'deleteObjects' => const DeleteObjects(),
    'duplicateObjects' => const DuplicateObjects(),
    'extrude' => switch (json['distance']) {
      final num distance => Extrude(distance.toDouble()),
      _ => null,
    },
    'loopCut' => LoopCut(
      cuts: switch (json['cuts']) {
        final int cuts => cuts,
        _ => 1,
      },
      factor: switch (json['factor']) {
        final num factor => factor.toDouble(),
        _ => 0.5,
      },
    ),
    'deleteElements' => const DeleteElements(),
    'mergeByDistance' => MergeByDistance(
      distance: switch (json['distance']) {
        final num how => how.toDouble(),
        _ => null,
      },
    ),
    'dissolveEdges' => const DissolveEdges(),
    'separate' => const Separate(),
    'fillHoles' => const FillHoles(),
    'triangulate' => const Triangulate(),
    'recalculateNormals' => RecalculateNormals(
      flip: json['flip'] as bool? ?? false,
    ),
    'transformElements' => switch ((
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
    'selectAll' => const SelectAll(),
    'selectNone' => const SelectNone(),
    'invertSelection' => const InvertSelection(),
    'growSelection' => const GrowSelection(),
    'shrinkSelection' => const ShrinkSelection(),
    'selectLinked' => const SelectLinked(),
    'selectEdgeLoop' => switch (json['edge']) {
      final int edge => SelectEdgeLoop(edge),
      _ => null,
    },
    'selectEdgeRing' => switch (json['edge']) {
      final int edge => SelectEdgeRing(edge),
      _ => null,
    },
    'selectByMaterial' => switch (json['slot']) {
      final int slot => SelectByMaterial(slot),
      _ => null,
    },
    'addMaterial' => AddMaterial(materialName: json['materialName'] as String?),
    'removeMaterial' => switch (json['index']) {
      final int index => RemoveMaterial(index),
      _ => null,
    },
    'duplicateMaterial' => switch (json['index']) {
      final int index => DuplicateMaterial(index),
      _ => null,
    },
    'setMaterialField' => switch ((json['index'], json['field'])) {
      (final int index, final String field) => SetMaterialField(
        index: index,
        field: field,
        value: json['value'],
      ),
      _ => null,
    },
    'setTexture' => switch ((json['materialIndex'], json['slot'])) {
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
    'addImage' => switch (json['bytes']) {
      final String encoded => AddImage(
        bytes: base64Decode(encoded),
        imageName: json['imageName'] as String?,
        mimeType: json['mimeType'] as String?,
      ),
      _ => null,
    },
    'assignMaterial' => switch ((json['id'], json['to'])) {
      (final int id, final int? to) => AssignMaterial(id: id, to: to),
      _ => null,
    },
    'setMaterialGraph' => switch (json['materialIndex']) {
      final int materialIndex => SetMaterialGraph(
        materialIndex: materialIndex,
        graph: switch (json['graph']) {
          final Map<String, Object?> g => TextureGraph.fromJson(g),
          _ => null,
        },
      ),
      _ => null,
    },
    'bakeTextureGraph' => switch (json['materialIndex']) {
      final int materialIndex => BakeTextureGraph(
        materialIndex: materialIndex,
        size: json['size'] as int? ?? 1024,
      ),
      _ => null,
    },
    'addModifier' => switch ((json['id'], json['modifier'])) {
      (final int id, final Object? modifierJson) => switch (modifierFromJson(
        modifierJson,
      )) {
        final Modifier modifier => AddModifier(id: id, modifier: modifier),
        null => null,
      },
      _ => null,
    },
    'setModifierField' => switch ((json['id'], json['index'], json['field'])) {
      (final int id, final int index, final String field) => SetModifierField(
        id: id,
        index: index,
        field: field,
        value: json['value'],
      ),
      _ => null,
    },
    'toggleModifier' => switch ((json['id'], json['index'])) {
      (final int id, final int index) => ToggleModifier(id: id, index: index),
      _ => null,
    },
    'reorderModifier' => switch ((json['id'], json['from'], json['to'])) {
      (final int id, final int from, final int to) => ReorderModifier(
        id: id,
        from: from,
        to: to,
      ),
      _ => null,
    },
    'removeModifier' => switch ((json['id'], json['index'])) {
      (final int id, final int index) => RemoveModifier(id: id, index: index),
      _ => null,
    },
    'applyModifier' => switch ((json['id'], json['index'])) {
      (final int id, final int index) => ApplyModifier(id: id, index: index),
      _ => null,
    },
    'applyJobResult' => switch ((
      json['objectId'],
      json['baseVersion'],
      json['meshBytes'],
    )) {
      (final int objectId, final int baseVersion, final String encoded) =>
        ApplyJobResult(
          objectId: objectId,
          baseVersion: baseVersion,
          meshBytes: base64Decode(encoded),
        ),
      _ => null,
    },
    'setProfileLimits' => SetProfileLimits(
      maxJoints: json['maxJoints'] as int?,
      maxInfluences: json['maxInfluences'] as int?,
    ),
    'setShapeWeight' => switch ((json['id'], json['shapeIndex'], json['weight'])) {
      (final int id, final int shapeIndex, final num weight) => SetShapeWeight(
        id: id,
        shapeIndex: shapeIndex,
        weight: weight.toDouble(),
      ),
      _ => null,
    },
    'addShapeFromMesh' => switch ((json['id'], json['shapeName'])) {
      (final int id, final String shapeName) => AddShapeFromMesh(
        id: id,
        shapeName: shapeName,
      ),
      _ => null,
    },
    'renameShape' => switch ((json['id'], json['shapeIndex'], json['to'])) {
      (final int id, final int shapeIndex, final String to) => RenameShape(
        id: id,
        shapeIndex: shapeIndex,
        to: to,
      ),
      _ => null,
    },
    'deleteShape' => switch ((json['id'], json['shapeIndex'])) {
      (final int id, final int shapeIndex) => DeleteShape(id: id, shapeIndex: shapeIndex),
      _ => null,
    },
    'keyShape' => switch ((json['id'], json['clipIndex'], json['time'])) {
      (final int id, final int clipIndex, final num time) => KeyShape(
        id: id,
        clipIndex: clipIndex,
        time: time.toDouble(),
      ),
      _ => null,
    },
    'addSkeleton' => AddSkeleton(skeletonName: json['skeletonName'] as String?),
    'bindSkin' => switch ((json['objectId'], json['skeletonIndex'])) {
      (final int objectId, final int skeletonIndex) =>
        BindSkin(objectId: objectId, skeletonIndex: skeletonIndex),
      _ => null,
    },
    'addJoint' => switch ((json['skeletonIndex'], json['objectId'])) {
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
    'removeJoint' => switch ((json['skeletonIndex'], json['jointIndex'])) {
      (final int skeletonIndex, final int jointIndex) => RemoveJoint(
        skeletonIndex: skeletonIndex,
        jointIndex: jointIndex,
      ),
      _ => null,
    },
    'renameJoint' => switch ((json['skeletonIndex'], json['jointIndex'], json['to'])) {
      (final int skeletonIndex, final int jointIndex, final String to) => RenameJoint(
        skeletonIndex: skeletonIndex,
        jointIndex: jointIndex,
        to: to,
      ),
      _ => null,
    },
    'reparentJoint' => switch ((json['skeletonIndex'], json['jointIndex'])) {
      (final int skeletonIndex, final int jointIndex) => ReparentJoint(
        skeletonIndex: skeletonIndex,
        jointIndex: jointIndex,
        to: json['to'] as int?,
      ),
      _ => null,
    },
    'setRestPose' => switch ((
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
    'mirrorJoints' => switch ((json['skeletonIndex'], json['axis'], json['jointMirror'])) {
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
    'setKey' => switch ((
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
    'moveKeys' => switch ((
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
          indices: <int>[for (final Object? each in indicesJson) each! as int],
          deltaTime: deltaTime.toDouble(),
        ),
      _ => null,
    },
    'deleteKeys' => switch ((json['clipIndex'], json['trackIndex'], json['indices'])) {
      (
        final int clipIndex,
        final int trackIndex,
        final List<Object?> indicesJson,
      )
          when indicesJson.every((Object? each) => each is int) =>
        DeleteKeys(
          clipIndex: clipIndex,
          trackIndex: trackIndex,
          indices: <int>[for (final Object? each in indicesJson) each! as int],
        ),
      _ => null,
    },
    'setInterpolation' => switch ((
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
    'setTangent' => switch ((json['clipIndex'], json['trackIndex'], json['index'])) {
      (final int clipIndex, final int trackIndex, final int index) => SetTangent(
        clipIndex: clipIndex,
        trackIndex: trackIndex,
        index: index,
        inTangent: _doubleListFrom(json['inTangent']),
        outTangent: _doubleListFrom(json['outTangent']),
      ),
      _ => null,
    },
    'poseJoint' => switch ((
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
        PoseJoint(joint: joint, path: path, clipIndex: clipIndex, frame: frame),
      _ => null,
    },
    'extractRootMotion' => switch ((json['clipIndex'], json['rootJoint'])) {
      (final int clipIndex, final int rootJoint) =>
        ExtractRootMotion(clipIndex: clipIndex, rootJoint: rootJoint),
      _ => null,
    },
    'bakeRootMotionIntoClip' => switch ((
      json['clipIndex'],
      json['rootJoint'],
    )) {
      (final int clipIndex, final int rootJoint) =>
        BakeRootMotionIntoClip(clipIndex: clipIndex, rootJoint: rootJoint),
      _ => null,
    },
    'addClip' => AddClip(clipName: json['clipName'] as String?),
    _ => null,
  };
}

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
