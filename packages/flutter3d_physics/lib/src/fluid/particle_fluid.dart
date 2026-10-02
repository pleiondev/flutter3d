import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'fluid_medium.dart';
import 'jet.dart';

/// A flat surface particles rest on — a bench, a floor: the points with
/// `normal · p ≥ offset` are clear of it.
final class PlaneObstacle implements JetObstacle {
  PlaneObstacle({required Vector3 normal, required this.offset})
    : normal = normal.normalized();

  final Vector3 normal;
  final double offset;

  @override
  ({Vector3 normal, double depth})? touch(Vector3 point, double radius) {
    final d = normal.dot(point) - offset - radius;
    return d < 0.0 ? (normal: normal, depth: -d) : null;
  }
}

/// Liquid that has left every vessel and stream — drops, splashes, a puddle
/// on the bench — as particles: Position Based Fluids (Macklin and Müller,
/// 2013).
///
/// **Incompressibility is a constraint, not a stiff spring.** Each particle
/// carries ρ₀s³ of liquid, s the [spacing]; its density is the poly6-weighted
/// sum of its neighbours' masses, and every step the positions are moved, a
/// few passes over, until each density is the rest density: the constraint
/// ρᵢ/ρ₀ − 1 = 0, solved along its spiky-kernel gradient. A small artificial
/// pressure keeps neighbours from clumping where too few surround them.
///
/// **Viscosity** is XSPH's: each velocity is drawn towards its neighbours'
/// by a share that grows with the medium's kinematic viscosity over s²/Δt —
/// an artificial viscosity, so honey is slow and water quick, but not to the
/// figures a viscous flow is measured by.
///
/// **Surface tension** is Akinci and colleagues' (2013): cohesion between
/// neighbours plus a pull that flattens curvature. Their coefficient is not
/// σ; it is set so that pulling the liquid apart along a plane takes 2σ per
/// square metre, the work of cohesion, worked out once over the particle
/// lattice. A contact angle against a wall is not modelled: a puddle spreads
/// as far as cohesion lets it, whatever the wall.
///
/// **Every cubic metre is counted.** Liquid arrives by [inject] in any
/// amount, and what is less than one particle waits in a bank until it is;
/// what reaches a receiver leaves as whole particles. So [volume] — the
/// particles and the bank — is exactly what came in less what left.
final class ParticleFluid {
  ParticleFluid({
    required this.medium,
    required this.spacing,
    this.iterations = 4,
    this.substeps = 2,
  }) : h = 2.0 * spacing {
    _gamma = _cohesionForWorkOfCohesion();
    // The kernel summed over the lattice at rest: what a particle's density
    // estimate is divided by, so liquid at its rest spacing is at its rest
    // density exactly, whatever the kernel's own normalisation makes of a
    // discrete lattice.
    var sum = 0.0;
    var gradient2 = 0.0;
    final reach = (h / spacing).ceil();
    for (var a = -reach; a <= reach; a++) {
      for (var b = -reach; b <= reach; b++) {
        for (var c = -reach; c <= reach; c++) {
          final r2 = (a * a + b * b + c * c) * spacing * spacing;
          sum += _poly6(r2);
          gradient2 += _spikyGradient(
            _V(a * spacing, b * spacing, c * spacing),
          ).length2;
        }
      }
    }
    _latticeSum = sum;
    // How strongly the constraint answers a move at rest: Σ|∇C|² on the
    // lattice, in the constraint's normalisation. The artificial pressure
    // is a share of a constraint's worth over this.
    _restStiffness = gradient2 / (sum * sum);
  }

  late final double _latticeSum;
  late final double _restStiffness;

  final FluidMedium medium;

  /// The particles' spacing at rest, metres.
  final double spacing;

  /// Density passes per substep, and the fewest substeps per [step].
  final int iterations;
  final int substeps;

  /// The time surface tension takes to move a particle its own size,
  /// √(ρs³/σ): the cohesion between neighbours is a spring this quick, and
  /// a step stepped explicitly must be well inside it. A third of a
  /// millisecond for millimetre water, where a fixed two substeps of a
  /// 240th of a second threw drops apart at metres a second.
  double get capillaryTime => medium.surfaceTension > 0.0
      ? math.sqrt(
          medium.density * spacing * spacing * spacing / medium.surfaceTension,
        )
      : double.infinity;

  /// The kernel's reach.
  final double h;

  late final double _gamma;

  // In double precision: a particle's velocity is read off how far it moved
  // in a substep, a millionth of a metre a metre from the origin, and
  // single precision has only a tenth of that to spare.
  final List<_V> _x = [];
  final List<_V> _v = [];

