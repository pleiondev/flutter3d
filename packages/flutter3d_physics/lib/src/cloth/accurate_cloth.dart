/// A sheet under the accurate profile: the equations of motion integrated,
/// not XPBD.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../adaptive.dart';
import '../collision_shape.dart';
import 'cloth_collision.dart';
import 'cloth_mesh.dart';
import 'cloth_settings.dart';
import 'xpbd_solver.dart';

/// Advances [mesh] by [dt] seconds under the accurate profile, in place:
/// what `stepCloth` does when `ClothSettings.profile` allows adaptive steps.
///
/// **The equations, integrated.** The state is every particle's position
/// and velocity in doubles. Gravity, the wind's drag on each triangle and a
/// linear drag for [ClothSettings.damping] are forces; a constraint with a
/// compliance α above nought is a spring of stiffness 1/α along it, which
/// is what XPBD's compliance is in the limit of a small step; a constraint
/// with none is held exactly, by Lagrange multipliers solved from the
/// constraints' second derivatives at every stage (a conjugate-gradient
/// solve of J W Jᵀ λ = −(J a + J̇ v)). [DormandPrince] carries the state
/// through [dt] to a relative error of 1e-10, and after each of its steps
/// the held constraints are projected back onto their lengths, positions
/// and then velocities, so the drift of the multipliers never builds up.
///
/// **What is not held to analytic tests.** Obstacles and the sheet's own
/// layers are pushed apart after each of the integrator's steps, as the
/// fixed path pushes them after each substep, and a particle pushed out
/// loses its velocity into what it hit; friction is the fixed path's alone.
void stepClothAccurately(
  ClothMesh mesh,
  ClothSettings settings,
  double dt, {
  List<ClothObstacle> obstacles = const [],
}) {
  if (dt <= 0) return;
  _AccurateCloth(mesh, settings, dt, obstacles).run();
}

/// The integrators kept per mesh, so each step starts from the step size
/// the last one ended on.
final Expando<DormandPrince> _integrators = Expando<DormandPrince>();

final class _AccurateCloth {
  _AccurateCloth(this.mesh, this.settings, this.dt, this.obstacles)
    : n = mesh.particleCount,
      w = mesh.invMass {
    void sort(Int32List pairs, Float64List rest, double compliance) {
      for (var k = 0; k < rest.length; k++) {
        final a = pairs[2 * k], b = pairs[2 * k + 1];
        if (w[a] + w[b] == 0.0) continue;
        if (compliance <= 0.0) {
          _held.addAll(<int>[a, b]);
          _heldRest.add(rest[k]);
        } else {
          _springs.addAll(<int>[a, b]);
          _springRest.add(rest[k]);
          _stiffness.add(1.0 / compliance);
        }
      }
    }

    sort(
      mesh.structuralPairs,
      mesh.structuralRestLength,
      settings.distanceCompliance,
    );
    sort(mesh.bendPairs, mesh.bendRestLength, settings.bendCompliance);
    sort(mesh.shearPairs, mesh.shearRestLength, settings.shearCompliance);
    final m = _heldRest.length;
    _lambda = Float64List(m);
    _rhs = Float64List(m);
    _r = Float64List(m);
    _p = Float64List(m);
    _ap = Float64List(m);
    _z = Float64List(m);
    _spread = Float64List(3 * n);
    // The damping XPBD applies per substep, (1 − d) at each of `substeps`
    // in the step, as the rate of a linear drag: the same sheet settles
    // alike on both paths.
    final d = settings.damping;
    _dragRate = d <= 0.0 || settings.substeps <= 0
        ? 0.0
        : -math.log(math.max(1.0 - d, 1e-12)) * settings.substeps / dt;
  }

  final ClothMesh mesh;
  final ClothSettings settings;
  final double dt;
  final List<ClothObstacle> obstacles;
  final int n;
  final Float64List w;

  final List<int> _held = <int>[];
  final List<double> _heldRest = <double>[];
  final List<int> _springs = <int>[];
  final List<double> _springRest = <double>[];
  final List<double> _stiffness = <double>[];
  late final Float64List _lambda, _rhs, _r, _p, _ap, _z, _spread;
  late final double _dragRate;

  /// How much of its own diagonal is added to J W Jᵀ before it is solved.
  ///
  /// **A sheet folded or pulled taut has constraints that say the same
  /// thing twice**, and their matrix is singular there: the multipliers
  /// that solve it are as large as the rounding makes them, and the
  /// integrator follows them down to steps of nothing. A billionth of the
  /// diagonal bounds them, and changes a held edge's force by as little.
  /// Measured: an 8×8 sheet pinned at two corners draping over a ball took
  /// a second and more per step at 1e-11 and none at all at nought; at 1e-9
  /// it takes a quarter of one, and the pendulum's energy moves 4.7e-8
  /// where it moved 3.5e-8. At 1e-6 the pendulum lost 1.1e-5.
  static const double _regularization = 1e-9;

