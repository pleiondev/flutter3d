import 'dart:math' as math;

import 'package:flutter3d_game/src/actors/health.dart';
import 'package:flutter3d_game/src/actors/monster.dart';
import 'package:flutter3d_game/src/actors/monster_system.dart';
import 'package:flutter3d_game/src/combat/projectile.dart';
import 'package:flutter3d_game/src/physics/collider.dart';
import 'package:flutter3d_game/src/physics/collision_shape.dart';
import 'package:flutter3d_game/src/physics/collision_world.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// A floor, and optionally a wall across the middle.
CollisionWorld _room({bool wall = false}) {
  final world = CollisionWorld();
  world.addBox(Vector3(0.0, -0.5, 0.0), Vector3(80.0, 1.0, 80.0));
  if (wall) {
    world.addBox(Vector3(0.0, 3.0, -5.0), Vector3(40.0, 6.0, 1.0));
  }
  return world;
}

({MonsterSystem system, Collider player, Vector3 eye}) _harness(
  CollisionWorld world, {
  Vector3? playerAt,
  int seed = 1,
}) {
  final player = world.add(
    Collider(
      shape: CollisionBox(Vector3(0.35, 0.9, 0.35)),
      position: playerAt ?? Vector3.zero(),
      kind: ColliderKind.kinematic,
      layer: CollisionLayers.player,
    ),
  );
  world.update();
  return (
    system: MonsterSystem(
      world: world,
      projectiles: ProjectileSystem(world: world),
      random: math.Random(seed),
    ),
    player: player,
    eye: (playerAt ?? Vector3.zero()) + Vector3(0.0, 0.7, 0.0),
  );
}

