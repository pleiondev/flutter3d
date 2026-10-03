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

  test('a ball through a wall begins and ends one contact', () {
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
      ..setVelocity(ball, Vector3(1.0, 0.0, 0.0));
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
    // Nothing pushes them apart yet: it went right through.
    expect(deepest, greaterThan(0.1));
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
}
