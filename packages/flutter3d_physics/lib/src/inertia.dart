/// How hard a shape is to turn.
///
/// ## Three numbers, not nine
///
/// Every shape here is symmetric about its own three axes, and a solid with
/// that symmetry has a diagonal inertia tensor in those axes: the products of
/// inertia integrate an odd function over a symmetric body and vanish. So a
/// tensor in body space is three principal moments, carried as a [Vector3],
/// and a full matrix appears only once the body is turned — see
/// `RigidBody.inverseInertiaWorld`.
///
/// ## Two of the five are approximations, and say so
///
/// * **A wedge is treated as its bounding box.** The true solid is half the
///   box, with its centre of mass a sixth of the way towards the low side and
///   a tensor that is no longer diagonal about the box centre. A body's centre
///   is its collider's centre here, so honouring the wedge means moving one of
///   the two; until a wedge has to tumble convincingly, the box it sits in
///   turns close enough.
/// * **A heightfield is treated as its bounding box too.** It is ground, and
///   ground does not turn; the answer exists so that [inertiaFor] has one for
///   every shape the sealed class has, rather than a throw a game finds later.
library;

import 'package:vector_math/vector_math.dart';

import 'collision_shape.dart';

/// The principal moments of inertia of [shape] with [mass] kilograms spread
/// evenly through it, about its own centre and in its own axes.
///
/// Kilogram square metres. Zero for a [mass] of zero or less — what such a
/// body's inverse should be is `RigidBody`'s decision, not this one's.
Vector3 inertiaFor(CollisionShape shape, double mass) {
  if (mass <= 0.0) return Vector3.zero();
  return switch (shape) {
    CollisionBox(:final halfExtents) => _box(halfExtents, mass),
    CollisionSphere(:final radius) => Vector3.all(0.4 * mass * radius * radius),
    CollisionCapsule(:final radius, :final halfHeight) => _capsule(
      radius,
      halfHeight,
      mass,
    ),
    CollisionWedge(:final halfExtents) => _box(halfExtents, mass),
    CollisionHeightfield() => _box(shape.boundsHalfExtents, mass),
    final CustomShape custom => custom.inertia(mass),
  };
}

/// `m/12 · (w² + d²)` with the full widths, which is `m/3 · (b² + c²)` with
/// the half extents the shape keeps.
Vector3 _box(Vector3 half, double mass) {
  final x2 = half.x * half.x;
  final y2 = half.y * half.y;
  final z2 = half.z * half.z;
  final third = mass / 3.0;
  return Vector3(third * (y2 + z2), third * (x2 + z2), third * (x2 + y2));
}

/// An upright capsule: a cylinder of half length [halfHeight] and two
/// hemispherical caps, the mass split between them by volume.
///
/// **Not a cylinder of the total height**, which is the easy answer and puts
/// mass in the corners a capsule has rounded off. The difference is largest
/// for the short, round capsules a character stands in, and at a [halfHeight]
/// of zero this has to be a sphere — `rotation_test.dart` holds both ends.
///
/// Each cap about the centre is `ms · (2/5 r² + h² + 3/4 h r)` for the pair:
/// a hemisphere's own `2/5 mr²` about its flat face, moved to its centroid
/// three-eighths of a radius out, and then on to the capsule's middle.
Vector3 _capsule(double r, double h, double mass) {
  final r2 = r * r;
  // π cancels out of the ratio: a cylinder of 2h·r² against a sphere of 4/3·r³.
  final cylinderVolume = 2.0 * h * r2;
  final capsVolume = 4.0 / 3.0 * r2 * r;
  final cylinder = mass * cylinderVolume / (cylinderVolume + capsVolume);
  final caps = mass - cylinder;

  final axial = cylinder * 0.5 * r2 + caps * 0.4 * r2;
  final across =
      cylinder * (0.25 * r2 + h * h / 3.0) +
      caps * (0.4 * r2 + h * h + 0.75 * h * r);
  return Vector3(across, axial, across);
}
