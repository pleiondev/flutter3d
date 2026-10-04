/// The GPU library's functions, as `csrc/gpu/f3d_gpu.h` declares them —
/// P9, phase 10.
///
/// A library of its own beside the core's: built by the hook with
/// wgpu-native linked in, and missing where wgpu-native could not be had —
/// then every call here throws, which `NativeGpu.open` turns into null.
// The C names, kept.
// ignore_for_file: non_constant_identifier_names
@DefaultAsset('package:flutter3d_physics_native/src/gpu_bindings.dart')
library;

import 'dart:ffi';

/// `F3D_GPU_ABI_VERSION` this file was written against.
const int gpuAbiVersion = 2;

final class F3dGpu extends Opaque {}

final class F3dGpuParticles extends Opaque {}

/// `F3dGpuParticleForces`, field for field.
final class F3dGpuParticleForces extends Struct {
  @Array(3)
  external Array<Float> gravity;
  @Array(3)
  external Array<Float> wind;
  @Float()
  external double drag;
  @Float()
  external double floor_y;
  @Float()
  external double restitution;
  @Float()
  external double friction;
}

@Native<Uint32 Function()>(isLeaf: true)
external int f3d_gpu_abi_version();

@Native<Pointer<F3dGpu> Function()>()
external Pointer<F3dGpu> f3d_gpu_create();

@Native<Void Function(Pointer<F3dGpu>)>()
external void f3d_gpu_destroy(Pointer<F3dGpu> gpu);

@Native<Uint32 Function(Pointer<F3dGpu>, Pointer<Uint8>, Uint32)>(isLeaf: true)
external int f3d_gpu_adapter_name(
  Pointer<F3dGpu> gpu,
  Pointer<Uint8> out,
  int capacity,
);

@Native<Pointer<F3dGpuParticles> Function(Pointer<F3dGpu>, Uint32)>()
external Pointer<F3dGpuParticles> f3d_gpu_particles_create(
  Pointer<F3dGpu> gpu,
  int capacity,
);

@Native<Void Function(Pointer<F3dGpuParticles>)>()
external void f3d_gpu_particles_destroy(Pointer<F3dGpuParticles> particles);

@Native<Uint32 Function(Pointer<F3dGpuParticles>, Pointer<Float>, Uint32)>()
external int f3d_gpu_particles_emit(
  Pointer<F3dGpuParticles> particles,
  Pointer<Float> data,
  int count,
);

@Native<
  Void Function(
    Pointer<F3dGpuParticles>,
    Pointer<F3dGpuParticleForces>,
    Float,
    Uint32,
  )
>()
external void f3d_gpu_particles_step(
  Pointer<F3dGpuParticles> particles,
  Pointer<F3dGpuParticleForces> forces,
  double dt,
  int steps,
);

@Native<Uint32 Function(Pointer<F3dGpuParticles>, Pointer<Float>, Uint32)>()
external int f3d_gpu_particles_read(
  Pointer<F3dGpuParticles> particles,
  Pointer<Float> out,
  int capacity,
);

final class F3dGpuDebris extends Opaque {}

/// `F3dGpuDebrisSettings`, field for field.
final class F3dGpuDebrisSettings extends Struct {
  @Array(3)
  external Array<Float> gravity;
  @Float()
  external double friction;
  @Float()
  external double restitution;
  @Float()
  external double linear_damping;
  @Float()
  external double angular_damping;
  @Float()
  external double max_speed;
  @Uint32()
  external int substeps;
  @Uint32()
  external int iterations;
}

@Native<Pointer<F3dGpuDebris> Function(Pointer<F3dGpu>, Uint32)>()
external Pointer<F3dGpuDebris> f3d_gpu_debris_create(
  Pointer<F3dGpu> gpu,
  int capacity,
);

@Native<Void Function(Pointer<F3dGpuDebris>)>()
external void f3d_gpu_debris_destroy(Pointer<F3dGpuDebris> debris);

@Native<Uint32 Function(Pointer<F3dGpuDebris>, Pointer<Float>, Uint32)>()
external int f3d_gpu_debris_add(
  Pointer<F3dGpuDebris> debris,
  Pointer<Float> data,
  int count,
);

@Native<Int32 Function(Pointer<F3dGpuDebris>, Pointer<Float>, Uint32)>()
external int f3d_gpu_debris_set_statics(
  Pointer<F3dGpuDebris> debris,
  Pointer<Float> data,
  int count,
);

@Native<
  Void Function(Pointer<F3dGpuDebris>, Pointer<F3dGpuDebrisSettings>, Float)
>()
external void f3d_gpu_debris_step(
  Pointer<F3dGpuDebris> debris,
  Pointer<F3dGpuDebrisSettings> settings,
  double dt,
);

@Native<
  Uint64 Function(Pointer<F3dGpuDebris>, Pointer<Float>, Uint32, Int32)
>()
external int f3d_gpu_debris_read(
  Pointer<F3dGpuDebris> debris,
  Pointer<Float> out,
  int capacity,
  int wait,
);
