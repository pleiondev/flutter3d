import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cloth_collision.dart';
import 'cloth_mesh.dart';
import 'cloth_settings.dart';

/// Advances [mesh] by [dt] seconds, in place.
///
/// **One call, [ClothSettings.substeps] XPBD substeps inside it.** Each
/// substep: integrate gravity, wind and damping into a predicted position;
/// solve every structural and bending constraint once against that
/// prediction, each with its own Lagrange multiplier reset to zero for the
/// substep (the "X" in XPBD — a multiplier does not carry across a substep
/// boundary, which is what keeps a stiff constraint's own apparent
/// stiffness independent of how finely `dt` is cut); push particles outside
/// [obstacles]; then fold the prediction back into velocity and position.
///
/// **Determinism.** Every loop here walks a fixed-length typed array by
/// index, in the same order every call — no `Set`, no `Map`, no wall clock,
/// no unseeded randomness. The same [mesh] state, [settings], [dt] and
/// [obstacles] produce the same output every time, which is this package's
/// own read of "determinism like in sim": nothing here depends on when it
/// is called or on iteration order a collection does not promise.
void stepCloth(
  ClothMesh mesh,
  ClothSettings settings,
  double dt, {
  List<ClothObstacle> obstacles = const [],
}) {
  if (dt <= 0 || settings.substeps <= 0) return;
  final subDt = dt / settings.substeps;
  final n = mesh.particleCount;
  final predicted = Float64List(3 * n);

  for (var sub = 0; sub < settings.substeps; sub++) {
    _predict(mesh, settings, subDt, predicted);

    final structuralLambda = Float64List(mesh.structuralRestLength.length);
    final bendLambda = Float64List(mesh.bendRestLength.length);
    for (var iter = 0; iter < settings.iterations; iter++) {
      _solveDistance(
        predicted,
        mesh.invMass,
        mesh.structuralPairs,
        mesh.structuralRestLength,
        structuralLambda,
        settings.distanceCompliance,
        subDt,
      );
      _solveDistance(
        predicted,
        mesh.invMass,
        mesh.bendPairs,
        mesh.bendRestLength,
        bendLambda,
        settings.bendCompliance,
        subDt,
      );
    }

    _resolveCollisions(predicted, mesh.invMass, obstacles, settings.collisionThickness);
    _integrate(mesh, predicted, subDt);
  }
}

void _predict(ClothMesh mesh, ClothSettings settings, double subDt, Float64List predicted) {
  final positions = mesh.positions;
  final velocities = mesh.velocities;
  final invMass = mesh.invMass;
  final wind = settings.wind;
  final damped = 1.0 - settings.damping;

  // Damping shrinks the *old* velocity only, before gravity adds this
  // substep's own contribution to it — not the predicted position or the
  // constraint solve that follows, both of which must reach their own
  // undamped target every substep or a rigid (zero-compliance) distance
  // constraint never actually reaches rest length and keeps re-triggering
  // a correction forever. An earlier draft damped the solved *displacement*
  // instead, on the theory that this was the motion actually taken — it
  // measurably was not: at higher damping values the sheet settled *slower*,
  // non-monotonically, because damping was eating into the same correction
  // that was supposed to satisfy the constraint, leaving a permanent
  // residual error for the next substep to correct again.
  for (var i = 0; i < mesh.particleCount; i++) {
    if (invMass[i] == 0) {
      predicted[3 * i] = positions[3 * i];
      predicted[3 * i + 1] = positions[3 * i + 1];
      predicted[3 * i + 2] = positions[3 * i + 2];
      continue;
    }
    final vx = velocities[3 * i] * damped;
    final vy = velocities[3 * i + 1] * damped - settings.gravity * subDt;
    final vz = velocities[3 * i + 2] * damped;
    predicted[3 * i] = positions[3 * i] + vx * subDt;
    predicted[3 * i + 1] = positions[3 * i + 1] + vy * subDt;
    predicted[3 * i + 2] = positions[3 * i + 2] + vz * subDt;
  }

  if (!wind.isNone) _applyWind(mesh, predicted, wind, invMass, subDt);
}