  /// What is dissolved in each particle, as concentrations; and in the
  /// bank, as amounts.
  final List<Map<String, double>> _c = [];
  final Map<String, double> _bankAmounts = {};
  double _bank = 0.0;
  double _received = 0.0;

  /// How much liquid one particle is.
  double get particleVolume => spacing * spacing * spacing;
  double get _mass => medium.density * particleVolume;

  /// The particles' places.
  List<Vector3> get positions => [for (final p in _x) p.toVector3()];
  int get count => _x.length;

  /// Cubic metres here: every particle and the bank.
  double get volume => _x.length * particleVolume + _bank;

  /// Cubic metres handed to receivers so far.
  double get received => _received;

  /// Adds [amount] cubic metres at [position] moving at [velocity], with
  /// [concentrations] dissolved in it: as many whole particles as it and
  /// the bank make, laid out round [position] at the spacing so none start
  /// on top of another, each carrying what the bank holds per cubic metre.
  void inject(
    double amount,
    Vector3 position,
    Vector3 velocity, {
    Map<String, double> concentrations = const {},
  }) {
    _bank += amount;
    concentrations.forEach((key, c) {
      _bankAmounts[key] = (_bankAmounts[key] ?? 0.0) + c * amount;
    });
    // A hair of slack, so that halves that add up to a whole make one.
    final whole = (_bank / particleVolume + 1e-9).floor();
    if (whole <= 0) return;
    final carried = {
      for (final e in _bankAmounts.entries) e.key: e.value / _bank,
    };
    final left = math.max(_bank - whole * particleVolume, 0.0);
    for (final key in _bankAmounts.keys.toList()) {
      _bankAmounts[key] = carried[key]! * left;
    }
    _bank = left;
    var side = 1;
    while (side * side * side < whole) {
      side++;
    }
    var placed = 0;
    for (var k = 0; k < side && placed < whole; k++) {
      for (var j = 0; j < side && placed < whole; j++) {
        for (var i = 0; i < side && placed < whole; i++) {
          _x.add(
            _V(
              position.x + (i - 0.5 * (side - 1)) * spacing,
              position.y + (j - 0.5 * (side - 1)) * spacing,
              position.z + (k - 0.5 * (side - 1)) * spacing,
            ),
          );
          _v.add(_V(velocity.x, velocity.y, velocity.z));
          _c.add(carried);
          placed++;
        }
      }
    }
  }

  /// Moves the particles on by [dt] under [gravity], against [obstacles],
  /// into [receivers].
  void step(
    double dt, {
    required Vector3 gravity,
    List<JetObstacle> obstacles = const [],
    List<JetReceiver> receivers = const [],
  }) {
    if (_x.isEmpty) return;
    // A quarter of the capillary time a substep at most, and two fifths of
    // a spacing's travel: a wall holds what comes within a radius of it or
    // half its thickness into it, a band wider than that, so nothing passes
    // through glass thinner than a particle between one look and the next.
    // Never fewer than asked.
    final fastest = _v.fold(0.0, (m, v) => math.max(m, v.length));
    final count = [
      substeps,
      (dt / (0.25 * capillaryTime)).ceil(),
      (fastest * dt / (0.4 * spacing)).ceil(),
    ].reduce(math.max).clamp(1, 256);
    final sub = dt / count;
    final g = _V(gravity.x, gravity.y, gravity.z);
    for (var s = 0; s < count; s++) {
      _substep(sub, g, obstacles);
    }
    // Into a vessel's liquid: handed over, whole.
    final radius = 0.5 * spacing;
    for (var i = _x.length - 1; i >= 0; i--) {
      final at = _x[i].toVector3();
      for (final r in receivers) {
        if (!r.catches(at, radius)) continue;
        r.receive(particleVolume, at, _v[i].toVector3(), medium, _c[i]);
        _received += particleVolume;
        _x.removeAt(i);
        _v.removeAt(i);
        _c.removeAt(i);
        break;
      }
    }
  }

