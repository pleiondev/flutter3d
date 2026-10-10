/// Fluid — water as particles — on the CPU and on the GPU: P9, phase 10.
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

  final Vector3 gravity;

  /// The tank's corners: no particle centre comes nearer its walls than
  /// half the spacing.
  final Vector3 tankMin;
  final Vector3 tankMax;

  /// XSPH: how far a particle's velocity goes to its neighbours' a
  /// substep: a unitless fraction, 0..1.
  final double viscosity;

  /// Softens the density constraint; larger is softer and steadier. Added
  /// to the constraint's squared gradient, so per square metre.
  final double relaxation;
  final int substeps;
  final int iterations;
}

/// One particle to add.
typedef FluidParticle = ({Vector3 position, Vector3 velocity});

/// What a read gives: the step the particles are from, counted from one,
/// and four floats a particle — position xyz, density over rest density.
typedef FluidFrame = ({int step, Float32List particles});

/// Water as particles: on the CPU ([NativeFluid]) or the GPU
/// ([GpuFluid]), the same passes. Visual, not the game's state.
///
/// **Mixed in, not implemented**, outside this library: a `base` type, so a
/// member added in a 1.x release arrives with a body and nothing that mixes
/// it in has to change.
abstract base mixin class FluidSystem {
  int get capacity;

  /// Particles in the tank so far, up to [capacity].
  int get count;

  /// The density at rest, particles of mass one per cubic metre.
  double get restDensity;

  /// Puts [particles] into the next slots, round and round once full.
  void add(List<FluidParticle> particles);

  void step(FluidSettings settings, double dt);

  /// The latest step's particles not read yet; null when there is
  /// none (absent, not an error). On the GPU, without [wait], a frame late.
  FluidFrame? read({bool wait = true});

  void dispose();
}

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

/// [settings] as the core's `F3dFluidSettings` — and the GPU's, laid out
/// the same — in a block of the core's memory the caller frees.
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
  void step(FluidSettings settings, double dt) {
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
      return (step: _steps, particles: out.copy(_count * 4));
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
