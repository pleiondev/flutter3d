/// The spilt liquid's pair loops as kernels: [liquidPairKernels], and
/// [KernelLiquid], the solver that hands them to an executor.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart' show Portable;
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show SimulationProfile;
import 'package:vector_math/vector_math.dart';

import 'liquid_lanes.dart';

/// Floats of the pair kernels' `params`: the particles, the kernel's reach
/// and its square, the rest density, a particle's mass, the lattice's
/// norm, the cohesion coefficient, the rest stiffness, the poly6, spiky
/// and cohesion constants, h⁶, W(0.3h), XSPH's share, the artificial
/// pressure's scale (nought where there is none), the constraint's
/// softening and the distance under which two particles have no gradient.
const int liquidParamFloats = 17;

/// poly6(r²) of the local [r2] into a new local [name]: nought past the
/// reach.
String _poly6(String name, String r2) =>
    '''
      var $name = 0.0;
      if $r2 < params[2] {
        let ${name}d = params[2] - $r2;
        $name = params[8] * ${name}d * ${name}d * ${name}d;
      }''';

/// The spiky gradient's scale at distance [r] into a new local [name]:
/// nought at the same point and past the reach.
String _spiky(String name, String r) =>
    '''
      var $name = 0.0;
      if $r > params[16] && $r < params[1] {
        let ${name}h = params[1] - $r;
        $name = params[9] * ${name}h * ${name}h / $r;
      }''';

/// The neighbours of particle `i` in its row, [visit] done with each `j`,
/// `dx`, `dy`, `dz` from it and `r2` its distance squared.
String _row(String positions, String visit) =>
    '''
    for q in start[i] .. start[i + 1] {
      let j = list[q];
      let dx = xi - $positions[j * 3];
      let dy = yi - $positions[j * 3 + 1];
      let dz = zi - $positions[j * 3 + 2];
      let r2 = dx * dx + dy * dy + dz * dz;
$visit
    }''';

/// The kernel's opening: particle `i`, nothing past the last, its place.
String _particle(String positions) =>
    '''
    if id.x >= u32(params[0]) { return; }
    let i = i32(id.x);
    let xi = $positions[i * 3];
    let yi = $positions[i * 3 + 1];
    let zi = $positions[i * 3 + 2];''';

/// The spilt liquid's pair loops (`ParticleFluid`, Position Based Fluids),
/// written once in the kernel language: `LiquidDensity`, `LiquidNormal`,
/// `LiquidForce`, `LiquidLambda`, `LiquidDelta` and `LiquidSmooth`, an
/// invocation a particle.
///
/// **Over flat buffers**: `x` (and `v`) three floats a particle, the
/// neighbours as compressed rows (`start`, `list`: particle i's are
/// `list[start[i]]` up to `list[start[i + 1]]`, itself left out), the
/// constants in `params` ([liquidParamFloats]). Within the portable
/// profile: 64 invocations a workgroup, seven storage buffers at most.
///
/// **They divide and take square roots**, so a GPU computes them to within
/// the hardware layer's tolerances, and only the CPU kernel — their Dart
/// translation, rounded to f32 after every operation — gives the same bytes
/// on every machine; [KernelLiquid] asks for that where the run must
/// replay.
final String liquidPairKernels =
    '''
kernel 1

// Each particle's density: rho0 times the poly6 sum over the lattice's.
compute LiquidDensity {
  workgroup 64;
  buffer x: f32[] read;
  buffer start: i32[] read;
  buffer list: i32[] read;
  buffer density: f32[] read_write;
  buffer params: f32[] read;
  kernel {
${_particle('x')}
    var w = params[8] * params[2] * params[2] * params[2];
${_row('x', '''
${_poly6('k6', 'r2')}
      w = w + k6;''')}
    density[i] = params[3] * w * params[5];
  }
}

// Each particle's colour-field normal: h times the sum of m / rho_j grad W.
compute LiquidNormal {
  workgroup 64;
  buffer x: f32[] read;
  buffer start: i32[] read;
  buffer list: i32[] read;
  buffer density: f32[] read;
  buffer normal: f32[] read_write;
  buffer params: f32[] read;
  kernel {
${_particle('x')}
    var nx = 0.0;
    var ny = 0.0;
    var nz = 0.0;
${_row('x', '''
      let r = sqrt(r2);
