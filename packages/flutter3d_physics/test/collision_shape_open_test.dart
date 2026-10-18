import 'dart:typed_data';

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A ball written outside the package, straight on [CollisionShape]: its
/// bounds, its planes and its support, and nothing of the pair methods.
final class _Ball extends CollisionShape {
  _Ball(this.radius);

  final double radius;

  @override
  Vector3 get boundsHalfExtents => Vector3.all(radius);

  @override
  int get expandedPlaneCount => CollisionShape.boundsPlaneCount;

  @override
  int expandedPlanes(Vector3 position, Vector3 half, Float64List out) =>
      boundsExpandedPlanes(position, half, out);

  @override
  void supportPoint(double dx, double dy, double dz, Vector3 out) {
    final d = Vector3(dx, dy, dz);
    final length = d.length;
    if (length == 0.0) {
      out.setValues(radius, 0.0, 0.0);
      return;
    }
    out
      ..setFrom(d)
      ..scale(radius / length);
  }
}

void main() {
  group('a shape of its own, extending CollisionShape', () {
    test('meets every built-in shape through the convex walk', () {
      final ball = _Ball(0.5);
      final box = CollisionBox(Vector3.all(0.5));
      final sphere = CollisionSphere(0.5);
      final capsule = CollisionCapsule(radius: 0.5, halfHeight: 0.5);

      // Corner to corner the boxes of the two would touch; the ball does not
      // reach the box's corner.
      final diagonal = Vector3(0.95, 0.95, 0.0);
      expect(ball.overlaps(diagonal, box, Vector3.zero()), isFalse);
      expect(box.overlaps(Vector3.zero(), ball, diagonal), isFalse);

      final near = Vector3(0.9, 0.0, 0.0);
      expect(ball.overlaps(near, box, Vector3.zero()), isTrue);
      expect(box.overlaps(Vector3.zero(), ball, near), isTrue);
      expect(sphere.overlaps(Vector3.zero(), ball, near), isTrue);
      expect(ball.overlaps(near, sphere, Vector3.zero()), isTrue);
      expect(capsule.overlaps(Vector3.zero(), ball, near), isTrue);
      expect(
        capsule.overlaps(Vector3.zero(), ball, Vector3(1.1, 0.0, 0.0)),
        isFalse,
      );
    });

    test('meets ground through the field\'s prisms', () {
      final field = CollisionHeightfield(
        heights: Float32List.fromList(<double>[0, 0, 0, 0]),
        columns: 2,
        rows: 2,
        cellSize: 4.0,
      );
      final ball = _Ball(0.5);
      expect(
        ball.overlaps(Vector3(2.0, 0.4, 2.0), field, Vector3.zero()),
        isTrue,
      );
      expect(
        ball.overlaps(Vector3(2.0, 0.6, 2.0), field, Vector3.zero()),
        isFalse,
      );
    });

    test('has an inertia, a ray and a place in a world', () {
      final ball = _Ball(0.5);
      expect(inertiaFor(ball, 3.0).x, closeTo(0.5, 1e-12));

      final normal = Vector3.zero();
      final at = ball.raycast(
        Vector3.zero(),
        Vector3(-5.0, 0.0, 0.0),
        Vector3(1.0, 0.0, 0.0),
        10.0,
        normal,
      );
      expect(at, closeTo(4.5, 1e-12));

      final world = CollisionWorld();
      world.add(Collider(shape: ball, position: Vector3.zero()));
      final out = <Collider>[];
      world.overlap(CollisionSphere(0.3), Vector3(0.7, 0.0, 0.0), out);
      expect(out, hasLength(1));
    });
  });
}
