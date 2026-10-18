/// Debris — the visual bodies — on the CPU: P9, phase 10.
library;

import 'dart:typed_data';

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:vector_math/vector_math.dart';

import 'core/core.dart' as c;
import 'native_world.dart';

/// How debris moves. Eight substeps of four impulse passes keep a heap of a
/// thousand from sinking into itself by more than a tenth of a radius.
///
/// The gravity is the [world]'s, read when the settings are made, or
/// [standardGravityVector] without one — see `ClothSettings`.
final class DebrisSettings {
  /// Settings whose [gravity] is [world]'s when not given, or
  /// [standardGravityVector] with neither; the rest take the defaults shown.
  DebrisSettings({
    NativeWorld? world,
    Vector3? gravity,
    this.friction = MaterialCatalog.defaultFriction,
    this.restitution = 0.2,
    this.linearDamping = 0.0,
    this.angularDamping = 0.5,
    this.maxSpeed = 50.0,
    this.substeps = 8,
    this.iterations = 4,
  }) : gravity = gravity ?? world?.gravity ?? standardGravityVector;

  /// A copy with the given fields replaced. A `clear…` flag resets that
  /// nullable field to null, which passing null cannot say.
  // ignore: avoid-incomplete-copy-with, the world only seeds the defaults and is not kept
  DebrisSettings copyWith({
    Vector3? gravity,
    double? friction,
    double? restitution,
    double? linearDamping,
    double? angularDamping,
    double? maxSpeed,
    int? substeps,
    int? iterations,
    bool clearGravity = false,
  }) => DebrisSettings(
    gravity: clearGravity ? null : (gravity ?? this.gravity),
    friction: friction ?? this.friction,
    restitution: restitution ?? this.restitution,
    linearDamping: linearDamping ?? this.linearDamping,
    angularDamping: angularDamping ?? this.angularDamping,
    maxSpeed: maxSpeed ?? this.maxSpeed,
    substeps: substeps ?? this.substeps,
    iterations: iterations ?? this.iterations,
  );

  /// Gravity, m/s².
  final Vector3 gravity;

  /// Coulomb friction, a unitless coefficient: the most tangential impulse
  /// a contact takes, over its normal impulse.
  final double friction;

  /// Applied when two close faster than 1 m/s.
  final double restitution;

  /// Per second, as v / (1 + c dt).
  final double linearDamping;

  /// Per second, as ω / (1 + c dt), on the spin.
  final double angularDamping;

  /// The fastest a ball may move, in metres per second.
  final double maxSpeed;

  /// How many substeps a step is cut into; nought is taken as one.
  final int substeps;

  /// How many impulse passes a substep makes; nought is taken as one.
  final int iterations;
}

/// One ball of debris to add: a radius or mass of nought or less empties
/// its slot instead.
///
/// A class rather than a record, so it can carry more in a minor without
/// breaking a backend that mixes the system in.
final class DebrisBody {
  /// A ball at [position] moving at [velocity], of [radius] metres and
  /// [mass] kilograms.
  const DebrisBody({
    required this.position,
    required this.velocity,
    required this.radius,
    required this.mass,
  });

  /// Where, in metres.
  final Vector3 position;

  /// How fast, in metres a second.
  final Vector3 velocity;

  /// In metres.
  final double radius;

  /// In kilograms.
  final double mass;

  /// Equal to another with the same fields, as the record it was compared.
  @override
  bool operator ==(Object other) =>
      other is DebrisBody &&
      other.position == position &&
      other.velocity == velocity &&
      other.radius == radius &&
      other.mass == mass;

  @override
  int get hashCode => Object.hash(position, velocity, radius, mass);

  @override
  String toString() =>
      'DebrisBody(position: $position, velocity: $velocity, radius: $radius, mass: $mass)';
}

/// A still shape debris lands on.
abstract final class DebrisStatic {
  const DebrisStatic();
}

/// The plane of points p with p · [normal] = [offset]; debris stays on the
/// side [normal] points to.
final class DebrisPlane extends DebrisStatic {
  /// The plane along [normal] at [offset] metres from the origin.
  const DebrisPlane(this.normal, this.offset);