${_spiky('s', 'r')}
      let f = s * params[1] * params[4] / density[j];
      nx = nx + dx * f;
      ny = ny + dy * f;
      nz = nz + dz * f;''')}
    normal[i * 3] = nx;
    normal[i * 3 + 1] = ny;
    normal[i * 3 + 2] = nz;
  }
}

// Cohesion and curvature, added to the acceleration each particle has.
compute LiquidForce {
  workgroup 64;
  buffer x: f32[] read;
  buffer start: i32[] read;
  buffer list: i32[] read;
  buffer density: f32[] read;
  buffer normal: f32[] read;
  buffer accel: f32[] read_write;
  buffer params: f32[] read;
  kernel {
${_particle('x')}
    let h = params[1];
    let di = density[i];
    var ax = accel[i * 3];
    var ay = accel[i * 3 + 1];
    var az = accel[i * 3 + 2];
${_row('x', '''
      let r = sqrt(r2);
      if r < params[16] { continue; }
      let kk = 2.0 * params[3] / (di + density[j]);
      var coh = 0.0;
      if r < h {
        let a = (h - r) * (h - r) * (h - r) * r * r * r;
        if 2.0 * r > h {
          coh = params[10] * a;
        } else {
          coh = params[10] * (2.0 * a - params[11] / 64.0);
        }
      }
      let c = -kk * params[6] * params[4] * coh / r;
      let t = -kk * params[6];
      ax = ax + dx * c + (normal[i * 3] - normal[j * 3]) * t;
      ay = ay + dy * c + (normal[i * 3 + 1] - normal[j * 3 + 1]) * t;
      az = az + dz * c + (normal[i * 3 + 2] - normal[j * 3 + 2]) * t;''')}
    accel[i * 3] = ax;
    accel[i * 3 + 1] = ay;
    accel[i * 3 + 2] = az;
  }
}

// The density constraint's multiplier, and how far it is compressed.
compute LiquidLambda {
  workgroup 64;
  buffer x: f32[] read;
  buffer start: i32[] read;
  buffer list: i32[] read;
  buffer lam: f32[] read_write;
  buffer params: f32[] read;
  kernel {
${_particle('x')}
    let norm = params[5];
    var w = params[8] * params[2] * params[2] * params[2];
    var sum2 = 0.0;
    var gx = 0.0;
    var gy = 0.0;
    var gz = 0.0;
${_row('x', '''
${_poly6('k6', 'r2')}
      w = w + k6;
      let r = sqrt(r2);
${_spiky('s', 'r')}
      let f = s * norm;
      sum2 = sum2 + r2 * f * f;
      gx = gx + dx * f;
      gy = gy + dy * f;
      gz = gz + dz * f;''')}
    sum2 = sum2 + (gx * gx + gy * gy + gz * gz);
    let c = max(w * norm - 1.0, 0.0);
    lam[i * 2] = -c / (sum2 + params[15]);
    lam[i * 2 + 1] = c;
  }
}

// The position correction from the multipliers, with the artificial
// pressure where params[14] asks for it.
compute LiquidDelta {
  workgroup 64;
  buffer x: f32[] read;
  buffer start: i32[] read;
  buffer list: i32[] read;
  buffer lam: f32[] read;
  buffer delta: f32[] read_write;
  buffer params: f32[] read;
  kernel {
${_particle('x')}
    let li = lam[i * 2];
    var sx = 0.0;
    var sy = 0.0;
    var sz = 0.0;
${_row('x', '''
${_poly6('k6', 'r2')}
      let ratio = k6 / params[12];
      let corr = ratio * ratio * ratio * ratio * params[14];
      let r = sqrt(r2);
