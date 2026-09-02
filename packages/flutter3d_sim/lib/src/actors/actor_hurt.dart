import 'actor.dart';

/// An actor that took damage this step and survived it.
final class ActorHurt {
  ActorHurt(this.actor, this.amount, {this.from});
  final Actor actor;
  final double amount;

  /// Whoever dealt it, as the collider's `userData`, or null for damage with
  /// nobody behind it — a fall, a crushing lift, a pit.
  final Object? from;

  /// Whether it visibly reacted. Set by whatever decided that it did — a
  /// caller can tell a grunt from a scream.
  bool staggered = false;
}
