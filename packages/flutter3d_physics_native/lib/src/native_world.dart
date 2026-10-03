/// A physics world stepped by the C core — P9.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:vector_math/vector_math.dart';

import 'bindings.dart' as c;

/// A body in a [NativeWorld]: its slot and the slot's generation, packed as
/// the C core packs them. Nought is never one.
extension type const NativeBody(int raw) {
  /// The arena slot.
  int get slot => raw & 0xffffffff;

  /// How many times the slot had been used when this body took it.
  int get generation => raw >>> 32;
}

/// What kind of body — `F3dBodyType`.
///
/// A class of constants rather than an enum: kinematic bodies arrive in a
/// later phase, and a value added to an enum breaks every switch written
/// against it.
final class NativeBodyType {
  const NativeBodyType._(this.code, this.name);

  /// Moved by gravity, forces and contacts.
  static const NativeBodyType dynamic = NativeBodyType._(
    c.BodyType.dynamic,
    'dynamic',
  );

  /// Never moves.
  static const NativeBodyType fixed = NativeBodyType._(
    c.BodyType.fixed,
    'fixed',
  );

  /// The core's number for it.
  final int code;
  final String name;

  @override
  String toString() => 'NativeBodyType.$name';
}

/// A world of bodies owned and stepped by the C core.
///
/// **Numbers cross as f32.** The core is single precision throughout, which
/// is what makes its deterministic mode the same bits on every platform, so a
/// value set here is rounded to the nearest float on the way in.
///
/// Freed by [dispose], or by the garbage collector when a world is dropped
/// without it. Every call after [dispose] throws a [StateError], so a world
/// used after it was freed is a Dart error rather than a native crash.
final class NativeWorld implements Finalizable {
  NativeWorld() : _world = c.f3d_world_create() {
    if (_world == nullptr) {
      throw StateError('the physics core could not allocate a world');
    }
    if (c.f3d_abi_version() != c.abiVersion) {
      c.f3d_world_destroy(_world);
      throw StateError(
        'the physics core is ABI ${c.f3d_abi_version()} and these bindings '
        'were written for ${c.abiVersion}',
      );
    }
    _finalizer.attach(this, _world.cast(), detach: this);
  }

  static final NativeFinalizer _finalizer = NativeFinalizer(
    Native.addressOf<NativeFunction<Void Function(Pointer<c.F3dWorld>)>>(
      c.f3d_world_destroy,
    ).cast(),
  );

  Pointer<c.F3dWorld> _world;

  /// Three floats a getter writes into; the world's own, freed with it.
  final Pointer<Float> _out = malloc<Float>(3);

  Pointer<c.F3dWorld> get _live {
    if (_world == nullptr) throw StateError('this world was disposed');
    return _world;
  }

  /// Frees the world and everything in it. Calling it again does nothing.
  void dispose() {
    if (_world == nullptr) return;
    _finalizer.detach(this);
    c.f3d_world_destroy(_world);
    malloc.free(_out);
    _world = nullptr;
  }

  /// Whether [dispose] has run.
  bool get isDisposed => _world == nullptr;

  /// Metres per second squared; (0, −9.81, 0) for a new world.
  Vector3 get gravity {
    c.f3d_world_get_gravity(_live, _out);
    return Vector3(_out[0], _out[1], _out[2]);
  }

  set gravity(Vector3 value) =>
      c.f3d_world_set_gravity(_live, value.x, value.y, value.z);

  /// How many bodies the world holds.
  int get bodyCount => c.f3d_world_body_count(_live);

  /// Adds a body at [position] and returns it.
  ///
  /// Throws an [ArgumentError] for a dynamic body whose [mass] is not
  /// finite and positive, or a [position] that is not finite — the core
  /// refuses both, and a refusal here says which.
  NativeBody addBody({
    required Vector3 position,
    NativeBodyType type = NativeBodyType.dynamic,
    double mass = 1.0,
  }) {
    final raw = c.f3d_body_create(
      _live,
      type.code,
      position.x,
      position.y,
      position.z,
      mass,
    );
    if (raw == 0) {
      if (type == NativeBodyType.dynamic && !(mass.isFinite && mass > 0.0)) {
        throw ArgumentError.value(mass, 'mass', 'not finite and positive');
      }
      if (!(position.x.isFinite &&
          position.y.isFinite &&
          position.z.isFinite)) {
        throw ArgumentError.value(position, 'position', 'not finite');
      }
      throw StateError('the physics core could not grow its arena');
    }
    return NativeBody(raw);
  }

  /// Takes [body] out of the world, and says whether it was there.
  bool removeBody(NativeBody body) => c.f3d_body_destroy(_live, body.raw) == 1;

  /// Whether [body] names a body in this world.
  bool contains(NativeBody body) => c.f3d_body_is_valid(_live, body.raw) == 1;

  /// [body]'s position. Throws an [ArgumentError] for a body not in the world.
  Vector3 positionOf(NativeBody body) {
    _check(c.f3d_body_get_position(_live, body.raw, _out), body);
    return Vector3(_out[0], _out[1], _out[2]);
  }

  void setPosition(NativeBody body, Vector3 value) => _check(
    c.f3d_body_set_position(_live, body.raw, value.x, value.y, value.z),
    body,
  );

  /// [body]'s velocity, metres per second.
  Vector3 velocityOf(NativeBody body) {
    _check(c.f3d_body_get_velocity(_live, body.raw, _out), body);
    return Vector3(_out[0], _out[1], _out[2]);
  }

  void setVelocity(NativeBody body, Vector3 value) => _check(
    c.f3d_body_set_velocity(_live, body.raw, value.x, value.y, value.z),
    body,
  );

  /// Advances the world by [dt] seconds; nothing for a [dt] that is not
  /// finite and positive.
  void step(double dt) => c.f3d_world_step(_live, dt);

  /// Every body's transform, seven floats apiece — position xyz, then the
  /// orientation quaternion xyzw — and its handle, in the world's slot
  /// order: what the renderer uploads as instance transforms.
  ({Float32List transforms, List<NativeBody> bodies}) readTransforms() {
    final count = bodyCount;
    if (count == 0) {
      return (transforms: Float32List(0), bodies: const <NativeBody>[]);
    }
    final transforms = malloc<Float>(count * c.transformFloats);
    final handles = malloc<Uint64>(count);
    try {
      final written = c.f3d_world_read_transforms(
        _live,
        transforms,
        handles,
        count,
      );
      return (
        transforms: Float32List.fromList(
          transforms.asTypedList(written * c.transformFloats),
        ),
        bodies: <NativeBody>[
          for (var i = 0; i < written; i++) NativeBody(handles[i]),
        ],
      );
    } finally {
      malloc
        ..free(transforms)
        ..free(handles);
    }
  }

  void _check(int answer, NativeBody body) {
    if (answer == 0) {
      throw ArgumentError.value(body.raw, 'body', 'not in this world');
    }
  }
}
