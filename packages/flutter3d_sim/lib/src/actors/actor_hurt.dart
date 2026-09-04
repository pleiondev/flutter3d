import '../loop/game_event.dart';
import 'actor.dart';

/// An actor took damage this step and survived it.
///
/// A [GameEvent] rather than a value in a list beside one: this class already
/// carried everything an event carries, and having it be the event is what
/// stops the two from drifting.
final class ActorHurt extends GameEvent {
  ActorHurt(this.actor, this.amount, {this.from});

  final Actor actor;
  final double amount;

  /// Whoever dealt it, as the collider's `userData`, or null for damage with
  /// nobody behind it — a fall, a crushing lift, a pit.
  final Object? from;

  /// Whether it visibly reacted. Set by whatever decided that it did — a
  /// caller can tell a grunt from a scream.
  ///
  /// **Written after this is recorded**, by the brain that reacts to the
  /// damage later in the same step. That is safe because events are drained by
  /// the owner of the step, after the step: a reader never sees this one before
  /// everything that had an opinion about it has spoken.
  bool staggered = false;

  @override
  String get name => 'actor hurt ($amount)';
}

/// An actor's health reached zero this step.
///
/// One per actor, recorded where the death happens rather than collected into
/// a list read afterwards. The distinction is not academic: the list this
/// replaces was cleared at the top of `ActorSystem.step`, which is halfway
/// through a game's step, so a monster the player shot before the actors
/// thought was added and wiped again in the same step. Nothing downstream ever
/// saw it — no death sound, no sparks, no count. A drained buffer has no such
/// point to lose anything at, because whoever owns the step owns the draining.
final class ActorDied extends GameEvent {
  const ActorDied(this.actor, {this.from});

  final Actor actor;

  /// Whoever killed it, as the collider's `userData`, or null for a death with
  /// nobody behind it.
  final Object? from;

  @override
  String get name => 'actor died';
}
