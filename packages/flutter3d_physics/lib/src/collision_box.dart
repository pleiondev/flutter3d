/// A part of `collision_shape.dart` — see the seal, there.
part of 'collision_shape.dart';

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
  bool overlapsWedge(
    Vector3 position,
    CollisionWedge wedge,
    Vector3 wedgePosition,
  ) => wedge.overlapsBox(wedgePosition, this, position);

  @override
  double raycast(
    Vector3 position,
    Vector3 origin,
    Vector3 direction,
    double maxDistance,
    Vector3 outNormal,
  ) => raycastBounds(position, origin, direction, maxDistance, outNormal);

  @override
  int get expandedPlaneCount => CollisionShape.boundsPlaneCount;

  @override
  // The bounding box *is* this shape, so there is nothing approximate about it
  // here. The other two shapes say the same words and mean less by them.
  int expandedPlanes(Vector3 position, Vector3 half, Float64List out) =>
      boundsExpandedPlanes(position, half, out);
}
