/// The GPU passes natively, through wgpu-native — P9, phases 10 and 12.
///
/// The GPU library is its own, reached through `dart:ffi` alone: the
/// browser has none of it (`gpu_web.dart`), and there [NativeGpu.open] is
/// null. Its inputs are written into the core's memory as the CPU systems
/// write theirs — natively an address is a pointer — and its settings
/// structs are laid out as the core's.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'core/core.dart' as c;
import 'gpu_bindings.dart' as g;
import 'native_cloth.dart';
import 'native_debris.dart';
import 'native_fluid.dart';
import 'native_particles.dart';

Pointer<T> _at<T extends NativeType>(int address) =>
    Pointer<T>.fromAddress(address);

/// A GPU, through wgpu-native: what the visual passes run on.
final class NativeGpu {
  NativeGpu._(this._gpu);

  /// The best adapter there is, or null: no GPU, a driver wgpu cannot use,
  /// or no GPU library in this build — wgpu-native could not be fetched
  /// for the target, the platform has none, or this is the browser.
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
    final out = c.U8s.alloc(256);
    try {
      final n = g.f3d_gpu_adapter_name(_live, _at<Uint8>(out), 256);
      return String.fromCharCodes(out.copy(n < 255 ? n : 255));
    } finally {
      out.free();
    }
  }

  /// [capacity] particle slots on this GPU.
  GpuParticles particles(int capacity) => GpuParticles._(this, capacity);

  /// [capacity] debris slots on this GPU.
  GpuDebris debris(int capacity) => GpuDebris._(this, capacity);

  /// [mesh] as a cloth on this GPU.
  GpuCloth cloth(ClothMesh mesh) => GpuCloth._(this, mesh);

  /// Room for [capacity] particles of fluid on this GPU, [spacing] apart
  /// at rest.
  GpuFluid fluid(int capacity, double spacing) =>
      GpuFluid._(this, capacity, spacing);

  /// Frees the device. Its systems go first.
  void dispose() {
    if (_gpu == nullptr) return;
    g.f3d_gpu_destroy(_gpu);
    _gpu = nullptr;
  }
}

String _gpuRefused(String what) =>
    '$what, no memory, or a pass the GPU would not build';

/// Particles stepped by a compute shader that does what [NativeParticles]
/// does, step for step: the same to a GPU's own rounding.
final class GpuParticles implements ParticleSystem {
  GpuParticles._(this._gpu, int capacity)
    : _capacity = capacity,
      _p = g.f3d_gpu_particles_create(_gpu._live, capacity) {
    if (_p == nullptr) {
      throw ArgumentError.value(
        capacity,
        'capacity',
        _gpuRefused('none, too many'),
      );
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
    final data = packParticles(particles);
    try {
      g.f3d_gpu_particles_emit(_live, _at<Float>(data), particles.length);
    } finally {
      data.free();
    }
  }

  @override
  void step(ParticleForces forces, double dt, {int steps = 1}) {
    final f = writeParticleForces(forces);
    try {
      g.f3d_gpu_particles_step(
        _live,
        _at<g.F3dGpuParticleForces>(f),
        dt,
        steps,
      );
    } finally {
      c.coreFree(f);
    }
  }

  @override
  Float32List read() {
    final out = c.F32s.alloc(_capacity * 4);
    try {
      final n = g.f3d_gpu_particles_read(_live, _at<Float>(out), _capacity);
      if (n == 0) throw StateError('the GPU could not be read');
      return out.copy(_capacity * 4);
    } finally {
      out.free();
    }
  }

  @override
  void dispose() {
    if (_p == nullptr) return;
    g.f3d_gpu_particles_destroy(_p);
    _p = nullptr;
  }
}

/// Debris stepped on the GPU, read a frame late. The same passes as
/// [NativeDebris]: the same to the GPU's rounding until bodies meet, and
/// after that as a heap is — the same in what it does, not body for body.
final class GpuDebris implements DebrisSystem {
  GpuDebris._(this._gpu, int capacity)
    : _capacity = capacity,
      _d = g.f3d_gpu_debris_create(_gpu._live, capacity) {
    if (_d == nullptr) {
      throw ArgumentError.value(
        capacity,
        'capacity',
        _gpuRefused('none, too many'),
      );
    }
  }

  final NativeGpu _gpu;
  final int _capacity;
  Pointer<g.F3dGpuDebris> _d;

  Pointer<g.F3dGpuDebris> get _live {
    if (_d == nullptr) throw StateError('this debris was disposed');
    _gpu._live;
    return _d;
  }

  @override
  int get capacity => _capacity;

  @override
  void add(List<DebrisBody> bodies) {
    final data = packDebrisBodies(bodies);
    try {
      g.f3d_gpu_debris_add(_live, _at<Float>(data), bodies.length);
    } finally {
      data.free();
    }
  }

  @override
  void setStatics(List<DebrisStatic> statics) {
    final data = packDebrisStatics(statics);
    try {
      g.f3d_gpu_debris_set_statics(_live, _at<Float>(data), statics.length);
    } finally {
      data.free();
    }
  }

  @override
  void step(DebrisSettings settings, double dt) {
    final s = writeDebrisSettings(settings);
    try {
      g.f3d_gpu_debris_step(_live, _at<g.F3dGpuDebrisSettings>(s), dt);
    } finally {
      c.coreFree(s);
    }
  }

  @override
  DebrisFrame? read({bool wait = true}) {
    final out = c.F32s.alloc(_capacity * c.debrisFloats);
    try {
      final step = g.f3d_gpu_debris_read(
        _live,
        _at<Float>(out),
        _capacity,
        wait ? 1 : 0,
      );
      if (step == 0) return null;
      return (step: step, bodies: out.copy(_capacity * c.debrisFloats));
    } finally {
      out.free();
    }
  }

