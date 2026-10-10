/*
 * The GPU passes — P9, phase 10: a wgpu device, and what every pass shares
 * (f3d_gpu_internal.h). The passes are in their own files: particles,
 * debris.
 *
 * Written against wgpu-native's webgpu.h of v29: string views, callbacks
 * given as info structs and fired from wgpuInstanceProcessEvents, and
 * wgpuDevicePoll to wait for the queue.
 */
#include <stdlib.h>
#include <string.h>

#include "f3d_gpu_internal.h"

WGPUStringView f3d_gpu_view(const char *s) {
  WGPUStringView v;
  v.data = s;
  v.length = WGPU_STRLEN;
  return v;
}

uint32_t f3d_gpu_abi_version(void) { return F3D_GPU_ABI_VERSION; }

typedef struct Waiting {
  int done;
  void *result;
} Waiting;

static void got_adapter(WGPURequestAdapterStatus status, WGPUAdapter adapter,
                        WGPUStringView message, void *userdata1, void *userdata2) {
  (void)message;
  (void)userdata2;
  Waiting *w = (Waiting *)userdata1;
  w->result = status == WGPURequestAdapterStatus_Success ? (void *)adapter : NULL;
  w->done = 1;
}

static void got_device(WGPURequestDeviceStatus status, WGPUDevice device,
                       WGPUStringView message, void *userdata1, void *userdata2) {
  (void)message;
  (void)userdata2;
  Waiting *w = (Waiting *)userdata1;
  w->result = status == WGPURequestDeviceStatus_Success ? (void *)device : NULL;
  w->done = 1;
}

/* Turns the instance's events over until [done] is set, or gives up. */
static void wait_for(WGPUInstance instance, const int *done) {
  for (int i = 0; i < 100000 && !*done; i++) wgpuInstanceProcessEvents(instance);
}

F3dGpu *f3d_gpu_create(void) {
  F3dGpu *gpu = (F3dGpu *)calloc(1, sizeof(F3dGpu));
  if (gpu == NULL) return NULL;
  gpu->instance = wgpuCreateInstance(NULL);
  if (gpu->instance == NULL) {
    free(gpu);
    return NULL;
  }
  WGPURequestAdapterOptions options;
  memset(&options, 0, sizeof options);
  options.powerPreference = WGPUPowerPreference_HighPerformance;
  WGPURequestAdapterCallbackInfo adapter_info;
  memset(&adapter_info, 0, sizeof adapter_info);
  Waiting wa = {0, NULL};
  adapter_info.mode = WGPUCallbackMode_AllowProcessEvents;
  adapter_info.callback = got_adapter;
  adapter_info.userdata1 = &wa;
  wgpuInstanceRequestAdapter(gpu->instance, &options, adapter_info);
  wait_for(gpu->instance, &wa.done);
  gpu->adapter = (WGPUAdapter)wa.result;
  if (gpu->adapter == NULL) {
    f3d_gpu_destroy(gpu);
    return NULL;
  }
  WGPURequestDeviceCallbackInfo device_info;
  memset(&device_info, 0, sizeof device_info);
  Waiting wd = {0, NULL};
  device_info.mode = WGPUCallbackMode_AllowProcessEvents;
  device_info.callback = got_device;
  device_info.userdata1 = &wd;
  wgpuAdapterRequestDevice(gpu->adapter, NULL, device_info);
  wait_for(gpu->instance, &wd.done);
  gpu->device = (WGPUDevice)wd.result;
  if (gpu->device == NULL) {
    f3d_gpu_destroy(gpu);
    return NULL;
  }
  gpu->queue = wgpuDeviceGetQueue(gpu->device);
  WGPUAdapterInfo info;
  memset(&info, 0, sizeof info);
  if (wgpuAdapterGetInfo(gpu->adapter, &info) == WGPUStatus_Success) {
    if (info.device.data != NULL) {
      size_t n = info.device.length == WGPU_STRLEN ? strlen(info.device.data)
                                                   : info.device.length;
      if (n >= sizeof gpu->name) n = sizeof gpu->name - 1u;
      memcpy(gpu->name, info.device.data, n);
      gpu->name[n] = '\0';
    }
    wgpuAdapterInfoFreeMembers(info);
  }
  return gpu;
}

void f3d_gpu_destroy(F3dGpu *gpu) {
  if (gpu == NULL) return;
  if (gpu->queue != NULL) wgpuQueueRelease(gpu->queue);
  if (gpu->device != NULL) wgpuDeviceRelease(gpu->device);
  if (gpu->adapter != NULL) wgpuAdapterRelease(gpu->adapter);
  if (gpu->instance != NULL) wgpuInstanceRelease(gpu->instance);
  free(gpu);
}

