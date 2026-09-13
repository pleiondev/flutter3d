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
}
