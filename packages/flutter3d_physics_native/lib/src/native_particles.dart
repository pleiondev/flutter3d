/// Particles, on the CPU and on the GPU — P9, phase 10.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:vector_math/vector_math.dart';

import 'bindings.dart' as c;
import 'gpu_bindings.dart' as g;

/// How particles move: gravity, the wind they drift towards at [drag] per
/// second, and a floor at [floorY] they bounce off with [restitution] and
/// lose [friction] of their sliding speed on.
final class ParticleForces {
  ParticleForces({
    Vector3? gravity,
    Vector3? wind,
    this.drag = 0.0,
    this.floorY = double.negativeInfinity,
    this.restitution = 0.0,
    this.friction = 0.0,
  }) : gravity = gravity ?? Vector3(0.0, -9.81, 0.0),
       wind = wind ?? Vector3.zero();

  final Vector3 gravity;
  final Vector3 wind;
  final double drag;
  final double floorY;
  final double restitution;
  final double friction;
}

/// One particle to emit.
typedef Particle = ({Vector3 position, Vector3 velocity, double life});

/// A set of particle slots, filled round and round, that fall, drift,
/// bounce and die: on the CPU ([NativeParticles]) or the GPU
/// ([GpuParticles]), the same steps. Visual, not the game's state.
abstract interface class ParticleSystem {
  /// How many slots there are.
  int get capacity;

  /// Puts [particles] into the next slots, the oldest going first.
  void emit(List<Particle> particles);

  /// Steps every living particle [steps] times by [dt].
  void step(ParticleForces forces, double dt, {int steps = 1});

  /// Every slot: position xyz and the life it has left, four floats apiece;
  /// nought or less is dead.
  Float32List read();

  /// Frees the slots.
  void dispose();
}

Pointer<Float> _pack(List<Particle> particles) {
  final data = malloc<Float>(particles.isEmpty ? 7 : particles.length * 7);
  for (var i = 0; i < particles.length; i++) {
    final p = particles[i];
    data[i * 7] = p.position.x;
    data[i * 7 + 1] = p.position.y;
    data[i * 7 + 2] = p.position.z;
    data[i * 7 + 3] = p.velocity.x;
    data[i * 7 + 4] = p.velocity.y;
    data[i * 7 + 5] = p.velocity.z;
    data[i * 7 + 6] = p.life;
  }
  return data;
}

/// Particles stepped by the core on the CPU: the reference for the GPU's,
/// and the fallback where there is none.
final class NativeParticles implements ParticleSystem, Finalizable {
  NativeParticles(int capacity) : _p = c.f3d_particles_create(capacity) {
    if (_p == nullptr) {
      throw ArgumentError.value(capacity, 'capacity', 'none, or no memory');
    }
    _finalizer.attach(this, _p.cast(), detach: this);
  }

  static final NativeFinalizer _finalizer = NativeFinalizer(
    Native.addressOf<NativeFunction<Void Function(Pointer<c.F3dParticles>)>>(
      c.f3d_particles_destroy,
    ).cast(),
  );

  Pointer<c.F3dParticles> _p;

  Pointer<c.F3dParticles> get _live {
    if (_p == nullptr) throw StateError('these particles were disposed');
    return _p;
  }

  @override
  int get capacity => c.f3d_particles_capacity(_live);

  @override
  void emit(List<Particle> particles) {
    final data = _pack(particles);
    try {
      c.f3d_particles_emit(_live, data, particles.length);
    } finally {
      malloc.free(data);
    }
  }

  @override
  void step(ParticleForces forces, double dt, {int steps = 1}) {
    final f = calloc<c.F3dParticleForces>();
    try {
      final r = f.ref
        ..drag = forces.drag
        ..floor_y = forces.floorY == double.negativeInfinity
            ? -3.4e38
            : forces.floorY
        ..restitution = forces.restitution
        ..friction = forces.friction;
      for (var k = 0; k < 3; k++) {
        r.gravity[k] = forces.gravity[k];
        r.wind[k] = forces.wind[k];
      }
      for (var s = 0; s < steps; s++) {
        c.f3d_particles_step(_live, f, dt);
      }
    } finally {
      calloc.free(f);
    }
  }