uint32_t f3d_gpu_adapter_name(const F3dGpu *gpu, char *out, uint32_t capacity) {
  const size_t n = strlen(gpu->name);
  if (capacity > 0) {
    const size_t k = n < capacity - 1u ? n : capacity - 1u;
    memcpy(out, gpu->name, k);
    out[k] = '\0';
  }
  return (uint32_t)n;
}

WGPUBuffer f3d_gpu_buffer(const F3dGpu *gpu, WGPUBufferUsage usage, uint64_t size) {
  WGPUBufferDescriptor d;
  memset(&d, 0, sizeof d);
  d.usage = usage;
  /* wgpu refuses a binding of nought bytes, and copies in fours. */
  d.size = size < 16u ? 16u : (size + 3u) & ~(uint64_t)3u;
  return wgpuDeviceCreateBuffer(gpu->device, &d);
}

void f3d_gpu_finish(const F3dGpu *gpu) { wgpuDevicePoll(gpu->device, 1, NULL); }

typedef struct Scope {
  int done;
  int failed;
} Scope;

static void scope_popped(WGPUPopErrorScopeStatus status, WGPUErrorType type,
                         WGPUStringView message, void *userdata1, void *userdata2) {
  (void)message;
  (void)userdata2;
  Scope *scope = (Scope *)userdata1;
  scope->failed = status != WGPUPopErrorScopeStatus_Success || type != WGPUErrorType_NoError;
  scope->done = 1;
}

/* Whether anything since the matching push failed validation: so a WGSL
 * module that does not compile makes a kernel set that is not, instead of
 * a device error that ends the process. */
static int scope_failed(const F3dGpu *gpu) {
  Scope scope = {0, 0};
  WGPUPopErrorScopeCallbackInfo info;
  memset(&info, 0, sizeof info);
  info.mode = WGPUCallbackMode_AllowProcessEvents;
  info.callback = scope_popped;
  info.userdata1 = &scope;
  wgpuDevicePopErrorScope(gpu->device, info);
  wait_for(gpu->instance, &scope.done);
  return !scope.done || scope.failed;
}

static int kernels_build(F3dGpuKernels *k, const F3dGpu *gpu, const char *source,
                         const char *const *entries, uint32_t entry_count,
                         const F3dGpuBinding *kinds, const WGPUBuffer *buffers,
                         const uint64_t *sizes, uint32_t binding_count);

int f3d_gpu_kernels_create(F3dGpuKernels *k, const F3dGpu *gpu, const char *source,
                           const char *const *entries, uint32_t entry_count,
                           const F3dGpuBinding *kinds, const WGPUBuffer *buffers,
                           const uint64_t *sizes, uint32_t binding_count) {
  wgpuDevicePushErrorScope(gpu->device, WGPUErrorFilter_Validation);
  const int built =
      kernels_build(k, gpu, source, entries, entry_count, kinds, buffers, sizes, binding_count);
  const int failed = scope_failed(gpu);
  if (built && failed) f3d_gpu_kernels_release(k);
  return built && !failed;
}

