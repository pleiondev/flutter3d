import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' hide Ray;

/// Returned instead of a distance when nothing was hit.
///
/// A sentinel rather than `double?`: these run once per triangle of a mesh, and
/// a nullable double allocates a box on every miss. `-1` is unambiguous because
/// every function here rejects intersections behind the ray's origin.
const double kNoHit = -1.0;

/// A ray: an origin and a direction.
///
/// The direction is **not** normalized automatically, and that is deliberate.
/// Testing a mesh happens in the mesh's local space, which means transforming
/// the ray by the inverse world matrix — and under scale that changes the
/// direction's length. Leaving it alone is what keeps the returned `t` measured
/// in the original space's units, so distances from differently scaled objects
/// remain comparable. Call [normalizeDirection] when you want a unit ray.
///
/// A mutable object with `out`-style methods, because picking runs inside a
/// pointer-move handler and should not allocate per candidate mesh.
final class Ray {
  Ray.zero() : origin = Vector3.zero(), direction = Vector3(0.0, 0.0, -1.0);

  Ray(Vector3 origin, Vector3 direction)
    : origin = origin.clone(),
      direction = direction.clone();

  final Vector3 origin;
  final Vector3 direction;

  void setFrom(Vector3 origin, Vector3 direction) {
    this.origin.setFrom(origin);
    this.direction.setFrom(direction);
  }

  void copyFrom(Ray other) => setFrom(other.origin, other.direction);

  /// Normalizes [direction] **in place** and returns this ray.
  ///
  /// In place, not via `normalized()`: that returns a new vector and leaves the
  /// original untouched, and a caller that reads its own field afterwards gets
  /// the un-normalized value. The renderer already lost an afternoon to exactly
  /// that shape of bug with light directions.
  Ray normalizeDirection() {
    if (direction.length2 > 0.0) direction.normalize();
    return this;
  }

  /// The point at distance [t] along the ray.
  Vector3 pointAt(double t, [Vector3? out]) {
    final result = out ?? Vector3.zero();
    result
      ..setFrom(direction)
      ..scale(t)
      ..add(origin);
    return result;
  }

  /// Rewrites [out] as this ray expressed in the space [inverse] maps into.
  ///
  /// [inverse] is the *inverse* of the target space's transform — for a mesh,
  /// `node.inverseWorldMatrix`. Transforming the ray is much cheaper than
  /// transforming the mesh's triangles, and it is the only version that stays
  /// cheap as the triangle count grows.
  Ray transformInto(Matrix4 inverse, Ray out) {
    out.origin.setFrom(origin);
    inverse.transform3(out.origin);
    out.direction.setFrom(direction);
    inverse.rotate3(out.direction);
    return out;
  }

  @override
  String toString() => 'Ray($origin -> $direction)';
}

/// Distance along [ray] to [box], or [kNoHit].
///
/// A ray starting inside the box returns `0`: for picking, "the click was inside
/// this object" is a hit at zero distance, not a hit at the far wall.
double rayAabb(Ray ray, Aabb3 box) {
  final o = ray.origin;
  final d = ray.direction;
  final min = box.min;
  final max = box.max;

  var tMin = -double.infinity;
  var tMax = double.infinity;

  for (var axis = 0; axis < 3; axis++) {
    final origin = o[axis];
    final direction = d[axis];
    final lo = min[axis];
    final hi = max[axis];

    if (direction.abs() < 1e-20) {
      // Parallel to this slab: either always inside it, or never.
      if (origin < lo || origin > hi) return kNoHit;
      continue;
    }

    final inverse = 1.0 / direction;
    var near = (lo - origin) * inverse;
    var far = (hi - origin) * inverse;
    if (near > far) {
      final swap = near;
      near = far;
      far = swap;
    }
    if (near > tMin) tMin = near;
    if (far < tMax) tMax = far;
    if (tMin > tMax) return kNoHit;
  }

  if (tMax < 0.0) return kNoHit;
  return tMin < 0.0 ? 0.0 : tMin;
}

/// Distance along [ray] to a sphere, or [kNoHit]. Inside counts as `0`.
double raySphere(Ray ray, Vector3 centre, double radius) {
  if (radius <= 0.0) return kNoHit;

  // Solved with the origin-to-centre vector rather than by expanding the
  // quadratic, which keeps the numbers small when the sphere is far away.
  final ocX = ray.origin.x - centre.x;
  final ocY = ray.origin.y - centre.y;
  final ocZ = ray.origin.z - centre.z;

  final d = ray.direction;
  final a = d.x * d.x + d.y * d.y + d.z * d.z;
  if (a < 1e-20) return kNoHit;

  final b = 2.0 * (ocX * d.x + ocY * d.y + ocZ * d.z);
  final c = ocX * ocX + ocY * ocY + ocZ * ocZ - radius * radius;

  final discriminant = b * b - 4.0 * a * c;
  if (discriminant < 0.0) return kNoHit;

  final root = math.sqrt(discriminant);
  final inverse = 1.0 / (2.0 * a);
  final near = (-b - root) * inverse;
  if (near >= 0.0) return near;

  final far = (-b + root) * inverse;
  if (far < 0.0) return kNoHit;
  return 0.0; // the origin is inside
}

/// Möller–Trumbore ray/triangle intersection.
///
/// Returns the distance along [ray], or [kNoHit]. When it hits, [outUv] receives
/// the barycentric coordinates `(u, v)` of the second and third vertices, which
/// is what interpolating a normal or a texture coordinate at the hit needs.
///
/// The classic formulation: no plane equation, no separate inside test, and no
/// precomputed per-triangle data — which matters because the alternative would
/// mean building and invalidating an acceleration structure per mesh.
double rayTriangle(
  Ray ray,
  Vector3 a,
  Vector3 b,
  Vector3 c, {
  Vector2? outUv,
  bool cullBackFace = false,
}) {
  final e1x = b.x - a.x, e1y = b.y - a.y, e1z = b.z - a.z;
  final e2x = c.x - a.x, e2y = c.y - a.y, e2z = c.z - a.z;

  final d = ray.direction;
  // p = direction x edge2
  final px = d.y * e2z - d.z * e2y;
  final py = d.z * e2x - d.x * e2z;
  final pz = d.x * e2y - d.y * e2x;

  final determinant = e1x * px + e1y * py + e1z * pz;

  // A determinant at zero means the ray is parallel to the triangle's plane, or
  // the triangle is degenerate. Both are misses, and both would divide by zero.
  if (cullBackFace) {
    if (determinant < 1e-12) return kNoHit;
  } else if (determinant.abs() < 1e-12) {
    return kNoHit;
  }

  final inverse = 1.0 / determinant;

  final tx = ray.origin.x - a.x;
  final ty = ray.origin.y - a.y;
  final tz = ray.origin.z - a.z;

  final u = (tx * px + ty * py + tz * pz) * inverse;
  if (u < 0.0 || u > 1.0) return kNoHit;

  // q = t x edge1
  final qx = ty * e1z - tz * e1y;
  final qy = tz * e1x - tx * e1z;
  final qz = tx * e1y - ty * e1x;

  final v = (d.x * qx + d.y * qy + d.z * qz) * inverse;
  if (v < 0.0 || u + v > 1.0) return kNoHit;

  final t = (e2x * qx + e2y * qy + e2z * qz) * inverse;
  if (t < 0.0) return kNoHit;

  outUv?.setValues(u, v);
  return t;
}
