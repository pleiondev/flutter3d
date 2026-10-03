/// A native world through `dart:ffi` — P9, phase 0.
///
///     dart test test/native_world_test.dart
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// [value] rounded to the nearest float, as the core holds it.
double f32(double value) => (Float32List(1)..[0] = value)[0];

void main() {
  late NativeWorld world;
  setUp(() => world = NativeWorld());
  tearDown(() => world.dispose());

  test('a new world is empty under standard gravity', () {
    expect(world.bodyCount, 0);
    expect(world.gravity.y, f32(-9.81));
    world.gravity = Vector3(1.0, 2.0, 3.0);
    expect(world.gravity, Vector3(1.0, 2.0, 3.0));
  });

  test('bodies come and go by handle, and a stale handle names nothing', () {
    final a = world.addBody(position: Vector3(1.0, 2.0, 3.0));
    final b = world.addBody(position: Vector3.zero(), mass: 2.0);
    expect(world.bodyCount, 2);
    expect(world.contains(a) && world.contains(b), isTrue);
    expect(world.positionOf(a), Vector3(1.0, 2.0, 3.0));

    expect(world.removeBody(a), isTrue);
    expect(world.removeBody(a), isFalse);
    expect(world.contains(a), isFalse);
    expect(() => world.positionOf(a), throwsArgumentError);

    // The freed slot is reused under a new generation.
    final c = world.addBody(position: Vector3.zero());
    expect(c.slot, a.slot);
    expect(c.generation, a.generation + 1);
    expect(world.contains(a), isFalse);
    expect(world.contains(c), isTrue);
  });

  test('a body the core refuses is refused with the reason', () {
    expect(
      () => world.addBody(position: Vector3.zero(), mass: 0.0),
      throwsA(isA<ArgumentError>().having((e) => e.name, 'name', 'mass')),
    );
    expect(
      () => world.addBody(position: Vector3(double.nan, 0.0, 0.0)),
      throwsA(isA<ArgumentError>().having((e) => e.name, 'name', 'position')),
    );
    // A fixed body's mass is not read.
    world.addBody(
      position: Vector3.zero(),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    expect(world.bodyCount, 1);
  });

  test('a step is semi-implicit Euler: velocity, then position with it', () {
    // Mutation: integrate the position before the velocity in
    // `f3d_world_step` — y would stay at 10 after the first step.
    world.gravity = Vector3(0.0, -10.0, 0.0);
    final falling = world.addBody(position: Vector3(0.0, 10.0, 0.0));
    final pinned = world.addBody(
      position: Vector3(0.0, 10.0, 0.0),
      type: NativeBodyType.fixed,
    );
    world.step(0.5);
    expect(world.velocityOf(falling).y, -5.0);
    expect(world.positionOf(falling).y, 7.5);
    expect(world.positionOf(pinned).y, 10.0);
    world
      ..step(0.0)
      ..step(-1.0)
      ..step(double.nan);
    expect(world.positionOf(falling).y, 7.5);
  });

  test('transforms come back in slot order with their handles', () {
    final a = world.addBody(position: Vector3(1.0, 0.0, 0.0));
    final b = world.addBody(position: Vector3(2.0, 0.0, 0.0));
    final c = world.addBody(position: Vector3(3.0, 0.0, 0.0));
    world.removeBody(b);
    final read = world.readTransforms();
    expect(read.bodies, <NativeBody>[a, c]);
    expect(read.transforms, hasLength(14));
    expect(read.transforms.sublist(0, 7), <double>[1, 0, 0, 0, 0, 0, 1]);
    expect(read.transforms[7], 3.0);
  });

  test('a disposed world refuses every call', () {
    final other = NativeWorld()..dispose();
    expect(other.isDisposed, isTrue);
    expect(() => other.bodyCount, throwsStateError);
    expect(() => other.step(0.1), throwsStateError);
    other.dispose(); // Twice is fine.
  });

  test('a free fall agrees with flutter3d_physics, the reference', () {
    // Two seconds at sixty steps a second, from rest and thrown. The core is
    // in floats and the reference in doubles, so this holds the behaviour to
    // a tolerance rather than to the bit: the same integrator, the same
    // order, the same answer to within float rounding.
    //
    // Mutation: integrate with the old velocity (explicit Euler) in the core
    // — two seconds of it is 0.33 m off.
    const dt = 1.0 / 60.0;
    final reference = Dynamics(
      world: CollisionWorld(),
      gravity: Vector3(0.0, -9.81, 0.0),
    );
    final starts = <(Vector3, Vector3)>[
      (Vector3(0.0, 20.0, 0.0), Vector3.zero()),
      (Vector3(-3.0, 5.0, 2.0), Vector3(4.0, 6.0, -1.5)),
    ];
    final bodies = <(RigidBody, NativeBody)>[];
    for (final (position, velocity) in starts) {
      final dart = reference.add(
        RigidBody(
          world: reference.world,
          shape: CollisionBox(Vector3.all(0.1)),
          position: position.clone(),
        )..velocity.setFrom(velocity),
      );
      final native = world.addBody(position: position);
      world.setVelocity(native, velocity);
      bodies.add((dart, native));
    }
    for (var i = 0; i < 120; i++) {
      reference.step(dt);
      world.step(dt);
    }
    for (final (dart, native) in bodies) {
      final a = dart.position;
      final b = world.positionOf(native);
      final scale = math.max(1.0, a.length);
      expect((a - b).length / scale, lessThan(1e-4), reason: '$a vs $b');
    }
  });
}
