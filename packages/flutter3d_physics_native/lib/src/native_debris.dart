/// Debris — the visual bodies — on the CPU and on the GPU: P9, phase 10.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:vector_math/vector_math.dart';

import 'bindings.dart' as c;
import 'gpu_bindings.dart' as g;
import 'native_particles.dart';

/// How debris moves. Eight substeps of four impulse passes keep a heap of a
/// thousand from sinking into itself by more than a tenth of a radius.
final class DebrisSettings {
  DebrisSettings({
    Vector3? gravity,
    this.friction = 0.6,
    this.restitution = 0.2,
    this.linearDamping = 0.0,
    this.angularDamping = 0.5,
    this.maxSpeed = 50.0,
    this.substeps = 8,
    this.iterations = 4,
  }) : gravity = gravity ?? Vector3(0.0, -9.81, 0.0);

  final Vector3 gravity;
  final double friction;

  /// Applied when two close faster than 1 m/s.
  final double restitution;

  /// Per second, as v / (1 + c dt).
  final double linearDamping;
  final double angularDamping;
  final double maxSpeed;
  final int substeps;
  final int iterations;
}

/// One ball of debris to add: a radius or mass of nought or less empties
/// its slot instead.
typedef DebrisBody = ({
  Vector3 position,
  Vector3 velocity,
  double radius,
  double mass,
});

/// A still shape debris lands on.
sealed class DebrisStatic {
  const DebrisStatic();
}

/// The plane of points p with p · [normal] = [offset]; debris stays on the
/// side [normal] points to.
final class DebrisPlane extends DebrisStatic {
  const DebrisPlane(this.normal, this.offset);
  final Vector3 normal;
  final double offset;
}

/// An unturned box.
final class DebrisBox extends DebrisStatic {
  const DebrisBox(this.centre, this.halfExtents);
  final Vector3 centre;
  final Vector3 halfExtents;
}

/// What a read gives: the step the bodies are from, counted from one, and
/// eight floats a slot — position xyz, orientation xyzw, radius.
typedef DebrisFrame = ({int step, Float32List bodies});

/// Debris slots, filled round and round: on the CPU ([NativeDebris]) or the
/// GPU ([GpuDebris]), the same passes. Visual, not the game's state.
abstract interface class DebrisSystem {
  int get capacity;

  /// Puts [bodies] into the next slots, the oldest going first, unturned.
  void add(List<DebrisBody> bodies);

  /// The still shapes, replacing the last: at most 64.
  void setStatics(List<DebrisStatic> statics);

  void step(DebrisSettings settings, double dt);

  /// The latest step's bodies not read yet, or null when there is none. On
  /// the GPU, without [wait], a frame late: the step queued last is still
  /// on its way.
  DebrisFrame? read({bool wait = true});

  void dispose();
}

Pointer<Float> _packBodies(List<DebrisBody> bodies) {
  final data = malloc<Float>(bodies.isEmpty ? 8 : bodies.length * 8);
  for (var i = 0; i < bodies.length; i++) {
    final b = bodies[i];
    data[i * 8] = b.position.x;
    data[i * 8 + 1] = b.position.y;
    data[i * 8 + 2] = b.position.z;
    data[i * 8 + 3] = b.velocity.x;
    data[i * 8 + 4] = b.velocity.y;
    data[i * 8 + 5] = b.velocity.z;
    data[i * 8 + 6] = b.radius;
    data[i * 8 + 7] = b.mass;
  }
  return data;
}

Pointer<Float> _packStatics(List<DebrisStatic> statics) {
  if (statics.length > c.debrisMaxStatics) {
    throw ArgumentError.value(statics.length, 'statics', 'more than 64');
  }
  final data = calloc<Float>(statics.isEmpty ? 8 : statics.length * 8);
  for (var i = 0; i < statics.length; i++) {
    final o = i * 8;
    switch (statics[i]) {
      case DebrisPlane(:final normal, :final offset):
        data[o] = normal.x;
        data[o + 1] = normal.y;
        data[o + 2] = normal.z;
        data[o + 3] = offset;
      case DebrisBox(:final centre, :final halfExtents):
        data[o] = centre.x;
        data[o + 1] = centre.y;
        data[o + 2] = centre.z;
        data[o + 4] = halfExtents.x;
        data[o + 5] = halfExtents.y;
        data[o + 6] = halfExtents.z;
        data[o + 7] = 1.0;
    }
  }
  return data;
}

/// Debris stepped by the core on the CPU: the reference for the GPU's, and
/// the fallback where there is none.
final class NativeDebris implements DebrisSystem, Finalizable {
  NativeDebris(int capacity) : _d = c.f3d_debris_create(capacity) {
    if (_d == nullptr) {
      throw ArgumentError.value(capacity, 'capacity', 'none, or no memory');
    }
    _finalizer.attach(this, _d.cast(), detach: this);
  }

  static final NativeFinalizer _finalizer = NativeFinalizer(
    Native.addressOf<NativeFunction<Void Function(Pointer<c.F3dDebris>)>>(
      c.f3d_debris_destroy,
    ).cast(),
  );

