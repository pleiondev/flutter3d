import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import '../collision_shape.dart';
import '../portable_math.dart';
import '../rigid_body.dart';
import 'fluid_medium.dart';
import 'fluid_solver.dart';
import 'liquid_body.dart';
import 'vessel_shape.dart';

/// How much of [shape], centred at [centre], is below the plane
/// `up · p = height` (all in one frame): exactly, for the shapes a body can
/// have that hold a volume — a sphere by its cap, π h²(3R − h)/3; a box by
/// cutting it as a closed mesh; an upright capsule as a surface of
/// revolution. Nought for shapes with no inside: a heightfield, a wedge
/// ramp.
double submergedVolume(
  CollisionShape shape,
  Vector3 centre,
  Vector3 up,
  double height,
) {
  final depth = height - up.dot(centre);
  switch (shape) {
    case CollisionSphere(:final radius):
      final h = (radius + depth).clamp(0.0, 2.0 * radius);
      return math.pi * h * h * (3.0 * radius - h) / 3.0;
    case CollisionBox(:final halfExtents):
      return _box(halfExtents).volumeBelow(up, depth);
    case CollisionCapsule(:final radius, :final halfHeight):
      return _capsule(radius, halfHeight).volumeBelow(up, depth);
    default:
      return 0.0;
  }
}

/// A box about the origin as a closed mesh.
MeshVessel _box(Vector3 e) {
  final p = <Vector3>[
    for (final y in [-e.y, e.y])
      for (final (x, z) in [(-e.x, -e.z), (e.x, -e.z), (e.x, e.z), (-e.x, e.z)])
        Vector3(x, y, z),
  ];
  const quads = <List<int>>[
    [0, 1, 2, 3],
    [4, 7, 6, 5],
    [0, 4, 5, 1],
    [1, 5, 6, 2],
    [2, 6, 7, 3],
    [3, 7, 4, 0],
  ];
  return MeshVessel(
    positions: p,
    indices: [
      for (final q in quads) ...[q[0], q[1], q[2], q[0], q[2], q[3]],
    ],
  );
}

/// An upright capsule about the origin as a lathe: a hemisphere, the
/// cylinder, a hemisphere.
RevolvedVessel _capsule(double r, double half) => RevolvedVessel([
  for (var i = 0; i <= 12; i++)
    Vector2(
      r * Portable.sin(i / 12 * math.pi / 2),
      -half - r * Portable.cos(i / 12 * math.pi / 2),
    ),
  for (var i = 1; i <= 12; i++)
    Vector2(
      r * Portable.cos(i / 12 * math.pi / 2),
      half + r * Portable.sin(i / 12 * math.pi / 2),
    ),
  Vector2(0, half + r),
]);

/// The drag coefficient of a sphere at Reynolds number [re]: White's
/// correlation, 24/Re + 6/(1 + √Re) + 0.4, which is Stokes's law when the
/// flow is slow and the turbulent plateau when it is quick.
double sphereDrag(double re) {
  if (re <= 0.0) return 0.0;
  return 24.0 / re + 6.0 / (1.0 + math.sqrt(re)) + 0.4;
}

/// A rigid body in a vessel's liquid: the forces on it, applied as impulses
/// each step, and the liquid it pushes aside.
///
/// **Archimedes**: the liquid pushes up with the weight of what the body
/// displaces, ρgV along the gravity the liquid feels. **Drag**: against its
/// motion through the liquid, ½ρC_dA|v|v with White's C_d, for the part of
/// it that is under — a sphere's own coefficient, and a box's or capsule's
/// as the sphere of the same frontal area, which is an estimate. And the
/// liquid it pushes aside raises the level in the vessel by as much
/// ([LiquidBody.displaced]).
final class FloatingBody {
  FloatingBody(this.body);

  final RigidBody body;

  /// The volume of it under the surface of [liquid] as it is now.
  double submergedIn(LiquidBody liquid) {
    final turnBack = liquid.rotation.clone()..transpose();
    final centre = turnBack.transformed(body.position - liquid.position);
    if (!liquid.shape.contains(centre) &&
        !_overlaps(liquid.shape, centre, body.collider.shape)) {
      return 0.0;
    }
    return submergedVolume(
      body.collider.shape,
      centre,
      liquid.up,
      liquid.height,
    );
  }

  bool _overlaps(VesselShape shape, Vector3 centre, CollisionShape s) {
    final e = s.boundsHalfExtents;
    for (final dx in [-e.x, e.x]) {
      for (final dy in [-e.y, e.y]) {
        for (final dz in [-e.z, e.z]) {
          if (shape.contains(centre + Vector3(dx, dy, dz))) return true;
        }
      }
    }
    return false;
  }

