import 'dart:math' as math;

import 'package:flutter3d/src/engine/scene/projection.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Projects through a bare matrix, mirroring what the renderer does with a
/// view-projection product.
Vector3 projectToNdc(Matrix4 projection, Vector3 eyePosition) {
  final clip = projection.transform(
    Vector4(eyePosition.x, eyePosition.y, eyePosition.z, 1.0),
  );
  return Vector3(clip.x / clip.w, clip.y / clip.w, clip.z / clip.w);
}

void main() {
  _depthRangeTests();
  const fov = math.pi / 4;
  const near = 0.1;
  const far = 100.0;

  group('perspectiveZeroToOne maps depth to [0, 1]', () {
    final projection = PerspectiveProjection(
      fovYRadians: fov,
      near: near,
      far: far,
    ).toMatrix(16.0 / 9.0);

    test('the near plane maps to 0', () {
      // The camera looks down -Z, so the near plane sits at z = -near.
      final ndc = projectToNdc(projection, Vector3(0.0, 0.0, -near));
      expect(ndc.z, closeTo(0.0, 1e-6));
    });

    test('the far plane maps to 1', () {
      final ndc = projectToNdc(projection, Vector3(0.0, 0.0, -far));
      expect(ndc.z, closeTo(1.0, 1e-5));
    });

    test('depth increases monotonically with distance', () {
      var previous = -1.0;
      for (final distance in <double>[0.1, 0.5, 1, 2, 5, 10, 25, 50, 100]) {
        final z = projectToNdc(projection, Vector3(0.0, 0.0, -distance)).z;
        expect(z, greaterThan(previous), reason: 'at distance $distance');
        previous = z;
      }
    });

    test('everything between the planes stays inside the clip volume', () {
      for (final distance in <double>[0.1, 1, 10, 50, 100]) {
        final ndc = projectToNdc(projection, Vector3(0.0, 0.0, -distance));
        expect(ndc.z, inInclusiveRange(-1e-6, 1.0 + 1e-6));
      }
    });
  });

  group('perspectiveZeroToOne screen mapping', () {
    test('the centre of the view projects to the origin', () {
      final projection = PerspectiveProjection(
        fovYRadians: fov,
        near: near,
        far: far,
      ).toMatrix(1.0);
      final ndc = projectToNdc(projection, Vector3(0.0, 0.0, -5.0));
      expect(ndc.x, closeTo(0.0, 1e-6));
      expect(ndc.y, closeTo(0.0, 1e-6));
    });

    test('+Y in eye space stays +Y in NDC', () {
      // Y must not be flipped: mirroring would reverse triangle orientation on
      // screen and make backface culling drop the visible faces.
      final projection = PerspectiveProjection(
        fovYRadians: fov,
        near: near,
        far: far,
      ).toMatrix(1.0);
      final ndc = projectToNdc(projection, Vector3(0.0, 1.0, -5.0));
      expect(ndc.y, greaterThan(0.0));
    });

    test('the vertical field of view is honoured', () {
      final projection = PerspectiveProjection(
        fovYRadians: fov,
        near: near,
        far: far,
      ).toMatrix(1.0);
      // A point exactly on the top edge of the frustum lands at y = 1.
      const distance = 5.0;
      final edgeY = math.tan(fov / 2.0) * distance;
      final ndc = projectToNdc(projection, Vector3(0.0, edgeY, -distance));
      expect(ndc.y, closeTo(1.0, 1e-6));
    });

    test('aspect ratio compresses X, not Y', () {
      final wide = PerspectiveProjection(
        fovYRadians: fov,
        near: near,
        far: far,
      ).toMatrix(2.0);
      final square = PerspectiveProjection(
        fovYRadians: fov,
        near: near,
        far: far,
      ).toMatrix(1.0);
      final point = Vector3(1.0, 1.0, -5.0);

      final wideNdc = projectToNdc(wide, point);
      final squareNdc = projectToNdc(square, point);

      expect(wideNdc.x, closeTo(squareNdc.x / 2.0, 1e-6));
      expect(wideNdc.y, closeTo(squareNdc.y, 1e-6));
    });
  });

  group('argument validation', () {
    test('rejects a non-positive aspect', () {
      expect(
        () => PerspectiveProjection(
          fovYRadians: fov,
          near: near,
          far: far,
        ).toMatrix(0.0),
        throwsArgumentError,
      );
    });

    test('rejects near >= far', () {
      expect(
        () => const PerspectiveProjection(near: 10.0, far: 10.0).toMatrix(1.0),
        throwsArgumentError,
      );
    });

    test('rejects a non-positive near plane', () {
      expect(
        () => const PerspectiveProjection(near: 0.0, far: far).toMatrix(1.0),
        throwsArgumentError,
      );
    });
  });

  group('a transposed depth row is caught', () {
    test('swapping the two depth terms breaks the near-plane mapping', () {
      // This is the exact mistake that produced a black viewport: setEntry
      // takes (row, column), and the two depth terms live in different rows.
      final broken = Matrix4.zero();
      broken.setEntry(0, 0, 1.0);
      broken.setEntry(1, 1, 1.0);
      broken.setEntry(2, 2, far / (near - far));
      broken.setEntry(2, 3, -1.0);
      broken.setEntry(3, 2, (near * far) / (near - far));

      final ndc = projectToNdc(broken, Vector3(0.0, 0.0, -near));
      expect(ndc.z, isNot(closeTo(0.0, 1e-3)));
    });
  });

  _offAxisTests();
}

