import 'dart:math' as math;

import 'package:flutter3d_game/src/actors/damageable.dart';
import 'package:flutter3d_game/src/actors/health.dart';
import 'package:flutter3d_game/src/actors/player.dart';
import 'package:flutter3d_game/src/world/key_ring.dart';

import 'package:flutter3d_game/src/actors/actor.dart';
import 'package:flutter3d_game/src/actors/actor_system.dart';
import 'package:flutter3d_game/shooter.dart';
import 'package:flutter3d_game/src/combat/hitscan.dart';
import 'package:flutter3d_game/src/combat/projectile.dart';
import 'package:flutter3d_game/src/combat/weapon_behaviour.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:flutter3d_game/src/physics/layers.dart';
import 'package:flutter3d_game/sample.dart';

/// What an actor is doing, for a game whose actors are monsters.
///
/// The engine hands back an `Actor`; the six states are a `ChaseBrain`'s, and
/// reading them means saying which game this is. That is the seam working.
ChaseBrain _mind(Actor actor) => actor.brain as ChaseBrain;

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

/// A system with this game's bestiary attached.
///
/// The engine builds actors; what makes one of them a monster is a `ChaseBrain`
/// and a `MonsterDef`, and both of those live in `shooter.dart` now. That is
/// what this helper says out loud.
({ActorSystem system, Bestiary bestiary, Collider player, Vector3 eye}) _harness(
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
  final random = math.Random(seed);
  final system = ActorSystem(world: world, random: random);
  return (
    system: system,
    bestiary: Bestiary(
      actors: system,
      shot: WeaponShot(
        world: world,
        hitscan: Hitscan(world: world, random: random),
        projectiles: ProjectileSystem(world: world),
      ),
      catalog: Monsters.byName,
    ),
    player: player,
    eye: (playerAt ?? Vector3.zero()) + Vector3(0.0, 0.7, 0.0),
  );
}

