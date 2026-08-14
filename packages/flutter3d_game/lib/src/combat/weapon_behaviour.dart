import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'hitscan.dart';
import 'projectile.dart';
import 'weapon.dart';
import '../physics/layers.dart';

/// One shot, from where it starts to what it reached.
///
/// Reused between shots rather than made fresh: a held automatic weapon fires
/// several times a second and this sits on the simulation step.
final class WeaponShot {
  WeaponShot({required this.world, required this.hitscan, this.projectiles});

  final CollisionWorld world;
  final Hitscan hitscan;

  /// Where launched things go. Null in a world that has none — a test of the
  /// firing rules does not need a projectile system to exist.
  ProjectileSystem? projectiles;

  late WeaponDef weapon;
  final Vector3 origin = Vector3.zero();
  final Vector3 aim = Vector3.zero();

  /// The shooter, so a weapon does not hit the body holding it. The muzzle is
  /// inside that body.
  Collider? shooter;

  /// Filled by the behaviour. Empty when nothing was reached, and for a
  /// projectile, which lands later.
  final List<ShotHit> hits = <ShotHit>[];

  void begin(WeaponDef weapon, Vector3 origin, Vector3 aim, {Collider? shooter}) {
    this.weapon = weapon;
    this.origin.setFrom(origin);
    this.aim.setFrom(aim);
    this.shooter = shooter;
    hits.clear();
  }
}

/// How a weapon delivers a shot that has already been paid for.
///
/// A hierarchy rather than a `kind` field the caller switches on. The three
/// ways a shot arrives have almost nothing in common — one traces rays, one
/// sweeps an arc, one launches something with a flight time — and every place
/// that fired a weapon would otherwise repeat the same three-way branch. The
/// firing code now says `weapon.behaviour.deliver(shot)` and knows nothing.
///
/// Note what stayed data: [WeaponDef] is still a record of numbers. Damage,
/// rate and spread get adjusted by feel hundreds of times, and putting them in
/// subclasses would mean a rebuild per tweak and a class per gun. Behaviour is
/// polymorphic; tuning is not.
sealed class WeaponBehaviour {
  const WeaponBehaviour();

  void deliver(WeaponShot shot);
}

/// Rays, arriving the instant the trigger does.
final class HitscanBehaviour extends WeaponBehaviour {
  const HitscanBehaviour();

  @override
  void deliver(WeaponShot shot) {
    shot.hits.addAll(
      shot.hitscan.fire(
        shot.weapon,
        shot.origin,
        shot.aim,
        ignore: shot.shooter,
      ),
    );
  }
}

/// A swing: everything close enough and roughly in front.
///
/// Not a short ray, which is what this was before it had its own class. A ray
/// misses a monster standing beside the player's shoulder, and a punch should
/// not — the reach of a swing is an arc, and an arc is what a player expects to
/// connect with.
final class MeleeBehaviour extends WeaponBehaviour {
  const MeleeBehaviour({this.arcDegrees = 70.0});

  /// Full width of the arc the swing covers.
  final double arcDegrees;

  @override
  void deliver(WeaponShot shot) {
    final weapon = shot.weapon;
    final reach = weapon.range;
    final forward = shot.aim.normalized();

    // Centred half a reach ahead, so the sphere covers the arm's length rather
    // than a bubble around the player.
    final centre = Vector3(
      shot.origin.x + forward.x * reach * 0.5,
      shot.origin.y + forward.y * reach * 0.5,
      shot.origin.z + forward.z * reach * 0.5,
    );

    final candidates = <Collider>[];
    shot.world.overlap(
      CollisionSphere(reach * 0.5),
      centre,
      candidates,
      ignore: shot.shooter,
      includeTriggers: false,
    );

    final minimumCosine = math.cos(arcDegrees * 0.5 * math.pi / 180.0);
    final toTarget = Vector3.zero();
    // The arc is horizontal, so the cone test ignores height. Measuring it in
    // three dimensions from the swinger's eye rejects anything shorter than
    // them: the direction to a crouching target's centre points downwards, out
    // of a cone aimed level. Distance still counts all three axes.
    final flatForward = Vector3(forward.x, 0.0, forward.z);
    if (flatForward.length2 > 1e-9) flatForward.normalize();
    final flatToTarget = Vector3.zero();

    for (final target in candidates) {
      toTarget
        ..setFrom(target.position)
        ..sub(shot.origin);
      final distance = toTarget.length;
      if (distance > reach || distance <= 1e-6) continue;

      toTarget.scale(1.0 / distance);
      flatToTarget.setValues(toTarget.x, 0.0, toTarget.z);
      if (flatToTarget.length2 > 1e-9) {
        flatToTarget.normalize();
        if (flatToTarget.dot(flatForward) < minimumCosine) continue;
      }

      // A swing does not stop at a wall the way a ray does, but it must not
      // reach through one either.
      if (_blocked(shot, forward, target, distance)) continue;

      shot.hits.add(
        ShotHit(
          collider: target,
          point: target.position,
          normal: -toTarget,
          distance: distance,
          damage: weapon.damageAt(distance),
        ),
      );
    }
  }

  bool _blocked(
    WeaponShot shot,
    Vector3 forward,
    Collider target,
    double distance,
  ) {
    final hit = RayHit();
    final direction = (target.position - shot.origin)..normalize();
    if (!shot.world.raycast(
      shot.origin,
      direction,
      distance,
      hit,
      ignore: shot.shooter,
      mask: CollisionLayers.world,
    )) {
      return false;
    }
    return hit.distance < distance - 1e-3;
  }
}

/// Something with a flight time, which the target can move out of the way of.
///
/// The one behaviour whose effect is not immediate, which is exactly why it
/// needs to be its own class rather than an early return in the middle of the
/// firing code: [WeaponShot.hits] stays empty and the damage arrives later,
/// through the projectile system, from wherever the rocket ends up.
final class ProjectileBehaviour extends WeaponBehaviour {
  const ProjectileBehaviour();

  @override
  void deliver(WeaponShot shot) {
    final system = shot.projectiles;
    final blast = shot.weapon.blast;
    if (system == null || blast == null) return;

    system.spawn(
      position: shot.origin,
      direction: shot.aim,
      speed: shot.weapon.projectileSpeed,
      blast: blast,
      owner: shot.shooter,
    );
  }
}
