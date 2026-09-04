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

import 'package:vector_math/vector_math.dart';

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

/// Something the runner's own body did.
///
/// The base of the ten below, so a game reacting to "the runner moved
/// suddenly" filters on one type. They come from [Runner] rather than from the
/// simulation, and they arrive in the same buffer in the order the step
/// produced them — a landing and the block it broke are two events one after
/// the other rather than a flag on a body and a flag on a brush.
abstract base class RunnerEvent extends GameEvent {
  const RunnerEvent();
}

/// Left the ground under its own power.
final class Jumped extends RunnerEvent {
  const Jumped();

  @override
  String get name => 'jumped';
}

/// Pushed off a wall it was against.
final class WallJumped extends RunnerEvent {
  const WallJumped();

  @override
  String get name => 'wall jumped';
}

/// Came out of a slide, low and far, with no steering.
final class LongJumped extends RunnerEvent {
  const LongJumped();

  @override
  String get name => 'long jumped';
}

/// Pulled itself over a ledge.
final class Mantled extends RunnerEvent {
  const Mantled();

  @override
  String get name => 'mantled';
}

/// Committed to a dash.
final class Dashed extends RunnerEvent {
  const Dashed();

  @override
  String get name => 'dashed';
}

/// Went into a slide.
final class Slid extends RunnerEvent {
  const Slid();

  @override
  String get name => 'slid';
}

/// Caught a rope or a ladder, and stopped falling.
final class Grabbed extends RunnerEvent {
  const Grabbed();

  @override
  String get name => 'grabbed';
}

/// Touched the ground.
///
/// Carries whether it arrived on the way down from a ground pound, which is
/// two flags in the shape it replaces and one question a caller asks here.
final class Landed extends RunnerEvent {
  const Landed({required this.pounded});

  /// Whether the landing was the end of a ground pound.
  final bool pounded;

  @override
  String get name => pounded ? 'landed (pounded)' : 'landed';
}

/// Was thrown upwards by something it landed on.
///
/// Not [EnemyStomped], which says the enemy died: this says the runner was
/// thrown, and a spring throws without anything dying.
final class Bounced extends RunnerEvent {
  const Bounced();

  @override
  String get name => 'bounced';
}

/// A piece of the level's own furniture did something.
///
/// **Reported by the simulation on its pass over the mechanisms, not by the
/// mechanism itself**, and that is worth knowing rather than hiding: a spring
/// firing is placed in the buffer where the simulation reads it, which is
/// after the runner's own events for the step rather than at the instant the
/// pad went off. The flags this replaces were read by a game walking every
/// mechanism in the level once a frame and asking each one three questions;
/// what has actually gone is that walk.
abstract base class FurnitureEvent extends GameEvent {
  const FurnitureEvent(this.at);

  /// Where it happened, in world space.
  final Vector3 at;
}

/// A pad threw something.
final class SpringFired extends FurnitureEvent {
  const SpringFired(super.at);

  @override
  String get name => 'spring fired';
}

/// A platform gave way under the weight on it.
final class BlockCrumbled extends FurnitureEvent {
  const BlockCrumbled(super.at);

  @override
  String get name => 'block crumbled';
}

/// A block was broken.
final class BlockBroke extends FurnitureEvent {
  const BlockBroke(super.at);

  @override
  String get name => 'block broke';
}

/// A power-up ran out.
///
/// **The moment a player notices, and the one a countdown cannot report**: a
/// number on a HUD reads nought on the frame it ends and on every frame after,
/// so a game watching the number cannot tell the two apart without keeping a
/// copy — which is the shape `diedThisStep` was written to remove.
final class PowerEnded extends GameEvent {
  const PowerEnded(this.power);

  /// What ran out, by the name the level gave it.
  final String power;

  @override
  String get name => 'power ended ($power)';
}
