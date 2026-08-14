import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// Layer names for these tests, because the package deliberately has none.
///
/// The point of the extraction: a collision world cannot know what a monster
/// is, so "monster" is a bit a caller chose — here, a test. `Layers.all` is the
/// only constant the package keeps, because every bit means the same thing
/// everywhere.
abstract final class _Layer {
  static const int world = 1 << 0;
  static const int player = 1 << 1;
  static const int monster = 1 << 2;
  static const int trigger = 1 << 5;
}

/// Records what it was told, so a test can assert on the sequence.
final class _Recorder with CollisionListener {
  final List<String> events = <String>[];

  @override
  void onCollisionStart(Collider self, Collider other) =>
      events.add('start:${other.userData}');

  @override
  void onCollision(Collider self, Collider other) =>
      events.add('stay:${other.userData}');

  @override
  void onCollisionEnd(Collider self, Collider other) =>
      events.add('end:${other.userData}');
}

void main() {
  group('shape overlap is exact', () {
    test('two boxes touching face to face', () {
      final a = CollisionBox(Vector3.all(0.5));
      final b = CollisionBox(Vector3.all(0.5));

      expect(a.overlaps(Vector3.zero(), b, Vector3(0.9, 0.0, 0.0)), isTrue);
      expect(a.overlaps(Vector3.zero(), b, Vector3(1.1, 0.0, 0.0)), isFalse);
    });

    test('a sphere against a box corner, where a bounding box would lie', () {
      // The corner of a unit box is 0.866 from its centre, but only 0.707 away
      // along the diagonal from the face midpoints. A sphere placed just past
      // the corner overlaps the box's bounds and not the box.
      final box = CollisionBox(Vector3.all(0.5));
      final sphere = CollisionSphere(0.2);
      final justPastCorner = Vector3(0.65, 0.65, 0.0);

      expect(sphere.overlaps(justPastCorner, box, Vector3.zero()), isFalse);
      // Straight out from a face at the same distance, it does touch.
      expect(
        sphere.overlaps(Vector3(0.65, 0.0, 0.0), box, Vector3.zero()),
        isTrue,
      );
    });

    test('dispatch is symmetric whichever shape is asked', () {
      final box = CollisionBox(Vector3.all(0.5));
      final sphere = CollisionSphere(0.3);
      final at = Vector3(0.7, 0.0, 0.0);

      expect(
        sphere.overlaps(at, box, Vector3.zero()),
        box.overlaps(Vector3.zero(), sphere, at),
      );
    });

    test('a capsule reaches further than its centre section', () {
      final capsule = CollisionCapsule(radius: 0.3, halfHeight: 0.5);
      final box = CollisionBox(Vector3.all(0.5));

      // Level with the cylinder: the horizontal gap alone decides. The box
      // face is at x = 0.5 and the radius is 0.3, so 0.7 touches and 1.0 does
      // not.
      expect(
        capsule.overlaps(Vector3(0.7, 0.0, 0.0), box, Vector3.zero()),
        isTrue,
      );
      expect(
        capsule.overlaps(Vector3(1.0, 0.0, 0.0), box, Vector3.zero()),
        isFalse,
      );
      // Above the box entirely, by more than the cap radius.
      expect(
        capsule.overlaps(Vector3(0.0, 1.9, 0.0), box, Vector3.zero()),
        isFalse,
      );
      // Above by less: the cap still reaches down.
      expect(
        capsule.overlaps(Vector3(0.0, 1.2, 0.0), box, Vector3.zero()),
        isTrue,
      );
    });

    test('two capsules side by side', () {
      final a = CollisionCapsule(radius: 0.3, halfHeight: 0.5);
      final b = CollisionCapsule(radius: 0.3, halfHeight: 0.5);

      expect(a.overlaps(Vector3.zero(), b, Vector3(0.5, 0.0, 0.0)), isTrue);
      expect(a.overlaps(Vector3.zero(), b, Vector3(0.7, 0.0, 0.0)), isFalse);
      // Stacked far enough apart vertically that the caps miss.
      expect(a.overlaps(Vector3.zero(), b, Vector3(0.0, 1.7, 0.0)), isFalse);
    });

    test('a sphere inside a box counts as overlapping', () {
      final box = CollisionBox(Vector3.all(1.0));
      final sphere = CollisionSphere(0.1);

      expect(sphere.overlaps(Vector3.zero(), box, Vector3.zero()), isTrue);
    });
  });

  group('raycasting', () {
    late CollisionWorld world;

    setUp(() {
      world = CollisionWorld();
      world.addBox(Vector3(0.0, 0.0, -5.0), Vector3.all(2.0), userData: 'wall');
    });

    test('finds a box straight ahead and reports where', () {
      final hit = RayHit();
      final found = world.raycast(
        Vector3.zero(),
        Vector3(0.0, 0.0, -1.0),
        50.0,
        hit,
      );

      expect(found, isTrue);
      expect(hit.distance, closeTo(4.0, 1e-6));
      expect(hit.collider?.userData, 'wall');
      expect(hit.normal.z, closeTo(1.0, 1e-6));
    });

    test('misses when aimed past', () {
      final hit = RayHit();

      expect(
        world.raycast(Vector3.zero(), Vector3(1.0, 0.0, 0.0), 50.0, hit),
        isFalse,
      );
    });

    test('respects the maximum distance', () {
      final hit = RayHit();

      expect(
        world.raycast(Vector3.zero(), Vector3(0.0, 0.0, -1.0), 3.0, hit),
        isFalse,
      );
    });

    test('reports the nearest of several', () {
      world.addBox(Vector3(0.0, 0.0, -2.0), Vector3.all(0.5), userData: 'near');
      final hit = RayHit();
      world.raycast(Vector3.zero(), Vector3(0.0, 0.0, -1.0), 50.0, hit);

      expect(hit.collider?.userData, 'near');
    });

    test('a long diagonal ray still finds its target', () {
      // The grid walk is what this exercises: a diagonal crosses many cells,
      // and an implementation that only looked in the first or the last would
      // pass every other test in this group.
      world.clear();
      world.addBox(Vector3(40.0, 0.0, 40.0), Vector3.all(2.0), userData: 'far');

      final hit = RayHit();
      final direction = Vector3(1.0, 0.0, 1.0)..normalize();
      final found = world.raycast(Vector3.zero(), direction, 200.0, hit);

      expect(found, isTrue);
      expect(hit.collider?.userData, 'far');
    });

    test('a vertical ray does not spin the grid walk', () {
      world.clear();
      world.addBox(Vector3(0.0, -3.0, 0.0), Vector3.all(1.0), userData: 'down');

      final hit = RayHit();
      final found = world.raycast(
        Vector3.zero(),
        Vector3(0.0, -1.0, 0.0),
        10.0,
        hit,
      );

      expect(found, isTrue);
      expect(hit.collider?.userData, 'down');
    });

    test('triggers are invisible to a shot unless asked for', () {
      world.clear();
      world.add(
        Collider(
          shape: CollisionBox(Vector3.all(1.0)),
          position: Vector3(0.0, 0.0, -3.0),
          kind: ColliderKind.trigger,
          userData: 'zone',
        ),
      );
      world.update();

      final hit = RayHit();
      expect(
        world.raycast(Vector3.zero(), Vector3(0.0, 0.0, -1.0), 50.0, hit),
        isFalse,
      );
      expect(
        world.raycast(
          Vector3.zero(),
          Vector3(0.0, 0.0, -1.0),
          50.0,
          hit,
          includeTriggers: true,
        ),
        isTrue,
      );
    });

    test('layers keep a shot from hitting the wrong thing', () {
      world.clear();
      world.add(
        Collider(
          shape: CollisionBox(Vector3.all(1.0)),
          position: Vector3(0.0, 0.0, -3.0),
          layer: _Layer.monster,
          userData: 'monster',
        ),
      );

      final hit = RayHit();
      expect(
        world.raycast(
          Vector3.zero(),
          Vector3(0.0, 0.0, -1.0),
          50.0,
          hit,
          mask: _Layer.world,
        ),
        isFalse,
      );
      expect(
        world.raycast(
          Vector3.zero(),
          Vector3(0.0, 0.0, -1.0),
          50.0,
          hit,
          mask: _Layer.monster,
        ),
        isTrue,
      );
    });
  });

  group('sweeping', () {
    late CollisionWorld world;

    setUp(() {
      world = CollisionWorld();
      // A wall in the plane z = -5, two units thick.
      world.addBox(Vector3(0.0, 0.0, -5.0), Vector3(20.0, 4.0, 2.0));
    });

    test('stops at the surface and reports the fraction', () {
      final hit = SweepHit();
      final shape = CollisionBox(Vector3.all(0.5));
      final found = world.sweep(
        shape,
        Vector3.zero(),
        Vector3(0.0, 0.0, -8.0),
        hit,
      );

      expect(found, isTrue);
      // Contact when the near face of the player meets the near face of the
      // wall: 4 units of gap less the player's half-depth, over 8 of travel.
      expect(hit.fraction, closeTo(3.5 / 8.0, 1e-6));
      expect(hit.normal.z, closeTo(1.0, 1e-6));
    });

    test('reports nothing when the motion falls short', () {
      final hit = SweepHit();
      final shape = CollisionBox(Vector3.all(0.5));

      expect(
        world.sweep(shape, Vector3.zero(), Vector3(0.0, 0.0, -1.0), hit),
        isFalse,
      );
    });

    test('a fast sweep cannot tunnel through a thin wall', () {
      // The whole reason movement is swept rather than stepped: at 60 Hz a
      // falling body covers metres per step.
      world.clear();
      world.addBox(Vector3.zero(), Vector3(10.0, 0.1, 10.0));

      final hit = SweepHit();
      final shape = CollisionBox(Vector3.all(0.2));
      final found = world.sweep(
        shape,
        Vector3(0.0, 5.0, 0.0),
        Vector3(0.0, -60.0, 0.0),
        hit,
      );

      expect(found, isTrue);
      expect(hit.normal.y, closeTo(1.0, 1e-6));
    });

    test('a body already inside is not blocked, so it can get out', () {
      final hit = SweepHit();
      final shape = CollisionBox(Vector3.all(0.5));

      expect(
        world.sweep(
          shape,
          Vector3(0.0, 0.0, -5.0),
          Vector3(0.0, 0.0, 8.0),
          hit,
        ),
        isFalse,
      );
    });

    test('triggers do not block movement', () {
      world.clear();
      world.add(
        Collider(
          shape: CollisionBox(Vector3.all(1.0)),
          position: Vector3(0.0, 0.0, -3.0),
          kind: ColliderKind.trigger,
        ),
      );
      world.update();

      final hit = SweepHit();
      final shape = CollisionBox(Vector3.all(0.5));

      expect(
        world.sweep(shape, Vector3.zero(), Vector3(0.0, 0.0, -8.0), hit),
        isFalse,
      );
    });
  });

  group('depenetration', () {
    test('pushes out along the shallowest axis', () {
      final world = CollisionWorld();
      world.addBox(Vector3.zero(), Vector3(10.0, 1.0, 10.0));

      // Sunk a little way into a wide, thin slab: up is much the shortest way.
      final correction = Vector3.zero();
      final corrected = world.depenetrate(
        Vector3(0.0, 0.9, 0.0),
        Vector3.all(0.5),
        correction,
      );

      expect(corrected, isTrue);
      expect(correction.y, greaterThan(0.0));
      expect(correction.x, 0.0);
      expect(correction.z, 0.0);
    });

    test('reports nothing when clear', () {
      final world = CollisionWorld();
      world.addBox(Vector3.zero(), Vector3.all(1.0));

      final correction = Vector3.zero();

      expect(
        world.depenetrate(Vector3(5.0, 0.0, 0.0), Vector3.all(0.5), correction),
        isFalse,
      );
    });
  });

  group('overlap events', () {
    late CollisionWorld world;
    late _Recorder recorder;
    late Collider walker;

    setUp(() {
      world = CollisionWorld();
      recorder = _Recorder();
      world.add(
        Collider(
          shape: CollisionBox(Vector3.all(1.0)),
          position: Vector3.zero(),
          kind: ColliderKind.trigger,
          layer: _Layer.trigger,
          userData: 'zone',
        ),
      );
      walker = world.add(
        Collider(
          shape: CollisionSphere(0.3),
          position: Vector3(10.0, 0.0, 0.0),
          kind: ColliderKind.kinematic,
          layer: _Layer.player,
          listener: recorder,
          userData: 'player',
        ),
      );
    });

    test('start fires once, then stay, then end', () {
      world.update();
      expect(recorder.events, isEmpty);

      walker.moveTo(Vector3.zero());
      world.update();
      expect(recorder.events, <String>['start:zone']);

      world.update();
      expect(recorder.events.last, 'stay:zone');

      walker.moveTo(Vector3(10.0, 0.0, 0.0));
      world.update();
      expect(recorder.events.last, 'end:zone');
    });

    test('a pair is reported once even when both sides listen', () {
      final other = _Recorder();
      world.add(
        Collider(
          shape: CollisionBox(Vector3.all(0.5)),
          position: Vector3.zero(),
          kind: ColliderKind.kinematic,
          layer: _Layer.monster,
          listener: other,
          userData: 'monster',
        ),
      );

      walker.moveTo(Vector3.zero());
      world.update();

      expect(
        recorder.events.where((String e) => e == 'start:monster'),
        hasLength(1),
      );
      expect(
        other.events.where((String e) => e == 'start:player'),
        hasLength(1),
      );
    });

    test('layers keep unrelated colliders from reporting each other', () {
      walker.mask = _Layer.world;
      walker.moveTo(Vector3.zero());
      world.update();

      expect(recorder.events, isEmpty);
    });

    test('an exact miss inside the bounding boxes fires nothing', () {
      // The zone's corner is at (1, 1, 0) and the sphere has radius 0.3. At
      // (1.25, 1.25, 0) the two bounding boxes overlap but the corner is 0.354
      // away, so nothing has actually touched. This is the case the exact test
      // exists for.
      walker.moveTo(Vector3(1.25, 1.25, 0.0));
      world.update();

      expect(recorder.events, isEmpty);

      // And a nudge inwards does touch, so the test is not passing by accident.
      walker.moveTo(Vector3(1.15, 1.15, 0.0));
      world.update();
      expect(recorder.events, <String>['start:zone']);
    });
  });

  group('the broadphase', () {
    test('a query costs the local density, not the level size', () {
      // Ten thousand brushes in a long line. If anything here were linear in
      // the total, this test would take a visible amount of time; the point is
      // that it does not.
      final world = CollisionWorld();
      for (var i = 0; i < 10000; i++) {
        world.addBox(Vector3(i * 4.0, 0.0, 0.0), Vector3.all(1.0));
      }

      final hit = SweepHit();
      final shape = CollisionBox(Vector3.all(0.4));
      final watch = Stopwatch()..start();
      for (var i = 0; i < 2000; i++) {
        world.sweep(
          shape,
          Vector3(20000.0, 0.0, 3.0),
          Vector3(0.0, 0.0, -6.0),
          hit,
        );
      }
      watch.stop();

      expect(world.staticCount, 10000);
      // Generous: the assertion is about the order of growth, and a linear scan
      // would be a thousand times over this.
      expect(watch.elapsedMilliseconds, lessThan(500));
    });

    test('a collider spanning several cells is found once, not many times', () {
      final world = CollisionWorld();
      // Twenty metres across a four-metre grid: five cells.
      world.addBox(Vector3.zero(), Vector3(20.0, 1.0, 20.0), userData: 'floor');

      final found = <Collider>[];
      world.overlap(CollisionBox(Vector3.all(0.5)), Vector3.zero(), found);

      expect(found, hasLength(1));
    });

    test('movers are indexed too, so they are found without a linear scan', () {
      final world = CollisionWorld();
      for (var i = 0; i < 500; i++) {
        world.add(
          Collider(
            shape: CollisionSphere(0.3),
            position: Vector3(i * 5.0, 0.0, 0.0),
            kind: ColliderKind.kinematic,
            userData: i,
          ),
        );
      }
      world.update();

      final found = <Collider>[];
      world.overlap(CollisionSphere(0.3), Vector3(250 * 5.0, 0.0, 0.0), found);

      expect(found, hasLength(1));
      expect(found.single.userData, 250);
    });
  });
}