${_spiky('s', 'r')}
      let f = s * (li + lam[j * 2] + corr) * params[5];
      sx = sx + dx * f;
      sy = sy + dy * f;
      sz = sz + dz * f;''')}
    delta[i * 3] = sx;
    delta[i * 3 + 1] = sy;
    delta[i * 3 + 2] = sz;
  }
}

// XSPH: each velocity drawn towards its neighbours'.
compute LiquidSmooth {
  workgroup 64;
  buffer x: f32[] read;
  buffer v: f32[] read;
  buffer start: i32[] read;
  buffer list: i32[] read;
  buffer smoothed: f32[] read_write;
  buffer params: f32[] read;
  kernel {
${_particle('x')}
    let vx = v[i * 3];
    let vy = v[i * 3 + 1];
    let vz = v[i * 3 + 2];
    var sx = vx;
    var sy = vy;
    var sz = vz;
${_row('x', '''
${_poly6('k6', 'r2')}
      let w = k6 * params[5] * params[13];
      sx = sx + (v[j * 3] - vx) * w;
      sy = sy + (v[j * 3 + 1] - vy) * w;
      sz = sz + (v[j * 3 + 2] - vz) * w;''')}
    smoothed[i * 3] = sx;
    smoothed[i * 3 + 1] = sy;
    smoothed[i * 3 + 2] = sz;
  }
}
''';

/// The constants the pair loops share, for one fluid: worked out from a
/// [ParticleMotion], the same each step of it. What an executor of the
/// loops ([LiquidPairLoops]) is made for.
final class LiquidPairConstants {
  /// The constants of [motion]'s fluid.
  LiquidPairConstants(ParticleMotion motion)
    : h = 2.0 * motion.spacing,
      restDensity = motion.medium.density,
      mass =
          motion.medium.density *
          motion.spacing *
          motion.spacing *
          motion.spacing,
      norm = 1.0 / motion.latticeSum,
      gamma = motion.cohesion,
      restStiffness = motion.restStiffness;

  /// The kernel's reach, metres: twice the spacing.
  final double h;

  /// The liquid's rest density, kilograms per cubic metre.
  final double restDensity;

  /// One particle's mass, kilograms.
  final double mass;

  /// One over the density kernel summed over the rest lattice, cubic
  /// metres: what a density estimate is divided by.
  final double norm;

  /// Akinci's cohesion coefficient, in newton cubic metres per kilogram
  /// squared.
  final double gamma;

  /// Σ|∇C|² over the rest lattice, in the constraint's normalisation, per
  /// square metre: what the artificial pressure is a share of.
  final double restStiffness;

  /// The reach squared, square metres.
  double get h2 => h * h;

  /// The reach to the sixth, metres to the sixth.
  double get h6 => h2 * h2 * h2;

  /// The poly6 kernel's normalisation, per metre to the ninth.
  double get poly6 => 315.0 / (64.0 * math.pi * h6 * h * h * h);

  /// The spiky gradient's normalisation, per metre to the sixth.
  double get spiky => -45.0 / (math.pi * h6);

  /// Akinci's cohesion spline's normalisation, per metre to the ninth.
  double get cohesion => 32.0 / (math.pi * h6 * h * h * h);

  /// The poly6 kernel at three tenths of the reach, per cubic metre: the
  /// artificial pressure's reference.
  double get wq {
    final d = h2 - (0.3 * h) * (0.3 * h);
    return poly6 * d * d * d;
  }

  /// Whether [other] holds the same numbers.
  bool sameAs(LiquidPairConstants other) =>
      other.h == h &&
      other.restDensity == restDensity &&
      other.mass == mass &&
      other.norm == norm &&
      other.gamma == gamma &&
      other.restStiffness == restStiffness;