  void _substep(double dt, _V gravity, List<JetObstacle> obstacles) {
    final n = _x.length;
    final rho0 = medium.density;
    final m = _mass;
    final norm = 1.0 / _latticeSum;
    // Forces first: gravity, cohesion and curvature, on the velocities.
    final grid = _Grid(h, _x);
    final neighbours = [for (var i = 0; i < n; i++) grid.near(i, _x)];
    final density = List<double>.filled(n, 0.0);
    for (var i = 0; i < n; i++) {
      var w = _poly6(0.0);
      for (final j in neighbours[i]) {
        w += _poly6(_x[i].distance2(_x[j]));
      }
      density[i] = rho0 * w * norm;
    }
    final normal = List<_V>.generate(n, (_) => _V(0, 0, 0));
    for (var i = 0; i < n; i++) {
      for (final j in neighbours[i]) {
        normal[i].addScaled(_spikyGradient(_x[i] - _x[j]), h * m / density[j]);
      }
    }
    for (var i = 0; i < n; i++) {
      final a = gravity.copy();
      for (final j in neighbours[i]) {
        final d = _x[i] - _x[j];
        final r = d.length;
        if (r < 1e-12) continue;
        final k = 2.0 * rho0 / (density[i] + density[j]);
        a
          ..addScaled(d, -k * _gamma * m * _cohesion(r) / r)
          ..addScaled(normal[i] - normal[j], -k * _gamma);
      }
      _v[i].addScaled(a, dt);
    }
    // Predict, then hold the density to the rest density.
    final p = [for (var i = 0; i < n; i++) _x[i] + _v[i] * dt];
    final lambda = List<double>.filled(n, 0.0);
    final grid2 = _Grid(h, p);
    final near = [for (var i = 0; i < n; i++) grid2.near(i, p)];
    final dq = 0.3 * h;
    final wq = _poly6(dq * dq);
    for (var it = 0; it < iterations; it++) {
      for (var i = 0; i < n; i++) {
        // C = ρ/ρ₀ − 1 with ρ/ρ₀ the kernel sum over the lattice's: only
        // where it is compressed. Both ways, a surface particle with half
        // its neighbours missing is pulled in by half a spacing a pass and
        // the liquid flies apart; a stretched surface is held by cohesion
        // instead.
        var w = _poly6(0.0);
        var sum2 = 0.0;
        final gi = _V(0, 0, 0);
        for (final j in near[i]) {
          final d = p[i] - p[j];
          w += _poly6(d.length2);
          final g = _spikyGradient(d) * norm;
          sum2 += g.length2;
          gi.add(g);
        }
        sum2 += gi.length2;
        final c = math.max(w * norm - 1.0, 0.0);
        lambda[i] = -c / (sum2 + 1e-6 * norm * norm / (h * h));
      }
      final delta = List<_V>.generate(n, (_) => _V(0, 0, 0));
      for (var i = 0; i < n; i++) {
        for (final j in near[i]) {
          final d = p[i] - p[j];
          final ratio = _poly6(d.length2) / wq;
          // Macklin's artificial pressure, which keeps neighbours from
          // clumping: a fiftieth of a constraint's worth. At his tenth it
          // held still water a sixth thinner than its rest density.
          final corr = -0.02 * ratio * ratio * ratio * ratio / _restStiffness;
          // Δpᵢ = Σⱼ (λᵢ + λⱼ + s_corr) ∇W(pᵢ − pⱼ), in the same
          // normalisation as the constraint.
          delta[i].addScaled(
            _spikyGradient(d),
            (lambda[i] + lambda[j] + corr) * norm,
          );
        }
      }
      for (var i = 0; i < n; i++) {
        p[i].add(delta[i]);
        _collide(p[i], obstacles);
      }
    }
    // Velocities from the move, then XSPH's viscosity.
    for (var i = 0; i < n; i++) {
      _v[i] = (p[i] - _x[i]) * (1.0 / dt);
    }
    final share = math.min(
      0.5,
      medium.kinematicViscosity * dt / (spacing * spacing) * 50.0 + 0.01,
    );
    final smoothed = [for (final v in _v) v.copy()];
    for (var i = 0; i < n; i++) {
      for (final j in near[i]) {
        final w = _poly6(p[i].distance2(p[j])) * norm;
        smoothed[i].addScaled(_v[j] - _v[i], share * w);
      }
    }
    for (var i = 0; i < n; i++) {
      _v[i] = smoothed[i];
      _x[i] = p[i];
    }
  }

  void _collide(_V p, List<JetObstacle> obstacles) {
    final radius = 0.5 * spacing;
    for (final o in obstacles) {
      final hit = o.touch(p.toVector3(), radius);
      if (hit != null) {
        p.addScaled(_V(hit.normal.x, hit.normal.y, hit.normal.z), hit.depth);
      }
    }
  }

  double _poly6(double r2) {
    final h2 = h * h;
    if (r2 >= h2) return 0.0;
    final d = h2 - r2;
    return 315.0 / (64.0 * math.pi * _pow9(h)) * d * d * d;
  }

