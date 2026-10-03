/// A native world through `dart:ffi` — P9: bodies, their motion, sleep,
/// the origin and snapshots.
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

  test('a box spun off its axes turns as flutter3d_physics turns it', () {
    // The same momentum-keeping turn as `RigidBody.integrateOrientation`:
    // a box spun about a tilted axis wobbles, and after four seconds of it
    // the two still agree on where it faces and how it spins.
    //
    // Mutation: in `turn`, keep ω instead of reading it back out of L —
    // the box stops wobbling and the spins part by a radian a second.
    const dt = 1.0 / 120.0;
    final reference = Dynamics(
      world: CollisionWorld(),
      gravity: Vector3.zero(),
    );
    final half = Vector3(0.1, 0.4, 0.8);
    final dart = reference.add(
      RigidBody(
        world: reference.world,
        shape: CollisionBox(half),
        position: Vector3.zero(),
        mass: 2.0,
        canRotate: true,
      ),
    );
    dart.angularVelocity.setValues(2.0, 0.5, 0.25);
    world
      ..gravity = Vector3.zero()
      ..setSleep(speed: 0.0, time: 0.0);
    final native = world.addBody(position: Vector3.zero(), mass: 2.0);
    world
      ..setShape(native, NativeShape.box(half))
      ..setDrag(native, 1e-30)
      ..setAngularVelocity(native, Vector3(2.0, 0.5, 0.25));
    expect(world.inertiaOf(native).x, closeTo(dart.inertiaLocal.x, 1e-6));
    for (var i = 0; i < 480; i++) {
      reference.step(dt);
      world.step(dt);
    }
    final q = world.orientationOf(native);
    final r = dart.orientation;
    // q and −q are the same turn.
    final dot = (q.x * r.x + q.y * r.y + q.z * r.z + q.w * r.w).abs();
    expect(dot, closeTo(1.0, 1e-4));
    expect(
      (world.angularVelocityOf(native) - dart.angularVelocity).length,
      lessThan(1e-3),
    );
    expect(
      (dart.angularVelocity - Vector3(2.0, 0.5, 0.25)).length,
      greaterThan(0.1),
    );
  });

  test('an impulse off the centre spins the body as the reference does', () {
    final reference = Dynamics(
      world: CollisionWorld(),
      gravity: Vector3.zero(),
    );
    final dart = reference.add(
      RigidBody(
        world: reference.world,
        shape: CollisionSphere(0.5),
        position: Vector3.zero(),
        mass: 3.0,
        canRotate: true,
      ),
    )..applyImpulseAt(Vector3(0.0, 2.0, 1.0), Vector3(0.5, 0.0, 0.1));
    final native = world.addBody(position: Vector3.zero(), mass: 3.0);
    world
      ..setShape(native, const NativeShape.sphere(0.5))
      ..applyImpulse(
        native,
        Vector3(0.0, 2.0, 1.0),
        at: Vector3(0.5, 0.0, 0.1),
      );
    expect((world.velocityOf(native) - dart.velocity).length, lessThan(1e-6));
    expect(
      (world.angularVelocityOf(native) - dart.angularVelocity).length,
      lessThan(1e-5),
    );
  });

  test('forces, torques and damping, and what cannot turn does not', () {
    world
      ..gravity = Vector3.zero()
      ..setAir(temperature: 293.15, density: 1e-30);
    final b = world.addBody(position: Vector3.zero(), mass: 2.0);
    world
      ..addForce(b, Vector3(4.0, 0.0, 0.0))
      ..step(0.5);
    expect(world.velocityOf(b).x, 1.0);
    // A point has no inertia and does not turn.
    world.setAngularVelocity(b, Vector3(1.0, 0.0, 0.0));
    expect(world.angularVelocityOf(b), Vector3.zero());
    world.setShape(b, const NativeShape.capsule(0.1, 0.5));
    expect(world.inertiaOf(b).y, lessThan(world.inertiaOf(b).x));
    world
      ..setDamping(b, linear: 1.0)
      ..step(1.0);
    expect(world.velocityOf(b).x, 0.5);
    world.lockRotation(b);
    world
      ..addTorque(b, Vector3(0.0, 1.0, 0.0))
      ..step(0.5);
    expect(world.angularVelocityOf(b), Vector3.zero());
    expect(
      () => world.setShape(b, const NativeShape.sphere(-1.0)),
      throwsA(isA<ArgumentError>().having((e) => e.name, 'name', 'value')),
    );
    expect(() => world.setDamping(b, linear: -1.0), throwsArgumentError);
    world.setOrientation(b, Quaternion(0.0, 0.0, 0.0, 0.0));
    expect(world.orientationOf(b).w, 1.0);
    world.setOrientation(b, Quaternion(0.0, 2.0, 0.0, 0.0));
    expect(world.orientationOf(b).y, 1.0);
  });

  test('a body at rest falls asleep and says so, and a push wakes it', () {
    world.gravity = Vector3.zero();
    final b = world.addBody(position: Vector3.zero());
    world.setVelocity(b, Vector3(0.01, 0.0, 0.0));
    for (var i = 0; i < 31; i++) {
      world.step(1.0 / 60.0);
    }
    expect(world.isAsleep(b), isTrue);
    expect(world.velocityOf(b), Vector3.zero());
    world.applyImpulse(b, Vector3(1.0, 0.0, 0.0));
    expect(world.isAsleep(b), isFalse);
    expect(world.readEvents(), <NativeEvent>[
      (body: b, other: null, kind: NativeEventKind.slept),
      (body: b, other: null, kind: NativeEventKind.woke),
    ]);
    expect(world.readEvents(), isEmpty);
    expect(world.eventsDropped, 0);
  });

  test('an origin moved to a body far out gives it back its precision', () {
    // Ten kilometres out a float is a millimetre wide. Moved to an origin
    // beside it, a micrometre step is a step it can take, and nothing in
    // the world moved.
    world.gravity = Vector3.zero();
    final far = world.addBody(position: Vector3(10000.0, 0.0, 0.0));
    world.shiftOrigin(10000.0, 0.0, 0.0);
    expect(world.origin, (x: 10000.0, y: 0.0, z: 0.0));
    expect(world.positionOf(far), Vector3.zero());
    expect(world.worldPositionOf(far).x, 10000.0);
    world
      ..setVelocity(far, Vector3(1e-6, 0.0, 0.0))
      ..step(1.0);
    expect(world.worldPositionOf(far).x - 10000.0, closeTo(1e-6, 1e-12));
  });

  test('a world restored from a snapshot steps to the same bytes', () {
    // Mutation: leave the wind grid out of `f3d_world_snapshot_write` —
    // the restored world reads no wind and the bodies part.
    world.wind = Vector3(1.0, 0.0, 0.5);
    world.setWindGrid(
      origin: Vector3(-5.0, 0.0, -5.0),
      cell: 5.0,
      nx: 2,
      ny: 1,
      nz: 2,
      velocities: Float32List.fromList(<double>[
        1,
        0,
        0,
        0,
        0,
        2,
        -1,
        0,
        0,
        0,
        3,
        0,
      ]),
    );
    for (var i = 0; i < 5; i++) {
      final b = world.addBody(
        position: Vector3(i * 1.0, i * 2.0, 0.0),
        mass: 0.5 + i,
      );
      world
        ..setShape(b, NativeShape.box(Vector3(0.2, 0.3, 0.1)))
        ..setAngularVelocity(b, Vector3(0.3 * i, 1.0, -0.7))
        ..setMaterial(b, NativeMaterial.wood());
      if (i == 1) world.setTemperature(b, 650.0);
    }
    for (var i = 0; i < 30; i++) {
      world.step(1.0 / 60.0);
    }
    final saved = world.snapshot();
    final other = NativeWorld();
    addTearDown(other.dispose);
    other
      ..addBody(position: Vector3.zero())
      ..restore(saved);
    expect(other.bodyCount, world.bodyCount);
    for (var i = 0; i < 300; i++) {
      world.step(1.0 / 60.0);
      other.step(1.0 / 60.0);
    }
    expect(other.snapshot(), world.snapshot());
    expect(other.readEvents(), world.readEvents());
    // Not a snapshot: refused, and the world kept.
    final before = other.snapshot();
    expect(
      () => other.restore(Uint8List.fromList(<int>[1, 2, 3])),
      throwsArgumentError,
    );
    expect(other.snapshot(), before);
  });
}
