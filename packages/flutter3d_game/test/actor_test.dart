/// The engine's half of what used to be `Monster`.
///
/// The claim this file exists to check is that the split is real: an actor
/// driven by a brain that has never heard of chasing, attacking, alertness or
/// flinching works, and works through the same system the shooter's monsters
/// use. If that were not true the split would be a rename.
library;

import 'dart:math' as math;

import 'package:flutter3d_game/src/actors/actor.dart';
import 'package:flutter3d_game/src/actors/actor_components.dart';
import 'package:flutter3d_game/src/actors/actor_system.dart';
import 'package:flutter3d_game/src/actors/brain.dart';
import 'package:flutter3d_game/src/actors/damageable.dart';
import 'package:flutter3d_game/src/actors/health.dart';
import 'package:flutter3d_game/src/save/game_random.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

CollisionWorld _ground() {
  final world = CollisionWorld();
  world.addBox(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0));
  world.update();
  return world;
}

/// Walks east until it has gone far enough, then west, and repeats.
///
/// **A platformer's enemy, near enough.** Fourteen lines, no states shared with
/// the shooter, no weapon, no line of sight, and nothing it overrides that it
/// does not use. Everything else it needs — a body that walks and slides, a
/// turn rate, health that can run out, a place in a save file — comes from the
/// engine.
final class _Patrol extends Brain {
  _Patrol({required this.from, required this.to});

  final double from;
  final double to;
  bool eastward = true;

  @override
  void act(Mind it) {
    final x = it.actor.position!.x;
    if (eastward && x >= to) eastward = false;
    if (!eastward && x <= from) eastward = true;
    final heading = eastward ? 1.0 : -1.0;
    it.steer(Vector3(heading, 0.0, 0.0));
    it.turnTowards(heading, 0.0);
  }

  @override
  Map<String, Object?> save() => <String, Object?>{'eastward': eastward};

  @override
  void restore(Map<String, Object?> from) => eastward = from['eastward'] == true;
}

Actor _walker(ActorSystem system, {double at = 0.0}) => system.spawn(
      body: CharacterController(
        world: system.world,
        position: Vector3(at, 0.9, 0.0),
      ),
      health: Health(30.0),
      brain: _Patrol(from: -4.0, to: 4.0),
      facing: Facing(),
    );

/// A brain with no body, which is a perfectly good thing to be.
final class _Counting extends Brain {
  _Counting(this.onAct);
  final void Function() onAct;
  @override
  void act(Mind it) => onAct();
}

/// A brain that only remembers what it heard.
final class _Listening extends Brain {
  final List<Vector3> heard = <Vector3>[];

  @override
  void onNoise(Mind it, Vector3 at) => heard.add(at.clone());
}

/// Something a game might care about and this package has never heard of.
final class _Suspicion {
  _Suspicion(this.level);
  final double level;
}

