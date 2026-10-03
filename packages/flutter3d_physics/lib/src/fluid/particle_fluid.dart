import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import '../portable_math.dart';
import 'atmosphere.dart';
import 'fluid_medium.dart';
import 'jet.dart';
import 'native/pbf_backend.dart';
import 'pbf_kernels.dart';
import 'wetting.dart';

/// A flat surface particles rest on — a bench, a floor: the points with
/// `normal · p ≥ offset` are clear of it.
final class PlaneObstacle implements JetObstacle {
  PlaneObstacle({
    required Vector3 normal,
    required this.offset,
    this.solid = SolidSurface.glass,
  }) : normal = normal.normalized();

  @override
  final SolidSurface solid;

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
    this.native = false,
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

  /// Where the liquid is: each particle's place, then each drop's middle.
  List<Vector3> get positions => [
    for (final p in _x) p.toVector3(),
    for (final d in _drops) d.x.toVector3(),
  ];

  /// How many places [positions] has: particles and drops.
  int get count => _x.length + _drops.length;

  /// How many of them are drops, each one body: the rest are particles.
  int get dropCount => _drops.length;

  /// Cubic metres here: every particle, every drop and the bank.
  double get volume =>
      _vol.fold(0.0, (s, v) => s + v) +
      _drops.fold(0.0, (s, d) => s + d.volume) +
      _bank;

  /// The liquid at each of [positions], cubic metres.
  List<double> get volumes =>
      List.unmodifiable([..._vol, for (final d in _drops) d.volume]);

  /// What is dissolved in the particles and drops, as concentrations over
  /// all of them: for drawing them the colour of what they are.
  Map<String, double> get concentrations {
    final all = [..._c, for (final d in _drops) d.c];
    if (all.isEmpty) return const {};
    final sum = <String, double>{};
    for (final c in all) {
      c.forEach((k, v) => sum[k] = (sum[k] ?? 0.0) + v);
    }
    return {for (final e in sum.entries) e.key: e.value / all.length};
  }

  /// **A drop in flight is one body.** Falling, it does not feel its own
  /// weight, and what would break it up is the air: it holds together while
  /// its aerodynamic Weber number ρ_a·u²·d/σ is under about twelve (Pilch
  /// and Erdman, 1987), and a four-millimetre drop at a metre a second is at
  /// a fifteenth of one. So it moves as one, its drag a sphere's, its
  /// evaporation a sphere's, its hold on a wall Furmidge's. Laid out as
  /// particles it was dozens of bodies stepped at the capillary time,
  /// which were most of what a pour cost; and a block of them, free in the
  /// air, rang until it flew apart.
  ///
  /// Particles are for liquid on a wall: a block that lands on glass is
  /// particles; one that leaves the wall again is a drop.
  final List<_Drop> _drops = [];

  /// The air last flown through, for the Weber number at [inject].
  Atmosphere? _lastAir;

  /// The critical aerodynamic Weber number.
  static const double _breakupWeber = 12.0;

  bool _isDrop(double volume, Vector3 position, Vector3 velocity) {
    if (volume <= 0.0 || medium.surfaceTension <= 0.0) return false;
    final air = _lastAir;
    if (air == null) return true;
    final d = Portable.pow(6.0 * volume / math.pi, 1.0 / 3.0);
    final u = velocity - air.windAt(position);
    return air.density * u.length2 * d / medium.surfaceTension < _breakupWeber;
  }

  /// Cubic metres handed to receivers so far.
  double get received => _received;

  /// Adds [amount] cubic metres at [position] moving at [velocity], with
  /// [concentrations] dissolved in it: as many whole particles as it and
  /// the bank make, laid out round [position] at the spacing so none start
  /// on top of another, each carrying what the bank holds per cubic metre.
  ///
  /// Less than a drop of the capillary length is one drop, of exactly
  /// [amount]: see [dropCount].
  ///
  /// [asParticles] lays it out as particles whatever it is: for liquid put
  /// straight onto a wall.
  void inject(
    double amount,
    Vector3 position,
    Vector3 velocity, {
    Map<String, double> concentrations = const {},
    bool asParticles = false,
  }) {
    if (!asParticles && _isDrop(amount, position, velocity)) {
      _drops.add(
        _Drop(
          _V(position.x, position.y, position.z),
          _V(velocity.x, velocity.y, velocity.z),
          amount,
          Map.of(concentrations),
        ),
      );
      return;
    }
    _addToParticles(amount, position, velocity, concentrations);
  }

