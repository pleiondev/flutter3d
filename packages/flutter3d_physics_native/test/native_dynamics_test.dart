// The core underneath flutter3d_physics' bodies — P9: the same scenes built
// once, through RigidDynamics, and stepped by the reference and by the core;
// what a game sees of them — where the crates come to rest, which way a
// push or a slope sends them, that they sleep — is held equal, within what
// two solvers in two precisions differ by. Then what only the mirror has
// to get right: an impulse, a teleport, a lift, a removal, a rollback.
import 'dart:typed_data';

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

typedef Backend = RigidDynamics Function(CollisionWorld world);

final Map<String, Backend> backends = <String, Backend>{
  'Dynamics': (world) => Dynamics(world: world),
  'NativeDynamics': (world) {
    final dynamics = NativeDynamics(world: world);
    addTearDown(dynamics.dispose);
    return dynamics;
  },
};

RigidBody crate(
  RigidDynamics dynamics,
  Vector3 at, {
  double half = 0.5,
  bool canRotate = false,
}) => dynamics.add(
  RigidBody(
    world: dynamics.world,
    shape: CollisionBox(Vector3.all(half)),
    position: at,
    canRotate: canRotate,
  ),
);

void run(RigidDynamics dynamics, int steps) {
  for (var i = 0; i < steps; i++) {
    dynamics.step(1.0 / 60.0);
  }
}