  /// The constants in the native executor's order: h, h², ρ₀, m, norm, γ,
  /// rest stiffness, poly6, spiky, cohesion, h⁶, W(0.3h).
  Float64List get list => Float64List.fromList(<double>[
    h,
    h2,
    restDensity,
    mass,
    norm,
    gamma,
    restStiffness,
    poly6,
    spiky,
    cohesion,
    h6,
    wq,
  ]);
}

/// What an executor of the pair loops is made for: one fluid's
/// [constants], and the [origin] its particles are handed over about.
///
/// **One object, so a minor can hand an executor more** without breaking
/// the functions that make one.
final class LiquidLoopsContext {
  LiquidLoopsContext._(this.constants, this.origin);

  /// The fluid's constants.
  final LiquidPairConstants constants;

  /// Where positions are taken from before an executor that works in
  /// single precision is handed them, metres: the particles' middle, kept
  /// current by the solver from one motion to the next. Read it at each
  /// call, not once.
  final Vector3 origin;
}

/// The spilt liquid stepped with its pair loops as kernels: a [FluidSolver]
/// whose [moveParticles] is the reference's substep (pre-stabilised,
/// gravity, cohesion and curvature, a predicted move in pieces against the
/// walls, the density held, XSPH's viscosity) with every loop over pairs of
/// neighbours handed to an executor, and the walls, the moves and the
/// neighbour rows kept on the host.
///
/// **Where the loops run is the hardware layer's to say**, and this package
/// names no device: `placeKernelLiquid` in `flutter3d_effects` asks
/// `FrameCompute.placeHosted` and builds one of these on the kernels
/// ([liquidPairKernels]) where they land, a device with compute that reads
/// back in the same turn; or on the work's own native lanes, the loops in C
/// on the processor's vector lanes ([KernelLiquid.native]), which the
/// hardware layer places as `ComputePlacement.nativeSimd` where the run
/// allows it.
///
/// **Under a bit-exact profile** (`SimulationProfile.deterministic`) the
/// work requires `ComputeRequirement.bitExact`: a GPU is passed over, the
/// native lanes are refused, and the loops run on the CPU kernel, the same
/// bytes on every machine — the host's own arithmetic is Dart's doubles,
/// which every platform rounds alike.
///
/// The rest of a step — the parcels, the waves, the pipes, the floating
/// bodies — is [rest]'s.
///
/// **Breaking in 1.0.0-rc.1: no `executor`.** Where the loops run is a
/// placement of the hardware layer's, `ComputePlacement.nativeSimd` among
/// them; this says only what ran them ([backend], [isNativeLanes]).
final class KernelLiquid extends FluidSolver {
  /// A solver whose pair loops [loops] makes for each fluid's constants,
  /// run by [backend]; the rest of a step is [rest]'s. What a placement of
  /// the kernels builds (`placeKernelLiquid` in `flutter3d_effects`), and
  /// [KernelLiquid.native] for the native lanes.
  KernelLiquid({
    required LiquidPairLoops Function(LiquidLoopsContext context) loops,
    required this.backend,
    this.rest = const DartFluid(),
  }) : _make = loops,
       isNativeLanes = false;

  KernelLiquid._lanes({
    required LiquidPairLoops Function(LiquidLoopsContext context) loops,
    required this.rest,
  }) : _make = loops,
       backend = nativeBackend,
       isNativeLanes = true;

  /// The native lanes for a run under [profile], or null where they are
  /// refused — a bit-exact profile, whose bytes must be the CPU kernel's on
  /// every machine — or not there: the browser, a build with no C compiler.
  static KernelLiquid? native({
    SimulationProfile profile = SimulationProfile.deterministic,
    FluidSolver rest = const DartFluid(),
  }) {
    if (profile.isBitExact || !isNativeLanesBuilt) return null;
    return KernelLiquid._lanes(
      loops: (LiquidLoopsContext context) =>
          openLiquidLanes(context.constants.list) ??
          (throw StateError('the native lanes went away')),
      rest: rest,
    );
  }

  /// What [backend] says of the native lanes.
  static const String nativeBackend = 'its own host code';