static int kernels_build(F3dGpuKernels *k, const F3dGpu *gpu, const char *source,
                           const char *const *entries, uint32_t entry_count,
                           const F3dGpuBinding *kinds, const WGPUBuffer *buffers,
                           const uint64_t *sizes, uint32_t binding_count) {
  memset(k, 0, sizeof *k);
  if (entry_count > F3D_GPU_MAX_KERNELS || binding_count > 16u) return 0;
  WGPUShaderSourceWGSL wgsl;
  memset(&wgsl, 0, sizeof wgsl);
  wgsl.chain.sType = WGPUSType_ShaderSourceWGSL;
  wgsl.code = f3d_gpu_view(source);
  WGPUShaderModuleDescriptor md;
  memset(&md, 0, sizeof md);
  md.nextInChain = &wgsl.chain;
  k->module = wgpuDeviceCreateShaderModule(gpu->device, &md);
  WGPUBindGroupLayoutEntry layout_entries[16];
  WGPUBindGroupEntry bind_entries[16];
  memset(layout_entries, 0, sizeof layout_entries);
  memset(bind_entries, 0, sizeof bind_entries);
  for (uint32_t i = 0; i < binding_count; i++) {
    layout_entries[i].binding = i;
    layout_entries[i].visibility = WGPUShaderStage_Compute;
    const int at = kinds[i] == F3D_GPU_UNIFORM_AT;
    layout_entries[i].buffer.type = kinds[i] == F3D_GPU_UNIFORM || at ? WGPUBufferBindingType_Uniform
                                    : kinds[i] == F3D_GPU_STORAGE     ? WGPUBufferBindingType_Storage
                                                                      : WGPUBufferBindingType_ReadOnlyStorage;
    layout_entries[i].buffer.hasDynamicOffset = at;
    if (at) k->bound_at = 1;
    bind_entries[i].binding = i;
    bind_entries[i].buffer = buffers[i];
    bind_entries[i].size = sizes[i] < 16u ? 16u : (sizes[i] + 3u) & ~(uint64_t)3u;
  }
  WGPUBindGroupLayoutDescriptor ld;
  memset(&ld, 0, sizeof ld);
  ld.entryCount = binding_count;
  ld.entries = layout_entries;
  k->layout = wgpuDeviceCreateBindGroupLayout(gpu->device, &ld);
  WGPUPipelineLayoutDescriptor pld;
  memset(&pld, 0, sizeof pld);
  pld.bindGroupLayoutCount = 1;
  pld.bindGroupLayouts = &k->layout;
  k->pipeline_layout = wgpuDeviceCreatePipelineLayout(gpu->device, &pld);
  if (k->module == NULL || k->layout == NULL || k->pipeline_layout == NULL) {
    f3d_gpu_kernels_release(k);
    return 0;
  }
  for (uint32_t i = 0; i < entry_count; i++) {
    WGPUComputePipelineDescriptor pd;
    memset(&pd, 0, sizeof pd);
    pd.layout = k->pipeline_layout;
    pd.compute.module = k->module;
    pd.compute.entryPoint = f3d_gpu_view(entries[i]);
    k->pipelines[i] = wgpuDeviceCreateComputePipeline(gpu->device, &pd);
    k->count = i + 1u;
    if (k->pipelines[i] == NULL) {
      f3d_gpu_kernels_release(k);
      return 0;
    }
  }
  WGPUBindGroupDescriptor bd;
  memset(&bd, 0, sizeof bd);
  bd.layout = k->layout;
  bd.entryCount = binding_count;
  bd.entries = bind_entries;
  k->bind = wgpuDeviceCreateBindGroup(gpu->device, &bd);
  if (k->bind == NULL) {
    f3d_gpu_kernels_release(k);
    return 0;
  }
  return 1;
}

void f3d_gpu_kernels_release(F3dGpuKernels *k) {
  if (k->bind != NULL) wgpuBindGroupRelease(k->bind);
  for (uint32_t i = 0; i < k->count; i++) {
    if (k->pipelines[i] != NULL) wgpuComputePipelineRelease(k->pipelines[i]);
  }
  if (k->pipeline_layout != NULL) wgpuPipelineLayoutRelease(k->pipeline_layout);
  if (k->layout != NULL) wgpuBindGroupLayoutRelease(k->layout);
  if (k->module != NULL) wgpuShaderModuleRelease(k->module);
  memset(k, 0, sizeof *k);
}

void f3d_gpu_dispatch(WGPUComputePassEncoder pass, const F3dGpuKernels *k, uint32_t entry,
                      uint32_t threads) {
  const uint32_t nought = 0;
  wgpuComputePassEncoderSetPipeline(pass, k->pipelines[entry]);
  wgpuComputePassEncoderSetBindGroup(pass, 0, k->bind, k->bound_at ? 1u : 0u,
                                     k->bound_at ? &nought : NULL);
  wgpuComputePassEncoderDispatchWorkgroups(pass, (threads + 63u) / 64u, 1, 1);
}

void f3d_gpu_dispatch_at(WGPUComputePassEncoder pass, const F3dGpuKernels *k, uint32_t entry,
                         uint32_t threads, uint32_t offset) {
  if (threads == 0) return;
  wgpuComputePassEncoderSetPipeline(pass, k->pipelines[entry]);
  wgpuComputePassEncoderSetBindGroup(pass, 0, k->bind, 1, &offset);
  wgpuComputePassEncoderDispatchWorkgroups(pass, (threads + 63u) / 64u, 1, 1);
}

int f3d_gpu_readback_create(F3dGpuReadback *r, const F3dGpu *gpu, uint64_t bytes) {
  memset(r, 0, sizeof *r);
  r->bytes = bytes;
  for (int i = 0; i < 2; i++) {
    r->slots[i].owner = r;
    r->slots[i].staging =
        f3d_gpu_buffer(gpu, WGPUBufferUsage_MapRead | WGPUBufferUsage_CopyDst, bytes);
    if (r->slots[i].staging == NULL) {
      f3d_gpu_readback_release(r);
      return 0;
    }
  }
  return 1;
}

