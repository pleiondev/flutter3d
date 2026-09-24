import 'dart:math' as math;
import 'dart:typed_data';

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
  final structuralLambda = Float64List(mesh.structuralRestLength.length);
  final bendLambda = Float64List(mesh.bendRestLength.length);
  final push = Float64List(3);
  final friction = settings.friction;
  // Each particle's contact push, summed over the substep's iterations — the
  // normal force friction is measured against. Only when there is friction
  // to measure.
  final contact = friction > 0.0 && obstacles.isNotEmpty
      ? Float64List(3 * n)
      : null;

  for (var sub = 0; sub < settings.substeps; sub++) {
    _predict(mesh, settings, subDt, predicted);

    // Every multiplier starts the substep at zero, and so does the contact.
    structuralLambda.fillRange(0, structuralLambda.length, 0.0);
    bendLambda.fillRange(0, bendLambda.length, 0.0);
    contact?.fillRange(0, contact.length, 0.0);
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
      // **Inside the iteration loop, as XPBD and Flex solve contacts, not
      // once after it.** Wrapping a ball or a table edge needs the sheet to
      // compress in its own plane, which a rigid edge constraint refuses; a
      // collision pass run once after the constraints and a constraint pass
      // run once before it undo each other every substep, and the residual
      // becomes velocity. That pumped a 48×48 sheet on a ball from half a
      // metre a second to NaN in thirty steps.
      _resolveCollisions(
        predicted,
        mesh,
        obstacles,
        settings.collisionThickness,
        push,
        contact,
      );
    }
    // **Friction once per substep, against the whole substep's push.** The
    // first iteration does nearly all of the pushing out; measured against
    // the last iteration's push alone, which is close to nothing, 0.3 let a
    // sheet slide off a ball as if there were none.
    if (contact != null) _applyFriction(predicted, mesh, contact, friction);
    _integrate(mesh, predicted, subDt);
  }
}

