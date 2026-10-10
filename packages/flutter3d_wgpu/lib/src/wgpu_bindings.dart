/// The sidecar's C functions, as `csrc/f3d_wgpu.h` declares them.
///
/// A library of its own, built by the hook with wgpu-native linked in, and
/// missing where wgpu-native could not be had: then every call here throws,
/// which `WgpuComputeDevice.open` turns into its refusal.
// The C names, kept.
// ignore_for_file: non_constant_identifier_names
@DefaultAsset('package:flutter3d_wgpu/src/wgpu_bindings.dart')
library;

import 'dart:ffi';

/// `F3D_WGPU_ABI_VERSION` this file was written against.
const int wgpuAbiVersion = 1;

/// Binding kinds, as `f3d_wgpu.h` numbers them.
const int wgpuStorage = 0;
const int wgpuReadOnly = 1;
const int wgpuTexture = 2;
const int wgpuImage = 3;

final class F3dWgpu extends Opaque {}

final class F3dWgpuBuffer extends Opaque {}

final class F3dWgpuTexture extends Opaque {}

final class F3dWgpuKernel extends Opaque {}

final class F3dWgpuPass extends Opaque {}

@Native<Uint32 Function()>(isLeaf: true)
external int f3d_wgpu_abi_version();

@Native<Pointer<F3dWgpu> Function()>()
external Pointer<F3dWgpu> f3d_wgpu_open();

@Native<Void Function(Pointer<F3dWgpu>)>()
external void f3d_wgpu_close(Pointer<F3dWgpu> gpu);

@Native<Uint32 Function(Pointer<F3dWgpu>, Pointer<Uint8>, Uint32)>(isLeaf: true)
external int f3d_wgpu_adapter_name(
  Pointer<F3dWgpu> gpu,
  Pointer<Uint8> out,
  int capacity,
);

@Native<Uint32 Function(Pointer<F3dWgpu>, Pointer<Uint8>, Uint32)>(isLeaf: true)
external int f3d_wgpu_take_error(
  Pointer<F3dWgpu> gpu,
  Pointer<Uint8> out,
  int capacity,
);

@Native<Pointer<F3dWgpuBuffer> Function(Pointer<F3dWgpu>, Uint64)>()
external Pointer<F3dWgpuBuffer> f3d_wgpu_buffer_create(
  Pointer<F3dWgpu> gpu,
  int size,
);

@Native<
  Void Function(
    Pointer<F3dWgpu>,
    Pointer<F3dWgpuBuffer>,
    Uint64,
    Pointer<Void>,
    Uint64,
  )
>()
external void f3d_wgpu_buffer_write(
  Pointer<F3dWgpu> gpu,
  Pointer<F3dWgpuBuffer> buffer,
  int offset,
  Pointer<Void> data,
  int size,
);

@Native<
  Int32 Function(
    Pointer<F3dWgpu>,
    Pointer<F3dWgpuBuffer>,
    Uint64,
    Pointer<Void>,
    Uint64,
  )
>()
external int f3d_wgpu_buffer_read(
  Pointer<F3dWgpu> gpu,
  Pointer<F3dWgpuBuffer> buffer,
  int offset,
  Pointer<Void> out,
  int size,
);

@Native<Void Function(Pointer<F3dWgpuBuffer>)>()
external void f3d_wgpu_buffer_release(Pointer<F3dWgpuBuffer> buffer);

@Native<
  Pointer<F3dWgpuTexture> Function(Pointer<F3dWgpu>, Uint32, Uint32, Int32)
>()
external Pointer<F3dWgpuTexture> f3d_wgpu_texture_create(
  Pointer<F3dWgpu> gpu,
  int width,
  int height,
  int storage,
);

@Native<
  Void Function(Pointer<F3dWgpu>, Pointer<F3dWgpuTexture>, Pointer<Void>)
>()
external void f3d_wgpu_texture_write(
  Pointer<F3dWgpu> gpu,
  Pointer<F3dWgpuTexture> texture,
  Pointer<Void> rgba,
);

@Native<
  Int32 Function(Pointer<F3dWgpu>, Pointer<F3dWgpuTexture>, Pointer<Void>)
>()
external int f3d_wgpu_texture_read(
  Pointer<F3dWgpu> gpu,
  Pointer<F3dWgpuTexture> texture,
  Pointer<Void> rgba,
);

@Native<Pointer<Void> Function(Pointer<F3dWgpuTexture>)>(isLeaf: true)
external Pointer<Void> f3d_wgpu_texture_native_metal(
  Pointer<F3dWgpuTexture> texture,
);

@Native<Void Function(Pointer<F3dWgpuTexture>)>()
external void f3d_wgpu_texture_release(Pointer<F3dWgpuTexture> texture);

@Native<
  Pointer<F3dWgpuKernel> Function(
    Pointer<F3dWgpu>,
    Pointer<Uint8>,
    Pointer<Uint8>,
    Pointer<Uint32>,
    Uint32,
    Pointer<Uint8>,
    Uint32,
  )
>()
external Pointer<F3dWgpuKernel> f3d_wgpu_kernel_create(
  Pointer<F3dWgpu> gpu,
  Pointer<Uint8> wgsl,
  Pointer<Uint8> entry,
  Pointer<Uint32> kinds,
  int count,
  Pointer<Uint8> error,
  int capacity,
);

@Native<Void Function(Pointer<F3dWgpuKernel>)>()
external void f3d_wgpu_kernel_release(Pointer<F3dWgpuKernel> kernel);

@Native<Pointer<F3dWgpuPass> Function(Pointer<F3dWgpu>)>()
external Pointer<F3dWgpuPass> f3d_wgpu_pass_begin(Pointer<F3dWgpu> gpu);

@Native<
  Int32 Function(
    Pointer<F3dWgpuPass>,
    Pointer<F3dWgpuKernel>,
    Pointer<Pointer<Void>>,
    Pointer<Uint64>,
    Pointer<Uint64>,
    Uint32,
    Uint32,
    Uint32,
    Uint32,
  )
>()
external int f3d_wgpu_pass_dispatch(
  Pointer<F3dWgpuPass> pass,
  Pointer<F3dWgpuKernel> kernel,
  Pointer<Pointer<Void>> resources,
  Pointer<Uint64> offsets,
  Pointer<Uint64> sizes,
  int count,
  int x,
  int y,
  int z,
);

@Native<Int32 Function(Pointer<F3dWgpuPass>)>()
external int f3d_wgpu_pass_submit(Pointer<F3dWgpuPass> pass);

@Native<Void Function(Pointer<F3dWgpu>)>()
external void f3d_wgpu_finish(Pointer<F3dWgpu> gpu);