  /// The plane's normal, unit length, pointing to where debris stays.
  final Vector3 normal;

  /// The plane's distance from the origin along a unit [normal], in metres.
  final double offset;
}

/// An unturned box.
final class DebrisBox extends DebrisStatic {
  /// A box at [center] of [halfExtents], in metres.
  const DebrisBox(this.center, this.halfExtents);

  /// The box's centre, in metres.
  final Vector3 center;

  /// Half the box's size along x, y and z, in metres.
  final Vector3 halfExtents;
}

/// What a read gives: the step the bodies are from, counted from one, and
/// eight floats a slot — position xyz, orientation xyzw, radius.
///
/// A class rather than a record, so it can carry more in a minor without
/// breaking a backend that mixes the system in.
final class DebrisFrame {
  /// The bodies of step [step], eight floats a slot.
  const DebrisFrame({required this.step, required this.bodies});

  /// The step, counted from one.
  final int step;

  /// Eight floats a slot: position xyz in metres, orientation xyzw, radius
  /// in metres.
  final Float32List bodies;

  /// Equal to another with the same fields, as the record it was compared.
  @override
  bool operator ==(Object other) =>
      other is DebrisFrame && other.step == step && other.bodies == bodies;

  @override
  int get hashCode => Object.hash(step, bodies);

  @override
  String toString() => 'DebrisFrame(step: $step, bodies: $bodies)';
}

/// Debris slots, filled round and round: on the CPU ([NativeDebris]), or on
/// a GPU through the hardware layer (`DebrisWorkload` in
/// `flutter3d_effects`, from [debrisKernels]), the same passes. Visual, not the game's state.
///
/// **Mixed in, not implemented**, outside this library: a `base` type, so a
/// member added in a 1.x release arrives with a body and nothing that mixes
/// it in has to change.
abstract base mixin class DebrisSystem {
  /// How many slots the debris has.
  int get capacity;

  /// Puts [bodies] into the next slots, the oldest going first, unturned.
  void add(List<DebrisBody> bodies);

  /// The still shapes, replacing the last: at most 64.
  void setStatics(List<DebrisStatic> statics);

  /// One step of the debris, as [DebrisSystemStep] says.
  void step(DebrisSystemStep step);

  /// The latest step's bodies not read yet; null when there is none
  /// (absent, not an error). Stepped on a GPU, a frame or two late: the
  /// step queued last is still on its way.
  DebrisFrame? read({bool wait = true});

  /// Frees what the debris holds; it is not to be used after.
  void dispose();
}

/// What [DebrisSystem.step] is handed: the settings and the step's length
/// in seconds.
///
/// **One object, so a minor can hand the debris more** — a wind, an
/// explosion — without breaking one written against 1.0. **Reusable**:
/// debris stepped every frame keeps one and sets it before the call; the
/// system reads it during the call and does not keep it.
final class DebrisSystemStep {
  /// A step of [dt] seconds with [settings].
  DebrisSystemStep({required this.settings, required this.dt});

  /// How the debris behaves.
  DebrisSettings settings;

  /// The step, in seconds.
  double dt;
}

