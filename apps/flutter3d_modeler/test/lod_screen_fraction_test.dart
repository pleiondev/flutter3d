/// Meters ↔ screen fraction, checked against [LodGroup]'s own formula.
///
///     flutter test test/lod_screen_fraction_test.dart
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_modeler/src/lod_screen_fraction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('screenFractionForSize', () {
    test('a one-metre object ten metres away, through 45 degrees vertical', () {
      const projection = PerspectiveProjection(fovYRadians: math.pi / 4);
      final fraction = screenFractionForSize(
        diameterMeters: 1.0,
        distanceMeters: 10.0,
        projection: projection,
      );
      // halfHeight = tan(22.5°) * 10 ≈ 4.142; fraction = 0.5 / 4.142.
      final halfHeight = math.tan(math.pi / 8) * 10.0;
      expect(fraction, closeTo(0.5 / halfHeight, 1e-9));
    });

    test('caps at 1.0 once the camera sits inside the object', () {
      const projection = PerspectiveProjection(fovYRadians: math.pi / 4);
      expect(
        screenFractionForSize(
          diameterMeters: 4.0,
          distanceMeters: 1.0,
          projection: projection,
        ),
        1.0,
      );
    });

    test('an orthographic camera ignores distance entirely', () {
      const projection = OrthographicProjection(height: 4.0);
      final near = screenFractionForSize(
        diameterMeters: 1.0,
        distanceMeters: 1.0,
        projection: projection,
      );
      final far = screenFractionForSize(
        diameterMeters: 1.0,
        distanceMeters: 1000.0,
        projection: projection,
      );
      expect(near, closeTo(0.25, 1e-9));
      expect(far, closeTo(near, 1e-9));
    });

    test('zero or negative size is zero coverage', () {
      const projection = PerspectiveProjection();
      expect(
        screenFractionForSize(
          diameterMeters: 0.0,
          distanceMeters: 5.0,
          projection: projection,
        ),
        0.0,
      );
    });
  });

  group('sizeForScreenFraction', () {
    test('inverts screenFractionForSize for a perspective camera', () {
      const projection = PerspectiveProjection(fovYRadians: math.pi / 3);
      const distance = 7.5;
      const diameter = 2.25;

      final fraction = screenFractionForSize(
        diameterMeters: diameter,
        distanceMeters: distance,
        projection: projection,
      );
      final back = sizeForScreenFraction(
        screenFraction: fraction,
        distanceMeters: distance,
        projection: projection,
      );
      expect(back, closeTo(diameter, 1e-9));
    });

    test('inverts screenFractionForSize for an orthographic camera', () {
      const projection = OrthographicProjection(height: 6.0);
      const diameter = 1.5;

      final fraction = screenFractionForSize(
        diameterMeters: diameter,
        distanceMeters: 999.0,
        projection: projection,
      );
      final back = sizeForScreenFraction(
        screenFraction: fraction,
        distanceMeters: 999.0,
        projection: projection,
      );
      expect(back, closeTo(diameter, 1e-9));
    });
  });

  group('lodLevelAt', () {
    test('takes the coarsest level the size still allows', () {
      // Thresholds at a half and a quarter of the screen: an object at a
      // fifth is under both, and the engine draws the one with the smaller
      // threshold — the coarser mesh. Mutation: take the first that
      // qualifies. A distant object is then drawn with the finer level for
      // as long as it is on screen, which is the cost LODs exist to avoid.
      expect(lodLevelAt(const <double>[0.5, 0.25], 0.2), 1);
      expect(lodLevelAt(const <double>[0.5, 0.25], 0.3), 0);
    });

    test('an object bigger than every threshold is the full mesh', () {
      // Mutation: answer the largest threshold's level instead, which is
      // what `LodGroup.select` does over *its* list — but its list has the
      // full mesh in it, and a project's levels do not: they are extra
      // surfaces beside the base.
      expect(lodLevelAt(const <double>[0.5, 0.25], 0.8), isNull);
      expect(lodLevelAt(const <double>[], 0.1), isNull);
    });

    test('does not need the levels in order', () {
      // `AddLod` appends in whatever order a person adds.
      expect(lodLevelAt(const <double>[0.1, 0.5, 0.25], 0.2), 2);
    });

    test('a threshold is inclusive, the way the engine reads it', () {
      // `LodGroup.select` breaks on `fraction > threshold`, so exactly on
      // the line is still the coarser side of it.
      expect(lodLevelAt(const <double>[0.25], 0.25), 0);
    });
  });
}
