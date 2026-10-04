/// Contacts on a native world through `dart:ffi` — P9, phase 2.
///
///     dart test test/native_contact_test.dart
///
/// The C tests hold every pair of shapes against its closed form, turned;
/// these hold the axis-aligned pairs against `flutter3d_physics`, whose
/// contacts know no rotation, and what a game reads: the contacts, their
/// events and the filters.
library;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  late NativeWorld world;
  setUp(() {
    world = NativeWorld()
      ..gravity = Vector3.zero()
      ..setSleep(speed: 0.0, time: 0.0);
  });
  tearDown(() => world.dispose());

  NativeShape native(CollisionShape shape) => switch (shape) {
    CollisionSphere(:final radius) => NativeShape.sphere(radius),
    CollisionBox(:final halfExtents) => NativeShape.box(halfExtents),
    _ => throw ArgumentError(shape),
  };

  test('unturned, the contacts are flutter3d_physics\' contacts', () {
    // The reference reports one point per pair; the core reports a whole
    // face for two boxes, every point at the reference's depth, along its
    // normal.
    final cases = <(CollisionShape, Vector3, CollisionShape, Vector3)>[
      (
        CollisionSphere(0.5),
        Vector3(0.0, 0.95, 0.0),
        CollisionSphere(0.5),
        Vector3.zero(),
      ),
      (
        CollisionSphere(0.3),
        Vector3(0.1, 0.0, 0.79),
        CollisionSphere(0.5),
        Vector3.zero(),
      ),
      (
        CollisionSphere(0.25),
        Vector3(0.2, 0.74, 0.1),
        CollisionBox(Vector3.all(0.5)),
        Vector3.zero(),
      ),
      (
        CollisionSphere(0.25),
        Vector3(0.65, 0.65, 0.0),
        CollisionBox(Vector3.all(0.5)),
        Vector3.zero(),
      ),
      (
        CollisionBox(Vector3(0.5, 0.25, 0.5)),
        Vector3(0.2, 0.74, -0.1),
        CollisionBox(Vector3(1.0, 0.5, 1.0)),
        Vector3.zero(),
      ),
      (
        CollisionBox(Vector3.all(0.2)),
        Vector3(1.19, 0.1, 0.0),
        CollisionBox(Vector3.all(1.0)),
        Vector3.zero(),
      ),
    ];
    for (final (sa, at, sb, bt) in cases) {
      final w = NativeWorld()..gravity = Vector3.zero();
      addTearDown(w.dispose);
      final a = w.addBody(position: at);
      final b = w.addBody(position: bt, type: NativeBodyType.fixed);
      w
        ..setShape(a, native(sa))
        ..setShape(b, native(sb))
        ..step(1e-9);
      final reference = Contact();
      contactBetween(sa, at, sb, bt, reference);
      expect(reference.touching, isTrue);
      final contacts = w.readContacts();
      expect(contacts, isNotEmpty, reason: '$sa at $at on $sb');
      for (final c in contacts) {
        expect(c.a, a);
        expect(c.b, b);
        expect((c.normal - reference.normal).length, lessThan(1e-5));
        expect(c.depth, closeTo(reference.depth, 1e-5));
      }
    }
  });

  test('a ball bounced off a wall begins and ends one contact', () {
    // Mutation: compare the touching flags the wrong way round in the merge
    // of `f3d_step_collide` — no contact begins.
    world.setAir(temperature: 293.15, density: 1e-30);
    final wall = world.addBody(
      position: Vector3.zero(),
      type: NativeBodyType.fixed,
    );
    final ball = world.addBody(position: Vector3(-2.0, 0.0, 0.0), mass: 0.1);
    world
      ..setShape(wall, NativeShape.box(Vector3(0.1, 1.0, 1.0)))
      ..setShape(ball, const NativeShape.sphere(0.1))
      ..setRestitution(ball, 1.0)
      ..setVelocity(ball, Vector3(2.0, 0.0, 0.0));
    final seen = <NativeEvent>[];
    var deepest = -1.0;
    for (var i = 0; i < 400; i++) {
      world.step(0.01);
      seen.addAll(world.readEvents());
      for (final c in world.readContacts()) {
        if (c.depth > deepest) deepest = c.depth;
      }
    }
    expect(seen, <NativeEvent>[
      (body: wall, other: ball, kind: NativeEventKind.contactBegan),
      (body: wall, other: ball, kind: NativeEventKind.contactEnded),
    ]);
    // It never got into the wall past the slop, and came back at the speed
    // it arrived with.
    expect(deepest, lessThan(0.005));
    expect(world.velocityOf(ball).x, closeTo(-2.0, 0.05));
    expect(world.readContacts(), isEmpty);
  });

  test(
    'a filter keeps two bodies from meeting, and the margin is the world\'s',
    () {
      final a = world.addBody(position: Vector3.zero());
      final b = world.addBody(position: Vector3(0.0, 0.21, 0.0));
      world
        ..setShape(a, const NativeShape.sphere(0.1))
        ..setShape(b, const NativeShape.sphere(0.1))
        ..step(1e-9);
      // A centimetre apart, inside the default two-centimetre margin.
      expect(world.readContacts().single.depth, closeTo(-0.01, 1e-6));
      world
        ..contactMargin = 0.0
        ..step(1e-9);
      expect(world.readContacts(), isEmpty);
      world
        ..contactMargin = 0.02
        ..setCollisionFilter(a, layer: 1 << 1, mask: ~(1 << 2))
        ..setCollisionFilter(b, layer: 1 << 2, mask: ~0)
        ..step(1e-9);
      expect(world.readContacts(), isEmpty);
      expect(() => world.contactMargin = -1.0, throwsArgumentError);
    },
  );

  test('heat crosses a contact, and a hot plate keeps its heat', () {
    final steel = NativeMaterial.steel();
    final plate = world.addBody(
      position: Vector3(0.0, -0.5, 0.0),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    final block = world.addBody(position: Vector3(0.0, 0.099, 0.0));
    world
      ..setShape(plate, NativeShape.box(Vector3(1.0, 0.5, 1.0)))
      ..setShape(block, NativeShape.box(Vector3.all(0.1)))
      ..setMaterial(plate, steel)
      ..setMaterial(block, steel)
      ..setTemperature(plate, 500.0);
    // About forty seconds to warm: 490 J/K through Holm's 11 W/K.
    for (var i = 0; i < 1200; i++) {
      world.step(0.1);
    }
    expect(world.temperatureOf(plate), 500.0);
    expect(world.temperatureOf(block), greaterThan(400.0));
    expect(steel.conductivity, 50.0);
  });

  test('a box query finds what the tree holds, in slot order', () {
    // Mutation: return the leaves in the order the tree walks them, in
    // `found_one` — the answer depends on the tree's shape.
    final balls = <NativeBody>[
      for (var i = 0; i < 100; i++)
        world.addBody(position: Vector3((i % 10) * 2.0, 0.0, (i ~/ 10) * 2.0)),
    ];
    for (final b in balls) {
      world.setShape(b, const NativeShape.sphere(0.5));
    }
    world.addBody(position: Vector3.zero()); // A point: never found.
    expect(
      world.queryBox(Vector3(-1.0, -1.0, -1.0), Vector3(2.6, 1.0, 2.6)),
      <NativeBody>[balls[0], balls[1], balls[10], balls[11]],
    );
    expect(
      world.queryBox(Vector3(-100.0, -1.0, -100.0), Vector3(100.0, 1.0, 100.0)),
      balls,
    );
    expect(world.queryBox(Vector3.all(50.0), Vector3.all(51.0)), isEmpty);
  });

  test('cylinders, cones and hulls stand on a floor, through the binding', () {
    // The C tests hold GJK, EPA and the manifolds against the closed forms;
    // this holds what a game reads: each shape at rest at its own height.
    final floor = world.addBody(
      position: Vector3(0.0, -0.5, 0.0),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    world
      ..setShape(floor, NativeShape.box(Vector3(20.0, 0.5, 20.0)))
      ..setSleep(speed: 0.05, time: 0.5)
      ..gravity = Vector3(0.0, -9.81, 0.0);
    final hull = world.createHull(<Vector3>[
      for (var i = 0; i < 8; i++)
        Vector3(
          5.0 + ((i & 1) != 0 ? 0.5 : -0.5),
          (i & 2) != 0 ? 0.5 : -0.5,
          (i & 4) != 0 ? 0.5 : -0.5,
        ),
      Vector3(5.0, 0.0, 0.0), // Inside: not a corner.
    ]);
    expect(world.hullVertexCount(hull), 8);
    expect(world.hullOffset(hull).x, closeTo(5.0, 1e-6));
    final cylinder = world.addBody(position: Vector3(0.0, 1.01, 0.0));
    final cone = world.addBody(position: Vector3(3.0, 0.26, 0.0));
    final cube = world.addBody(position: Vector3(-3.0, 0.51, 0.0));
    final rounded = world.addBody(position: Vector3(6.0, 0.51, 0.0));
    world
      ..setShape(cylinder, const NativeShape.cylinder(0.3, 1.0))
      ..setShape(cone, const NativeShape.cone(0.4, 1.0))
      ..setHull(cube, hull)
      ..setShape(rounded, NativeShape.box(Vector3.all(0.4)))
      ..setRounding(rounded, 0.1);
    for (var i = 0; i < 240; i++) {
      world.step(1.0 / 60.0);
    }
    for (final (body, height) in <(NativeBody, double)>[
      (cylinder, 1.0),
      (cone, 0.25),
      (cube, 0.5),
      (rounded, 0.5),
    ]) {
      expect(world.positionOf(body).y, closeTo(height, 0.01));
      expect(world.isAsleep(body), isTrue);
    }
    expect(world.inertiaTensorOf(cube).entry(0, 1), closeTo(0.0, 1e-6));
    expect(
      () => world.createHull(<Vector3>[Vector3.zero(), Vector3(1.0, 0.0, 0.0)]),
      throwsArgumentError,
    );
  });
}
