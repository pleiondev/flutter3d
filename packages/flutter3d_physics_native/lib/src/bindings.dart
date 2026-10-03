/// The C core's functions, as `csrc/include/f3d_physics.h` declares them —
/// P9.
///
/// Written by hand rather than generated: the surface is small and grows a
/// phase at a time, and a generator would need libclang on every machine
/// that regenerates. `bindings_test.dart` holds the ABI version, so a
/// header that moved on without this file is a failed test rather than a
/// call into the wrong function.
// The C names, kept: a binding that renamed them would be one more thing to
// match against the header.
// ignore_for_file: non_constant_identifier_names
@DefaultAsset('package:flutter3d_physics_native/src/bindings.dart')
library;

import 'dart:ffi';

/// `F3D_ABI_VERSION` this file was written against.
const int abiVersion = 2;

/// `F3D_TRANSFORM_FLOATS`.
const int transformFloats = 7;

/// `F3dBodyType`.
abstract final class BodyType {
  static const int dynamic = 0;
  static const int fixed = 1;
}

final class F3dWorld extends Opaque {}

@Native<Pointer<Void> Function(Uint32)>(isLeaf: true)
external Pointer<Void> f3d_buffer_alloc(int bytes);

@Native<Void Function(Pointer<Void>)>(isLeaf: true)
external void f3d_buffer_free(Pointer<Void> buffer);

@Native<Uint32 Function()>(isLeaf: true)
external int f3d_abi_version();

@Native<Pointer<F3dWorld> Function()>()
external Pointer<F3dWorld> f3d_world_create();

@Native<Void Function(Pointer<F3dWorld>)>()
external void f3d_world_destroy(Pointer<F3dWorld> world);

@Native<Void Function(Pointer<F3dWorld>, Float, Float, Float)>(isLeaf: true)
external void f3d_world_set_gravity(
  Pointer<F3dWorld> world,
  double x,
  double y,
  double z,
);

@Native<Void Function(Pointer<F3dWorld>, Pointer<Float>)>(isLeaf: true)
external void f3d_world_get_gravity(
  Pointer<F3dWorld> world,
  Pointer<Float> out,
);

@Native<Uint32 Function(Pointer<F3dWorld>)>(isLeaf: true)
external int f3d_world_body_count(Pointer<F3dWorld> world);

@Native<Uint64 Function(Pointer<F3dWorld>, Int32, Float, Float, Float, Float)>()
external int f3d_body_create(
  Pointer<F3dWorld> world,
  int type,
  double px,
  double py,
  double pz,
  double mass,
);

@Native<Int32 Function(Pointer<F3dWorld>, Uint64)>(isLeaf: true)
external int f3d_body_destroy(Pointer<F3dWorld> world, int body);

@Native<Int32 Function(Pointer<F3dWorld>, Uint64)>(isLeaf: true)
external int f3d_body_is_valid(Pointer<F3dWorld> world, int body);

@Native<Int32 Function(Pointer<F3dWorld>, Uint64, Float, Float, Float)>(
  isLeaf: true,
)
external int f3d_body_set_velocity(
  Pointer<F3dWorld> world,
  int body,
  double x,
  double y,
  double z,
);

@Native<Int32 Function(Pointer<F3dWorld>, Uint64, Pointer<Float>)>(isLeaf: true)
external int f3d_body_get_velocity(
  Pointer<F3dWorld> world,
  int body,
  Pointer<Float> out,
);

@Native<Int32 Function(Pointer<F3dWorld>, Uint64, Float, Float, Float)>(
  isLeaf: true,
)
external int f3d_body_set_position(
  Pointer<F3dWorld> world,
  int body,
  double x,
  double y,
  double z,
);

@Native<Int32 Function(Pointer<F3dWorld>, Uint64, Pointer<Float>)>(isLeaf: true)
external int f3d_body_get_position(
  Pointer<F3dWorld> world,
  int body,
  Pointer<Float> out,
);

@Native<Void Function(Pointer<F3dWorld>, Float)>()
external void f3d_world_step(Pointer<F3dWorld> world, double dt);

@Native<
  Uint32 Function(Pointer<F3dWorld>, Pointer<Float>, Pointer<Uint64>, Uint32)
>(isLeaf: true)
external int f3d_world_read_transforms(
  Pointer<F3dWorld> world,
  Pointer<Float> transforms,
  Pointer<Uint64> handles,
  int capacity,
);
