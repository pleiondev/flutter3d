import 'package:flutter3d_foundation/flutter3d_foundation.dart' show Severity;

import '../cinema/sequence.dart';
import '../world/cutscene.dart';
import 'entity_def.dart';
import 'entity_kind.dart';
import 'level_issue.dart';

/// A cutscene in a level: an entity with its [Sequence] document in its
/// `sequence` property, played when something it is the target of fires.
///
/// **The document on the entity, not beside the level**, because a cutscene
/// belongs to a place — the trigger in front of a door, the room a boss
/// waits in — and an entity is a level's word for a thing in a place: the
/// editor selects it, moves it and edits its fields like any other.
///
/// [stepsPerSecond] is the game's: the moments are read for the step it
/// takes, and a document that does not read is a validation error with every
/// problem in it, not a cutscene that silently does nothing.
final class CutsceneKind extends EntityKind {
  /// The `cutscene` kind, reading its documents for [stepsPerSecond].
  const CutsceneKind({required this.stepsPerSecond})
    : super(EntityTypes.cutscene);

  /// The game's step rate, in steps per second, its documents' moments are
  /// read for.
  final int stepsPerSecond;

  SequenceRead _read(EntityDef entity) => Sequence.read(
    entity.properties['sequence'],
    stepsPerSecond: stepsPerSecond,
  );

  @override
  void validate(EntityCheck check) {
    final entity = check.entity;
    final scope = check.scope;
    final out = check.out;
    if (entity.name == null) {
      out.add(
        LevelIssue(
          Severity.error,
          'has no name, so nothing can start it',
          where: scope.describe(entity),
        ),
      );
    }
    for (final problem in _read(entity).problems) {
      out.add(
        LevelIssue(
          Severity.error,
          'its sequence: $problem',
          where: scope.describe(entity),
        ),
      );
    }
  }

  @override
  void spawn(EntitySpawn spawn) {
    final entity = spawn.entity;
    final context = spawn.context;
    final sequence = _read(entity).sequence;
    if (sequence == null) return;
    context.mechanisms.add(
      Cutscene(
        name: entity.name,
        sequence: sequence,
        actors: context.actors,
        once: entity.flag('once', orElse: true),
      ),
    );
  }
}