  void _addToParticles(
    double amount,
    Vector3 position,
    Vector3 velocity,
    Map<String, double> concentrations,
  ) {
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
    Vector3 Function(Vector3 point)? gravityAt,
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
    if (air != null) _lastAir = air;
    _stepDrops(dt, gravity, obstacles, receivers, air, gravityAt);
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
    _gravityAt = gravityAt;
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
        if (!r.reaches(at, radius)) continue;
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
    _clustersToDrops(walls);
  }

  /// Each drop moved on by [dt]: the air's drag and evaporation, a wall
  /// holding it or letting it slide, the walls it meets, the receivers it
  /// reaches; drops that touch run together, and a drop that touches the
  /// particles or outgrows the capillary length becomes particles.
  void _stepDrops(
    double dt,
    Vector3 gravity,
    List<JetObstacle> obstacles,
    List<JetReceiver> receivers,
    Atmosphere? air,
    Vector3 Function(Vector3 point)? gravityAt,
  ) {
    if (_drops.isEmpty) return;
    _mergeDrops();
    // Into the particles it touches.
    for (var i = _drops.length - 1; i >= 0; i--) {
      final d = _drops[i];
      final reach = d.radius + 0.5 * spacing;
      var touches = false;
      for (var j = 0; j < _x.length && !touches; j++) {
        touches = _x[j].distance2(d.x) < reach * reach;
      }
      if (!touches) continue;
      _drops.removeAt(i);
      _addToParticles(d.volume, d.x.toVector3(), d.v.toVector3(), d.c);
    }
    final rho = medium.density;
    for (var i = _drops.length - 1; i >= 0; i--) {
      final d = _drops[i];
      final at = d.x.toVector3();
      final g = gravityAt?.call(at) ?? gravity;
      final r = d.radius;
      var ax = g.x;
      var ay = g.y;
      var az = g.z;
      if (air != null) {
        final drag = air.dragOnSphere(d.v.toVector3(), at, 2.0 * r, rho);
        ax += drag.x;
        ay += drag.y;
        az += drag.z;
        _evaporate(d, dt, air);
        if (d.volume <= 0.0) {
          _drops.removeAt(i);
          continue;
        }
      }
      final walls = obstaclesNear(
        obstacles,
        at,
        (d.v.length + g.length * dt) * dt + 2.0 * r,
      );
      // On a wall: held whole by its edge, or sliding with what of its
      // weight along the wall the edge cannot hold. Wider than the
      // capillary length, where its weight flattens it, it spreads there
      // as particles.
      final touch = _touchingDrop(d, walls);
      if (touch != null &&
          2.0 * r > medium.capillaryLength(math.max(g.length, 1e-9))) {
        _drops.removeAt(i);
        _addToParticles(d.volume, at, d.v.toVector3(), d.c);
        continue;
      }
      if (touch != null) {
        final n = touch.normal;
        final into = g.x * n.x + g.y * n.y + g.z * n.z;
        final gx = g.x - n.x * into;
        final gy = g.y - n.y * into;
        final gz = g.z - n.z * into;
        final along = math.sqrt(gx * gx + gy * gy + gz * gz);
        final mass = rho * d.volume;
        final hold = touch.solid.retention(
          medium,
          2.0 * touch.solid.baseRadius(medium, d.volume),
        );
        if (mass * along <= hold || along <= 0.0) {
          d.v
            ..x = 0.0
            ..y = 0.0
            ..z = 0.0;
        } else {
          final k = 1.0 - hold / (mass * along);
          d.v
            ..x += gx * k * dt
            ..y += gy * k * dt
            ..z += gz * k * dt;
          final off = _dot(d.v, n);
          if (off < 0.0) {
            d.v
              ..x -= n.x * off
              ..y -= n.y * off
              ..z -= n.z * off;
          }
        }
      } else {
        d.v
          ..x += ax * dt
          ..y += ay * dt
          ..z += az * dt;
      }
      // In pieces no longer than its radius, held out of the walls after
      // each: what meets a wall loses the part of its speed into it.
      final pieces = (d.v.length * dt / r).ceil().clamp(1, 64);
      for (var k = 0; k < pieces; k++) {
        d.x.addScaled(d.v, dt / pieces);
        for (final o in walls) {
          final hit = o.touch(d.x.toVector3(), r);
          if (hit == null) continue;
          d.x
            ..x += hit.normal.x * hit.depth
            ..y += hit.normal.y * hit.depth
            ..z += hit.normal.z * hit.depth;
          final off =
              d.v.x * hit.normal.x +
              d.v.y * hit.normal.y +
              d.v.z * hit.normal.z;
          if (off < 0.0) {
            d.v
              ..x -= hit.normal.x * off
              ..y -= hit.normal.y * off
              ..z -= hit.normal.z * off;
          }
        }
      }
      final now = d.x.toVector3();
      for (final receiver in receivers) {
        if (!receiver.reaches(now, r)) continue;
        if (!receiver.catches(now, r) && !receiver.wets(now, r)) continue;
        receiver.receive(d.volume, now, d.v.toVector3(), medium, d.c);
        _received += d.volume;
        _drops.removeAt(i);
        break;
      }
    }
  }

