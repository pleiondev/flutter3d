import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// A collision volume, positioned by whatever owns it.
///
/// Three shapes, and the choice is not arbitrary: a box is level geometry, a
/// sphere is a pickup or a projectile, a capsule is anything that walks.
/// Between them they cover every collider this game has, and every pair has a
/// closed-form test — no iterative solver, nothing that can fail to converge in
/// the middle of a step.
///
/// Named `Collision*` rather than `*Shape` on purpose: `flutter3d` already has
/// `SphereShape` and `CapsuleShape` for generating meshes, and an application
/// imports both packages.
///
/// ## How a pair is tested
///
/// By double dispatch, not by a table of cases. [overlaps] asks the *other*
/// shape to test itself against this one, so the concrete pair is resolved by
/// the language and each pair's mathematics lives on one of the two shapes it
/// concerns. Adding a fourth shape then means writing its own file and
/// implementing the visitor methods — the compiler names every case that is
/// missing, which a `switch` over pairs cannot do.
///
/// ## Exact here, approximate when sweeping
///
/// Everything below is exact. Overlap decides outcomes — whether a rocket hit a
/// monster, whether the player is standing in a pickup — and being
/// approximately right there is being wrong in a way the player can see.
/// Sweeping, in [CollisionWorld], runs against bounds instead: it moves bodies,
/// where stopping a centimetre early at a corner is invisible, and the exact
/// version is a swept Minkowski sum with rounded edges, which is a solver.
sealed class CollisionShape {
  const CollisionShape();

  /// Half the size of the axis-aligned box containing this shape.
  Vector3 get boundsHalfExtents;

  /// Writes the world bounds of this shape centred on [centre].
  void computeBounds(Vector3 centre, Aabb3 out) {
    final half = boundsHalfExtents;
    out
      ..min.setValues(centre.x - half.x, centre.y - half.y, centre.z - half.z)
      ..max.setValues(centre.x + half.x, centre.y + half.y, centre.z + half.z);
  }

  /// Whether this shape at [position] intersects [other] at [otherPosition].
  ///
  /// Implemented by handing the question to [other], which knows which of its
  /// visitor methods applies to a shape of this type.
  bool overlaps(Vector3 position, CollisionShape other, Vector3 otherPosition);

  /// Second half of the dispatch: this shape against a box.
  bool overlapsBox(Vector3 position, CollisionBox box, Vector3 boxPosition);

  /// Second half of the dispatch: this shape against a sphere.
  bool overlapsSphere(
    Vector3 position,
    CollisionSphere sphere,
    Vector3 spherePosition,
  );

  /// Second half of the dispatch: this shape against a capsule.
  bool overlapsCapsule(
    Vector3 position,
    CollisionCapsule capsule,
    Vector3 capsulePosition,
  );

  /// Distance along [direction] at which a ray from [origin] first meets this
  /// shape at [position], or a negative number for a miss.
  ///
  /// A ray that starts inside reports zero rather than missing — a shot fired
  /// from inside a monster still hits it.
  double raycast(
    Vector3 position,
    Vector3 origin,
    Vector3 direction,
    double maxDistance,
    Vector3 outNormal,
  );

  /// Ray against this shape's bounding box.
  ///
  /// The slab test, inherited by the shapes whose bounds are a good enough
  /// stand-in for them. It lives here rather than on the world because it is a
  /// property of a shape, not of a level.
  double raycastBounds(
    Vector3 position,
    Vector3 origin,
    Vector3 direction,
    double maxDistance,
    Vector3 outNormal,
  ) {
    final half = boundsHalfExtents;
    var tNear = 0.0;
    var tFar = maxDistance;
    var hitAxis = -1;
    var hitSign = 0.0;

    for (var axis = 0; axis < 3; axis++) {
      final lo = position[axis] - half[axis];
      final hi = position[axis] + half[axis];
      final o = origin[axis];
      final d = direction[axis];

      if (d.abs() < 1e-12) {
        if (o < lo || o > hi) return -1.0;
        continue;
      }

      final inverse = 1.0 / d;
      var enter = (lo - o) * inverse;
      var exit = (hi - o) * inverse;
      // Travelling towards +axis enters through the low face, whose outward
      // normal points the other way.
      final sign = d > 0.0 ? -1.0 : 1.0;
      if (enter > exit) {
        final swap = enter;
        enter = exit;
        exit = swap;
      }

      if (enter > tNear) {
        tNear = enter;
        hitAxis = axis;
        hitSign = sign;
      }
      if (exit < tFar) tFar = exit;
      if (tNear > tFar) return -1.0;
    }

    if (hitAxis < 0) return -1.0;
    outNormal.setZero();
    outNormal[hitAxis] = hitSign;
    return tNear;
  }
}

