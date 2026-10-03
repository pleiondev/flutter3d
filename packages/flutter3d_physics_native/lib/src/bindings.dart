/// The C core's functions, as `csrc/include/f3d_physics.h` declares them —
/// P9.
///
/// Written by hand rather than generated: the surface is small and grows a
/// phase at a time, and a generator would need libclang on every machine
/// that regenerates. `bindings_test.dart` holds the ABI version, so a
/// header that moved on without this file is a failed test rather than a
/// call into the wrong function.
///
/// **For the f32 build.** `f3d_real` is a `Float` here; a core built with
/// `F3D_REAL_DOUBLE` is for C callers, and `NativeWorld` refuses it.
// The C names, kept: a binding that renamed them would be one more thing to
// match against the header.
// ignore_for_file: non_constant_identifier_names
@DefaultAsset('package:flutter3d_physics_native/src/bindings.dart')
library;

import 'dart:ffi';

/// `F3D_ABI_VERSION` this file was written against.
const int abiVersion = 4;

/// `F3D_TRANSFORM_FLOATS`.
const int transformFloats = 7;

/// `F3D_FIRE_FLOATS`.
const int fireFloats = 4;

/// `F3D_CONTACT_FLOATS`.
const int contactFloats = 7;

/// `F3D_EVENT_CAPACITY`.
const int eventCapacity = 65536;

/// `F3dBodyType`.
abstract final class BodyType {
  static const int dynamic = 0;
  static const int fixed = 1;
}

/// `F3dShapeKind`.
abstract final class ShapeKind {
  static const int point = 0;
  static const int sphere = 1;
  static const int box = 2;
  static const int capsule = 3;
}

/// `F3dMaterialKind`.
abstract final class MaterialKind {
  static const int inert = 0;
  static const int wood = 1;
  static const int paper = 2;
  static const int rubber = 3;
  static const int steel = 4;
  static const int stone = 5;
}

/// `F3dEventKind`.
abstract final class EventKind {
  static const int slept = 0;
  static const int woke = 1;
  static const int ignited = 2;
  static const int extinguished = 3;
  static const int burntOut = 4;
  static const int contactBegan = 5;
  static const int contactEnded = 6;
}

final class F3dWorld extends Opaque {}

/// `F3dMaterial`, field for field.
final class F3dMaterial extends Struct {
  @Float()
  external double specific_heat;
  @Float()
  external double emissivity;
  @Float()
  external double ignition_temperature;
  @Float()
  external double heat_of_combustion;
  @Float()
  external double burn_rate;
  @Float()
  external double fuel_fraction;
  @Float()
  external double flame_feedback;
  @Float()
  external double conductivity;
}

@Native<Uint32 Function()>(isLeaf: true)
external int f3d_abi_version();

@Native<Uint32 Function()>(isLeaf: true)
external int f3d_real_bytes();

@Native<Pointer<Void> Function(Uint32)>(isLeaf: true)
external Pointer<Void> f3d_buffer_alloc(int bytes);

@Native<Void Function(Pointer<Void>)>(isLeaf: true)
external void f3d_buffer_free(Pointer<Void> buffer);

// ------------------------------------------------------------------ world

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

@Native<Int32 Function(Pointer<F3dWorld>, Float, Float)>(isLeaf: true)
external int f3d_world_set_air(
  Pointer<F3dWorld> world,
  double temperature,
  double density,
);

@Native<Void Function(Pointer<F3dWorld>, Pointer<Float>)>(isLeaf: true)
external void f3d_world_get_air(Pointer<F3dWorld> world, Pointer<Float> out);

@Native<Void Function(Pointer<F3dWorld>, Float, Float, Float)>(isLeaf: true)
external void f3d_world_set_wind(
  Pointer<F3dWorld> world,
  double x,
  double y,
  double z,
);

@Native<
  Int32 Function(
    Pointer<F3dWorld>,
    Float,
    Float,
    Float,
    Float,
    Uint32,
    Uint32,
    Uint32,
    Pointer<Float>,
  )
>(isLeaf: true)
external int f3d_world_set_wind_grid(
  Pointer<F3dWorld> world,
  double ox,
  double oy,
  double oz,
  double cell,
  int nx,
  int ny,
  int nz,
  Pointer<Float> velocities,
);

@Native<Void Function(Pointer<F3dWorld>, Float, Float, Float, Pointer<Float>)>(
  isLeaf: true,
)
external void f3d_world_sample_wind(
  Pointer<F3dWorld> world,
  double x,
  double y,
  double z,
  Pointer<Float> out,
);

@Native<Int32 Function(Pointer<F3dWorld>, Float, Float)>(isLeaf: true)
external int f3d_world_set_sleep(
  Pointer<F3dWorld> world,
  double speed,
  double time,
);

@Native<Void Function(Pointer<F3dWorld>, Pointer<Double>)>(isLeaf: true)
external void f3d_world_get_origin(
  Pointer<F3dWorld> world,
  Pointer<Double> out,
);