  void run() {
    final y = Float64List(6 * n)
      ..setAll(0, mesh.positions)
      ..setAll(3 * n, mesh.velocities);
    final integrator = _integrators[mesh] ??= DormandPrince();
    final thickness = settings.selfCollisionThickness ?? mesh.meanRestEdge;
    final self = settings.selfCollision && thickness > 0.0 && n > 1
        ? ClothSelfCollision(mesh, thickness, 0.0)
        : null;
    final span =
        obstacles.any(
          (o) => o.shape is CollisionSphere || o.shape is CollisionCapsule,
        )
        ? widestTriangles(mesh)
        : null;
    final before = Float64List(3 * n);
    final push = Float64List(3);
    integrator.integrate(
      y,
      0.0,
      dt,
      _derivative,
      after: (double t, y) {
        _project(y);
        if (self == null && obstacles.isEmpty) return;
        final x = Float64List.sublistView(y, 0, 3 * n);
        before.setAll(0, x);
        if (self != null) {
          self.update(x);
          self.solve(x);
        }
        for (var i = 0; i < n; i++) {
          if (w[i] == 0.0) continue;
          for (final obstacle in obstacles) {
            pushParticleOutside(
              x,
              i,
              obstacle,
              settings.collisionThickness,
              push,
              span: span == null ? 0.0 : span[i],
            );
          }
        }
        _loseVelocityInto(y, before);
      },
    );
    for (var i = 0; i < n; i++) {
      if (w[i] == 0.0) continue;
      for (var c = 0; c < 3; c++) {
        mesh.positions[3 * i + c] = y[3 * i + c];
        mesh.velocities[3 * i + c] = y[3 * n + 3 * i + c];
      }
    }
  }

  /// A particle pushed this far since [before] keeps none of its velocity
  /// along the push that went into what pushed it.
  void _loseVelocityInto(Float64List y, Float64List before) {
    for (var i = 0; i < n; i++) {
      final dx = y[3 * i] - before[3 * i];
      final dy = y[3 * i + 1] - before[3 * i + 1];
      final dz = y[3 * i + 2] - before[3 * i + 2];
      final d2 = dx * dx + dy * dy + dz * dz;
      if (d2 == 0.0) continue;
      final v = 3 * n + 3 * i;
      final into = (y[v] * dx + y[v + 1] * dy + y[v + 2] * dz) / d2;
      if (into >= 0.0) continue;
      y[v] -= into * dx;
      y[v + 1] -= into * dy;
      y[v + 2] -= into * dz;
    }
  }

  void _derivative(double t, Float64List y, Float64List dy) {
    final g = settings.gravity;
    for (var i = 0; i < n; i++) {
      final p = 3 * i, v = 3 * n + 3 * i;
      if (w[i] == 0.0) {
        dy
          ..[p] = 0.0
          ..[p + 1] = 0.0
          ..[p + 2] = 0.0
          ..[v] = 0.0
          ..[v + 1] = 0.0
          ..[v + 2] = 0.0;
        continue;
      }
      dy
        ..[p] = y[v]
        ..[p + 1] = y[v + 1]
        ..[p + 2] = y[v + 2]
        ..[v] = -_dragRate * y[v]
        ..[v + 1] = -g - _dragRate * y[v + 1]
        ..[v + 2] = -_dragRate * y[v + 2];
    }
    _addSprings(y, dy);
    if (!settings.wind.isNone) _addWind(y, dy);
    if (_heldRest.isNotEmpty) _addHeld(y, dy);
  }

  void _addSprings(Float64List y, Float64List dy) {
    final o = 3 * n;
    for (var k = 0; k < _springRest.length; k++) {
      final a = _springs[2 * k], b = _springs[2 * k + 1];
      final dx = y[3 * a] - y[3 * b];
      final dyy = y[3 * a + 1] - y[3 * b + 1];
      final dz = y[3 * a + 2] - y[3 * b + 2];
      final len = math.sqrt(dx * dx + dyy * dyy + dz * dz);
      if (len < 1e-12) continue;
      final f = -_stiffness[k] * (len - _springRest[k]) / len;
      final wa = w[a] * f, wb = w[b] * f;
      dy[o + 3 * a] += wa * dx;
      dy[o + 3 * a + 1] += wa * dyy;
      dy[o + 3 * a + 2] += wa * dz;
      dy[o + 3 * b] -= wb * dx;
      dy[o + 3 * b + 1] -= wb * dyy;
      dy[o + 3 * b + 2] -= wb * dz;
    }
  }

