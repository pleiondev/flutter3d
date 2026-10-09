/// What a step of this game did, for a game that wants to hear about it.
///
/// Published onto the engine's bus from inside the step that raised them —
/// `PlatformerSimulation.publishTo`, which `PlatformerPlugin` calls — each
/// declared with its codec under a `platformer.` name. See [GameEvent] for
/// why nothing here names a sound or a particle: these say what happened, and
/// what to do about it is the game's.
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

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'package:vector_math/vector_math.dart';

import 'checkpoint.dart';
import 'collectible.dart';

/// The runner picked something up.
///
/// One per collectible, so a step that sweeps through three coins is three of
/// these — which is three sounds and three bursts, and was one list a caller
/// had to know to look in.
final class CollectibleTaken extends GameEvent {
  const CollectibleTaken(this.collectible, this.scored);

  /// The name it is declared and published under.
  static const String eventName = 'platformer.collectibleTaken';

  /// Its codec: the collectible's name and what it scored. Reads back as
  /// null, since the collectible is a live part of the level, not a value.
  static final EventCodec<CollectibleTaken> codec =
      EventCodec<CollectibleTaken>.of(
        encode: (CollectibleTaken e) => <Object?>[e.collectible.name, e.scored],
        decode: (Object? data, int version) => null,
      );

  final Collectible collectible;

  /// What it was worth once the chain in hand was applied.
  ///
  /// Carried rather than left to be recomputed, because the multiplier has
  /// already moved on by the time anything reads this — and the number a game
  /// floats over the coin is this one, not what the coin says it is worth.
  final double scored;

  @override
  String get name => eventName;
}

/// The level said something to the player.
///
/// A locked gate answering "You need the blue key" — the sentence a trigger
/// parks in `MechanismEvents.messages` because it fires from inside the
/// collision dispatch, where there is nobody to return an outcome to.
final class LevelSaid extends GameEvent {
  const LevelSaid(this.message);

  /// The name it is declared and published under.
  static const String eventName = 'platformer.levelSaid';

  /// Its codec: the sentence. Reads back whole.
  static final EventCodec<LevelSaid> codec = EventCodec<LevelSaid>.of(
    encode: (LevelSaid e) => e.message,
    decode: (Object? data, int version) =>
        data is String ? LevelSaid(data) : null,
  );

  final String message;

  @override
  String get name => eventName;
}

/// A checkpoint was reached for the first time.
///
/// Carries which one, which the flag it replaces could not: a level whose
/// checkpoints look different from each other had no way to say which had just
/// been passed.
final class CheckpointReached extends GameEvent {
  const CheckpointReached(this.checkpoint);

  /// The name it is declared and published under.
  static const String eventName = 'platformer.checkpointReached';

  /// Its codec: the checkpoint's name. Reads back as null, since the
  /// checkpoint is a live part of the level, not a value.
  static final EventCodec<CheckpointReached> codec =
      EventCodec<CheckpointReached>.of(
        encode: (CheckpointReached e) => e.checkpoint.name,
        decode: (Object? data, int version) => null,
      );

  final Checkpoint checkpoint;

  @override
  String get name => eventName;
}

/// The runner landed on something and killed it.
///
/// One per enemy. Two in one step is two of these, which is the case the flag
/// this replaces could not report at all.
final class EnemyStomped extends GameEvent {
  const EnemyStomped(this.enemy);

  /// The name it is declared and published under.
  static const String eventName = 'platformer.enemyStomped';

  /// Its codec: the enemy's ordinal. Reads back as null, since an actor is
  /// a live part of a world, not a value.
  static final EventCodec<EnemyStomped> codec = EventCodec<EnemyStomped>.of(
    encode: (EnemyStomped e) => e.enemy.ordinal,
    decode: (Object? data, int version) => null,
  );

  final Actor enemy;

  @override
  String get name => eventName;
}

/// The runner died on this step.
///
/// Once, on the step it happened, whatever the death counter says — which is
/// the property the counter never had.
final class RunnerDied extends GameEvent {
  const RunnerDied();

  /// The name it is declared and published under.
  static const String eventName = 'platformer.runnerDied';

  /// Its codec: nothing but the name, read back as the event.
  static final EventCodec<RunnerDied> codec = EventCodec<RunnerDied>.of(
    encode: (RunnerDied e) => null,
    decode: (Object? data, int version) => const RunnerDied(),
  );

  @override
  String get name => eventName;
}

