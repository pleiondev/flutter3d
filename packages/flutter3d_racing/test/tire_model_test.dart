import 'dart:math' as math;

import 'package:flutter3d_racing/flutter3d_racing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('the shape of the curve', () {
    test('grip is at its best where the tyre says it is', () {
      // Mutation: derive the stiffness from the tail instead of the peak. The
      // curve keeps its shape and puts it in the wrong place, so the limit is
      // somewhere other than where the car was tuned to find it.
      final tires = TireModel(peakSlipAngle: 0.16);

      final atPeak = tires.lateralAt(0.16);
      expect(atPeak, closeTo(1.0, 1e-6));

      for (final slip in <double>[0.02, 0.08, 0.13, 0.2, 0.4, 1.0]) {
        expect(tires.lateralAt(slip), lessThan(atPeak));
      }
    });

    test('grip falls away past the peak instead of holding', () {
      // Mutation: a curve that rises and then flattens — `min(k·slip, 1)`. It
      // looks close enough on a plot and takes the game apart: a car past the
      // limit keeps every bit of grip it had, so a slide never runs away, never
      // has to be caught, and a corner entered far too fast costs nothing.
      final tires = TireModel(peakSlipAngle: 0.16, lateralTail: 0.7);

      final atPeak = tires.lateralAt(0.16);
      final wellPast = tires.lateralAt(0.6);
      final fullySideways = tires.lateralAt(1.4);

      expect(wellPast, lessThan(atPeak * 0.95));
      expect(fullySideways, lessThan(wellPast));

      // The tail is what the curve settles towards, not where it is by the time
      // a car is properly sideways — at a slip of 1.4 it is still on its way
      // down. Asked for far out, where it has arrived.
      expect(tires.lateralAt(20.0), closeTo(0.7, 0.01));
    });

    test('the curve is smooth across the peak', () {
      // A kink here would be a kink exactly where a car spends its interesting
      // moments, and it would arrive as a car that snaps at the limit rather
      // than easing over it.
      final tires = TireModel(peakSlipAngle: 0.16);
      const step = 0.002;

      var worst = 0.0;
      for (var slip = 0.10; slip < 0.24; slip += step) {
        final second = tires.lateralAt(slip + step) -
            2 * tires.lateralAt(slip) +
            tires.lateralAt(slip - step);
        worst = math.max(worst, second.abs());
      }

      expect(worst, lessThan(1e-3));
    });

    test('sliding one way is pushed back the other', () {
      final tires = TireModel();

      expect(tires.lateralAt(0.2), closeTo(-tires.lateralAt(-0.2), 1e-12));
      expect(tires.lateralAt(0.0), 0.0);
    });

    test('driving and braking have their own peak', () {
      // Slip ratio is not slip angle, and a tyre is not equally good at both.
      final tires = TireModel(peakSlipAngle: 0.16, peakSlipRatio: 0.08);

      expect(tires.longitudinalAt(0.08), closeTo(1.0, 1e-6));
      expect(tires.longitudinalAt(0.16), lessThan(1.0));
    });
  });

  group('the friction circle', () {
    test('one tyre cannot do two things at full strength', () {
      // Mutation: clamp each component to the limit on its own. Both are then
      // legal and their sum is not, so a car brakes at full strength through a
      // corner it is already taking at the limit — and the driver never has to
      // choose, which is the choice the game is made of.
      final force = Vector2(10.0, 10.0);

      TireModel.clampToCircle(force, 10.0);

      expect(force.length, closeTo(10.0, 1e-6));
      expect(force.x, closeTo(10.0 / math.sqrt2, 1e-6));
      expect(force.y, closeTo(10.0 / math.sqrt2, 1e-6));
    });

    test('a force inside the circle is left alone', () {
      final force = Vector2(3.0, 4.0);

      TireModel.clampToCircle(force, 10.0);

      expect(force.x, 3.0);
      expect(force.y, 4.0);
    });

    test('cutting the size keeps the direction', () {
      final force = Vector2(30.0, 40.0);

      TireModel.clampToCircle(force, 10.0);

      expect(force.length, closeTo(10.0, 1e-6));
      expect(force.y / force.x, closeTo(40.0 / 30.0, 1e-9));
    });
  });

  group('the grip table', () {
    test('a surface nobody named is full grip, not none', () {
      // A track may name a surface for its tyre noise alone. If an unknown name
      // meant no grip, adding a sound would turn a straight into an ice rink.
      const grips = GripTable.common();

      expect(grips.gripFor(null), 1.0);
      expect(grips.gripFor('carpet'), 1.0);
    });

    test('the surfaces it does know are worth what they say', () {
      const grips = GripTable.common();

      expect(grips.gripFor('asphalt'), greaterThan(grips.gripFor('gravel')));
      expect(grips.gripFor('gravel'), greaterThan(grips.gripFor('ice')));
      expect(grips.knows('ice'), isTrue);
      expect(grips.knows('carpet'), isFalse);
    });
  });
}
