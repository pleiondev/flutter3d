import 'dart:math' as math;
import 'dart:typed_data';

/// The loops over pairs of neighbours that a Position Based Fluids substep
/// is made of, over flat buffers: what [ParticleFluid] hands to whichever
/// implementation runs them, this one in Dart or a native one.
///
/// **Flat, so another language can take them as they are.** Positions,
/// velocities and every per-particle vector are `Float64List`s of x, y, z
/// in turn; the neighbours are compressed rows, particle i's being
/// `list[start[i]]` up to `list[start[i + 1]]`, itself left out. Nothing
/// here knows about walls, receivers or drops: [ParticleFluid] keeps those,
/// between the calls.
///
/// **This implementation is the reference**: the order of every sum is the
/// order [ParticleFluid] has always added in, so a step is the same step to
/// the last bit. A native one, free to vectorise, is held to it within a
/// tolerance instead.
abstract interface class PbfKernels {
  /// Each particle's density, from its neighbours at [x]: ρ₀·ΣW/ΣW_rest.
  void densities(
    Float64List x,
    Int32List start,
    Int32List list,
    int n,
    Float64List density,
  );

  /// Each particle's colour-field normal, h·Σ m/ρⱼ·∇W, into [normal].
  void normals(
    Float64List x,
    Int32List start,
    Int32List list,
    int n,
    Float64List density,
    Float64List normal,
  );

  /// The forces on each particle as accelerations, added to its velocity
  /// [v] over [dt]: [before] (gravity), then cohesion and curvature from
  /// its neighbours, then [after] (the air's drag), in that order.
  void forces(
    Float64List x,
    Int32List start,
    Int32List list,
    int n,
    Float64List density,
    Float64List normal,
    Float64List before,
    Float64List after,
    Float64List v,
    double dt,
  );

  /// Each particle's density constraint multiplier λ, from the predicted
  /// positions [p]: only where it is compressed.
  void lambdas(
    Float64List p,
    Int32List start,
    Int32List list,
    int n,
    Float64List lambda,
  );

  /// Each particle's position correction Δp from [lambda], with the
  /// artificial pressure that keeps neighbours from clumping, into [delta].
  void deltas(
    Float64List p,
    Int32List start,
    Int32List list,
    int n,
    Float64List lambda,
    Float64List delta,
  );

  /// XSPH: each velocity drawn towards its neighbours' by [share] of the
  /// kernel weight, into [smoothed].
  void viscosity(
    Float64List p,
    Float64List v,
    Int32List start,
    Int32List list,
    int n,
    double share,
    Float64List smoothed,
  );
}

/// The constants the kernels share, worked out once for a fluid.
final class PbfConstants {
  PbfConstants({
    required this.h,
    required this.restDensity,
    required this.mass,
    required this.norm,
    required this.gamma,
    required this.restStiffness,
  }) : h2 = h * h,
       poly6 = 315.0 / (64.0 * math.pi * _pow9(h)),
       spiky = -45.0 / (math.pi * _pow6(h)),
       cohesion = 32.0 / (math.pi * _pow9(h)),
       h6 = _pow6(h),
       wq = _poly6Of((0.3 * h) * (0.3 * h), h);

  /// The kernel's reach, and its square.
  final double h;
  final double h2;

  /// ρ₀, and one particle's mass.
  final double restDensity;
  final double mass;

  /// One over the kernel summed over the lattice at rest.
  final double norm;

  /// Akinci's cohesion coefficient.
  final double gamma;

  /// Σ|∇C|² on the lattice, which the artificial pressure is a share of.
  final double restStiffness;

  /// The kernels' own normalisations.
  final double poly6;
  final double spiky;
  final double cohesion;
  final double h6;

  /// W at 0.3·h, the artificial pressure's reference.
  final double wq;

  static double _pow6(double x) => x * x * x * x * x * x;
  static double _pow9(double x) => _pow6(x) * x * x * x;
  static double _poly6Of(double r2, double h) {
    final h2 = h * h;
    if (r2 >= h2) return 0.0;
    final d = h2 - r2;
    return 315.0 / (64.0 * math.pi * _pow9(h)) * d * d * d;
  }
}

