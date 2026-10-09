/// What a step of this game did, for a game that wants to hear about it.
///
/// Published onto the engine's bus from inside the step that raised them
/// (`GameSimulation.publishTo`, which `ShooterPlugin` calls), each under the
/// name it is declared with and with its codec. See [GameEvent] for why
/// nothing here names a sound: these say what happened, and what to do about
/// it is the game's decision.
///
/// **The simulation already had half of this**, in fields like
/// `GameSimulation.firedThisStep` — one moment of each kind per step, readable
/// only until the next step clears it. Those stay, because programs read them.
/// What they cannot do is carry two of anything: a shotgun landing eight
/// pellets is eight hits and one `firedThisStep`, and a step that kills three
/// monsters used to be a number in a tally. Events carry all of them, in the
/// order they happened.
///
/// The list below is what this template can see happening, and it is not the
/// whole list: `ActorDied` and `ActorHurt` come from `flutter3d_sim`, because
/// a monster dying is not a shooter's idea, and arrive on the same step channel
/// as these, in the order the step raised them. A game that adds a mechanic adds its own event beside them —
/// [GameEvent] is open, and nothing here dispatches on the type.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';
import 'combat/shot_hit.dart';
import 'combat/weapon_def.dart';
import 'secret.dart';

/// The player pulled a trigger and the shot was delivered.
///
/// One per shot, whatever the shot did: a burst that hits nothing still fired.
/// The hits it landed arrive separately, as [ShotLanded], because a shotgun
/// has one of these and up to eight of those.
final class ShotFired extends GameEvent {
  ShotFired({required this.weapon, required Vector3 from})
    : from = Vector3.copy(from);

  /// The name it is declared and published under.
  static const String eventName = 'shooter.shotFired';

  /// Its codec: the weapon's name and where the shot came from. Reads back
  /// as null, since a weapon is the game's roster and not a value.
  static final EventCodec<ShotFired> codec = EventCodec<ShotFired>.of(
    encode: (ShotFired e) => <Object?>[
      e.weapon.name,
      e.from.x,
      e.from.y,
      e.from.z,
    ],
    decode: (Object? data, int version) => null,
  );

  final WeaponDef weapon;

  /// Where the shot came from, copied rather than held: the simulation reuses
  /// one vector for this across steps, and an event that aliased it would
  /// report the position of whatever fired next.
  final Vector3 from;

  @override
  String get name => eventName;
}

/// A shot reached something.
///
/// One per hit, so a shotgun landing four pellets in a wall and four in a
/// monster is eight of these — which is what a game wants for eight impact
/// marks, and what no single field could have said.
final class ShotLanded extends GameEvent {
  const ShotLanded(this.hit);

  /// The name it is declared and published under.
  static const String eventName = 'shooter.shotLanded';

  /// Its codec: where the hit landed, how far and for how much, and whether
  /// it struck anything. Reads back as null, since what it struck is a live
  /// collider and not a value.
  static final EventCodec<ShotLanded> codec = EventCodec<ShotLanded>.of(
    encode: (ShotLanded e) => <Object?>[
      e.hit.point.x,
      e.hit.point.y,
      e.hit.point.z,
      e.hit.distance,
      e.hit.damage,
      e.hit.didStrikeSomething,
    ],
    decode: (Object? data, int version) => null,
  );

  final ShotHit hit;

  @override
  String get name => eventName;
}

/// The player took damage this step, from everything at once.
///
/// One per step rather than one per source: the player has a single pool of
/// health, a step's damage is applied to it as a sum, and a game that wanted
/// to react per source would be reacting to arithmetic that already happened.
final class PlayerHurt extends GameEvent {
  const PlayerHurt(this.amount);

  /// The name it is declared and published under.
  static const String eventName = 'shooter.playerHurt';

  /// Its codec: the amount. Reads back whole.
  static final EventCodec<PlayerHurt> codec = EventCodec<PlayerHurt>.of(
    encode: (PlayerHurt e) => e.amount,
    decode: (Object? data, int version) =>
        data is num ? PlayerHurt(data.toDouble()) : null,
  );

  /// How much health the step cost, always above zero.
  final double amount;

  @override
  String get name => eventName;
}

/// The player's health reached zero this step.
///
/// Once per death, on the step it happened — not on every step afterwards,
/// which is what reading `player.isAlive` gives.
final class PlayerDied extends GameEvent {
  const PlayerDied();

  /// The name it is declared and published under.
  static const String eventName = 'shooter.playerDied';

  /// Its codec: nothing to carry. Reads back whole.
  static final EventCodec<PlayerDied> codec = EventCodec<PlayerDied>.of(
    encode: (PlayerDied e) => null,
    decode: (Object? data, int version) => const PlayerDied(),
  );

  @override
  String get name => eventName;
}

/// The player walked into a secret.
final class SecretFound extends GameEvent {
  const SecretFound(this.secret);

  /// The name it is declared and published under.
  static const String eventName = 'shooter.secretFound';

  /// Its codec: the secret's name in the level. Reads back as null, since a
  /// secret is a live part of a level and not a value.
  static final EventCodec<SecretFound> codec = EventCodec<SecretFound>.of(
    encode: (SecretFound e) => e.secret.name,
    decode: (Object? data, int version) => null,
  );

  final Secret secret;

  @override
  String get name => eventName;
}

/// The player pressed something, and here is what came of it.
///
/// Carries the outcome rather than a bool, so a game can say what a locked
/// door told the player without asking the door again. [ActivationOutcome] is
/// itself open: a game whose door has a fourth answer gets it here unchanged.
final class MechanismUsed extends GameEvent {
  const MechanismUsed(this.outcome);

  /// The name it is declared and published under.
  static const String eventName = 'shooter.mechanismUsed';

  /// Its codec: which of the engine's outcomes it was and its message. The
  /// engine's three read back; a game's own outcome is written as `other`
  /// with its message and reads back as null, since only the game knows its
  /// class.
  static final EventCodec<MechanismUsed> codec = EventCodec<MechanismUsed>.of(
    encode: (MechanismUsed e) => <Object?>[
      switch (e.outcome) {
        Activated() => 'activated',
        Refused() => 'refused',
        NothingToDo() => 'nothingToDo',
        _ => 'other',
      },
      e.outcome.message,
    ],
    decode: (Object? data, int version) => switch (data) {
      ['activated', _] => const MechanismUsed(Activated()),
      ['refused', final String message] => MechanismUsed(Refused(message)),
      ['nothingToDo', _] => const MechanismUsed(NothingToDo()),
      _ => null,
    },
  );

  final ActivationOutcome outcome;

  @override
  String get name => eventName;
}
