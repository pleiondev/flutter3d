import 'package:vector_math/vector_math.dart';

import 'package:flutter3d_physics/flutter3d_physics.dart';
import '../physics/layers.dart';

/// An explosion's shape: how far it reaches and how hard.
final class Blast {
  const Blast({
    required this.radius,
    required this.damage,
    this.minimumFraction = 0.0,
    this.knockback = 0.0,
  });

  final double radius;

  /// Damage at the very centre.
  final double damage;

  /// Fraction of [damage] still delivered at the outer edge.
  ///
  /// Zero by default, so the edge of a blast is a warning rather than a wound.
  /// A blast that does most of its damage everywhere inside its radius removes
  /// any reason to move.
  final double minimumFraction;

  final double knockback;

  /// Damage at [distance] from the centre.
  ///
  /// Linear, like the weapons' range falloff and for the same reason: a curve
  /// a player cannot predict is a curve they cannot play around.
  double damageAt(double distance) {
    if (distance >= radius) return 0.0;
    if (radius <= 0.0) return damage;
    final t = distance / radius;
    return damage * (1.0 - t * (1.0 - minimumFraction));
  }
}

/// Works out who an explosion actually hurt.
///
/// ## Line of sight is the whole job
///
/// A blast that damages everything inside a sphere goes through walls, and the
/// player finds out by being killed by a rocket in the next room. Every
/// candidate is therefore checked against the world geometry first, and one
/// that cannot be seen from the centre takes nothing.
///
/// The check is a single ray to the target's centre, which is cheap and
/// slightly conservative: a monster peeking round a corner survives a blast
/// that would clip its shoulder. Erring that way is right — a player who takes
/// damage they cannot explain blames the game, and one who deals none they
/// cannot explain blames their aim.
final class BlastResolver {
  BlastResolver(this.world);

  final CollisionWorld world;

  final List<Collider> _candidates = <Collider>[];
  final RayHit _sight = RayHit();
  final Vector3 _toTarget = Vector3.zero();

  /// Fills [out] with the damage each collider takes.
  ///
  /// The one who fired is included on purpose. A rocket at your own feet should
  /// hurt, and it is the price of the launcher being the best weapon in the
  /// game at close range.
  void resolve(
    Blast blast,
    Vector3 centre,
    Map<Collider, double> out, {
    int mask = CollisionLayers.player | CollisionLayers.monster,
  }) {
    out.clear();
    world.overlap(
      CollisionSphere(blast.radius),
      centre,
      _candidates,
      mask: mask,
      includeTriggers: false,
    );

    for (final target in _candidates) {
      _toTarget
        ..setFrom(target.position)
        ..sub(centre);
      final distance = _toTarget.length;
      final damage = blast.damageAt(distance);
      if (damage <= 0.0) continue;

      // Standing inside the blast's own point of origin: nothing can be in the
      // way, and normalising a zero vector is undefined anyway.
      if (distance > 1e-4) {
        _toTarget.scale(1.0 / distance);
        if (_blockedByGeometry(centre, distance)) continue;
      }

      out[target] = damage;
    }
  }

  bool _blockedByGeometry(Vector3 centre, double distance) {
    if (!world.raycast(
      centre,
      _toTarget,
      distance,
      _sight,
      mask: CollisionLayers.world,
    )) {
      return false;
    }
    // Touching the wall the target is standing against does not count as being
    // behind it.
    return _sight.distance < distance - 0.05;
  }
}