  @override
  void dispose() {
    if (_d == nullptr) return;
    g.f3d_gpu_debris_destroy(_d);
    _d = nullptr;
  }
}

/// Cloth stepped on the GPU, a dispatch a colour, read a frame late. The
/// constraints are coloured by the core, so it solves what [NativeCloth]
/// solves in the same order of colours: the same to the GPU's rounding,
/// until folds and wrinkles take the two their own ways.
final class GpuCloth implements ClothSystem {
  GpuCloth._(this._gpu, ClothMesh mesh)
    : _points = mesh.points.length,
      _c = _upload(_gpu, mesh);

  static Pointer<g.F3dGpuCloth> _upload(NativeGpu gpu, ClothMesh mesh) {
    final core = createCoreCloth(mesh);
    final packed = ClothPacked(mesh);
    final edges = c.f3d_cloth_edge_count(core);
    final colours = c.f3d_cloth_colour_count(core);
    final pairs = c.U32s.alloc(edges == 0 ? 2 : edges * 2);
    final rest = c.F32s.alloc(edges == 0 ? 1 : edges);
    final compliance = c.F32s.alloc(edges == 0 ? 1 : edges);
    final start = c.U32s.alloc(colours + 1);
    try {
      c.f3d_cloth_edges(core, pairs, rest, compliance, start);
      final cloth = g.f3d_gpu_cloth_create(
        gpu._live,
        _at<Float>(packed.points),
        mesh.points.length,
        _at<Uint32>(pairs),
        _at<Float>(rest),
        _at<Float>(compliance),
        edges,
        _at<Uint32>(start),
        colours,
      );
      if (cloth == nullptr) {
        throw ArgumentError.value(mesh, 'mesh', _gpuRefused('too large'));
      }
      return cloth;
    } finally {
      c.f3d_cloth_destroy(core);
      packed.free();
      pairs.free();
      rest.free();
      compliance.free();
      start.free();
    }
  }

  final NativeGpu _gpu;
  final int _points;
  Pointer<g.F3dGpuCloth> _c;

  Pointer<g.F3dGpuCloth> get _live {
    if (_c == nullptr) throw StateError('this cloth was disposed');
    _gpu._live;
    return _c;
  }

  @override
  int get pointCount => _points;

  @override
  void setBalls(List<({Vector3 centre, double radius})> balls) {
    final data = packClothBalls(balls);
    try {
      g.f3d_gpu_cloth_set_balls(_live, _at<Float>(data), balls.length);
    } finally {
      data.free();
    }
  }

  @override
  void movePoint(int index, Vector3 at) {
    g.f3d_gpu_cloth_move_point(_live, index, at.x, at.y, at.z);
  }

  @override
  void step(ClothSettings settings, double dt) {
    final s = writeClothSettings(settings);
    try {
      g.f3d_gpu_cloth_step(_live, _at<g.F3dGpuClothSettings>(s), dt);
    } finally {
      c.coreFree(s);
    }
  }

  @override
  ClothFrame? read({bool wait = true}) {
    final out = c.F32s.alloc(_points * 4);
    try {
      final step = g.f3d_gpu_cloth_read(
        _live,
        _at<Float>(out),
        _points,
        wait ? 1 : 0,
      );
      if (step == 0) return null;
      return (step: step, points: out.copy(_points * 4));
    } finally {
      out.free();
    }
  }

  @override
  void dispose() {
    if (_c == nullptr) return;
    g.f3d_gpu_cloth_destroy(_c);
    _c = nullptr;
  }
}

/// Fluid stepped on the GPU, read a frame late: the same passes as
/// [NativeFluid] to the GPU's rounding, until its splashes go their own
/// way.
final class GpuFluid implements FluidSystem {
  GpuFluid._(this._gpu, int capacity, double spacing)
    : _capacity = capacity,
      _f = g.f3d_gpu_fluid_create(_gpu._live, capacity, spacing) {
    if (_f == nullptr) {
      throw ArgumentError(_gpuRefused('no room, a spacing not above nought'));
    }
  }

  final NativeGpu _gpu;
  final int _capacity;
  Pointer<g.F3dGpuFluid> _f;
  int _count = 0;

  Pointer<g.F3dGpuFluid> get _live {
    if (_f == nullptr) throw StateError('this fluid was disposed');
    _gpu._live;
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
    final data = packFluidParticles(particles);
    try {
      g.f3d_gpu_fluid_add(_live, _at<Float>(data), particles.length);
      _count = (_count + particles.length).clamp(0, _capacity);
    } finally {
      data.free();
    }
  }

  @override
  void step(FluidSettings settings, double dt) {
    final s = writeFluidSettings(settings);
    try {
      g.f3d_gpu_fluid_step(_live, _at<g.F3dGpuFluidSettings>(s), dt);
    } finally {
      c.coreFree(s);
    }
  }

  @override
  FluidFrame? read({bool wait = true}) {
    final out = c.F32s.alloc(_count == 0 ? 4 : _count * 4);
    try {
      final step = g.f3d_gpu_fluid_read(
        _live,
        _at<Float>(out),
        _count,
        wait ? 1 : 0,
      );
      if (step == 0) return null;
      return (step: step, particles: out.copy(_count * 4));
    } finally {
      out.free();
    }
  }

  @override
  void dispose() {
    if (_f == nullptr) return;
    g.f3d_gpu_fluid_destroy(_f);
    _f = nullptr;
  }
}
