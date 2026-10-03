import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import '../portable_math.dart';
import 'atmosphere.dart';
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
  bool reaches(Vector3 centre, double distance) =>
      normal.dot(centre) - offset < distance;

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

  /// Each particle's liquid, cubic metres: [particleVolume], but for the
  /// last of a run of drops, which is what was left in the bank.
  final List<double> _vol = [];

  /// Where and how fast the last liquid came in, and whether any came in
  /// since the last step: the bank is let go there once none does.
  final _V _lastAt = _V(0, 0, 0);
  final _V _lastVelocity = _V(0, 0, 0);
  bool _injected = false;

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
  double get volume => _vol.fold(0.0, (s, v) => s + v) + _bank;

  /// The particles' liquid, cubic metres each.
  List<double> get volumes => List.unmodifiable(_vol);

  /// What is dissolved in the particles, as concentrations over all of
  /// them: for drawing them the colour of what they are.
  Map<String, double> get concentrations {
    if (_c.isEmpty) return const {};
    final sum = <String, double>{};
    for (final c in _c) {
      c.forEach((k, v) => sum[k] = (sum[k] ?? 0.0) + v);
    }
    return {for (final e in sum.entries) e.key: e.value / _c.length};
  }

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
    _injected = true;
    _lastAt
      ..x = position.x
      ..y = position.y
      ..z = position.z;
    _lastVelocity
      ..x = velocity.x
      ..y = velocity.y
      ..z = velocity.z;
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
          _vol.add(particleVolume);
          _c.add(carried);
          placed++;
        }
      }
    }
  }

  /// Moves the particles on by [dt] under [gravity], against [obstacles],
  /// into [receivers], through [air] when there is any.
  void step(
    double dt, {
    required Vector3 gravity,
    List<JetObstacle> obstacles = const [],
    List<JetReceiver> receivers = const [],
    Atmosphere? air,
  }) {
    // **What is less than a particle is let go too**, once no more liquid
    // comes to make it one: as a particle of its own amount, where the last
    // came in. Kept in the bank, the end of every run of drops, up to a
    // particle's worth of it, was counted and was nowhere.
    if (!_injected && _bank > 0.0) {
      _x.add(_lastAt.copy());
      _v.add(_lastVelocity.copy());
      _vol.add(_bank);
      _c.add({for (final e in _bankAmounts.entries) e.key: e.value / _bank});
      _bank = 0.0;
      _bankAmounts.clear();
    }
    _injected = false;
    if (_x.isEmpty) return;
    // A quarter of the capillary time a substep at most, and never fewer
    // than asked. How far a particle goes in one is not held here: it is
    // moved in pieces against the walls instead (`_advance`), which costs a
    // wall test, not a density solve, per piece.
    final fastest = _v.fold(0.0, (m, v) => math.max(m, v.length));
    final count = math
        .max(substeps, (dt / (0.25 * capillaryTime)).ceil())
        .clamp(1, 256);
    final sub = dt / count;
    final g = _V(gravity.x, gravity.y, gravity.z);
    // The walls anything here could reach this step, found once: every
    // particle, and as far as the fastest goes, in one ball.
    final low = _x.first.copy();
    final high = _x.first.copy();
    for (final p in _x) {
      low
        ..x = math.min(low.x, p.x)
        ..y = math.min(low.y, p.y)
        ..z = math.min(low.z, p.z);
      high
        ..x = math.max(high.x, p.x)
        ..y = math.max(high.y, p.y)
        ..z = math.max(high.z, p.z);
    }
    final walls = obstaclesNear(
      obstacles,
      ((low + high) * 0.5).toVector3(),
      0.5 * (high - low).length +
          (fastest + gravity.length * dt) * dt +
          spacing,
    );
    _air = air;
    if (air != null) _measureDrops(dt, air);
    for (var s = 0; s < count; s++) {
      _substep(sub, g, walls);
    }
    // Into a vessel's liquid, or onto its glass inside, which runs down
    // into it: handed over, whole.
    final radius = 0.5 * spacing;
    for (var i = _x.length - 1; i >= 0; i--) {
      final at = _x[i].toVector3();
      for (final r in receivers) {
        if (!r.catches(at, radius) && !r.wets(at, radius)) continue;
        r.receive(_vol[i], at, _v[i].toVector3(), medium, _c[i]);
        _received += _vol[i];
        _x.removeAt(i);
        _v.removeAt(i);
        _vol.removeAt(i);
        _c.removeAt(i);
        break;
      }
    }
  }

  /// The air the particles are being stepped through, and each particle's
  /// drop's diameter: set at the start of a step, read by its substeps.
  Atmosphere? _air;
  Float64List _drop = Float64List(0);

  /// Cubic metres evaporated from the drops so far.
  double get evaporated => _evaporated;
  double _evaporated = 0.0;

  /// **The drops, as drops**: particles nearer each other than a spacing
  /// and a half are one, of their summed volume. A drop's drag goes with
  /// its own size, d² against a mass of d³; worked out per particle, a
  /// drop of thirty would be slowed as thirty drops each a third its size.
  ///
  /// And what each drop loses to the air in [dt]: a sphere's evaporation,
  /// π·d·D·Δc·Sh, with Ranz and Marshall's Sherwood number
  /// 2 + 0.6·Re^½·Sc^⅓ for its speed through the air. Taken from its
  /// particles by their share, what is dissolved in them left behind.
  void _measureDrops(double dt, Atmosphere air) {
    final n = _x.length;
    final parent = List<int>.generate(n, (i) => i);
    int root(int i) {
      var r = i;
      while (parent[r] != r) {
        r = parent[r];
      }
      return parent[i] = r;
    }

    final grid = _Grid(h, _x);
    final touching = 2.25 * spacing * spacing;
    for (var i = 0; i < n; i++) {
      for (final j in grid.near(i, _x)) {
        if (_x[i].distance2(_x[j]) < touching) parent[root(i)] = root(j);
      }
    }
    final volume = <int, double>{};
    final speed = <int, _V>{};
    for (var i = 0; i < n; i++) {
      final r = root(i);
      volume[r] = (volume[r] ?? 0.0) + _vol[i];
      (speed[r] ??= _V(0, 0, 0)).addScaled(_v[i], _vol[i]);
    }
    _drop = Float64List(n);
    final deficit = air.vapourDeficit(medium);
    final d = air.vapourDiffusivity;
    final sc = air.viscosity / (air.density * d);
    final lost = <int, double>{};
    for (final MapEntry(key: r, value: v) in volume.entries) {
      final diameter = Portable.pow(6.0 * v / math.pi, 1.0 / 3.0);
      if (deficit > 0.0) {
        final u = speed[r]! * (1.0 / v);
        final wind = air.windAt(Vector3.zero());
        final through = _V(u.x - wind.x, u.y - wind.y, u.z - wind.z).length;
        final re = air.density * through * diameter / air.viscosity;
        final sherwood =
            2.0 + 0.6 * math.sqrt(re) * Portable.pow(sc, 1.0 / 3.0);
        final rate = math.pi * diameter * d * deficit * sherwood;
        lost[r] = math.min(rate / medium.density * dt, v) / v;
      }
      volume[r] = diameter;
    }
    for (var i = 0; i < n; i++) {
      final r = root(i);
      _drop[i] = volume[r]!;
      final share = lost[r];
      if (share != null && share > 0.0) {
        final gone = _vol[i] * share;
        _evaporated += gone;
        // What is dissolved stays: the same amount in less liquid.
        final kept = _vol[i] - gone;
        if (kept > 0.0) {
          _c[i] = {
            for (final e in _c[i].entries) e.key: e.value * _vol[i] / kept,
          };
        }
        _vol[i] = kept;
      }
    }
    // A drop dried away is gone.
    for (var i = n - 1; i >= 0; i--) {
      if (_vol[i] > 0.0) continue;
      _x.removeAt(i);
      _v.removeAt(i);
      _vol.removeAt(i);
      _c.removeAt(i);
    }
    if (_x.length != n) _drop = Float64List(0);
  }

  void _substep(double dt, _V gravity, List<JetObstacle> all) {
    final n = _x.length;
    // **Each particle's own walls**, found once a substep: those within what
    // it moves in one and two spacings more, which the density passes never
    // carry it past. Asked of every wall for every particle at every pass,
    // the profile of every glass on the bench was walked for drops that had
    // scattered across it, and thirty of them took most of a frame.
    final g = gravity.length;
    final walls = [
      for (var i = 0; i < n; i++)
        all.isEmpty
            ? all
            : obstaclesNear(
                all,
                _x[i].toVector3(),
                (_v[i].length + g * dt) * dt + 2.0 * spacing,
              ),
    ];
    // Where a particle starts inside a wall or under the floor, it is put
    // out first, its velocity left alone. A drop let go near the bottom of a
    // glass is laid out as a little block round where it parted, and a
    // particle of the block can start under the floor; put out by the
    // correction pass instead, its four millimetres became its velocity
    // over a fifth of a millisecond, and it left at eighteen metres a
    // second.
    for (var i = 0; i < n; i++) {
      _collide(_x[i], walls[i]);
    }
    // **What touches a wall is pinned to it.** A drop's edge on glass or
    // the bench holds where it is until something pushes harder than the
    // contact angle's hysteresis lets it, which nothing a millimetre drop
    // weighs does: a particle touching a wall at the start of the substep
    // moves only off it, or not at all. Left free along it, three
    // particles that came down on the bench rolled away over each other as
    // a wheel does, faster with every turn.
    final pinned = [for (var i = 0; i < n; i++) _contact(_x[i], walls[i])];
    // **Component by component, into buffers made once a substep.** The
    // loops over pairs below run tens of thousands of times a frame; with a
    // vector made for each difference, gradient and product, thirty drops
    // made hundreds of thousands of objects a frame, and the collector's
    // pauses were most of what a pour with drops cost.
    final rho0 = medium.density;
    final m = _mass;
    final norm = 1.0 / _latticeSum;
    // Forces first: gravity, cohesion and curvature, on the velocities.
    final grid = _Grid(h, _x);
    final neighbours = [for (var i = 0; i < n; i++) grid.near(i, _x)];
    final density = Float64List(n);
    for (var i = 0; i < n; i++) {
      var w = _poly6(0.0);
      for (final j in neighbours[i]) {
        w += _poly6(_x[i].distance2(_x[j]));
      }
      density[i] = rho0 * w * norm;
    }
    final normal = Float64List(3 * n);
    for (var i = 0; i < n; i++) {
      final xi = _x[i];
      var nx = 0.0;
      var ny = 0.0;
      var nz = 0.0;
      for (final j in neighbours[i]) {
        final xj = _x[j];
        final dx = xi.x - xj.x;
        final dy = xi.y - xj.y;
        final dz = xi.z - xj.z;
        final f =
            _spikyScale(math.sqrt(dx * dx + dy * dy + dz * dz)) *
            h *
            m /
            density[j];
        nx += dx * f;
        ny += dy * f;
        nz += dz * f;
      }
      normal[3 * i] = nx;
      normal[3 * i + 1] = ny;
      normal[3 * i + 2] = nz;
    }
    for (var i = 0; i < n; i++) {
      final xi = _x[i];
      var ax = gravity.x;
      var ay = gravity.y;
      var az = gravity.z;
      for (final j in neighbours[i]) {
        final xj = _x[j];
        final dx = xi.x - xj.x;
        final dy = xi.y - xj.y;
        final dz = xi.z - xj.z;
        final r = math.sqrt(dx * dx + dy * dy + dz * dz);
        if (r < 1e-12) continue;
        final k = 2.0 * rho0 / (density[i] + density[j]);
        final c = -k * _gamma * m * _cohesion(r) / r;
        final t = -k * _gamma;
        ax += dx * c + (normal[3 * i] - normal[3 * j]) * t;
        ay += dy * c + (normal[3 * i + 1] - normal[3 * j + 1]) * t;
        az += dz * c + (normal[3 * i + 2] - normal[3 * j + 2]) * t;
      }
      // The air, on the drop it is in: its drag over the drop's mass,
      // which every particle of it feels alike.
      final air = _air;
      if (air != null && i < _drop.length && _drop[i] > 0.0) {
        final drag = air.dragOnSphere(
          _v[i].toVector3(),
          xi.toVector3(),
          _drop[i],
          rho0,
        );
        ax += drag.x;
        ay += drag.y;
        az += drag.z;
      }
      _v[i]
        ..x += ax * dt
        ..y += ay * dt
        ..z += az * dt;
    }
    // Predict, then hold the density to the rest density.
    final p = [
      for (var i = 0; i < n; i++)
        if (pinned[i] case final wall?)
          _pin(_advance(_x[i], _v[i], dt, walls[i]), _x[i], wall)
        else
          _advance(_x[i], _v[i], dt, walls[i]),
    ];
    final lambda = Float64List(n);
    final grid2 = _Grid(h, p);
    final near = [for (var i = 0; i < n; i++) grid2.near(i, p)];
    final dq = 0.3 * h;
    final wq = _poly6(dq * dq);
    final delta = Float64List(3 * n);
    for (var it = 0; it < iterations; it++) {
      for (var i = 0; i < n; i++) {
        // C = ρ/ρ₀ − 1 with ρ/ρ₀ the kernel sum over the lattice's: only
        // where it is compressed. Both ways, a surface particle with half
        // its neighbours missing is pulled in by half a spacing a pass and
        // the liquid flies apart; a stretched surface is held by cohesion
        // instead.
        final pi = p[i];
        var w = _poly6(0.0);
        var sum2 = 0.0;
        var gx = 0.0;
        var gy = 0.0;
        var gz = 0.0;
        for (final j in near[i]) {
          final pj = p[j];
          final dx = pi.x - pj.x;
          final dy = pi.y - pj.y;
          final dz = pi.z - pj.z;
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
        lambda[i] = -c / (sum2 + 1e-6 * norm * norm / (h * h));
      }
      delta.fillRange(0, 3 * n, 0.0);
      for (var i = 0; i < n; i++) {
        final pi = p[i];
        for (final j in near[i]) {
          final pj = p[j];
          final dx = pi.x - pj.x;
          final dy = pi.y - pj.y;
          final dz = pi.z - pj.z;
          final r2 = dx * dx + dy * dy + dz * dz;
          final ratio = _poly6(r2) / wq;
          // Macklin's artificial pressure, which keeps neighbours from
          // clumping: a fiftieth of a constraint's worth. At his tenth it
          // held still water a sixth thinner than its rest density.
          final corr = -0.02 * ratio * ratio * ratio * ratio / _restStiffness;
          // Δpᵢ = Σⱼ (λᵢ + λⱼ + s_corr) ∇W(pᵢ − pⱼ), in the same
          // normalisation as the constraint.
          final f =
              _spikyScale(math.sqrt(r2)) *
              (lambda[i] + lambda[j] + corr) *
              norm;
          delta[3 * i] += dx * f;
          delta[3 * i + 1] += dy * f;
          delta[3 * i + 2] += dz * f;
        }
      }
      for (var i = 0; i < n; i++) {
        p[i]
          ..x += delta[3 * i]
          ..y += delta[3 * i + 1]
          ..z += delta[3 * i + 2];
        _collide(p[i], walls[i]);
        if (pinned[i] case final wall?) _pin(p[i], _x[i], wall);
      }
    }
    // Velocities from the move, then XSPH's viscosity.
    final inverse = 1.0 / dt;
    for (var i = 0; i < n; i++) {
      _v[i]
        ..x = (p[i].x - _x[i].x) * inverse
        ..y = (p[i].y - _x[i].y) * inverse
        ..z = (p[i].z - _x[i].z) * inverse;
    }
    final share = math.min(
      0.5,
      medium.kinematicViscosity * dt / (spacing * spacing) * 50.0 + 0.01,
    );
    final smoothed = Float64List(3 * n);
    for (var i = 0; i < n; i++) {
      final vi = _v[i];
      var sx = vi.x;
      var sy = vi.y;
      var sz = vi.z;
      for (final j in near[i]) {
        final w = _poly6(p[i].distance2(p[j])) * norm * share;
        final vj = _v[j];
        sx += (vj.x - vi.x) * w;
        sy += (vj.y - vi.y) * w;
        sz += (vj.z - vi.z) * w;
      }
      smoothed[3 * i] = sx;
      smoothed[3 * i + 1] = sy;
      smoothed[3 * i + 2] = sz;
    }
    // A viscous liquid's velocity at a wall at rest is nil along it, and
    // nothing goes on into it: what touches one keeps only the part of its
    // velocity that leaves. Left its speed along the wall, a drop that fell
    // on the bench slid off at five centimetres a second and never
    // stopped, and ended up under another glass's foot, looking as if it
    // were inside.
    final onWall = List<bool>.filled(n, false);
    for (var i = 0; i < n; i++) {
      final v = _v[i]
        ..x = smoothed[3 * i]
        ..y = smoothed[3 * i + 1]
        ..z = smoothed[3 * i + 2];
      final wall = _contact(p[i], walls[i]);
      onWall[i] = wall != null;
      if (wall != null) {
        final off = math.max(_dot(v, wall), 0.0);
        v
          ..x = wall.x * off
          ..y = wall.y * off
          ..z = wall.z * off;
      }
      _x[i] = p[i];
    }
    _holdSmallDrops(near, onWall, gravity);
  }

  /// **A drop smaller than the capillary length, pinned, stands still.**
  /// Under ℓc = √(σ/ρg), 2.7 mm for water, surface tension holds a drop's
  /// shape against its weight, and what of it touches a wall is pinned:
  /// it stays as a whole where it is. Pinning only the particles that touch
  /// let the others turn over them, and a three-particle drop on the bench
  /// rolled away; a puddle wider than ℓc still spreads.
  void _holdSmallDrops(List<List<int>> near, List<bool> onWall, _V gravity) {
    final n = _x.length;
    final g = gravity.length;
    if (n == 0 || g <= 0.0 || medium.surfaceTension <= 0.0) return;
    final capillary = math.sqrt(medium.surfaceTension / (medium.density * g));
    final parent = List<int>.generate(n, (i) => i);
    int root(int i) {
      var r = i;
      while (parent[r] != r) {
        r = parent[r];
      }
      return parent[i] = r;
    }

    // One drop: particles nearer each other than a spacing and a half.
    final touching = 2.25 * spacing * spacing;
    for (var i = 0; i < n; i++) {
      for (final j in near[i]) {
        if (_x[i].distance2(_x[j]) < touching) parent[root(i)] = root(j);
      }
    }
    final low = <int, _V>{};
    final high = <int, _V>{};
    final held = <int>{};
    for (var i = 0; i < n; i++) {
      final r = root(i);
      final p = _x[i];
      final lo = low[r] ??= p.copy();
      final hi = high[r] ??= p.copy();
      lo
        ..x = math.min(lo.x, p.x)
        ..y = math.min(lo.y, p.y)
        ..z = math.min(lo.z, p.z);
      hi
        ..x = math.max(hi.x, p.x)
        ..y = math.max(hi.y, p.y)
        ..z = math.max(hi.z, p.z);
      if (onWall[i]) held.add(r);
    }
    for (var i = 0; i < n; i++) {
      final r = root(i);
      if (!held.contains(r)) continue;
      // Across it, a particle's width beyond the centres.
      if ((high[r]! - low[r]!).length + spacing < capillary) {
        _v[i] = _V(0, 0, 0);
      }
    }
  }

  /// The normal of the wall [p] touches, if it touches one. Put out a
  /// radius from a wall, a particle touches it at a radius and a little.
  _V? _contact(_V p, List<JetObstacle> obstacles) {
    final reach = 0.55 * spacing;
    for (final o in obstacles) {
      final hit = o.touch(p.toVector3(), reach);
      if (hit != null) return _V(hit.normal.x, hit.normal.y, hit.normal.z);
    }
    return null;
  }

  /// [p] moved back to where [from] was along the wall of normal [n]: off
  /// it is the only way it goes.
  _V _pin(_V p, _V from, _V n) {
    final off = math.max(_dot(p - from, n), 0.0);
    p
      ..x = from.x + n.x * off
      ..y = from.y + n.y * off
      ..z = from.z + n.z * off;
    return p;
  }

  static double _dot(_V a, _V b) => a.x * b.x + a.y * b.y + a.z * b.z;

  /// Where [x] moving at [v] is after [dt]: moved in pieces of two fifths
  /// of a spacing, put out of the walls after each. A wall holds what comes
  /// within a radius of it or half its thickness into it, a band wider than
  /// a piece, so nothing passes through glass thinner than a particle; a
  /// drop falling a metre a second into a test tube went five millimetres a
  /// step and through its bottom.
  _V _advance(_V x, _V v, double dt, List<JetObstacle> obstacles) {
    final p = x.copy();
    final pieces = obstacles.isEmpty
        ? 1
        : (v.length * dt / (0.4 * spacing)).ceil().clamp(1, 64);
    for (var k = 0; k < pieces; k++) {
      p.addScaled(v, dt / pieces);
      if (pieces > 1) _collide(p, obstacles);
    }
    return p;
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

  /// What a difference d of length [r] is scaled by to be the spiky
  /// kernel's gradient: ∇W = d·f(r).
  double _spikyScale(double r) {
    if (r <= 1e-12 || r >= h) return 0.0;
    return -45.0 / (math.pi * _pow6(h)) * (h - r) * (h - r) / r;
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

  /// By multiplication, as `spatial_grid.dart` does, and not by shifting
  /// into the high bits: on the web an int's bitwise operations are 32 bits
  /// wide, `x << 42` kept almost nothing of `x`, cells far apart shared a
  /// key, a particle met the same neighbour several times over, and the
  /// liquid read as many times its density and flew apart. Each index is
  /// held to ±2¹⁶ cells and the key under 2⁵¹, which a double holds exactly.
  static int _pack(int x, int y, int z) {
    const span = 1 << 17;
    const half = 1 << 16;
    int wrap(int v) => (v + half) % span;
    return (wrap(x) * span + wrap(y)) * span + wrap(z);
  }

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
