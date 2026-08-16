import 'dart:math' as math;
import 'dart:typed_data';

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
/// ## Exact here, approximate when moving
///
/// Overlap decides outcomes — whether a rocket hit a monster, whether the
/// player is standing in a pickup — and being approximately right there is
/// being wrong in a way the player can see. The three original shapes are
/// exact against each other; [CollisionWedge] says on each of its own methods
/// where it is not, because a ramp is level geometry and nothing asks whether a
/// pickup is inside one.
///
/// Moving a body is the other trade, and [expandedPlanes] is where each shape
/// declares which side of it it takes. Box, sphere and capsule take the
/// bounding box, because stopping a centimetre early at a corner is invisible
/// and the exact version is a swept Minkowski sum with rounded edges, which is
/// a solver. A wedge does **not**, and cannot: its bounding box is a wall you
/// can stand on top of, which is the whole reason this method is abstract.
sealed class CollisionShape {
  const CollisionShape();

  /// Half the size of the axis-aligned box containing this shape.
  Vector3 get boundsHalfExtents;

  /// How many planes [expandedPlanes] writes, four doubles each.
  ///
  /// Asked before the write so the caller can size its buffer. Abstract for
  /// the same reason [expandedPlanes] is: a shape that answered six by
  /// inheritance and then wrote eight would have two of them silently dropped.
  int get expandedPlaneCount;

  /// This shape at [position], grown by [half], as a set of planes.
  ///
  /// **This is the one thing that moves a body**, and every sweep and every
  /// push in [CollisionWorld] goes through it. Written into [out] as four
  /// doubles a plane — the normal's three components, then `d` — with the solid
  /// being every point where `n · p <= d`, and the normals pointing outwards.
  /// Returns how many planes were written.
  ///
  /// Growing by [half] is what makes a *box* against this shape the same
  /// question as a *point* against this shape: the Minkowski sum of an
  /// axis-aligned box with a convex body is that body with each plane pushed
  /// out by `|n · half|`, which is closed form and needs no solver. A caller
  /// therefore sweeps its own shape by handing over its half-extents, and the
  /// answer has no rounded edges to iterate towards.
  ///
  /// Abstract, and deliberately so. Every shape here answers with
  /// [boundsExpandedPlanes], which is the bounding box — but it answers *out
  /// loud*. Before this, a shape that was not a box behaved like one because
  /// the world reached past it for `Collider.bounds`, and no test could tell:
  /// the fourth shape would have been a slope, and a slope that silently
  /// collides as its bounding box is a wall you can stand on top of.
  int expandedPlanes(Vector3 position, Vector3 half, Float64List out);

  /// The six planes of this shape's bounding box, grown by [half].
  ///
  /// In axis order — low face then high face, x then y then z — which the
  /// world's slab walk relies on to break ties between axes the way it always
  /// has.
  int boundsExpandedPlanes(Vector3 position, Vector3 half, Float64List out) {
    final extent = boundsHalfExtents;
    var i = 0;
    for (var axis = 0; axis < 3; axis++) {
      final grown = extent[axis] + half[axis];
      // The low face, whose outward normal points the other way.
      out[i] = 0.0;
      out[i + 1] = 0.0;
      out[i + 2] = 0.0;
      out[i + axis] = -1.0;
      out[i + 3] = grown - position[axis];
      i += 4;
      out[i] = 0.0;
      out[i + 1] = 0.0;
      out[i + 2] = 0.0;
      out[i + axis] = 1.0;
      out[i + 3] = position[axis] + grown;
      i += 4;
    }
    return 6;
  }

  /// How many planes [boundsExpandedPlanes] writes.
  static const int boundsPlaneCount = 6;

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

  /// Second half of the dispatch: this shape against a wedge.
  ///
  /// Added with [CollisionWedge], and the compiler naming every shape that had
  /// not implemented it is exactly what the double dispatch was chosen for — a
  /// `switch` over pairs would have compiled and answered wrongly.
  bool overlapsWedge(
    Vector3 position,
    CollisionWedge wedge,
    Vector3 wedgePosition,
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

  CollisionWedge.size(Vector3 size, {WedgeUphill uphill = WedgeUphill.positiveX})
      : this(size / 2.0, uphill: uphill);

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
      final grown = (nx * half.x).abs() + (ny * half.y).abs() + (nz * half.z).abs();
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
      final depth = scratch[base + 3] -
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
      final depth = scratch[base + 3] -
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
    for (final offset in <double>[-capsule.halfHeight, 0.0, capsule.halfHeight]) {
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

      if (approach.abs() < 1e-12) {
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