/// The projection a headset dictates: four angles, no symmetry to lean on.
///
/// Every check here is one of the ways an eye's frustum can be wrong while
/// still producing a picture — which is the whole difficulty, because half of
/// them look fine on a monitor and only disagree with the *other* eye.
void _offAxisTests() {
  const near = 0.1;
  const far = 100.0;

  // Roughly one eye of a headset: wider outward than inward, and not centred.
  const eye = OffAxisProjection(
    tanLeft: -1.19175359259,
    tanRight: 1.0,
    tanDown: -1.19175359259,
    tanUp: 1.19175359259,
    near: near,
    far: far,
  );

  group('an off-axis frustum with symmetric angles is a perspective one', () {
    test('the matrices agree entry for entry', () {
      const fov = math.pi / 3;
      const aspect = 16.0 / 9.0;
      final offAxis = OffAxisProjection.symmetric(
        fovYRadians: fov,
        aspect: aspect,
        near: near,
        far: far,
      ).toMatrix(aspect);
      final perspective = const PerspectiveProjection(
        fovYRadians: fov,
        near: near,
        far: far,
      ).toMatrix(aspect);

      for (var i = 0; i < 16; i++) {
        expect(
          offAxis.storage[i],
          closeTo(perspective.storage[i], 1e-9),
          reason: 'entry $i',
        );
      }
    });

    test('the two shear terms are what makes it off-axis, and they vanish', () {
      final m = OffAxisProjection.symmetric(aspect: 2.0).toMatrix(1.0);
      expect(m.entry(0, 2), closeTo(0.0, 1e-12));
      expect(m.entry(1, 2), closeTo(0.0, 1e-12));
      // And do not vanish when the frustum really is off-axis, or the check
      // above would pass on a matrix that had dropped them entirely.
      expect(eye.toMatrix(1.0).entry(0, 2), isNot(closeTo(0.0, 1e-3)));
    });
  });

  group('the four angles come back out of the matrix', () {
    // The only way to assert an asymmetric frustum: put a point exactly on each
    // plane and see it land on that edge of the clip volume. A sign error in
    // either shear term moves these off the edge — and, in a headset, moves the
    // whole image sideways in one eye.
    test('a point on each side plane lands on that edge of NDC', () {
      const depth = 5.0;
      final m = eye.toMatrix(1.0);

      expect(
        projectToNdc(m, Vector3(eye.tanLeft * depth, 0.0, -depth)).x,
        closeTo(-1.0, 1e-9),
      );
      expect(
        projectToNdc(m, Vector3(eye.tanRight * depth, 0.0, -depth)).x,
        closeTo(1.0, 1e-9),
      );
      expect(
        projectToNdc(m, Vector3(0.0, eye.tanDown * depth, -depth)).y,
        closeTo(-1.0, 1e-9),
      );
      expect(
        projectToNdc(m, Vector3(0.0, eye.tanUp * depth, -depth)).y,
        closeTo(1.0, 1e-9),
      );
    });

    test('the view axis is not in the middle of the frame', () {
      // What "off-axis" means, stated as a picture: looking straight ahead does
      // not land at x = 0. An implementation that quietly symmetrised the
      // frustum would pass every other check in this group.
      final ndc = projectToNdc(eye.toMatrix(1.0), Vector3(0.0, 0.0, -5.0));
      expect(ndc.x, isNot(closeTo(0.0, 1e-3)));
      expect(ndc.y, closeTo(0.0, 1e-9));
    });

    test('depth still maps near to 0 and far to 1', () {
      final m = eye.toMatrix(1.0);
      expect(projectToNdc(m, Vector3(0.0, 0.0, -near)).z, closeTo(0.0, 1e-6));
      expect(projectToNdc(m, Vector3(0.0, 0.0, -far)).z, closeTo(1.0, 1e-5));
    });
  });

  group('the aspect argument is ignored', () {
    test('the same frustum at any viewport shape', () {
      // Deliberate, and the doc comment says why: the four tangents already
      // state the shape. Dividing by an aspect here would squash one eye
      // against the other by the ratio between them.
      final square = eye.toMatrix(1.0);
      final wide = eye.toMatrix(2.0);
      for (var i = 0; i < 16; i++) {
        expect(wide.storage[i], equals(square.storage[i]), reason: 'entry $i');
      }
    });
  });

  group('the vertical field of view it reports', () {
    test('is the angle a symmetric frustum was built from', () {
      const fov = math.pi / 3;
      expect(
        OffAxisProjection.symmetric(fovYRadians: fov).verticalFieldOfView,
        closeTo(fov, 1e-12),
      );
    });

    test('covers the same vertical extent as the frustum itself', () {
      // What a caller sizing an object against the frame actually needs: the
      // half-height of the view volume at a distance, which is what the LOD
      // formula computes from this angle.
      const distance = 10.0;
      final half = math.tan(eye.verticalFieldOfView! * 0.5) * distance;
      expect(half, closeTo((eye.tanUp - eye.tanDown) * 0.5 * distance, 1e-9));
    });

    test('a perspective projection answers with its own, and an orthographic '
        'answers with nothing', () {
      expect(
        const PerspectiveProjection(fovYRadians: 1.2).verticalFieldOfView,
        closeTo(1.2, 1e-12),
      );
      expect(const OrthographicProjection().verticalFieldOfView, isNull);
    });
  });

  group('argument validation', () {
    test('rejects a frustum with no width or no height', () {
      expect(
        () => const OffAxisProjection(
          tanLeft: 1.0,
          tanRight: 1.0,
          tanDown: -1.0,
          tanUp: 1.0,
        ).toMatrix(1.0),
        throwsArgumentError,
      );
      expect(
        () => const OffAxisProjection(
          tanLeft: -1.0,
          tanRight: 1.0,
          tanDown: 1.0,
          tanUp: -1.0,
        ).toMatrix(1.0),
        throwsArgumentError,
      );
    });

    test('rejects near >= far', () {
      expect(
        () => const OffAxisProjection(
          tanLeft: -1.0,
          tanRight: 1.0,
          tanDown: -1.0,
          tanUp: 1.0,
          near: 10.0,
          far: 10.0,
        ).toMatrix(1.0),
        throwsArgumentError,
      );
    });
  });

  group('from the angles a runtime states', () {
    test('tangents are taken of each, signs and all', () {
      // `XrFovf` states four angles in radians, left and down negative. Taking
      // the tangent of the absolute value — an easy slip, since three of the
      // four are usually mirror images — puts the whole frustum on one side.
      final p = OffAxisProjection.fromAngles(
        left: -0.9,
        right: 0.8,
        down: -0.87,
        up: 0.87,
      );
      expect(p.tanLeft, closeTo(math.tan(-0.9), 1e-12));
      expect(p.tanRight, closeTo(math.tan(0.8), 1e-12));
      expect(p.tanDown, closeTo(math.tan(-0.87), 1e-12));
      expect(p.tanUp, closeTo(math.tan(0.87), 1e-12));
      expect(p.tanLeft, lessThan(0.0));
    });
  });
}

