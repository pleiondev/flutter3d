/// Something in the world that walks, can be hurt, and is driven by a [Brain].
///
/// This was `Monster`, and the rename is the point rather than decoration. A
/// monster is a thing a *shooter* has; a platformer has an enemy that paces a
/// ledge, a racing game has a rival, a stealth game has a guard on a route.
/// All four are a body with health that something decides for, and that is what
/// this is. What differs is the brain, and the brain belongs to the game.
///
/// What is deliberately **not** here, because it was here as `Monster` and is a
/// shooter's idea rather than an engine's: a state called `alert`, a weapon to
/// attack with, a chance of flinching, a range at which it notices you. Those
/// are in `lib/shooter.dart` on `ChaseBrain`, which the barrel does not export.
library;

import 'package:vector_math/vector_math.dart';

import 'package:flutter3d_physics/flutter3d_physics.dart';
import '../world/rider.dart';
import 'brain.dart';
import 'damageable.dart';
import 'health.dart';

final class Actor implements Damageable, Rider {
  Actor({
    required this.body,
    required this.health,
    required this.brain,
    this.turnRate = 6.0,
    this.eyeFraction = 0.32,
    this.yaw = 0.0,
  }) {
    body.collider.userData = this;
  }

  /// The capsule that walks, slides along walls and falls off ledges.
  final CharacterController body;

  final Health health;

  /// What decides. Replaceable at runtime, which is what a game needs to turn
  /// a guard into a fleeing civilian without rebuilding the body.
  Brain brain;

  /// Radians a second. How fast it comes round to face something.
  double turnRate;

  /// Where the eye sits, as a fraction of the body's half-height above its
  /// centre. Roughly the chest on anything humanoid, which is what a shot
  /// should leave from and what a shot should aim at.
  double eyeFraction;

  /// Which way it is facing, in radians about Y.
  double yaw;

  /// Which actor this is, counting from zero as they were added.
  ///
  /// **It replaces `hashCode`, and that was a real bug rather than a tidy-up.**
  /// The system staggers thinking across steps so thirty actors do not all
  /// raycast on the same one, and it used the object's hash to spread them —
  /// which is its identity, which is its address, which differs between two
  /// runs of the same game with the same seed. Two identical playthroughs
  /// diverged. Found by the determinism test, which is the only thing that
  /// could have found it.
  int ordinal = 0;

  /// Installed by the system, so that being hurt goes through the system that
  /// counts deaths, rolls flinches and stops corpses blocking corridors.
  ///
  /// A closure rather than a reference to the system, because that file already
  /// imports this one and naming it here would close a cycle.
  bool Function(double amount)? onDamage;

  @override
  bool applyDamage(double amount) =>
      onDamage?.call(amount) ?? health.damage(amount);

  @override
  Collider? get carriedBy => body.groundBody;

  Vector3 get position => body.position;

  bool get isAlive => health.isAlive;

  /// Where a shot from this actor leaves, and where a shot at it should aim.
  Vector3 eyeLevel(Vector3 out) => out
    ..setFrom(body.position)
    ..y += body.halfExtents.y * eyeFraction;

  Map<String, Object?> save() => <String, Object?>{
        'body': body.save(),
        'health': health.save(),
        'yaw': yaw,
        'brain': brain.save(),
      };

  void restore(Map<String, Object?> from) {
    final body = from['body'];
    if (body is Map) this.body.restore(body.cast<String, Object?>());
    final health = from['health'];
    if (health is Map) this.health.restore(health.cast<String, Object?>());
    yaw = (from['yaw'] as num?)?.toDouble() ?? yaw;
    final brain = from['brain'];
    if (brain is Map) this.brain.restore(brain.cast<String, Object?>());
    // A corpse stops being an obstacle when it dies, and has to still be one
    // after a load — otherwise reloading a save turns every body you walked
    // over back into a wall.
    this.body.collider.kind =
        isAlive ? ColliderKind.kinematic : ColliderKind.trigger;
  }
}
