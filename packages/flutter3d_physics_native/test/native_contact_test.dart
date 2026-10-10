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
      expect(reference.isTouching, isTrue);
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
    // Plain carbon steel's, as the catalogue (flutter3d_matter) gives it.
    expect(steel.conductivity, 60.5);
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

  test('a table of five boxes stands on its legs, and a ray finds a part, '
      'through the binding', () {
    // The C tests hold the mass, the manifolds and the snapshot; this holds
    // what a game reads: a compound built from parts, standing where its
    // legs put it, and seen by a ray only where it has a part.
    final floor = world.addBody(
      position: Vector3(0.0, -0.5, 0.0),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    world
      ..setShape(floor, NativeShape.box(Vector3(20.0, 0.5, 20.0)))
      ..setSleep(speed: 0.05, time: 0.5)
      ..gravity = Vector3(0.0, -9.81, 0.0);
    final table = world.createCompound(<NativeCompoundPart>[
      NativeCompoundPart(
        NativeShape.box(Vector3(0.6, 0.025, 0.4)),
        at: Vector3(0.0, 0.725, 0.0),
      ),
      for (final (x, z) in const <(double, double)>[
        (-0.55, -0.35),
        (0.55, -0.35),
        (-0.55, 0.35),
        (0.55, 0.35),
      ])
        NativeCompoundPart(
          NativeShape.box(Vector3(0.03, 0.35, 0.03)),
          at: Vector3(x, 0.35, z),
        ),
    ]);
    expect(world.compoundPartCount(table), 5);
    final lift = world.compoundOffset(table).y;
    expect(lift, greaterThan(0.35));
    expect(lift, lessThan(0.725));
    final body = world.addBody(
      position: Vector3(0.0, lift + 0.05, 0.0),
      mass: 20.0,
    );
    world.setCompound(body, table);
    for (var i = 0; i < 240; i++) {
      world.step(1.0 / 60.0);
    }
    // Mutation: the parts not moved by the offset — the table stands a
    // leg's length off, or sinks into the floor.
    expect(world.positionOf(body).y, closeTo(lift, 0.01));
    expect(world.isAsleep(body), isTrue);
    final top = world.rayCast(
      Vector3(0.0, 3.0, 0.0),
      Vector3(0.0, -1.0, 0.0),
      5.0,
    );
    expect(top?.body, body);
    expect(top!.point.y, closeTo(0.75, 0.01));
    // Under the top, between the legs: the floor, not the table.
    final under = world.rayCast(
      Vector3(0.0, 0.3, -2.0),
      Vector3(0.0, 0.0, 1.0),
      4.0,
    );
    expect(under, isNull);
    expect(
      () => world.createCompound(const <NativeCompoundPart>[]),
      throwsArgumentError,
    );
  });

  test('a crate and a ball rest on a mesh floor, through the binding', () {
    world
      ..gravity = Vector3(0.0, -9.81, 0.0)
      ..setSleep(speed: 0.05, time: 0.5);
    // Four by four squares, two triangles each, their vertices shared.
    final vertices = <Vector3>[
      for (var j = 0; j <= 4; j++)
        for (var i = 0; i <= 4; i++) Vector3(i - 2.0, 0.0, j - 2.0),
    ];
    final indices = <int>[
      for (var j = 0; j < 4; j++)
        for (var i = 0; i < 4; i++) ...<int>[
          j * 5 + i, (j + 1) * 5 + i + 1, j * 5 + i + 1, //
          j * 5 + i, (j + 1) * 5 + i, (j + 1) * 5 + i + 1,
        ],
    ];
    final mesh = world.createMesh(vertices, indices);
    expect(world.meshTriangleCount(mesh), 32);
    expect(world.meshInternalEdges(mesh), 40);
    final ground = world.addBody(
      position: Vector3.zero(),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    world.setMesh(ground, mesh);
    final crate = world.addBody(position: Vector3(0.5, 0.51, 0.5));
    final ball = world.addBody(position: Vector3(-1.0, 0.31, -1.0));
    world
      ..setShape(crate, NativeShape.box(Vector3.all(0.5)))
      ..setShape(ball, const NativeShape.sphere(0.3));
    for (var i = 0; i < 180; i++) {
      world.step(1.0 / 60.0);
    }
    expect(world.positionOf(crate).y, closeTo(0.5, 0.01));
    expect(world.positionOf(ball).y, closeTo(0.3, 0.01));
    expect(world.isAsleep(crate) && world.isAsleep(ball), isTrue);
    expect(
      () => world.setMesh(crate, mesh),
      throwsArgumentError,
      reason: 'a dynamic body cannot be a mesh',
    );
    expect(
      () => world.createMesh(vertices, <int>[0, 1, 99]),
      throwsArgumentError,
    );
  });

  test(
    'rays meet what flutter3d_physics\' rays meet, at the same distance',
    () {
      // Unturned balls and boxes, the shapes both worlds hold alike, and two
      // hundred rays: the same nearest body, a hundredth of a millimetre
      // apart.
      final reference = CollisionWorld();
      final pairs = <NativeBody, Collider>{};
      var seed = 7;
      double next() {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        return seed / 0x7fffffff;
      }

      for (var i = 0; i < 60; i++) {
        final at = Vector3(
          next() * 20 - 10,
          next() * 20 - 10,
          next() * 20 - 10,
        );
        final CollisionShape shape = i.isEven
            ? CollisionSphere(0.3 + next())
            : CollisionBox(Vector3(0.3 + next(), 0.3 + next(), 0.3 + next()));
        final body = world.addBody(position: at, type: NativeBodyType.fixed);
        world.setShape(body, native(shape));
        pairs[body] = reference.add(
          Collider(
            shape: shape,
            position: at.clone(),
            kind: ColliderKind.static,
          ),
        );
      }
      final hit = RayHit();
      var met = 0;
      for (var q = 0; q < 200; q++) {
        final origin = Vector3(
          next() * 30 - 15,
          next() * 30 - 15,
          next() * 30 - 15,
        );
        final direction = Vector3(next() - 0.5, next() - 0.5, next() - 0.5)
          ..normalize();
        final mine = world.rayCast(origin, direction, 40.0);
        final theirs = reference.raycast(origin, direction, 40.0, hit);
        // Neither sees a shape its ray starts inside, alike; a ray starting
        // inside one is left out of the comparison.
        if (world
            .overlapShape(const NativeShape.sphere(1e-4), origin)
            .isNotEmpty) {
          continue;
        }
        expect(mine != null, theirs, reason: 'ray $q');
        if (mine == null) continue;
        met++;
        expect(pairs[mine.body], same(hit.collider), reason: 'ray $q');
        expect(mine.at, closeTo(hit.distance, 1e-5), reason: 'ray $q');
        expect((mine.normal - hit.normal).length, lessThan(1e-4));
      }
      expect(met, greaterThan(10));
      // A cast and an overlap through the binding.
      final first = pairs.keys.first;
      final at = world.localPositionOf(first);
      expect(
        world.overlapShape(const NativeShape.sphere(0.01), at),
        contains(first),
      );
      final cast = world.castShape(
        const NativeShape.sphere(0.1),
        at + Vector3(0.0, 30.0, 0.0),
        Vector3(0.0, -40.0, 0.0),
      );
      expect(cast, isNotNull);
      expect(
        world.rayCastAll(
          at + Vector3(0.0, 30.0, 0.0),
          Vector3(0.0, -1.0, 0.0),
          60.0,
        ),
        isNotEmpty,
      );
    },
  );

  test('a character walks, slides along a wall and climbs a step', () {
    world.gravity = Vector3(0.0, -9.81, 0.0);
    final floor = world.addBody(
      position: Vector3(0.0, -0.5, 0.0),
      type: NativeBodyType.fixed,
    );
    final wall = world.addBody(
      position: Vector3(3.5, 5.0, 0.0),
      type: NativeBodyType.fixed,
    );
    final step = world.addBody(
      position: Vector3(0.0, 0.15, 5.0),
      type: NativeBodyType.fixed,
    );
    world
      ..setShape(floor, NativeShape.box(Vector3(50.0, 0.5, 50.0)))
      ..setShape(wall, NativeShape.box(Vector3(0.5, 5.0, 50.0)))
      ..setShape(step, NativeShape.box(Vector3(2.0, 0.15, 2.0)));
    var at = Vector3(0.0, 3.0, 0.0);
    var move = world.moveCharacter(
      shape: const NativeShape.capsule(0.3, 0.6),
      position: at,
      move: Vector3(0.0, -5.0, 0.0),
    );
    expect(move.grounded, isTrue);
    expect(move.ground, floor);
    expect(move.position.y, closeTo(0.91, 2e-3));
    move = world.moveCharacter(
      shape: const NativeShape.capsule(0.3, 0.6),
      position: move.position,
      move: Vector3(4.0, 0.0, 1.0),
    );
    expect(move.hitWall, isTrue);
    expect(move.position.x, closeTo(2.69, 2e-3));
    at = Vector3(0.0, move.position.y, 2.0);
    move = world.moveCharacter(
      shape: const NativeShape.capsule(0.3, 0.6),
      position: at,
      move: Vector3(0.0, 0.0, 2.0),
    );
    expect(move.stepped, isTrue);
    expect(move.ground, step);
    expect(move.position.y, closeTo(1.21, 3e-3));
    expect(move.hitCeiling, isFalse);
    expect(move.groundNormal.y, closeTo(1.0, 1e-4));
  });
}