void f3d_gpu_readback_release(F3dGpuReadback *r) {
  for (int i = 0; i < 2; i++) {
    if (r->slots[i].staging != NULL) wgpuBufferRelease(r->slots[i].staging);
    r->slots[i].staging = NULL;
  }
}

static void mapped(WGPUMapAsyncStatus status, WGPUStringView message, void *userdata1,
                   void *userdata2) {
  (void)message;
  (void)userdata2;
  F3dGpuReadbackSlot *slot = (F3dGpuReadbackSlot *)userdata1;
  /* A map that failed leaves the slot free, its frame never returned. */
  slot->state = status == WGPUMapAsyncStatus_Success ? 2 : 0;
}

void f3d_gpu_readback_request(F3dGpuReadback *r, const F3dGpu *gpu, WGPUBuffer source,
                              uint64_t frame) {
  int pick = -1;
  for (int i = 0; i < 2 && pick < 0; i++) {
    if (r->slots[i].state == 0) pick = i;
  }
  if (pick < 0) {
    /* Both taken: give up the older one that has come back. */
    for (int i = 0; i < 2; i++) {
      if (r->slots[i].state == 2 && (pick < 0 || r->slots[i].frame < r->slots[pick].frame)) {
        pick = i;
      }
    }
    if (pick < 0) return;
    wgpuBufferUnmap(r->slots[pick].staging);
    r->slots[pick].state = 0;
  }
  F3dGpuReadbackSlot *slot = &r->slots[pick];
  WGPUCommandEncoder encoder = wgpuDeviceCreateCommandEncoder(gpu->device, NULL);
  wgpuCommandEncoderCopyBufferToBuffer(encoder, source, 0, slot->staging, 0, r->bytes);
  WGPUCommandBuffer commands = wgpuCommandEncoderFinish(encoder, NULL);
  wgpuQueueSubmit(gpu->queue, 1, &commands);
  wgpuCommandBufferRelease(commands);
  wgpuCommandEncoderRelease(encoder);
  slot->state = 1;
  slot->frame = frame;
  WGPUBufferMapCallbackInfo info;
  memset(&info, 0, sizeof info);
  info.mode = WGPUCallbackMode_AllowProcessEvents;
  info.callback = mapped;
  info.userdata1 = slot;
  wgpuBufferMapAsync(slot->staging, WGPUMapMode_Read, 0, (size_t)r->bytes, info);
}

static void pump(const F3dGpu *gpu, int wait) {
  wgpuDevicePoll(gpu->device, wait, NULL);
  wgpuInstanceProcessEvents(gpu->instance);
}

uint64_t f3d_gpu_readback_take(F3dGpuReadback *r, const F3dGpu *gpu, WGPUBuffer source,
                               uint64_t frame, int wait,
                               void (*copy)(const void *mapped, void *out, uint32_t n),
                               void *out, uint32_t n) {
  pump(gpu, 0);
  if (wait && frame > r->taken) {
    for (int tries = 0; tries < 1000; tries++) {
      int asked = 0;
      for (int i = 0; i < 2; i++) asked |= r->slots[i].state != 0 && r->slots[i].frame == frame;
      if (asked) break;
      f3d_gpu_readback_request(r, gpu, source, frame);
      /* Both still on their way: let one come back first. */
      pump(gpu, 1);
    }
    for (int tries = 0; tries < 1000; tries++) {
      int back = 0;
      for (int i = 0; i < 2; i++) back |= r->slots[i].state == 2 && r->slots[i].frame == frame;
      if (back) break;
      pump(gpu, 1);
    }
  }
  int best = -1;
  for (int i = 0; i < 2; i++) {
    F3dGpuReadbackSlot *slot = &r->slots[i];
    if (slot->state != 2) continue;
    if (slot->frame <= r->taken) {
      wgpuBufferUnmap(slot->staging);
      slot->state = 0;
      continue;
    }
    if (best < 0 || slot->frame > r->slots[best].frame) best = i;
  }
  if (best < 0) return 0;
  F3dGpuReadbackSlot *slot = &r->slots[best];
  const void *data = wgpuBufferGetConstMappedRange(slot->staging, 0, (size_t)r->bytes);
  if (data == NULL) return 0;
  copy(data, out, n);
  wgpuBufferUnmap(slot->staging);
  slot->state = 0;
  r->taken = slot->frame;
  /* The other, older and come back, is past. */
  for (int i = 0; i < 2; i++) {
    if (r->slots[i].state == 2 && r->slots[i].frame <= r->taken) {
      wgpuBufferUnmap(r->slots[i].staging);
      r->slots[i].state = 0;
    }
  }
  return r->taken;
}
