import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

/// Spikes, lava, a saw blade: a volume that hurts whatever is standing in it.
///
/// Damage while overlapping rather than on entry, because a platformer's spikes
/// are a place you must not be rather than a line you must not cross — and a
/// player who lands in them and stays should keep taking it.
final class Hazard extends Mechanism with CollisionListener {
  Hazard({
    super.name,
    required this.collider,
    this.damagePerSecond = 40.0,
    this.instant = false,
  }) {
    collider
      ..kind = ColliderKind.trigger
      ..userData = this
      ..listener = this;
  }

  final Collider collider;

  final double damagePerSecond;

  /// Whether touching it is simply fatal, whatever the health.
  ///
  /// A pit of lava is not a damage number, and expressing it as one means
  /// picking a figure large enough to kill a full-health player and then
  /// discovering it is not large enough for a player with armour.
  final bool instant;

  @override
  Vector3 get origin => collider.position;

  /// Seconds accumulated this step, so damage does not depend on how many
  /// overlap callbacks the broadphase happened to dispatch.
  double _dt = 0.0;

  @override
  void step(double dt) => _dt = dt;

  @override
  ActivationOutcome activate(Activation by) {
    final who = by.by?.userData;
    if (who is! Damageable) return const NothingToDo();
    final killed = who.applyDamage(instant ? double.infinity : damagePerSecond * _dt);
    return killed ? const Activated() : const NothingToDo();
  }

  @override
  void onCollisionStart(Collider self, Collider other) {
    activate(world.activationBy(other));
  }

  @override
  void onCollision(Collider self, Collider other) {
    activate(world.activationBy(other));
  }
}
