/// The arithmetic of `P4`'s mirrored camera: a reflection across a plane,
/// and a projection whose near plane is that plane.
///
/// Tolerances are float32's: vector_math's matrices store their elements in
/// a `Float32List`.
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// [point] in clip space through [projection] after [view].
Vector4 _clip(Matrix4 projection, Matrix4 view, Vector3 point) => projection
    .transform(view.transform(Vector4(point.x, point.y, point.z, 1.0)));

/// Window depth of [point] through [projection] after [view].
double _depth(Matrix4 projection, Matrix4 view, Vector3 point) {
  final clip = _clip(projection, view, point);
  return clip.z / clip.w;
}

void main() {
  test('the reflection mirrors a point across a tilted plane and undoes '
      'itself', () {
    final normal = Vector3(0.3, 1.0, -0.2)..normalize();
    final point = Vector3(1.0, 2.0, -0.5);
    final mirror = mirrorAcrossPlane(normal, point);
    final p = Vector3(-2.0, 4.0, 3.0);
    final reflected = mirror.transform3(p.clone());
    // The two are the same distance either side, along the normal.
    // Mutation: dropping the translation reflects across a plane through the
    // origin, and the distances disagree by twice the plane's offset.
    expect(
      normal.dot(reflected - point),
      closeTo(-normal.dot(p - point), 1e-5),
    );
    expect(
      (reflected - p).normalized().cross(normal).length,
      closeTo(0.0, 1e-5),
    );
    expect(mirror.transform3(reflected).distanceTo(p), closeTo(0.0, 1e-5));
    expect(mirror.determinant(), closeTo(-1.0, 1e-5));
  });

  group('obliqueNearPlane', () {
    final camera = CameraNode()
      ..setPositionFrom(Vector3(0.0, 3.0, 5.0))
      ..lookAt(Vector3.zero());
    final normal = Vector3(0.0, 1.0, 0.0);
    final mirrored =
        camera.viewMatrix * mirrorAcrossPlane(normal, Vector3.zero())
            as Matrix4;
    final projection = camera.projection.toMatrix(1.0);
    final clipped = obliqueNearPlane(
      projection,
      planeInEyeSpace(mirrored, normal, Vector3.zero()),
    )!;

    test(
      'cuts at the plane: what is below it is in front of the near plane',
      () {
        // Mutation: the ordinary projection keeps both of these in [0, 1].
        expect(_depth(clipped, mirrored, Vector3(0.0, -1.5, 1.8)), lessThan(0));
        expect(
          _depth(clipped, mirrored, Vector3(0.0, -0.01, 0.0)),
          lessThan(0),
        );
        expect(
          _depth(clipped, mirrored, Vector3(0.0, 1.0, 0.0)),
          inExclusiveRange(0.0, 1.0),
        );
        expect(
          _depth(clipped, mirrored, Vector3(2.0, 0.0, -1.0)),
          closeTo(0.0, 1e-6),
        );
      },
    );

    test('moves only depth: every point lands on the same pixel', () {
      for (final point in <Vector3>[
        Vector3(0.0, 1.0, 0.0),
        Vector3(1.5, 0.5, -2.0),
        Vector3(-1.0, 2.0, 1.0),
      ]) {
        final a = _clip(projection, mirrored, point);
        final b = _clip(clipped, mirrored, point);
        expect(a.x / a.w, closeTo(b.x / b.w, 1e-5));
        expect(a.y / a.w, closeTo(b.y / b.w, 1e-5));
      }
    });

    test('refuses a plane the eye stands on the kept side of', () {
      // The ordinary camera, not the mirrored one: it is above the plane,
      // which is the side kept, so no near plane can stand on it.
      expect(
        obliqueNearPlane(
          projection,
          planeInEyeSpace(camera.viewMatrix, normal, Vector3.zero()),
        ),
        isNull,
      );
    });
  });
}