@Native<Void Function(Pointer<F3dWorld>, Double, Double, Double)>(isLeaf: true)
external void f3d_world_shift_origin(
  Pointer<F3dWorld> world,
  double dx,
  double dy,
  double dz,
);

@Native<Uint32 Function(Pointer<F3dWorld>)>(isLeaf: true)
external int f3d_world_body_count(Pointer<F3dWorld> world);

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

@Native<
  Uint32 Function(Pointer<F3dWorld>, Pointer<Float>, Pointer<Uint64>, Uint32)
>(isLeaf: true)
external int f3d_world_read_fires(
  Pointer<F3dWorld> world,
  Pointer<Float> fires,
  Pointer<Uint64> handles,
  int capacity,
);

@Native<
  Uint32 Function(
    Pointer<F3dWorld>,
    Pointer<Uint64>,
    Pointer<Uint64>,
    Pointer<Uint32>,
    Uint32,
  )
>(isLeaf: true)
external int f3d_world_read_events(
  Pointer<F3dWorld> world,
  Pointer<Uint64> bodies,
  Pointer<Uint64> others,
  Pointer<Uint32> kinds,
  int capacity,
);

@Native<Int32 Function(Pointer<F3dWorld>, Float)>(isLeaf: true)
external int f3d_world_set_contact_margin(
  Pointer<F3dWorld> world,
  double margin,
);

@Native<Uint32 Function(Pointer<F3dWorld>)>(isLeaf: true)
external int f3d_world_contact_count(Pointer<F3dWorld> world);

@Native<
  Uint32 Function(Pointer<F3dWorld>, Pointer<Float>, Pointer<Uint64>, Uint32)
>(isLeaf: true)
external int f3d_world_read_contacts(
  Pointer<F3dWorld> world,
  Pointer<Float> contacts,
  Pointer<Uint64> pairs,
  int capacity,
);

@Native<Int32 Function(Pointer<F3dWorld>, Uint64, Uint32, Uint32)>(isLeaf: true)
external int f3d_body_set_collision_filter(
  Pointer<F3dWorld> world,
  int body,
  int layer,
  int mask,
);

@Native<Uint32 Function(Pointer<F3dWorld>)>(isLeaf: true)
external int f3d_world_events_dropped(Pointer<F3dWorld> world);

// -------------------------------------------------------------- snapshots

@Native<Uint32 Function(Pointer<F3dWorld>)>(isLeaf: true)
external int f3d_world_snapshot_size(Pointer<F3dWorld> world);

@Native<Uint32 Function(Pointer<F3dWorld>, Pointer<Uint8>, Uint32)>(
  isLeaf: true,
)
external int f3d_world_snapshot_write(
  Pointer<F3dWorld> world,
  Pointer<Uint8> buffer,
  int size,
);

@Native<Int32 Function(Pointer<F3dWorld>, Pointer<Uint8>, Uint32)>()
external int f3d_world_restore(
  Pointer<F3dWorld> world,
  Pointer<Uint8> buffer,
  int size,
);

// ----------------------------------------------------------------- bodies

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

typedef _Set3 = Int32 Function(Pointer<F3dWorld>, Uint64, Float, Float, Float);
typedef _GetN = Int32 Function(Pointer<F3dWorld>, Uint64, Pointer<Float>);

@Native<_Set3>(isLeaf: true)
external int f3d_body_set_velocity(
  Pointer<F3dWorld> world,
  int body,
  double x,
  double y,
  double z,
);

@Native<_GetN>(isLeaf: true)
external int f3d_body_get_velocity(
  Pointer<F3dWorld> world,
  int body,
  Pointer<Float> out,
);

@Native<_Set3>(isLeaf: true)
external int f3d_body_set_position(
  Pointer<F3dWorld> world,
  int body,
  double x,
  double y,
  double z,
);

@Native<_GetN>(isLeaf: true)
external int f3d_body_get_position(
  Pointer<F3dWorld> world,
  int body,
  Pointer<Float> out,
);

@Native<Int32 Function(Pointer<F3dWorld>, Uint64, Pointer<Double>)>(
  isLeaf: true,
)
external int f3d_body_get_world_position(
  Pointer<F3dWorld> world,
  int body,
  Pointer<Double> out,
);

@Native<_Set3>(isLeaf: true)
external int f3d_body_set_angular_velocity(
  Pointer<F3dWorld> world,
  int body,
  double x,
  double y,
  double z,
);

@Native<_GetN>(isLeaf: true)
external int f3d_body_get_angular_velocity(
  Pointer<F3dWorld> world,
  int body,
  Pointer<Float> out,
);

@Native<Int32 Function(Pointer<F3dWorld>, Uint64, Float, Float, Float, Float)>(
  isLeaf: true,
)
external int f3d_body_set_orientation(
  Pointer<F3dWorld> world,
  int body,
  double x,
  double y,
  double z,
  double w,
);

