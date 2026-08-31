/// The fourth shape, and the first one that is not a box.
///
///     flutter test test/wedge_test.dart
///
/// **This is the shape the gate was built for.** While `CollisionWorld` moved
/// bodies by reading `Collider.bounds`, a wedge added here would have collided
/// as its own bounding box — a ramp you cannot walk up and can stand on top of
/// — and no test could have told, because every shape reported the same six
/// faces. `CollisionShape.expandedPlanes` is abstract so that this class has to
/// answer, and these tests are what its answer is worth.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// Half the player: 0.7 m across, 1.8 m tall.
final Vector3 _playerHalf = Vector3(0.35, 0.9, 0.35);

CollisionWorld _floor() {
  final world = CollisionWorld();
  world.addBox(Vector3(0.0, -0.5, 0.0), Vector3(60.0, 1.0, 60.0));
  return world;
}

CharacterController _player(CollisionWorld world, Vector3 at) =>
    CharacterController(
      world: world,
      shape: CollisionBox(_playerHalf),
      position: at,
    );

void _walk(CharacterController player, int steps, {Vector3? direction}) {
  final wish = direction ?? Vector3.zero();
  for (var i = 0; i < steps; i++) {
    player.step(_dt, wishDirection: wish);
    player.world.update();
  }
}