void main() {
  test('a death is still news after the step it happened in', () {
    // **The bug this method exists to prevent.** These lists used to be cleared
    // at the top of `ActorSystem.step`, which is halfway through a game's step
    // — and in the shooter the player's own shot is fired *before* the actors
    // think. So a monster the player killed was added to `died` and wiped again
    // in the same step, and everything downstream read an empty list: no death
    // sound, no sparks, nothing counted. The monster was dead and the news
    // never left the building.
    final world = _ground();
    final system = ActorSystem(world: world, random: GameRandom(1));
    final actor = system.spawn(
      body: CharacterController(world: world, position: Vector3(0.0, 0.9, 0.0)),
      health: Health(10.0),
    );

    system.beginStep();
    // Killed part-way through the game's step, as a shot does it.
    actor.applyDamage(50.0);
    system.step(1 / 60.0, focus: Vector3(0.0, 0.9, 20.0));

    expect(system.died, hasLength(1),
        reason: 'the death was forgotten inside the step it happened in');
  });

  test('and is forgotten when the next step begins', () {
    final world = _ground();
    final system = ActorSystem(world: world, random: GameRandom(1));
    final actor = system.spawn(
      body: CharacterController(world: world, position: Vector3(0.0, 0.9, 0.0)),
      health: Health(10.0),
    );

    system.beginStep();
    actor.applyDamage(50.0);
    system.step(1 / 60.0, focus: Vector3.zero());
    expect(system.died, hasLength(1));

    system.beginStep();

    expect(system.died, isEmpty, reason: 'it would be reported twice');
  });

  test('stepping without beginning says so in every build', () {
    // **A protocol between two objects, not an invariant of one**, and that is
    // why it throws rather than asserts. A game that forgets `beginStep` grows
    // its dead and hurt lists for ever and keeps adding to its damage counter:
    // a slow leak and a wrong number rather than a crash, found six months
    // later. An `assert` says that in debug and says nothing in the build a
    // player runs — which is the build where six months happen.
    final world = CollisionWorld();
    final system = ActorSystem(world: world, random: GameRandom(1))
      ..spawn(
        body: CharacterController(world: world, position: Vector3(0.0, 0.9, 0.0)),
        health: Health(10.0),
      );

    expect(
      () => system.step(1 / 60.0, focus: Vector3.zero()),
      throwsA(isA<StateError>()),
    );
  });

  test('and beginning it once is enough for one step and not two', () {
    // The other half: the flag is consumed, so a second step without a second
    // beginning is the same mistake and is caught the same way.
    final world = CollisionWorld();
    final system = ActorSystem(world: world, random: GameRandom(1))
      ..spawn(
        body: CharacterController(world: world, position: Vector3(0.0, 0.9, 0.0)),
        health: Health(10.0),
      );

    system.beginStep();
    system.step(1 / 60.0, focus: Vector3.zero());

    expect(
      () => system.step(1 / 60.0, focus: Vector3.zero()),
      throwsA(isA<StateError>()),
    );
  });

  test('an actor turns the short way round the wrap point', () {
    // **Nothing checked this, and the extraction is what found it.** Replacing
    // the shared `shortestAngle` with a plain subtraction left every test in
    // this package and in both genre packages passing, while an actor asked to
    // face a hair the other side of south turns almost the whole way round —
    // once, visibly, in front of whoever is watching.
    final world = _ground();
    final system = ActorSystem(world: world, random: GameRandom(1));
    final actor = system.spawn(
      body: CharacterController(world: world, position: Vector3(0.0, 0.9, 0.0)),
      health: Health(10.0),
      facing: Facing(yaw: math.pi - 0.05, turnRate: 100.0),
    );

    // A heading a hair the other side of the wrap point. The sign is the one
    // `turnTowards` takes: it faces *away* from the direction handed to it, so
    // this asks for a yaw of -pi + 0.05.
    system.turnTowards(actor, -math.sin(-math.pi + 0.05), -math.cos(-math.pi + 0.05), 1 / 60.0);

    final moved = (actor.yaw - (math.pi - 0.05)).abs();
    expect(moved, lessThan(0.5),
        reason: 'it went the long way round: yaw ${actor.yaw}');
  });

  group('an actor with a brain that is not a monster', () {
    test('walks its patrol, turns round, and comes back', () {
      final world = _ground();
      final system = ActorSystem(world: world, random: GameRandom(1));
      _walker(system);
      final walker = system.actors.single;
      final nowhere = Vector3(0.0, 100.0, 0.0);

      var east = walker.position!.x;
      var west = walker.position!.x;
      for (var i = 0; i < 400; i++) {
        system.beginStep();
        system.step(_dt, focus: nowhere);
        if (walker.position!.x > east) east = walker.position!.x;
        if (walker.position!.x < west) west = walker.position!.x;
      }

      // Both ends, rather than "which way is it going at step four hundred",
      // which is a question about the arithmetic of the test rather than about
      // the actor: it walks the eight metres in under three seconds and the
      // answer flips twice inside the loop.
      expect(east, greaterThan(3.9), reason: 'never reached the east end');
      expect(west, lessThan(-3.9), reason: 'never came back to the west end');
    });

    test('faces the way it is walking', () {
      final world = _ground();
      final system = ActorSystem(world: world, random: GameRandom(1));
      _walker(system);
      // Twenty steps: long enough to have come round at six radians a second,
      // short enough that it has not reached the end of its patrol and turned
      // back — which it does in about forty.
      for (var i = 0; i < 20; i++) {
        system.beginStep();
        system.step(_dt, focus: Vector3(0.0, 100.0, 0.0));
      }
      // Forward is −Z at yaw zero, so facing +X is a quarter turn.
      expect(system.actors.single.yaw, closeTo(-1.5708, 0.05));
    });

    test('is hurt, dies, and stops being an obstacle — with no brain for it',
        () {
      // `onHurt` and `onDeath` are not overridden by `_Patrol`. Everything here
      // is the engine's, which is what makes it available to every game.
      final world = _ground();
      final system = ActorSystem(world: world, random: GameRandom(1));
      final walker = _walker(system);

      expect(system.hurt(walker, 10.0), isFalse);
      expect(system.hurtThisStep.single.actor, same(walker));
      expect(system.hurtThisStep.single.staggered, isFalse,
          reason: 'nothing rolled a flinch, because nothing here has one');

      expect(system.hurt(walker, 100.0), isTrue);
      expect(system.died, <Actor>[walker]);
      expect(walker.body!.collider.kind, ColliderKind.trigger);
      expect(system.aliveCount, 0);
    });

    test('damage routed through the collider reaches the system', () {
      // The `Damageable` path: a rocket asks whoever it hit to take damage and
      // never learns what they are.
      final world = _ground();
      final system = ActorSystem(world: world, random: GameRandom(1));
      final walker = _walker(system);

      final owner = walker.body!.collider.userData;
      expect(owner, same(walker));
      expect((owner! as Damageable).applyDamage(1000.0), isTrue);
      expect(system.died, hasLength(1),
          reason: 'the kill never reached the system that owns it');
    });

    test('a brain saves and restores itself with the actor', () {
      // The engine writes body, health and yaw; what the brain remembers is the
      // brain's, and nothing in `Actor.save` knows what it is.
      final world = _ground();
      final system = ActorSystem(world: world, random: GameRandom(1));
      _walker(system);
      final walker = system.actors.single;

      // Far enough to have turned round at least once, so the flag is not
      // simply its initial value.
      for (var i = 0; i < 100; i++) {
        system.beginStep();
        system.step(_dt, focus: Vector3(0.0, 100.0, 0.0));
      }
      final wasHeading = (walker.brain! as _Patrol).eastward;
      expect(wasHeading, isFalse, reason: 'it should have turned by now');

      // Through the entity world, which is what actually writes an actor down
      // now: the brain's memory is a component and nothing in between knows
      // what a patrol is.
      final saved = system.entities.save();
      (walker.brain! as _Patrol).eastward = !wasHeading;
      system.entities.restore(saved);
      expect((walker.brain! as _Patrol).eastward, wasHeading);
    });

    test('a corpse still falls', () {
      // It was a comment in the old system and it is still true of anything:
      // stop stepping a dead body and it hangs in the air where it died.
      final world = _ground();
      final system = ActorSystem(world: world, random: GameRandom(1));
      final walker = system.spawn(
        body: CharacterController(
          world: world,
          position: Vector3(0.0, 6.0, 0.0),
        ),
        health: Health(10.0),
        brain: _Patrol(from: -1.0, to: 1.0),
      );
      system.hurt(walker, 100.0);

      for (var i = 0; i < 120; i++) {
        system.beginStep();
        system.step(_dt, focus: Vector3(0.0, 100.0, 0.0));
      }
      expect(walker.position!.y, closeTo(0.9, 0.1));
    });
  });

  group('an actor with only what it needs', () {
    test('a barrel: health, and nothing else at all', () {
      // No body, no brain, no facing. It used to be impossible to make: `spawn`
      // required all three, so a destructible crate came with a walking capsule
      // and a brain that did nothing.
      final system = ActorSystem(world: _ground(), random: GameRandom(1));
      final barrel = system.spawn(health: Health(20.0));

      expect(barrel.body, isNull);
      expect(barrel.brain, isNull);
      expect(barrel.facing, isNull);
      expect(barrel.position, isNull);

      expect(system.hurt(barrel, 5.0), isFalse);
      expect(system.hurtThisStep.single.actor, barrel);
      expect(system.hurt(barrel, 100.0), isTrue);
      expect(system.died, <Actor>[barrel]);

      // **A second death is not a death.** Found by mutating the guard at the
      // top of `hurt` to `return true` and watching the suite pass: a rocket
      // asks everything in its radius, and something already dead — or a lamp
      // post with no health at all — answering "yes, that killed it" is a
      // score counted twice and a corpse killed again.
      expect(system.hurt(barrel, 100.0), isFalse,
          reason: 'the dead were killed a second time');
      expect(system.died, <Actor>[barrel]);
      expect(system.hurt(system.spawn(), 100.0), isFalse,
          reason: 'something with no health reported a kill');

      // And it steps without complaint alongside everything else.
      system.beginStep();
      system.step(_dt, focus: Vector3.zero());
    });

    test('a lamp post: a body a rocket may ask, and no health to lose', () {
      final world = _ground();
      final system = ActorSystem(world: world, random: GameRandom(1));
      final post = system.spawn(
        body: CharacterController(world: world, position: Vector3(2.0, 0.9, 0.0)),
      );

      expect(post.isAlive, isTrue,
          reason: 'nothing to kill is not the same as dead');
      expect(post.applyDamage(1000.0), isFalse);
      expect(system.died, isEmpty);
      expect(post.body!.collider.kind, isNot(ColliderKind.trigger),
          reason: 'it was turned into a corpse, and it was never alive');
    });

    test('without a facing it does not turn, and nothing throws', () {
      final world = _ground();
      final system = ActorSystem(world: world, random: GameRandom(1));
      final drifter = system.spawn(
        body: CharacterController(world: world, position: Vector3.zero()),
        brain: _Patrol(from: -4.0, to: 4.0),
      );

      for (var i = 0; i < 60; i++) {
        system.beginStep();
        system.step(_dt, focus: Vector3(0.0, 100.0, 0.0));
      }
      expect(drifter.yaw, 0.0);
      expect(drifter.position!.x, greaterThan(1.0),
          reason: 'it should still walk; only the turning is missing');
    });

    test('a director: a brain and no body', () {
      // Something that decides and stands nowhere — a spawner, a level script.
      var thoughts = 0;
      final system = ActorSystem(world: _ground(), random: GameRandom(1));
      system.spawn(brain: _Counting(() => thoughts++));

      for (var i = 0; i < 10; i++) {
        system.beginStep();
        system.step(_dt, focus: Vector3.zero());
      }
      expect(thoughts, 10);
    });
  });

  group('writing an actor down', () {
    test('a game may put its own component on an actor', () {
      // The thing an actor being an entity actually buys, and the reason the
      // move happened at all: a stealth game adds `Suspicion`, a looter adds
      // `Drops`, and neither needs a subclass of anything or a second map
      // keyed by actor.
      final world = _ground();
      final system = ActorSystem(world: world, random: GameRandom(1));
      final walker = _walker(system);
      system.entities
        ..register<_Suspicion>(
          'suspicion',
          encode: (_Suspicion value) => value.level,
          decode: (Object? data) => _Suspicion((data! as num).toDouble()),
        )
        ..set(walker.entity, _Suspicion(0.75));

      final saved = system.entities.save();
      system.entities
        ..set(walker.entity, _Suspicion(0.0))
        ..restore(saved);

      expect(system.entities.get<_Suspicion>(walker.entity)!.level, 0.75);
    });

    test('a component nobody declared stops the save, naming itself', () {
      // The whole payoff, on an actor. `ActorSystem` used to write its own save
      // by walking its own list, and the next field anybody added to an actor
      // would have been left out of it in silence.
      final world = _ground();
      final system = ActorSystem(world: world, random: GameRandom(1));
      system.entities.set(_walker(system).entity, _Suspicion(0.5));

      expect(
        system.entities.save,
        throwsA(isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          contains('_Suspicion'),
        )),
      );
    });
  });

  group('the system', () {
    test('numbers actors as they are added, and not by their address', () {
      // The ordinal that replaced `hashCode`. Two identical runs must agree
      // about which actor thinks on which step.
      final world = _ground();
      final system = ActorSystem(world: world, random: GameRandom(1));
      for (var i = 0; i < 4; i++) {
        _walker(system, at: i.toDouble());
      }
      expect(
        <int>[for (final actor in system.actors) actor.ordinal],
        <int>[0, 1, 2, 3],
      );
    });

    test('the eye comes off the body, not off a definition', () {
      final world = _ground();
      final tall = ActorSystem(world: world, random: GameRandom(1)).spawn(
        body: CharacterController(
          world: world,
          shape: CollisionCapsule(radius: 0.3, halfHeight: 0.9),
          position: Vector3(0.0, 1.2, 0.0),
        ),
        health: Health(10.0),
        brain: _Patrol(from: 0.0, to: 1.0),
      );
      final eye = Vector3.zero();
      tall.eyeLevel(eye);
      expect(eye.y, greaterThan(tall.position!.y));
      expect(eye.y - tall.position!.y,
          closeTo(tall.body!.halfExtents.y * 0.32, 1e-6));
    });
  });

  group('hearing', () {
    // **The sense these actors did not have.** A brain reacted to being seen or
    // being hurt and to nothing else, so a fight in the next room was something
    // it stood through. What counts as loud and how far it carries is the
    // caller's; this layer knows only that something happened somewhere.
    ActorSystem quietRoom() {
      final world = CollisionWorld()
        ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(80.0, 1.0, 80.0));
      return ActorSystem(world: world, random: GameRandom(1));
    }

    Actor listener(ActorSystem system, {double at = 0.0}) => system.spawn(
          body: CharacterController(
            world: system.world,
            position: Vector3(at, 0.9, 0.0),
          ),
          health: Health(30.0),
          brain: _Listening(),
          facing: Facing(),
        );

    test('reaches everything inside the radius', () {
      final system = quietRoom();
      final near = listener(system, at: 3.0);

      system.hear(Vector3.zero(), radius: 10.0);

      expect((near.brain! as _Listening).heard, hasLength(1));
      expect((near.brain! as _Listening).heard.first, Vector3.zero());
    });

    test('and nothing outside it', () {
      // Mutation: drop the distance check. Every actor in the level wakes on
      // the first noise, which is a level with no pacing left in it.
      final system = quietRoom();
      final far = listener(system, at: 30.0);

      system.hear(Vector3.zero(), radius: 10.0);

      expect((far.brain! as _Listening).heard, isEmpty);
    });

    test('and the dead are not told', () {
      // A corpse that turns towards a noise is a corpse that gets back up as
      // far as anything reading its brain is concerned. Guarded here rather
      // than left to each brain: every brain would have to remember, and the
      // one that forgets is the one nobody looks at.
      final system = quietRoom();
      final dead = listener(system);
      system.hurt(dead, 999.0);
      expect(dead.isAlive, isFalse);

      system.hear(Vector3.zero(), radius: 10.0);

      expect((dead.brain! as _Listening).heard, isEmpty);
    });
  });
}