/// An axis-aligned box: level geometry, and the player.
///
/// Axis-aligned rather than oriented, which is a decision about the level
/// format — brushes never rotate. It makes a box against a box exactly a point
/// against one box grown by the other's half-extents, so the swept test is
/// analytic and cannot tunnel.
final class CollisionBox extends CollisionShape {
  CollisionBox(this.halfExtents);

  CollisionBox.size(Vector3 size) : halfExtents = size / 2.0;

  final Vector3 halfExtents;

  @override
  Vector3 get boundsHalfExtents => halfExtents;

  @override
  bool overlaps(
    Vector3 position,
    CollisionShape other,
    Vector3 otherPosition,
  ) => other.overlapsBox(otherPosition, this, position);

  @override
  bool overlapsBox(Vector3 position, CollisionBox box, Vector3 boxPosition) =>
      (position.x - boxPosition.x).abs() < halfExtents.x + box.halfExtents.x &&
      (position.y - boxPosition.y).abs() < halfExtents.y + box.halfExtents.y &&
      (position.z - boxPosition.z).abs() < halfExtents.z + box.halfExtents.z;

  @override
  bool overlapsSphere(
    Vector3 position,
    CollisionSphere sphere,
    Vector3 spherePosition,
  ) =>
      // One implementation per unordered pair; the sphere owns this one.
      sphere.overlapsBox(spherePosition, this, position);

  @override
  bool overlapsCapsule(
    Vector3 position,
    CollisionCapsule capsule,
    Vector3 capsulePosition,
  ) => capsule.overlapsBox(capsulePosition, this, position);

  @override
  double raycast(
    Vector3 position,
    Vector3 origin,
    Vector3 direction,
    double maxDistance,
    Vector3 outNormal,
  ) => raycastBounds(position, origin, direction, maxDistance, outNormal);
}

/// A sphere: pickups, projectiles, blast radii.
final class CollisionSphere extends CollisionShape {
  CollisionSphere(this.radius);

  final double radius;

  @override
  Vector3 get boundsHalfExtents => Vector3.all(radius);

  @override
  bool overlaps(
    Vector3 position,
    CollisionShape other,
    Vector3 otherPosition,
  ) => other.overlapsSphere(otherPosition, this, position);

  @override
  bool overlapsBox(Vector3 position, CollisionBox box, Vector3 boxPosition) {
    // Distance to the nearest point of the box, which for an axis-aligned box
    // is one clamp per axis.
    final dx = _axisGap(position.x - boxPosition.x, box.halfExtents.x);
    final dy = _axisGap(position.y - boxPosition.y, box.halfExtents.y);
    final dz = _axisGap(position.z - boxPosition.z, box.halfExtents.z);
    return dx * dx + dy * dy + dz * dz < radius * radius;
  }

  @override
  bool overlapsSphere(
    Vector3 position,
    CollisionSphere sphere,
    Vector3 spherePosition,
  ) {
    final reach = radius + sphere.radius;
    return position.distanceToSquared(spherePosition) < reach * reach;
  }

  @override
  bool overlapsCapsule(
    Vector3 position,
    CollisionCapsule capsule,
    Vector3 capsulePosition,
  ) {
    // Distance from a point to an upright segment.
    final dx = position.x - capsulePosition.x;
    final dz = position.z - capsulePosition.z;
    final dy = _axisGap(position.y - capsulePosition.y, capsule.halfHeight);
    final reach = radius + capsule.radius;
    return dx * dx + dy * dy + dz * dz < reach * reach;
  }