  Pointer<c.F3dDebris> _d;
  int _steps = 0;
  int _read = 0;

  Pointer<c.F3dDebris> get _live {
    if (_d == nullptr) throw StateError('this debris was disposed');
    return _d;
  }

  @override
  int get capacity => c.f3d_debris_capacity(_live);

  @override
  void add(List<DebrisBody> bodies) {
    final data = _packBodies(bodies);
    try {
      c.f3d_debris_add(_live, data, bodies.length);
    } finally {
      malloc.free(data);
    }
  }

  @override
  void setStatics(List<DebrisStatic> statics) {
    final data = _packStatics(statics);
    try {
      c.f3d_debris_set_statics(_live, data, statics.length);
    } finally {
      calloc.free(data);
    }
  }

  @override
  void step(DebrisSettings settings, double dt) {
    final s = calloc<c.F3dDebrisSettings>();
    try {
      final r = s.ref
        ..friction = settings.friction
        ..restitution = settings.restitution
        ..linear_damping = settings.linearDamping
        ..angular_damping = settings.angularDamping
        ..max_speed = settings.maxSpeed
        ..substeps = settings.substeps
        ..iterations = settings.iterations;
      for (var k = 0; k < 3; k++) {
        r.gravity[k] = settings.gravity[k];
      }
      c.f3d_debris_step(_live, s, dt);
      _steps++;
    } finally {
      calloc.free(s);
    }
  }

  @override
  DebrisFrame? read({bool wait = true}) {
    final n = capacity;
    if (_steps == _read) return null;
    final out = malloc<Float>(n * c.debrisFloats);
    try {
      c.f3d_debris_read(_live, out, n);
      _read = _steps;
      return (
        step: _steps,
        bodies: Float32List.fromList(out.asTypedList(n * c.debrisFloats)),
      );
    } finally {
      malloc.free(out);
    }
  }

  @override
  void dispose() {
    if (_d == nullptr) return;
    _finalizer.detach(this);
    c.f3d_debris_destroy(_d);
    _d = nullptr;
  }
}

/// [capacity] debris slots on a GPU.
extension NativeGpuDebris on NativeGpu {
  GpuDebris debris(int capacity) => GpuDebris.on(this, capacity);
}

/// Debris stepped on the GPU, read a frame late. The same passes as
/// [NativeDebris]: the same to the GPU's rounding until bodies meet, and
/// after that as a heap is — the same in what it does, not body for body.
final class GpuDebris implements DebrisSystem {
  GpuDebris.on(NativeGpu gpu, int capacity)
    : _gpu = gpu,
      _capacity = capacity,
      _d = g.f3d_gpu_debris_create(nativeGpuPointer(gpu), capacity) {
    if (_d == nullptr) {
      throw ArgumentError.value(
        capacity,
        'capacity',
        'none, too many, no memory, or a pass the GPU would not build',
      );
    }
  }

  final NativeGpu _gpu;
  final int _capacity;
  Pointer<g.F3dGpuDebris> _d;

  Pointer<g.F3dGpuDebris> get _live {
    if (_d == nullptr) throw StateError('this debris was disposed');
    nativeGpuPointer(_gpu);
    return _d;
  }

  @override
  int get capacity => _capacity;

  @override
  void add(List<DebrisBody> bodies) {
    final data = _packBodies(bodies);
    try {
      g.f3d_gpu_debris_add(_live, data, bodies.length);
    } finally {
      malloc.free(data);
    }
  }

  @override
  void setStatics(List<DebrisStatic> statics) {
    final data = _packStatics(statics);
    try {
      g.f3d_gpu_debris_set_statics(_live, data, statics.length);
    } finally {
      calloc.free(data);
    }
  }

  @override
  void step(DebrisSettings settings, double dt) {
    final s = calloc<g.F3dGpuDebrisSettings>();
    try {
      final r = s.ref
        ..friction = settings.friction
        ..restitution = settings.restitution
        ..linear_damping = settings.linearDamping
        ..angular_damping = settings.angularDamping
        ..max_speed = settings.maxSpeed
        ..substeps = settings.substeps
        ..iterations = settings.iterations;
      for (var k = 0; k < 3; k++) {
        r.gravity[k] = settings.gravity[k];
      }
      g.f3d_gpu_debris_step(_live, s, dt);
    } finally {
      calloc.free(s);
    }
  }

  @override
  DebrisFrame? read({bool wait = true}) {
    final out = malloc<Float>(_capacity * c.debrisFloats);
    try {
      final step = g.f3d_gpu_debris_read(_live, out, _capacity, wait ? 1 : 0);
      if (step == 0) return null;
      return (
        step: step,
        bodies: Float32List.fromList(
          out.asTypedList(_capacity * c.debrisFloats),
        ),
      );
    } finally {
      malloc.free(out);
    }
  }

  @override
  void dispose() {
    if (_d == nullptr) return;
    g.f3d_gpu_debris_destroy(_d);
    _d = nullptr;
  }
}
