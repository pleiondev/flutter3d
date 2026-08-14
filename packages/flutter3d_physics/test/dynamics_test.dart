/// Stage one of the rigid bodies, against the numbers the specification asks
/// for rather than against the impression that it looks right.
///
/// `docs/SPEC.md` §4.3 splits rigid bodies into two stages with separate
/// acceptance, and this is stage one: mass, gravity, impulses, being pushed,
/// and coming to rest. The stress tests below are its half of that list — a
/// stack that stands, a crate that is pushed and stops, a body that sleeps.
///
/// Every one of them fails on a solver that merely *nearly* works, which is the
/// reason for writing them as numbers and durations rather than as "it settles".
library;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// A floor with its top face at y = 0.
CollisionWorld _ground() {
  final world = CollisionWorld();
  world.addBox(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0));
  world.update();
  return world;
}

RigidBody _crate(
  Dynamics dynamics, {
  required Vector3 at,
  double half = 0.25,
  double mass = 10.0,
}) => dynamics.add(
  RigidBody(
    world: dynamics.world,
    shape: CollisionBox(Vector3.all(half)),
    position: at,
    mass: mass,
  ),
);

void _run(Dynamics dynamics, double seconds) {
  final steps = (seconds / _dt).round();
  for (var i = 0; i < steps; i++) {
    dynamics.step(_dt);
    dynamics.world.update();
    dynamics.world.clearKinematicDeltas();
  }
}