/// Something the runner's own body did.
///
/// The base of the ten below, so a game reacting to "the runner moved
/// suddenly" filters on one type. They come from [Runner] rather than from the
/// simulation, and they arrive on the same bus in the order the step
/// produced them — a landing and the block it broke are two events one after
/// the other rather than a flag on a body and a flag on a brush.
abstract base class RunnerEvent extends GameEvent {
  const RunnerEvent();
}

/// Left the ground under its own power.
final class Jumped extends RunnerEvent {
  const Jumped();

  /// The name it is declared and published under.
  static const String eventName = 'platformer.jumped';

  /// Its codec: nothing but the name, read back as the event.
  static final EventCodec<Jumped> codec = EventCodec<Jumped>.of(
    encode: (Jumped e) => null,
    decode: (Object? data, int version) => const Jumped(),
  );

  @override
  String get name => eventName;
}

/// Pushed off a wall it was against.
final class WallJumped extends RunnerEvent {
  const WallJumped();

  /// The name it is declared and published under.
  static const String eventName = 'platformer.wallJumped';

  /// Its codec: nothing but the name, read back as the event.
  static final EventCodec<WallJumped> codec = EventCodec<WallJumped>.of(
    encode: (WallJumped e) => null,
    decode: (Object? data, int version) => const WallJumped(),
  );

  @override
  String get name => eventName;
}

/// Came out of a slide, low and far, with no steering.
final class LongJumped extends RunnerEvent {
  const LongJumped();

  /// The name it is declared and published under.
  static const String eventName = 'platformer.longJumped';

  /// Its codec: nothing but the name, read back as the event.
  static final EventCodec<LongJumped> codec = EventCodec<LongJumped>.of(
    encode: (LongJumped e) => null,
    decode: (Object? data, int version) => const LongJumped(),
  );

  @override
  String get name => eventName;
}

/// Pulled itself over a ledge.
final class Mantled extends RunnerEvent {
  const Mantled();

  /// The name it is declared and published under.
  static const String eventName = 'platformer.mantled';

  /// Its codec: nothing but the name, read back as the event.
  static final EventCodec<Mantled> codec = EventCodec<Mantled>.of(
    encode: (Mantled e) => null,
    decode: (Object? data, int version) => const Mantled(),
  );

  @override
  String get name => eventName;
}

/// Committed to a dash.
final class Dashed extends RunnerEvent {
  const Dashed();

  /// The name it is declared and published under.
  static const String eventName = 'platformer.dashed';

  /// Its codec: nothing but the name, read back as the event.
  static final EventCodec<Dashed> codec = EventCodec<Dashed>.of(
    encode: (Dashed e) => null,
    decode: (Object? data, int version) => const Dashed(),
  );

  @override
  String get name => eventName;
}

/// Went into a slide.
final class Slid extends RunnerEvent {
  const Slid();

  /// The name it is declared and published under.
  static const String eventName = 'platformer.slid';

  /// Its codec: nothing but the name, read back as the event.
  static final EventCodec<Slid> codec = EventCodec<Slid>.of(
    encode: (Slid e) => null,
    decode: (Object? data, int version) => const Slid(),
  );

  @override
  String get name => eventName;
}

/// Caught a rope or a ladder, and stopped falling.
final class Grabbed extends RunnerEvent {
  const Grabbed();

  /// The name it is declared and published under.
  static const String eventName = 'platformer.grabbed';

  /// Its codec: nothing but the name, read back as the event.
  static final EventCodec<Grabbed> codec = EventCodec<Grabbed>.of(
    encode: (Grabbed e) => null,
    decode: (Object? data, int version) => const Grabbed(),
  );

  @override
  String get name => eventName;
}

/// Touched the ground.
///
/// Carries whether it arrived on the way down from a ground pound, which is
/// two flags in the shape it replaces and one question a caller asks here.
final class Landed extends RunnerEvent {
  const Landed({required this.pounded});

  /// The name it is declared and published under.
  static const String eventName = 'platformer.landed';

  /// Its codec: whether it was the end of a ground pound. Reads back whole.
  static final EventCodec<Landed> codec = EventCodec<Landed>.of(
    encode: (Landed e) => e.pounded,
    decode: (Object? data, int version) =>
        data is bool ? Landed(pounded: data) : null,
  );

  /// Whether the landing was the end of a ground pound.
  final bool pounded;

  @override
  String get name => eventName;
}

