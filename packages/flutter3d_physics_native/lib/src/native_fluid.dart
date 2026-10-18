/// Fluid — water as particles — on the CPU: P9, phase 10.
library;

import 'dart:typed_data';

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:vector_math/vector_math.dart';

import 'core/core.dart' as c;
import 'native_world.dart';

/// How fluid moves, inside the tank from [tankMin] to [tankMax].
///
/// Its gravity is its [world]'s, read when the settings are made, or
/// [standardGravityVector] without one — see `ClothSettings`, which is made
/// the same way.
final class FluidSettings {
  /// Settings for a tank from [tankMin] to [tankMax], whose [gravity] is
  /// [world]'s when not given, or [standardGravityVector] with neither; the
  /// rest take the defaults shown.
  FluidSettings({
    required this.tankMin,
    required this.tankMax,
    NativeWorld? world,
    Vector3? gravity,
    this.viscosity = 0.01,
    this.relaxation = 10.0,
    this.substeps = 2,
    this.iterations = 4,
  }) : gravity = gravity ?? world?.gravity ?? standardGravityVector;

  /// A copy with the given fields replaced. A `clear…` flag resets that
  /// nullable field to null, which passing null cannot say.
  // ignore: avoid-incomplete-copy-with, the world only seeds the defaults and is not kept
  FluidSettings copyWith({
    Vector3? tankMin,
    Vector3? tankMax,
    Vector3? gravity,
    double? viscosity,
    double? relaxation,
    int? substeps,
    int? iterations,
    bool clearGravity = false,
  }) => FluidSettings(
    tankMin: tankMin ?? this.tankMin,
    tankMax: tankMax ?? this.tankMax,
    gravity: clearGravity ? null : (gravity ?? this.gravity),
    viscosity: viscosity ?? this.viscosity,
    relaxation: relaxation ?? this.relaxation,
    substeps: substeps ?? this.substeps,
    iterations: iterations ?? this.iterations,
  );

  /// Gravity, m/s².
  final Vector3 gravity;

  /// The tank's corners: no particle centre comes nearer its walls than
  /// half the spacing.
  final Vector3 tankMin;

  /// The tank's highest corner, in metres, opposite [tankMin].
  final Vector3 tankMax;

  /// XSPH: how far a particle's velocity goes to its neighbours' a
  /// substep: a unitless fraction, 0..1.
  final double viscosity;

  /// Softens the density constraint; larger is softer and steadier. Added
  /// to the constraint's squared gradient, so per square metre.
  final double relaxation;

  /// How many substeps a step is cut into; nought is taken as one.
  final int substeps;

  /// How many density passes a substep makes; nought is taken as one.
  final int iterations;
}

/// One particle to add.
///
/// A class rather than a record, so it can carry more in a minor without
/// breaking a backend that mixes the system in.
final class FluidParticle {
  /// A particle at [position] moving at [velocity].
  const FluidParticle({required this.position, required this.velocity});

  /// Where, in metres.
  final Vector3 position;

  /// How fast, in metres a second.
  final Vector3 velocity;

  /// Equal to another with the same fields, as the record it was compared.
  @override
  bool operator ==(Object other) =>
      other is FluidParticle &&
      other.position == position &&
      other.velocity == velocity;

  @override
  int get hashCode => Object.hash(position, velocity);

  @override
  String toString() =>
      'FluidParticle(position: $position, velocity: $velocity)';
}

/// What a read gives: the step the particles are from, counted from one,
/// and four floats a particle — position xyz, density over rest density.
///
/// A class rather than a record, so it can carry more in a minor without
/// breaking a backend that mixes the system in.
final class FluidFrame {
  /// The particles of step [step], four floats a particle.
  const FluidFrame({required this.step, required this.particles});

  /// The step, counted from one.
  final int step;

  /// Four floats a particle: position xyz in metres, density over rest
  /// density as a ratio.
  final Float32List particles;

  /// Equal to another with the same fields, as the record it was compared.
  @override
  bool operator ==(Object other) =>
      other is FluidFrame && other.step == step && other.particles == particles;

  @override
  int get hashCode => Object.hash(step, particles);

  @override
  String toString() => 'FluidFrame(step: $step, particles: $particles)';
}

/// Water as particles: on the CPU ([NativeFluid]), or on a GPU through the
/// hardware layer (`FluidWorkload` in `flutter3d_effects`, from
/// [fluidKernels]), the same passes. Visual, not the game's state.
///
/// **Mixed in, not implemented**, outside this library: a `base` type, so a
/// member added in a 1.x release arrives with a body and nothing that mixes
/// it in has to change.
abstract base mixin class FluidSystem {
  /// How many particles the tank has room for.
  int get capacity;

  /// Particles in the tank so far, up to [capacity].
  int get count;

  /// The density at rest, particles of mass one per cubic metre.
  double get restDensity;

  /// Puts [particles] into the next slots, round and round once full.
  void add(List<FluidParticle> particles);

  /// One step of the tank, as [FluidSystemStep] says.
  void step(FluidSystemStep step);

  /// The latest step's particles not read yet; null when there is
  /// none (absent, not an error). Stepped on a GPU, a frame or two late.
  FluidFrame? read({bool wait = true});

  /// Frees what the tank holds; it is not to be used after.
  void dispose();
}