  /// The wall [d] touches and its normal and solid there, if any.
  ({_V normal, SolidSurface solid})? _touchingDrop(
    _Drop d,
    List<JetObstacle> walls,
  ) {
    final reach = d.radius * 1.05;
    final at = d.x.toVector3();
    for (final o in walls) {
      final hit = o.touch(at, reach);
      if (hit != null) {
        return (
          normal: _V(hit.normal.x, hit.normal.y, hit.normal.z),
          solid: o.solid,
        );
      }
    }
    return null;
  }

  /// Drops that touch run together: their liquid, momentum and what is
  /// dissolved, into one at their centre of volume.
  void _mergeDrops() {
    var merged = true;
    while (merged) {
      merged = false;
      outer:
      for (var i = 0; i < _drops.length; i++) {
        for (var j = i + 1; j < _drops.length; j++) {
          final a = _drops[i];
          final b = _drops[j];
          final reach = a.radius + b.radius;
          if (a.x.distance2(b.x) >= reach * reach) continue;
          final total = a.volume + b.volume;
          final wa = a.volume / total;
          final wb = b.volume / total;
          a.x
            ..x = a.x.x * wa + b.x.x * wb
            ..y = a.x.y * wa + b.x.y * wb
            ..z = a.x.z * wa + b.x.z * wb;
          a.v
            ..x = a.v.x * wa + b.v.x * wb
            ..y = a.v.y * wa + b.v.y * wb
            ..z = a.v.z * wa + b.v.z * wb;
          a.c = {
            for (final k in {...a.c.keys, ...b.c.keys})
              k: (a.c[k] ?? 0.0) * wa + (b.c[k] ?? 0.0) * wb,
          };
          a.volume = total;
          _drops.removeAt(j);
          merged = true;
          break outer;
        }
      }
    }
  }

  /// A drop's evaporation in [dt]: a sphere's, π·d·D·Δc·Sh with Ranz and
  /// Marshall's Sherwood number, what is dissolved left behind.
  void _evaporate(_Drop d, double dt, Atmosphere air) {
    final deficit = air.vapourDeficit(medium);
    if (deficit <= 0.0) return;
    final diffusivity = air.vapourDiffusivity;
    final diameter = 2.0 * d.radius;
    final wind = air.windAt(d.x.toVector3());
    final through = _V(d.v.x - wind.x, d.v.y - wind.y, d.v.z - wind.z).length;
    final re = air.density * through * diameter / air.viscosity;
    final sc = air.viscosity / (air.density * diffusivity);
    final sherwood = 2.0 + 0.6 * math.sqrt(re) * Portable.pow(sc, 1.0 / 3.0);
    final rate = math.pi * diameter * diffusivity * deficit * sherwood;
    final gone = math.min(rate / medium.density * dt, d.volume);
    _evaporated += gone;
    final kept = d.volume - gone;
    if (kept > 0.0) {
      d.c = {for (final e in d.c.entries) e.key: e.value * d.volume / kept};
    }
    d.volume = kept;
  }

