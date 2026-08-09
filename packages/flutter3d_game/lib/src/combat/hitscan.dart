import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../physics/collider.dart';
import '../physics/collision_world.dart';
import 'weapon.dart';

/// One thing a shot reached.
///
/// Named for the shot rather than for the ray, because a melee swing produces
/// these as well and it does not cast one.
final class ShotHit {
  ShotHit({
    required this.collider,
    required Vector3 point,
    required Vector3 normal,
    required this.distance,
    required this.damage,
  })  : point = point.clone(),
        normal = normal.clone();

  /// What was struck. Null when the ray reached its range without meeting
  /// anything, which still matters: a tracer has to end somewhere.
  final Collider? collider;

  final Vector3 point;
  final Vector3 normal;
  final double distance;

  /// After falloff. Zero when nothing was hit.
  final double damage;

  bool get struckSomething => collider != null;
}

/// Fires a weapon's rays into the world and reports where they landed.
///
/// ## The spread is mostly not random
///
/// A shotgun's pellets follow a fixed pattern — one down the middle and the
/// rest on a ring — with only a small random jitter on top. Fully random spread
/// makes the same shot at the same range do wildly different damage, which
/// reads to a player as the game cheating rather than as variance. A fixed
/// pattern means a shotgun at close range always kills what it is pointed at,
/// and that reliability is the whole character of the weapon.
///
/// The jitter exists so two consecutive shots do not draw identical tracers.
///
/// ## What it tests against
///
/// The collision world, not the render meshes. Those are two different things —
/// a wall is one merged surface per material by the time it is drawn — and the
/// player's expectation is set by what they cannot walk through.
final class Hitscan {
  Hitscan({required this.world, math.Random? random})
      : _random = random ?? math.Random();

  final CollisionWorld world;
  final math.Random _random;

  /// How far the jitter can move a ray, as a fraction of the weapon's spread.
  static const double jitterFraction = 0.25;

  final RayHit _hit = RayHit();
  final Vector3 _direction = Vector3.zero();
  final Vector3 _right = Vector3.zero();
  final Vector3 _up = Vector3.zero();
  final Vector3 _endPoint = Vector3.zero();

  /// Fires one shot and returns a hit per ray, in pattern order.
  ///
  /// [aim] need not be normalised. [ignore] keeps a shooter from hitting
  /// themselves, which matters because the muzzle is inside their own collider.
  List<ShotHit> fire(
    WeaponDef weapon,
    Vector3 origin,
    Vector3 aim, {
    Collider? ignore,
    int mask = CollisionLayers.all,
  }) {
    final forward = aim.normalized();
    _basisFrom(forward);

    final hits = <ShotHit>[];
    for (var i = 0; i < weapon.rayCount; i++) {
      _aimRay(forward, weapon, i);
      hits.add(_castOne(weapon, origin, ignore, mask));
    }
    return hits;
  }

  /// Total damage a shot delivered to one collider.
  ///
  /// Summed per target rather than per ray, because that is what applying it
  /// needs: eight pellets in the same monster is one death, and telling the
  /// health system eight times invites eight death animations.
  static Map<Collider, double> damageByTarget(List<ShotHit> hits) {
    final totals = <Collider, double>{};
    for (final hit in hits) {
      final collider = hit.collider;
      if (collider == null || hit.damage <= 0.0) continue;
      totals[collider] = (totals[collider] ?? 0.0) + hit.damage;
    }
    return totals;
  }

  /// Two axes across the aim direction.
  ///
  /// The world up is a poor second axis when the player is looking straight
  /// down, so it is swapped for a horizontal one there. Without that, spread
  /// collapses to a line at exactly the angle a player shooting at their own
  /// feet is using.
  void _basisFrom(Vector3 forward) {
    final reference = forward.y.abs() > 0.99
        ? Vector3(1.0, 0.0, 0.0)
        : Vector3(0.0, 1.0, 0.0);
    _right
      ..setFrom(forward.cross(reference))
      ..normalize();
    _up
      ..setFrom(_right.cross(forward))
      ..normalize();
  }

  /// Points [_direction] at ray [index] of the pattern.
  void _aimRay(Vector3 forward, WeaponDef weapon, int index) {
    _direction.setFrom(forward);
    if (weapon.rayCount == 1 || weapon.spread <= 0.0) {
      if (weapon.spread > 0.0) _applyJitter(weapon.spread);
      _direction.normalize();
      return;
    }

    // Ray zero goes down the middle, so a shotgun always lands something where
    // the crosshair is. The rest sit on a ring.
    if (index == 0) {
      _applyJitter(weapon.spread * jitterFraction);
      _direction.normalize();
      return;
    }

    final petals = weapon.rayCount - 1;
    final angle = (index - 1) / petals * 2.0 * math.pi;
    final offsetRight = math.cos(angle) * weapon.spread;
    final offsetUp = math.sin(angle) * weapon.spread;

    _direction
      ..x += _right.x * offsetRight + _up.x * offsetUp
      ..y += _right.y * offsetRight + _up.y * offsetUp
      ..z += _right.z * offsetRight + _up.z * offsetUp;

    _applyJitter(weapon.spread * jitterFraction);
    _direction.normalize();
  }

  void _applyJitter(double amount) {
    if (amount <= 0.0) return;
    final right = (_random.nextDouble() * 2.0 - 1.0) * amount;
    final up = (_random.nextDouble() * 2.0 - 1.0) * amount;
    _direction
      ..x += _right.x * right + _up.x * up
      ..y += _right.y * right + _up.y * up
      ..z += _right.z * right + _up.z * up;
  }

  ShotHit _castOne(
    WeaponDef weapon,
    Vector3 origin,
    Collider? ignore,
    int mask,
  ) {
    final found = world.raycast(
      origin,
      _direction,
      weapon.range,
      _hit,
      ignore: ignore,
      mask: mask,
    );

    if (!found) {
      // Still reported, with the point the ray reached: a tracer or an impact
      // effect needs somewhere to end even when nothing was there.
      _endPoint
        ..setFrom(_direction)
        ..scale(weapon.range)
        ..add(origin);
      return ShotHit(
        collider: null,
        point: _endPoint,
        normal: -_direction,
        distance: weapon.range,
        damage: 0.0,
      );
    }

    return ShotHit(
      collider: _hit.collider,
      point: _hit.point,
      normal: _hit.normal,
      distance: _hit.distance,
      damage: weapon.damageAt(_hit.distance),
    );
  }
}
