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

import 'package:vector_math/vector_math.dart';

import 'project.dart';
import 'selection.dart';

/// What a command did.
final class Outcome {
  const Outcome._(this.project, this.selection, this.refused);

  /// It worked, and this is the project now.
  ///
  /// [selection] is what should be selected afterwards, which is not always
  /// what was selected before: a command that makes something selects what it
  /// made, because that is what a person wants to move next.
  factory Outcome.done(ModelProject project, {ProjectSelection? selection}) =>
      Outcome._(project, selection, null);

  /// It did not, and this is what to tell somebody.
  factory Outcome.refused(String said) => Outcome._(null, null, said);

  final ModelProject? project;
  final ProjectSelection? selection;
  final String? refused;

  bool get ok => refused == null;
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
      // The copy keeps the geometry by reference. `EditMesh` is edited through
      // commands that replace it, so two objects sharing one until either is
      // touched is the same structural sharing the project itself uses — and
      // duplicating a two hundred thousand face mesh is then free.
      next = next.added(
        (int fresh) => ModelObject(
          id: fresh,
          name: '${object.name} copy',
          geometry: object.geometry,
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
  'deleteObjects',
  'duplicateObjects',
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
    'deleteObjects' => const DeleteObjects(),
    'duplicateObjects' => const DuplicateObjects(),
    _ => null,
  };
}

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