void _predict(
  ClothMesh mesh,
  ClothSettings settings,
  double subDt,
  Float64List predicted,
) {
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
/// of the air's velocity relative to the cloth that points along the normal
/// pushes on it, so wind blowing parallel to a taut sheet does nothing to it,
/// which is the visible difference between cloth flapping and cloth being
/// dragged sideways bodily.
///
/// **A force, integrated as gravity is: `Δx = F·w·h²`.** It used to add
/// `F·w·h` to a position, which is a velocity, so the push grew with the
/// substep count — 480 times the formula at eight substeps — and it ignored
/// the cloth's own velocity, so a sheet in a one-metre-a-second wind was
/// still accelerating at forty. The air speed is now relative to the
/// triangle, the way NvCloth's is, which is what makes drag a drag: a sheet
/// moving with the wind feels none of it. The normals come from the start of
/// the substep rather than from positions this loop is still moving, so no
/// triangle's answer depends on which came before it.
void _applyWind(
  ClothMesh mesh,
  Float64List predicted,
  WindSettings wind,
  Float64List invMass,
  double subDt,
) {
  final x = mesh.positions;
  final v = mesh.velocities;
  final tris = mesh.triangles;
  final h2 = subDt * subDt;
  for (var t = 0; t < tris.length; t += 3) {
    final a = tris[t], b = tris[t + 1], c = tris[t + 2];
    final e1x = x[3 * b] - x[3 * a];
    final e1y = x[3 * b + 1] - x[3 * a + 1];
    final e1z = x[3 * b + 2] - x[3 * a + 2];
    final e2x = x[3 * c] - x[3 * a];
    final e2y = x[3 * c + 1] - x[3 * a + 1];
    final e2z = x[3 * c + 2] - x[3 * a + 2];
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

    // The air's velocity relative to the triangle's own.
    final rx = wind.velocityX - (v[3 * a] + v[3 * b] + v[3 * c]) / 3.0;
    final ry =
        wind.velocityY - (v[3 * a + 1] + v[3 * b + 1] + v[3 * c + 1]) / 3.0;
    final rz =
        wind.velocityZ - (v[3 * a + 2] + v[3 * b + 2] + v[3 * c + 2]) / 3.0;
    final relative = nx * rx + ny * ry + nz * rz;
    // Newtons per corner: half the cross product's length is the area, and
    // the force is split three ways.
    final force = wind.drag * relative * (len * 0.5) / 3.0;

    _windOn(a, force, nx, ny, nz, relative, invMass, subDt, h2, predicted);
    _windOn(b, force, nx, ny, nz, relative, invMass, subDt, h2, predicted);
    _windOn(c, force, nx, ny, nz, relative, invMass, subDt, h2, predicted);
  }
}

void _windOn(
  int i,
  double force,
  double nx,
  double ny,
  double nz,
  double relative,
  Float64List invMass,
  double subDt,
  double h2,
  Float64List predicted,
) {
  final w = invMass[i];
  if (w == 0) return;
  // A drag cannot turn the relative velocity round in one substep; a light
  // corner on a large triangle in a gale otherwise would, and oscillate.
  final dv = (force * w * subDt).abs();
  final scale = dv > relative.abs() && dv > 0.0 ? relative.abs() / dv : 1.0;
  final dx = force * w * h2 * scale;
  predicted[3 * i] += nx * dx;
  predicted[3 * i + 1] += ny * dx;
  predicted[3 * i + 2] += nz * dx;
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

/// Pushes every free particle out of [obstacles], adding each push to
/// [contact] when there is one to keep.
///
/// In doubles throughout: a particle used to be copied into a `Vector3` and
/// back for every obstacle, which rounded it to single precision, so an
/// obstacle nothing touched still moved the sheet.
void _resolveCollisions(
  Float64List predicted,
  ClothMesh mesh,
  List<ClothObstacle> obstacles,
  double thickness,
  Float64List push,
  Float64List? contact,
) {
  if (obstacles.isEmpty) return;
  final invMass = mesh.invMass;
  for (var i = 0; i < mesh.particleCount; i++) {
    if (invMass[i] == 0) continue;
    for (final obstacle in obstacles) {
      if (!pushParticleOutside(predicted, i, obstacle, thickness, push)) {
        continue;
      }
      if (contact == null) continue;
      contact[3 * i] += push[0];
      contact[3 * i + 1] += push[1];
      contact[3 * i + 2] += push[2];
    }
  }
}

/// Takes back up to [friction] times each particle's [contact] push from how
/// far it slid along the surface this substep — position-level Coulomb
/// friction, as Macklin et al. (Flex, §6.1) and Müller et al. (2020, §3.5)
/// apply it.
void _applyFriction(
  Float64List predicted,
  ClothMesh mesh,
  Float64List contact,
  double friction,
) {
  final invMass = mesh.invMass;
  final positions = mesh.positions;
  for (var i = 0; i < mesh.particleCount; i++) {
    if (invMass[i] == 0) continue;
    final cx = contact[3 * i], cy = contact[3 * i + 1], cz = contact[3 * i + 2];
    final depth = math.sqrt(cx * cx + cy * cy + cz * cz);
    if (depth < 1e-12) continue;
    final nx = cx / depth, ny = cy / depth, nz = cz / depth;
    final mx = predicted[3 * i] - positions[3 * i];
    final my = predicted[3 * i + 1] - positions[3 * i + 1];
    final mz = predicted[3 * i + 2] - positions[3 * i + 2];
    final along = mx * nx + my * ny + mz * nz;
    final tx = mx - along * nx, ty = my - along * ny, tz = mz - along * nz;
    final slid = math.sqrt(tx * tx + ty * ty + tz * tz);
    if (slid < 1e-12) continue;
    final cut = slid <= friction * depth ? 1.0 : friction * depth / slid;
    predicted[3 * i] -= tx * cut;
    predicted[3 * i + 1] -= ty * cut;
    predicted[3 * i + 2] -= tz * cut;
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
    velocities[3 * i + 1] =
        (predicted[3 * i + 1] - positions[3 * i + 1]) * inverseDt;
    velocities[3 * i + 2] =
        (predicted[3 * i + 2] - positions[3 * i + 2]) * inverseDt;
    positions[3 * i] = predicted[3 * i];
    positions[3 * i + 1] = predicted[3 * i + 1];
    positions[3 * i + 2] = predicted[3 * i + 2];
  }
}