  /// For each particle, the drop it is in, by the particle that stands for
  /// the drop: particles nearer each other than a spacing and a half are
  /// one, through any chain of them.
  ///
  /// **Each step on the way halved.** Which particle stands for a drop is
  /// set by the joins alone, so shortcuts taken on the way change none;
  /// walked to the end each time, a block of five hundred on a pane made
  /// chains hundreds long, and finding the drops was a sixth of a step.
  Int32List _dropRoots(Int32List start, Int32List list) {
    final n = _x.length;
    final parent = Int32List.fromList([for (var i = 0; i < n; i++) i]);
    int root(int i) {
      var r = i;
      while (parent[r] != r) {
        parent[r] = parent[parent[r]];
        r = parent[r];
      }
      return r;
    }

    final close = 2.25 * spacing * spacing;
    for (var i = 0; i < n; i++) {
      for (var q = start[i]; q < start[i + 1]; q++) {
        final j = list[q];
        if (_x[i].distance2(_x[j]) < close) parent[root(i)] = root(j);
      }
    }
    return Int32List.fromList([for (var i = 0; i < n; i++) root(i)]);
  }

  /// Particles gathered into a drop, a spacing and a half apart at most,
  /// that touch no wall, become that drop: one body again, in flight.
  void _clustersToDrops(List<JetObstacle> walls) {
    final n = _x.length;
    if (n == 0 || medium.surfaceTension <= 0.0) return;
    final (start, list) = _rows(_x);
    final roots = _dropRoots(start, list);
    final volume = <int, double>{};
    final speed = <int, _V>{};
    final onWall = <int>{};
    for (var i = 0; i < n; i++) {
      final r = roots[i];
      volume[r] = (volume[r] ?? 0.0) + _vol[i];
      (speed[r] ??= _V(0, 0, 0)).addScaled(_v[i], _vol[i]);
      final near = obstaclesNear(walls, _x[i].toVector3(), spacing);
      if (_contact(_x[i], near) != null) onWall.add(r);
    }
    final into = <int, _Drop>{};
    for (final MapEntry(key: r, value: v) in volume.entries) {
      if (onWall.contains(r)) continue;
      final at = _x[r].toVector3();
      if (_isDrop(v, at, (speed[r]! * (1.0 / v)).toVector3())) {
        into[r] = _Drop(_V(0, 0, 0), _V(0, 0, 0), 0.0, {});
      }
    }
    if (into.isEmpty) return;
    for (var i = n - 1; i >= 0; i--) {
      final d = into[roots[i]];
      if (d == null) continue;
      final w = _vol[i];
      final total = d.volume + w;
      final a = d.volume / total;
      final b = w / total;
      d.x
        ..x = d.x.x * a + _x[i].x * b
        ..y = d.x.y * a + _x[i].y * b
        ..z = d.x.z * a + _x[i].z * b;
      d.v
        ..x = d.v.x * a + _v[i].x * b
        ..y = d.v.y * a + _v[i].y * b
        ..z = d.v.z * a + _v[i].z * b;
      d.c = {
        for (final k in {...d.c.keys, ..._c[i].keys})
          k: (d.c[k] ?? 0.0) * a + (_c[i][k] ?? 0.0) * b,
      };
      d.volume = total;
      _x.removeAt(i);
      _v.removeAt(i);
      _vol.removeAt(i);
      _c.removeAt(i);
    }
    _drops.addAll(into.values);
  }

  /// Whether to run the loops over pairs natively where that was built
  /// ([nativePbfAvailable]): several times as fast, and the same to within
  /// a tolerance rather than to the bit, so not for a world that must
  /// replay exactly.
  final bool native;

  /// What runs the loops over pairs: the Dart reference, or the native
  /// kernels when [native] asks for them and they are there.
  late PbfKernels kernels = () {
    final k = PbfConstants(
      h: h,
      restDensity: medium.density,
      mass: _mass,
      norm: 1.0 / _latticeSum,
      gamma: _gamma,
      restStiffness: _restStiffness,
    );
    return (native ? nativePbfKernels(k) : null) ?? DartPbfKernels(k);
  }();