  /// How far one substep on the native lanes may land from the CPU
  /// kernel's: each position within this share of the particles' spacing,
  /// each velocity within this share of the fastest — a part in ten
  /// thousand. The lanes run in doubles and add in another order; the
  /// kernel rounds to f32 after every operation, a part in ten million
  /// each, and the sums of a few dozen neighbours that nearly cancel lose a
  /// few digits more.
  static const double nativeTolerance = 1e-4;

  /// The name the work goes by where it is placed.
  static const String workName = 'liquid pairs';

  /// Whether the hook built the native lanes here: never in the browser,
  /// and not where there was no C compiler.
  static bool get isNativeLanesBuilt =>
      openLiquidLanes(Float64List(12)) != null;

  /// Whether the pair loops run on the native lanes ([KernelLiquid.native])
  /// rather than as kernels on a device.
  final bool isNativeLanes;

  /// What runs them, by its name for people: a device's backend, or
  /// [nativeBackend].
  final String backend;

  /// What steps the rest: the parcels, the waves, the pipes and the bodies.
  final FluidSolver rest;

  final LiquidPairLoops Function(LiquidLoopsContext context) _make;

  LiquidPairLoops? _loops;
  LiquidPairConstants? _constants;
  final Vector3 _origin = Vector3.zero();

  LiquidPairLoops _loopsFor(LiquidPairConstants constants, Vector3 origin) {
    // The origin the loops are handed is the one kept here, moved each
    // motion, so loops made once read where the particles are now.
    _origin.setFrom(origin);
    final held = _loops;
    if (held != null && _constants!.sameAs(constants)) return held;
    _constants = constants;
    return _loops = _make(LiquidLoopsContext._(constants, _origin));
  }

  @override
  void moveParticles(ParticleMotion motion) {
    final n = motion.count;
    if (n == 0 || motion.substeps <= 0) return;
    final state = motion.state;
    const stride = ParticleMotion.particleFloats;
    final x = Float64List(3 * n);
    final v = Float64List(3 * n);
    for (var i = 0; i < n; i++) {
      for (var k = 0; k < 3; k++) {
        x[3 * i + k] = state[i * stride + k];
        v[3 * i + k] = state[i * stride + 3 + k];
      }
    }
    // About the particles' middle, so single precision keeps the digits a
    // substep's move is read off.
    final origin = Vector3.zero();
    for (var i = 0; i < n; i++) {
      origin.x += x[3 * i] / n;
      origin.y += x[3 * i + 1] / n;
      origin.z += x[3 * i + 2] / n;
    }
    final constants = LiquidPairConstants(motion);
    final solve = _Substeps(motion, _loopsFor(constants, origin), x, v);
    for (var s = 0; s < motion.substeps; s++) {
      solve.substep(motion.dt);
    }
    for (var i = 0; i < n; i++) {
      for (var k = 0; k < 3; k++) {
        state[i * stride + k] = solve.x[3 * i + k];
        state[i * stride + 3 + k] = solve.v[3 * i + k];
      }
    }
  }

  @override
  void flyParcels(ParcelFlight flight) => rest.flyParcels(flight);

  @override
  void ringModes(ModeRinging ringing) => rest.ringModes(ringing);

  @override
  void flowPipes(PipeFlow flow) => rest.flowPipes(flow);

  @override
  void pushBodies(FloatPush push) => rest.pushBodies(push);

  @override
  String toString() =>
      'KernelLiquid(${isNativeLanes ? 'native lanes' : 'kernels'} on '
      '$backend)';
}

/// One motion's substeps on the host, the loops over pairs handed to
/// [loops].
final class _Substeps {
  _Substeps(this.motion, this.loops, this.x, this.v)
    : n = x.length ~/ 3,
      h = 2.0 * motion.spacing;

  final ParticleMotion motion;
  final LiquidPairLoops loops;
  Float64List x;
  Float64List v;
  final int n;

  /// The kernel's reach, metres.
  final double h;

