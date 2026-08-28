/// A part of `collision_shape.dart` — see the seal, there.
part of 'collision_shape.dart';

/// Which way a [CollisionWedge] climbs.
///
/// Four directions and no angle, because a level document has no rotation in
/// it: a brush is placed by its centre and its size, and a ramp that could
/// point anywhere would be the first thing in this format needing a transform.
/// The steepness is the wedge's own proportions — a box twice as long as it is
/// tall is a ramp of twenty-six degrees — which keeps one number out of the
/// format and makes the slope something a level author can see in the sizes.
enum WedgeUphill {
  positiveX(1.0, 0.0),
  negativeX(-1.0, 0.0),
  positiveZ(0.0, 1.0),
  negativeZ(0.0, -1.0);

  const WedgeUphill(this.x, this.z);

  /// The horizontal direction the surface rises towards, as a unit vector.
  final double x;
  final double z;

  /// Which axis this climbs along: 0 for x, 2 for z.
  int get axis => x != 0.0 ? 0 : 2;

  /// The sign along that axis.
  double get sign => x != 0.0 ? x : z;
}

/// A box with one edge cut away: a ramp.
///
/// **The fourth shape, and the one the third commit of the slope groundwork
/// was written to make possible.** While `CollisionWorld` moved bodies by
/// reading `Collider.bounds`, a wedge would have collided as its own bounding
/// box — which is a wall you can stand on top of, and no test would have said
/// so. It is a shape now because [expandedPlanes] is abstract and this one
/// answers with five real faces.
///
/// The solid fills its bounding box at the high end and tapers to an edge at
/// the low one, so the sloping face passes through the centre. That is not a
/// simplification: it is what makes the ramp's steepness readable from the size
/// a level author typed.
final class CollisionWedge extends CollisionShape {
  CollisionWedge(this.halfExtents, {this.uphill = WedgeUphill.positiveX})
    : assert(halfExtents.x > 0.0),
      assert(halfExtents.y > 0.0),
      assert(halfExtents.z > 0.0);

  CollisionWedge.size(
    Vector3 size, {
    WedgeUphill uphill = WedgeUphill.positiveX,
  }) : this(size / 2.0, uphill: uphill);

  /// Half the box this wedge is cut from.
  final Vector3 halfExtents;

  final WedgeUphill uphill;

  @override
  Vector3 get boundsHalfExtents => halfExtents;

  /// How far the surface rises for every metre travelled up it.
  double get gradient => halfExtents.y / halfExtents[uphill.axis];

  /// The surface's outward normal, which is what a body standing on it feels.
  Vector3 get slopeNormal {
    final run = halfExtents[uphill.axis];
    final rise = halfExtents.y;
    final length = math.sqrt(run * run + rise * rise);
    final out = Vector3.zero();
    out[uphill.axis] = -uphill.sign * rise / length;
    out.y = run / length;
    return out;
  }

  @override
  int get expandedPlaneCount => 5;

  /// Five faces: the floor, two sides, the wall at the top, and the slope.
  ///
  /// **The low end has no face at all**, which is the difference between this
  /// and the box it is cut from, and the whole of what makes it walkable.
  @override
  int expandedPlanes(Vector3 position, Vector3 half, Float64List out) {
    final axis = uphill.axis;
    final side = axis == 0 ? 2 : 0;
    var i = 0;

    void plane(double nx, double ny, double nz, double through) {
      // Grown by the moving body's own extent along this normal, which is the
      // Minkowski sum in closed form — see [CollisionShape.expandedPlanes].
      final grown =
          (nx * half.x).abs() + (ny * half.y).abs() + (nz * half.z).abs();
      out[i] = nx;
      out[i + 1] = ny;
      out[i + 2] = nz;
      out[i + 3] = through + grown;
      i += 4;
    }

    // The floor.
    plane(0.0, -1.0, 0.0, -(position.y - halfExtents.y));
    // The two sides, which are whichever horizontal axis this does not climb.
    final sideLow = position[side] - halfExtents[side];
    final sideHigh = position[side] + halfExtents[side];
    plane(side == 0 ? -1.0 : 0.0, 0.0, side == 2 ? -1.0 : 0.0, -sideLow);
    plane(side == 0 ? 1.0 : 0.0, 0.0, side == 2 ? 1.0 : 0.0, sideHigh);
    // The wall at the top of the climb.
    final topEnd = position[axis] + uphill.sign * halfExtents[axis];
    plane(
      axis == 0 ? uphill.sign : 0.0,
      0.0,
      axis == 2 ? uphill.sign : 0.0,
      uphill.sign * topEnd,
    );
    // The slope, which passes through the centre.
    final normal = slopeNormal;
    plane(
      normal.x,
      normal.y,
      normal.z,
      normal.x * position.x + normal.y * position.y + normal.z * position.z,
    );
    return 5;
  }

  @override
  bool overlaps(
    Vector3 position,
    CollisionShape other,
    Vector3 otherPosition,
  ) => other.overlapsWedge(otherPosition, this, position);

