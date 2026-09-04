/// What a step of this game did, for a game that wants to hear about it.
///
/// Drained from `PlatformerSimulation.events` after each step. See [GameEvent]
/// for why this is a drained buffer rather than a stream, and for why nothing
/// here names a sound or a particle: these say what happened, and what to do
/// about it is the game's.
///
/// **This game is where the reason is written down.** `diedThisStep` exists
/// because a death used to be inferred by comparing a counter against a copy —
/// the camera kept one, the particles kept one, the soundtrack kept a third,
/// and all three were wrong the moment a run began with deaths already on it.
/// The flag fixed that and then met the next version of the same problem: a
/// flag carries one of a thing. Two enemies stomped in one step were one
/// `stompedThisStep`, so the second made no sound and threw no dust.
///
/// A game that adds a mechanic adds its own event beside these — [GameEvent]
/// is open, and nothing here dispatches on the type.
library;

import 'package:flutter3d_game/flutter3d_game.dart';

import 'checkpoint.dart';
import 'collectible.dart';

/// The runner picked something up.
///
/// One per collectible, so a step that sweeps through three coins is three of
/// these — which is three sounds and three bursts, and was one list a caller
/// had to know to look in.
final class CollectibleTaken extends GameEvent {
  const CollectibleTaken(this.collectible);

  final Collectible collectible;

  @override
  String get name => 'collectible taken';
}

/// The level said something to the player.
///
/// A locked gate answering "You need the blue key" — the sentence a trigger
/// parks in `MechanismEvents.messages` because it fires from inside the
/// collision dispatch, where there is nobody to return an outcome to.
final class LevelSaid extends GameEvent {
  const LevelSaid(this.message);

  final String message;

  @override
  String get name => 'level said "$message"';
}

/// A checkpoint was reached for the first time.
///
/// Carries which one, which the flag it replaces could not: a level whose
/// checkpoints look different from each other had no way to say which had just
/// been passed.
final class CheckpointReached extends GameEvent {
  const CheckpointReached(this.checkpoint);

  final Checkpoint checkpoint;

  @override
  String get name => 'checkpoint reached';
}

/// The runner landed on something and killed it.
///
/// One per enemy. Two in one step is two of these, which is the case the flag
/// this replaces could not report at all.
final class EnemyStomped extends GameEvent {
  const EnemyStomped(this.enemy);

  final Actor enemy;

  @override
  String get name => 'enemy stomped';
}

/// The runner died on this step.
///
/// Once, on the step it happened, whatever the death counter says — which is
/// the property the counter never had.
final class RunnerDied extends GameEvent {
  const RunnerDied();

  @override
  String get name => 'runner died';
}