void main() {
  _damageableTests();

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
      final monster = h.bestiary.spawn(Monsters.runner, Vector3(0.0, 0.9, -8.0));

      h.system.step(_dt, focus: h.eye, focusBody: h.player);

      expect(_mind(monster).state, MonsterState.alert);
    });

    test('a wall in the way keeps it asleep', () {
      // The failure this exists for: monsters charging through geometry at a
      // player they cannot possibly have seen.
      final world = _room(wall: true);
      final h = _harness(world);
      final monster = h.bestiary.spawn(Monsters.runner, Vector3(0.0, 0.9, -8.0));

      for (var i = 0; i < 60; i++) {
        h.system.step(_dt, focus: h.eye, focusBody: h.player);
      }

      expect(_mind(monster).state, MonsterState.idle);
    });

    test('something too far away is not noticed', () {
      final world = _room();
      final h = _harness(world);
      final monster = h.bestiary.spawn(Monsters.runner, Vector3(0.0, 0.9, -40.0));

      for (var i = 0; i < 30; i++) {
        h.system.step(_dt, focus: h.eye, focusBody: h.player);
      }

      expect(_mind(monster).state, MonsterState.idle);
    });

    test('being shot wakes it even with no line of sight', () {
      // Otherwise a player can whittle down a monster round a corner and it
      // never reacts, which reads as the game being broken rather than as an
      // ambush.
      final world = _room(wall: true);
      final h = _harness(world);
      final monster = h.bestiary.spawn(Monsters.runner, Vector3(0.0, 0.9, -8.0));

      h.system.hurt(monster, 5.0);

      expect(_mind(monster).hasNoticed, isTrue);
      expect(_mind(monster).state, isNot(MonsterState.idle));
    });

    test('it hesitates before charging', () {
      // A monster that snaps into a sprint the instant it sees you reads as a
      // turret.
      final world = _room();
      final h = _harness(world);
      final monster = h.bestiary.spawn(Monsters.runner, Vector3(0.0, 0.9, -8.0));

      h.system.step(_dt, focus: h.eye, focusBody: h.player);
      expect(_mind(monster).state, MonsterState.alert);

      for (var i = 0; i < 30; i++) {
        h.system.step(_dt, focus: h.eye, focusBody: h.player);
      }
      expect(_mind(monster).state, MonsterState.chase);
    });
  });

  group('chasing', () {
    test('it closes the distance', () {
      final world = _room();
      final h = _harness(world);
      final monster = h.bestiary.spawn(Monsters.runner, Vector3(0.0, 0.9, -12.0));

      final before = monster.position.z;
      for (var i = 0; i < 120; i++) {
        h.system.step(_dt, focus: h.eye, focusBody: h.player);
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
      final monster = h.bestiary.spawn(Monsters.runner, Vector3(-3.0, 0.9, -10.0));
      h.system.hurt(monster, 1.0);

      final startX = monster.position.x;
      var furthest = 0.0;
      for (var i = 0; i < 180; i++) {
        h.system.step(_dt, focus: h.eye, focusBody: h.player);
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
      final monster = h.bestiary.spawn(Monsters.runner, Vector3(0.0, 0.9, -1.5));

      for (var i = 0; i < 40; i++) {
        h.system.step(_dt, focus: h.eye, focusBody: h.player);
      }
      expect(_mind(monster).state, MonsterState.attack);

      // The player runs away.
      final farEye = Vector3(0.0, 0.7, 20.0);
      for (var i = 0; i < 10; i++) {
        h.system.step(_dt, focus: farEye, focusBody: h.player);
      }

      expect(_mind(monster).state, MonsterState.chase);
    });
  });

  group('attacking', () {
    test('a runner in reach hurts the player', () {
      final world = _room();
      final h = _harness(world);
      h.bestiary.spawn(Monsters.runner, Vector3(0.0, 0.9, -1.4));

      var total = 0.0;
      for (var i = 0; i < 120; i++) {
        h.system.step(_dt, focus: h.eye, focusBody: h.player);
        total += h.system.damageToFocusThisStep;
      }

      expect(total, greaterThan(0.0));
    });

    test('out of reach it does nothing', () {
      final world = _room();
      final h = _harness(world);
      h.bestiary.spawn(Monsters.runner, Vector3(0.0, 0.9, -10.0));

      var total = 0.0;
      for (var i = 0; i < 40; i++) {
        h.system.step(_dt, focus: h.eye, focusBody: h.player);
        total += h.system.damageToFocusThisStep;
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
      final random = math.Random(1);
      final system = ActorSystem(world: world, random: random);
      Bestiary(
        actors: system,
        shot: WeaponShot(
          world: world,
          hitscan: Hitscan(world: world, random: random),
          projectiles: projectiles,
        ),
        catalog: Monsters.byName,
      ).spawn(Monsters.shooter, Vector3(0.0, 0.9, -12.0));

      final eye = Vector3(0.0, 0.7, 0.0);
      for (var i = 0; i < 180; i++) {
        system.step(_dt, focus: eye, focusBody: player);
      }

      expect(projectiles.activeCount + projectiles.detonations.length,
          greaterThan(0));
    });

    test('the rate of attack does not depend on the frame rate', () {
      double damageOver(double seconds, double step) {
        final world = _room();
        final h = _harness(world);
        h.bestiary.spawn(Monsters.runner, Vector3(0.0, 0.9, -1.4));
        var total = 0.0;
        for (var t = 0.0; t < seconds; t += step) {
          h.system.step(step, focus: h.eye, focusBody: h.player);
          total += h.system.damageToFocusThisStep;
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
      final monster = h.bestiary.spawn(Monsters.runner, Vector3(0.0, 0.9, -4.0));

      expect(h.system.hurt(monster, 1000.0), isTrue);
      expect(h.system.hurt(monster, 1000.0), isFalse);
      expect(h.system.died, hasLength(1));
    });

    test('a corpse stops blocking the corridor', () {
      final world = _room();
      final h = _harness(world);
      final monster = h.bestiary.spawn(Monsters.runner, Vector3(0.0, 0.9, -4.0));
      h.system.hurt(monster, 1000.0);

      expect(monster.body.collider.isSolid, isFalse);
    });

    test('a corpse stops thinking and stops attacking', () {
      final world = _room();
      final h = _harness(world);
      final monster = h.bestiary.spawn(Monsters.runner, Vector3(0.0, 0.9, -1.4));
      h.system.hurt(monster, 1000.0);

      var total = 0.0;
      for (var i = 0; i < 120; i++) {
        h.system.step(_dt, focus: h.eye, focusBody: h.player);
        total += h.system.damageToFocusThisStep;
      }

      expect(_mind(monster).state, MonsterState.dead);
      expect(total, 0.0);
    });

    test('the dead list covers one step only', () {
      final world = _room();
      final h = _harness(world);
      final monster = h.bestiary.spawn(Monsters.runner, Vector3(0.0, 0.9, -4.0));
      h.system.hurt(monster, 1000.0);

      expect(h.system.died, hasLength(1));
      h.system.step(_dt, focus: h.eye, focusBody: h.player);
      expect(h.system.died, isEmpty);
    });

    test('aliveCount falls as they die', () {
      final world = _room();
      final h = _harness(world);
      for (var i = 0; i < 5; i++) {
        h.bestiary.spawn(Monsters.runner, Vector3(i * 3.0, 0.9, -8.0));
      }

      expect(h.system.aliveCount, 5);
      h.system.hurt(h.system.actors.first, 1000.0);
      expect(h.system.aliveCount, 4);
    });
  });

  group('staggering', () {
    test('a heavy monster cannot be held in place by small hits', () {
      // Otherwise a shotgun stun-locks the hardest enemy in the game and it
      // never reaches the player, which makes it the easiest.
      final world = _room();
      final h = _harness(world, seed: 7);
      final tank = h.bestiary.spawn(Monsters.tank, Vector3(0.0, 0.9, -10.0));
      h.system.hurt(tank, 1.0);

      var staggeredSteps = 0;
      for (var i = 0; i < 240; i++) {
        h.system.hurt(tank, 1.0);
        h.system.step(_dt, focus: h.eye, focusBody: h.player);
        if (_mind(tank).state == MonsterState.hurt) staggeredSteps++;
      }

      // It spent most of the time doing something other than flinching.
      expect(staggeredSteps, lessThan(120));
      expect(tank.position.z, greaterThan(-10.0 + 1.0));
    });

    test('a light monster does flinch', () {
      final world = _room();
      final h = _harness(world, seed: 3);
      final runner = h.bestiary.spawn(Monsters.runner, Vector3(0.0, 0.9, -8.0));

      h.system.hurt(runner, 1.0);

      expect(_mind(runner).state, MonsterState.hurt);
    });
  });

  group('the thinking budget', () {
    test('a crowd far away still eventually notices', () {
      // Distant monsters think every fourth step; the throttle must delay the
      // decision, not lose it.
      final world = _room();
      final h = _harness(world);
      final monster = h.bestiary.spawn(Monsters.shooter, Vector3(0.0, 0.9, -25.0));

      for (var i = 0; i < 40; i++) {
        h.system.step(_dt, focus: h.eye, focusBody: h.player);
      }

      expect(_mind(monster).state, isNot(MonsterState.idle));
    });

    test('thirty monsters step without complaint', () {
      final world = _room();
      final h = _harness(world);
      for (var i = 0; i < 30; i++) {
        h.bestiary.spawn(
          Monsters.runner,
          Vector3((i % 6) * 2.0 - 6.0, 0.9, -10.0 - (i ~/ 6) * 2.0),
        );
      }

      final watch = Stopwatch()..start();
      for (var i = 0; i < 300; i++) {
        h.system.step(_dt, focus: h.eye, focusBody: h.player);
      }
      watch.stop();

      expect(h.system.aliveCount, 30);
      // Five seconds of simulation for thirty monsters. Generous, and the point
      // is the order of magnitude rather than the figure.
      expect(watch.elapsedMilliseconds, lessThan(2000));
    });
  });
}

/// Damage through one interface, whatever is being hurt.
///
/// Two type-switches used to live in the application — one for hitscan, one for
/// a blast — and neither could have been written by a game with a third thing
/// worth shooting. What replaced them is one question: can this be hurt?
void _damageableTests() {
  group('damageable', () {
    test('a spawned monster takes damage the way its system would', () {
      // The assertion that matters. `applyDamage` must go back through the
      // system, not into `health` directly: a monster killed the short way
      // leaves a corpse that still blocks the corridor and a death nothing
      // counted.
      //
      // Mutation: make `applyDamage` call `health.damage`. Both of these fail.
      final world = CollisionWorld();
      final h = _harness(world);
      final monsters = h.system;
      final monster = h.bestiary.spawn(Monsters.runner, Vector3.zero());

      final died = (monster as Damageable).applyDamage(1000.0);

      expect(died, isTrue);
      expect(monsters.died, <Actor>[monster],
          reason: 'the kill never reached the system that owns it');
      expect(monster.body.collider.kind, ColliderKind.trigger,
          reason: 'the corpse still blocks the corridor');
    });

    test('surviving a hit is reported too', () {
      final world = CollisionWorld();
      final h = _harness(world);
      final monsters = h.system;
      final monster = h.bestiary.spawn(Monsters.tank, Vector3.zero());

      expect((monster as Damageable).applyDamage(1.0), isFalse);
      expect(monsters.hurtThisStep.single.actor, monster);
    });

    test('a monster nothing is running still takes the damage', () {
      // Built by hand, which is what a test does. There is no system to go
      // through and no state machine to run, so the health is the whole of it.
      final world = CollisionWorld();
      final monster = Actor(
        body: CharacterController(world: world, position: Vector3.zero()),
        health: Health(Monsters.runner.health),
        brain: ChaseBrain(
          def: Monsters.runner,
          shot: WeaponShot(
            world: world,
            hitscan: Hitscan(world: world),
            projectiles: ProjectileSystem(world: world),
          ),
        ),
      );

      expect((monster as Damageable).applyDamage(1000.0), isTrue);
      expect(monster.health.isAlive, isFalse);
    });

    test('a player is who their collider is, and can be hurt', () {
      // The other half of the untangling: `userData` used to hold the player's
      // *inventory*, which is what the body carries rather than who it is — so
      // a blast had to test the collider's layer instead of asking it.
      final world = CollisionWorld();
      final player = Player(
        body: CharacterController(world: world, position: Vector3.zero()),
      );

      final owner = player.body.collider.userData;
      expect(owner, same(player));
      expect(owner, isA<Damageable>());

      (owner! as Damageable).applyDamage(10.0);
      expect(player.inventory.health.current, lessThan(100.0));
    });

    test('and a locked door still finds the keys on them', () {
      // `MechanismWorld.activationBy` asks whether the collider's owner is a
      // `KeyHolder`. It used to find the inventory there, which was right by
      // accident; it now finds the player, who forwards.
      final world = CollisionWorld();
      final player = Player(
        body: CharacterController(world: world, position: Vector3.zero()),
      );
      player.inventory.keyRing.take('brass');

      final owner = player.body.collider.userData;
      expect(owner, isA<KeyHolder>());
      expect((owner! as KeyHolder).keys, contains('brass'));
    });
  });
}
