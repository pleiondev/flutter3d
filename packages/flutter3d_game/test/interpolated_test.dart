import 'dart:math' as math;

import 'package:flutter3d_game/src/loop/interpolated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('InterpolatedVector3', () {
    late InterpolatedVector3 value;
    late Vector3 out;

    setUp(() {
      value = InterpolatedVector3();
      out = Vector3.zero();
    });

    test('reads the midpoint at half a step', () {
      value.push(Vector3(10.0, 0.0, 0.0));
      value.read(0.5, out);

      expect(out.x, closeTo(5.0, 1e-9));
    });

    test('reads the previous state at the start of a step', () {
      value.push(Vector3(10.0, 0.0, 0.0));
      value.read(0.0, out);

      expect(out.x, closeTo(0.0, 1e-9));
    });

    test('reads the current state at the end of a step', () {
      value.push(Vector3(10.0, 0.0, 0.0));
      value.read(1.0, out);

      expect(out.x, closeTo(10.0, 1e-9));
    });

    test('the simulation sees the authoritative value, not a blend', () {
      // Collision, AI and damage must all agree on one position. The
      // interpolated one exists only between two of them.
      value.push(Vector3(10.0, 0.0, 0.0));

      expect(value.current.x, 10.0);
    });

    test('successive pushes leave only the last two states', () {
      value.push(Vector3(1.0, 0.0, 0.0));
      value.push(Vector3(2.0, 0.0, 0.0));
      value.read(0.0, out);

      expect(out.x, closeTo(1.0, 1e-9));
    });

    test('a teleport shows no motion', () {
      // Pushing a distant value instead would smear the object across the level
      // for one frame.
      value.push(Vector3(1.0, 0.0, 0.0));
      value.jumpTo(Vector3(500.0, 0.0, 0.0));
      value.read(0.5, out);

      expect(out.x, closeTo(500.0, 1e-9));
    });

    test('an out-of-range alpha does not extrapolate', () {
      value.push(Vector3(10.0, 0.0, 0.0));

      value.read(2.0, out);
      expect(out.x, closeTo(10.0, 1e-9));

      value.read(-1.0, out);
      expect(out.x, closeTo(0.0, 1e-9));
    });

    test('reading does not disturb the stored states', () {
      value.push(Vector3(10.0, 0.0, 0.0));
      value.read(0.5, out);
      value.read(0.5, out);

      expect(out.x, closeTo(5.0, 1e-9));
    });

    test('the caller cannot alias the stored value through the argument', () {
      final source = Vector3(1.0, 2.0, 3.0);
      value.push(source);
      source.setValues(99.0, 99.0, 99.0);

      expect(value.current.x, 1.0);
    });
  });

  group('step smoothing', () {
    const dt = 1.0 / 60.0;
    const riser = 0.3;

    /// A `Vector3` is single precision, so a height that has been through one
    /// comes back a hundredth of a micrometre out. Comparisons of a *drawn*
    /// height to one still in a `double` want this rather than `1e-9`.
    const stored = 1e-6;

    /// The drawn height at the end of the step just pushed.
    double drawn(InterpolatedVector3 value, [double alpha = 1.0]) {
      final out = Vector3.zero();
      value.read(alpha, out);
      return out.y;
    }

    /// Walks [value] along the flat, climbing one riser at step [climbAt].
    ///
    /// Returns the drawn height after every step, which is what a display at
    /// the simulation's own rate would show.
    List<double> climb(
      InterpolatedVector3 value, {
      int steps = 60,
      int climbAt = 5,
    }) {
      final at = Vector3.zero();
      final seen = <double>[];
      for (var i = 0; i < steps; i++) {
        final stepped = i == climbAt ? riser : 0.0;
        at
          ..x += 4.0 * dt
          ..y += stepped;
        value.push(at, dt: dt, steppedUp: stepped);
        seen.add(drawn(value));
      }
      return seen;
    }

    test('is off unless a limit is given', () {
      // The dungeon's camera runs through this class and must not acquire a
      // vertical lag because a platformer wanted one.
      final plain = InterpolatedVector3();
      final heights = climb(plain);

      expect(heights.last, closeTo(riser, stored));
      expect(
        heights.reduce(math.max) - heights.reduce(math.min),
        closeTo(riser, stored),
      );
    });

    test('a climbed riser is held back and then given back', () {
      final smoothed = InterpolatedVector3(stepLimit: 0.4);
      final heights = climb(smoothed);

      // Held back: the step the climb happened on shows almost none of it.
      expect(heights[5], lessThan(riser * 0.2));
      // Given back: half a second later the picture has caught up.
      expect(heights.last, closeTo(riser, 1e-3));
      // And the authoritative value never moved.
      expect(smoothed.current.y, closeTo(riser, stored));
    });

    test('the picture never jumps, at the riser or anywhere else', () {
      // **This is the claim the two stored offsets exist for.** Subtracting one
      // offset from the blended result drops the drawn body by the whole riser
      // at the instant it is climbed, which is the jerk this removes, one frame
      // earlier. Mutate to a single offset and this fails at step five.
      final smoothed = InterpolatedVector3(stepLimit: 0.4);
      final at = Vector3.zero();
      var previous = drawn(smoothed);

      for (var i = 0; i < 60; i++) {
        final stepped = i == 5 ? riser : 0.0;
        at.y += stepped;
        // The end of the step about to be replaced is the start of the next
        // one: a display reads both, a frame apart.
        expect(drawn(smoothed), closeTo(previous, 1e-9));
        smoothed.push(at, dt: dt, steppedUp: stepped);
        expect(drawn(smoothed, 0.0), closeTo(previous, 1e-9));
        previous = drawn(smoothed);
      }
    });

    test('the drawn climb is slower than the teleport by an order', () {
      // The number that matters: a riser of 0.3 m inside one step is 18 m/s,
      // and it is the camera following this that pitches the horizon.
      final smoothed = InterpolatedVector3(stepLimit: 0.4);
      final plain = InterpolatedVector3();

      double fastest(List<double> heights) {
        var most = 0.0;
        for (var i = 1; i < heights.length; i++) {
          most = math.max(most, (heights[i] - heights[i - 1]) / dt);
        }
        return most;
      }

      final smoothly = fastest(climb(smoothed));
      final rawly = fastest(climb(plain));

      expect(rawly, closeTo(riser / dt, 1e-6));
      expect(smoothly, lessThan(rawly / 5.0));
    });

    test('a body carried upward is drawn where it is', () {
      // **The regression that decided the shape of this.** A lift moves its
      // passenger by writing the body's position, so a rise inferred from the
      // position alone reads a lift as a stair: the offset accumulates to the
      // clamp and the runner is drawn a fifth of a metre inside the floor for
      // the whole ascent. Nothing is reported, so nothing is held back.
      final smoothed = InterpolatedVector3(stepLimit: 0.4);
      final at = Vector3.zero();

      for (var i = 0; i < 120; i++) {
        at.y += 2.0 * dt;
        smoothed.push(at, dt: dt);
      }

      expect(drawn(smoothed), closeTo(at.y, 1e-9));
    });

    test('a staircase climbed at speed lags by at most one riser', () {
      final smoothed = InterpolatedVector3(stepLimit: 0.4);
      final at = Vector3.zero();
      var worst = 0.0;

      // A riser every three steps is faster than any body climbs, which is the
      // point: the clamp is what stops the drawn feet sinking through a stair.
      for (var i = 0; i < 180; i++) {
        final stepped = i % 3 == 0 ? 0.4 : 0.0;
        at.y += stepped;
        smoothed.push(at, dt: dt, steppedUp: stepped);
        worst = math.max(worst, at.y - drawn(smoothed));
      }

      // Sixty risers of single-precision arithmetic, so the slack is the
      // storage rather than the clamp.
      expect(worst, lessThanOrEqualTo(0.4 + 1e-4));
    });

    test('a respawn shows no held-back climb', () {
      // A death mid-stair otherwise revives the runner buried in the floor.
      final smoothed = InterpolatedVector3(stepLimit: 0.4);
      smoothed.push(Vector3(0.0, riser, 0.0), dt: dt, steppedUp: riser);
      smoothed.jumpTo(Vector3(0.0, 12.0, 0.0));

      expect(drawn(smoothed, 0.5), closeTo(12.0, 1e-9));
    });
  });

  group('InterpolatedAngle', () {
    test('reads the midpoint at half a step', () {
      final angle = InterpolatedAngle(0.0);
      angle.push(1.0);

      expect(angle.read(0.5), closeTo(0.5, 1e-9));
    });

    test('takes the short way round the wrap point', () {
      // A monster turning to face the player crosses this constantly. A plain
      // lerp from +3.1 to -3.1 spins it almost all the way round the wrong way.
      final angle = InterpolatedAngle(3.1);
      angle.push(-3.1);

      final midpoint = angle.read(0.5);
      final distanceFromPi = (midpoint.abs() - math.pi).abs();

      // The short path passes through pi, not through zero.
      expect(distanceFromPi, lessThan(0.05));
    });

    test('a small turn is unaffected by the wrap handling', () {
      final angle = InterpolatedAngle(0.1);
      angle.push(0.2);

      expect(angle.read(0.5), closeTo(0.15, 1e-9));
    });

    test('half a turn is not flipped arbitrarily', () {
      final angle = InterpolatedAngle(0.0);
      angle.push(math.pi);

      expect(angle.read(1.0).abs(), closeTo(math.pi, 1e-9));
    });

    test('a teleport shows no rotation', () {
      final angle = InterpolatedAngle(0.0);
      angle.push(1.0);
      angle.jumpTo(3.0);

      expect(angle.read(0.5), closeTo(3.0, 1e-9));
    });

    test('an out-of-range alpha does not extrapolate', () {
      final angle = InterpolatedAngle(0.0);
      angle.push(1.0);

      expect(angle.read(5.0), closeTo(1.0, 1e-9));
      expect(angle.read(-5.0), closeTo(0.0, 1e-9));
    });
  });
}
