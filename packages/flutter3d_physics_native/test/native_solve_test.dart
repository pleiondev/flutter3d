/// The solver on a native world through `dart:ffi` — P9, phase 3.
///
///     dart test test/native_solve_test.dart
///
/// The C tests hold the solver against the physics: rest, stacks, bounce,
/// slopes, rolling, momentum. These hold it against `flutter3d_physics`
/// where the two can be compared — a crate dropped on a floor comes to rest
/// in the same place — and what a game sets through the binding.
library;

import 'dart:math' as math;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  late NativeWorld world;
  late NativeBody floor;
  setUp(() {
    world = NativeWorld()..setAir(temperature: 293.15, density: 1e-30);
    floor = world.addBody(
      position: Vector3(0.0, -0.5, 0.0),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    world.setShape(floor, NativeShape.box(Vector3(20.0, 0.5, 20.0)));
  });
  tearDown(() => world.dispose());

  test('a crate dropped on a floor rests where the reference rests it', () {
    // Mutation: drop the warm start from the substep loop — the crate sinks
    // five and a half centimetres under its own weight and never sleeps.
    final reference = Dynamics(
      world: CollisionWorld(),
      gravity: Vector3(0.0, -9.81, 0.0),
    );
    // The reference's floor is level geometry, a static collider.
    reference.world.add(
      Collider(
        shape: CollisionBox(Vector3(20.0, 0.5, 20.0)),
        position: Vector3(0.0, -0.5, 0.0),
        kind: ColliderKind.static,
      ),
    );
    final dart = reference.add(
      RigidBody(
        world: reference.world,
        shape: CollisionBox(Vector3.all(0.5)),
        position: Vector3(0.0, 1.5, 0.0),
      ),
    );
    final crate = world.addBody(position: Vector3(0.0, 1.5, 0.0));
    world.setShape(crate, NativeShape.box(Vector3.all(0.5)));
    for (var i = 0; i < 180; i++) {
      reference.step(1.0 / 60.0);
      world.step(1.0 / 60.0);
    }
    expect(world.positionOf(crate).y, closeTo(dart.position.y, 0.01));
    expect(world.positionOf(crate).y, closeTo(0.5, 0.006));
    expect(world.velocityOf(crate).length, lessThan(1e-3));
    expect(world.isAsleep(crate), isTrue);
  });

  test('a stack stands and sleeps, and a knock wakes all of it', () {
    final crates = <NativeBody>[
      for (var i = 0; i < 5; i++)
        world.addBody(position: Vector3(0.0, 0.5 + i, 0.0)),
    ];
    for (final c in crates) {
      world.setShape(c, NativeShape.box(Vector3.all(0.5)));
    }
    for (var i = 0; i < 180; i++) {
      world.step(1.0 / 60.0);
    }
    expect(crates.every(world.isAsleep), isTrue);
    expect(world.positionOf(crates.last).y, closeTo(4.5, 0.05));
    world.readEvents();
    world
      ..applyImpulse(crates.last, Vector3(0.5, 0.0, 0.0))
      ..step(1.0 / 60.0);
    expect(crates.any(world.isAsleep), isFalse);
  });

  test('friction holds on a slope and restitution bounces, as set', () {
    final ball = world.addBody(position: Vector3(0.0, 2.25, 0.0));
    world
      ..setShape(ball, const NativeShape.sphere(0.25))
      ..setRestitution(ball, 0.8);
    var up = 0.0;
    for (var i = 0; i < 90; i++) {
      world.step(1.0 / 60.0);
      if (world.velocityOf(ball).y > up) up = world.velocityOf(ball).y;
    }
    expect(up, closeTo(0.8 * 6.26, 0.2));
    expect(() => world.setFriction(ball, -1.0), throwsArgumentError);
    expect(() => world.setRestitution(ball, 2.0), throwsArgumentError);
    expect(() => world.substeps = 0, throwsArgumentError);
    world.substeps = 8;
  });

  test(
    'a pendulum on a hinge swings at 2π √(L / g), and a rod holds a weight',
    () {
      // The C tests hold every joint against its physics; this holds the
      // binding: a joint made, read and taken away.
      world
        ..setSleep(speed: 0.0, time: 0.0)
        ..substeps = 4;
      final pivot = world.addBody(
        position: Vector3(0.0, 3.0, 0.0),
        type: NativeBodyType.fixed,
        mass: 0.0,
      );
      const start = 0.05;
      final bob = world.addBody(
        position: Vector3(math.sin(start), 3.0 - math.cos(start), 0.0),
      );
      world.setShape(bob, const NativeShape.sphere(0.01));
      final hinge = world.createJoint(
        NativeJointType.revolute,
        pivot,
        bob,
        anchor: Vector3(0.0, 3.0, 0.0),
        axis: Vector3(0.0, 0.0, 1.0),
      );
      // A quarter period later it is at the bottom: the angle back to nought.
      final quarter = 0.5 * math.pi * math.sqrt(1.0 / 9.81);
      var t = 0.0;
      while (t < quarter - 1e-9) {
        world.step(1.0 / 240.0);
        t += 1.0 / 240.0;
      }
      expect(world.jointValue(hinge), closeTo(-start, 2e-3));
      world.setJointLimits(hinge, (lower: -0.1, upper: 0.1));
      world.setJointMotor(hinge, (speed: 1.0, maxForce: 100.0));
      expect(
        () => world.setJointLength(hinge, length: 1, least: 0, most: 1),
        throwsArgumentError,
      );
      expect(world.jointCount, 1);
      expect(world.removeJoint(hinge), isTrue);
      expect(world.containsJoint(hinge), isFalse);
      // A rod holding a kilogram still: the force on it is its weight, up.
      final weight = world.addBody(position: Vector3(5.0, 1.0, 0.0));
      world.setShape(weight, const NativeShape.sphere(0.1));
      final hook = world.addBody(
        position: Vector3(5.0, 3.0, 0.0),
        type: NativeBodyType.fixed,
        mass: 0.0,
      );
      final rod = world.createDistanceJoint(
        hook,
        weight,
        anchorA: Vector3(5.0, 3.0, 0.0),
        anchorB: Vector3(5.0, 1.0, 0.0),
      );
      for (var i = 0; i < 120; i++) {
        world.step(1.0 / 60.0);
      }
      expect(world.jointForce(rod).y, closeTo(9.81, 0.02));
      expect(world.jointValue(rod), closeTo(2.0, 1e-3));
      // Made a rope two and a half metres long: slack, the weight falls half
      // a metre and hangs there, the rope taut, clear of the floor.
      world
        ..setJointLength(rod, length: 2.5, least: 0.0, most: 2.5)
        ..setJointSpring(rod, (hertz: 0.0, damping: 0.0));
      for (var i = 0; i < 240; i++) {
        world.step(1.0 / 60.0);
      }
      expect(world.jointValue(rod), closeTo(2.5, 2e-3));
      expect(world.positionOf(weight).y, closeTo(0.5, 2e-3));
      // Joined bodies pass through each other until told to collide.
      world.setShape(hook, const NativeShape.sphere(0.5));
      world.setPosition(weight, Vector3(5.0, 3.2, 0.0));
      world.setVelocity(weight, Vector3.zero());
      bool touching() => world.readContacts().any(
        (c) => <NativeBody>{c.a, c.b}.containsAll(<NativeBody>[hook, weight]),
      );
      world.step(1.0 / 60.0);
      expect(touching(), isFalse);
      world
        ..setJointCollide(rod, collide: true)
        ..step(1.0 / 60.0);
      expect(touching(), isTrue);
    },
  );

  test('a fast ball stops at a thin wall, softly or as a bullet', () {
    // Mutation: drop the speculative reach from the pair's margin in
    // `f3d_step_collide` — the soft ball goes through.
    world.gravity = Vector3.zero();
    final wall = world.addBody(
      position: Vector3(0.0, 5.0, 0.0),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    world.setShape(wall, NativeShape.box(Vector3(0.005, 2.0, 2.0)));
    final soft = world.addBody(position: Vector3(-2.0, 5.0, 0.0));
    world
      ..setShape(soft, const NativeShape.sphere(0.05))
      ..setVelocity(soft, Vector3(300.0, 0.0, 0.0));
    for (var i = 0; i < 10; i++) {
      world.step(1.0 / 60.0);
    }
    expect(world.positionOf(soft).x, lessThan(0.0));
    world.speculative = false;
    final bullet = world.addBody(position: Vector3(-2.0, 6.0, 0.0));
    world
      ..setShape(bullet, const NativeShape.sphere(0.05))
      ..setBullet(bullet)
      ..setVelocity(bullet, Vector3(500.0, 0.0, 0.0));
    for (var i = 0; i < 10; i++) {
      world.step(1.0 / 60.0);
    }
    expect(world.positionOf(bullet).x, lessThan(0.0));
  });

  test(
    'a heap steps to the same bits on four threads as on one, fast or not',
    () {
      // The C tests hold every shape and every thread count to the byte; this
      // holds the binding.
      final other = NativeWorld()..setAir(temperature: 293.15, density: 1e-30);
      addTearDown(other.dispose);
      expect(other.threads, 1);
      other.threads = 4;
      expect(other.threads, 4);
      final heaps = <(NativeWorld, List<NativeBody>)>[];
      for (final w in <NativeWorld>[world, other]) {
        if (w != world) {
          final ground = w.addBody(
            position: Vector3(0.0, -0.5, 0.0),
            type: NativeBodyType.fixed,
            mass: 0.0,
          );
          w.setShape(ground, NativeShape.box(Vector3(20.0, 0.5, 20.0)));
        }
        final bodies = <NativeBody>[
          for (var i = 0; i < 60; i++)
            w.addBody(
              position: Vector3(
                (i % 5) * 0.6 + (i % 3) * 0.02,
                0.5 + (i ~/ 25) * 0.6,
                ((i ~/ 5) % 5) * 0.6,
              ),
            ),
        ];
        for (var i = 0; i < bodies.length; i++) {
          w.setShape(
            bodies[i],
            i.isEven
                ? NativeShape.box(Vector3(0.25, 0.25, 0.25))
                : const NativeShape.sphere(0.27),
          );
        }
        heaps.add((w, bodies));
      }
      for (var step = 0; step < 120; step++) {
        world.step(1.0 / 60.0);
        other.step(1.0 / 60.0);
      }
      for (var i = 0; i < heaps[0].$2.length; i++) {
        expect(
          other.positionOf(heaps[1].$2[i]),
          world.positionOf(heaps[0].$2[i]),
        );
        expect(
          other.orientationOf(heaps[1].$2[i]),
          world.orientationOf(heaps[0].$2[i]),
        );
      }
      // The fast mode: other bits, the same on four threads as on one.
      for (final w in <NativeWorld>[world, other]) {
        expect(w.fast, isFalse);
        w.fast = true;
        expect(w.fast, isTrue);
      }
      for (var step = 0; step < 60; step++) {
        world.step(1.0 / 60.0);
        other.step(1.0 / 60.0);
      }
      for (var i = 0; i < heaps[0].$2.length; i++) {
        expect(
          other.positionOf(heaps[1].$2[i]),
          world.positionOf(heaps[0].$2[i]),
        );
      }
      expect(() => other.threads = 0, throwsArgumentError);
      expect(() => other.threads = 65, throwsArgumentError);
      other.threads = 1;
      expect(other.threads, 1);
    },
  );
}