  void substep(double dt) {
    final gravity = motion.gravity;
    // Put out of the walls first, the velocity left alone.
    for (var i = 0; i < n; i++) {
      _collide(x, i);
    }
    _holdDensity(x, artificial: false, until: 1e-3);
    final (start, list) = _neighbours(x);
    final density = Float64List(n);
    final normal = Float64List(3 * n);
    loops
      ..densities(x, start, list, n, density)
      ..normals(x, start, list, n, density, normal);
    final accel = Float64List(3 * n);
    for (var i = 0; i < n; i++) {
      accel
        ..[3 * i] = gravity.x
        ..[3 * i + 1] = gravity.y
        ..[3 * i + 2] = gravity.z;
    }
    loops.forces(x, start, list, n, density, normal, accel);
    for (var k = 0; k < 3 * n; k++) {
      v[k] += accel[k] * dt;
    }
    final p = Float64List.fromList(x);
    for (var i = 0; i < n; i++) {
      _advance(p, i, dt);
    }
    final (nearStart, nearList) = _holdDensity(p, artificial: true);
    for (var k = 0; k < 3 * n; k++) {
      v[k] = (p[k] - x[k]) * (1.0 / dt);
    }
    final share = math.min(
      0.5,
      motion.medium.kinematicViscosity *
              dt /
              (motion.spacing * motion.spacing) *
              50.0 +
          0.01,
    );
    final smoothed = Float64List(3 * n);
    loops.viscosity(p, v, nearStart, nearList, n, share, smoothed);
    v = smoothed;
    x = p;
  }

  /// Moves [p] until no particle is compressed past the rest density, for
  /// the motion's iterations at most, or fewer once none is compressed by
  /// more than [until] of it; returns the neighbour rows found where [p]
  /// stood at the start.
  (Int32List, Int32List) _holdDensity(
    Float64List p, {
    required bool artificial,
    double until = 0.0,
  }) {
    final rows = _neighbours(p);
    final (start, list) = rows;
    _part(p, start, list);
    final lambda = Float64List(n);
    final crowd = Float64List(n);
    final delta = Float64List(3 * n);
    for (var it = 0; it < motion.iterations; it++) {
      loops.lambdas(p, start, list, n, lambda, crowd);
      final worst = crowd.fold(0.0, math.max);
      if (worst <= until) break;
      loops.deltas(p, start, list, n, lambda, delta, artificial: artificial);
      for (var i = 0; i < n; i++) {
        p
          ..[3 * i] += delta[3 * i]
          ..[3 * i + 1] += delta[3 * i + 1]
          ..[3 * i + 2] += delta[3 * i + 2];
        _collide(p, i);
      }
    }
    return rows;
  }

  /// **Coincident particles have no gradient to part along**: a hair apart,
  /// in a direction set by the pair alone, before the density is held.
  /// The reference does the same inside its sums; here the loops are the
  /// executor's, so the particles themselves are moved, by a hundred
  /// thousandth of the reach.
  void _part(Float64List p, Int32List start, Int32List list) {
    final close = 1e-24 * h * h;
    for (var i = 0; i < n; i++) {
      for (var q = start[i]; q < start[i + 1]; q++) {
        final j = list[q];
        if (j <= i) continue;
        final dx = p[3 * i] - p[3 * j];
        final dy = p[3 * i + 1] - p[3 * j + 1];
        final dz = p[3 * i + 2] - p[3 * j + 2];
        if (dx * dx + dy * dy + dz * dz > close) continue;
        // A point on the sphere from the pair's indices, by the golden
        // angle.
        final t = (i * 0.6180339887498949 + j * 0.4142135623730951) % 1.0;
        final z = 1.0 - 2.0 * t;
        final ring = math.sqrt(math.max(1.0 - z * z, 0.0));
        final phi = 2.399963229728653 * (i + 7 * j);
        final away = 1e-5 * h;
        p
          ..[3 * j] += ring * Portable.cos(phi) * away
          ..[3 * j + 1] += ring * Portable.sin(phi) * away
          ..[3 * j + 2] += z * away;
      }
    }
  }

