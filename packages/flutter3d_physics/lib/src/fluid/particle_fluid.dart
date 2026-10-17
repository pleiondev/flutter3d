import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_matter/flutter3d_matter.dart' show standardGravity;
import 'package:vector_math/vector_math.dart';

import 'fluid_air.dart';
import 'fluid_medium.dart';
import 'fluid_solver.dart';
import 'jet.dart';
import 'wetting.dart';

/// A flat surface particles rest on — a bench, a floor: the points with
/// `normal · p ≥ offset` are clear of it.
final class PlaneObstacle with JetObstacle {
  /// The plane facing [normal] at [offset] metres from the origin along it,
  /// made of [surface] (the liquid's own angle, as on glass, when null).
  PlaneObstacle({required Vector3 normal, required this.offset, this.surface})
    : normal = normal.normalized();

  final Vector3 normal;

  /// The plane's distance from the origin along [normal], in metres.
  final double offset;

  /// What the plane is made of: a phenolic bench top
  /// ([SolidSurface.benchTop]) beads water that glass spreads.
  @override
  final SolidSurface? surface;

  @override
  bool reaches(Vector3 center, double distance) =>
      normal.dot(center) - offset < distance;

  @override
  ObstacleTouch? touch(Vector3 point, double radius) {
    final d = normal.dot(point) - offset - radius;
    return d < 0.0 ? ObstacleTouch(normal: normal, depth: -d) : null;
  }
}

/// Particles [ParticleFluid.retire] took out: where each was, and what they
/// carried between them.
final class RetiredParticles {
  RetiredParticles({
    required this.positions,
    required this.particleVolume,
    this.amounts = const {},
    this.drops = const <LiquidDrop>[],
  });

  /// None taken out.
  static final RetiredParticles none = RetiredParticles(
    positions: const [],
    particleVolume: 0.0,
  );

  /// Where each particle was when it was taken out.
  final List<Vector3> positions;

  /// How much liquid each one was, in cubic metres.
  final double particleVolume;

  /// How much of each solute they carried between them, the [drops]
  /// included: each one's concentration times its volume, summed. Over
  /// [volume], their mixture's concentrations.
  final Map<String, double> amounts;

  /// The drops taken out with them, each its own volume
  /// ([ParticleFluid.drops]): a drop come to rest on a floor is taken out
  /// as the particles lying there are.
  final List<LiquidDrop> drops;

  /// Cubic metres taken out: every particle and every drop.
  double get volume =>
      positions.length * particleVolume +
      drops.fold(0.0, (s, d) => s + d.volume);

  /// Whether none were taken out.
  bool get isEmpty => positions.isEmpty && drops.isEmpty;
}

/// One drop of a [ParticleFluid], as one body: where it is, how fast it
/// goes, how much it holds and what is dissolved in it.
///
/// **A class, not a record**, so a field a later minor adds (a
/// temperature, the wall it hangs on) breaks no code that reads one.
final class LiquidDrop {
  /// A drop of [volume] cubic metres at [position] moving at [velocity],
  /// carrying [concentrations].
  const LiquidDrop({
    required this.position,
    required this.velocity,
    required this.volume,
    this.concentrations = const <String, double>{},
  });

  /// Its middle, in the world.
  final Vector3 position;

  /// How fast it goes, m/s.
  final Vector3 velocity;

  /// How much liquid it is, in cubic metres.
  final double volume;

  /// What is dissolved in it, by species.
  final Map<String, double> concentrations;

  /// Its radius as a sphere, in metres.
  double get radius => Portable.pow(3.0 * volume / (4.0 * math.pi), 1.0 / 3.0);
}

/// A drop's state as [ParticleFluid] keeps it, in double precision.
final class _Drop {
  _Drop(this.x, this.v, this.volume, this.c);

  /// Its middle, in metres, and its velocity, in metres per second.
  _V x;
  _V v;

  /// How much liquid it is, in cubic metres.
  double volume;

  /// What is dissolved in it, by species.
  Map<String, double> c;

  /// How long `ParticleFluid.retire`'s test has held of it, seconds.
  double settled = 0.0;

  /// Its radius as a sphere, in metres.
  double get radius => Portable.pow(3.0 * volume / (4.0 * math.pi), 1.0 / 3.0);