  /// Pushes the body for [dt] with the buoyancy and drag of [liquid] under
  /// [gravity], and returns the volume it displaces there. How much of it is
  /// under is worked out here; the push is [solver]'s — the reference unless
  /// a `FluidWorld` passes the run's.
  double push(
    LiquidBody liquid,
    double dt,
    Vector3 gravity, {
    FluidSolver solver = const DartFluid(),
  }) {
    final under = submergedIn(liquid);
    if (under <= 0.0 || !body.isMovable) return under;
    final medium = liquid.medium;
    final g = gravity.length;
    if (g <= 0.0) return under;
    body.wake();
    final v = body.velocity;
    final bodies = Float64List.fromList([v.x, v.y, v.z, body.inverseMass]);
    final (kind, a, b, c) = switch (body.collider.shape) {
      CollisionSphere(:final radius) => (FloatPush.sphere, radius, 0.0, 0.0),
      CollisionBox(:final halfExtents) => (
        FloatPush.box,
        halfExtents.x,
        halfExtents.y,
        halfExtents.z,
      ),
      CollisionCapsule(:final radius, :final halfHeight) => (
        FloatPush.capsule,
        radius,
        halfHeight,
        0.0,
      ),
      _ => (FloatPush.other, 0.0, 0.0, 0.0),
    };
    solver.pushBodies(
      FloatPush(
        bodies: bodies,
        pushes: Float64List.fromList([
          0.0,
          kind.toDouble(),
          a,
          b,
          c,
          under,
          medium.density,
          medium.viscosity,
        ]),
        gravity: gravity,
        dt: dt,
      ),
    );
    v.setValues(bodies[0], bodies[1], bodies[2]);
    return under;
  }
}

/// [push] pushed in Dart: what [DartFluid.pushBodies] does.
void pushBodiesInDart(FloatPush push) {
  final gravity = push.gravity;
  final dt = push.dt;
  for (var i = 0; i < push.count; i++) {
    final r = Float64List.sublistView(
      push.pushes,
      i * FloatPush.pushFloats,
      (i + 1) * FloatPush.pushFloats,
    );
    final at = r[0].toInt() * FloatPush.bodyFloats;
    final v = Vector3(
      push.bodies[at],
      push.bodies[at + 1],
      push.bodies[at + 2],
    );
    final inverseMass = push.bodies[at + 3];
    final kind = r[1].toInt();
    final (a, b, c) = (r[2], r[3], r[4]);
    final under = r[5];
    final density = r[6];
    final viscosity = r[7];
    // Archimedes: the weight of what it displaces, along the gravity felt,
    // as an impulse.
    final lift = -gravity * (density * under);
    v.addScaled(lift * dt, inverseMass);
    // Drag, implicitly: the velocity scaled by 1 / (1 + kΔt) for a drag
    // acceleration −kv, which slows a body however thick the liquid and
    // never turns it round.
    final speed = v.length;
    if (speed > 1e-9) {
      final area = _frontalArea(kind, a, b, c, v / speed);
      final share = (under / _wholeVolume(kind, a, b, c)).clamp(0.0, 1.0);
      final diameter = math.sqrt(4.0 * area / math.pi);
      final re = density * speed * diameter / viscosity;
      final k =
          0.5 * density * sphereDrag(re) * area * share * speed * inverseMass;
      // Gravity is added after this, by the body's own step; taken into the
      // implicit solve here and back out, so the speed the body settles at
      // is (g − b)/k and not that plus the one step of gravity that would
      // otherwise land on top of it — g·Δt, half again Stokes's speed for a
      // small ball in glycerol at a two-thousandth of a second.
      v
        ..addScaled(gravity, dt)
        ..scale(1.0 / (1.0 + k * dt))
        ..addScaled(gravity, -dt);
    }
    push.bodies
      ..[at] = v.x
      ..[at + 1] = v.y
      ..[at + 2] = v.z;
  }
}

/// The area a shape of [kind] and sizes [a], [b], [c] shows to a flow along
/// [dir]: a sphere's disc, a box's projection, an upright capsule's — its
/// cylinder's rectangle and its caps' disc, foreshortened by how steeply it
/// is met.
double _frontalArea(int kind, double a, double b, double c, Vector3 dir) =>
    switch (kind) {
      FloatPush.sphere => math.pi * a * a,
      FloatPush.box =>
        4.0 * (b * c * dir.x.abs() + a * c * dir.y.abs() + a * b * dir.z.abs()),
      FloatPush.capsule =>
        math.pi * a * a + 4.0 * a * b * math.sqrt(1.0 - dir.y * dir.y),
      _ => 0.0,
    };

double _wholeVolume(int kind, double a, double b, double c) => switch (kind) {
  FloatPush.sphere => 4.0 / 3.0 * math.pi * a * a * a,
  FloatPush.box => 8.0 * a * b * c,
  FloatPush.capsule => math.pi * a * a * (2.0 * b + 4.0 / 3.0 * a),
  _ => 1.0,
};

/// Stokes's settling speed of a sphere of [radius] and [density] in [medium]
/// under [g]: 2(ρ_s − ρ)gR² / 9μ, for slow flow. What [FloatingBody]'s drag
/// comes to for a small heavy ball in a thick liquid.
double stokesSpeed(
  FluidMedium medium,
  double radius,
  double density,
  double g,
) =>
    2.0 *
    (density - medium.density) *
    g *
    radius *
    radius /
    (9.0 * medium.viscosity);