void main() {
  group('a body on its own', () {
    test('falls, lands, and stays landed', () {
      final dynamics = Dynamics(world: _ground());
      final crate = _crate(dynamics, at: Vector3(0.0, 4.0, 0.0));

      _run(dynamics, 3.0);

      // Resting on the floor means its centre is one half-extent above it,
      // less whatever penetration the slop tolerates.
      expect(crate.position.y, closeTo(0.25, dynamics.slop + 1e-3));
      expect(crate.velocity.length, lessThan(0.05));
    });

    test('goes to sleep once it has stopped, and stays put', () {
      final dynamics = Dynamics(world: _ground());
      final crate = _crate(dynamics, at: Vector3(0.0, 1.0, 0.0));

      _run(dynamics, 3.0);
      expect(
        crate.isAsleep,
        isTrue,
        reason: 'a settled crate is still being solved sixty times a second',
      );

      final restedAt = crate.position.clone();
      _run(dynamics, 5.0);
      expect(
        (crate.position - restedAt).length,
        lessThan(1e-4),
        reason: 'it drifted while asleep',
      );
    });

    test('an impulse wakes it and throws it', () {
      final dynamics = Dynamics(world: _ground());
      final crate = _crate(dynamics, at: Vector3(0.0, 1.0, 0.0));
      _run(dynamics, 3.0);
      expect(crate.isAsleep, isTrue);

      // Ten kilograms, forty newton-seconds sideways: four metres a second.
      crate.applyImpulse(Vector3(40.0, 0.0, 0.0));
      expect(crate.isAsleep, isFalse);
      expect(crate.velocity.x, closeTo(4.0, 1e-9));

      _run(dynamics, 0.5);
      expect(crate.position.x, greaterThan(0.5));
    });

    test('an immovable body is not moved by gravity or by anything else', () {
      final dynamics = Dynamics(world: _ground());
      final bolted = dynamics.add(
        RigidBody(
          world: dynamics.world,
          shape: CollisionBox(Vector3.all(0.25)),
          position: Vector3(0.0, 3.0, 0.0),
          mass: 0.0,
        ),
      );

      bolted.applyImpulse(Vector3(1000.0, 0.0, 0.0));
      _run(dynamics, 2.0);

      expect(bolted.position.y, 3.0);
      expect(bolted.position.x, 0.0);
    });
  });

  group('the acceptance stress tests', () {
    test('a stack of ten crates stands still for a minute', () {
      // The specification's number, and the one that separates a solver from an
      // arrangement of hopeful arithmetic. Ten boxes, sixty seconds, and the
      // bottom one may not be squeezed out of the pile by the accumulated
      // error of nine contacts above it.
      final dynamics = Dynamics(world: _ground());
      final stack = <RigidBody>[
        for (var i = 0; i < 10; i++)
          _crate(dynamics, at: Vector3(0.0, 0.25 + i * 0.5, 0.0)),
      ];

      _run(dynamics, 60.0);

      for (var i = 0; i < stack.length; i++) {
        expect(
          stack[i].position.y,
          closeTo(0.25 + i * 0.5, 0.05),
          reason: 'crate $i sank or climbed',
        );
        expect(
          stack[i].position.x.abs(),
          lessThan(0.05),
          reason: 'crate $i squirmed sideways out of the pile',
        );
        expect(stack[i].position.z.abs(), lessThan(0.05));
      }
      expect(
        stack.every((RigidBody b) => b.isAsleep),
        isTrue,
        reason: 'a settled stack is still being solved every step',
      );
    });

    test('a pushed crate travels, slows on friction, and stops', () {
      final dynamics = Dynamics(world: _ground());
      final crate = _crate(dynamics, at: Vector3(0.0, 0.25, 0.0));
      _run(dynamics, 1.0);

      crate.applyImpulse(Vector3(60.0, 0.0, 0.0));
      _run(dynamics, 4.0);

      expect(crate.position.x, greaterThan(1.0), reason: 'it barely moved');
      expect(
        crate.velocity.length,
        lessThan(0.1),
        reason: 'friction never brought it to rest',
      );
      expect(
        crate.position.y,
        closeTo(0.25, dynamics.slop + 1e-3),
        reason: 'it ploughed into the floor or climbed out of it',
      );
    });

    test('a crate pushed into another moves it and neither ends up inside', () {
      final dynamics = Dynamics(world: _ground());
      final pusher = _crate(dynamics, at: Vector3(-1.0, 0.25, 0.0));
      final pushed = _crate(dynamics, at: Vector3(0.0, 0.25, 0.0));
      _run(dynamics, 1.0);

      pusher.applyImpulse(Vector3(120.0, 0.0, 0.0));
      _run(dynamics, 3.0);

      expect(
        pushed.position.x,
        greaterThan(0.2),
        reason: 'the second crate was walked through rather than pushed',
      );
      expect(
        pushed.position.x - pusher.position.x,
        greaterThan(0.45),
        reason: 'they are inside each other',
      );
    });

    test('a heavy crate is barely moved by a light one', () {
      // Mass has to mean something, or `applyImpulse` is just a velocity
      // setter with extra steps.
      final dynamics = Dynamics(world: _ground());
      final light = _crate(dynamics, at: Vector3(-1.0, 0.25, 0.0), mass: 5.0);
      final heavy = _crate(dynamics, at: Vector3(0.0, 0.25, 0.0), mass: 500.0);
      _run(dynamics, 1.0);

      light.applyImpulse(Vector3(60.0, 0.0, 0.0));
      _run(dynamics, 2.0);

      expect(heavy.position.x, lessThan(0.15));
      expect(light.position.x, greaterThan(-0.7));
    });

    test('a bouncy body bounces and a crate does not', () {
      final dynamics = Dynamics(world: _ground());
      final ball = dynamics.add(
        RigidBody(
          world: dynamics.world,
          shape: CollisionSphere(0.25),
          position: Vector3(0.0, 3.0, 0.0),
          mass: 2.0,
          restitution: 0.7,
        ),
      );
      final crate = _crate(dynamics, at: Vector3(4.0, 3.0, 0.0));

      var ballHighest = 0.0;
      var crateHighest = 0.0;
      var landed = false;
      for (var i = 0; i < 240; i++) {
        dynamics.step(_dt);
        dynamics.world.update();
        dynamics.world.clearKinematicDeltas();
        if (ball.position.y < 0.3) landed = true;
        if (landed) {
          if (ball.position.y > ballHighest) ballHighest = ball.position.y;
          if (crate.position.y > crateHighest) crateHighest = crate.position.y;
        }
      }

      expect(ballHighest, greaterThan(0.6), reason: 'it did not bounce');
      expect(
        crateHighest,
        lessThan(0.35),
        reason: 'a crate with no restitution bounced',
      );
    });
  });

  group('against the rest of the world', () {
    test('a crate rides a kinematic platform', () {
      // The one interaction that matters most for a game: `ColliderKind` says a
      // rigid body is kinematic to the collision world, which is what lets a
      // lift and a crate meet at all.
      final world = _ground();
      final platform = world.add(
        Collider(
          shape: CollisionBox(Vector3(1.0, 0.25, 1.0)),
          position: Vector3(0.0, 0.25, 0.0),
          kind: ColliderKind.kinematic,
        ),
      );
      world.update();

      final dynamics = Dynamics(world: world);
      final crate = _crate(dynamics, at: Vector3(0.0, 0.75, 0.0));
      _run(dynamics, 1.0);
      final restedAt = crate.position.y;

      for (var i = 0; i < 120; i++) {
        platform.moveTo(platform.position + Vector3(0.0, 0.02, 0.0));
        world.reindex();
        dynamics.step(_dt);
        dynamics.world.update();
        dynamics.world.clearKinematicDeltas();
      }

      expect(
        platform.position.y,
        closeTo(2.65, 1e-3),
        reason: 'a Vector3 is float32, so 120 additions of 0.02 land nearby',
      );
      expect(
        crate.position.y,
        greaterThan(restedAt + 2.0),
        reason: 'the platform rose out from under it',
      );
    });

    test('a snapshot puts a body back exactly', () {
      final dynamics = Dynamics(world: _ground());
      final crate = _crate(dynamics, at: Vector3(0.0, 3.0, 0.0));
      _run(dynamics, 0.5);

      final saved = crate.save();
      final wasAt = crate.position.clone();
      final wasMoving = crate.velocity.clone();

      _run(dynamics, 1.0);
      expect(crate.position.y, isNot(wasAt.y));

      crate.restore(saved);
      expect(crate.position.y, closeTo(wasAt.y, 1e-6));
      expect(crate.velocity.y, closeTo(wasMoving.y, 1e-6));
    });
  });
}
