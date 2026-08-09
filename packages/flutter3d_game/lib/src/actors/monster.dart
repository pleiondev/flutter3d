import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../combat/weapon.dart';
import '../combat/weapon_behaviour.dart';
import '../physics/character_controller.dart';
import '../physics/collider.dart';
import '../physics/collision_shape.dart';
import '../physics/collision_world.dart';
import 'health.dart';

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

/// The roster.
abstract final class Monsters {
  /// Fast, fragile, and always in your face. The state machine's simplest case
  /// and the one that sets the game's tempo.
  static const MonsterDef runner = MonsterDef(
    name: 'runner',
    health: 45.0,
    speed: 5.4,
    radius: 0.35,
    height: 1.7,
    sightRange: 24.0,
    attack: WeaponDef(
      name: 'claws',
      behaviour: MeleeBehaviour(),
      ammo: AmmoType.none,
      damage: 9.0,
      shotsPerSecond: 1.6,
      range: 1.9,
      automatic: true,
    ),
  );

  /// Keeps its distance and throws something slow enough to dodge, which is
  /// what makes the room's geometry matter.
  static const MonsterDef shooter = MonsterDef(
    name: 'shooter',
    health: 60.0,
    speed: 3.0,
    radius: 0.38,
    height: 1.8,
    sightRange: 30.0,
    attack: WeaponDef(
      name: 'fireball',
      behaviour: ProjectileBehaviour(),
      ammo: AmmoType.none,
      damage: 22.0,
      shotsPerSecond: 0.55,
      range: 30.0,
      projectileSpeed: 13.0,
      splashRadius: 2.2,
      splashMinimumFraction: 0.2,
    ),
  );

  /// Slow, heavy, and largely indifferent to being shot.
  static const MonsterDef tank = MonsterDef(
    name: 'tank',
    health: 320.0,
    speed: 2.2,
    radius: 0.62,
    height: 2.4,
    sightRange: 22.0,
    painChance: 0.15,
    painCooldown: 1.4,
    hurtDuration: 0.18,
    attack: WeaponDef(
      name: 'slam',
      behaviour: MeleeBehaviour(arcDegrees: 100.0),
      ammo: AmmoType.none,
      damage: 34.0,
      shotsPerSecond: 0.7,
      range: 2.6,
      automatic: true,
    ),
  );

  static const Map<String, MonsterDef> byName = <String, MonsterDef>{
    'runner': runner,
    'shooter': shooter,
    'tank': tank,
  };
}

/// One monster, alive or otherwise.
final class Monster {
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
