/// A point and an angle round-trip through a [BridgePlane] unchanged.
library;

import 'dart:math' as math;

import 'package:flutter3d_flame/src/transform/plane.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Plane;

void main() {
  group('BridgePlane.ground', () {
    final plane = BridgePlane.ground(height: 2.0);

    test('a flat point lands at the fixed height, x and y on x and z', () {
      final point = plane.to3d(Vector2(3.0, -4.0));

      expect(point.x, 3.0);
      expect(point.y, 2.0);
      expect(point.z, -4.0);
    });

    test('to2d undoes to3d, dropping the height', () {
      final flat = Vector2(5.0, 6.0);

      expect(plane.to2d(plane.to3d(flat)), Vector2(5.0, 6.0));
    });

    test('a right angle round-trips through rotationFor/angleFor', () {
      const angle = math.pi / 2;

      expect(plane.angleFor(plane.rotationFor(angle)), closeTo(angle, 1e-6));
    });

    test('rotationFor turns about the world Y axis', () {
      expect(plane.normal, Vector3(0.0, 1.0, 0.0));
    });
  });

  group('BridgePlane.backdrop', () {
    final plane = BridgePlane.backdrop(depth: -1.0);

    test('a flat point lands at the fixed depth, y flipped onto y', () {
      final point = plane.to3d(Vector2(3.0, 4.0));

      expect(point.x, 3.0);
      expect(point.y, -4.0, reason: 'screen-down y becomes world-up y');
      expect(point.z, -1.0);
    });

    test('to2d undoes to3d, dropping the depth', () {
      final flat = Vector2(1.0, 2.0);

      expect(plane.to2d(plane.to3d(flat)), Vector2(1.0, 2.0));
    });

    test('an angle round-trips the same as on a ground plane', () {
      const angle = -1.2;

      expect(plane.angleFor(plane.rotationFor(angle)), closeTo(angle, 1e-6));
    });
  });

  test('BridgePlane.backdrop(flipY: false) keeps y aligned literally', () {
    final plane = BridgePlane.backdrop(depth: 0.0, flipY: false);

    expect(plane.to3d(Vector2(0.0, 7.0)).y, 7.0);
  });
}
