import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../combat/hitscan.dart';
import '../combat/projectile.dart';
import '../combat/weapon_behaviour.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'monster.dart';
import '../physics/layers.dart';

/// Everything that wants to kill the player, and the rules it follows.
///
/// ## The AI is deliberately simple
///
/// See the player, turn, walk straight at them, hit them. No navigation mesh,
/// no pathfinding, no flanking. Monsters get stuck on corners, and in a game
/// this fast that is rarely visible — the plan chose this trade explicitly, and
/// the alternative is a navmesh, which is a stage of its own.
///
/// What it does have is the two things whose absence is immediately visible:
/// a line-of-sight test, so nothing charges through a wall at a player it
/// cannot see, and wall sliding, so a monster that meets a corner keeps moving
/// along it instead of grinding into it for ever.
///
/// ## Nothing targets anything but the player
///
/// No infighting, decided in the plan. It keeps the target a single reference
/// rather than a search, and it removes the whole class of bug where two
/// monsters lock onto each other and the fight resolves itself off screen.
final class MonsterSystem {
  MonsterSystem({
    required this.world,
    required this.projectiles,
    math.Random? random,
  })  : _random = random ?? math.Random(),
        _shot = WeaponShot(
          world: world,
          hitscan: Hitscan(world: world),
          projectiles: projectiles,
        );

  final CollisionWorld world;
  final ProjectileSystem projectiles;
  final math.Random _random;
  final WeaponShot _shot;

  final List<Monster> monsters = <Monster>[];

  /// How often a monster far from the player thinks.
  ///
  /// Sight tests are raycasts and they are the expensive part of this system.
  /// Something twenty-five metres away deciding four times a second instead of
  /// sixty is invisible; the plan budgeted thirty monsters, and without this
  /// that is thirty rays every step.
  static const int distantInterval = 4;

  /// Beyond this, a monster is on the slow schedule.
  static const double distantRange = 18.0;

  int _tick = 0;

  /// Damage the player took this step, from anything that reached them.
  double playerDamageThisStep = 0.0;

  /// Monsters that died this step, for effects and the kill counter.
  final List<Monster> died = <Monster>[];

  /// Monsters that took damage this step and survived it.
  ///
  /// The counterpart to [died], and it was missing: a pain sound was declared,
  /// preloaded and **never played**, because nothing anywhere could tell that a
  /// monster had been hit. The caller knew it had fired and the system knew
  /// what it had hit, and between them the fact went nowhere.
  ///
  /// A list cleared at the top of [step], like [died], rather than a stream: a
  /// `Stream` delivers after the step that produced it, which breaks the one
  /// property this package exists to protect, and allocates a subscription and
  /// an event per hit sixty times a second.
  final List<MonsterHurt> hurtThisStep = <MonsterHurt>[];

  Monster spawn(MonsterDef def, Vector3 position, {double yaw = 0.0}) {
    final monster = Monster(
      def: def,
      world: world,
      position: position,
      yaw: yaw,
    );
    monster.onDamage = (double amount) => hurt(monster, amount);
    monsters.add(monster);
    return monster;
  }

  int get aliveCount {
    var count = 0;
    for (final monster in monsters) {
      if (monster.isAlive) count++;
    }
    return count;
  }

  // Scratch, because this runs sixty times a second over thirty monsters.
  final Vector3 _toPlayer = Vector3.zero();
  final Vector3 _wish = Vector3.zero();
  final Vector3 _eye = Vector3.zero();
  final Vector3 _aim = Vector3.zero();
  final RayHit _sight = RayHit();