  /// [w] cubic metres at [at] moving at [u] carrying [carried], taken in:
  /// the middle, the velocity and the concentrations weighed by volume.
  void absorb(_V at, _V u, double w, Map<String, double> carried) {
    final total = volume + w;
    final a = volume / total;
    final b = w / total;
    x = x * a + at * b;
    v = v * a + u * b;
    c = {
      for (final k in {...c.keys, ...carried.keys})
        k: (c[k] ?? 0.0) * a + (carried[k] ?? 0.0) * b,
    };
    volume = total;
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
/// what reaches a receiver leaves as whole particles, and so does what
/// [retire] takes out. So [volume] — the particles and the bank — is exactly
/// what came in less what was [received] and [retired].
final class ParticleFluid {
  ParticleFluid({
    required this.medium,
    required this.spacing,
    this.iterations = 4,
    this.substeps = 2,
    this.solver = const DartFluid(),
  }) : h = 2.0 * spacing {
    final kernels = _Kernels(h);
    _gamma = _cohesionForWorkOfCohesion(kernels);
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
          sum += kernels.poly6(r2);
          gradient2 += kernels
              .spikyGradient(_V(a * spacing, b * spacing, c * spacing))
              .length2;
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

  /// What moves the particles each step: the reference unless told
  /// otherwise; a `FluidWorld` gives its own, the run's.
  final FluidSolver solver;

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

  /// The kernel's reach, in metres: twice [spacing].
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
  double _retired = 0.0;

  /// How long [retire]'s test has held of each particle, in seconds.
  final List<double> _settled = [];

  /// The one landing every particle handed over goes in.
  final JetLanding _landing = JetLanding();

  /// How much liquid one particle is, in cubic metres.
  double get particleVolume => spacing * spacing * spacing;
  double get _mass => medium.density * particleVolume;

  /// Where the liquid is: each particle's place, then each drop's middle
  /// ([drops]), so whatever draws the spilt liquid as points draws the drops
  /// too.
  List<Vector3> get positions => [
    for (final p in _x) p.toVector3(),
    for (final d in _drops) d.x.toVector3(),
  ];

  /// The velocity at each of [positions], in its order.
  List<Vector3> get velocities => [
    for (final v in _v) v.toVector3(),
    for (final d in _drops) d.v.toVector3(),
  ];

  /// How many particles the solve steps: the first [count] of [positions].
  int get count => _x.length;

  /// Cubic metres here: every particle, every drop and the bank.
  double get volume =>
      _x.length * particleVolume +
      _drops.fold(0.0, (s, d) => s + d.volume) +
      _bank;

  /// Cubic metres handed to receivers so far.
  double get received => _received;

  /// Cubic metres [retire] has taken out so far.
  double get retired => _retired;

  /// Takes out every particle that [settled] has held true of for [after]
  /// seconds running, and says where they were and what they carried.
  ///
  /// Meant to be called once a frame, [elapsed] being the seconds since the
  /// last call: a particle [settled] holds true of has [elapsed] added to
  /// its time, one it does not starts again from nought. [settled] is asked
  /// with the particle's position and velocity, in vectors lent for the
  /// call and reused for the next particle.
  ///
  /// **What this is for is cost.** Liquid spilt where nothing will gather
  /// it up again — a puddle on a bench — is still a particle every step
  /// solves for, and a solve that only ever gains particles only ever gets
  /// slower. Taken out, it is whatever the caller draws in its place, and
  /// costs nothing; the volume it was is counted in [retired], and
  /// `FluidWorld.volume` still counts it.
  ///
  /// **Lying low, rather than lying still,** is what a caller usually
  /// tests on a floor: a [PlaneObstacle] has no friction and no contact
  /// angle, so a lone particle on one slides on at the speed it landed
  /// with, and a test for stillness would never pass.
  RetiredParticles retire({
    required double elapsed,
    required double after,
    required bool Function(Vector3 position, Vector3 velocity) settled,
  }) {
    if (_x.isEmpty && _drops.isEmpty) return RetiredParticles.none;
    final position = Vector3.zero();
    final velocity = Vector3.zero();
    final gone = <Vector3>[];
    final amounts = <String, double>{};
    final v = particleVolume;
    final goneDrops = <LiquidDrop>[];
    for (var i = _drops.length - 1; i >= 0; i--) {
      final d = _drops[i];
      position.setValues(d.x.x, d.x.y, d.x.z);
      velocity.setValues(d.v.x, d.v.y, d.v.z);
      d.settled = settled(position, velocity) ? d.settled + elapsed : 0.0;
      if (d.settled < after) continue;
      goneDrops.add(
        LiquidDrop(
          position: d.x.toVector3(),
          velocity: d.v.toVector3(),
          volume: d.volume,
          concentrations: Map.unmodifiable(d.c),
        ),
      );
      d.c.forEach((key, c) {
        amounts[key] = (amounts[key] ?? 0.0) + c * d.volume;
      });
      _retired += d.volume;
      _drops.removeAt(i);
    }
    var kept = 0;
    for (var i = 0; i < _x.length; i++) {
      final x = _x[i];
      final u = _v[i];
      position.setValues(x.x, x.y, x.z);
      velocity.setValues(u.x, u.y, u.z);
      final time = settled(position, velocity) ? _settled[i] + elapsed : 0.0;
      if (time >= after) {
        gone.add(x.toVector3());
        _c[i].forEach((key, c) {
          amounts[key] = (amounts[key] ?? 0.0) + c * v;
        });
        continue;
      }
      _x[kept] = x;
      _v[kept] = u;
      _c[kept] = _c[i];
      _settled[kept] = time;
      kept++;
    }
    if (gone.isEmpty && goneDrops.isEmpty) return RetiredParticles.none;
    _x.length = kept;
    _v.length = kept;
    _c.length = kept;
    _settled.length = kept;
    _retired += gone.length * v;
    return RetiredParticles(
      positions: gone,
      particleVolume: v,
      amounts: amounts,
      drops: goneDrops,
    );
  }

  /// Adds [amount] cubic metres at [position] moving at [velocity], with
  /// [concentrations] dissolved in it.
  ///
  /// **Less than a drop the capillary length across is one drop**, of
  /// exactly [amount], in flight ([drops]), unless the air it last flew
  /// through would tear it apart. Anything else, or anything put
  /// [asParticles] — liquid laid straight onto a wall — is as many whole
  /// particles as it and the bank make, laid out round [position] at the
  /// spacing so none start on top of another, each carrying what the bank
  /// holds per cubic metre.
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
    _bankFed = true;
    _bankAt.setValues(position.x, position.y, position.z);
    _bankVelocity.setValues(velocity.x, velocity.y, velocity.z);
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
          _settled.add(0.0);
          placed++;
        }
      }
    }
  }

  /// Moves the particles on by [dt] under [gravity], against [obstacles],
  /// into [receivers].
  ///
  /// The solve itself is the [solver]'s; how many substeps it takes, which
  /// walls it is given and what is caught after are worked out here, the
  /// same on every backend.
  ///
  /// The [drops] are flown first, each as the body it is, through [air]
  /// where there is some and by [gravityAt] their own place where gravity
  /// differs from place to place; the particles then by [gravity], and
  /// those that have left every wall gathered into drops again.
  void step(
    double dt, {
    required Vector3 gravity,
    List<JetObstacle> obstacles = const [],
    List<JetReceiver> receivers = const [],
    FluidAir? air,
    Vector3 Function(Vector3 point)? gravityAt,
  }) {
    if (gravity.length > 0.0) _lastG = gravity.length;
    _lastAir = air;
    _releaseBank();
    _stepDrops(dt, gravity, obstacles, receivers, air, gravityAt);
    if (_x.isEmpty) return;
    // A quarter of the capillary time a substep at most, and never fewer
    // than asked. How far a particle goes in one is not held here: it is
    // moved in pieces against the walls instead, which costs a wall test,
    // not a density solve, per piece.
    final fastest = _v.fold(0.0, (m, v) => math.max(m, v.length));
    final count = math
        .max(substeps, (dt / (0.25 * capillaryTime)).ceil())
        .clamp(1, 256);
    final sub = dt / count;
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
    final n = _x.length;
    final state = Float64List(n * ParticleMotion.particleFloats);
    for (var i = 0; i < n; i++) {
      final at = i * ParticleMotion.particleFloats;
      state
        ..[at] = _x[i].x
        ..[at + 1] = _x[i].y
        ..[at + 2] = _x[i].z
        ..[at + 3] = _v[i].x
        ..[at + 4] = _v[i].y
        ..[at + 5] = _v[i].z;
    }
    solver.moveParticles(
      ParticleMotion(
        state: state,
        medium: medium,
        spacing: spacing,
        iterations: iterations,
        substeps: count,
        dt: sub,
        gravity: gravity,
        cohesion: _gamma,
        latticeSum: _latticeSum,
        restStiffness: _restStiffness,
        walls: walls,
      ),
    );
    for (var i = 0; i < n; i++) {
      final at = i * ParticleMotion.particleFloats;
      _x[i]
        ..x = state[at]
        ..y = state[at + 1]
        ..z = state[at + 2];
      _v[i]
        ..x = state[at + 3]
        ..y = state[at + 4]
        ..z = state[at + 5];
    }
    // Into a vessel's liquid: handed over, whole.
    final radius = 0.5 * spacing;
    for (var i = _x.length - 1; i >= 0; i--) {
      final at = _x[i].toVector3();
      for (final r in receivers) {
        if (!r.catches(at, radius)) continue;
        r.receive(
          _landing
            ..volume = particleVolume
            ..point = at
            ..velocity = _v[i].toVector3()
            ..medium = medium
            ..concentrations = _c[i],
        );
        _received += particleVolume;
        _removeParticle(i);
        break;
      }
    }
    _clustersToDrops(walls);
  }

  void _removeParticle(int i) {
    _x.removeAt(i);
    _v.removeAt(i);
    _c.removeAt(i);
    _settled.removeAt(i);
  }

  // ------------------------------------------------------------- drops

  /// **A drop in flight is one body.** Falling, it does not feel its own
  /// weight, and what would break it up is the air: it holds together while
  /// its aerodynamic Weber number ρ_a·u²·d/σ is under about twelve (Pilch
  /// and Erdman, Int. J. Multiphase Flow 13, 1987), and a four-millimetre
  /// drop at a metre a second is at a fifteenth of one. So it moves as one:
  /// its drag a sphere's ([FluidAir.dragOnSphere]), its evaporation a
  /// sphere's, its hold on a wall Furmidge's ([SolidSurface.retention]).
  /// Laid out as particles it was dozens of bodies stepped at the capillary
  /// time, and a block of them, free in the air, rang until it flew apart.
  ///
  /// Particles are for liquid on a wall: a drop that lands on a wall wider
  /// than the capillary length, or meets the particles, becomes particles;
  /// particles that leave every wall gather into a drop again.
  final List<_Drop> _drops = [];

  /// The air last flown through and the strength of the gravity last
  /// stepped under, which [inject] judges a drop by.
  FluidAir? _lastAir;
  double _lastG = standardGravity;

  /// Whether liquid went into the bank since the last step, and where the
  /// last of it came in and how fast.
  bool _bankFed = false;
  final Vector3 _bankAt = Vector3.zero();
  final Vector3 _bankVelocity = Vector3.zero();

  /// **What is less than a particle is let go too**, once no more liquid
  /// comes to make it one: as a droplet of its own amount, where the last
  /// came in. Kept in the bank, the end of every run of drops, up to a
  /// particle's worth of it, was counted and was nowhere.
  void _releaseBank() {
    final fed = _bankFed;
    _bankFed = false;
    if (fed || _bank <= 0.0) return;
    _drops.add(
      _Drop(
        _V(_bankAt.x, _bankAt.y, _bankAt.z),
        _V(_bankVelocity.x, _bankVelocity.y, _bankVelocity.z),
        _bank,
        {for (final e in _bankAmounts.entries) e.key: e.value / _bank},
      ),
    );
    _bank = 0.0;
    _bankAmounts.clear();
  }

  /// The critical aerodynamic Weber number.
  static const double _breakupWeber = 12.0;

  /// The drops in flight or held on a wall, each one body: a fresh list.
  List<LiquidDrop> get drops => [
    for (final d in _drops)
      LiquidDrop(
        position: d.x.toVector3(),
        velocity: d.v.toVector3(),
        volume: d.volume,
        concentrations: Map.unmodifiable(d.c),
      ),
  ];

  /// Cubic metres evaporated from the drops so far.
  double get evaporated => _evaporated;
  double _evaporated = 0.0;

  bool _isDrop(double volume, Vector3 position, Vector3 velocity) {
    if (volume <= 0.0 || medium.surfaceTension <= 0.0) return false;
    final d = Portable.pow(6.0 * volume / math.pi, 1.0 / 3.0);
    if (d > medium.capillaryLength(_lastG)) return false;
    final air = _lastAir;
    if (air == null) return true;
    final u = velocity - air.windAt(position);
    return air.density * u.length2 * d / medium.surfaceTension < _breakupWeber;
  }

  /// Each drop moved on by [dt]: the air's drag and evaporation, a wall
  /// holding it or letting it slide, the walls it meets, the receivers it
  /// reaches; drops that touch run together, and a drop that touches the
  /// particles or lands wider than the capillary length becomes particles.
  void _stepDrops(
    double dt,
    Vector3 gravity,
    List<JetObstacle> obstacles,
    List<JetReceiver> receivers,
    FluidAir? air,
    Vector3 Function(Vector3 point)? gravityAt,
  ) {
    if (_drops.isEmpty) return;
    _mergeDrops();
    for (var i = _drops.length - 1; i >= 0; i--) {
      final d = _drops[i];
      final reach = d.radius + 0.5 * spacing;
      // Less than a particle stays a droplet beside them: laid out as
      // particles it would only wait in the bank.
      if (d.volume < particleVolume) continue;
      if (!_x.any((p) => p.distance2(d.x) < reach * reach)) continue;
      _drops.removeAt(i);
      _addToParticles(d.volume, d.x.toVector3(), d.v.toVector3(), d.c);
    }
    final rho = medium.density;
    for (var i = _drops.length - 1; i >= 0; i--) {
      final d = _drops[i];
      final at = d.x.toVector3();
      final g = gravityAt?.call(at) ?? gravity;
      final r = d.radius;
      final a = _V(g.x, g.y, g.z);
      if (air != null) {
        final drag = air.dragOnSphere(d.v.toVector3(), at, 2.0 * r, rho);
        a.add(_V(drag.x, drag.y, drag.z));
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
      final touch = _touching(d, walls);
      // On a wall and wider than the capillary length, its weight flattens
      // it: it spreads there as particles.
      if (touch != null &&
          2.0 * r > medium.capillaryLength(math.max(g.length, 1e-9))) {
        _drops.removeAt(i);
        _addToParticles(d.volume, at, d.v.toVector3(), d.c);
        continue;
      }
      if (touch != null) {
        // Held whole by its edge, or sliding with what of its weight along
        // the wall the edge cannot hold.
        final n = touch.normal;
        final into = a.x * n.x + a.y * n.y + a.z * n.z;
        final along = _V(a.x - n.x * into, a.y - n.y * into, a.z - n.z * into);
        final pull = rho * d.volume * along.length;
        final hold = touch.solid.retention(
          medium,
          2.0 * touch.solid.baseRadius(medium, d.volume),
        );
        if (pull <= hold) {
          d.v = _V(0, 0, 0);
        } else {
          d.v.addScaled(along, (1.0 - hold / pull) * dt);
          final off = d.v.x * n.x + d.v.y * n.y + d.v.z * n.z;
          if (off < 0.0) d.v.addScaled(n, -off);
        }
      } else {
        d.v.addScaled(a, dt);
      }
      // In pieces no longer than its radius, held out of the walls after
      // each: what meets a wall loses the part of its speed into it.
      final pieces = (d.v.length * dt / r).ceil().clamp(1, 64);
      for (var k = 0; k < pieces; k++) {
        d.x.addScaled(d.v, dt / pieces);
        for (final o in walls) {
          final hit = o.touch(d.x.toVector3(), r);
          if (hit == null) continue;
          final n = _V(hit.normal.x, hit.normal.y, hit.normal.z);
          d.x.addScaled(n, hit.depth);
          final off = d.v.x * n.x + d.v.y * n.y + d.v.z * n.z;
          if (off < 0.0) d.v.addScaled(n, -off);
        }
      }
      final now = d.x.toVector3();
      for (final receiver in receivers) {
        if (!receiver.catches(now, r)) continue;
        receiver.receive(
          _landing
            ..volume = d.volume
            ..point = now
            ..velocity = d.v.toVector3()
            ..medium = medium
            ..concentrations = d.c,
        );
        _received += d.volume;
        _drops.removeAt(i);
        break;
      }
    }
  }

  /// The wall [d] touches, its way out and what it is made of, if any.
  ({_V normal, SolidSurface solid})? _touching(
    _Drop d,
    List<JetObstacle> walls,
  ) {
    final at = d.x.toVector3();
    for (final o in walls) {
      final hit = o.touch(at, d.radius * 1.05);
      if (hit != null) {
        return (
          normal: _V(hit.normal.x, hit.normal.y, hit.normal.z),
          solid: o.surface ?? SolidSurface.glass,
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
          a.absorb(b.x, b.v, b.volume, b.c);
          _drops.removeAt(j);
          merged = true;
          break outer;
        }
      }
    }
  }

  /// [d]'s evaporation in [dt] ([FluidAir.sphereEvaporation]), what is
  /// dissolved left behind in less liquid.
  void _evaporate(_Drop d, double dt, FluidAir air) {
    final wind = air.windAt(d.x.toVector3());
    final through = _V(d.v.x - wind.x, d.v.y - wind.y, d.v.z - wind.z).length;
    final rate = air.sphereEvaporation(medium, 2.0 * d.radius, through);
    if (rate <= 0.0) return;
    final gone = math.min(rate / medium.density * dt, d.volume);
    _evaporated += gone;
    final kept = d.volume - gone;
    if (kept > 0.0) {
      d.c = {for (final e in d.c.entries) e.key: e.value * d.volume / kept};
    }
    d.volume = kept;
  }

  /// Particles gathered into a drop — each within a spacing and a half of
  /// another of it — that touch no wall become that drop: one body again,
  /// in flight.
  void _clustersToDrops(List<JetObstacle> walls) {
    final n = _x.length;
    if (n == 0 || medium.surfaceTension <= 0.0) return;
    final parent = List<int>.generate(n, (i) => i);
    int root(int i) {
      var r = i;
      while (parent[r] != r) {
        parent[r] = parent[parent[r]];
        r = parent[r];
      }
      return r;
    }

    final grid = _Grid(h, _x);
    final close = 2.25 * spacing * spacing;
    for (var i = 0; i < n; i++) {
      for (final j in grid.near(i, _x)) {
        if (_x[i].distance2(_x[j]) < close) parent[root(i)] = root(j);
      }
    }
    final volume = <int, double>{};
    final momentum = <int, _V>{};
    final onWall = <int>{};
    for (var i = 0; i < n; i++) {
      final r = root(i);
      volume[r] = (volume[r] ?? 0.0) + particleVolume;
      (momentum[r] ??= _V(0, 0, 0)).addScaled(_v[i], particleVolume);
      final at = _x[i].toVector3();
      if (walls.any((o) => o.touch(at, spacing) != null)) onWall.add(r);
    }
    final into = <int, _Drop>{};
    for (final MapEntry(key: r, value: v) in volume.entries) {
      if (onWall.contains(r)) continue;
      final velocity = (momentum[r]! * (1.0 / v)).toVector3();
      if (_isDrop(v, _x[r].toVector3(), velocity)) {
        into[r] = _Drop(_V(0, 0, 0), _V(0, 0, 0), 0.0, {});
      }
    }
    if (into.isEmpty) return;
    for (var i = n - 1; i >= 0; i--) {
      final d = into[root(i)];
      if (d == null) continue;
      d.absorb(_x[i], _v[i], particleVolume, _c[i]);
      _removeParticle(i);
    }
    _drops.addAll(into.values);
  }

  /// The cohesion coefficient that makes the work of pulling the lattice
  /// apart along a plane 2σ per square metre: the potential of the cohesion
  /// force, summed across a plane over every pair within reach, per unit of
  /// area, at a coefficient of one, then scaled.
  double _cohesionForWorkOfCohesion(_Kernels kernels) {
    final m = _mass;
    double potential(double r) {
      // ∫ from r to h of m²C(s) ds, by Simpson over sixteen pieces.
      const pieces = 16;
      final step = (h - r) / pieces;
      var sum = 0.0;
      for (var k = 0; k <= pieces; k++) {
        final s = r + k * step;
        final w = k == 0 || k == pieces ? 1.0 : (k.isOdd ? 4.0 : 2.0);
        sum += w * m * m * kernels.cohesion(s);
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
}

/// [motion] moved in Dart: what [DartFluid.moveParticles] does.
void moveParticlesInDart(ParticleMotion motion) {
  final state = motion.state;
  final n = motion.count;
  const stride = ParticleMotion.particleFloats;
  final x = [
    for (var i = 0; i < n; i++)
      _V(state[i * stride], state[i * stride + 1], state[i * stride + 2]),
  ];
  final v = [
    for (var i = 0; i < n; i++)
      _V(state[i * stride + 3], state[i * stride + 4], state[i * stride + 5]),
  ];
  final solve = _Solve(motion, x, v);
  final g = _V(motion.gravity.x, motion.gravity.y, motion.gravity.z);
  for (var s = 0; s < motion.substeps; s++) {
    solve.substep(motion.dt, g);
  }
  for (var i = 0; i < n; i++) {
    final at = i * stride;
    final p = solve.x[i];
    final u = solve.v[i];
    state
      ..[at] = p.x
      ..[at + 1] = p.y
      ..[at + 2] = p.z
      ..[at + 3] = u.x
      ..[at + 4] = u.y
      ..[at + 5] = u.z;
  }
}

/// The kernels for a reach of [h]: the density's poly6, the pressure's
/// spiky gradient, and Akinci's cohesion spline.
final class _Kernels {
  _Kernels(this.h);

  /// The kernels' reach, in metres.
  final double h;

  double poly6(double r2) {
    final h2 = h * h;
    if (r2 >= h2) return 0.0;
    final d = h2 - r2;
    return 315.0 / (64.0 * math.pi * _pow9(h)) * d * d * d;
  }

  _V spikyGradient(_V d) {
    final r = d.length;
    if (r <= 1e-12 || r >= h) return _V(0, 0, 0);
    final f = -45.0 / (math.pi * _pow6(h)) * (h - r) * (h - r);
    return d * (f / r);
  }

  /// Akinci's cohesion spline.
  double cohesion(double r) {
    if (r >= h || r <= 0.0) return 0.0;
    final c = 32.0 / (math.pi * _pow9(h));
    final a = (h - r) * (h - r) * (h - r) * r * r * r;
    if (2.0 * r > h) return c * a;
    return c * (2.0 * a - _pow6(h) / 64.0);
  }

  static double _pow6(double x) => x * x * x * x * x * x;
  static double _pow9(double x) => _pow6(x) * x * x * x;
}

/// One [ParticleMotion]'s solve, on the particles [x] moving at [v].
final class _Solve {
  _Solve(this.motion, this.x, this.v)
    : h = 2.0 * motion.spacing,
      kernels = _Kernels(2.0 * motion.spacing);

  final ParticleMotion motion;
  final List<_V> x;
  final List<_V> v;

  /// The kernel's reach, in metres.
  final double h;
  final _Kernels kernels;

  /// The particles' spacing at rest, in metres.
  double get spacing => motion.spacing;
  double get _mass => motion.medium.density * spacing * spacing * spacing;
  List<JetObstacle> get obstacles => motion.walls;

  double _poly6(double r2) => kernels.poly6(r2);
  _V _spikyGradient(_V d) => kernels.spikyGradient(d);

  void substep(double dt, _V gravity) {
    final n = x.length;
    // Where a particle starts inside a wall or under the floor, it is put
    // out first, its velocity left alone. A drop let go near the bottom of a
    // glass is laid out as a little block round where it parted, and a
    // particle of the block can start under the floor; put out by the
    // correction pass instead, its four millimetres became its velocity
    // over a fifth of a millisecond, and it left at eighteen metres a
    // second.
    for (var i = 0; i < n; i++) {
      _collide(x[i]);
    }
    // **Pre-stabilisation** (Macklin, Müller, Chentanez and Kim, "Unified
    // Particle Physics for Real-Time Applications", 2014): the compression
    // there already is when the substep starts is taken out of where the
    // particles are, and not out of how fast they go — the same as a
    // particle started in a wall, above, for the same reason. A stream lets
    // go of its drops at nearly one point step after step and lays each
    // lump over the last; corrected only in the solve below, that overlap
    // became velocity, and the chemistry bench's overflowing flask threw
    // thirty thousand particles eleven metres up. Taken out here, the crowd
    // makes room for itself and keeps the speed it had.
    _holdDensity(x, artificialPressure: false, until: 1e-3);
    final rho0 = motion.medium.density;
    final m = _mass;
    final gamma = motion.cohesion;
    final norm = 1.0 / motion.latticeSum;
    // Forces first: gravity, cohesion and curvature, on the velocities.
    final grid = _Grid(h, x);
    final neighbors = [for (var i = 0; i < n; i++) grid.near(i, x)];
    final density = List<double>.filled(n, 0.0);
    for (var i = 0; i < n; i++) {
      var w = _poly6(0.0);
      for (final j in neighbors[i]) {
        w += _poly6(x[i].distance2(x[j]));
      }
      density[i] = rho0 * w * norm;
    }
    final normal = List<_V>.generate(n, (_) => _V(0, 0, 0));
    for (var i = 0; i < n; i++) {
      for (final j in neighbors[i]) {
        normal[i].addScaled(_spikyGradient(x[i] - x[j]), h * m / density[j]);
      }
    }
    for (var i = 0; i < n; i++) {
      final a = gravity.copy();
      for (final j in neighbors[i]) {
        final d = x[i] - x[j];
        final r = d.length;
        if (r < 1e-12) continue;
        final k = 2.0 * rho0 / (density[i] + density[j]);
        a
          ..addScaled(d, -k * gamma * m * kernels.cohesion(r) / r)
          ..addScaled(normal[i] - normal[j], -k * gamma);
      }
      v[i].addScaled(a, dt);
    }
    // Predict, then hold the density to the rest density.
    final p = [for (var i = 0; i < n; i++) _advance(x[i], v[i], dt)];
    final near = _holdDensity(p, artificialPressure: true);
    // Velocities from the move, then XSPH's viscosity.
    for (var i = 0; i < n; i++) {
      v[i] = (p[i] - x[i]) * (1.0 / dt);
    }
    final share = math.min(
      0.5,
      motion.medium.kinematicViscosity * dt / (spacing * spacing) * 50.0 + 0.01,
    );
    final smoothed = [for (final u in v) u.copy()];
    for (var i = 0; i < n; i++) {
      for (final j in near[i]) {
        final w = _poly6(p[i].distance2(p[j])) * norm;
        smoothed[i].addScaled(v[j] - v[i], share * w);
      }
    }
    for (var i = 0; i < n; i++) {
      v[i] = smoothed[i];
      x[i] = p[i];
    }
  }

  /// Moves [p] until no particle is compressed past the rest density, for
  /// the motion's iterations at most, or fewer once none is compressed by
  /// more than [until] of it; returns each particle's neighbours, found
  /// where [p] stood at the start.
  ///
  /// [artificialPressure] adds Macklin's term against clumping, which the
  /// solve wants and pre-stabilisation does not: there it would push still
  /// water apart every substep with nothing to answer it.
  List<List<int>> _holdDensity(
    List<_V> p, {
    required bool artificialPressure,
    double until = 0.0,
  }) {
    final n = p.length;
    final norm = 1.0 / motion.latticeSum;
    final lambda = List<double>.filled(n, 0.0);
    final grid = _Grid(h, p);
    final near = [for (var i = 0; i < n; i++) grid.near(i, p)];
    final dq = 0.3 * h;
    final wq = _poly6(dq * dq);
    for (var it = 0; it < motion.iterations; it++) {
      var worst = 0.0;
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
          final d = _between(p, i, j);
          w += _poly6(d.length2);
          final g = _spikyGradient(d) * norm;
          sum2 += g.length2;
          gi.add(g);
        }
        sum2 += gi.length2;
        final c = math.max(w * norm - 1.0, 0.0);
        worst = math.max(worst, c);
        lambda[i] = -c / (sum2 + 1e-6 * norm * norm / (h * h));
      }
      if (worst <= until) break;
      final delta = List<_V>.generate(n, (_) => _V(0, 0, 0));
      for (var i = 0; i < n; i++) {
        for (final j in near[i]) {
          final d = _between(p, i, j);
          var corr = 0.0;
          if (artificialPressure) {
            final ratio = _poly6(d.length2) / wq;
            // Macklin's artificial pressure, which keeps neighbours from
            // clumping: a fiftieth of a constraint's worth. At his tenth it
            // held still water a sixth thinner than its rest density.
            corr = -0.02 * ratio * ratio * ratio * ratio / motion.restStiffness;
          }
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
        _collide(p[i]);
      }
    }
    return near;
  }

  /// Where [x] moving at [v] is after [dt]: moved in pieces of two fifths
  /// of a spacing, put out of the walls after each. A wall holds what comes
  /// within a radius of it or half its thickness into it, a band wider than
  /// a piece, so nothing passes through glass thinner than a particle; a
  /// drop falling a metre a second into a test tube went five millimetres a
  /// step and through its bottom.
  _V _advance(_V x, _V v, double dt) {
    final p = x.copy();
    final pieces = obstacles.isEmpty
        ? 1
        : (v.length * dt / (0.4 * spacing)).ceil().clamp(1, 64);
    for (var k = 0; k < pieces; k++) {
      p.addScaled(v, dt / pieces);
      if (pieces > 1) _collide(p);
    }
    return p;
  }

  void _collide(_V p) {
    final radius = 0.5 * spacing;
    for (final o in obstacles) {
      final hit = o.touch(p.toVector3(), radius);
      if (hit != null) {
        p.addScaled(_V(hit.normal.x, hit.normal.y, hit.normal.z), hit.depth);
      }
    }
  }

  /// pᵢ − pⱼ, or, where the two stand on the same point, a hair of it in a
  /// direction set by the pair alone — opposite for j and i.
  ///
  /// **Coincident particles have no gradient to part along.** Each counts
  /// whole in the other's density, and the kernel's gradient at nought is
  /// nought: the constraint read heavily compressed with nothing to move it
  /// by, λ = −C / |∇C|² ran away, and the particles round the pair were
  /// thrown kilometres. A stream's lumps let go at the same point land
  /// exactly on each other's lattice, so this is the ordinary case, not a
  /// corner.
  _V _between(List<_V> p, int i, int j) {
    final d = p[i] - p[j];
    if (d.length2 > 1e-24 * h * h) return d;
    final low = math.min(i, j);
    final high = math.max(i, j);
    // A point on the sphere from the pair's indices, by the golden angle.
    final t = (low * 0.6180339887498949 + high * 0.4142135623730951) % 1.0;
    final z = 1.0 - 2.0 * t;
    final ring = math.sqrt(math.max(1.0 - z * z, 0.0));
    final phi = 2.399963229728653 * (low + 7 * high);
    final away = 1e-6 * h * (i < j ? 1.0 : -1.0);
    return _V(
      ring * Portable.cos(phi) * away,
      ring * Portable.sin(phi) * away,
      z * away,
    );
  }
}

/// A uniform grid of cells as wide as the kernel, for finding neighbours.
final class _Grid {
  _Grid(this.cell, List<_V> points) {
    for (var i = 0; i < points.length; i++) {
      _cells.putIfAbsent(_key(points[i]), () => []).add(i);
    }
  }

  /// A cell's side, in metres.
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

  /// The x component: metres for a position, metres per second for a
  /// velocity.
  double x;

  /// The y component, in the unit of [x].
  double y;

  /// The z component, in the unit of [x].
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

  /// The squared length, in the square of the unit of [x].
  double get length2 => x * x + y * y + z * z;

  /// The length, in the unit of [x].
  double get length => math.sqrt(length2);

  double distance2(_V o) {
    final dx = x - o.x, dy = y - o.y, dz = z - o.z;
    return dx * dx + dy * dy + dz * dz;
  }
}
