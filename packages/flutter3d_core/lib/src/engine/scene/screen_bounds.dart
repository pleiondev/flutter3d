/// Where a thing in the world lands on the glass — `gfx-79n`.
///
/// **Written for the accessibility layer and useful to three other callers.**
/// A screen reader needs a rectangle to put a focus ring around, and that
/// rectangle is the projection of an object's bounds. So is the box a tooltip
/// anchors to, the one a marquee selection tests against, and the one a
/// two-dimensional label follows. The engine had none of them: every place that
/// needed clip space built the matrix and did the divide by hand, which is
/// three copies of the one step that is easy to get wrong.
///
/// In this package rather than in a widget, because none of it is about Flutter:
/// a camera, a box and a viewport size are all the inputs, and the answer is
/// four numbers. The application turns those into a `Rect`.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// A rectangle on the glass, in logical pixels, with the origin top left.
typedef ScreenBounds = ({double left, double top, double right, double bottom});

/// Where [point] lands, or null if it is behind the eye.
///
/// [viewProjection] is the camera's own matrix for the viewport's aspect, in
/// this engine's `[0, 1]` depth convention and with +Y up — the matrix
/// `CameraNode.viewProjection` returns, *not* one adjusted for a backend's
/// framebuffer origin. That adjustment answers "which end of a texture is row
/// zero"; this answers "where on the screen is it", and the screen's origin is
/// top left on every platform Flutter draws on.
({double x, double y})? projectPoint(
  Matrix4 viewProjection,
  Vector3 point, {
  required double width,
  required double height,
}) {
  final Vector4 clip = viewProjection * Vector4(point.x, point.y, point.z, 1.0);
  // Behind the eye, or exactly on the plane through it. Dividing by this would
  // fold the point back into view somewhere it is not, which is how a label
  // ends up on the opposite side of the screen from the thing it names.
  if (clip.w <= 1e-6) return null;
  final ndcX = clip.x / clip.w;
  final ndcY = clip.y / clip.w;
  // +Y is up in clip space and down on the glass, which is the one flip this
  // function owes its callers.
  return (x: (ndcX * 0.5 + 0.5) * width, y: (0.5 - ndcY * 0.5) * height);
}

/// The axis-aligned rectangle covering [box] on the glass, or null when none of
/// it is in front of the eye.
///
/// **A box straddling the near plane has no honest rectangle**, and this says so
/// by returning the whole viewport rather than by returning the projection of
/// the corners that happened to be in front. Those corners are a strict subset
/// of what is visible — the object continues off every edge — so their box is
/// too small, and a focus ring drawn to it sits inside the thing it is supposed
/// to surround. The viewport is the smallest rectangle that is certainly not
/// too small, which is the answer that cannot mislead.
///
/// Not clamped to the viewport otherwise: a caller that wants the on-screen
/// part can intersect, and one that wants to know the object is off to the left
/// cannot recover that from a clamped answer.
ScreenBounds? screenBoundsOfBox(
  Matrix4 viewProjection,
  Aabb3 box, {
  required double width,
  required double height,
}) {
  final min = box.min;
  final max = box.max;
  var left = double.infinity;
  var top = double.infinity;
  var right = double.negativeInfinity;
  var bottom = double.negativeInfinity;
  var behind = 0;

  final corner = Vector3.zero();
  for (var i = 0; i < 8; i++) {
    corner.setValues(
      (i & 1) == 0 ? min.x : max.x,
      (i & 2) == 0 ? min.y : max.y,
      (i & 4) == 0 ? min.z : max.z,
    );
    final at = projectPoint(
      viewProjection,
      corner,
      width: width,
      height: height,
    );
    if (at == null) {
      behind++;
      continue;
    }
    left = math.min(left, at.x);
    top = math.min(top, at.y);
    right = math.max(right, at.x);
    bottom = math.max(bottom, at.y);
  }

  if (behind == 8) return null;
  if (behind > 0) {
    return (left: 0.0, top: 0.0, right: width, bottom: height);
  }
  return (left: left, top: top, right: right, bottom: bottom);
}