/// [PbfKernels] in Dart: the reference.
final class DartPbfKernels implements PbfKernels {
  DartPbfKernels(this.k);

  final PbfConstants k;

  double _poly6(double r2) {
    if (r2 >= k.h2) return 0.0;
    final d = k.h2 - r2;
    return k.poly6 * d * d * d;
  }

  double _spikyScale(double r) {
    if (r <= 1e-12 || r >= k.h) return 0.0;
    return k.spiky * (k.h - r) * (k.h - r) / r;
  }

  double _cohesion(double r) {
    final h = k.h;
    if (r >= h || r <= 0.0) return 0.0;
    final a = (h - r) * (h - r) * (h - r) * r * r * r;
    if (2.0 * r > h) return k.cohesion * a;
    return k.cohesion * (2.0 * a - k.h6 / 64.0);
  }

  @override
  void densities(
    Float64List x,
    Int32List start,
    Int32List list,
    int n,
    Float64List density,
  ) {
    for (var i = 0; i < n; i++) {
      final xi = x[3 * i];
      final yi = x[3 * i + 1];
      final zi = x[3 * i + 2];
      var w = _poly6(0.0);
      for (var q = start[i]; q < start[i + 1]; q++) {
        final j = list[q];
        final dx = xi - x[3 * j];
        final dy = yi - x[3 * j + 1];
        final dz = zi - x[3 * j + 2];
        w += _poly6(dx * dx + dy * dy + dz * dz);
      }
      density[i] = k.restDensity * w * k.norm;
    }
  }

  @override
  void normals(
    Float64List x,
    Int32List start,
    Int32List list,
    int n,
    Float64List density,
    Float64List normal,
  ) {
    for (var i = 0; i < n; i++) {
      final xi = x[3 * i];
      final yi = x[3 * i + 1];
      final zi = x[3 * i + 2];
      var nx = 0.0;
      var ny = 0.0;
      var nz = 0.0;
      for (var q = start[i]; q < start[i + 1]; q++) {
        final j = list[q];
        final dx = xi - x[3 * j];
        final dy = yi - x[3 * j + 1];
        final dz = zi - x[3 * j + 2];
        final f =
            _spikyScale(math.sqrt(dx * dx + dy * dy + dz * dz)) *
            k.h *
            k.mass /
            density[j];
        nx += dx * f;
        ny += dy * f;
        nz += dz * f;
      }
      normal[3 * i] = nx;
      normal[3 * i + 1] = ny;
      normal[3 * i + 2] = nz;
    }
  }

  @override
  void forces(
    Float64List x,
    Int32List start,
    Int32List list,
    int n,
    Float64List density,
    Float64List normal,
    Float64List before,
    Float64List after,
    Float64List v,
    double dt,
  ) {
    final rho0 = k.restDensity;
    for (var i = 0; i < n; i++) {
      final xi = x[3 * i];
      final yi = x[3 * i + 1];
      final zi = x[3 * i + 2];
      var ax = before[3 * i];
      var ay = before[3 * i + 1];
      var az = before[3 * i + 2];
      for (var q = start[i]; q < start[i + 1]; q++) {
        final j = list[q];
        final dx = xi - x[3 * j];
        final dy = yi - x[3 * j + 1];
        final dz = zi - x[3 * j + 2];
        final r = math.sqrt(dx * dx + dy * dy + dz * dz);
        if (r < 1e-12) continue;
        final kk = 2.0 * rho0 / (density[i] + density[j]);
        final c = -kk * k.gamma * k.mass * _cohesion(r) / r;
        final t = -kk * k.gamma;
        ax += dx * c + (normal[3 * i] - normal[3 * j]) * t;
        ay += dy * c + (normal[3 * i + 1] - normal[3 * j + 1]) * t;
        az += dz * c + (normal[3 * i + 2] - normal[3 * j + 2]) * t;
      }
      ax += after[3 * i];
      ay += after[3 * i + 1];
      az += after[3 * i + 2];
      v[3 * i] += ax * dt;
      v[3 * i + 1] += ay * dt;
      v[3 * i + 2] += az * dt;
    }
  }