  /// Advances every monster.
  ///
  /// [playerEye] is where the player's head is, which is both what a monster
  /// aims at and what it needs a clear line to.
  void step(
    double dt, {
    required Vector3 playerEye,
    required Collider playerCollider,
  }) {
    _tick++;
    playerDamageThisStep = 0.0;
    died.clear();
    hurtThisStep.clear();

    for (final monster in monsters) {
      if (monster.state == MonsterState.dead) {
        // A corpse still needs its body stepped, or it hangs in the air where
        // it died.
        monster.body.step(dt, wishDirection: Vector3.zero());
        monster.stateTime += dt;
        continue;
      }

      monster.stateTime += dt;
      monster.attackCooldown = math.max(0.0, monster.attackCooldown - dt);
      monster.painCooldown = math.max(0.0, monster.painCooldown - dt);

      _toPlayer
        ..setFrom(playerEye)
        ..sub(monster.position);
      final distance = _toPlayer.length;

      // Thinking is throttled; moving is not. A monster whose movement ran
      // every fourth step would visibly stutter.
      final thinks = distance < distantRange ||
          (_tick + monster.hashCode) % distantInterval == 0;
      if (thinks) {
        _think(monster, playerEye, playerCollider, distance);
      }

      _act(monster, dt, distance);
    }
  }

  void _think(
    Monster monster,
    Vector3 playerEye,
    Collider playerCollider,
    double distance,
  ) {
    switch (monster.state) {
      case MonsterState.dead:
      case MonsterState.hurt:
        // Staggered, and not making decisions.
        return;

      case MonsterState.idle:
        if (distance <= monster.def.sightRange &&
            _canSee(monster, playerEye, playerCollider)) {
          _enter(monster, MonsterState.alert);
        }

      case MonsterState.alert:
        if (monster.stateTime >= monster.def.alertDuration) {
          _enter(monster, MonsterState.chase);
        }

      case MonsterState.chase:
        if (distance <= monster.def.attack.range &&
            _canSee(monster, playerEye, playerCollider)) {
          _enter(monster, MonsterState.attack);
        }

      case MonsterState.attack:
        // Left as soon as the player is out of reach, so a monster does not
        // stand swinging at nothing.
        if (distance > monster.def.attack.range * 1.15) {
          _enter(monster, MonsterState.chase);
        }
    }
  }

  void _act(Monster monster, double dt, double distance) {
    _wish.setZero();

    switch (monster.state) {
      case MonsterState.idle:
      case MonsterState.dead:
        break;

      case MonsterState.hurt:
        if (monster.stateTime >= monster.def.hurtDuration) {
          _enter(monster, MonsterState.chase);
        }

      case MonsterState.alert:
        _turnTowards(monster, dt);

      case MonsterState.chase:
        _turnTowards(monster, dt);
        // Straight at the player, horizontally. The controller does the
        // sliding, which is what keeps a corner from being a wall.
        _wish.setValues(_toPlayer.x, 0.0, _toPlayer.z);
        if (_wish.length2 > 1e-6) _wish.normalize();

      case MonsterState.attack:
        _turnTowards(monster, dt);
        if (monster.attackCooldown <= 0.0) _attack(monster);
    }

    monster.body.step(dt, wishDirection: _wish);
  }

  void _attack(Monster monster) {
    final weapon = monster.def.attack;
    monster.attackCooldown = weapon.cooldownSeconds;

    monster.eyeLevel(_eye);
    _aim
      ..setFrom(_toPlayer)
      ..y = 0.0;
    if (_aim.length2 < 1e-6) return;
    _aim.normalize();
    // Aim slightly up at the player's head rather than dead level, or a
    // fireball launched from chest height sails under them on a slope.
    _aim.y = (_toPlayer.y * 0.15).clamp(-0.4, 0.4);
    _aim.normalize();

    _shot.begin(weapon, _eye, _aim, shooter: monster.body.collider);
    weapon.behaviour.deliver(_shot);

    // A melee swing lands immediately and reports what it reached; a projectile
    // reports nothing and arrives later, through the projectile system.
    for (final hit in _shot.hits) {
      if (hit.collider?.layer == CollisionLayers.player) {
        playerDamageThisStep += hit.damage;
      }
    }
  }

