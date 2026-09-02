/// Where each face of a reflection probe puts the world, on both framebuffer
/// origins.
///
///     flutter test test/probe_faces_test.dart
///
/// A cube map is addressed by a table every graphics API shares: on the +X
/// face, row zero looks up +Y and column zero looks along +Z. A camera drawn
/// into that face has to put +Z on the *left* of its picture and +Y at row
/// zero, and a right-handed camera does neither by itself — its right is +Z,
/// and on a bottom-left backend its top lands on the last row. Nothing in a
/// rendered picture says whether a face is mirrored, so this asks the matrix
/// directly: project a direction the table names, and see which side of the
/// picture it lands on.
library;

import 'package:flutter3d/src/engine/render/probe_faces.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// The direction each face shows in its left column and its top row, from
/// the cube-map table: sc = 0 and tc = 0 of each face, inverted.
const List<({List<double> left, List<double> top})> _table =
    <({List<double> left, List<double> top})>[
      (left: <double>[1, 0, 1], top: <double>[1, 1, 0]), // +X
      (left: <double>[-1, 0, -1], top: <double>[-1, 1, 0]), // −X
      (left: <double>[-1, 1, 0], top: <double>[0, 1, -1]), // +Y
      (left: <double>[-1, -1, 0], top: <double>[0, -1, 1]), // −Y
      (left: <double>[-1, 0, 1], top: <double>[0, 1, 1]), // +Z
      (left: <double>[1, 0, -1], top: <double>[0, 1, -1]), // −Z
    ];

final Vector3 _eye = Vector3(2.0, -1.0, 3.0);

/// Where a point [direction] away from the eye lands in NDC.
Vector3 _ndc(int face, List<double> direction, FramebufferOrigin origin) {
  final matrix = probeFaceViewProjection(
    face,
    _eye,
    near: 0.1,
    far: 100.0,
    origin: origin,
    depthRange: DepthRange.zeroToOne,
  );
  final at = _eye + Vector3.array(direction) * 4.0;
  final clip = matrix.transform(Vector4(at.x, at.y, at.z, 1.0));
  expect(clip.w, greaterThan(0.0), reason: 'the point is behind the face');
  return Vector3(clip.x / clip.w, clip.y / clip.w, clip.z / clip.w);
}

void main() {
  for (var face = 0; face < 6; face++) {
    final aim = ProbeFace.all[face].aim;

    test('face $face looks straight down its axis', () {
      // The centre of the face is the direction it is named after. Mutation:
      // swap two entries of the aim table — the centre of one face lands off
      // the picture entirely.
      final centre = _ndc(face, <double>[
        aim.x,
        aim.y,
        aim.z,
      ], FramebufferOrigin.topLeft);
      expect(centre.x.abs(), lessThan(1e-6));
      expect(centre.y.abs(), lessThan(1e-6));
    });

    test('face $face puts the table\'s left column on the left', () {
      // The mirror. Without it every face has its left on the right, and a
      // mirror ball shows the room reversed — which a person reads as the
      // reflection being "off" and cannot say why. Mutation: drop the x
      // negation in `probeFaceViewProjection`; this fails on all six.
      for (final origin in FramebufferOrigin.values) {
        final left = _ndc(face, _table[face].left, origin);
        expect(left.x, lessThan(-0.5), reason: 'on a ${origin.name} backend');
      }
    });

    test('face $face puts the table\'s top row at row zero', () {
      // Clip +y is row zero on a top-left backend and the last row on a
      // bottom-left one, so the same direction has to land on opposite sides
      // of clip space. Mutation: stop negating y for bottom-left — the +X face
      // of every WebGL probe is upside down, and only the cross-backend
      // comparison of the golden would say so. The first version of this
      // negated the up vector instead, which is a half turn rather than a
      // flip and put the left column back on the right; the test above is
      // what caught it.
      final top = _ndc(face, _table[face].top, FramebufferOrigin.topLeft);
      expect(top.y, greaterThan(0.5), reason: 'top-left keeps row zero up');
      final flipped = _ndc(
        face,
        _table[face].top,
        FramebufferOrigin.bottomLeft,
      );
      expect(
        flipped.y,
        lessThan(-0.5),
        reason: 'bottom-left stores row zero where clip −y lands',
      );
    });
  }

  test('one negated axis is a mirror and two are a half turn', () {
    // What the mesh encoder is told: the winding flips on the origin where
    // only x is negated and stays where y is negated with it. Mutation:
    // return true for both — every face of every WebGL probe shows the inside
    // of every object.
    expect(probeFaceIsMirrored(FramebufferOrigin.topLeft), isTrue);
    expect(probeFaceIsMirrored(FramebufferOrigin.bottomLeft), isFalse);
  });

  test('the near plane keeps the probe\'s own surroundings out', () {
    // A point nearer than `near` projects in front of the near plane, which
    // is how a probe placed inside a body leaves that body out of its picture
    // without a list of exclusions.
    final matrix = probeFaceViewProjection(
      0,
      _eye,
      near: 0.5,
      far: 10.0,
      origin: FramebufferOrigin.topLeft,
      depthRange: DepthRange.zeroToOne,
    );
    final at = _eye + Vector3(0.25, 0.0, 0.0);
    final clip = matrix.transform(Vector4(at.x, at.y, at.z, 1.0));
    expect(clip.z / clip.w, lessThan(0.0));
  });

  test('a GL depth range is remapped like every other camera', () {
    // The far plane lands at +1 in both conventions and the near plane at 0
    // or −1; the depth remap is the one every projection in the engine goes
    // through, and a probe that skipped it would draw into half the depth
    // buffer on WebGL.
    final at = _eye + Vector3(0.1, 0.0, 0.0);
    Vector4 clip(DepthRange range) => probeFaceViewProjection(
      0,
      _eye,
      near: 0.1,
      far: 100.0,
      origin: FramebufferOrigin.topLeft,
      depthRange: range,
    ).transform(Vector4(at.x, at.y, at.z, 1.0));
    final metal = clip(DepthRange.zeroToOne);
    final gl = clip(DepthRange.negativeOneToOne);
    expect(metal.z / metal.w, closeTo(0.0, 1e-6));
    expect(gl.z / gl.w, closeTo(-1.0, 1e-6));
  });
}