  @override
  void lambdas(
    Float64List p,
    Int32List start,
    Int32List list,
    int n,
    Float64List lambda,
  ) {
    final norm = k.norm;
    for (var i = 0; i < n; i++) {
      final xi = p[3 * i];
      final yi = p[3 * i + 1];
      final zi = p[3 * i + 2];
      var w = _poly6(0.0);
      var sum2 = 0.0;
      var gx = 0.0;
      var gy = 0.0;
      var gz = 0.0;
      for (var q = start[i]; q < start[i + 1]; q++) {
        final j = list[q];
        final dx = xi - p[3 * j];
        final dy = yi - p[3 * j + 1];
        final dz = zi - p[3 * j + 2];
        final r2 = dx * dx + dy * dy + dz * dz;
        w += _poly6(r2);
        final f = _spikyScale(math.sqrt(r2)) * norm;
        sum2 += r2 * f * f;
        gx += dx * f;
        gy += dy * f;
        gz += dz * f;
      }
      sum2 += gx * gx + gy * gy + gz * gz;
      final c = math.max(w * norm - 1.0, 0.0);
      lambda[i] = -c / (sum2 + 1e-6 * norm * norm / (k.h * k.h));
    }
  }

  @override
  void deltas(
    Float64List p,
    Int32List start,
    Int32List list,
    int n,
    Float64List lambda,
    Float64List delta,
  ) {
    final norm = k.norm;
    for (var i = 0; i < n; i++) {
      final xi = p[3 * i];
      final yi = p[3 * i + 1];
      final zi = p[3 * i + 2];
      var sx = 0.0;
      var sy = 0.0;
      var sz = 0.0;
      for (var q = start[i]; q < start[i + 1]; q++) {
        final j = list[q];
        final dx = xi - p[3 * j];
        final dy = yi - p[3 * j + 1];
        final dz = zi - p[3 * j + 2];
        final r2 = dx * dx + dy * dy + dz * dz;
        final ratio = _poly6(r2) / k.wq;
        // Macklin's artificial pressure: a fiftieth of a constraint's worth.
        final corr = -0.02 * ratio * ratio * ratio * ratio / k.restStiffness;
        final f =
            _spikyScale(math.sqrt(r2)) * (lambda[i] + lambda[j] + corr) * norm;
        sx += dx * f;
        sy += dy * f;
        sz += dz * f;
      }
      delta[3 * i] = sx;
      delta[3 * i + 1] = sy;
      delta[3 * i + 2] = sz;
    }
  }

  @override
  void viscosity(
    Float64List p,
    Float64List v,
    Int32List start,
    Int32List list,
    int n,
    double share,
    Float64List smoothed,
  ) {
    final norm = k.norm;
    for (var i = 0; i < n; i++) {
      final xi = p[3 * i];
      final yi = p[3 * i + 1];
      final zi = p[3 * i + 2];
      final vx = v[3 * i];
      final vy = v[3 * i + 1];
      final vz = v[3 * i + 2];
      var sx = vx;
      var sy = vy;
      var sz = vz;
      for (var q = start[i]; q < start[i + 1]; q++) {
        final j = list[q];
        final dx = xi - p[3 * j];
        final dy = yi - p[3 * j + 1];
        final dz = zi - p[3 * j + 2];
        final w = _poly6(dx * dx + dy * dy + dz * dz) * norm * share;
        sx += (v[3 * j] - vx) * w;
        sy += (v[3 * j + 1] - vy) * w;
        sz += (v[3 * j + 2] - vz) * w;
      }
      smoothed[3 * i] = sx;
      smoothed[3 * i + 1] = sy;
      smoothed[3 * i + 2] = sz;
    }
  }
}
