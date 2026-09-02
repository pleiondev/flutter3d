import 'dart:math' as math;

import 'package:flutter3d_sim/src/math/spline.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A circle of [radius] as [count] evenly spaced control points, in the XZ
/// plane. The curve through them is the closest thing to a shape whose length
/// and curvature are known in advance.
CatmullRom circle({double radius = 50.0, int count = 16}) => CatmullRom([
  for (var i = 0; i < count; i++)
    Vector3(
      radius * math.cos(2 * math.pi * i / count),
      0.0,
      radius * math.sin(2 * math.pi * i / count),
    ),
]);

/// A long, narrow loop: two straights six metres apart joined at the ends.
///
/// The shape a track takes whenever a hairpin folds back beside the straight
/// that feeds it, and the one that breaks a nearest-point search that has no
/// memory of where the car was.
CatmullRom narrowLoop() => CatmullRom([
  Vector3(-100.0, 0.0, 3.0),
  Vector3(-50.0, 0.0, 3.0),
  Vector3(0.0, 0.0, 3.0),
  Vector3(50.0, 0.0, 3.0),
  Vector3(100.0, 0.0, 3.0),
  Vector3(103.0, 0.0, 0.0),
  Vector3(100.0, 0.0, -3.0),
  Vector3(50.0, 0.0, -3.0),
  Vector3(0.0, 0.0, -3.0),
  Vector3(-50.0, 0.0, -3.0),
  Vector3(-100.0, 0.0, -3.0),
  Vector3(-103.0, 0.0, 0.0),
]);

/// The shorter of the two ways round between two distances on a closed curve.
double gap(CatmullRom curve, double a, double b) {
  final raw = (curve.wrap(a) - curve.wrap(b)).abs();
  return math.min(raw, curve.length - raw);
}