  _V _spikyGradient(_V d) {
    final r = d.length;
    if (r <= 1e-12 || r >= h) return _V(0, 0, 0);
    final f = -45.0 / (math.pi * _pow6(h)) * (h - r) * (h - r);
    return d * (f / r);
  }

  /// Akinci's cohesion spline.
  double _cohesion(double r) {
    if (r >= h || r <= 0.0) return 0.0;
    final c = 32.0 / (math.pi * _pow9(h));
    final a = (h - r) * (h - r) * (h - r) * r * r * r;
    if (2.0 * r > h) return c * a;
    return c * (2.0 * a - _pow6(h) / 64.0);
  }

  /// The cohesion coefficient that makes the work of pulling the lattice
  /// apart along a plane 2σ per square metre: the potential of the cohesion
  /// force, summed across a plane over every pair within reach, per unit of
  /// area, at a coefficient of one, then scaled.
  double _cohesionForWorkOfCohesion() {
    final m = _mass;
    double potential(double r) {
      // ∫ from r to h of m²C(s) ds, by Simpson over sixteen pieces.
      const pieces = 16;
      final step = (h - r) / pieces;
      var sum = 0.0;
      for (var k = 0; k <= pieces; k++) {
        final s = r + k * step;
        final w = k == 0 || k == pieces ? 1.0 : (k.isOdd ? 4.0 : 2.0);
        sum += w * m * m * _cohesion(s);
      }
      return sum * step / 3.0;
    }

    final reach = (h / spacing).ceil() + 1;
    var work = 0.0;
    // One column of particles below the plane, at z = −(k + ½)s, against
    // every particle above it.
    for (var k = 0; k < reach; k++) {
      final zi = -(k + 0.5) * spacing;
      for (var a = -reach; a <= reach; a++) {
        for (var b = -reach; b <= reach; b++) {
          for (var c = 0; c < reach; c++) {
            final d = Vector3(
              a * spacing,
              b * spacing,
              (c + 0.5) * spacing - zi,
            );
            final r = d.length;
            if (r < h) work += potential(r);
          }
        }
      }
    }
    work /= spacing * spacing;
    return work > 0.0 ? 2.0 * medium.surfaceTension / work : 0.0;
  }

  static double _pow6(double x) => x * x * x * x * x * x;
  static double _pow9(double x) => _pow6(x) * x * x * x;
}

/// A uniform grid of cells as wide as the kernel, for finding neighbours.
final class _Grid {
  _Grid(this.cell, List<_V> points) {
    for (var i = 0; i < points.length; i++) {
      _cells.putIfAbsent(_key(points[i]), () => []).add(i);
    }
  }

  final double cell;
  final Map<int, List<int>> _cells = {};

  int _key(_V p) =>
      _pack((p.x / cell).floor(), (p.y / cell).floor(), (p.z / cell).floor());

  static int _pack(int x, int y, int z) =>
      ((x & 0x1fffff) << 42) | ((y & 0x1fffff) << 21) | (z & 0x1fffff);

  /// The points within [cell] of point [i], itself left out.
  List<int> near(int i, List<_V> points) {
    final p = points[i];
    final cx = (p.x / cell).floor();
    final cy = (p.y / cell).floor();
    final cz = (p.z / cell).floor();
    final out = <int>[];
    final reach2 = cell * cell;
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        for (var dz = -1; dz <= 1; dz++) {
          final list = _cells[_pack(cx + dx, cy + dy, cz + dz)];
          if (list == null) continue;
          for (final j in list) {
            if (j != i && points[j].distance2(p) < reach2) out.add(j);
          }
        }
      }
    }
    return out;
  }
}

/// A vector in double precision, for the solver's own arithmetic.
final class _V {
  _V(this.x, this.y, this.z);

  double x;
  double y;
  double z;

  _V copy() => _V(x, y, z);
  Vector3 toVector3() => Vector3(x, y, z);

  _V operator +(_V o) => _V(x + o.x, y + o.y, z + o.z);
  _V operator -(_V o) => _V(x - o.x, y - o.y, z - o.z);
  _V operator *(double k) => _V(x * k, y * k, z * k);

  void add(_V o) {
    x += o.x;
    y += o.y;
    z += o.z;
  }

  void addScaled(_V o, double k) {
    x += o.x * k;
    y += o.y * k;
    z += o.z * k;
  }

  double get length2 => x * x + y * y + z * z;
  double get length => math.sqrt(length2);

  double distance2(_V o) {
    final dx = x - o.x, dy = y - o.y, dz = z - o.z;
    return dx * dx + dy * dy + dz * dz;
  }
}