  /// Applies damage from the outside — a shot, a blast, a crushing lift.
  ///
  /// Returns true if this killed it. Staggering is probabilistic: something
  /// that flinches at every pellet can be held in place by a shotgun and never
  /// reaches the player, which turns the hardest enemy into the easiest.
  bool hurt(Monster monster, double amount) {
    if (!monster.isAlive) return false;

    final killed = monster.health.damage(amount);
    if (killed) {
      _enter(monster, MonsterState.dead);
      // A corpse stops being an obstacle: walking into the bodies of everything
      // you have killed turns a corridor into a maze of your own making.
      monster.body.collider.kind = ColliderKind.trigger;
      died.add(monster);
      return true;
    }

    hurtThisStep.add(MonsterHurt(monster, amount));

    // Being shot is how a monster notices someone it could not see.
    monster.hasNoticed = true;
    if (monster.state == MonsterState.idle) {
      _enter(monster, MonsterState.chase);
    }
    if (monster.painCooldown <= 0.0 &&
        monster.state != MonsterState.hurt &&
        _random.nextDouble() < monster.def.painChance) {
      _enter(monster, MonsterState.hurt);
      monster.painCooldown = monster.def.hurtDuration + monster.def.painCooldown;
      // Recorded after the roll, so a caller can tell a monster that flinched
      // from one that took the hit and kept coming — which is the difference
      // between a grunt and a scream.
      hurtThisStep.last.staggered = true;
    }
    return false;
  }

  void _enter(Monster monster, MonsterState state) {
    if (monster.state == state) return;
    monster.state = state;
    monster.stateTime = 0.0;
    if (state == MonsterState.alert || state == MonsterState.chase) {
      monster.hasNoticed = true;
    }
  }

  void _turnTowards(Monster monster, double dt) {
    if (_toPlayer.x == 0.0 && _toPlayer.z == 0.0) return;
    final wanted = math.atan2(-_toPlayer.x, -_toPlayer.z);
    final delta = _shortestAngle(monster.yaw, wanted);
    final step = monster.def.turnRate * dt;
    monster.yaw += delta.abs() <= step ? delta : (delta.isNegative ? -step : step);
  }

  static double _shortestAngle(double from, double to) {
    const twoPi = 2.0 * math.pi;
    var delta = (to - from) % twoPi;
    if (delta > math.pi) {
      delta -= twoPi;
    } else if (delta < -math.pi) {
      delta += twoPi;
    }
    return delta;
  }

  /// Whether the monster has a clear line to the player.
  ///
  /// Against the world only. A ray that stopped on another monster would mean a
  /// crowd blinds itself, and monsters standing in a doorway would each wait
  /// for the others to move.
  bool _canSee(Monster monster, Vector3 playerEye, Collider playerCollider) {
    monster.eyeLevel(_eye);
    _aim
      ..setFrom(playerEye)
      ..sub(_eye);
    final distance = _aim.length;
    if (distance < 1e-4) return true;
    _aim.scale(1.0 / distance);

    if (!world.raycast(
      _eye,
      _aim,
      distance,
      _sight,
      mask: CollisionLayers.world,
      ignore: monster.body.collider,
    )) {
      return true;
    }
    // Touching the wall the player stands against is not the same as being
    // behind it.
    return _sight.distance >= distance - 0.05;
  }
}

/// One monster taking damage and surviving it.
///
/// A record of a moment rather than a state: the monster is still there to be
/// asked about its health, and what a caller wants from this is the *event* —
/// a sound to play, a mark on the crosshair, a number floating up.
final class MonsterHurt {
  MonsterHurt(this.monster, this.amount);

  final Monster monster;

  /// How much it took, before armour if it had any.
  final double amount;

  /// Whether the hit made it flinch, which is a roll rather than a certainty.
  ///
  /// The difference between a grunt and a scream, and the reason this is a
  /// record and not just the monster: by the time a caller looks, the state
  /// machine has already moved on.
  bool staggered = false;
}
