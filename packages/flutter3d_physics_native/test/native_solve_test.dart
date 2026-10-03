/// The solver on a native world through `dart:ffi` — P9, phase 3.
///
///     dart test test/native_solve_test.dart
///
/// The C tests hold the solver against the physics: rest, stacks, bounce,
/// slopes, rolling, momentum. These hold it against `flutter3d_physics`
/// where the two can be compared — a crate dropped on a floor comes to rest
/// in the same place — and what a game sets through the binding.
library;

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
}
