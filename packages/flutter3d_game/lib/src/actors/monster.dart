import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../combat/weapon.dart';
import '../combat/weapon_behaviour.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import '../world/rider.dart';
import 'damageable.dart';
import 'health.dart';
import '../physics/layers.dart';

/// What a monster is doing.
///
/// An enum and not a hierarchy, deliberately, and against the grain of the rest
/// of this package. The states share every transition — anything can be hurt,
/// anything that is hurt enough dies, anything that can see the player chases
/// them — so a class per state would be six classes repeating one another's
/// rules. What differs between monsters is *numbers* and *how they attack*, and
/// those are [MonsterDef] and [WeaponBehaviour] respectively.
enum MonsterState {
  /// Has not noticed anything. Cheapest state, and most monsters spend most of
  /// the level in it.
  idle,

  /// Has noticed, and is turning to face before it moves. A monster that
  /// snaps to face the player the instant it sees them reads as a turret.
  alert,

  chase,
  attack,

  /// Briefly staggered. Long enough to read as a reaction, short enough that
  /// it cannot be used to stun-lock something to death.
  hurt,

  dead,
}

/// Everything about a kind of monster that does not change.
///
/// Numbers, plus the weapon it attacks with. Reusing [WeaponDef] rather than
/// inventing a parallel notion of a monster attack: an attack has damage, a
/// rate, a range and a way of arriving, which is a weapon — and it means a
/// monster that throws fireballs gets the projectile system, the blast falloff
/// and the line-of-sight check without a line of new code.
final class MonsterDef {
  const MonsterDef({
    required this.name,
    required this.health,
    required this.speed,
    required this.attack,
    required this.radius,
    required this.height,
    this.sightRange = 26.0,
    this.hurtDuration = 0.25,
    this.alertDuration = 0.35,
    this.turnRate = 6.0,
    this.painChance = 1.0,
    this.painCooldown = 0.2,
  });

  final String name;
  final double health;

  /// Metres per second while chasing.
  final double speed;

  final WeaponDef attack;

  final double radius;
  final double height;

  /// How far it can notice the player, given a clear line.
  final double sightRange;

  final double hurtDuration;

  /// How long it hesitates on first noticing the player.
  final double alertDuration;

  /// Radians per second it can turn.
  final double turnRate;

  /// Probability that a hit staggers it at all.
  ///
  /// Below one for the heavy monsters: something that flinches at every pellet
  /// can be held in place by a shotgun and never reaches the player, which
  /// turns the hardest enemy in the game into the easiest.
  final double painChance;

  /// How long after a stagger it cannot be staggered again.
  ///
  /// A chance alone is not enough, and the test that proved it is worth
  /// keeping in mind: at sixty hits a second even a fifteen-percent chance
  /// re-triggers before the previous stagger has finished, so the monster
  /// spends two thirds of the fight flinching. The cooldown is what actually
  /// bounds it.
  final double painCooldown;
}


/// One monster, alive or otherwise.
final class Monster implements Damageable, Rider {
  Monster({
    required this.def,
    required CollisionWorld world,
    required Vector3 position,
    this.yaw = 0.0,
  })  : health = Health(def.health),
        body = CharacterController(
          world: world,
          shape: CollisionCapsule(
            radius: def.radius,
            halfHeight: math.max(0.01, def.height / 2.0 - def.radius),
          ),
          position: position,
          layer: CollisionLayers.monster,
          tuning: MovementTuning(
            walkSpeed: def.speed,
            sprintSpeed: def.speed,
            // No jumping and no coyote time: a monster that leaves the ground
            // is a monster that has walked off something, and it should simply
            // fall.
            jumpSpeed: 0.0,
            coyoteTime: 0.0,
            jumpBufferTime: 0.0,
          ),
        ) {
    body.collider.userData = this;
  }

  final MonsterDef def;
  final Health health;

  /// How this monster takes damage, installed by whatever is running it.
  ///
  /// A function rather than a reference to `MonsterSystem`, and not for
  /// tidiness: the system already imports this file, so naming it here would
  /// close a cycle between the two. One closure per monster, made once when it
  /// spawns.
  /// A monster rides a platform the same way the player does. See [Rider].
  @override
  Collider? get carriedBy => body.groundBody;

  bool Function(double amount)? onDamage;

  /// Takes damage the way its system would, because it *is* its system.
  ///
  /// **Not `health.damage(amount)`.** That subtracts the number and skips
  /// everything being hurt means here: the corpse stays solid and turns the
  /// corridor into a maze of your own making, the death never reaches
  /// `MonsterSystem.died`, the flinch is not rolled, and a monster shot from
  /// behind never notices.
  ///
  /// A monster with nothing running it is one built by hand in a test; it takes
  /// the damage to its health, which is all there is to do with it.
  @override
  bool applyDamage(double amount) =>
      onDamage?.call(amount) ?? health.damage(amount);
  final CharacterController body;

  /// Which way it is facing, in radians about Y.
  double yaw;

  MonsterState state = MonsterState.idle;

  /// Seconds spent in the current state, for animation and for timing out of
  /// [MonsterState.hurt] and [MonsterState.alert].
  double stateTime = 0.0;

  /// Seconds until it can attack again.
  double attackCooldown = 0.0;

  /// Seconds until it can be staggered again.
  double painCooldown = 0.0;

  /// True once it has noticed the player, and it never goes back to false.
  ///
  /// A monster that forgets and re-notices produces the alert hesitation over
  /// and over, which reads as a stutter rather than as caution.
  bool hasNoticed = false;

  Vector3 get position => body.position;
  bool get isAlive => health.isAlive;

  /// Where a shot from this monster leaves, and where a player's shot should
  /// aim. Two thirds up the body rather than the centre, which is roughly the
  /// chest on anything humanoid.
  Vector3 eyeLevel(Vector3 out) => out
    ..setFrom(body.position)
    ..y += def.height * 0.16;
}
