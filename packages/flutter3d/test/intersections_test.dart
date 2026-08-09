import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Ray;

import 'package:flutter3d/src/engine/math/intersections.dart';

void main() {
  Ray down(double x, double y, double z) =>
      Ray(Vector3(x, y, z), Vector3(0.0, 0.0, -1.0));

  group('ray', () {
    test('direction is left alone until asked, then normalized in place', () {
      final direction = Vector3(0.0, 0.0, -4.0);
      final ray = Ray(Vector3.zero(), direction);
      expect(ray.direction.length, 4.0);

      final returned = ray.normalizeDirection();
      expect(returned, same(ray));
      expect(ray.direction.length, closeTo(1.0, 1e-12));
      // The caller's vector must not have been captured by reference.
      expect(direction.length, 4.0);
    });

    test('pointAt walks along the direction', () {
      final ray = down(0.0, 0.0, 5.0);
      expect(ray.pointAt(3.0), Vector3(0.0, 0.0, 2.0));
    });

    test('transformInto keeps t comparable under scale', () {
      // A node scaled 2x: in its local space the ray direction doubles in
      // length, so a surface 4 world units away is still reported at t = 4.
      final ray = down(0.0, 0.0, 10.0);
      final inverse = Matrix4.diagonal3(Vector3(0.5, 0.5, 0.5));
      final local = ray.transformInto(inverse, Ray.zero());

      expect(local.origin, Vector3(0.0, 0.0, 5.0));
      expect(local.direction, Vector3(0.0, 0.0, -0.5));

      // The unit sphere in local space is the radius-2 sphere in world space,
      // whose near surface sits 8 world units away.
      final t = raySphere(local, Vector3.zero(), 1.0);
      expect(t, closeTo(8.0, 1e-9));
    });
  });

  group('rayAabb', () {
    final box = Aabb3.minMax(Vector3(-1.0, -1.0, -1.0), Vector3(1.0, 1.0, 1.0));

    test('a ray aimed at the box reports the near face', () {
      expect(rayAabb(down(0.0, 0.0, 5.0), box), closeTo(4.0, 1e-12));
    });

    test('a ray aimed past the box misses', () {
      expect(rayAabb(down(3.0, 0.0, 5.0), box), kNoHit);
    });

    test('a ray pointing away from the box misses', () {
      expect(rayAabb(Ray(Vector3(0, 0, 5), Vector3(0, 0, 1)), box), kNoHit);
    });

    test('an origin inside the box is a hit at zero', () {
      expect(rayAabb(down(0.0, 0.0, 0.0), box), 0.0);
    });

    test('a ray parallel to a slab and outside it misses', () {
      // Travelling along X at y = 5: never enters the box, and the y slab test
      // is the only thing that can reject it.
      expect(rayAabb(Ray(Vector3(-5, 5, 0), Vector3(1, 0, 0)), box), kNoHit);
    });

    test('a ray parallel to a slab and inside it hits', () {
      expect(
        rayAabb(Ray(Vector3(-5, 0, 0), Vector3(1, 0, 0)), box),
        closeTo(4.0, 1e-12),
      );
    });

    test('grazing the corner still counts', () {
      expect(rayAabb(down(1.0, 1.0, 5.0), box), closeTo(4.0, 1e-9));
    });
  });

  group('raySphere', () {
    test('the near surface is reported, not the far one', () {
      expect(
        raySphere(down(0.0, 0.0, 5.0), Vector3.zero(), 1.0),
        closeTo(4.0, 1e-12),
      );
    });

    test('a miss returns the sentinel', () {
      expect(raySphere(down(2.0, 0.0, 5.0), Vector3.zero(), 1.0), kNoHit);
    });

    test('a sphere behind the ray misses', () {
      expect(
        raySphere(Ray(Vector3(0, 0, 5), Vector3(0, 0, 1)), Vector3.zero(), 1.0),
        kNoHit,
      );
    });

    test('an origin inside the sphere is a hit at zero', () {
      expect(raySphere(down(0.0, 0.0, 0.0), Vector3.zero(), 1.0), 0.0);
    });

    test('a zero radius is never hit', () {
      expect(raySphere(down(0.0, 0.0, 5.0), Vector3.zero(), 0.0), kNoHit);
    });

    test('a non-unit direction scales t accordingly', () {
      final ray = Ray(Vector3(0, 0, 5), Vector3(0, 0, -2));
      expect(raySphere(ray, Vector3.zero(), 1.0), closeTo(2.0, 1e-12));
    });
  });

  group('rayTriangle', () {
    final a = Vector3(0.0, 0.0, 0.0);
    final b = Vector3(1.0, 0.0, 0.0);
    final c = Vector3(0.0, 1.0, 0.0);

    test('a hit reports the distance and the barycentric coordinates', () {
      final uv = Vector2.zero();
      // Aimed at (0.25, 0.25), which is inside the triangle.
      final ray = Ray(Vector3(0.25, 0.25, 2.0), Vector3(0, 0, -1));
      final t = rayTriangle(ray, a, b, c, outUv: uv);

      expect(t, closeTo(2.0, 1e-12));
      expect(uv.x, closeTo(0.25, 1e-12));
      expect(uv.y, closeTo(0.25, 1e-12));
    });

    test('a point outside the triangle misses even though the plane is hit',
        () {
      final ray = Ray(Vector3(0.9, 0.9, 2.0), Vector3(0, 0, -1));
      expect(rayTriangle(ray, a, b, c), kNoHit);
    });

    test('a triangle behind the origin misses', () {
      final ray = Ray(Vector3(0.25, 0.25, -2.0), Vector3(0, 0, -1));
      expect(rayTriangle(ray, a, b, c), kNoHit);
    });

    test('a ray parallel to the plane misses', () {
      final ray = Ray(Vector3(0.25, 0.25, 0.0), Vector3(1, 0, 0));
      expect(rayTriangle(ray, a, b, c), kNoHit);
    });

    test('a degenerate triangle is a miss, not a division by zero', () {
      final ray = Ray(Vector3(0.25, 0.0, 2.0), Vector3(0, 0, -1));
      // All three vertices collinear: zero area, no surface to hit.
      final t = rayTriangle(ray, a, b, Vector3(2.0, 0.0, 0.0), outUv: null);
      expect(t, kNoHit);
      expect(t.isNaN, isFalse);
    });

    test('back faces hit by default and miss when culled', () {
      // From behind: the winding reads clockwise, so the determinant flips.
      final ray = Ray(Vector3(0.25, 0.25, -2.0), Vector3(0, 0, 1));
      expect(rayTriangle(ray, a, b, c), closeTo(2.0, 1e-12));
      expect(rayTriangle(ray, a, b, c, cullBackFace: true), kNoHit);
    });

    test('the barycentric coordinates interpolate the vertices back', () {
      final uv = Vector2.zero();
      final ray = Ray(Vector3(0.2, 0.5, 2.0), Vector3(0, 0, -1));
      final t = rayTriangle(ray, a, b, c, outUv: uv);
      expect(t, isNot(kNoHit));

      final w = 1.0 - uv.x - uv.y;
      // vector_math stores components as float32, so the reconstruction is only
      // good to single precision however exact the intersection maths was.
      final reconstructed = a * w + b * uv.x + c * uv.y;
      expect(reconstructed.x, closeTo(0.2, 1e-6));
      expect(reconstructed.y, closeTo(0.5, 1e-6));
    });

    test('a rotated triangle is hit at the rotated distance', () {
      final rotation = Matrix4.rotationY(math.pi / 4);
      final ra = rotation.transformed3(a);
      final rb = rotation.transformed3(b);
      final rc = rotation.transformed3(c);

      // Straight down the rotated triangle's own normal, from one unit away.
      final normal = (rb - ra).cross(rc - ra)..normalize();
      final origin = ra + normal;
      final ray = Ray(origin, -normal);
      expect(rayTriangle(ray, ra, rb, rc), closeTo(1.0, 1e-9));
    });
  });
}