  /// The wind's drag on each triangle along its normal, as the fixed path
  /// reckons it, as a force.
  void _addWind(Float64List y, Float64List dy) {
    final wind = settings.wind;
    final drag = wind.effectiveDrag;
    final tris = mesh.triangles;
    final o = 3 * n;
    for (var t = 0; t < tris.length; t += 3) {
      final a = tris[t], b = tris[t + 1], c = tris[t + 2];
      final e1x = y[3 * b] - y[3 * a];
      final e1y = y[3 * b + 1] - y[3 * a + 1];
      final e1z = y[3 * b + 2] - y[3 * a + 2];
      final e2x = y[3 * c] - y[3 * a];
      final e2y = y[3 * c + 1] - y[3 * a + 1];
      final e2z = y[3 * c + 2] - y[3 * a + 2];
      var nx = e1y * e2z - e1z * e2y;
      var ny = e1z * e2x - e1x * e2z;
      var nz = e1x * e2y - e1y * e2x;
      final len = math.sqrt(nx * nx + ny * ny + nz * nz);
      if (len < 1e-12) continue;
      nx /= len;
      ny /= len;
      nz /= len;
      double mean(int axis) =>
          (y[o + 3 * a + axis] + y[o + 3 * b + axis] + y[o + 3 * c + axis]) /
          3.0;
      final relative =
          nx * (wind.velocityX - mean(0)) +
          ny * (wind.velocityY - mean(1)) +
          nz * (wind.velocityZ - mean(2));
      final force = drag * relative * (len * 0.5) / 3.0;
      for (final i in <int>[a, b, c]) {
        final f = force * w[i];
        dy[o + 3 * i] += f * nx;
        dy[o + 3 * i + 1] += f * ny;
        dy[o + 3 * i + 2] += f * nz;
      }
    }
  }

  /// Adds the held constraints' forces to the accelerations in [dy]: the
  /// multipliers that keep every one's second derivative at nought.
  void _addHeld(Float64List y, Float64List dy) {
    final o = 3 * n;
    final m = _heldRest.length;
    for (var k = 0; k < m; k++) {
      final a = _held[2 * k], b = _held[2 * k + 1];
      final dx = y[3 * a] - y[3 * b];
      final dyy = y[3 * a + 1] - y[3 * b + 1];
      final dz = y[3 * a + 2] - y[3 * b + 2];
      final len = math.sqrt(dx * dx + dyy * dyy + dz * dz);
      final ux = dx / len, uy = dyy / len, uz = dz / len;
      final rvx = y[o + 3 * a] - y[o + 3 * b];
      final rvy = y[o + 3 * a + 1] - y[o + 3 * b + 1];
      final rvz = y[o + 3 * a + 2] - y[o + 3 * b + 2];
      final along = ux * rvx + uy * rvy + uz * rvz;
      final across = rvx * rvx + rvy * rvy + rvz * rvz - along * along;
      final accel =
          ux * (dy[o + 3 * a] - dy[o + 3 * b]) +
          uy * (dy[o + 3 * a + 1] - dy[o + 3 * b + 1]) +
          uz * (dy[o + 3 * a + 2] - dy[o + 3 * b + 2]);
      _rhs[k] = -(accel + across / len);
    }
    _solve(y, _rhs, _lambda);
    _spreadBack(y, _lambda);
    for (var i = 0; i < n; i++) {
      dy[o + 3 * i] += w[i] * _spread[3 * i];
      dy[o + 3 * i + 1] += w[i] * _spread[3 * i + 1];
      dy[o + 3 * i + 2] += w[i] * _spread[3 * i + 2];
    }
  }

  /// Jᵀ [lambda] into [_spread], at the positions in [y].
  void _spreadBack(Float64List y, Float64List lambda) {
    _spread.fillRange(0, _spread.length, 0.0);
    for (var k = 0; k < _heldRest.length; k++) {
      final a = _held[2 * k], b = _held[2 * k + 1];
      final dx = y[3 * a] - y[3 * b];
      final dyy = y[3 * a + 1] - y[3 * b + 1];
      final dz = y[3 * a + 2] - y[3 * b + 2];
      final len = math.sqrt(dx * dx + dyy * dyy + dz * dz);
      final s = lambda[k] / len;
      _spread[3 * a] += s * dx;
      _spread[3 * a + 1] += s * dyy;
      _spread[3 * a + 2] += s * dz;
      _spread[3 * b] -= s * dx;
      _spread[3 * b + 1] -= s * dyy;
      _spread[3 * b + 2] -= s * dz;
    }
  }

