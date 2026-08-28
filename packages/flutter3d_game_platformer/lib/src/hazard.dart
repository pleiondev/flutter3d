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
    this.follows,
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

  /// The name of a [Mover] this rides on, or null for a hazard that stays put.
  ///
  /// **This is what a saw blade is.** A hazard is a volume and a mover is a
  /// block that travels, and until this existed a level could author either but
  /// never one on the other: a moving saw had to be a platform that happened to
  /// hurt, which the mover knows nothing about, or a hazard that happened to be
  /// where the platform was, which stops being true a second later.
  ///
  /// Resolved by name on the first step rather than at spawn, because a level
  /// document may name a mover that has not been spawned yet and the order of
  /// entities in a file is not something an author should have to think about.
  final String? follows;

  Mover? _rail;
  bool _looked = false;
  final Vector3 _offset = Vector3.zero();
  final Vector3 _at = Vector3.zero();

  @override
  Vector3 get origin => collider.position;

  /// Seconds accumulated this step, so damage does not depend on how many
  /// overlap callbacks the broadphase happened to dispatch.
  double _dt = 0.0;

  /// Nothing. **A decision, not an omission**, which is what the empty map is
  /// for: what a hazard holds is a fraction of a second of accumulated contact
  /// and whether it looked for its rail yet, and both are rebuilt on the first
  /// step after a load. A player who saves standing in lava is restored
  /// standing in lava, which is the same lava either way.
  @override
  Map<String, Object?> save() => const <String, Object?>{};

  @override
  void restore(Map<String, Object?> from) {}

  @override
  void step(double dt) {
    _dt = dt;
    _ride();
  }

  /// Keeps a mounted hazard where its mover is, at the offset it was authored
  /// at — so a saw drawn a metre above its arm stays a metre above it.
  void _ride() {
    final name = follows;
    if (name == null) return;
    if (!_looked) {
      _looked = true;
      final found = world[name];
      if (found is Mover) {
        _rail = found;
        _offset
          ..setFrom(collider.position)
          ..sub(found.collider.position);
      }
    }
    final rail = _rail;
    if (rail == null) return;
    _at
      ..setFrom(rail.collider.position)
      ..add(_offset);
    collider.moveTo(_at);
  }

  @override
  ActivationOutcome activate(Activation by) {
    final who = by.by?.userData;
    if (who is! Damageable) return const NothingToDo();
    final killed = who.applyDamage(
      instant ? double.infinity : damagePerSecond * _dt,
    );
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