  /// Where particle [i] of [p] moving at its velocity is after [dt]: moved
  /// in pieces of two fifths of a spacing, put out of the walls after each.
  void _advance(Float64List p, int i, double dt) {
    final vx = v[3 * i], vy = v[3 * i + 1], vz = v[3 * i + 2];
    final speed = math.sqrt(vx * vx + vy * vy + vz * vz);
    final pieces = motion.walls.isEmpty
        ? 1
        : (speed * dt / (0.4 * motion.spacing)).ceil().clamp(1, 64);
    for (var k = 0; k < pieces; k++) {
      p
        ..[3 * i] += vx * (dt / pieces)
        ..[3 * i + 1] += vy * (dt / pieces)
        ..[3 * i + 2] += vz * (dt / pieces);
      if (pieces > 1) _collide(p, i);
    }
  }

  final Vector3 _point = Vector3.zero();

  void _collide(Float64List p, int i) {
    final radius = 0.5 * motion.spacing;
    for (final o in motion.walls) {
      _point.setValues(p[3 * i], p[3 * i + 1], p[3 * i + 2]);
      final hit = o.touch(_point, radius);
      if (hit == null) continue;
      p
        ..[3 * i] += hit.normal.x * hit.depth
        ..[3 * i + 1] += hit.normal.y * hit.depth
        ..[3 * i + 2] += hit.normal.z * hit.depth;
    }
  }

  /// A cell's three indices as one key, by multiplication rather than by
  /// shifting into high bits: on the web an int's bitwise operations are 32
  /// bits wide. Each index is held to ±2¹⁶ cells and the key under 2⁵¹,
  /// which a double holds exactly.
  static int _pack(int x, int y, int z) {
    const span = 1 << 17;
    const half = 1 << 16;
    int wrap(int v) => (v + half) % span;
    return (wrap(x) * span + wrap(y)) * span + wrap(z);
  }

  /// The neighbours of each particle at [x] within the kernel's reach, as
  /// compressed rows, in one order on every machine: the particles sorted
  /// by cell and then index, and each particle's row its 27 cells in x,
  /// then y, then z order, each cell's particles by index.
  (Int32List, Int32List) _neighbours(Float64List x) {
    final cx = Int32List(n);
    final cy = Int32List(n);
    final cz = Int32List(n);
    final keys = List<int>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      cx[i] = (x[3 * i] / h).floor();
      cy[i] = (x[3 * i + 1] / h).floor();
      cz[i] = (x[3 * i + 2] / h).floor();
      keys[i] = _pack(cx[i], cy[i], cz[i]);
    }
    final order = List<int>.generate(n, (i) => i)
      ..sort((a, b) {
        final c = keys[a].compareTo(keys[b]);
        return c != 0 ? c : a - b;
      });
    final sorted = [for (final j in order) keys[j]];
    int first(int key) {
      var lo = 0;
      var hi = n;
      while (lo < hi) {
        final mid = (lo + hi) ~/ 2;
        if (sorted[mid] < key) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      return lo;
    }

    final start = Int32List(n + 1);
    final list = <int>[];
    final reach2 = h * h;
    for (var i = 0; i < n; i++) {
      for (var dx = -1; dx <= 1; dx++) {
        for (var dy = -1; dy <= 1; dy++) {
          for (var dz = -1; dz <= 1; dz++) {
            final key = _pack(cx[i] + dx, cy[i] + dy, cz[i] + dz);
            for (var q = first(key); q < n && sorted[q] == key; q++) {
              final j = order[q];
              if (j == i) continue;
              final ex = x[3 * j] - x[3 * i];
              final ey = x[3 * j + 1] - x[3 * i + 1];
              final ez = x[3 * j + 2] - x[3 * i + 2];
              if (ex * ex + ey * ey + ez * ez < reach2) list.add(j);
            }
          }
        }
      }
      start[i + 1] = list.length;
    }
    return (start, Int32List.fromList(list));
  }
}