/// Was thrown upwards by something it landed on.
///
/// Not [EnemyStomped], which says the enemy died: this says the runner was
/// thrown, and a spring throws without anything dying.
final class Bounced extends RunnerEvent {
  const Bounced();

  /// The name it is declared and published under.
  static const String eventName = 'platformer.bounced';

  /// Its codec: nothing but the name, read back as the event.
  static final EventCodec<Bounced> codec = EventCodec<Bounced>.of(
    encode: (Bounced e) => null,
    decode: (Object? data, int version) => const Bounced(),
  );

  @override
  String get name => eventName;
}

/// A piece of the level's own furniture did something.
///
/// **Reported by the simulation on its pass over the mechanisms, not by the
/// mechanism itself**, and that is worth knowing rather than hiding: a spring
/// firing is published where the simulation reads it, which is
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

  /// The name it is declared and published under.
  static const String eventName = 'platformer.springFired';

  /// Its codec: where it happened. Reads back whole.
  static final EventCodec<SpringFired> codec = EventCodec<SpringFired>.of(
    encode: (SpringFired e) => <double>[e.at.x, e.at.y, e.at.z],
    decode: (Object? data, int version) => switch (data) {
      [final num x, final num y, final num z] => SpringFired(
        Vector3(x.toDouble(), y.toDouble(), z.toDouble()),
      ),
      _ => null,
    },
  );

  @override
  String get name => eventName;
}

/// A platform gave way under the weight on it.
final class BlockCrumbled extends FurnitureEvent {
  const BlockCrumbled(super.at);

  /// The name it is declared and published under.
  static const String eventName = 'platformer.blockCrumbled';

  /// Its codec: where it happened. Reads back whole.
  static final EventCodec<BlockCrumbled> codec = EventCodec<BlockCrumbled>.of(
    encode: (BlockCrumbled e) => <double>[e.at.x, e.at.y, e.at.z],
    decode: (Object? data, int version) => switch (data) {
      [final num x, final num y, final num z] => BlockCrumbled(
        Vector3(x.toDouble(), y.toDouble(), z.toDouble()),
      ),
      _ => null,
    },
  );

  @override
  String get name => eventName;
}

/// A block was broken.
final class BlockBroke extends FurnitureEvent {
  const BlockBroke(super.at);

  /// The name it is declared and published under.
  static const String eventName = 'platformer.blockBroke';

  /// Its codec: where it happened. Reads back whole.
  static final EventCodec<BlockBroke> codec = EventCodec<BlockBroke>.of(
    encode: (BlockBroke e) => <double>[e.at.x, e.at.y, e.at.z],
    decode: (Object? data, int version) => switch (data) {
      [final num x, final num y, final num z] => BlockBroke(
        Vector3(x.toDouble(), y.toDouble(), z.toDouble()),
      ),
      _ => null,
    },
  );

  @override
  String get name => eventName;
}

/// A power-up ran out.
///
/// **The moment a player notices, and the one a countdown cannot report**: a
/// number on a HUD reads nought on the frame it ends and on every frame after,
/// so a game watching the number cannot tell the two apart without keeping a
/// copy — which is the shape `diedThisStep` was written to remove.
final class PowerEnded extends GameEvent {
  const PowerEnded(this.power);

  /// The name it is declared and published under.
  static const String eventName = 'platformer.powerEnded';

  /// Its codec: the power's name. Reads back whole.
  static final EventCodec<PowerEnded> codec = EventCodec<PowerEnded>.of(
    encode: (PowerEnded e) => e.power,
    decode: (Object? data, int version) =>
        data is String ? PowerEnded(data) : null,
  );

  /// What ran out, by the name the level gave it.
  final String power;

  @override
  String get name => eventName;
}

/// A run of scoring ended, and here is what it was worth.
///
/// **The moment, rather than the number afterwards.** A chain worth nought
/// once it has lapsed cannot be told from one that never happened, which is
/// why this is an event and not a field that goes back to zero.
final class ChainEnded extends GameEvent {
  const ChainEnded(this.worth);

  /// The name it is declared and published under.
  static const String eventName = 'platformer.chainEnded';

  /// Its codec: what the chain was worth. Reads back whole.
  static final EventCodec<ChainEnded> codec = EventCodec<ChainEnded>.of(
    encode: (ChainEnded e) => e.worth,
    decode: (Object? data, int version) =>
        data is num ? ChainEnded(data.toDouble()) : null,
  );

  /// What the whole run came to.
  /// In points (unitless), as the scoring counts them.
  final double worth;

  @override
  String get name => eventName;
}
