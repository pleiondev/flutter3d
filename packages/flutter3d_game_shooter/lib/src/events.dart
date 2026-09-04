/// What a step of this game did, for a game that wants to hear about it.
///
/// Drained from `GameSimulation.events` after each step. See [GameEvent] for
/// why this is a drained buffer rather than a stream, and for why nothing here
/// names a sound: these say what happened, and what to do about it is the
/// game's decision.
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
/// a monster dying is not a shooter's idea, and arrive in the same buffer as
/// these. A game that adds a mechanic adds its own event beside them —
/// [GameEvent] is open, and nothing here dispatches on the type.
library;

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

  final WeaponDef weapon;

  /// Where the shot came from, copied rather than held: the simulation reuses
  /// one vector for this across steps, and an event that aliased it would
  /// report the position of whatever fired next.
  final Vector3 from;

  @override
  String get name => 'shot fired (${weapon.name})';
}

/// A shot reached something.
///
/// One per hit, so a shotgun landing four pellets in a wall and four in a
/// monster is eight of these — which is what a game wants for eight impact
/// marks, and what no single field could have said.
final class ShotLanded extends GameEvent {
  const ShotLanded(this.hit);

  final ShotHit hit;

  @override
  String get name => 'shot landed';
}

/// The player took damage this step, from everything at once.
///
/// One per step rather than one per source: the player has a single pool of
/// health, a step's damage is applied to it as a sum, and a game that wanted
/// to react per source would be reacting to arithmetic that already happened.
final class PlayerHurt extends GameEvent {
  const PlayerHurt(this.amount);

  /// How much health the step cost, always above zero.
  final double amount;

  @override
  String get name => 'player hurt ($amount)';
}

/// The player's health reached zero this step.
///
/// Once per death, on the step it happened — not on every step afterwards,
/// which is what reading `player.isAlive` gives.
final class PlayerDied extends GameEvent {
  const PlayerDied();

  @override
  String get name => 'player died';
}

/// The player walked into a secret.
final class SecretFound extends GameEvent {
  const SecretFound(this.secret);

  final Secret secret;

  @override
  String get name => 'secret found';
}

/// The player pressed something, and here is what came of it.
///
/// Carries the outcome rather than a bool, so a game can say what a locked
/// door told the player without asking the door again. [ActivationOutcome] is
/// itself open: a game whose door has a fourth answer gets it here unchanged.
final class MechanismUsed extends GameEvent {
  const MechanismUsed(this.outcome);

  final ActivationOutcome outcome;

  @override
  String get name => 'mechanism used';
}
