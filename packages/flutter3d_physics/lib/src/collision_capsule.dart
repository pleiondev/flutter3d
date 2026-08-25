/// A part of `collision_shape.dart` — see the seal, there.
part of 'collision_shape.dart';

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
  bool overlapsWedge(
    Vector3 position,
    CollisionWedge wedge,
    Vector3 wedgePosition,
  ) => wedge.overlapsCapsule(wedgePosition, this, position);

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

  @override
  int get expandedPlaneCount => CollisionShape.boundsPlaneCount;

  @override
  // **The box, and a capsule is not one.** A walking body swept as its bounding
  // box catches its shoulders on a corner it should round, which is a thing
  // players feel and no test here asserts. Saying so costs a line and is the
  // whole reason this method is abstract: the next person to want a capsule
  // swept as a capsule has one place to change and a comment admitting it was
  // never done.
  int expandedPlanes(Vector3 position, Vector3 half, Float64List out) =>
      boundsExpandedPlanes(position, half, out);
}