  @override
  Float32List read() {
    final n = capacity;
    final out = malloc<Float>(n * c.particleFloats);
    try {
      c.f3d_particles_read(_live, out, n);
      return Float32List.fromList(out.asTypedList(n * c.particleFloats));
    } finally {
      malloc.free(out);
    }
  }

  @override
  void dispose() {
    if (_p == nullptr) return;
    _finalizer.detach(this);
    c.f3d_particles_destroy(_p);
    _p = nullptr;
  }
}

/// A GPU, through wgpu-native: what the visual passes run on.
final class NativeGpu {
  NativeGpu._(this._gpu);

  /// The best adapter there is, or null: no GPU, a driver wgpu cannot use,
  /// or no GPU library in this build — wgpu-native could not be fetched
  /// for the target, or the platform has none.
  static NativeGpu? open() {
    try {
      if (g.f3d_gpu_abi_version() != g.gpuAbiVersion) return null;
      final gpu = g.f3d_gpu_create();
      return gpu == nullptr ? null : NativeGpu._(gpu);
    } on ArgumentError {
      // The asset is not there: no GPU library in this build.
      return null;
    }
  }

  Pointer<g.F3dGpu> _gpu;

  Pointer<g.F3dGpu> get _live {
    if (_gpu == nullptr) throw StateError('this GPU was disposed');
    return _gpu;
  }

  /// The adapter's name.
  String get adapterName {
    final out = malloc<Uint8>(256);
    try {
      final n = g.f3d_gpu_adapter_name(_live, out, 256);
      return String.fromCharCodes(out.asTypedList(n < 255 ? n : 255));
    } finally {
      malloc.free(out);
    }
  }

  /// [capacity] particle slots on this GPU.
  GpuParticles particles(int capacity) => GpuParticles._(this, capacity);

  /// Frees the device. Its particles go first.
  void dispose() {
    if (_gpu == nullptr) return;
    g.f3d_gpu_destroy(_gpu);
    _gpu = nullptr;
  }
}

/// Particles stepped by a compute shader that does what [NativeParticles]
/// does, step for step: the same to a GPU's own rounding.
final class GpuParticles implements ParticleSystem {
  GpuParticles._(this._gpu, int capacity)
    : _capacity = capacity,
      _p = g.f3d_gpu_particles_create(_gpu._live, capacity) {
    if (_p == nullptr) {
      throw ArgumentError.value(capacity, 'capacity', 'none, or no memory');
    }
  }

  final NativeGpu _gpu;
  final int _capacity;
  Pointer<g.F3dGpuParticles> _p;

  Pointer<g.F3dGpuParticles> get _live {
    if (_p == nullptr) throw StateError('these particles were disposed');
    _gpu._live;
    return _p;
  }

  @override
  int get capacity => _capacity;

  @override
  void emit(List<Particle> particles) {
    final data = _pack(particles);
    try {
      g.f3d_gpu_particles_emit(_live, data, particles.length);
    } finally {
      malloc.free(data);
    }
  }

  @override
  void step(ParticleForces forces, double dt, {int steps = 1}) {
    final f = calloc<g.F3dGpuParticleForces>();
    try {
      final r = f.ref
        ..drag = forces.drag
        ..floor_y = forces.floorY == double.negativeInfinity
            ? -3.4e38
            : forces.floorY
        ..restitution = forces.restitution
        ..friction = forces.friction;
      for (var k = 0; k < 3; k++) {
        r.gravity[k] = forces.gravity[k];
        r.wind[k] = forces.wind[k];
      }
      g.f3d_gpu_particles_step(_live, f, dt, steps);
    } finally {
      calloc.free(f);
    }
  }

  @override
  Float32List read() {
    final out = malloc<Float>(_capacity * 4);
    try {
      final n = g.f3d_gpu_particles_read(_live, out, _capacity);
      if (n == 0) throw StateError('the GPU could not be read');
      return Float32List.fromList(out.asTypedList(_capacity * 4));
    } finally {
      malloc.free(out);
    }
  }

  @override
  void dispose() {
    if (_p == nullptr) return;
    g.f3d_gpu_particles_destroy(_p);
    _p = nullptr;
  }
}