void _depthRangeTests() {
  group('depth range', () {
    // Cameras build for Metal/Vulkan/Impeller: near at 0, far at 1. GL wants
    // near at -1. Getting this wrong does not error — it halves the depth
    // buffer and shows up much later as z-fighting — so it is pinned by the
    // numbers rather than by inspection.
    const near = 0.1;
    const far = 100.0;
    final projection = const PerspectiveProjection(
      fovYRadians: 1.0,
      near: near,
      far: far,
    ).toMatrix(1.0);

    double ndcZ(Matrix4 m, double viewZ) {
      // A point on the -Z axis at distance |viewZ|, projected and divided.
      final clip = m.transform(Vector4(0.0, 0.0, viewZ, 1.0));
      return clip.z / clip.w;
    }

    test('the engine convention puts near at 0 and far at 1', () {
      final m = toDepthRange(projection, DepthRange.zeroToOne);
      expect(ndcZ(m, -near), closeTo(0.0, 1e-5));
      expect(ndcZ(m, -far), closeTo(1.0, 1e-5));
    });

    test('the OpenGL convention puts near at -1 and far at 1', () {
      final m = toDepthRange(projection, DepthRange.negativeOneToOne);
      expect(ndcZ(m, -near), closeTo(-1.0, 1e-5));
      expect(ndcZ(m, -far), closeTo(1.0, 1e-5));
    });

    test('the remap keeps depth monotonic, which is why order survives it', () {
      // The reason an uncorrected matrix on GL still draws in the right order,
      // and therefore the reason nobody notices the lost precision.
      final m = toDepthRange(projection, DepthRange.negativeOneToOne);
      var previous = -2.0;
      for (var d = near; d < far; d *= 1.5) {
        final z = ndcZ(m, -d);
        expect(z, greaterThan(previous));
        previous = z;
      }
    });

    test('zeroToOne hands back the same matrix rather than a copy', () {
      // Nothing depends on identity, but a needless clone every frame for the
      // backend that needs no correction is the wrong default.
      expect(
        identical(toDepthRange(projection, DepthRange.zeroToOne), projection),
        isTrue,
      );
    });
  });
}
