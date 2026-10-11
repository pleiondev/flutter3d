import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show SimulationProfile;
import 'package:vector_math/vector_math.dart';

import '../adaptive.dart';
import '../collision_shape.dart';
import '../rigid_body.dart';
import 'fluid_medium.dart';
import 'fluid_solver.dart';
import 'liquid_body.dart';
import 'vessel_shape.dart';

/// How much of [shape], centred at [center], is below the plane
/// `up · p = height` (all in one frame): exactly, for the shapes a body can
/// have that hold a volume — a sphere by its cap, π h²(3R − h)/3; a box by
/// cutting it as a closed mesh; an upright capsule as a surface of
/// revolution. Nought for shapes with no inside: a heightfield, a wedge
/// ramp.
double submergedVolume(
  CollisionShape shape,
  Vector3 center,
  Vector3 up,
  double height,
) {
  final depth = height - up.dot(center);
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
/// flow is slow and the turbulent plateau when it is quick (White, Viscous
/// Fluid Flow, 2nd ed., 1991, which puts it within 10 % of the measurements
/// from Re 0 to 2·10⁵).
///
/// **The engine's sphere drag, and the one law where a body moves through a
/// liquid at any speed** — this, and the core's vessels (`f3d_liquid.c`),
/// which use the same correlation. Two solvers use another, each for a
/// reason of its own:
///
/// * **a body in the core's shallow liquid** (`f3d_shallow.c`) takes
///   Schiller and Naumann's 24/Re·(1 + 0.15 Re^0.687), Newton's 0.44 past
///   Re 1000, for a ball, because every other shape there is Haider and
///   Levenspiel's correlation by its sphericity (Powder Technology 58,
///   1989), which is fitted to the same data and reduces to Schiller and
///   Naumann's at a sphericity of one: a ball and a nearly round stone must
///   not drag differently by the formula alone. The two laws are within
///   about 10 % of each other, and of the measurements, over the range;
/// * **a body in the wind** (`NativeWorld.setDrag`) and **an ember in a
///   fire's gas** (`FireView`) take a constant, Newton's regime: in air they
///   are at Reynolds numbers in the hundreds to thousands, where this
///   correlation has all but reached its plateau (0.47 at Re 6 600), and a
///   constant is what a wind field sampled once a step can afford.
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
    final center = turnBack.transformed(body.position - liquid.position);
    if (!liquid.shape.contains(center) &&
        !_overlaps(liquid.shape, center, body.collider.shape)) {
      return 0.0;
    }
    return submergedVolume(
      body.collider.shape,
      center,
      liquid.up,
      liquid.height,
    );
  }

  bool _overlaps(VesselShape shape, Vector3 center, CollisionShape s) {
    final e = s.boundsHalfExtents;
    for (final dx in [-e.x, e.x]) {
      for (final dy in [-e.y, e.y]) {
        for (final dz in [-e.z, e.z]) {
          if (shape.contains(center + Vector3(dx, dy, dz))) return true;
        }
      }
    }
    return false;
  }

  /// Pushes the body for [dt] with the buoyancy and drag of [liquid] under
  /// [gravity], and returns the volume it displaces there. How much of it is
  /// under is worked out here; the push is [solver]'s — the reference unless
  /// a `FluidWorld` passes the run's.
  ///
  /// **The liquid as it is now**: its density and viscosity at the
  /// liquid's state (`LiquidBody.mediumInState`), so a ball sinks faster
  /// through warm glycerol than through cold.
  ///
  /// **Under a profile that allows adaptive steps** the push is not the
  /// solver's implicit step but the velocity's own equation, lift, gravity
  /// and drag at the speed it has, integrated through [dt] in Dart to a
  /// relative error of 1e-10 with how much of the body is under held as
  /// it was at the start of the step: a ball let go in a liquid reaches its
  /// settling speed along the curve the drag law gives, not a step behind.
  double push(
    LiquidBody liquid,
    double dt,
    Vector3 gravity, {
    FluidSolver solver = const DartFluid(),
    SimulationProfile profile = SimulationProfile.deterministic,
  }) {
    final under = submergedIn(liquid);
    if (under <= 0.0 || !body.isMovable) return under;
    final medium = liquid.mediumInState;
    final g = gravity.length;
    if (g <= 0.0) return under;
    body.wake();
    final v = body.velocity;
    final bodies = Float64List.fromList([v.x, v.y, v.z, body.inverseMass]);
    final (kind, a, b, c) = _sizes(body.collider.shape);
    if (profile.allowsAdaptiveSteps) {
      _integrate(bodies, kind, a, b, c, under, medium, gravity, dt);
      v.setValues(bodies[0], bodies[1], bodies[2]);
      return under;
    }
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

  /// The kind and the sizes of [shape], as `FloatPush` writes them.
  static (int, double, double, double) _sizes(CollisionShape shape) =>
      switch (shape) {
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

  /// The velocity in [state] (`x, y, z, 1/m`) carried through [dt] by its
  /// own equation: lift and gravity, less the drag at the speed it has, the
  /// step's gravity then taken back out for the body's own step to add.
  static void _integrate(
    Float64List state,
    int kind,
    double a,
    double b,
    double c,
    double under,
    FluidMedium medium,
    Vector3 gravity,
    double dt,
  ) {
    final w = state[3];
    final share = (under / _wholeVolume(kind, a, b, c)).clamp(0.0, 1.0);
    final gx = gravity.x, gy = gravity.y, gz = gravity.z;
    final lift = medium.density * under * w;
    final direction = Vector3.zero();
    final v = Float64List.fromList(<double>[state[0], state[1], state[2]]);
    DormandPrince().integrate(v, 0.0, dt, (
      double t,
      Float64List y,
      Float64List dy,
    ) {
      var ax = gx - gx * lift, ay = gy - gy * lift, az = gz - gz * lift;
      final speed = math.sqrt(y[0] * y[0] + y[1] * y[1] + y[2] * y[2]);
      if (speed > 1e-12) {
        direction.setValues(y[0] / speed, y[1] / speed, y[2] / speed);
        final area = _frontalArea(kind, a, b, c, direction);
        final diameter = math.sqrt(4.0 * area / math.pi);
        final re = medium.density * speed * diameter / medium.viscosity;
        final k =
            0.5 * medium.density * sphereDrag(re) * area * share * speed * w;
        ax -= k * y[0];
        ay -= k * y[1];
        az -= k * y[2];
      }
      dy
        ..[0] = ax
        ..[1] = ay
        ..[2] = az;
    });
    state
      ..[0] = v[0] - gx * dt
      ..[1] = v[1] - gy * dt
      ..[2] = v[2] - gz * dt;
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
