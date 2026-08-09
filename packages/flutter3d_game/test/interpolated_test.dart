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