void main() {
  group('measurement', () {
    test('the length of a circle is the circumference', () {
      // Mutation: sum the control point chords instead of the sampled ones. A
      // sixteen-sided polygon is two percent short of the circle it inscribes,
      // and every lap time inherits that error.
      final curve = circle();

      expect(
        curve.length,
        closeTo(2 * math.pi * 50.0, 2 * math.pi * 50.0 * 0.01),
      );
    });

    test('the curve passes through its control points', () {
      final curve = circle();
      final out = Vector3.zero();

      curve.sampleAt(0.0, out);

      expect(out.x, closeTo(50.0, 1e-9));
      expect(out.z, closeTo(0.0, 1e-9));
    });

    test('equal steps in metres are equal steps in space', () {
      // Mutation: return the raw segment parameter from `_toU` instead of
      // searching the measured table. The segments of this circle span ten
      // degrees at one end and seventy at the other, so the samples would bunch
      // up sevenfold at the tight end — an AI aiming "twelve metres ahead" would
      // be aiming at four, or at thirty.
      final curve = CatmullRom([
        for (final degrees in [
          0.0,
          10.0,
          20.0,
          90.0,
          180.0,
          200.0,
          270.0,
          350.0,
        ])
          Vector3(
            50 * math.cos(degrees * math.pi / 180),
            0.0,
            50 * math.sin(degrees * math.pi / 180),
          ),
      ]);

      final out = Vector3.zero();
      final next = Vector3.zero();
      var shortest = double.infinity;
      var longest = 0.0;
      const steps = 100;

      for (var i = 0; i < steps; i++) {
        curve
          ..sampleAt(curve.length * i / steps, out)
          ..sampleAt(curve.length * (i + 1) / steps, next);
        final chord = out.distanceTo(next);
        shortest = math.min(shortest, chord);
        longest = math.max(longest, chord);
      }

      expect(longest / shortest, lessThan(1.25));
    });

    test('curvature is the reciprocal of the radius', () {
      // Mutation: divide by the speed rather than its cube. Curvature would then
      // depend on how the curve happens to be parameterised, and an AI would
      // brake for corners that are not there.
      //
      // Measured densely on purpose. A Catmull-Rom curve is only C1, so its
      // curvature jumps at every control point and sags between them: through
      // sixteen points it reads twelve percent high at a knot and five percent
      // low mid-segment, and it converges on the true value as the points close
      // up. Sixty-four points is inside one percent, which is what a track built
      // from a generator will have.
      final curve = circle(count: 64);
      final segment = curve.length / 64;

      expect(curve.curvatureAt(0.0), closeTo(1 / 50.0, 1 / 50.0 * 0.01));
      expect(
        curve.curvatureAt(segment / 2),
        closeTo(1 / 50.0, 1 / 50.0 * 0.01),
      );
    });

    test('a straight has no curvature', () {
      final curve = CatmullRom([
        Vector3(0.0, 0.0, 0.0),
        Vector3(10.0, 0.0, 0.0),
        Vector3(20.0, 0.0, 0.0),
      ], closed: false);

      expect(curve.curvatureAt(10.0), closeTo(0.0, 1e-6));
    });

    test('the tangent is a unit vector pointing the way travelled', () {
      final curve = circle();
      final out = Vector3.zero();

      curve.tangentAt(0.0, out);

      expect(out.length, closeTo(1.0, 1e-9));
      // The points run anticlockwise from (50, 0, 0), so travel at the start is
      // towards +z.
      expect(out.z, closeTo(1.0, 0.02));
    });
  });

  group('wrapping', () {
    test('a distance past the end comes back round', () {
      final curve = circle();

      expect(curve.wrap(curve.length + 5.0), closeTo(5.0, 1e-9));
    });

    test('a distance before the start comes back round', () {
      // Mutation: `s - length * (s / length).floor()` looks equivalent and is,
      // but a plain `s.abs() % length` is not — reversing over the finish line
      // would read as most of a lap rather than a metre of it.
      final curve = circle();

      expect(curve.wrap(-5.0), closeTo(curve.length - 5.0, 1e-9));
    });

    test('an open curve clamps instead of wrapping', () {
      final curve = CatmullRom([
        Vector3.zero(),
        Vector3(10.0, 0.0, 0.0),
        Vector3(20.0, 0.0, 0.0),
      ], closed: false);

      expect(curve.wrap(-5.0), 0.0);
      expect(curve.wrap(curve.length + 5.0), curve.length);
    });

    test('sampling past the seam is continuous', () {
      final curve = circle();
      final before = Vector3.zero();
      final after = Vector3.zero();

      curve
        ..sampleAt(curve.length - 0.01, before)
        ..sampleAt(0.01, after);

      expect(before.distanceTo(after), lessThan(0.05));
    });
  });

  group('nearest point', () {
    test(
      'a windowed search agrees with a global one when nothing is nearby',
      () {
        // On a plain circle the two can only disagree if one of them is wrong.
        final curve = circle();
        final random = math.Random(7);
        final probe = Vector3.zero();

        for (var i = 0; i < 200; i++) {
          final angle = random.nextDouble() * 2 * math.pi;
          final radius = 40.0 + random.nextDouble() * 20.0;
          probe.setValues(
            radius * math.cos(angle),
            0.0,
            radius * math.sin(angle),
          );

          final global = curve.closestSGlobal(probe);
          final windowed = curve.closestS(probe, nearS: global, window: 20.0);

          expect(gap(curve, windowed, global), lessThan(0.05));
        }
      },
    );

    test('the window keeps the answer on the branch the car is on', () {
      // Mutation: ignore `nearS` and search the whole curve. This is the bug the
      // window exists for — the car is on the near straight, drifting wide, and
      // is momentarily closer to the far one. A global search teleports it two
      // hundred metres up the track for a frame, which reads as a finished lap.
      final curve = narrowLoop();

      final onNearStraight = curve.closestSGlobal(Vector3(0.0, 0.0, 3.0));
      // Four metres across from the near straight, so two metres from the far
      // one: nearest in space, wrong in every other sense.
      final driftedWide = Vector3(0.0, 0.0, -1.0);

      final global = curve.closestSGlobal(driftedWide);
      final windowed = curve.closestS(
        driftedWide,
        nearS: onNearStraight,
        window: 20.0,
      );

      expect(
        gap(curve, global, onNearStraight),
        greaterThan(100.0),
        reason: 'the far straight must really be the global answer',
      );
      expect(gap(curve, windowed, onNearStraight), lessThan(5.0));
    });

    test('a window that straddles the seam searches both sides of it', () {
      // Mutation: clamp the window to the ends of the table instead of letting it
      // run past and wrap. A car two metres before the finish line, asked about
      // from just after it, would be reported at the start line — the lap counter
      // would then see the line crossed twice.
      final curve = circle();
      final justBefore = Vector3.zero();
      curve.sampleAt(curve.length - 2.0, justBefore);

      final found = curve.closestS(justBefore, nearS: 1.0, window: 20.0);

      expect(gap(curve, found, curve.length - 2.0), lessThan(0.05));
    });

    test('a window wider than the curve falls back to a global search', () {
      final curve = circle();
      final probe = Vector3(-50.0, 0.0, 0.0);

      final found = curve.closestS(probe, nearS: 0.0, window: 1000.0);

      expect(gap(curve, found, curve.closestSGlobal(probe)), lessThan(0.05));
    });

    test('the nearest point is found between samples, not only at them', () {
      // Mutation: return the nearest measured sample's distance and skip the
      // refinement. The samples on this curve are a metre and a quarter apart,
      // so the answer would be up to half of that out — a car would shuffle
      // along the track in steps rather than slide, and every distance derived
      // from it would tremble with it.
      final curve = circle();
      final probe = Vector3.zero();

      // A point exactly on the curve, deliberately between two samples: the
      // right answer is known to the metre it was asked for.
      const truth = 0.317;
      curve.sampleAt(curve.length * truth, probe);

      expect(
        gap(curve, curve.closestSGlobal(probe), curve.length * truth),
        lessThan(0.01),
      );
    });
  });

  group('construction', () {
    test('the curve keeps its own copy of the points', () {
      // Mutation: store the caller's list. Every distance this class reports
      // comes from a table measured once, so a point moved afterwards leaves the
      // curve answering for a shape it no longer has.
      final source = [
        Vector3(50.0, 0.0, 0.0),
        Vector3(0.0, 0.0, 50.0),
        Vector3(-50.0, 0.0, 0.0),
      ];
      final curve = CatmullRom(source);
      final out = Vector3.zero();

      source[0].setValues(999.0, 999.0, 999.0);
      curve.sampleAt(0.0, out);

      expect(out.x, closeTo(50.0, 1e-9));
    });

    test('two curves from the same points are identical to the bit', () {
      // The simulation is replayed from recorded input, so anything derived from
      // the track has to come out the same every time it is built.
      final points = [
        Vector3(0.0, 0.0, 0.0),
        Vector3(30.0, 2.0, 10.0),
        Vector3(50.0, 0.0, 40.0),
        Vector3(10.0, -3.0, 60.0),
      ];
      final a = CatmullRom(points);
      final b = CatmullRom(points);
      final left = Vector3.zero();
      final right = Vector3.zero();

      expect(a.length, b.length);
      for (var i = 0; i < 50; i++) {
        final s = a.length * i / 50;
        a.sampleAt(s, left);
        b.sampleAt(s, right);
        expect(left.x, right.x);
        expect(left.y, right.y);
        expect(left.z, right.z);
      }
    });

    test('a closed curve needs three points', () {
      expect(
        () => CatmullRom([Vector3.zero(), Vector3(1.0, 0.0, 0.0)]),
        throwsArgumentError,
      );
    });

    test('an open curve needs two', () {
      expect(
        () => CatmullRom([Vector3.zero()], closed: false),
        throwsArgumentError,
      );
    });

    test('an open curve holds its end points rather than looping', () {
      // Mutation: wrap the control point index on an open curve too. The last
      // segment would then bend towards the first point — a sprint track whose
      // finish curls back at the start line.
      final curve = CatmullRom([
        Vector3(0.0, 0.0, 0.0),
        Vector3(10.0, 0.0, 0.0),
        Vector3(20.0, 0.0, 0.0),
        Vector3(30.0, 0.0, 0.0),
      ], closed: false);
      final out = Vector3.zero();

      curve.sampleAt(curve.length, out);

      expect(out.x, closeTo(30.0, 1e-9));
      expect(out.z, closeTo(0.0, 1e-9));
    });
  });
}
