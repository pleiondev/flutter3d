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
part 'collision_heightfield.dart';

/// A collision volume, positioned by whatever owns it.
///
/// Five shapes, and the choice is not arbitrary: a box is level geometry, a
/// sphere is a pickup or a projectile, a capsule is anything that walks, a
/// wedge is a ramp, and a heightfield is the ground a game with hills in it is
/// played on. Every pair has a closed-form test — no iterative solver, nothing
/// that can fail to converge in the middle of a step.
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
/// concerns. Adding a shape then means writing its own file and implementing
/// the visitor methods — the compiler names every case that is missing, which a
/// `switch` over pairs cannot do. That is not a claim about a future: it is
/// what happened twice, once for [CollisionWedge] and once for
/// [CollisionHeightfield], and both times the compiler wrote the list.
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
///
/// ## One solid, or several
///
/// [expandedPlanes] describes a shape as one convex solid, which four of the
/// five are. Ground is not, and cannot be made so — see [partsIn], which is
/// the door a shape with a dent in it comes in through, and [partSeams], which
/// is how it says that the joins between its pieces are not surfaces.
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

  /// How far this shape reaches from its centre along the unit direction
  /// `(nx, ny, nz)`.
  ///
  /// **The support function, and it is what "grown by" above really means.**
  /// Every plane a sweep tests is pushed out by exactly this much, and the
  /// default here — the box of [boundsHalfExtents] — is why a capsule used to
  /// catch its shoulders on a corner it should have rounded. For an axis
  /// normal the box answer and the true one agree for every shape in this file,
  /// which is why nothing changed the day this arrived: they part company only
  /// on a face that is not an axis, and until [CollisionWedge] there were none.
  double supportAlong(double nx, double ny, double nz) {
    final half = boundsHalfExtents;
    return (nx * half.x).abs() + (ny * half.y).abs() + (nz * half.z).abs();
  }

  // MARK: - Convex pieces

  /// Which convex parts of this shape lie in the world box [min]..[max].
  ///
  /// **The door a shape that is not convex comes in through.** Everything above
  /// assumes one solid described by one set of planes, which is a fair
  /// assumption for a box, a sphere, a capsule and a ramp and a false one for
  /// ground: two triangles meeting along a ridge make a shape with a dent in
  /// it, and no intersection of half-spaces has a dent. So a query names the
  /// region it cares about and the shape hands back the convex pieces near it,
  /// and the plane walk runs once per piece.
  ///
  /// Part numbers are written into [out] and the **total** is returned, which
  /// may be more than [out] could hold: a caller sizes its buffer from the
  /// answer and asks again rather than quietly colliding with part of the
  /// ground.
  ///
  /// The default is one part numbered zero, and unlike [expandedPlanes] that
  /// default is not a lie waiting to be found: a convex shape genuinely is one
  /// piece, whatever box it is asked about.
  int partsIn(Vector3 position, Vector3 min, Vector3 max, Int32List out) {
    if (out.isNotEmpty) out[0] = 0;
    return 1;
  }

  /// How many planes [partPlanes] writes, for any part of this shape.
  int get partPlaneCount => expandedPlaneCount;

  /// One convex part of this shape at [position], grown to hold [mover].
  ///
  /// The same four-doubles-a-plane form [expandedPlanes] writes, and for a
  /// convex shape it is that method — with the growth taken from the mover's
  /// [supportAlong] rather than from its bounding box, which is the difference
  /// between a capsule that rounds a corner and one that does not.
  int partPlanes(
    int part,
    Vector3 position,
    CollisionShape mover,
    Float64List out,
  ) => expandedPlanes(position, mover.boundsHalfExtents, out);

  /// Which of [part]'s planes face another part of this same shape, as a bit
  /// per plane.
  ///
  /// **A seam is not a surface, and reporting one is the bug every collider
  /// made of triangles is known for.** Where two pieces of ground meet, each
  /// piece ends in a vertical face that the other piece continues through; a
  /// body sliding across the join enters that face and is stopped dead by a
  /// wall nobody drew, or shoved out of it and into the air. [CollisionWorld]
  /// refuses to report a contact on a plane named here.
  ///
  /// Nothing for a convex shape: it has no other part to meet.
  int partSeams(int part) => 0;

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

  /// Second half of the dispatch: this shape against a field of ground.
  bool overlapsHeightfield(
    Vector3 position,
    CollisionHeightfield field,
    Vector3 fieldPosition,
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
