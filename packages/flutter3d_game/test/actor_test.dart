/// The engine's half of what used to be `Monster`.
///
/// The claim this file exists to check is that the split is real: an actor
/// driven by a brain that has never heard of chasing, attacking, alertness or
/// flinching works, and works through the same system the shooter's monsters
/// use. If that were not true the split would be a rename.
library;

import 'package:flutter3d_game/src/actors/actor.dart';
import 'package:flutter3d_game/src/actors/actor_system.dart';
import 'package:flutter3d_game/src/actors/brain.dart';
import 'package:flutter3d_game/src/actors/damageable.dart';
import 'package:flutter3d_game/src/actors/health.dart';
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
    final x = it.actor.position.x;
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

Actor _walker(CollisionWorld world, {double at = 0.0}) => Actor(
      body: CharacterController(
        world: world,
        position: Vector3(at, 0.9, 0.0),
      ),
      health: Health(30.0),
      brain: _Patrol(from: -4.0, to: 4.0),
    );

void main() {
  group('an actor with a brain that is not a monster', () {
    test('walks its patrol, turns round, and comes back', () {
      final world = _ground();
      final system = ActorSystem(world: world)..add(_walker(world));
      final walker = system.actors.single;
      final nowhere = Vector3(0.0, 100.0, 0.0);

      var east = walker.position.x;
      var west = walker.position.x;
      for (var i = 0; i < 400; i++) {
        system.step(_dt, focus: nowhere);
        if (walker.position.x > east) east = walker.position.x;
        if (walker.position.x < west) west = walker.position.x;
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
      final system = ActorSystem(world: world)..add(_walker(world));
      // Twenty steps: long enough to have come round at six radians a second,
      // short enough that it has not reached the end of its patrol and turned
      // back — which it does in about forty.
      for (var i = 0; i < 20; i++) {
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
      final system = ActorSystem(world: world);
      final walker = system.add(_walker(world));

      expect(system.hurt(walker, 10.0), isFalse);
      expect(system.hurtThisStep.single.actor, same(walker));
      expect(system.hurtThisStep.single.staggered, isFalse,
          reason: 'nothing rolled a flinch, because nothing here has one');

      expect(system.hurt(walker, 100.0), isTrue);
      expect(system.died, <Actor>[walker]);
      expect(walker.body.collider.kind, ColliderKind.trigger);
      expect(system.aliveCount, 0);
    });

    test('damage routed through the collider reaches the system', () {
      // The `Damageable` path: a rocket asks whoever it hit to take damage and
      // never learns what they are.
      final world = _ground();
      final system = ActorSystem(world: world);
      final walker = system.add(_walker(world));

      final owner = walker.body.collider.userData;
      expect(owner, same(walker));
      expect((owner! as Damageable).applyDamage(1000.0), isTrue);
      expect(system.died, hasLength(1),
          reason: 'the kill never reached the system that owns it');
    });

    test('a brain saves and restores itself with the actor', () {
      // The engine writes body, health and yaw; what the brain remembers is the
      // brain's, and nothing in `Actor.save` knows what it is.
      final world = _ground();
      final system = ActorSystem(world: world)..add(_walker(world));
      final walker = system.actors.single;

      // Far enough to have turned round at least once, so the flag is not
      // simply its initial value.
      for (var i = 0; i < 100; i++) {
        system.step(_dt, focus: Vector3(0.0, 100.0, 0.0));
      }
      final wasHeading = (walker.brain as _Patrol).eastward;
      expect(wasHeading, isFalse, reason: 'it should have turned by now');

      final saved = walker.save();
      (walker.brain as _Patrol).eastward = !wasHeading;
      walker.restore(saved);
      expect((walker.brain as _Patrol).eastward, wasHeading);
    });

    test('a corpse still falls', () {
      // It was a comment in the old system and it is still true of anything:
      // stop stepping a dead body and it hangs in the air where it died.
      final world = _ground();
      final system = ActorSystem(world: world);
      final walker = system.add(
        Actor(
          body: CharacterController(
            world: world,
            position: Vector3(0.0, 6.0, 0.0),
          ),
          health: Health(10.0),
          brain: _Patrol(from: -1.0, to: 1.0),
        ),
      );
      system.hurt(walker, 100.0);

      for (var i = 0; i < 120; i++) {
        system.step(_dt, focus: Vector3(0.0, 100.0, 0.0));
      }
      expect(walker.position.y, closeTo(0.9, 0.1));
    });
  });

  group('the system', () {
    test('numbers actors as they are added, and not by their address', () {
      // The ordinal that replaced `hashCode`. Two identical runs must agree
      // about which actor thinks on which step.
      final world = _ground();
      final system = ActorSystem(world: world);
      for (var i = 0; i < 4; i++) {
        system.add(_walker(world, at: i.toDouble()));
      }
      expect(
        <int>[for (final actor in system.actors) actor.ordinal],
        <int>[0, 1, 2, 3],
      );
    });

    test('the eye comes off the body, not off a definition', () {
      final world = _ground();
      final tall = Actor(
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
      expect(eye.y, greaterThan(tall.position.y));
      expect(eye.y - tall.position.y,
          closeTo(tall.body.halfExtents.y * 0.32, 1e-6));
    });
  });
}
