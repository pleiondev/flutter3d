/// Fluid — water as particles — on the CPU and on the GPU: P9, phase 10.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:vector_math/vector_math.dart';

import 'bindings.dart' as c;
import 'gpu_bindings.dart' as g;
import 'native_particles.dart';

/// How fluid moves, inside the tank from [tankMin] to [tankMax].
final class FluidSettings {
  FluidSettings({
    required this.tankMin,
    required this.tankMax,
    Vector3? gravity,
    this.viscosity = 0.01,
    this.relaxation = 10.0,
    this.substeps = 2,
    this.iterations = 4,
  }) : gravity = gravity ?? Vector3(0.0, -9.81, 0.0);

  final Vector3 gravity;

  /// The tank's corners: no particle centre comes nearer its walls than
  /// half the spacing.
  final Vector3 tankMin;
  final Vector3 tankMax;

  /// XSPH: how far a particle's velocity goes to its neighbours' a
  /// substep.
  final double viscosity;

  /// Softens the density constraint; larger is softer and steadier.
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
abstract interface class FluidSystem {
  int get capacity;

  /// Particles in the tank so far, up to [capacity].
  int get count;

  /// The density at rest, particles of mass one per cubic metre.
  double get restDensity;

  /// Puts [particles] into the next slots, round and round once full.
  void add(List<FluidParticle> particles);

  void step(FluidSettings settings, double dt);

  /// The latest step's particles not read yet, or null when there is
  /// none. On the GPU, without [wait], a frame late.
  FluidFrame? read({bool wait = true});

  void dispose();
}

Pointer<Float> _packParticles(List<FluidParticle> particles) {
  final data = malloc<Float>(particles.isEmpty ? 6 : particles.length * 6);
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

/// Fluid stepped by the core on the CPU: the reference for the GPU's, and
/// the fallback where there is none.
final class NativeFluid implements FluidSystem, Finalizable {
  /// Room for [capacity] particles [spacing] apart at rest.
  NativeFluid(int capacity, double spacing)
    : _f = c.f3d_fluid_create(capacity, spacing) {
    if (_f == nullptr) {
      throw ArgumentError('no room, a spacing not above nought, or no memory');
    }
    _finalizer.attach(this, _f.cast(), detach: this);
  }

  static final NativeFinalizer _finalizer = NativeFinalizer(
    Native.addressOf<NativeFunction<Void Function(Pointer<c.F3dFluid>)>>(
      c.f3d_fluid_destroy,
    ).cast(),
  );

  Pointer<c.F3dFluid> _f;
  int _count = 0;
  int _steps = 0;
  int _read = 0;

  Pointer<c.F3dFluid> get _live {
    if (_f == nullptr) throw StateError('this fluid was disposed');
    return _f;
  }

  @override
  int get capacity => c.f3d_fluid_capacity(_live);

  @override
  int get count => _count;

  @override
  double get restDensity => c.f3d_fluid_rest_density(_live);

  @override
  void add(List<FluidParticle> particles) {
    final data = _packParticles(particles);
    try {
      c.f3d_fluid_add(_live, data, particles.length);
      _count = (_count + particles.length).clamp(0, capacity);
    } finally {
      malloc.free(data);
    }
  }

  @override
  void step(FluidSettings settings, double dt) {
    final s = calloc<c.F3dFluidSettings>();
    try {
      final r = s.ref
        ..viscosity = settings.viscosity
        ..relaxation = settings.relaxation
        ..substeps = settings.substeps
        ..iterations = settings.iterations;
      for (var k = 0; k < 3; k++) {
        r.gravity[k] = settings.gravity[k];
        r.tank_min[k] = settings.tankMin[k];
        r.tank_max[k] = settings.tankMax[k];
      }
      c.f3d_fluid_step(_live, s, dt);
      _steps++;
    } finally {
      calloc.free(s);
    }
  }

  @override
  FluidFrame? read({bool wait = true}) {
    final live = _live;
    if (_steps == _read) return null;
    final out = malloc<Float>(_count == 0 ? 4 : _count * 4);
    try {
      c.f3d_fluid_read(live, out, _count);
      _read = _steps;
      return (
        step: _steps,
        particles: Float32List.fromList(out.asTypedList(_count * 4)),
      );
    } finally {
      malloc.free(out);
    }
  }

  @override
  void dispose() {
    if (_f == nullptr) return;
    _finalizer.detach(this);
    c.f3d_fluid_destroy(_f);
    _f = nullptr;
  }
}

/// Room for [capacity] particles of fluid on a GPU, [spacing] apart at
/// rest.
extension NativeGpuFluid on NativeGpu {
  GpuFluid fluid(int capacity, double spacing) =>
      GpuFluid.on(this, capacity, spacing);
}

/// Fluid stepped on the GPU, read a frame late: the same passes as
/// [NativeFluid] to the GPU's rounding, until its splashes go their own
/// way.
final class GpuFluid implements FluidSystem {
  GpuFluid.on(NativeGpu gpu, int capacity, double spacing)
    : _gpu = gpu,
      _capacity = capacity,
      _f = g.f3d_gpu_fluid_create(nativeGpuPointer(gpu), capacity, spacing) {
    if (_f == nullptr) {
      throw ArgumentError(
        'no room, a spacing not above nought, no memory, or a pass the GPU '
        'would not build',
      );
    }
  }

  final NativeGpu _gpu;
  final int _capacity;
  Pointer<g.F3dGpuFluid> _f;
  int _count = 0;

  Pointer<g.F3dGpuFluid> get _live {
    if (_f == nullptr) throw StateError('this fluid was disposed');
    nativeGpuPointer(_gpu);
    return _f;
  }

  @override
  int get capacity => _capacity;

  @override
  int get count => _count;

  @override
  double get restDensity => g.f3d_gpu_fluid_rest_density(_live);

  @override
  void add(List<FluidParticle> particles) {
    final data = _packParticles(particles);
    try {
      g.f3d_gpu_fluid_add(_live, data, particles.length);
      _count = (_count + particles.length).clamp(0, _capacity);
    } finally {
      malloc.free(data);
    }
  }

  @override
  void step(FluidSettings settings, double dt) {
    final s = calloc<g.F3dGpuFluidSettings>();
    try {
      final r = s.ref
        ..viscosity = settings.viscosity
        ..relaxation = settings.relaxation
        ..substeps = settings.substeps
        ..iterations = settings.iterations;
      for (var k = 0; k < 3; k++) {
        r.gravity[k] = settings.gravity[k];
        r.tank_min[k] = settings.tankMin[k];
        r.tank_max[k] = settings.tankMax[k];
      }
      g.f3d_gpu_fluid_step(_live, s, dt);
    } finally {
      calloc.free(s);
    }
  }

  @override
  FluidFrame? read({bool wait = true}) {
    final out = malloc<Float>(_count == 0 ? 4 : _count * 4);
    try {
      final step = g.f3d_gpu_fluid_read(_live, out, _count, wait ? 1 : 0);
      if (step == 0) return null;
      return (
        step: step,
        particles: Float32List.fromList(out.asTypedList(_count * 4)),
      );
    } finally {
      malloc.free(out);
    }
  }

  @override
  void dispose() {
    if (_f == nullptr) return;
    g.f3d_gpu_fluid_destroy(_f);
    _f = nullptr;
  }
}
