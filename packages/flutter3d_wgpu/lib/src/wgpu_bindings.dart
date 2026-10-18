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
const int wgpuAbiVersion = 3;

/// Backends, as `f3d_wgpu.h` numbers them. `F3D_WGPU_BACKEND_DEFAULT`, only
/// asked for: the platform's own backends, tried in order.
const int wgpuBackendDefault = 0;

/// `F3D_WGPU_BACKEND_DX12`: Direct3D 12.
const int wgpuBackendDx12 = 1;

/// `F3D_WGPU_BACKEND_VULKAN`: Vulkan.
const int wgpuBackendVulkan = 2;

/// `F3D_WGPU_BACKEND_METAL`: Metal.
const int wgpuBackendMetal = 3;

/// `F3D_WGPU_BACKEND_GL`: OpenGL or OpenGL ES.
const int wgpuBackendGl = 4;

/// `F3D_WGPU_BACKEND_OTHER`: only answered, for anything else wgpu reports.
const int wgpuBackendOther = 5;

/// Binding kinds, as `f3d_wgpu.h` numbers them. `F3D_WGPU_STORAGE`: a
/// `var<storage, read_write>` buffer.
const int wgpuStorage = 0;

/// `F3D_WGPU_READ_ONLY`: a `var<storage, read>` buffer.
const int wgpuReadOnly = 1;

/// `F3D_WGPU_TEXTURE`: a sampled `texture_2d<f32>`.
const int wgpuTexture = 2;

/// `F3D_WGPU_IMAGE`: a `texture_storage_2d<rgba8unorm, write>`.
const int wgpuImage = 3;

/// The C `F3dWgpu`: an adapter, its device and queue, and the readback
/// staging pool.
final class F3dWgpu extends Opaque {}

/// The C `F3dWgpuBuffer`: a storage buffer that can be copied to and from.
final class F3dWgpuBuffer extends Opaque {}

/// The C `F3dWgpuTexture`: an RGBA8 texture, sampled and copied, and a
/// storage texture when made so.
final class F3dWgpuTexture extends Opaque {}

/// The C `F3dWgpuKernel`: a compute pipeline from one WGSL entry point, with
/// the bind groups it kept.
final class F3dWgpuKernel extends Opaque {}

/// The C `F3dWgpuPass`: a compute pass recording dispatches until submit.
final class F3dWgpuPass extends Opaque {}

/// The C `F3dWgpuRead`: a readback in flight, polled until done.
final class F3dWgpuRead extends Opaque {}

/// The `F3D_WGPU_ABI_VERSION` the library was built with, to compare with
/// [wgpuAbiVersion].
@Native<Uint32 Function()>(isLeaf: true)
external int f3d_wgpu_abi_version();

/// The best adapter of the platform's own backend, or `nullptr`; the same
/// as `f3d_wgpu_open_on(wgpuBackendDefault, 0)`.
@Native<Pointer<F3dWgpu> Function()>()
external Pointer<F3dWgpu> f3d_wgpu_open();

/// The best adapter on [backend] alone, or `nullptr`. [wgpuBackendDefault]
/// tries the platform's backends in order, each alone, and keeps the first
/// with an adapter. [fallback] non-zero asks for the software adapter.
@Native<Pointer<F3dWgpu> Function(Uint32, Int32)>()
external Pointer<F3dWgpu> f3d_wgpu_open_on(int backend, int fallback);

/// The backend the adapter runs on, a `wgpuBackend*` other than
/// [wgpuBackendDefault].
@Native<Uint32 Function(Pointer<F3dWgpu>)>(isLeaf: true)
external int f3d_wgpu_adapter_backend(Pointer<F3dWgpu> gpu);

/// One when the adapter is a CPU one (WARP, llvmpipe, SwiftShader), zero
/// otherwise.
@Native<Int32 Function(Pointer<F3dWgpu>)>(isLeaf: true)
external int f3d_wgpu_adapter_is_fallback(Pointer<F3dWgpu> gpu);

/// Releases the staging pool, queue, device, adapter and instance and frees
/// [gpu]; `nullptr` is ignored.
@Native<Void Function(Pointer<F3dWgpu>)>()
external void f3d_wgpu_close(Pointer<F3dWgpu> gpu);

/// Writes the adapter's name into [out], cut to [capacity] bytes with its
/// NUL; returns the whole name's length in bytes.
@Native<Uint32 Function(Pointer<F3dWgpu>, Pointer<Uint8>, Uint32)>(isLeaf: true)
external int f3d_wgpu_adapter_name(
  Pointer<F3dWgpu> gpu,
  Pointer<Uint8> out,
  int capacity,
);

/// Writes the last validation error into [out], cut to [capacity] bytes;
/// returns its length, zero when there was none since the last call.
@Native<Uint32 Function(Pointer<F3dWgpu>, Pointer<Uint8>, Uint32)>(isLeaf: true)
external int f3d_wgpu_take_error(
  Pointer<F3dWgpu> gpu,
  Pointer<Uint8> out,
  int capacity,
);

/// A storage buffer of [size] bytes that can be copied to and from, or
/// `nullptr` where it could not be made.
@Native<Pointer<F3dWgpuBuffer> Function(Pointer<F3dWgpu>, Uint64)>()
external Pointer<F3dWgpuBuffer> f3d_wgpu_buffer_create(
  Pointer<F3dWgpu> gpu,
  int size,
);

