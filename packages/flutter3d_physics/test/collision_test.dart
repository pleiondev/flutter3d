import 'dart:typed_data';

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

    test('a body resting exactly on a face is touching it, not inside it', () {
      // **The difference is float noise, and reading it as "inside" costs a
      // landing.** A body put exactly on a surface reads as some tens of
      // nanometres *under* it, because the surface's coordinates went through a
      // single-precision vector on the way and the body's arithmetic did not.
      // Answering "no contact" there lets the next sixtieth of a second of
      // gravity carry it properly inside, where the answer is honestly no
      // contact — and the fall never ends. It was found as a runner hovering
      // seven millimetres under a conveyor belt for ever, neither standing on
      // it nor falling off it.
      //
      // **The numbers are the belt's, and they have to be.** A first version of
      // this used a wall at whole coordinates, where the boundary lands on an
      // exactly representable number, there is no noise to swallow and the test
      // passed with the tolerance deleted.
      world.clear();
      world.addBox(Vector3(0.0, 0.2, 0.0), Vector3(8.0, 0.4, 20.0));
      world.update();

      final hit = SweepHit();
      final shape = CollisionBox(Vector3(0.35, 0.9, 0.35));
      // The belt's top is 0.4 and the body is 0.9 from its centre to its feet,
      // so this is exactly resting on it — in double precision, and a hair
      // inside it in the world's own.
      final found = world.sweep(
        shape,
        Vector3(0.0, 1.3, 0.0),
        Vector3(0.0, -0.0067, 0.0),
        hit,
      );

      expect(
        found,
        isTrue,
        reason: 'a body standing on a belt was told there was no belt',
      );
      expect(hit.fraction, 0.0);
      expect(hit.normal.y, closeTo(1.0, 1e-6));
    });

    test('and a body properly inside still is not, at a thousand times that', () {
      // The slack is a micrometre, and the rule it must not swallow is the one
      // two tests above: a body that really is inside has to be free to move
      // out. A millimetre in is a thousand times the slack, and is exactly the
      // clearance every contact backs off by.
      world.clear();
      world.addBox(Vector3(0.0, 0.2, 0.0), Vector3(8.0, 0.4, 20.0));
      world.update();

      final hit = SweepHit();
      final shape = CollisionBox(Vector3(0.35, 0.9, 0.35));

      expect(
        world.sweep(
          shape,
          Vector3(0.0, 1.3 - 1e-3, 0.0),
          Vector3(0.0, -0.0067, 0.0),
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

  group('the planes a shape offers', () {
    // **Every sweep and every push in the world goes through this**, and it is
    // abstract so that a shape which is not a box cannot behave like one by
    // saying nothing. Before it, the world reached past the shape for
    // `Collider.bounds` and no test could tell the difference.
    final planes = Float64List(CollisionShape.boundsPlaneCount * 4);

    /// The offset of the plane whose normal is [normal].
    double offsetOf(int count, Vector3 normal) {
      for (var i = 0; i < count; i++) {
        final base = i * 4;
        if (planes[base] == normal.x &&
            planes[base + 1] == normal.y &&
            planes[base + 2] == normal.z) {
          return planes[base + 3];
        }
      }
      fail('no face pointing $normal');
    }

    test('are the shape grown by whatever is being swept against it', () {
      // The Minkowski sum, in closed form: a box against a box is a *point*
      // against the first grown by the second's half-extents, which is what
      // makes the sweep analytic instead of a solver.
      final box = CollisionBox(Vector3(1.0, 2.0, 3.0));
      final count = box.expandedPlanes(
        Vector3(10.0, 0.0, 0.0),
        Vector3(0.5, 0.5, 0.5),
        planes,
      );

      expect(count, 6);
      expect(offsetOf(count, Vector3(1.0, 0.0, 0.0)), closeTo(11.5, 1e-9));
      // The low face's normal points out the other way, so its offset is the
      // negated coordinate.
      expect(offsetOf(count, Vector3(-1.0, 0.0, 0.0)), closeTo(-8.5, 1e-9));
      expect(offsetOf(count, Vector3(0.0, 1.0, 0.0)), closeTo(2.5, 1e-9));
      expect(offsetOf(count, Vector3(0.0, 0.0, 1.0)), closeTo(3.5, 1e-9));
    });

    test('and nothing is swept by a face the shape did not offer', () {
      // A sphere and a capsule both answer with their bounding box today, and
      // the point of the method is that they answer at all. If one of them ever
      // stops, this is the test that says what changed.
      final sphere = CollisionSphere(2.0);
      final capsule = CollisionCapsule(radius: 0.5, halfHeight: 1.0);
      final zero = Vector3.zero();
      final none = Vector3.zero();

      expect(sphere.expandedPlanes(zero, none, planes), 6);
      expect(offsetOf(6, Vector3(0.0, 1.0, 0.0)), closeTo(2.0, 1e-9));

      expect(capsule.expandedPlanes(zero, none, planes), 6);
      expect(
        offsetOf(6, Vector3(0.0, 1.0, 0.0)),
        closeTo(1.5, 1e-9),
        reason: 'a capsule is as tall as its caps reach',
      );
      expect(offsetOf(6, Vector3(1.0, 0.0, 0.0)), closeTo(0.5, 1e-9));
    });
  });

  group('depenetration', () {
    test('pushes out the nearest face, not the narrowest part of the body', () {
      // **A body deep inside a wide floor used to be shoved sideways.** The old
      // form measured the *overlap* of two boxes per axis, and when the brush
      // is wider than the body — every floor in every level — the horizontal
      // overlap is the body's own width and stops growing. Sink a body further
      // in than it is wide and the shallowest-looking axis became a horizontal
      // one, so the way out of a floor was out of its side.
      //
      // A face is the honest measure: how far to travel along the normal to
      // leave through it. Mutation: take the shallowest overlap instead and
      // this pushes sideways by 0.5.
      final world = CollisionWorld();
      world.addBox(Vector3.zero(), Vector3(20.0, 4.0, 20.0));

      final correction = Vector3.zero();
      // Half a metre wide, sunk 1.4 m into a slab whose top is at y = 2.
      final corrected = world.depenetrate(
        Vector3(0.0, 1.1, 0.0),
        Vector3.all(0.5),
        correction,
      );

      expect(corrected, isTrue);
      expect(correction.y, closeTo(1.4, 1e-6));
      expect(correction.x, 0.0);
      expect(correction.z, 0.0);
    });

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

    test('a body on the seam between two floors is lifted once, not twice', () {
      // **The most ordinary situation there is, and it was double-counted.**
      // Every floor in every level is a row of brushes, and a body standing on
      // the seam overlaps two of them — by the same amount, upwards, for the
      // same reason. `out.y += push` once per collider lifted it by the sum.
      //
      // It went unnoticed for the reason small errors do: it is always upward
      // and always small, so it reads as a body sitting a little high rather
      // than as a bug.
      //
      // Mutation: restore `+=` per collider. The correction doubles.
      final world = CollisionWorld();
      world.addBox(Vector3(-5.0, 0.0, 0.0), Vector3(10.0, 1.0, 10.0));
      world.addBox(Vector3(5.0, 0.0, 0.0), Vector3(10.0, 1.0, 10.0));

      // Straddling x = 0, sunk 0.1 m into both.
      final correction = Vector3.zero();
      final corrected = world.depenetrate(
        Vector3(0.0, 0.9, 0.0),
        Vector3.all(0.5),
        correction,
      );

      expect(corrected, isTrue);
      expect(
        correction.y,
        closeTo(0.1, 1e-6),
        reason: 'lifted ${correction.y} m out of a 0.1 m overlap',
      );
    });

    test('and it is lifted the deeper of two unequal overlaps, either order', () {
      // The other half of "deepest, not sum": two floors at different heights,
      // and the answer is the one that actually clears both.
      //
      // **On both sides, and that is the point.** With the deeper floor to the
      // east it is visited last, and an implementation that simply keeps
      // whichever push it saw most recently gives the same answer — so that
      // version of this test passed against exactly the mutation it was written
      // for. The grid walks cells in order, so which floor is *visited* first
      // is decided by where it stands, not by when it was added.
      double liftedWithDeeper({required bool west}) {
        final world = CollisionWorld();
        world.addBox(
          Vector3(-5.0, west ? 0.1 : 0.0, 0.0),
          Vector3(10.0, 1.0, 10.0),
        );
        world.addBox(
          Vector3(5.0, west ? 0.0 : 0.1, 0.0),
          Vector3(10.0, 1.0, 10.0),
        );

        final correction = Vector3.zero();
        world.depenetrate(Vector3(0.0, 0.9, 0.0), Vector3.all(0.5), correction);
        return correction.y;
      }

      expect(
        liftedWithDeeper(west: false),
        closeTo(0.2, 1e-6),
        reason: 'the taller floor needs 0.2 m',
      );
      expect(
        liftedWithDeeper(west: true),
        closeTo(0.2, 1e-6),
        reason:
            'the answer changed with which side the taller floor is on, '
            'so it is keeping the last push rather than the deepest',
      );
    });

    test('but opposing pushes still both count', () {
      // **Not an oversight, and the crushing test caught it.** Written as "only
      // what is still needed along this normal", the second of two opposing
      // pushes overwrites the first — so a body being closed on by a platform
      // is resolved as whichever face spoke last, and goes through the floor.
      //
      // A body told two different things gets the net of them.
      //
      // Mutation: keep only the deepest push of the six regardless of
      // direction, or resolve by projection. The correction stops being a
      // difference and this fails.
      final world = CollisionWorld();
      world.addBox(Vector3(0.0, 0.0, 0.0), Vector3(10.0, 1.0, 10.0));
      world.addBox(Vector3(0.0, 2.5, 0.0), Vector3(10.0, 1.0, 10.0));

      // Squeezed: 0.2 m up out of the floor below, 0.1 m down out of the
      // ceiling above, so the net is a tenth upward.
      final correction = Vector3.zero();
      world.depenetrate(
        Vector3(0.0, 1.2, 0.0),
        Vector3(0.5, 0.9, 0.5),
        correction,
      );

      expect(
        correction.y,
        closeTo(0.1, 1e-6),
        reason: 'the two faces did not net out: ${correction.y}',
      );
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

  group('exactly touching', () {
    // **Found by mutating the comparisons and watching nothing fail.** Every
    // overlap test here asks about a clear overlap and a clear gap, so the one
    // case the code has to *decide* — the surfaces exactly meeting — was
    // whatever the operator happened to be. It is a decision either way, and an
    // undecided one turns into a body resting on a floor that alternately does
    // and does not hold it.
    //
    // The answer is "not overlapping": a contact needs depth to resolve, and a
    // zero-depth contact resolves to a zero-length push, which the solver reads
    // as a body that is stuck.
    test('two capsules exactly a radius apart do not overlap', () {
      final a = CollisionCapsule(radius: 0.5, halfHeight: 1.0);
      final b = CollisionCapsule(radius: 0.5, halfHeight: 1.0);

      expect(
        a.overlaps(Vector3.zero(), b, Vector3(1.0, 0.0, 0.0)),
        isFalse,
        reason: 'surfaces meeting exactly counted as an overlap',
      );
      expect(a.overlaps(Vector3.zero(), b, Vector3(0.999, 0.0, 0.0)), isTrue);
    });

    test('and a sphere exactly touching a box does not either', () {
      final sphere = CollisionSphere(0.5);
      final box = CollisionBox(Vector3(1.0, 1.0, 1.0));

      expect(
        sphere.overlaps(Vector3(1.5, 0.0, 0.0), box, Vector3.zero()),
        isFalse,
      );
      expect(
        sphere.overlaps(Vector3(1.49, 0.0, 0.0), box, Vector3.zero()),
        isTrue,
      );
    });
  });
}