/// [bodies] as `f3d_debris_add` takes them, eight floats apiece, in a block
/// the caller frees.
c.F32s packDebrisBodies(List<DebrisBody> bodies) {
  final data = c.F32s.alloc(bodies.isEmpty ? 8 : bodies.length * 8);
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

/// [statics] as `f3d_debris_set_statics` takes them, eight floats apiece, in
/// a block the caller frees. Throws an [ArgumentError] for more than 64, and
/// an [UnsupportedError] for a shape that is neither a [DebrisPlane] nor a
/// [DebrisBox].
c.F32s packDebrisStatics(List<DebrisStatic> statics) {
  if (statics.length > c.debrisMaxStatics) {
    throw ArgumentError.value(statics.length, 'statics', 'more than 64');
  }
  final data = c.F32s.alloc(statics.isEmpty ? 8 : statics.length * 8);
  for (var i = 0; i < statics.length; i++) {
    final o = i * 8;
    switch (statics[i]) {
      case DebrisPlane(:final normal, :final offset):
        data[o] = normal.x;
        data[o + 1] = normal.y;
        data[o + 2] = normal.z;
        data[o + 3] = offset;
      case DebrisBox(:final center, :final halfExtents):
        data[o] = center.x;
        data[o + 1] = center.y;
        data[o + 2] = center.z;
        data[o + 4] = halfExtents.x;
        data[o + 5] = halfExtents.y;
        data[o + 6] = halfExtents.z;
        data[o + 7] = 1.0;
      default:
        throw UnsupportedError(
          'the native core has no static shape for ${statics[i]}',
        );
    }
  }
  return data;
}

/// [settings] as the core's `F3dDebrisSettings` in a block of the core's memory the
/// caller frees.
int writeDebrisSettings(DebrisSettings settings) {
  final s = c.coreAlloc(c.F3dDebrisSettingsLayout.size);
  for (var k = 0; k < 3; k++) {
    c.writeF32(
      s + c.F3dDebrisSettingsLayout.gravity + k * 4,
      settings.gravity[k],
    );
  }
  c.writeF32(s + c.F3dDebrisSettingsLayout.friction, settings.friction);
  c.writeF32(s + c.F3dDebrisSettingsLayout.restitution, settings.restitution);
  c.writeF32(
    s + c.F3dDebrisSettingsLayout.linearDamping,
    settings.linearDamping,
  );
  c.writeF32(
    s + c.F3dDebrisSettingsLayout.angularDamping,
    settings.angularDamping,
  );
  c.writeF32(s + c.F3dDebrisSettingsLayout.maxSpeed, settings.maxSpeed);
  c.writeU32(s + c.F3dDebrisSettingsLayout.substeps, settings.substeps);
  c.writeU32(s + c.F3dDebrisSettingsLayout.iterations, settings.iterations);
  return s;
}

/// Debris stepped by the core on the CPU: the reference for the GPU's, and
/// the fallback where there is none.
final class NativeDebris implements DebrisSystem {
  /// Debris of [capacity] empty slots. Throws an [ArgumentError] for none,
  /// or when the core has no memory.
  NativeDebris(int capacity) : _d = c.f3d_debris_create(capacity) {
    if (_d == 0) {
      throw ArgumentError.value(capacity, 'capacity', 'none, or no memory');
    }
    _finalizer.attach(this, _d, detach: this);
  }

  static final Finalizer<int> _finalizer = Finalizer<int>(c.f3d_debris_destroy);

  int _d;
  int _steps = 0;
  int _read = 0;

  int get _live {
    if (_d == 0) throw StateError('this debris was disposed');
    return _d;
  }

  @override
  int get capacity => c.f3d_debris_capacity(_live);

  @override
  void add(List<DebrisBody> bodies) {
    final data = packDebrisBodies(bodies);
    try {
      c.f3d_debris_add(_live, data, bodies.length);
    } finally {
      data.free();
    }
  }

  @override
  void setStatics(List<DebrisStatic> statics) {
    final data = packDebrisStatics(statics);
    try {
      c.f3d_debris_set_statics(_live, data, statics.length);
    } finally {
      data.free();
    }
  }

  @override
  void step(DebrisSystemStep request) {
    final settings = request.settings;
    final dt = request.dt;
    final s = writeDebrisSettings(settings);
    try {
      c.f3d_debris_step(_live, s, dt);
      _steps++;
    } finally {
      c.coreFree(s);
    }
  }

  @override
  DebrisFrame? read({bool wait = true}) {
    final n = capacity;
    if (_steps == _read) return null;
    final out = c.F32s.alloc(n * c.debrisFloats);
    try {
      c.f3d_debris_read(_live, out, n);
      _read = _steps;
      return DebrisFrame(step: _steps, bodies: out.copy(n * c.debrisFloats));
    } finally {
      out.free();
    }
  }

  @override
  void dispose() {
    if (_d == 0) return;
    _finalizer.detach(this);
    c.f3d_debris_destroy(_d);
    _d = 0;
  }
}
