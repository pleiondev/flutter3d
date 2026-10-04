/*
 * What the GPU passes share — P9, phase 10: the device, waiting on it,
 * buffers, kernels built from one WGSL module with one explicit layout, and
 * reading a buffer back a frame late.
 */
#ifndef F3D_GPU_INTERNAL_H_
#define F3D_GPU_INTERNAL_H_

#include <stdint.h>

#include "f3d_gpu.h"
#include "webgpu/webgpu.h"
#include "webgpu/wgpu.h"

struct F3dGpu {
  WGPUInstance instance;
  WGPUAdapter adapter;
  WGPUDevice device;
  WGPUQueue queue;
  char name[256];
};

/* A null-terminated string as wgpu takes one. */
WGPUStringView f3d_gpu_view(const char *s);

WGPUBuffer f3d_gpu_buffer(const F3dGpu *gpu, WGPUBufferUsage usage, uint64_t size);

/* Waits for everything submitted to [gpu]'s queue. */
void f3d_gpu_finish(const F3dGpu *gpu);

/* What a kernel binding is. */
typedef enum F3dGpuBinding {
  F3D_GPU_UNIFORM,
  /* A uniform of the given size, bound at an offset each dispatch gives:
   * at most one in a set of kernels. */
  F3D_GPU_UNIFORM_AT,
  F3D_GPU_STORAGE,
  F3D_GPU_READ_ONLY,
} F3dGpuBinding;

#define F3D_GPU_MAX_KERNELS 16

/* The entry points of one WGSL module, sharing one bind group whose
 * bindings are numbered from nought in the order given. */
typedef struct F3dGpuKernels {
  WGPUShaderModule module;
  WGPUBindGroupLayout layout;
  WGPUPipelineLayout pipeline_layout;
  WGPUComputePipeline pipelines[F3D_GPU_MAX_KERNELS];
  uint32_t count;
  WGPUBindGroup bind;
  /* Whether a binding is F3D_GPU_UNIFORM_AT: every dispatch then gives an
   * offset, nought when it does not care. */
  int bound_at;
} F3dGpuKernels;

/* Compiles [source] and makes a pipeline for each of [entries]; then binds
 * [buffers], with [sizes], to the bindings of [kinds]. 0 on failure, with
 * whatever was made released. */
int f3d_gpu_kernels_create(F3dGpuKernels *k, const F3dGpu *gpu, const char *source,
                           const char *const *entries, uint32_t entry_count,
                           const F3dGpuBinding *kinds, const WGPUBuffer *buffers,
                           const uint64_t *sizes, uint32_t binding_count);
void f3d_gpu_kernels_release(F3dGpuKernels *k);

/* Dispatches entry [entry] over [threads] threads, sixty-four a group. */
void f3d_gpu_dispatch(WGPUComputePassEncoder pass, const F3dGpuKernels *k, uint32_t entry,
                      uint32_t threads);

/* The same, with the kernels' F3D_GPU_UNIFORM_AT binding at [offset], a
 * multiple of 256. */
void f3d_gpu_dispatch_at(WGPUComputePassEncoder pass, const F3dGpuKernels *k, uint32_t entry,
                         uint32_t threads, uint32_t offset);

/* A buffer read back without waiting: each step copies it into one of two
 * staging buffers and maps that, and a read takes whichever has come back
 * latest. */
typedef struct F3dGpuReadback F3dGpuReadback;

typedef struct F3dGpuReadbackSlot {
  F3dGpuReadback *owner;
  WGPUBuffer staging;
  /* 0 free, 1 copying and mapping, 2 mapped. */
  int state;
  uint64_t frame;
} F3dGpuReadbackSlot;

struct F3dGpuReadback {
  F3dGpuReadbackSlot slots[2];
  uint64_t bytes;
  /* The last frame a read returned: older ones coming back are dropped. */
  uint64_t taken;
};

int f3d_gpu_readback_create(F3dGpuReadback *r, const F3dGpu *gpu, uint64_t bytes);
void f3d_gpu_readback_release(F3dGpuReadback *r);

/* Copies [source] for [frame], unless both staging buffers are still on
 * their way back. */
void f3d_gpu_readback_request(F3dGpuReadback *r, const F3dGpu *gpu, WGPUBuffer source,
                              uint64_t frame);

/* The latest frame come back and not yet read, copied by [copy] into
 * [out]; 0 when there is none. With [wait], the copy of [frame] — which is
 * asked for if it was not — is waited for. */
uint64_t f3d_gpu_readback_take(F3dGpuReadback *r, const F3dGpu *gpu, WGPUBuffer source,
                               uint64_t frame, int wait,
                               void (*copy)(const void *mapped, void *out, uint32_t n),
                               void *out, uint32_t n);

#endif /* F3D_GPU_INTERNAL_H_ */
