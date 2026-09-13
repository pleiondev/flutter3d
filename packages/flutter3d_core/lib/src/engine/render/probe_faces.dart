/// The six cameras a reflection probe looks through, and the matrix that puts
/// each face where a cube sampler expects to find it.
///
/// Pure arithmetic, no device: `probe_faces_test.dart` projects known
/// directions through every face on both framebuffer origins and asks where
/// they land, which is the only way to be right about this — nothing in a
/// picture says whether a face is mirrored.
///
/// ## Why a face is drawn through a mirror
///
/// A cube map is addressed by the graphics API's table: on the +X face, row
/// zero looks up +Y and column zero looks along +Z. Point a right-handed camera
/// down +X with +Y up and its *right* is +Z, so the picture it draws has +Z on
/// the right where the sampler wants it on the left. Every face comes out the
/// same way — the table is left-handed, and a camera is not — so each view is
/// mirrored in x before it is drawn. That reverses which way a triangle winds,
/// which is why the mesh encoder takes a `mirrored` flag and flips the winding
/// it sets per node.
///
/// A backend whose framebuffer origin is at the bottom stores row zero where
/// the camera's bottom edge lands, which turns every face upside down as well.
/// The fix is one more sign: clip y is negated too, so the camera's top lands
/// on the last row, and the last row is where such a backend keeps the
/// picture's top. Two negated axes are a half turn rather than a mirror, so on
/// that backend the winding stays as it was — [probeFaceIsMirrored] is what
/// the encoder asks. Measured through the sampler rather than reasoned about,
/// on every face and both origins.
library;

import 'dart:math' as math;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import '../scene/projection.dart';

/// Where each face looks and which way is up, in the order the faces are
/// stored: +X, −X, +Y, −Y, +Z, −Z.
///
/// The up vectors follow the cube-map table rather than a general rule: the
/// four side faces keep +Y up, the top face looks along +Y with −Z at its top
/// row, and the bottom face looks along −Y with +Z at its top row.
final class ProbeFace {
  const ProbeFace._(this.aim, this.up);

  final Vector3 aim;
  final Vector3 up;

  static final List<ProbeFace> all = List<ProbeFace>.unmodifiable(<ProbeFace>[
    ProbeFace._(Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0)),
    ProbeFace._(Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0)),
    ProbeFace._(Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, -1.0)),
    ProbeFace._(Vector3(0.0, -1.0, 0.0), Vector3(0.0, 0.0, 1.0)),
    ProbeFace._(Vector3(0.0, 0.0, 1.0), Vector3(0.0, 1.0, 0.0)),
    ProbeFace._(Vector3(0.0, 0.0, -1.0), Vector3(0.0, 1.0, 0.0)),
  ]);
}

/// The view-projection that draws [face] of a probe at [position] into a cube
/// face a sampler reads correctly, in the clip space of a backend with the
/// given [origin] and [depthRange].
///
/// Ninety degrees, square, from [near] to [far]. The mirror in x is applied
/// to every face — see the library note — and clip y is negated as well on a
/// bottom-left backend. The depth remap is the same one every camera in the
/// engine goes through at the boundary.
Matrix4 probeFaceViewProjection(
  int face,
  Vector3 position, {
  required double near,
  required double far,
  required FramebufferOrigin origin,
  required DepthRange depthRange,
}) {
  final camera = ProbeFace.all[face];
  final view = lookAtRightHanded(position, position + camera.aim, camera.up);
  final projection = PerspectiveProjection(
    fovYRadians: math.pi / 2,
    near: near,
    far: far,
  ).toMatrix(1.0);
  // Mirror x in clip space: the cube-map table is left-handed, and a
  // right-handed camera puts every face's left on the right. And y where row
  // zero is at the bottom, so the picture's top lands on the last row. Typed,
  // because `Matrix4.operator*` returns `dynamic`.
  final Matrix4 mirrored = Matrix4.identity()
    ..setEntry(0, 0, -1.0)
    ..setEntry(1, 1, origin == FramebufferOrigin.bottomLeft ? -1.0 : 1.0)
    ..multiply(projection)
    ..multiply(view);
  return toDepthRange(mirrored, depthRange);
}

/// Whether the view [probeFaceViewProjection] builds reverses the winding of
/// every triangle drawn through it.
///
/// One negated axis is a mirror; two are a half turn. On a top-left backend
/// only x is negated and front faces wind the other way; on a bottom-left one
/// y is negated too, and they wind as they always did.
bool probeFaceIsMirrored(FramebufferOrigin origin) =>
    origin == FramebufferOrigin.topLeft;

/// A right-handed look-at whose camera looks down its own −Z, which is what
/// `PerspectiveProjection` and this engine's `[0, 1]` depth convention expect.
///
/// The same construction the renderer keeps privately for its shadow faces,
/// written here where a test can reach it.
Matrix4 lookAtRightHanded(Vector3 eye, Vector3 target, Vector3 up) {
  final forward = (target - eye)..normalize();
  final right = forward.cross(up)..normalize();
  final trueUp = right.cross(forward);

  final view = Matrix4.identity();
  view.setEntry(0, 0, right.x);
  view.setEntry(0, 1, right.y);
  view.setEntry(0, 2, right.z);
  view.setEntry(1, 0, trueUp.x);
  view.setEntry(1, 1, trueUp.y);
  view.setEntry(1, 2, trueUp.z);
  view.setEntry(2, 0, -forward.x);
  view.setEntry(2, 1, -forward.y);
  view.setEntry(2, 2, -forward.z);
  view.setEntry(0, 3, -right.dot(eye));
  view.setEntry(1, 3, -trueUp.dot(eye));
  view.setEntry(2, 3, forward.dot(eye));
  return view;
}
