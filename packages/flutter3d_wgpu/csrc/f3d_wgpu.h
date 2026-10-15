/*
 * The compute sidecar's C surface: a wgpu device, buffers, RGBA8 textures,
 * kernels compiled from WGSL, and compute passes — what
 * `lib/src/wgpu_bindings.dart` binds through dart:ffi.
 *
 * Narrow on purpose. wgpu's own API is struct-heavy and moves between
 * releases; this is the subset a compute step needs, in plain integers and
 * pointers, versioned by F3D_WGPU_ABI_VERSION, so the Dart side binds a
 * dozen functions instead of webgpu.h.
 */
#ifndef F3D_WGPU_H_
#define F3D_WGPU_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define F3D_WGPU_EXPORT __declspec(dllexport)
#else
#define F3D_WGPU_EXPORT __attribute__((visibility("default")))
#endif

/* Bumped whenever a signature here changes. 2: the readback that does not
 * wait (f3d_wgpu_read_begin, f3d_wgpu_read_poll). */
#define F3D_WGPU_ABI_VERSION 2

typedef struct F3dWgpu F3dWgpu;
typedef struct F3dWgpuBuffer F3dWgpuBuffer;
typedef struct F3dWgpuTexture F3dWgpuTexture;
typedef struct F3dWgpuKernel F3dWgpuKernel;
typedef struct F3dWgpuPass F3dWgpuPass;
typedef struct F3dWgpuRead F3dWgpuRead;

/* What a kernel binding is, in binding order, group zero. */
enum {
  F3D_WGPU_STORAGE = 0,      /* var<storage, read_write> */
  F3D_WGPU_READ_ONLY = 1,    /* var<storage, read> */
  F3D_WGPU_TEXTURE = 2,      /* texture_2d<f32> */
  F3D_WGPU_IMAGE = 3,        /* texture_storage_2d<rgba8unorm, write> */
};

F3D_WGPU_EXPORT uint32_t f3d_wgpu_abi_version(void);

/* The best adapter there is, or NULL. */
F3D_WGPU_EXPORT F3dWgpu *f3d_wgpu_open(void);
F3D_WGPU_EXPORT void f3d_wgpu_close(F3dWgpu *gpu);

/* The adapter's name into [out], cut to [capacity] with its NUL; returns
 * the whole name's length. */
F3D_WGPU_EXPORT uint32_t f3d_wgpu_adapter_name(const F3dWgpu *gpu, char *out, uint32_t capacity);

/* The last validation error, as text, into [out]; returns its length, zero
 * when there was none since the last call. */
F3D_WGPU_EXPORT uint32_t f3d_wgpu_take_error(F3dWgpu *gpu, char *out, uint32_t capacity);

/* A storage buffer of [size] bytes that can be copied to and from. */
F3D_WGPU_EXPORT F3dWgpuBuffer *f3d_wgpu_buffer_create(F3dWgpu *gpu, uint64_t size);
F3D_WGPU_EXPORT void f3d_wgpu_buffer_write(F3dWgpu *gpu, F3dWgpuBuffer *buffer, uint64_t offset,
                                           const void *data, uint64_t size);
/* Copies [size] bytes from [offset] into [out] once every pass submitted
 * before is done; 1 on success. */
F3D_WGPU_EXPORT int f3d_wgpu_buffer_read(F3dWgpu *gpu, F3dWgpuBuffer *buffer, uint64_t offset,
                                         void *out, uint64_t size);
/* Starts copying [size] bytes from [offset] back, after every pass
 * submitted before, without waiting: NULL when no staging buffer could be
 * made. The staging buffer comes from a pool the device keeps. */
F3D_WGPU_EXPORT F3dWgpuRead *f3d_wgpu_read_begin(F3dWgpu *gpu, F3dWgpuBuffer *buffer,
                                                 uint64_t offset, uint64_t size);
/* Turns the device's events over once, or until the read is done when
 * [wait] is set: 0 while it is in flight; 1 once its bytes are in [out]
 * (NULL to drop them) and -1 when it failed, the read freed either way. */
F3D_WGPU_EXPORT int f3d_wgpu_read_poll(F3dWgpuRead *read, void *out, int wait);
/* Lets go of the buffer and of every bind group a kernel kept for it. */
F3D_WGPU_EXPORT void f3d_wgpu_buffer_release(F3dWgpuBuffer *buffer);

/* An RGBA8 texture, sampled and copied, and a storage texture when
 * [storage] is set. */
F3D_WGPU_EXPORT F3dWgpuTexture *f3d_wgpu_texture_create(F3dWgpu *gpu, uint32_t width,
                                                        uint32_t height, int storage);
/* Writes width × height × 4 tightly packed bytes. */
F3D_WGPU_EXPORT void f3d_wgpu_texture_write(F3dWgpu *gpu, F3dWgpuTexture *texture,
                                            const void *rgba);
/* Reads width × height × 4 tightly packed bytes; 1 on success. */
F3D_WGPU_EXPORT int f3d_wgpu_texture_read(F3dWgpu *gpu, F3dWgpuTexture *texture, void *rgba);
/* The texture's id<MTLTexture> where the backend is Metal, else NULL. */
F3D_WGPU_EXPORT void *f3d_wgpu_texture_native_metal(F3dWgpuTexture *texture);
F3D_WGPU_EXPORT void f3d_wgpu_texture_release(F3dWgpuTexture *texture);

/* A kernel from one WGSL module's [entry], its [count] bindings of [kinds].
 * NULL, with the reason in [error], when the module or the layout does not
 * validate. */
F3D_WGPU_EXPORT F3dWgpuKernel *f3d_wgpu_kernel_create(F3dWgpu *gpu, const char *wgsl,
                                                      const char *entry, const uint32_t *kinds,
                                                      uint32_t count, char *error,
                                                      uint32_t capacity);
F3D_WGPU_EXPORT void f3d_wgpu_kernel_release(F3dWgpuKernel *kernel);

/* A compute pass: dispatches recorded in order, run on submit. */
F3D_WGPU_EXPORT F3dWgpuPass *f3d_wgpu_pass_begin(F3dWgpu *gpu);
/* Dispatches [kernel] over x × y × z workgroups with [resources], one per
 * binding: an F3dWgpuBuffer (with [offsets] and [sizes], a size of zero
 * meaning to the end) or an F3dWgpuTexture. 1 on success. */
F3D_WGPU_EXPORT int f3d_wgpu_pass_dispatch(F3dWgpuPass *pass, F3dWgpuKernel *kernel,
                                           void *const *resources, const uint64_t *offsets,
                                           const uint64_t *sizes, uint32_t count, uint32_t x,
                                           uint32_t y, uint32_t z);
/* Submits the pass and frees it; 1 when nothing in it failed validation. */
F3D_WGPU_EXPORT int f3d_wgpu_pass_submit(F3dWgpuPass *pass);

/* Waits for everything submitted. */
F3D_WGPU_EXPORT void f3d_wgpu_finish(F3dWgpu *gpu);

#ifdef __cplusplus
}
#endif

#endif /* F3D_WGPU_H_ */
