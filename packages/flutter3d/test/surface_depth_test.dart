/// What the surface buffer's alpha channel means, and that it survives the
/// round trip both ways round.
///
/// **The channel used to hold `gl_FragCoord.z` and now holds metres along the
/// view axis.** That was a defect rather than a preference: the attachment is
/// `r16g16b16a16Float` on every backend, and a window depth spends nearly the
/// whole of `[0, 1]` on the first few metres — so past twenty, half-float steps
/// are wider than half a metre and two surfaces that far apart stored the same
/// number. Both passes that read this buffer decide occlusion by subtracting
/// two of them, so the rounding decided whole bands of the picture: vertical
/// stripes along the lines of equal depth, on both GPU backends, in every scene
/// with a wall in it.
///
/// The tests below are the two halves of the contract:
///
///  * a writer stores `dot(p - eye, forward)`, transcribed as [viewDepth];
///  * a reader turns a pixel and one of those numbers back into the point,
///    transcribed as [worldAtDepth].
///
/// Round-tripped under **both projections**, which is the part that is easy to
/// get wrong and impossible to see: an orthographic camera's rays are parallel
/// and meet nowhere, so a reconstruction that starts every ray at the camera
/// position is right on a perspective camera and quietly wrong on an isometric
/// scene. The first version of this change did exactly that.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/src/cpu_shaders_color.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A camera at [eye] looking at the origin, with [projection].
CameraNode _camera(Projection projection, Vector3 eye) =>
    CameraNode(projection: projection)
      ..setPositionFrom(eye)
      ..lookAt(Vector3.zero());

/// Where [point] lands on the screen, in the uv the passes read the buffer at.
Vector2 _uvOf(Matrix4 viewProjection, Vector3 point) {
  final Vector4 clip = viewProjection * Vector4(point.x, point.y, point.z, 1.0);
  return Vector2((clip.x / clip.w) * 0.5 + 0.5, 0.5 - (clip.y / clip.w) * 0.5);
}

void main() {
  const aspect = 16.0 / 9.0;
  final eye = Vector3(3.0, 4.0, 9.0);

  /// Every projection this engine has, and the point of the test: the same
  /// arithmetic has to serve both.
  final projections = <String, Projection>{
    'perspective': const PerspectiveProjection(near: 0.1, far: 500.0),
    'orthographic': const OrthographicProjection(
      height: 12.0,
      near: 0.1,
      far: 500.0,
    ),
  };

  for (final entry in projections.entries) {
    group('under an ${entry.key} camera', () {
      final camera = _camera(entry.value, eye);
      final viewProjection = camera.viewProjection(aspect);
      final inverse = Matrix4.copy(viewProjection)..invert();
      final forward = camera.readForward();

      test('a point reconstructs where it was', () {
        // Spread about the frame and through the range where a half float used
        // to give up: a metre away, and forty.
        for (final point in <Vector3>[
          Vector3.zero(),
          Vector3(1.0, 0.5, -1.0),
          Vector3(-2.0, 1.0, 2.0),
          Vector3(4.0, -3.0, -30.0),
          Vector3(-1.5, 2.5, -38.0),
        ]) {
          final depth = (point - eye).dot(forward);
          final uv = _uvOf(viewProjection, point);
          final back = worldAtDepth(inverse, eye, forward, uv.x, uv.y, depth);

          expect(
            back.distanceTo(point),
            lessThan(1e-3),
            reason: '$point came back as $back',
          );
        }
      });

      test(
        'and the axis is read out of the matrix as the camera reports it',
        () {
          // `viewAxisOf` is what the frame graph and the probe faces use, where
          // there is a matrix and no camera node. It has to be the same vector,
          // or the buffer would be written against one axis and read against
          // another.
          final fromMatrix = viewAxisOf(viewProjection);

          expect(fromMatrix.distanceTo(forward), lessThan(1e-5));
        },
      );
    });
  }

  test('the axis survives the two adjustments a matrix can carry', () {
    // Both are applied to the matrices the reading passes are handed:
    // `toFramebufferOrigin` mirrors y for a bottom-left backend, and
    // `toDepthRange` moves clip depth to `[-1, 1]` for one that wants it there.
    // Neither is a change of *direction*, and a reconstruction that thought
    // otherwise would be wrong on exactly one backend — which is how the
    // previous defect in this channel was found.
    final camera = _camera(
      const PerspectiveProjection(near: 0.1, far: 500.0),
      eye,
    );
    final plain = camera.viewProjection(aspect);
    final adjusted = toFramebufferOrigin(
      toDepthRange(plain, DepthRange.negativeOneToOne),
      FramebufferOrigin.bottomLeft,
    );

    expect(viewAxisOf(adjusted).distanceTo(viewAxisOf(plain)), lessThan(1e-5));
  });

  test('a wall at twenty metres is told from one at twenty and a half', () {
    // The defect, as the numbers that caused it, held here so the claim in
    // `WriteSurfaceGeometry` is a measurement rather than an assertion.
    //
    // Half precision keeps eleven bits of mantissa, so its step is about a
    // two-thousandth of the value. In metres that is under a centimetre at
    // twenty. In a window depth it is a two-thousandth of `[0, 1]` — and with a
    // near plane of a tenth of a metre, everything past twenty metres is inside
    // the last half a hundredth of that range.

    /// [v] as it would come back out of an `r16g16b16a16Float` attachment.
    double half(double v) {
      final bits = (ByteData(4)..setFloat32(0, v)).getUint32(0);
      // Thirteen of float32's twenty-three mantissa bits do not survive, so
      // drop them and round to nearest on the highest one dropped.
      final kept = bits & 0xFFFFE000;
      final up = (bits & 0x1000) != 0 ? 0x2000 : 0;
      return (ByteData(4)..setUint32(0, kept + up)).getFloat32(0);
    }

    /// What the channel used to hold, in the engine's `[0, 1]` convention.
    double windowDepth(double metres) {
      const near = 0.1, far = 500.0;
      return far / (far - near) * (1.0 - near / metres);
    }

    expect(
      half(windowDepth(20.0)),
      half(windowDepth(20.5)),
      reason: 'the defect this channel was changed to remove',
    );
    // And it only gets worse further out, which is why the stripes ran along
    // the lines of equal depth rather than appearing at one distance.
    expect(half(windowDepth(40.0)), half(windowDepth(40.5)));

    // The same two surfaces, in the metres the channel holds now.
    expect(half(20.0), isNot(half(20.5)));
    expect((half(20.0) - 20.0).abs(), lessThan(0.02));
    expect((half(40.0) - 40.0).abs(), lessThan(0.04));
  });
}