/// Writes [size] bytes from [data] into [buffer] at byte [offset], through
/// the queue.
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

/// Copies [size] bytes from byte [offset] of [buffer] into [out] once every
/// pass submitted before is done, blocking until then; one on success.
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

/// Starts copying [size] bytes from byte [offset] of [buffer] back, after
/// every pass submitted before, without waiting; `nullptr` when no staging
/// buffer could be had from the device's pool.
@Native<
  Pointer<F3dWgpuRead> Function(
    Pointer<F3dWgpu>,
    Pointer<F3dWgpuBuffer>,
    Uint64,
    Uint64,
  )
>()
external Pointer<F3dWgpuRead> f3d_wgpu_read_begin(
  Pointer<F3dWgpu> gpu,
  Pointer<F3dWgpuBuffer> buffer,
  int offset,
  int size,
);

/// Turns the device's events over once, or until [read] is done when
/// [wait] is non-zero. Returns zero while in flight, one once the bytes are
/// in [out] (`nullptr` drops them) and minus one when it failed; [read] is
/// freed in the last two cases.
@Native<Int32 Function(Pointer<F3dWgpuRead>, Pointer<Void>, Int32)>()
external int f3d_wgpu_read_poll(
  Pointer<F3dWgpuRead> read,
  Pointer<Void> out,
  int wait,
);

/// Lets go of [buffer] and of every bind group a kernel kept for it.
@Native<Void Function(Pointer<F3dWgpuBuffer>)>()
external void f3d_wgpu_buffer_release(Pointer<F3dWgpuBuffer> buffer);

/// An RGBA8 texture of [width] by [height] pixels, sampled and copied, and
/// a storage texture when [storage] is non-zero; `nullptr` on failure.
@Native<
  Pointer<F3dWgpuTexture> Function(Pointer<F3dWgpu>, Uint32, Uint32, Int32)
>()
external Pointer<F3dWgpuTexture> f3d_wgpu_texture_create(
  Pointer<F3dWgpu> gpu,
  int width,
  int height,
  int storage,
);

/// Writes width × height × 4 tightly packed bytes from [rgba] into
/// [texture].
@Native<
  Void Function(Pointer<F3dWgpu>, Pointer<F3dWgpuTexture>, Pointer<Void>)
>()
external void f3d_wgpu_texture_write(
  Pointer<F3dWgpu> gpu,
  Pointer<F3dWgpuTexture> texture,
  Pointer<Void> rgba,
);

/// Reads width × height × 4 tightly packed bytes of [texture] into [rgba];
/// one on success.
@Native<
  Int32 Function(Pointer<F3dWgpu>, Pointer<F3dWgpuTexture>, Pointer<Void>)
>()
external int f3d_wgpu_texture_read(
  Pointer<F3dWgpu> gpu,
  Pointer<F3dWgpuTexture> texture,
  Pointer<Void> rgba,
);

/// The texture's `id<MTLTexture>` where the backend is Metal, otherwise
/// `nullptr`.
@Native<Pointer<Void> Function(Pointer<F3dWgpuTexture>)>(isLeaf: true)
external Pointer<Void> f3d_wgpu_texture_native_metal(
  Pointer<F3dWgpuTexture> texture,
);

/// Lets go of [texture], its view and every bind group a kernel kept for
/// it; `nullptr` is ignored.
@Native<Void Function(Pointer<F3dWgpuTexture>)>()
external void f3d_wgpu_texture_release(Pointer<F3dWgpuTexture> texture);

/// A kernel from the NUL-terminated WGSL module [wgsl]'s entry point
/// [entry], with [count] bindings in group zero of the `wgpu*` kinds in
/// [kinds]. `nullptr`, with the reason written into [error] up to
/// [capacity] bytes, when the module or the layout does not validate.
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

/// Frees [kernel] and the bind groups it kept; `nullptr` is ignored.
@Native<Void Function(Pointer<F3dWgpuKernel>)>()
external void f3d_wgpu_kernel_release(Pointer<F3dWgpuKernel> kernel);

/// Opens a compute pass whose dispatches are recorded in order and run on
/// [f3d_wgpu_pass_submit]; `nullptr` when it could not be allocated.
@Native<Pointer<F3dWgpuPass> Function(Pointer<F3dWgpu>)>()
external Pointer<F3dWgpuPass> f3d_wgpu_pass_begin(Pointer<F3dWgpu> gpu);

/// Records [kernel] over [x] × [y] × [z] workgroups with [count] resources,
/// one per binding: an [F3dWgpuBuffer] with its byte range in [offsets] and
/// [sizes] (a size of zero meaning to the end), or an [F3dWgpuTexture].
/// One on success.
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

/// Submits [pass] and frees it; one when nothing in it failed validation.
@Native<Int32 Function(Pointer<F3dWgpuPass>)>()
external int f3d_wgpu_pass_submit(Pointer<F3dWgpuPass> pass);

/// Blocks until everything submitted on [gpu] has finished.
@Native<Void Function(Pointer<F3dWgpu>)>()
external void f3d_wgpu_finish(Pointer<F3dWgpu> gpu);
