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

  /// Half the total height, caps included — the sum [halfHeight] is not.
  ///
  /// The solver works with the segment and the radius separately, which is why
  /// nothing here adds them. It is for a caller sizing something against the
  /// capsule: a camera that must clear the top of a head, or a game placing a
  /// body so its feet land on a floor.
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
  bool overlapsHeightfield(
    Vector3 position,
    CollisionHeightfield field,
    Vector3 fieldPosition,
  ) => field.overlapsCapsule(fieldPosition, this, position);

  /// The segment's reach plus the radius, which is a capsule and not the box
  /// around it.
  ///
  /// **This is the shoulder the comment on [expandedPlanes] admitted to.** A
  /// walking body swept as its bounding box is grown by
  /// `radius·|nx| + (halfHeight + radius)·|ny| + radius·|nz|`, and against a
  /// face leaning forty-five degrees that is nearly half a radius too much —
  /// the corner it should have rounded, caught. Along any of the six axes the
  /// two answers are identical, which is why no face in this package could tell
  /// the difference until a ramp had one that was not an axis.
  @override
  double supportAlong(double nx, double ny, double nz) =>
      (ny * halfHeight).abs() + radius;

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
  // **The box, and against a box that is no approximation at all.** The six
  // faces of a bounding box are the six axes, and a capsule's reach along an
  // axis is exactly its bounding box's — see [supportAlong], where the
  // arithmetic is. What used to be wrong was the other half of the pair: a
  // capsule *moving* against a face that is not an axis was grown as a box, and
  // that is where the shoulders were. The growth is the mover's business now,
  // so this side of it can stay the cheap answer it always was.
  int expandedPlanes(Vector3 position, Vector3 half, Float64List out) =>
      boundsExpandedPlanes(position, half, out);
}