  /// Whether [point] is inside this wedge at [position], allowing [margin].
  ///
  /// The convex test, and the only exact thing here: a point is inside a convex
  /// solid when it is behind every one of its faces.
  bool containsPoint(Vector3 position, Vector3 point, {double margin = 0.0}) {
    final scratch = Float64List(20);
    final count = expandedPlanes(position, _noGrowth, scratch);
    for (var i = 0; i < count; i++) {
      final base = i * 4;
      final depth =
          scratch[base + 3] -
          (scratch[base] * point.x +
              scratch[base + 1] * point.y +
              scratch[base + 2] * point.z);
      if (depth < -margin) return false;
    }
    return true;
  }

  @override
  bool overlapsBox(Vector3 position, CollisionBox box, Vector3 boxPosition) {
    // The box grown by nothing against this wedge grown by the box: the same
    // Minkowski sum the sweep uses, asked at one instant. **Conservative at the
    // slope's two long edges**, where the exact answer needs the axes that come
    // from crossing this shape's slanted edge with the box's — it reports a
    // touch up to a corner's width early. A ramp is level geometry and the
    // question is asked by triggers and pickups, so the cost is that a coin
    // resting in the crease of a ramp is collected slightly early.
    final scratch = Float64List(20);
    final count = expandedPlanes(position, box.halfExtents, scratch);
    for (var i = 0; i < count; i++) {
      final base = i * 4;
      final depth =
          scratch[base + 3] -
          (scratch[base] * boxPosition.x +
              scratch[base + 1] * boxPosition.y +
              scratch[base + 2] * boxPosition.z);
      if (depth <= 0.0) return false;
    }
    return true;
  }

  @override
  bool overlapsSphere(
    Vector3 position,
    CollisionSphere sphere,
    Vector3 spherePosition,
  ) =>
      // The faces pushed out by the radius. Exact against a face, and early by
      // at most the radius at an edge — see [overlapsBox].
      containsPoint(position, spherePosition, margin: sphere.radius);

  @override
  bool overlapsCapsule(
    Vector3 position,
    CollisionCapsule capsule,
    Vector3 capsulePosition,
  ) {
    // The two cap centres and the middle, each as a sphere. A capsule standing
    // on a ramp touches it at one end, which the ends catch; the middle is
    // there so a long capsule lying across a thin ramp is not missed entirely.
    final probe = Vector3.copy(capsulePosition);
    for (final offset in <double>[
      -capsule.halfHeight,
      0.0,
      capsule.halfHeight,
    ]) {
      probe.y = capsulePosition.y + offset;
      if (containsPoint(position, probe, margin: capsule.radius)) return true;
    }
    return false;
  }

  @override
  bool overlapsWedge(
    Vector3 position,
    CollisionWedge wedge,
    Vector3 wedgePosition,
  ) =>
      // Two ramps against each other, which is a question no level has ever
      // asked: brushes do not move and a generator does not stack ramps. The
      // bounding boxes, and said out loud rather than dressed up — the day
      // something needs this it needs a real answer, not this one made subtler.
      (position.x - wedgePosition.x).abs() <
          halfExtents.x + wedge.halfExtents.x &&
      (position.y - wedgePosition.y).abs() <
          halfExtents.y + wedge.halfExtents.y &&
      (position.z - wedgePosition.z).abs() <
          halfExtents.z + wedge.halfExtents.z;

  @override
  double raycast(
    Vector3 position,
    Vector3 origin,
    Vector3 direction,
    double maxDistance,
    Vector3 outNormal,
  ) {
    // **Exact**, unlike the overlaps above, and for a reason worth stating: a
    // ray against a convex solid is the same plane walk the sweep does, with no
    // edge cases at all. A shot that grazes a ramp hits the ramp.
    final scratch = Float64List(20);
    final count = expandedPlanes(position, _noGrowth, scratch);
    var near = 0.0;
    var far = maxDistance;
    var entering = -1;

    for (var i = 0; i < count; i++) {
      final base = i * 4;
      final nx = scratch[base];
      final ny = scratch[base + 1];
      final nz = scratch[base + 2];
      final approach = nx * direction.x + ny * direction.y + nz * direction.z;
      final outside =
          nx * origin.x + ny * origin.y + nz * origin.z - scratch[base + 3];

      if (approach.abs() < Nearly.parallel) {
        if (outside > 0.0) return -1.0;
        continue;
      }
      final t = -outside / approach;
      if (approach < 0.0) {
        if (t > near) {
          near = t;
          entering = i;
        }
      } else if (t < far) {
        far = t;
      }
      if (near > far) return -1.0;
    }

    if (near > maxDistance) return -1.0;
    if (entering < 0) {
      // Started inside, which is a hit at nothing — the same answer a sphere
      // gives a shot fired from within a monster.
      outNormal.setValues(0.0, 1.0, 0.0);
      return 0.0;
    }
    final base = entering * 4;
    outNormal.setValues(scratch[base], scratch[base + 1], scratch[base + 2]);
    return near;
  }
}

/// Nothing to grow by, for the queries that ask about a point rather than a
/// body.
final Vector3 _noGrowth = Vector3.zero();

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