/// What [FluidSystem.step] is handed: the settings and the step's length in
/// seconds.
///
/// **One object, so a minor can hand a tank more** — a moving container, a
/// stirring — without breaking one written against 1.0. **Reusable**: a
/// tank stepped every frame keeps one and sets it before the call; the tank
/// reads it during the call and does not keep it.
final class FluidSystemStep {
  /// A step of [dt] seconds with [settings].
  FluidSystemStep({required this.settings, required this.dt});

  /// How the liquid behaves.
  FluidSettings settings;

  /// The step, in seconds.
  double dt;
}

/// [particles] as `f3d_fluid_add` takes them, six floats apiece, in a block
/// the caller frees.
c.F32s packFluidParticles(List<FluidParticle> particles) {
  final data = c.F32s.alloc(particles.isEmpty ? 6 : particles.length * 6);
  for (var i = 0; i < particles.length; i++) {
    final p = particles[i];
    data[i * 6] = p.position.x;
    data[i * 6 + 1] = p.position.y;
    data[i * 6 + 2] = p.position.z;
    data[i * 6 + 3] = p.velocity.x;
    data[i * 6 + 4] = p.velocity.y;
    data[i * 6 + 5] = p.velocity.z;
  }
  return data;
}

/// [settings] as the core's `F3dFluidSettings` in a block of the core's memory the
/// caller frees.
int writeFluidSettings(FluidSettings settings) {
  final s = c.coreAlloc(c.F3dFluidSettingsLayout.size);
  for (var k = 0; k < 3; k++) {
    c.writeF32(
      s + c.F3dFluidSettingsLayout.gravity + k * 4,
      settings.gravity[k],
    );
    c.writeF32(
      s + c.F3dFluidSettingsLayout.tankMin + k * 4,
      settings.tankMin[k],
    );
    c.writeF32(
      s + c.F3dFluidSettingsLayout.tankMax + k * 4,
      settings.tankMax[k],
    );
  }
  c.writeF32(s + c.F3dFluidSettingsLayout.viscosity, settings.viscosity);
  c.writeF32(s + c.F3dFluidSettingsLayout.relaxation, settings.relaxation);
  c.writeU32(s + c.F3dFluidSettingsLayout.substeps, settings.substeps);
  c.writeU32(s + c.F3dFluidSettingsLayout.iterations, settings.iterations);
  return s;
}

/// Fluid stepped by the core on the CPU: the reference for the GPU's, and
/// the fallback where there is none.
final class NativeFluid implements FluidSystem {
  /// Room for [capacity] particles [spacing] apart at rest.
  NativeFluid(int capacity, double spacing)
    : _f = c.f3d_fluid_create(capacity, spacing) {
    if (_f == 0) {
      throw ArgumentError('no room, a spacing not above nought, or no memory');
    }
    _finalizer.attach(this, _f, detach: this);
  }

  static final Finalizer<int> _finalizer = Finalizer<int>(c.f3d_fluid_destroy);

  int _f;
  int _count = 0;
  int _steps = 0;
  int _read = 0;

  int get _live {
    if (_f == 0) throw StateError('this fluid was disposed');
    return _f;
  }

  @override
  int get capacity => c.f3d_fluid_capacity(_live);

  @override
  int get count => _count;

  /// The density at rest, particles of mass one per cubic metre.
  @override
  double get restDensity => c.f3d_fluid_rest_density(_live);

  @override
  void add(List<FluidParticle> particles) {
    final data = packFluidParticles(particles);
    try {
      c.f3d_fluid_add(_live, data, particles.length);
      _count = (_count + particles.length).clamp(0, capacity);
    } finally {
      data.free();
    }
  }

  @override
  void step(FluidSystemStep request) {
    final settings = request.settings;
    final dt = request.dt;
    final s = writeFluidSettings(settings);
    try {
      c.f3d_fluid_step(_live, s, dt);
      _steps++;
    } finally {
      c.coreFree(s);
    }
  }

  @override
  FluidFrame? read({bool wait = true}) {
    final live = _live;
    if (_steps == _read) return null;
    final out = c.F32s.alloc(_count == 0 ? 4 : _count * 4);
    try {
      c.f3d_fluid_read(live, out, _count);
      _read = _steps;
      return FluidFrame(step: _steps, particles: out.copy(_count * 4));
    } finally {
      out.free();
    }
  }

  @override
  void dispose() {
    if (_f == 0) return;
    _finalizer.detach(this);
    c.f3d_fluid_destroy(_f);
    _f = 0;
  }
}