@Native<_GetN>(isLeaf: true)
external int f3d_body_get_orientation(
  Pointer<F3dWorld> world,
  int body,
  Pointer<Float> out,
);

@Native<Int32 Function(Pointer<F3dWorld>, Uint64, Int32, Float, Float, Float)>(
  isLeaf: true,
)
external int f3d_body_set_shape(
  Pointer<F3dWorld> world,
  int body,
  int kind,
  double a,
  double b,
  double c,
);

@Native<_GetN>(isLeaf: true)
external int f3d_body_get_inertia(
  Pointer<F3dWorld> world,
  int body,
  Pointer<Float> out,
);

@Native<_GetN>(isLeaf: true)
external int f3d_body_get_mass(
  Pointer<F3dWorld> world,
  int body,
  Pointer<Float> out,
);

@Native<Int32 Function(Pointer<F3dWorld>, Uint64, Int32)>(isLeaf: true)
external int f3d_body_lock_rotation(
  Pointer<F3dWorld> world,
  int body,
  int locked,
);

@Native<Int32 Function(Pointer<F3dWorld>, Uint64, Float, Float)>(isLeaf: true)
external int f3d_body_set_damping(
  Pointer<F3dWorld> world,
  int body,
  double linear,
  double angular,
);

@Native<Int32 Function(Pointer<F3dWorld>, Uint64, Float)>(isLeaf: true)
external int f3d_body_set_drag(
  Pointer<F3dWorld> world,
  int body,
  double coefficient,
);

@Native<_Set3>(isLeaf: true)
external int f3d_body_apply_impulse(
  Pointer<F3dWorld> world,
  int body,
  double x,
  double y,
  double z,
);

@Native<
  Int32 Function(
    Pointer<F3dWorld>,
    Uint64,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
  )
>(isLeaf: true)
external int f3d_body_apply_impulse_at(
  Pointer<F3dWorld> world,
  int body,
  double x,
  double y,
  double z,
  double px,
  double py,
  double pz,
);

@Native<_Set3>(isLeaf: true)
external int f3d_body_add_force(
  Pointer<F3dWorld> world,
  int body,
  double x,
  double y,
  double z,
);

@Native<_Set3>(isLeaf: true)
external int f3d_body_add_torque(
  Pointer<F3dWorld> world,
  int body,
  double x,
  double y,
  double z,
);

@Native<Int32 Function(Pointer<F3dWorld>, Uint64)>(isLeaf: true)
external int f3d_body_is_asleep(Pointer<F3dWorld> world, int body);

@Native<Int32 Function(Pointer<F3dWorld>, Uint64)>(isLeaf: true)
external int f3d_body_wake(Pointer<F3dWorld> world, int body);

// ------------------------------------------------------- heat and fire

@Native<Int32 Function(Int32, Pointer<F3dMaterial>)>(isLeaf: true)
external int f3d_material_preset(int kind, Pointer<F3dMaterial> out);

@Native<Int32 Function(Pointer<F3dWorld>, Uint64, Pointer<F3dMaterial>)>(
  isLeaf: true,
)
external int f3d_body_set_material(
  Pointer<F3dWorld> world,
  int body,
  Pointer<F3dMaterial> material,
);

@Native<Int32 Function(Pointer<F3dWorld>, Uint64, Float)>(isLeaf: true)
external int f3d_body_set_temperature(
  Pointer<F3dWorld> world,
  int body,
  double kelvin,
);

@Native<_GetN>(isLeaf: true)
external int f3d_body_get_temperature(
  Pointer<F3dWorld> world,
  int body,
  Pointer<Float> out,
);

@Native<Int32 Function(Pointer<F3dWorld>, Uint64, Float)>(isLeaf: true)
external int f3d_body_add_heat(
  Pointer<F3dWorld> world,
  int body,
  double joules,
);

@Native<Int32 Function(Pointer<F3dWorld>, Uint64, Float)>(isLeaf: true)
external int f3d_body_add_water(Pointer<F3dWorld> world, int body, double kg);

@Native<_GetN>(isLeaf: true)
external int f3d_body_get_water(
  Pointer<F3dWorld> world,
  int body,
  Pointer<Float> out,
);

@Native<_GetN>(isLeaf: true)
external int f3d_body_get_fuel(
  Pointer<F3dWorld> world,
  int body,
  Pointer<Float> out,
);

@Native<Int32 Function(Pointer<F3dWorld>, Uint64, Pointer<Int32>)>(isLeaf: true)
external int f3d_body_is_burning(
  Pointer<F3dWorld> world,
  int body,
  Pointer<Int32> out,
);

@Native<_GetN>(isLeaf: true)
external int f3d_body_get_heat_release(
  Pointer<F3dWorld> world,
  int body,
  Pointer<Float> out,
);