/// Drag along each triangle's own normal, split evenly across its three
/// corners — the standard "flat plate in a flow" proxy: only the component
/// of the wind's own velocity relative to the cloth that points along the
/// normal pushes on it, so wind blowing parallel to a taut sheet does
/// nothing to it, which is the visible difference between cloth flapping
/// and cloth being dragged sideways bodily.
void _applyWind(
  ClothMesh mesh,
  Float64List predicted,
  WindSettings wind,
  Float64List invMass,
  double subDt,
) {
  final tris = mesh.triangles;
  for (var t = 0; t < tris.length; t += 3) {
    final a = tris[t], b = tris[t + 1], c = tris[t + 2];
    final ax = predicted[3 * a], ay = predicted[3 * a + 1], az = predicted[3 * a + 2];
    final bx = predicted[3 * b], by = predicted[3 * b + 1], bz = predicted[3 * b + 2];
    final cx = predicted[3 * c], cy = predicted[3 * c + 1], cz = predicted[3 * c + 2];

    final e1x = bx - ax, e1y = by - ay, e1z = bz - az;
    final e2x = cx - ax, e2y = cy - ay, e2z = cz - az;
    // Cross product e1 x e2; its length is twice the triangle's own area,
    // which folds the area weighting into the force for free.
    var nx = e1y * e2z - e1z * e2y;
    var ny = e1z * e2x - e1x * e2z;
    var nz = e1x * e2y - e1y * e2x;
    final len = math.sqrt(nx * nx + ny * ny + nz * nz);
    if (len < 1e-12) continue;
    nx /= len;
    ny /= len;
    nz /= len;

    final relative = nx * wind.velocityX + ny * wind.velocityY + nz * wind.velocityZ;
    // Half the cross product's own length is the triangle's own area; the
    // force below is already split three ways, so a sixth of it each.
    final force = relative * wind.drag * (len * 0.5) / 3.0;
    final fx = nx * force * subDt;
    final fy = ny * force * subDt;
    final fz = nz * force * subDt;

    for (final i in [a, b, c]) {
      if (invMass[i] == 0) continue;
      predicted[3 * i] += fx * invMass[i];
      predicted[3 * i + 1] += fy * invMass[i];
      predicted[3 * i + 2] += fz * invMass[i];
    }
  }
}

/// One XPBD pass over every constraint in [pairs]/[restLength]: for a pair
/// `(a, b)` with current gap `C = |p_a - p_b| - restLength`, the multiplier
/// step is `dLambda = (-C - alphaTilde * lambda) / (wSum + alphaTilde)`
/// where `alphaTilde = compliance / subDt²` and `wSum` is the pair's own
/// combined inverse mass — Müller et al.'s own XPBD update, unabridged.
/// Zero compliance collapses `alphaTilde` and this becomes an ordinary PBD
/// distance constraint.
void _solveDistance(
  Float64List predicted,
  Float64List invMass,
  Int32List pairs,
  Float64List restLength,
  Float64List lambda,
  double compliance,
  double subDt,
) {
  final alphaTilde = compliance / (subDt * subDt);
  for (var k = 0; k < restLength.length; k++) {
    final a = pairs[2 * k];
    final b = pairs[2 * k + 1];
    final wa = invMass[a];
    final wb = invMass[b];
    final wSum = wa + wb;
    if (wSum == 0) continue;

    final dx = predicted[3 * a] - predicted[3 * b];
    final dy = predicted[3 * a + 1] - predicted[3 * b + 1];
    final dz = predicted[3 * a + 2] - predicted[3 * b + 2];
    final dist = math.sqrt(dx * dx + dy * dy + dz * dz);
    if (dist < 1e-12) continue;

    final c = dist - restLength[k];
    final dLambda = (-c - alphaTilde * lambda[k]) / (wSum + alphaTilde);
    lambda[k] += dLambda;

    final nx = dx / dist;
    final ny = dy / dist;
    final nz = dz / dist;

    predicted[3 * a] += wa * dLambda * nx;
    predicted[3 * a + 1] += wa * dLambda * ny;
    predicted[3 * a + 2] += wa * dLambda * nz;
    predicted[3 * b] -= wb * dLambda * nx;
    predicted[3 * b + 1] -= wb * dLambda * ny;
    predicted[3 * b + 2] -= wb * dLambda * nz;
  }
}

final _scratchPoint = Vector3.zero();

void _resolveCollisions(
  Float64List predicted,
  Float64List invMass,
  List<ClothObstacle> obstacles,
  double thickness,
) {
  if (obstacles.isEmpty) return;
  final n = predicted.length ~/ 3;
  for (var i = 0; i < n; i++) {
    if (invMass[i] == 0) continue;
    _scratchPoint.setValues(predicted[3 * i], predicted[3 * i + 1], predicted[3 * i + 2]);
    for (final obstacle in obstacles) {
      pushOutsideObstacle(_scratchPoint, obstacle, thickness);
    }
    predicted[3 * i] = _scratchPoint.x;
    predicted[3 * i + 1] = _scratchPoint.y;
    predicted[3 * i + 2] = _scratchPoint.z;
  }
}

void _integrate(ClothMesh mesh, Float64List predicted, double subDt) {
  final positions = mesh.positions;
  final velocities = mesh.velocities;
  final invMass = mesh.invMass;
  final inverseDt = 1.0 / subDt;
  for (var i = 0; i < mesh.particleCount; i++) {
    if (invMass[i] == 0) continue;
    velocities[3 * i] = (predicted[3 * i] - positions[3 * i]) * inverseDt;
    velocities[3 * i + 1] = (predicted[3 * i + 1] - positions[3 * i + 1]) * inverseDt;
    velocities[3 * i + 2] = (predicted[3 * i + 2] - positions[3 * i + 2]) * inverseDt;
    positions[3 * i] = predicted[3 * i];
    positions[3 * i + 1] = predicted[3 * i + 1];
    positions[3 * i + 2] = predicted[3 * i + 2];
  }
}