  /// J W Jᵀ [x] into [out].
  void _apply(Float64List y, Float64List x, Float64List out) {
    _spreadBack(y, x);
    for (var k = 0; k < _heldRest.length; k++) {
      final a = _held[2 * k], b = _held[2 * k + 1];
      final dx = y[3 * a] - y[3 * b];
      final dyy = y[3 * a + 1] - y[3 * b + 1];
      final dz = y[3 * a + 2] - y[3 * b + 2];
      final len = math.sqrt(dx * dx + dyy * dyy + dz * dz);
      out[k] =
          (dx * (w[a] * _spread[3 * a] - w[b] * _spread[3 * b]) +
                  dyy *
                      (w[a] * _spread[3 * a + 1] - w[b] * _spread[3 * b + 1]) +
                  dz *
                      (w[a] * _spread[3 * a + 2] - w[b] * _spread[3 * b + 2])) /
              len +
          _regularization * (w[a] + w[b]) * x[k];
    }
  }

  /// Solves J W Jᵀ [x] = [b] by conjugate gradients, preconditioned by its
  /// diagonal, from what [x] holds (the last solve's answer, which is close).
  void _solve(Float64List y, Float64List b, Float64List x) {
    final m = b.length;
    var bb = 0.0;
    for (var k = 0; k < m; k++) {
      bb += b[k] * b[k];
    }
    if (bb == 0.0) {
      x.fillRange(0, m, 0.0);
      return;
    }
    _apply(y, x, _ap);
    var rz = 0.0;
    for (var k = 0; k < m; k++) {
      _r[k] = b[k] - _ap[k];
      _z[k] = _r[k] / (w[_held[2 * k]] + w[_held[2 * k + 1]]);
      _p[k] = _z[k];
      rz += _r[k] * _z[k];
    }
    final limit = bb * 1e-28;
    for (var iteration = 0; iteration < 4 * m + 20; iteration++) {
      var rr = 0.0;
      for (var k = 0; k < m; k++) {
        rr += _r[k] * _r[k];
      }
      if (rr <= limit) return;
      _apply(y, _p, _ap);
      var pap = 0.0;
      for (var k = 0; k < m; k++) {
        pap += _p[k] * _ap[k];
      }
      if (pap <= 0.0) return;
      final alpha = rz / pap;
      var next = 0.0;
      for (var k = 0; k < m; k++) {
        x[k] += alpha * _p[k];
        _r[k] -= alpha * _ap[k];
        _z[k] = _r[k] / (w[_held[2 * k]] + w[_held[2 * k + 1]]);
        next += _r[k] * _z[k];
      }
      final beta = next / rz;
      rz = next;
      for (var k = 0; k < m; k++) {
        _p[k] = _z[k] + beta * _p[k];
      }
    }
  }

  /// The held constraints back onto their lengths, positions first (each
  /// pair moved along itself by inverse mass until every length is within
  /// 1e-13 of its rest), then velocities (the part of them that would
  /// change a length taken out).
  void _project(Float64List y) {
    final m = _heldRest.length;
    if (m == 0) return;
    for (var pass = 0; pass < 200; pass++) {
      var worst = 0.0;
      for (var k = 0; k < m; k++) {
        final a = _held[2 * k], b = _held[2 * k + 1];
        final dx = y[3 * a] - y[3 * b];
        final dyy = y[3 * a + 1] - y[3 * b + 1];
        final dz = y[3 * a + 2] - y[3 * b + 2];
        final len = math.sqrt(dx * dx + dyy * dyy + dz * dz);
        final c = len - _heldRest[k];
        worst = math.max(worst, c.abs() / _heldRest[k]);
        final s = -c / ((w[a] + w[b]) * len);
        y[3 * a] += w[a] * s * dx;
        y[3 * a + 1] += w[a] * s * dyy;
        y[3 * a + 2] += w[a] * s * dz;
        y[3 * b] -= w[b] * s * dx;
        y[3 * b + 1] -= w[b] * s * dyy;
        y[3 * b + 2] -= w[b] * s * dz;
      }
      if (worst <= 1e-13) break;
    }
    final o = 3 * n;
    for (var k = 0; k < m; k++) {
      final a = _held[2 * k], b = _held[2 * k + 1];
      final dx = y[3 * a] - y[3 * b];
      final dyy = y[3 * a + 1] - y[3 * b + 1];
      final dz = y[3 * a + 2] - y[3 * b + 2];
      final len = math.sqrt(dx * dx + dyy * dyy + dz * dz);
      _rhs[k] =
          (dx * (y[o + 3 * a] - y[o + 3 * b]) +
              dyy * (y[o + 3 * a + 1] - y[o + 3 * b + 1]) +
              dz * (y[o + 3 * a + 2] - y[o + 3 * b + 2])) /
          len;
    }
    final mu = Float64List(m);
    _solve(y, _rhs, mu);
    _spreadBack(y, mu);
    for (var i = 0; i < n; i++) {
      y[o + 3 * i] -= w[i] * _spread[3 * i];
      y[o + 3 * i + 1] -= w[i] * _spread[3 * i + 1];
      y[o + 3 * i + 2] -= w[i] * _spread[3 * i + 2];
    }
  }
}