void main() {
  group('the faces a wedge offers', () {
    final planes = Float64List(20);

    double offsetOf(int count, Vector3 normal) {
      for (var i = 0; i < count; i++) {
        final base = i * 4;
        if ((planes[base] - normal.x).abs() < 1e-9 &&
            (planes[base + 1] - normal.y).abs() < 1e-9 &&
            (planes[base + 2] - normal.z).abs() < 1e-9) {
          return planes[base + 3];
        }
      }
      fail('no face pointing $normal');
    }

    test('are five, because the low end is an edge and not a wall', () {
      // The whole difference between this and the box it is cut from. A sixth
      // face at the low end is a step you cannot walk onto.
      final wedge = CollisionWedge(Vector3(2.0, 1.0, 3.0));

      expect(wedge.expandedPlaneCount, 5);
      expect(
        wedge.expandedPlanes(Vector3.zero(), Vector3.zero(), planes),
        5,
      );
      expect(
        () => offsetOf(5, Vector3(-1.0, 0.0, 0.0)),
        throwsA(anything),
        reason: 'the low end has a face, so this is a box',
      );
    });

    test('and the slope is as steep as the wedge is proportioned', () {
      // No angle in the format: a ramp twice as long as it is tall is 26.6
      // degrees, and a level author reads that off the sizes they typed.
      final wedge = CollisionWedge(Vector3(2.0, 1.0, 3.0));
      final normal = wedge.slopeNormal;

      expect(wedge.gradient, closeTo(0.5, 1e-9));
      expect(math.atan2(1.0, 2.0) * 180.0 / math.pi, closeTo(26.565, 1e-3));
      // Pointing up and back down the hill.
      // Single precision on the way through a `Vector3`, so not `1e-9`.
      expect(normal.y, closeTo(2.0 / math.sqrt(5.0), 1e-6));
      expect(normal.x, closeTo(-1.0 / math.sqrt(5.0), 1e-6));
      expect(normal.z, 0.0);
      expect(normal.length, closeTo(1.0, 1e-6));
    });

    test('the slope passes through the centre, whichever way it climbs', () {
      // Which is what makes the steepness readable, and what makes a wedge and
      // its mirror image fill the box between them.
      for (final uphill in WedgeUphill.values) {
        final wedge = CollisionWedge(Vector3(2.0, 1.0, 3.0), uphill: uphill);
        final at = Vector3(5.0, 7.0, -4.0);
        final count = wedge.expandedPlanes(at, Vector3.zero(), planes);
        final normal = wedge.slopeNormal;

        expect(
          offsetOf(count, normal),
          closeTo(normal.dot(at), 1e-6),
          reason: '$uphill does not cut its own centre',
        );
      }
    });

    test('and growing it by a body pushes every face out by that much', () {
      // The Minkowski sum in closed form, which is what makes a *box* against
      // this the same question as a *point* against this.
      final wedge = CollisionWedge(Vector3(2.0, 1.0, 3.0));
      final half = Vector3(0.35, 0.9, 0.35);
      final count = wedge.expandedPlanes(Vector3.zero(), half, planes);
      final normal = wedge.slopeNormal;

      expect(offsetOf(count, Vector3(0.0, -1.0, 0.0)), closeTo(1.0 + 0.9, 1e-6));
      expect(offsetOf(count, Vector3(1.0, 0.0, 0.0)), closeTo(2.0 + 0.35, 1e-6));
      expect(
        offsetOf(count, normal),
        closeTo((normal.x * half.x).abs() + (normal.y * half.y).abs(), 1e-6),
      );
    });
  });

  group('a ray against a ramp', () {
    test('meets the slope and is told which way it faces', () {
      // Exact, unlike the overlaps: a ray against a convex solid is the same
      // plane walk the sweep does. A shot that grazes a ramp hits the ramp.
      final wedge = CollisionWedge(Vector3(2.0, 1.0, 3.0));
      final normal = Vector3.zero();
      final distance = wedge.raycast(
        Vector3.zero(),
        Vector3(0.0, 5.0, 0.0),
        Vector3(0.0, -1.0, 0.0),
        10.0,
        normal,
      );

      // Straight down the middle: the surface is at the centre's height.
      expect(distance, closeTo(5.0, 1e-6));
      expect(normal.y, closeTo(wedge.slopeNormal.y, 1e-6));
      expect(normal.x, closeTo(wedge.slopeNormal.x, 1e-6));
    });

    test('and passes over the thin end, where a bounding box would stop it',
        () {
      // **The mutation that says this is not a box.** Above the tapering end
      // there is nothing; a bounding box would report a hit.
      final wedge = CollisionWedge(Vector3(2.0, 1.0, 3.0));
      final normal = Vector3.zero();

      final distance = wedge.raycast(
        Vector3.zero(),
        Vector3(-1.6, 5.0, 0.0),
        Vector3(0.0, -1.0, 0.0),
        5.5,
        normal,
      );

      expect(distance, lessThan(0.0),
          reason: 'hit something over the thin end, so this is a box');
    });
  });

  group('a body on a ramp', () {
    /// A ramp 8 m long and 2 m tall — a fourteen-degree climb — with its foot
    /// at z = 0 and its top at z = 8.
    late Collider ramp;
    CollisionWorld rampWorld({Vector3? half, WedgeUphill? uphill}) {
      final world = _floor();
      ramp = world.add(
        Collider(
          shape: CollisionWedge(
            half ?? Vector3(3.0, 1.0, 4.0),
            uphill: uphill ?? WedgeUphill.positiveZ,
          ),
          position: Vector3(0.0, 1.0, 4.0),
        ),
      );
      world.update();
      return world;
    }

    /// Walks [steps] and returns how high the body ever got.
    double climb(CharacterController player, Vector3 direction, int steps) {
      var highest = player.position.y;
      for (var i = 0; i < steps; i++) {
        player.step(_dt, wishDirection: direction);
        player.world.update();
        highest = math.max(highest, player.position.y);
      }
      return highest;
    }

    test('walks up it instead of into it', () {
      // The claim in one number: the body ends up above where it started, on
      // the way. A bounding box stops it dead at the near face, at the height
      // it began — and would fail on the height rather than on the distance,
      // because the box's own front is a wall.
      final world = rampWorld();
      final player = _player(world, Vector3(0.0, 0.9, -3.0));
      _walk(player, 30);
      final startY = player.position.y;

      // Sixty steps takes it to about the middle of the ramp. **Measured, not
      // assumed**: a first version of this walked for 180 and asserted the
      // height at the end, by which time the body was over the top, off the far
      // side and back on the floor at the height it started — a test that
      // failed while the ramp worked perfectly.
      final highest = climb(player, Vector3(0.0, 0.0, 1.0), 60);

      expect(player.position.z, greaterThan(1.5),
          reason: 'never got onto the ramp');
      expect(highest, greaterThan(startY + 0.4),
          reason: 'walked into the ramp instead of up it');
    });

    test('and gets to the top of it', () {
      final world = rampWorld();
      final player = _player(world, Vector3(0.0, 0.9, -3.0));
      _walk(player, 30);

      // The ramp's top is y = 2, so a body on it stands at 2.9.
      final highest = climb(player, Vector3(0.0, 0.0, 1.0), 150);

      expect(highest, greaterThan(2.8));
    });

    test('a ramp climbing the other way is climbed the other way', () {
      // Mutation: ignore `uphill` and this passes on one of the four.
      final world = rampWorld(uphill: WedgeUphill.negativeZ);
      final player = _player(world, Vector3(0.0, 0.9, 11.0));
      _walk(player, 30);

      final highest = climb(player, Vector3(0.0, 0.0, -1.0), 150);

      expect(highest, greaterThan(2.8));
    });

    test('and going the wrong way at it climbs nothing', () {
      // The thin end is an edge, not a step: approached from above the low end
      // there is a surface, but approached from *behind* the high end there is
      // a two-metre wall, and a wall is not climbed.
      final world = rampWorld();
      final player = _player(world, Vector3(0.0, 0.9, 11.0));
      _walk(player, 30);
      final startY = player.position.y;

      final highest = climb(player, Vector3(0.0, 0.0, -1.0), 150);

      expect(highest, lessThan(startY + 0.5),
          reason: 'climbed the back of the ramp, which is a wall');
    });

    test('walks up it rather than flying up it', () {
      // **A ramp was a ski jump.** Sliding along a slope puts the climb into
      // the velocity as well as the position, so the body ended every step
      // travelling upwards — and `_probeGround` reads upward speed as a jump,
      // so it was airborne the whole way and launched off the top. Measured
      // before: 0 grounded steps of the climb, and `velocity.y` pinned at
      // +1.05 m/s.
      //
      // Mutation: stop recording the climb in `_slide` and every assertion
      // below fails at once.
      final world = rampWorld();
      final player = _player(world, Vector3(0.0, 0.9, -3.0));
      _walk(player, 30);

      var airborne = 0;
      var fastest = 0.0;
      for (var i = 0; i < 100; i++) {
        player.step(_dt, wishDirection: Vector3(0.0, 0.0, 1.0));
        world.update();
        if (!player.isGrounded) airborne++;
        fastest = math.max(fastest, player.velocity.y);
      }

      expect(player.position.y, greaterThan(2.5), reason: 'never climbed');
      expect(airborne, 0, reason: 'left the ground while walking up a ramp');
      expect(fastest, lessThan(0.01),
          reason: 'the climb went into the velocity, so the top is a jump');
    });

    test('and too steep to stand on is too steep to climb', () {
      // Past `_walkableNormalY` — sixty degrees — a face stops being a floor.
      // Nothing new was written for this: the ground probe already refused a
      // normal that flat, and until there was a shape that could report one,
      // the refusal had never been reachable.
      final world = _floor();
      world.add(
        Collider(
          // Three and a half up over two along: sixty degrees and a bit.
          shape: CollisionWedge(
            Vector3(3.0, 3.5, 2.0),
            uphill: WedgeUphill.positiveZ,
          ),
          position: Vector3(0.0, 3.5, 2.0),
        ),
      );
      world.update();

      final player = _player(world, Vector3(0.0, 0.9, -3.0));
      _walk(player, 30);
      final startY = player.position.y;
      _walk(player, 150, direction: Vector3(0.0, 0.0, 1.0));

      expect(player.position.y, closeTo(startY, 0.05),
          reason: 'stood on a sixty-degree face');
    });

    test('and a body never ends up inside one', () {
      // The stop condition plan §4a named in advance, in its smallest form: a
      // wedge that lets a body through is a wedge to revert.
      final world = rampWorld();
      final random = math.Random(20260817);
      final wish = Vector3.zero();

      for (var run = 0; run < 200; run++) {
        final player = _player(
          world,
          Vector3(random.nextDouble() * 6.0 - 3.0, 3.0 + random.nextDouble(),
              random.nextDouble() * 12.0 - 2.0),
        );
        for (var i = 0; i < 90; i++) {
          wish.setValues(
            random.nextDouble() * 2.0 - 1.0,
            0.0,
            random.nextDouble() * 2.0 - 1.0,
          );
          player.step(_dt, wishDirection: wish, sprint: random.nextBool());
          world.update();
        }

        final inside = (ramp.shape as CollisionWedge)
            .containsPoint(ramp.position, player.position);
        expect(inside, isFalse,
            reason: 'run $run ended inside the ramp at ${player.position}');
      }
    });
  });
}