void main() {
  group('health', () {
    test('death is reported exactly once', () {
      // Eight shotgun pellets in one monster is one death. A health class that
      // reports the transition on every later hit produces eight death
      // animations, eight corpses and eight kills on the counter.
      final health = Health(30.0);

      expect(health.damage(40.0), isTrue);
      expect(health.damage(40.0), isFalse);
      expect(health.damage(40.0), isFalse);
    });

    test('damage accumulates towards one death', () {
      final health = Health(30.0);

      expect(health.damage(10.0), isFalse);
      expect(health.damage(10.0), isFalse);
      expect(health.damage(10.0), isTrue);
      expect(health.isDead, isTrue);
    });

    test('health never goes below zero', () {
      final health = Health(30.0)..damage(500.0);

      expect(health.current, 0.0);
    });

    test('armour absorbs its share and is spent', () {
      final health = Health(100.0, armour: 30.0);
      health.damage(30.0);

      // A third of the damage went to armour.
      expect(health.armour, closeTo(20.0, 1e-9));
      expect(health.current, closeTo(80.0, 1e-9));
    });

    test('armour runs out and stops helping', () {
      final health = Health(100.0, armour: 1.0);
      health.damage(90.0);

      expect(health.armour, 0.0);
      expect(health.current, closeTo(11.0, 1e-9));
    });

    test('healing stops at the maximum and says how much it gave', () {
      final health = Health(100.0, current: 90.0);

      expect(health.heal(25.0), closeTo(10.0, 1e-9));
      expect(health.heal(25.0), 0.0);
      expect(health.current, 100.0);
    });

    test('the dead take no more damage and cannot be healed', () {
      final health = Health(10.0)..damage(20.0);

      expect(health.damage(10.0), isFalse);
      expect(health.heal(50.0), 0.0);
      expect(health.isDead, isTrue);
    });

    test('reviving allows a second death', () {
      final health = Health(10.0)..damage(20.0);
      health.revive();

      expect(health.isAlive, isTrue);
      expect(health.damage(20.0), isTrue);
    });
  });

  group('noticing the player', () {
    test('a monster with a clear line takes notice', () {
      final world = _room();
      final h = _harness(world);
      final monster = h.system.spawn(Monsters.runner, Vector3(0.0, 0.9, -8.0));

      h.system.step(_dt, playerEye: h.eye, playerCollider: h.player);

      expect(monster.state, MonsterState.alert);
    });

    test('a wall in the way keeps it asleep', () {
      // The failure this exists for: monsters charging through geometry at a
      // player they cannot possibly have seen.
      final world = _room(wall: true);
      final h = _harness(world);
      final monster = h.system.spawn(Monsters.runner, Vector3(0.0, 0.9, -8.0));

      for (var i = 0; i < 60; i++) {
        h.system.step(_dt, playerEye: h.eye, playerCollider: h.player);
      }

      expect(monster.state, MonsterState.idle);
    });

    test('something too far away is not noticed', () {
      final world = _room();
      final h = _harness(world);
      final monster = h.system.spawn(Monsters.runner, Vector3(0.0, 0.9, -40.0));

      for (var i = 0; i < 30; i++) {
        h.system.step(_dt, playerEye: h.eye, playerCollider: h.player);
      }

      expect(monster.state, MonsterState.idle);
    });

    test('being shot wakes it even with no line of sight', () {
      // Otherwise a player can whittle down a monster round a corner and it
      // never reacts, which reads as the game being broken rather than as an
      // ambush.
      final world = _room(wall: true);
      final h = _harness(world);
      final monster = h.system.spawn(Monsters.runner, Vector3(0.0, 0.9, -8.0));

      h.system.hurt(monster, 5.0);

      expect(monster.hasNoticed, isTrue);
      expect(monster.state, isNot(MonsterState.idle));
    });

    test('it hesitates before charging', () {
      // A monster that snaps into a sprint the instant it sees you reads as a
      // turret.
      final world = _room();
      final h = _harness(world);
      final monster = h.system.spawn(Monsters.runner, Vector3(0.0, 0.9, -8.0));

      h.system.step(_dt, playerEye: h.eye, playerCollider: h.player);
      expect(monster.state, MonsterState.alert);

      for (var i = 0; i < 30; i++) {
        h.system.step(_dt, playerEye: h.eye, playerCollider: h.player);
      }
      expect(monster.state, MonsterState.chase);
    });
  });

  group('chasing', () {
    test('it closes the distance', () {
      final world = _room();
      final h = _harness(world);
      final monster = h.system.spawn(Monsters.runner, Vector3(0.0, 0.9, -12.0));

      final before = monster.position.z;
      for (var i = 0; i < 120; i++) {
        h.system.step(_dt, playerEye: h.eye, playerCollider: h.player);
      }

      expect(monster.position.z, greaterThan(before + 4.0));
    });

    test('a corner is slid along, not ground into', () {
      // No navmesh, so a monster will get stuck on geometry eventually. What it
      // must not do is stop dead against a wall it could walk along.
      final world = _room();
      // A short wall between the monster and the player, offset to one side so
      // sliding is possible round its end.
      world.addBox(Vector3(-3.0, 3.0, -6.0), Vector3(12.0, 6.0, 1.0));
      final h = _harness(world);
      final monster = h.system.spawn(Monsters.runner, Vector3(-3.0, 0.9, -10.0));
      h.system.hurt(monster, 1.0);

      final startX = monster.position.x;
      var furthest = 0.0;
      for (var i = 0; i < 180; i++) {
        h.system.step(_dt, playerEye: h.eye, playerCollider: h.player);
        furthest = math.max(furthest, (monster.position.x - startX).abs());
      }

      // The furthest it got, not where it ended up. With no navigation mesh it
      // slides to the player's side of the wall, overshoots and oscillates —
      // which the plan accepted. What it must not do is stop dead against a
      // surface it could walk along, and that is what this measures.
      expect(furthest, greaterThan(3.0));
    });

    test('it stops attacking when the player leaves its reach', () {
      final world = _room();
      final h = _harness(world);
      final monster = h.system.spawn(Monsters.runner, Vector3(0.0, 0.9, -1.5));

      for (var i = 0; i < 40; i++) {
        h.system.step(_dt, playerEye: h.eye, playerCollider: h.player);
      }
      expect(monster.state, MonsterState.attack);

      // The player runs away.
      final farEye = Vector3(0.0, 0.7, 20.0);
      for (var i = 0; i < 10; i++) {
        h.system.step(_dt, playerEye: farEye, playerCollider: h.player);
      }

      expect(monster.state, MonsterState.chase);
    });
  });

  group('attacking', () {
    test('a runner in reach hurts the player', () {
      final world = _room();
      final h = _harness(world);
      h.system.spawn(Monsters.runner, Vector3(0.0, 0.9, -1.4));

      var total = 0.0;
      for (var i = 0; i < 120; i++) {
        h.system.step(_dt, playerEye: h.eye, playerCollider: h.player);
        total += h.system.playerDamageThisStep;
      }

      expect(total, greaterThan(0.0));
    });

    test('out of reach it does nothing', () {
      final world = _room();
      final h = _harness(world);
      h.system.spawn(Monsters.runner, Vector3(0.0, 0.9, -10.0));

      var total = 0.0;
      for (var i = 0; i < 40; i++) {
        h.system.step(_dt, playerEye: h.eye, playerCollider: h.player);
        total += h.system.playerDamageThisStep;
      }

      expect(total, 0.0);
    });

    test('a shooter launches something rather than reaching', () {
      final world = _room();
      final player = world.add(
        Collider(
          shape: CollisionBox(Vector3(0.35, 0.9, 0.35)),
          position: Vector3.zero(),
          kind: ColliderKind.kinematic,
          layer: CollisionLayers.player,
        ),
      );
      world.update();
      final projectiles = ProjectileSystem(world: world);
      final system = MonsterSystem(
        world: world,
        projectiles: projectiles,
        random: math.Random(1),
      );
      system.spawn(Monsters.shooter, Vector3(0.0, 0.9, -12.0));

      final eye = Vector3(0.0, 0.7, 0.0);
      for (var i = 0; i < 180; i++) {
        system.step(_dt, playerEye: eye, playerCollider: player);
      }

      expect(projectiles.activeCount + projectiles.detonations.length,
          greaterThan(0));
    });

    test('the rate of attack does not depend on the frame rate', () {
      double damageOver(double seconds, double step) {
        final world = _room();
        final h = _harness(world);
        h.system.spawn(Monsters.runner, Vector3(0.0, 0.9, -1.4));
        var total = 0.0;
        for (var t = 0.0; t < seconds; t += step) {
          h.system.step(step, playerEye: h.eye, playerCollider: h.player);
          total += h.system.playerDamageThisStep;
        }
        return total;
      }

      final sixty = damageOver(6.0, _dt);
      final thirty = damageOver(6.0, 1.0 / 30.0);

      expect(thirty, closeTo(sixty, Monsters.runner.attack.damage));
    });
  });

  group('dying', () {
    test('enough damage kills it, and only once', () {
      final world = _room();
      final h = _harness(world);
      final monster = h.system.spawn(Monsters.runner, Vector3(0.0, 0.9, -4.0));

      expect(h.system.hurt(monster, 1000.0), isTrue);
      expect(h.system.hurt(monster, 1000.0), isFalse);
      expect(h.system.died, hasLength(1));
    });

    test('a corpse stops blocking the corridor', () {
      final world = _room();
      final h = _harness(world);
      final monster = h.system.spawn(Monsters.runner, Vector3(0.0, 0.9, -4.0));
      h.system.hurt(monster, 1000.0);

      expect(monster.body.collider.isSolid, isFalse);
    });

    test('a corpse stops thinking and stops attacking', () {
      final world = _room();
      final h = _harness(world);
      final monster = h.system.spawn(Monsters.runner, Vector3(0.0, 0.9, -1.4));
      h.system.hurt(monster, 1000.0);

      var total = 0.0;
      for (var i = 0; i < 120; i++) {
        h.system.step(_dt, playerEye: h.eye, playerCollider: h.player);
        total += h.system.playerDamageThisStep;
      }

      expect(monster.state, MonsterState.dead);
      expect(total, 0.0);
    });

    test('the dead list covers one step only', () {
      final world = _room();
      final h = _harness(world);
      final monster = h.system.spawn(Monsters.runner, Vector3(0.0, 0.9, -4.0));
      h.system.hurt(monster, 1000.0);

      expect(h.system.died, hasLength(1));
      h.system.step(_dt, playerEye: h.eye, playerCollider: h.player);
      expect(h.system.died, isEmpty);
    });

    test('aliveCount falls as they die', () {
      final world = _room();
      final h = _harness(world);
      for (var i = 0; i < 5; i++) {
        h.system.spawn(Monsters.runner, Vector3(i * 3.0, 0.9, -8.0));
      }

      expect(h.system.aliveCount, 5);
      h.system.hurt(h.system.monsters.first, 1000.0);
      expect(h.system.aliveCount, 4);
    });
  });

  group('staggering', () {
    test('a heavy monster cannot be held in place by small hits', () {
      // Otherwise a shotgun stun-locks the hardest enemy in the game and it
      // never reaches the player, which makes it the easiest.
      final world = _room();
      final h = _harness(world, seed: 7);
      final tank = h.system.spawn(Monsters.tank, Vector3(0.0, 0.9, -10.0));
      h.system.hurt(tank, 1.0);

      var staggeredSteps = 0;
      for (var i = 0; i < 240; i++) {
        h.system.hurt(tank, 1.0);
        h.system.step(_dt, playerEye: h.eye, playerCollider: h.player);
        if (tank.state == MonsterState.hurt) staggeredSteps++;
      }

      // It spent most of the time doing something other than flinching.
      expect(staggeredSteps, lessThan(120));
      expect(tank.position.z, greaterThan(-10.0 + 1.0));
    });

    test('a light monster does flinch', () {
      final world = _room();
      final h = _harness(world, seed: 3);
      final runner = h.system.spawn(Monsters.runner, Vector3(0.0, 0.9, -8.0));

      h.system.hurt(runner, 1.0);

      expect(runner.state, MonsterState.hurt);
    });
  });

  group('the thinking budget', () {
    test('a crowd far away still eventually notices', () {
      // Distant monsters think every fourth step; the throttle must delay the
      // decision, not lose it.
      final world = _room();
      final h = _harness(world);
      final monster = h.system.spawn(Monsters.shooter, Vector3(0.0, 0.9, -25.0));

      for (var i = 0; i < 40; i++) {
        h.system.step(_dt, playerEye: h.eye, playerCollider: h.player);
      }

      expect(monster.state, isNot(MonsterState.idle));
    });

    test('thirty monsters step without complaint', () {
      final world = _room();
      final h = _harness(world);
      for (var i = 0; i < 30; i++) {
        h.system.spawn(
          Monsters.runner,
          Vector3((i % 6) * 2.0 - 6.0, 0.9, -10.0 - (i ~/ 6) * 2.0),
        );
      }

      final watch = Stopwatch()..start();
      for (var i = 0; i < 300; i++) {
        h.system.step(_dt, playerEye: h.eye, playerCollider: h.player);
      }
      watch.stop();

      expect(h.system.aliveCount, 30);
      // Five seconds of simulation for thirty monsters. Generous, and the point
      // is the order of magnitude rather than the figure.
      expect(watch.elapsedMilliseconds, lessThan(2000));
    });
  });
}
