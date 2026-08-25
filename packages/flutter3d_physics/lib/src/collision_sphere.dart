/// A part of `collision_shape.dart` — see the seal, there.
part of 'collision_shape.dart';

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
  bool overlapsWedge(
    Vector3 position,
    CollisionWedge wedge,
    Vector3 wedgePosition,
  ) => wedge.overlapsSphere(wedgePosition, this, position);

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

  @override
  int get expandedPlaneCount => CollisionShape.boundsPlaneCount;

  @override
  // A cube, when it is being pushed out of the way of something. Nothing that
  // sweeps is a sphere today — they are pickups and projectiles, and a
  // projectile is a ray — so this is the cheap answer to a question nobody
  // asks, and it is written down rather than assumed.
  int expandedPlanes(Vector3 position, Vector3 half, Float64List out) =>
      boundsExpandedPlanes(position, half, out);
}
