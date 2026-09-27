import 'dart:math' as math;
import 'dart:typed_data';

import 'cloth_collision.dart';
import 'cloth_mesh.dart';
import 'cloth_settings.dart';

/// Advances [mesh] by [dt] seconds, in place.
///
/// **One call, [ClothSettings.substeps] XPBD substeps inside it.** Each
/// substep: integrate gravity, wind and damping into a predicted position;
/// solve every structural, bending and shear constraint once against that
/// prediction, each with its own Lagrange multiplier reset to zero for the
/// substep (the "X" in XPBD — a multiplier does not carry across a substep
/// boundary, which is what keeps a stiff constraint's own apparent
/// stiffness independent of how finely `dt` is cut); push the sheet's own
/// layers apart when [ClothSettings.selfCollision] is on; push particles
/// outside [obstacles]; then fold the prediction back into velocity and
/// position.
///
/// **Determinism.** Every loop here walks a fixed-length typed array by
/// index, in the same order every call — no `Set`, no `Map`, no wall clock,
/// no unseeded randomness. Self-collision's spatial hash is a counting sort
/// into typed arrays and lives for one call only, so no call leans on what
/// an earlier one left behind. The same [mesh] state, [settings], [dt] and
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
  final shearLambda = Float64List(mesh.shearRestLength.length);
  final push = Float64List(3);
  final friction = settings.friction;
  // Each particle's contact push, summed over the substep's iterations — the
  // normal force friction is measured against. Only when there is friction
  // to measure.
  final contact = friction > 0.0 && obstacles.isNotEmpty
      ? Float64List(3 * n)
      : null;
  final thickness = settings.selfCollisionThickness ?? mesh.meanRestEdge;
  final self = settings.selfCollision && thickness > 0.0 && n > 1
      ? _SelfCollision(mesh, thickness, settings.selfCollisionFriction)
      : null;
  // Each particle's widest triangle as the sheet stands at the start of the
  // step, so a round obstacle keeps whole triangles outside it and not only
  // their corners. Per particle: the widest over the whole sheet is a strand
  // stretched in the air far from the ball, and it lifted the sheet two
  // centimetres clear of a 0.2 m ball. Once a step: a triangle does not grow
  // much within one.
  final span = obstacles.isEmpty ? null : _widestTriangles(mesh);

  for (var sub = 0; sub < settings.substeps; sub++) {
    _predict(mesh, settings, subDt, predicted);
    self?.update(predicted);

    // Every multiplier starts the substep at zero, and so does the contact.
    structuralLambda.fillRange(0, structuralLambda.length, 0.0);
    bendLambda.fillRange(0, bendLambda.length, 0.0);
    shearLambda.fillRange(0, shearLambda.length, 0.0);
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
      _solveDistance(
        predicted,
        mesh.invMass,
        mesh.shearPairs,
        mesh.shearRestLength,
        shearLambda,
        settings.shearCompliance,
        subDt,
      );
      // Before the obstacles, so what is pushed last is pushed out of the
      // floor rather than into it by the layer above.
      self?.solve(predicted);
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
        span,
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

/// For each particle of [mesh], the largest radius of the circle through the
/// three corners of a triangle it belongs to, where the sheet stands now:
/// how far a flat triangle sags inside a sphere its corners sit on.
/// `abc / 4A`, with a triangle folded flat onto a line left out. Only
/// `+ - * /` and `sqrt`, so the same bits on every platform.
Float64List _widestTriangles(ClothMesh mesh) {
  final p = mesh.positions;
  final t = mesh.triangles;
  final widest = Float64List(mesh.particleCount);
  for (var k = 0; k < t.length; k += 3) {
    final a = 3 * t[k], b = 3 * t[k + 1], c = 3 * t[k + 2];
    final abx = p[b] - p[a],
        aby = p[b + 1] - p[a + 1],
        abz = p[b + 2] - p[a + 2];
    final acx = p[c] - p[a],
        acy = p[c + 1] - p[a + 1],
        acz = p[c + 2] - p[a + 2];
    final bcx = p[c] - p[b],
        bcy = p[c + 1] - p[b + 1],
        bcz = p[c + 2] - p[b + 2];
    final cx = aby * acz - abz * acy;
    final cy = abz * acx - abx * acz;
    final cz = abx * acy - aby * acx;
    // |ab × ac| is twice the area.
    final twiceArea = math.sqrt(cx * cx + cy * cy + cz * cz);
    if (twiceArea <= 1e-12) continue;
    final ab = math.sqrt(abx * abx + aby * aby + abz * abz);
    final ac = math.sqrt(acx * acx + acy * acy + acz * acz);
    final bc = math.sqrt(bcx * bcx + bcy * bcy + bcz * bcz);
    final r = ab * ac * bc / (2.0 * twiceArea);
    for (var j = k; j < k + 3; j++) {
      if (r > widest[t[j]]) widest[t[j]] = r;
    }
  }
  return widest;
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
  Float64List? span,
  Float64List push,
  Float64List? contact,
) {
  if (obstacles.isEmpty) return;
  final invMass = mesh.invMass;
  for (var i = 0; i < mesh.particleCount; i++) {
    if (invMass[i] == 0) continue;
    for (final obstacle in obstacles) {
      if (!pushParticleOutside(
        predicted,
        i,
        obstacle,
        thickness,
        push,
        span: span == null ? 0.0 : span[i],
      )) {
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

/// The sheet against itself: every particle a sphere of [thickness], pushed
/// out of every other one that is not already that close in the rest shape.
///
/// The method is Müller's self-collision for particle cloth ("Ten Minute
/// Physics", self-collision chapter), solved as one more position
/// constraint inside the XPBD iteration loop (Müller et al. 2020, "Detailed
/// Rigid Body Simulation with Extended Position Based Dynamics"): a spatial
/// hash for the close pairs, and each iteration pushing every pair still
/// closer than the thickness apart along the line between them, split by
/// inverse mass.
///
/// **A list with a skin, rebuilt only when something has moved.** Hashing
/// all 6400 particles of an 80×80 sheet costs about a millisecond, and
/// doing it every substep (12 per step) added 40% to the step. The pairs are
/// gathered out to [_skin] beyond the thickness instead, and gathered again
/// only once some particle has moved more than half the skin since: until
/// then no pair that was left out can have closed the gap, since each of the
/// two has moved less than half of it. A falling sheet rebuilds nearly every
/// substep; a draped one every few dozen. Nothing slows a particle down to
/// fit the list, as a list gathered once per step would need.
///
/// **Deterministic by construction.** The hash is a counting sort into
/// typed arrays: particles land in their buckets in index order, pairs are
/// listed in index order and then in the fixed order of the cells around
/// it, the rebuild is decided by the positions alone, and the cell key is
/// built from 10-bit masks and shifts, which give the same bits on a 64-bit
/// VM and in JavaScript's 32-bit bitwise ops.
final class _SelfCollision {
  _SelfCollision(ClothMesh mesh, this.thickness, this.friction)
    : n = mesh.particleCount,
      rest = mesh.restPositions,
      invMass = mesh.invMass,
      start = mesh.positions,
      reach = thickness * (1.0 + _skin),
      tableSize = 2 * mesh.particleCount + 1,
      cellStart = Int32List(2 * mesh.particleCount + 2),
      cellEntries = Int32List(mesh.particleCount),
      cells = Int32List(3 * mesh.particleCount),
      builtAt = Float64List(3 * mesh.particleCount),
      pairStart = Int32List(mesh.particleCount + 1),
      pairs = Int32List(8 * mesh.particleCount);

  /// How far past the thickness the pairs are gathered, in thicknesses.
  static const double _skin = 0.5;

  final int n;
  final double thickness;
  final double friction;
  final Float64List rest;
  final Float64List invMass;

  /// The mesh's positions, which until `_integrate` still hold the start of
  /// the substep: what a particle's slide this substep is measured from.
  final Float64List start;

  /// How far apart two particles may be and still be listed; also the width
  /// of a hash cell, so every listed pair is in neighbouring cells.
  final double reach;
  final int tableSize;
  final Int32List cellStart;
  final Int32List cellEntries;
  final Int32List cells;

  /// Where each particle was when the pairs were last gathered.
  final Float64List builtAt;
  bool _built = false;
  final Int32List pairStart;
  Int32List pairs;

  /// Gathers the pairs again from [x] unless nothing has moved half the
  /// skin since they were last gathered.
  void update(Float64List x) {
    if (_built) {
      final half = 0.5 * _skin * thickness;
      final limit = half * half;
      var moved = false;
      for (var i = 0; i < 3 * n && !moved; i += 3) {
        final dx = x[i] - builtAt[i];
        final dy = x[i + 1] - builtAt[i + 1];
        final dz = x[i + 2] - builtAt[i + 2];
        moved = dx * dx + dy * dy + dz * dz > limit;
      }
      if (!moved) return;
    }
    _findPairs(x);
    builtAt.setAll(0, x);
    _built = true;
  }

  int _cellOf(Float64List x, int i) {
    final inverse = 1.0 / reach;
    final cx = (x[3 * i] * inverse).floor();
    final cy = (x[3 * i + 1] * inverse).floor();
    final cz = (x[3 * i + 2] * inverse).floor();
    cells[3 * i] = cx;
    cells[3 * i + 1] = cy;
    cells[3 * i + 2] = cz;
    return _bucket(cx, cy, cz);
  }

  int _bucket(int cx, int cy, int cz) =>
      (((cx & 1023) << 20) | ((cy & 1023) << 10) | (cz & 1023)) % tableSize;

  /// Hashes [x] and lists every pair within [reach] that is not a pair of
  /// neighbours at rest, each pair once.
  void _findPairs(Float64List x) {
    cellStart.fillRange(0, cellStart.length, 0);
    for (var i = 0; i < n; i++) {
      cellStart[_cellOf(x, i)]++;
    }
    var running = 0;
    for (var h = 0; h < tableSize; h++) {
      running += cellStart[h];
      cellStart[h] = running;
    }
    cellStart[tableSize] = running;
    // Filled from the top down, so each bucket ends up in index order.
    for (var i = n - 1; i >= 0; i--) {
      final h = _bucket(cells[3 * i], cells[3 * i + 1], cells[3 * i + 2]);
      cellStart[h]--;
      cellEntries[cellStart[h]] = i;
    }

    final reach2 = reach * reach;
    final rest2 = thickness * thickness * (1.0 + 1e-6);
    var count = 0;
    for (var i = 0; i < n; i++) {
      pairStart[i] = count;
      final xi = x[3 * i], yi = x[3 * i + 1], zi = x[3 * i + 2];
      final ci = cells[3 * i], cj = cells[3 * i + 1], ck = cells[3 * i + 2];
      // A cell is one reach wide, so everything within the reach is in the particle's own cell or one of its 26 neighbours. Each pair is
      // found once: in the own cell only by its lower index, and otherwise
      // only from the cell whose offset to the other is one of the 13
      // "forward" ones, (dx, dy, dz) after (0, 0, 0) in lexicographic order.
      for (var o = 0; o < _offsets.length; o += 3) {
        final cx = ci + _offsets[o];
        final cy = cj + _offsets[o + 1];
        final cz = ck + _offsets[o + 2];
        final own = o == 0;
        final h = _bucket(cx, cy, cz);
        for (var k = cellStart[h]; k < cellStart[h + 1]; k++) {
          final j = cellEntries[k];
          if (own && j <= i) continue;
          final dx = x[3 * j] - xi;
          final dy = x[3 * j + 1] - yi;
          final dz = x[3 * j + 2] - zi;
          if (dx * dx + dy * dy + dz * dz >= reach2) continue;
          // Two cells can share a bucket; only the pass over j's own cell
          // counts it.
          if (cells[3 * j] != cx ||
              cells[3 * j + 1] != cy ||
              cells[3 * j + 2] != cz) {
            continue;
          }
          if (invMass[i] + invMass[j] == 0.0) continue;
          final rx = rest[3 * j] - rest[3 * i];
          final ry = rest[3 * j + 1] - rest[3 * i + 1];
          final rz = rest[3 * j + 2] - rest[3 * i + 2];
          // Neighbours at rest, within a rounding of the thickness: a grid's
          // own edges are exactly one spacing long, and the default
          // thickness is their mean.
          if (rx * rx + ry * ry + rz * rz < rest2) continue;
          if (count == pairs.length) {
            pairs = Int32List(2 * pairs.length)..setAll(0, pairs);
          }
          pairs[count++] = j;
        }
      }
    }
    pairStart[n] = count;
  }

  /// The own cell, then the 13 neighbours after it in lexicographic order.
  static final Int32List _offsets = Int32List.fromList(<int>[
    0, 0, 0, //
    0, 0, 1, //
    0, 1, -1, 0, 1, 0, 0, 1, 1, //
    1, -1, -1, 1, -1, 0, 1, -1, 1, //
    1, 0, -1, 1, 0, 0, 1, 0, 1, //
    1, 1, -1, 1, 1, 0, 1, 1, 1, //
  ]);

  /// One pass over the pairs [findPairs] listed: each pair closer than the
  /// thickness is pushed apart to it, and [friction] of the slide between
  /// the two this substep, along the surface they touch on, is taken out.
  void solve(Float64List p) {
    final t2 = thickness * thickness;
    for (var i = 0; i < n; i++) {
      final wi = invMass[i];
      for (var k = pairStart[i]; k < pairStart[i + 1]; k++) {
        final j = pairs[k];
        final wj = invMass[j];
        final dx = p[3 * i] - p[3 * j];
        final dy = p[3 * i + 1] - p[3 * j + 1];
        final dz = p[3 * i + 2] - p[3 * j + 2];
        final d2 = dx * dx + dy * dy + dz * dz;
        // At exactly the same point no direction is shorter than another;
        // the other constraints separate them first.
        if (d2 >= t2 || d2 == 0.0) continue;
        final d = math.sqrt(d2);
        final nx = dx / d, ny = dy / d, nz = dz / d;
        final wSum = wi + wj;
        final depth = (thickness - d) / wSum;
        p[3 * i] += wi * depth * nx;
        p[3 * i + 1] += wi * depth * ny;
        p[3 * i + 2] += wi * depth * nz;
        p[3 * j] -= wj * depth * nx;
        p[3 * j + 1] -= wj * depth * ny;
        p[3 * j + 2] -= wj * depth * nz;
        if (friction <= 0.0) continue;
        // The two particles' relative slide this substep, less its part
        // along the normal, shared out by inverse mass so momentum is kept.
        final rx = (p[3 * i] - start[3 * i]) - (p[3 * j] - start[3 * j]);
        final ry =
            (p[3 * i + 1] - start[3 * i + 1]) -
            (p[3 * j + 1] - start[3 * j + 1]);
        final rz =
            (p[3 * i + 2] - start[3 * i + 2]) -
            (p[3 * j + 2] - start[3 * j + 2]);
        final along = rx * nx + ry * ny + rz * nz;
        final scale = friction / wSum;
        final tx = (rx - along * nx) * scale;
        final ty = (ry - along * ny) * scale;
        final tz = (rz - along * nz) * scale;
        p[3 * i] -= wi * tx;
        p[3 * i + 1] -= wi * ty;
        p[3 * i + 2] -= wi * tz;
        p[3 * j] += wj * tx;
        p[3 * j + 1] += wj * ty;
        p[3 * j + 2] += wj * tz;
      }
    }
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