  @override
  double raycast(
    Vector3 position,
    Vector3 origin,
    Vector3 direction,
    double maxDistance,
    Vector3 outNormal,
  ) {
    final ox = origin.x - position.x;
    final oy = origin.y - position.y;
    final oz = origin.z - position.z;

    final b = ox * direction.x + oy * direction.y + oz * direction.z;
    final c = ox * ox + oy * oy + oz * oz - radius * radius;
    // Outside and pointing away.
    if (c > 0.0 && b > 0.0) return -1.0;

    final discriminant = b * b - c;
    if (discriminant < 0.0) return -1.0;

    var t = -b - math.sqrt(discriminant);
    if (t < 0.0) t = 0.0;
    if (t > maxDistance) return -1.0;

    outNormal.setValues(
      ox + direction.x * t,
      oy + direction.y * t,
      oz + direction.z * t,
    );
    if (outNormal.length2 > 0.0) outNormal.normalize();
    return t;
  }
}

/// An upright capsule: a segment of length `2 * halfHeight` with [radius]
/// around it.
///
/// Upright rather than arbitrary, because everything that uses one stands on
/// the floor. A monster falling over is an animation, not a physics event.
final class CollisionCapsule extends CollisionShape {
  CollisionCapsule({required this.radius, required this.halfHeight})
    : assert(radius > 0.0),
      assert(halfHeight >= 0.0);

  final double radius;

  /// Half the distance between the two cap centres — **not** half the total
  /// height, which is `halfHeight + radius`.
  final double halfHeight;

  double get totalHalfHeight => halfHeight + radius;

  @override
  Vector3 get boundsHalfExtents => Vector3(radius, halfHeight + radius, radius);

  @override
  bool overlaps(
    Vector3 position,
    CollisionShape other,
    Vector3 otherPosition,
  ) => other.overlapsCapsule(otherPosition, this, position);

  @override
  bool overlapsBox(Vector3 position, CollisionBox box, Vector3 boxPosition) {
    // Both are axis-aligned and the capsule stands upright, so the horizontal
    // gap does not depend on which point of the segment is closest and the
    // vertical gap is between two intervals. That makes this exact without any
    // of the machinery general segment-to-box distance needs.
    final dx = _axisGap(position.x - boxPosition.x, box.halfExtents.x);
    final dz = _axisGap(position.z - boxPosition.z, box.halfExtents.z);
    final dy = _intervalGap(
      position.y - halfHeight,
      position.y + halfHeight,
      boxPosition.y - box.halfExtents.y,
      boxPosition.y + box.halfExtents.y,
    );
    return dx * dx + dy * dy + dz * dz < radius * radius;
  }

  @override
  bool overlapsSphere(
    Vector3 position,
    CollisionSphere sphere,
    Vector3 spherePosition,
  ) => sphere.overlapsCapsule(spherePosition, this, position);

  @override
  bool overlapsCapsule(
    Vector3 position,
    CollisionCapsule capsule,
    Vector3 capsulePosition,
  ) {
    final dx = position.x - capsulePosition.x;
    final dz = position.z - capsulePosition.z;
    final dy = _intervalGap(
      position.y - halfHeight,
      position.y + halfHeight,
      capsulePosition.y - capsule.halfHeight,
      capsulePosition.y + capsule.halfHeight,
    );
    final reach = radius + capsule.radius;
    return dx * dx + dy * dy + dz * dz < reach * reach;
  }

  @override
  double raycast(
    Vector3 position,
    Vector3 origin,
    Vector3 direction,
    double maxDistance,
    Vector3 outNormal,
  ) =>
      // Through the bounds, which for an upright capsule differ from the truth
      // only at the rounded caps. A monster shot at the very top of the head is
      // the only case, and it resolves in the player's favour.
      raycastBounds(position, origin, direction, maxDistance, outNormal);
}

/// How far [offset] lies outside `[-half, half]`. Zero when inside.
double _axisGap(double offset, double half) {
  final distance = offset.abs() - half;
  return distance > 0.0 ? distance : 0.0;
}

/// The gap between two intervals on a line. Zero when they overlap.
double _intervalGap(double aMin, double aMax, double bMin, double bMax) {
  if (aMax < bMin) return bMin - aMax;
  if (bMax < aMin) return aMin - bMax;
  return 0.0;
}