  /// [points] as one flat buffer of x, y, z in turn.
  static Float64List _flat(List<_V> points) {
    final out = Float64List(3 * points.length);
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      out[3 * i] = p.x;
      out[3 * i + 1] = p.y;
      out[3 * i + 2] = p.z;
    }
    return out;
  }

  /// [flat] back into [points].
  static void _unflat(Float64List flat, List<_V> points) {
    for (var i = 0; i < points.length; i++) {
      points[i]
        ..x = flat[3 * i]
        ..y = flat[3 * i + 1]
        ..z = flat[3 * i + 2];
    }
  }

  /// The neighbours of each of [points] within the kernel's reach, as
  /// compressed rows: [PbfKernels]' layout.
  ///
  /// Searched afresh each time. Candidates kept from one search to the next
  /// (Verlet's list, half the reach again) were measured and cost more
  /// here: drops landing while others still fall move apart faster than
  /// any skin outlasts, and the wider search came round nearly every time.
  (Int32List, Int32List) _rows(List<_V> points) =>
      kernels.neighbours(_flat(points), points.length, h);

  /// The air the particles are being stepped through, and each particle's
  /// drop's diameter: set at the start of a step, read by its substeps.
  Atmosphere? _air;
  Float64List _drop = Float64List(0);

  /// The gravity at a point, when it is not one vector everywhere.
  Vector3 Function(Vector3 point)? _gravityAt;

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
    final (start, list) = _rows(_x);
    final roots = _dropRoots(start, list);
    final volume = <int, double>{};
    final speed = <int, _V>{};
    for (var i = 0; i < n; i++) {
      final r = roots[i];
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
      final r = roots[i];
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
    //
    // **Unless the drop's weight along the wall is more than its edge can
    // hold**, by Furmidge's σ·w·(cos θr − cos θa): then it slides, its
    // particles kept out of the wall and free along it.
    // The neighbours at these places, found once: for which drop each
    // particle is in, and for the forces.
    final (start, list) = _rows(_x);
    final touching = [for (var i = 0; i < n; i++) _touching(_x[i], walls[i])];
    final held = _held(touching, gravity, start, list);
    final pinned = [
      for (var i = 0; i < n; i++) held[i] ? touching[i]?.normal : null,
    ];
    // **Component by component, into buffers made once a substep.** The
    // loops over pairs below run tens of thousands of times a frame; with a
    // vector made for each difference, gradient and product, thirty drops
    // made hundreds of thousands of objects a frame, and the collector's
    // pauses were most of what a pour with drops cost.
    // **The loops over pairs, by [kernels]**, over flat buffers: positions
    // and velocities copied out of the particles before each call and back
    // after, a few hundred numbers against the tens of thousands of pair
    // terms the call works through.
    final rho0 = medium.density;
    final ker = kernels;
    // Forces first: gravity, cohesion and curvature, on the velocities.
    final xs = _flat(_x);
    final vs = _flat(_v);
    final density = Float64List(n);
    ker.densities(xs, start, list, n, density);
    final normal = Float64List(3 * n);
    ker.normals(xs, start, list, n, density, normal);
    final before = Float64List(3 * n);
    final after = Float64List(3 * n);
    final air = _air;
    for (var i = 0; i < n; i++) {
      final here = _gravityAt?.call(_x[i].toVector3());
      before[3 * i] = here?.x ?? gravity.x;
      before[3 * i + 1] = here?.y ?? gravity.y;
      before[3 * i + 2] = here?.z ?? gravity.z;
      // The air, on the drop it is in: its drag over the drop's mass,
      // which every particle of it feels alike.
      if (air != null && i < _drop.length && _drop[i] > 0.0) {
        final drag = air.dragOnSphere(
          _v[i].toVector3(),
          _x[i].toVector3(),
          _drop[i],
          rho0,
        );
        after[3 * i] = drag.x;
        after[3 * i + 1] = drag.y;
        after[3 * i + 2] = drag.z;
      }
    }
    ker.forces(xs, start, list, n, density, normal, before, after, vs, dt);
    _unflat(vs, _v);
    // Predict, then hold the density to the rest density.
    final p = [
      for (var i = 0; i < n; i++)
        if (pinned[i] case final wall?)
          _pin(_advance(_x[i], _v[i], dt, walls[i]), _x[i], wall)
        else
          _advance(_x[i], _v[i], dt, walls[i]),
    ];
    final lambda = Float64List(n);
    final (near, rows) = _rows(p);
    final delta = Float64List(3 * n);
    for (var it = 0; it < iterations; it++) {
      // C = ρ/ρ₀ − 1, only where it is compressed: see [PbfKernels].
      final ps = _flat(p);
      ker
        ..lambdas(ps, near, rows, n, lambda)
        ..deltas(ps, near, rows, n, lambda, delta);
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
    ker.viscosity(_flat(p), _flat(_v), near, rows, n, share, smoothed);
    // A viscous liquid's velocity at a wall at rest is nil along it, and
    // nothing goes on into it: what touches one keeps only the part of its
    // velocity that leaves. Left its speed along the wall, a drop that fell
    // on the bench slid off at five centimetres a second and never
    // stopped, and ended up under another glass's foot, looking as if it
    // were inside.
    // A drop that slides keeps only out of the wall.
    for (var i = 0; i < n; i++) {
      final v = _v[i]
        ..x = smoothed[3 * i]
        ..y = smoothed[3 * i + 1]
        ..z = smoothed[3 * i + 2];
      final wall = _contact(p[i], walls[i]);
      if (wall != null) {
        final into = _dot(v, wall);
        if (held[i]) {
          final off = math.max(into, 0.0);
          v
            ..x = wall.x * off
            ..y = wall.y * off
            ..z = wall.z * off;
        } else if (into < 0.0) {
          v
            ..x -= wall.x * into
            ..y -= wall.y * into
            ..z -= wall.z * into;
        }
      }
      // A drop its edge holds stands still, as a whole: pinning only the
      // particles that touch let the others turn over them, and a drop of
      // three on the bench rolled away.
      if (held[i]) {
        v
          ..x = 0.0
          ..y = 0.0
          ..z = 0.0;
      }
      _x[i] = p[i];
    }
  }

  /// The wall [p] touches and its normal there, if it touches one.
  ({_V normal, JetObstacle wall})? _touching(_V p, List<JetObstacle> walls) {
    final reach = 0.55 * spacing;
    for (final o in walls) {
      final hit = o.touch(p.toVector3(), reach);
      if (hit != null) {
        return (normal: _V(hit.normal.x, hit.normal.y, hit.normal.z), wall: o);
      }
    }
    return null;
  }

  /// For each particle, whether the drop it is in is held where it is by
  /// the wall it touches: its weight along the wall, ρ·V·g∥, no more than
  /// the wall's [SolidSurface.retention] across the circle a drop of its
  /// volume wets. Held, a drop stands still; on a level bench every drop
  /// is, its weight being all into the bench.
  List<bool> _held(
    List<({_V normal, JetObstacle wall})?> touching,
    _V gravity,
    Int32List start,
    Int32List list,
  ) {
    final n = _x.length;
    final out = List<bool>.filled(n, false);
    if (n == 0 || medium.surfaceTension <= 0.0) return out;
    final dropOf = _dropRoots(start, list);
    // By root, in arrays: summed in the particles' order, as before.
    final volume = Float64List(n);
    final normal = Float64List(3 * n);
    final solid = List<SolidSurface?>.filled(n, null);
    for (var i = 0; i < n; i++) {
      final r = dropOf[i];
      volume[r] += _vol[i];
      final t = touching[i];
      if (t == null) continue;
      normal[3 * r] += t.normal.x;
      normal[3 * r + 1] += t.normal.y;
      normal[3 * r + 2] += t.normal.z;
      solid[r] ??= t.wall.solid;
    }
    final holds = List<bool>.filled(n, false);
    for (var r = 0; r < n; r++) {
      final surface = solid[r];
      if (surface == null) continue;
      final sum = _V(normal[3 * r], normal[3 * r + 1], normal[3 * r + 2]);
      final length = sum.length;
      if (length <= 0.0) continue;
      final nx = sum.x / length;
      final ny = sum.y / length;
      final nz = sum.z / length;
      final at = _gravityAt?.call(_x[r].toVector3());
      final g = at == null ? gravity : _V(at.x, at.y, at.z);
      final into = g.x * nx + g.y * ny + g.z * nz;
      final along = math.sqrt(math.max(g.length2 - into * into, 0.0));
      final v = volume[r];
      final weight = medium.density * v * along;
      final width = 2.0 * surface.baseRadius(medium, v);
      if (weight <= surface.retention(medium, width)) holds[r] = true;
    }
    for (var i = 0; i < n; i++) {
      out[i] = holds[dropOf[i]];
    }
    return out;
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

/// A drop small enough to be one body: where, how fast, how much, and
/// what is dissolved in it.
final class _Drop {
  _Drop(this.x, this.v, this.volume, this.c);

  final _V x;
  final _V v;
  double volume;
  Map<String, double> c;

  /// The radius of the sphere it is.
  double get radius => Portable.pow(3.0 * volume / (4.0 * math.pi), 1.0 / 3.0);
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
