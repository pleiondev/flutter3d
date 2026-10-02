import 'package:vector_math/vector_math.dart';

/// The affine reflection of world space across the plane through [point]
/// with unit normal [normal] — `P4`.
///
/// `x' = x - 2 (n·x - n·p) n`. Its own inverse, and it reverses handedness,
/// so whatever is drawn through it winds the other way round.
Matrix4 mirrorAcrossPlane(Vector3 normal, Vector3 point) {
  final n = normal.normalized();
  final d = -n.dot(point);
  return Matrix4(
    1.0 - 2.0 * n.x * n.x,
    -2.0 * n.y * n.x,
    -2.0 * n.z * n.x,
    0.0,
    -2.0 * n.x * n.y,
    1.0 - 2.0 * n.y * n.y,
    -2.0 * n.z * n.y,
    0.0,
    -2.0 * n.x * n.z,
    -2.0 * n.y * n.z,
    1.0 - 2.0 * n.z * n.z,
    0.0,
    -2.0 * d * n.x,
    -2.0 * d * n.y,
    -2.0 * d * n.z,
    1.0,
  );
}

/// [projection] with its near plane moved onto [plane], or null where that
/// cannot be done — `P4`'s clip plane.
///
/// **The clip plane is the projection's own near plane, and not a plane the
/// shaders test.** No stage here has a clip distance to write, and adding
/// one would be an output on every vertex stage and a branch on every
/// backend for the one pass that wants it. Lengyel's oblique frustum
/// (*Oblique View Frustum Depth Projection and Clipping*, 2005) gets the same
/// cut out of the rasteriser's own near clip, for the price of the depth
/// precision the reflection does not need.
///
/// [plane] is in the eye space [projection] maps from, as `(n, d)` with
/// `n·v + d >= 0` on the side that is kept; the eye has to be on the other
/// side, which is what a mirrored camera below a mirror is. The matrix is the
/// engine's: near at depth nought and far at one, the convention every
/// camera builds for before `toDepthRange` turns it into a device's.
///
/// What it costs is the far plane, which tilts to pass through the frustum's
/// far corner on the plane's side: something far off to the other side can
/// be cut by it. A reflection is mostly of what is near the mirror.
///
/// Null when the plane does not face away from the eye — a camera behind
/// the mirror, or level with it — since there is then nothing in front of
/// the mirror for the near plane to stand on.
Matrix4? obliqueNearPlane(Matrix4 projection, Vector4 plane) {
  // The eye is the origin of its own space, so `d` is which side it is on.
  if (plane.w >= 0.0) return null;
  // The far corner of the frustum on the plane's side, in eye space: where
  // the clip-space plane leans, at the far plane.
  final inverse = Matrix4.copy(projection);
  if (inverse.invert() == 0.0) return null;
  final clipPlane = inverse.transposed().transform(plane.clone());
  final corner = inverse.transform(
    Vector4(_sign(clipPlane.x), _sign(clipPlane.y), 1.0, 1.0),
  );
  // The fourth row of the projection takes `corner` to w = 1 by
  // construction; the third becomes the plane, scaled so the far plane
  // `w - z = 0` still passes through it.
  final along = plane.dot(corner);
  if (along <= 0.0) return null;
  final row = plane.scaled(1.0 / along);
  return Matrix4.copy(projection)..setRow(2, row);
}

/// The plane through [point] with [normal], in the eye space [view] maps
/// world space into, as `obliqueNearPlane` takes it — [offset] metres
/// further along the normal's opposite, so a surface standing in the plane
/// keeps its foot in the picture.
Vector4 planeInEyeSpace(
  Matrix4 view,
  Vector3 normal,
  Vector3 point, {
  double offset = 0.0,
}) {
  final n = normal.normalized();
  final world = Vector4(n.x, n.y, n.z, -n.dot(point) + offset);
  // A plane goes through the inverse transpose of what moves the points.
  final inverse = Matrix4.copy(view)..invert();
  return inverse.transposed().transform(world);
}

double _sign(double value) => value > 0.0
    ? 1.0
    : value < 0.0
    ? -1.0
    : 0.0;
