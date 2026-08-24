import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';
import 'tolerances.dart';

// **Parts, not libraries, and not by preference.** [CollisionShape] is `sealed`,
// and Dart lets a sealed type be extended only from inside its own library — the
// whole point of the seal being that a `switch` over the shapes is checked for
// exhaustiveness. So the choice was never between one file and four libraries;
// it was between one file and four parts of one. The docstring below already
// promised this shape: "adding a fourth shape then means writing its own file".
part 'collision_box.dart';
part 'collision_sphere.dart';
part 'collision_capsule.dart';
part 'collision_wedge.dart';

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

      if (d.abs() < Nearly.parallel) {
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