void main() {
  for (final MapEntry(key: name, value: make) in backends.entries) {
    group(name, () {
      test('a crate falls onto a floor and rests on it, asleep', () {
        final world = CollisionWorld()
          ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(20.0, 1.0, 20.0));
        final dynamics = make(world);
        final box = crate(dynamics, Vector3(0.0, 3.0, 0.0));
        run(dynamics, 180);
        expect(box.position.y, closeTo(0.5, 0.02));
        expect(box.isAsleep, isTrue);
        expect(box.collider.position.y, box.position.y);
      });

      test('a stack of five stands and sleeps', () {
        final world = CollisionWorld()
          ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(20.0, 1.0, 20.0));
        final dynamics = make(world);
        final stack = <RigidBody>[
          for (var i = 0; i < 5; i++)
            crate(dynamics, Vector3(0.0, 0.5 + i * 1.0, 0.0)),
        ];
        run(dynamics, 300);
        for (var i = 0; i < 5; i++) {
          expect(stack[i].position.x, closeTo(0.0, 0.02));
          expect(stack[i].position.y, closeTo(0.5 + i, 0.05));
        }
        expect(stack.every((b) => b.isAsleep), isTrue);
      });

      test('a walker pushes a crate the way it walks', () {
        final world = CollisionWorld()
          ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(20.0, 1.0, 20.0));
        final dynamics = make(world);
        final box = crate(dynamics, Vector3(0.0, 0.5, 0.0));
        final walker = world.add(
          Collider(
            shape: CollisionCapsule(radius: 0.3, halfHeight: 0.6),
            position: Vector3(-0.81, 0.9, 0.0),
            kind: ColliderKind.kinematic,
          ),
        );
        run(dynamics, 30);
        dynamics.push(walker, Vector3(2.0, 0.0, 0.0));
        expect(box.velocity.x, closeTo(2.0, 1e-9));
        run(dynamics, 1);
        expect(box.position.x, greaterThan(0.01));
      });

      test('an impulse between steps is taken', () {
        final world = CollisionWorld();
        final dynamics = make(world);
        final ball = dynamics.add(
          RigidBody(
            world: world,
            shape: CollisionSphere(0.25),
            position: Vector3.zero(),
            mass: 2.0,
          ),
        );
        dynamics.gravity.setZero();
        ball.applyImpulse(Vector3(4.0, 0.0, 0.0));
        run(dynamics, 60);
        expect(ball.velocity.x, closeTo(2.0, 1e-6));
        expect(ball.position.x, closeTo(2.0, 1e-3));
      });

      test('a crate rests on a height field where its surface is', () {
        final heights = Float32List(9 * 9);
        for (var row = 0; row < 9; row++) {
          for (var column = 0; column < 9; column++) {
            heights[row * 9 + column] = 0.1 * column;
          }
        }
        final field = CollisionHeightfield(
          columns: 9,
          rows: 9,
          cellSize: 1.0,
          heights: heights,
        );
        final world = CollisionWorld()
          ..add(Collider(shape: field, position: Vector3.zero()));
        final dynamics = make(world);
        final box = crate(dynamics, Vector3(0.0, 3.0, 0.0), half: 0.25);
        run(dynamics, 120);
        final ground = field.heightAt(Vector3.zero(), 0.0, 0.0);
        expect(box.position.y, closeTo(ground + 0.25, 0.15));
        expect(box.position.y, greaterThan(ground));
      });
    });
  }

  group('NativeDynamics alone', () {
    late CollisionWorld world;
    late NativeDynamics dynamics;
    setUp(() {
      world = CollisionWorld()
        ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(20.0, 1.0, 20.0));
      dynamics = NativeDynamics(world: world);
      addTearDown(dynamics.dispose);
    });

    // The reference meets a wedge as its box, and a ball on it stays put.
    test('a ball rolls down a wedge, downhill', () {
      final world = CollisionWorld()
        ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0))
        ..add(
          Collider(
            shape: CollisionWedge(
              Vector3(2.0, 2.0, 2.0),
              uphill: WedgeUphill.positiveX,
            ),
            position: Vector3(0.0, 2.0, 0.0),
          ),
        );
      final dynamics = NativeDynamics(world: world);
      addTearDown(dynamics.dispose);
      final ball = dynamics.add(
        RigidBody(
          world: world,
          shape: CollisionSphere(0.25),
          position: Vector3(1.0, 3.6, 0.0),
          friction: 0.1,
        ),
      );
      run(dynamics, 90);
      expect(ball.position.x, lessThan(0.0));
    });

    test('a body put back by its own save() is where it was put', () {
      final box = crate(dynamics, Vector3(0.0, 0.5, 0.0));
      run(dynamics, 10);
      final saved = box.save();
      run(dynamics, 1);
      box.collider.moveTo(Vector3(5.0, 4.0, 0.0));
      run(dynamics, 1);
      expect(box.position.x, closeTo(5.0, 1e-6));
      expect(box.position.y, lessThan(4.0));
      box.restore(saved);
      run(dynamics, 1);
      expect(box.position.x, closeTo(0.0, 1e-6));
      expect(box.position.y, closeTo(0.5, 0.01));
    });

    test('a lift carries the crate on it up', () {
      final lift = world.add(
        Collider(
          shape: CollisionBox(Vector3(1.0, 0.25, 1.0)),
          position: Vector3(5.0, 0.25, 0.0),
          kind: ColliderKind.kinematic,
        ),
      );
      final box = crate(dynamics, Vector3(5.0, 1.0, 0.0));
      run(dynamics, 60);
      expect(box.position.y, closeTo(1.0, 0.02));
      for (var i = 0; i < 60; i++) {
        lift.moveTo(lift.position + Vector3(0.0, 1.0 / 60.0, 0.0));
        dynamics.step(1.0 / 60.0);
        world.clearKinematicDeltas();
      }
      expect(box.position.y, closeTo(2.0, 0.05));
    });

    test('a wall taken out of the world is taken out of the core', () {
      final wall = world.addBox(Vector3(2.0, 1.0, 0.0), Vector3(0.2, 2.0, 4.0));
      final ball = dynamics.add(
        RigidBody(
          world: world,
          shape: CollisionSphere(0.25),
          position: Vector3(0.0, 0.25, 0.0),
          // Sliding, as it cannot turn: without friction, or the floor
          // stops it before the wall does.
          friction: 0.0,
        ),
      );
      ball.velocity.setValues(4.0, 0.0, 0.0);
      run(dynamics, 60);
      expect(ball.position.x, lessThan(2.0));
      world.remove(wall);
      ball
        ..wake()
        ..velocity.setValues(4.0, 0.0, 0.0);
      run(dynamics, 60);
      expect(ball.position.x, greaterThan(2.5));
      final count = dynamics.native.bodyCount;
      dynamics.remove(ball);
      expect(dynamics.native.bodyCount, count - 1);
      expect(world.movers, isNot(contains(ball.collider)));
    });

    test(
      'a crate that can turn tips off an edge; one that cannot, does not',
      () {
        final turning = crate(
          dynamics,
          Vector3(10.3, 0.5, 0.0),
          canRotate: true,
        );
        final upright = crate(dynamics, Vector3(10.3, 0.5, 5.0));
        run(dynamics, 120);
        expect(turning.orientation.w.abs(), lessThan(0.99));
        expect(upright.orientation.w, 1.0);
      },
    );

    test('a snapshot restored steps on to the same bits', () {
      final boxes = <RigidBody>[
        for (var i = 0; i < 6; i++)
          crate(
            dynamics,
            Vector3(i * 0.3, 1.0 + i * 1.1, 0.0),
            canRotate: true,
          ),
      ];
      run(dynamics, 20);
      final bytes = dynamics.snapshot();
      final then = <Object?>[for (final b in boxes) b.save()].toString();
      run(dynamics, 40);
      final first = <Object?>[for (final b in boxes) b.save()].toString();
      dynamics.restore(bytes);
      // The bodies are back at once, before the next step reads them.
      expect(<Object?>[for (final b in boxes) b.save()].toString(), then);
      run(dynamics, 40);
      final again = <Object?>[for (final b in boxes) b.save()].toString();
      expect(again, first);
    });
  });
}
