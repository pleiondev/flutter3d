/*
 * The GPU passes — P9, phase 10: a wgpu device, and particles stepped by a
 * compute shader that does what f3d_particles.c does, line for line.
 *
 * Written against wgpu-native's webgpu.h of v29: string views, callbacks
 * given as info structs and fired from wgpuInstanceProcessEvents, and
 * wgpuDevicePoll to wait for the queue.
 */
#include "f3d_gpu.h"

#include <stdlib.h>
#include <string.h>

#include "webgpu/webgpu.h"
#include "webgpu/wgpu.h"

struct F3dGpu {
  WGPUInstance instance;
  WGPUAdapter adapter;
  WGPUDevice device;
  WGPUQueue queue;
  char name[256];
};

struct F3dGpuParticles {
  F3dGpu *gpu;
  uint32_t capacity;
  uint32_t next;
  WGPUBuffer slots;
  WGPUBuffer staging;
  WGPUBuffer forces;
  WGPUShaderModule module;
  WGPUComputePipeline pipeline;
  WGPUBindGroup bind;
};

/* The particles' step: f3d_particles_step, in WGSL. */
static const char kParticleShader[] =
    "struct Particle { pos_life : vec4<f32>, vel : vec4<f32> };\n"
    "struct Forces {\n"
    "  gravity : vec4<f32>, wind : vec4<f32>,\n"
    "  params : vec4<f32>,  // drag, floor, restitution, friction\n"
    "  dt : f32, count : u32, pad0 : u32, pad1 : u32,\n"
    "};\n"
    "@group(0) @binding(0) var<storage, read_write> slots : array<Particle>;\n"
    "@group(0) @binding(1) var<uniform> forces : Forces;\n"
    "@compute @workgroup_size(64)\n"
    "fn step(@builtin(global_invocation_id) id : vec3<u32>) {\n"
    "  let i = id.x;\n"
    "  if (i >= forces.count) { return; }\n"
    "  let p = slots[i];\n"
    "  if (!(p.pos_life.w > 0.0)) { return; }\n"
    "  let dt = forces.dt;\n"
    "  var v = p.vel.xyz + forces.gravity.xyz * dt;\n"
    "  let keep = 1.0 / (1.0 + forces.params.x * dt);\n"
    "  v = forces.wind.xyz + (v - forces.wind.xyz) * keep;\n"
    "  var x = p.pos_life.xyz + v * dt;\n"
    "  if (x.y < forces.params.y) {\n"
    "    x.y = forces.params.y;\n"
    "    if (v.y < 0.0) { v.y = -v.y * forces.params.z; }\n"
    "    let slide = 1.0 - forces.params.w;\n"
    "    v.x = v.x * slide;\n"
    "    v.z = v.z * slide;\n"
    "  }\n"
    "  slots[i] = Particle(vec4<f32>(x, p.pos_life.w - dt), vec4<f32>(v, 0.0));\n"
    "}\n";

static WGPUStringView view(const char *s) {
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
                        WGPUStringView message, void *userdata1,
                        void *userdata2) {
  (void)message;
  (void)userdata2;
  Waiting *w = (Waiting *)userdata1;
  w->result = status == WGPURequestAdapterStatus_Success ? (void *)adapter : NULL;
  w->done = 1;
}

static void got_device(WGPURequestDeviceStatus status, WGPUDevice device,
                       WGPUStringView message, void *userdata1,
                       void *userdata2) {
  (void)message;
  (void)userdata2;
  Waiting *w = (Waiting *)userdata1;
  w->result = status == WGPURequestDeviceStatus_Success ? (void *)device : NULL;
  w->done = 1;
}

/* Turns the instance's events over until [w] is answered, or gives up. */
static void wait_for(WGPUInstance instance, Waiting *w) {
  for (int i = 0; i < 100000 && !w->done; i++) {
    wgpuInstanceProcessEvents(instance);
  }
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
  wait_for(gpu->instance, &wa);
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
  wait_for(gpu->instance, &wd);
  gpu->device = (WGPUDevice)wd.result;
  if (gpu->device == NULL) {
    f3d_gpu_destroy(gpu);
    return NULL;
  }
  gpu->queue = wgpuDeviceGetQueue(gpu->device);
  WGPUAdapterInfo info;
  memset(&info, 0, sizeof info);
  if (wgpuAdapterGetInfo(gpu->adapter, &info) == WGPUStatus_Success &&
      info.device.data != NULL) {
    size_t n = info.device.length == WGPU_STRLEN ? strlen(info.device.data)
                                                 : info.device.length;
    if (n >= sizeof gpu->name) n = sizeof gpu->name - 1u;
    memcpy(gpu->name, info.device.data, n);
    gpu->name[n] = '\0';
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

/* Thirty-two bytes a slot: position and life, velocity and a spare. */
#define SLOT_BYTES 32u
/* Sixty-four bytes of forces, as the shader's struct lays them out. */
#define FORCES_BYTES 64u

static WGPUBuffer buffer(WGPUDevice device, WGPUBufferUsage usage, uint64_t size) {
  WGPUBufferDescriptor d;
  memset(&d, 0, sizeof d);
  d.usage = usage;
  d.size = size;
  return wgpuDeviceCreateBuffer(device, &d);
}

F3dGpuParticles *f3d_gpu_particles_create(F3dGpu *gpu, uint32_t capacity) {
  if (gpu == NULL || capacity == 0 || capacity > (1u << 24)) return NULL;
  F3dGpuParticles *p = (F3dGpuParticles *)calloc(1, sizeof(F3dGpuParticles));
  if (p == NULL) return NULL;
  p->gpu = gpu;
  p->capacity = capacity;
  const uint64_t bytes = (uint64_t)capacity * SLOT_BYTES;
  p->slots = buffer(gpu->device,
                    WGPUBufferUsage_Storage | WGPUBufferUsage_CopyDst |
                        WGPUBufferUsage_CopySrc,
                    bytes);
  p->staging = buffer(gpu->device, WGPUBufferUsage_MapRead | WGPUBufferUsage_CopyDst,
                      bytes);
  p->forces = buffer(gpu->device, WGPUBufferUsage_Uniform | WGPUBufferUsage_CopyDst,
                     FORCES_BYTES);
  if (p->slots == NULL || p->staging == NULL || p->forces == NULL) {
    f3d_gpu_particles_destroy(p);
    return NULL;
  }
  /* All dead: zeroed, so every life is nought. */
  void *zero = calloc(1, (size_t)bytes);
  if (zero == NULL) {
    f3d_gpu_particles_destroy(p);
    return NULL;
  }
  wgpuQueueWriteBuffer(gpu->queue, p->slots, 0, zero, (size_t)bytes);
  free(zero);
  WGPUShaderSourceWGSL wgsl;
  memset(&wgsl, 0, sizeof wgsl);
  wgsl.chain.sType = WGPUSType_ShaderSourceWGSL;
  wgsl.code = view(kParticleShader);
  WGPUShaderModuleDescriptor md;
  memset(&md, 0, sizeof md);
  md.nextInChain = &wgsl.chain;
  p->module = wgpuDeviceCreateShaderModule(gpu->device, &md);
  WGPUComputePipelineDescriptor pd;
  memset(&pd, 0, sizeof pd);
  pd.compute.module = p->module;
  pd.compute.entryPoint = view("step");
  p->pipeline = wgpuDeviceCreateComputePipeline(gpu->device, &pd);
  if (p->module == NULL || p->pipeline == NULL) {
    f3d_gpu_particles_destroy(p);
    return NULL;
  }
  WGPUBindGroupEntry entries[2];
  memset(entries, 0, sizeof entries);
  entries[0].binding = 0;
  entries[0].buffer = p->slots;
  entries[0].size = bytes;
  entries[1].binding = 1;
  entries[1].buffer = p->forces;
  entries[1].size = FORCES_BYTES;
  WGPUBindGroupLayout layout = wgpuComputePipelineGetBindGroupLayout(p->pipeline, 0);
  WGPUBindGroupDescriptor bd;
  memset(&bd, 0, sizeof bd);
  bd.layout = layout;
  bd.entryCount = 2;
  bd.entries = entries;
  p->bind = wgpuDeviceCreateBindGroup(gpu->device, &bd);
  wgpuBindGroupLayoutRelease(layout);
  if (p->bind == NULL) {
    f3d_gpu_particles_destroy(p);
    return NULL;
  }
  return p;
}

void f3d_gpu_particles_destroy(F3dGpuParticles *p) {
  if (p == NULL) return;
  if (p->bind != NULL) wgpuBindGroupRelease(p->bind);
  if (p->pipeline != NULL) wgpuComputePipelineRelease(p->pipeline);
  if (p->module != NULL) wgpuShaderModuleRelease(p->module);
  if (p->forces != NULL) wgpuBufferRelease(p->forces);
  if (p->staging != NULL) wgpuBufferRelease(p->staging);
  if (p->slots != NULL) wgpuBufferRelease(p->slots);
  free(p);
}

uint32_t f3d_gpu_particles_emit(F3dGpuParticles *p, const float *data,
                                uint32_t count) {
  const uint32_t first = p->next;
  float slot[8];
  for (uint32_t i = 0; i < count; i++) {
    const float *d = data + (size_t)i * 7u;
    slot[0] = d[0];
    slot[1] = d[1];
    slot[2] = d[2];
    slot[3] = d[6];
    slot[4] = d[3];
    slot[5] = d[4];
    slot[6] = d[5];
    slot[7] = 0.0f;
    wgpuQueueWriteBuffer(p->gpu->queue, p->slots, (uint64_t)p->next * SLOT_BYTES,
                         slot, sizeof slot);
    p->next = (p->next + 1u) % p->capacity;
  }
  return first;
}

void f3d_gpu_particles_step(F3dGpuParticles *p, const F3dGpuParticleForces *f,
                            float dt, uint32_t steps) {
  if (!(dt > 0.0f) || steps == 0) return;
  float forces[16];
  memset(forces, 0, sizeof forces);
  forces[0] = f->gravity[0];
  forces[1] = f->gravity[1];
  forces[2] = f->gravity[2];
  forces[4] = f->wind[0];
  forces[5] = f->wind[1];
  forces[6] = f->wind[2];
  forces[8] = f->drag;
  forces[9] = f->floor_y;
  forces[10] = f->restitution;
  forces[11] = f->friction;
  forces[12] = dt;
  memcpy(&forces[13], &p->capacity, sizeof(uint32_t));
  wgpuQueueWriteBuffer(p->gpu->queue, p->forces, 0, forces, sizeof forces);
  WGPUCommandEncoder encoder = wgpuDeviceCreateCommandEncoder(p->gpu->device, NULL);
  WGPUComputePassEncoder pass = wgpuCommandEncoderBeginComputePass(encoder, NULL);
  wgpuComputePassEncoderSetPipeline(pass, p->pipeline);
  wgpuComputePassEncoderSetBindGroup(pass, 0, p->bind, 0, NULL);
  const uint32_t groups = (p->capacity + 63u) / 64u;
  /* One dispatch a step: each is its own usage scope, so a step sees the
   * last one's writes. */
  for (uint32_t s = 0; s < steps; s++) {
    wgpuComputePassEncoderDispatchWorkgroups(pass, groups, 1, 1);
  }
  wgpuComputePassEncoderEnd(pass);
  wgpuComputePassEncoderRelease(pass);
  WGPUCommandBuffer commands = wgpuCommandEncoderFinish(encoder, NULL);
  wgpuQueueSubmit(p->gpu->queue, 1, &commands);
  wgpuCommandBufferRelease(commands);
  wgpuCommandEncoderRelease(encoder);
}

static void mapped(WGPUMapAsyncStatus status, WGPUStringView message,
                   void *userdata1, void *userdata2) {
  (void)message;
  (void)userdata2;
  Waiting *w = (Waiting *)userdata1;
  w->result = status == WGPUMapAsyncStatus_Success ? (void *)1 : NULL;
  w->done = 1;
}

uint32_t f3d_gpu_particles_read(F3dGpuParticles *p, float *out,
                                uint32_t capacity) {
  const uint64_t bytes = (uint64_t)p->capacity * SLOT_BYTES;
  WGPUCommandEncoder encoder = wgpuDeviceCreateCommandEncoder(p->gpu->device, NULL);
  wgpuCommandEncoderCopyBufferToBuffer(encoder, p->slots, 0, p->staging, 0, bytes);
  WGPUCommandBuffer commands = wgpuCommandEncoderFinish(encoder, NULL);
  wgpuQueueSubmit(p->gpu->queue, 1, &commands);
  wgpuCommandBufferRelease(commands);
  wgpuCommandEncoderRelease(encoder);
  WGPUBufferMapCallbackInfo info;
  memset(&info, 0, sizeof info);
  Waiting w = {0, NULL};
  info.mode = WGPUCallbackMode_AllowProcessEvents;
  info.callback = mapped;
  info.userdata1 = &w;
  wgpuBufferMapAsync(p->staging, WGPUMapMode_Read, 0, (size_t)bytes, info);
  wgpuDevicePoll(p->gpu->device, 1, NULL);
  wait_for(p->gpu->instance, &w);
  if (w.result == NULL) return 0;
  const float *slots =
      (const float *)wgpuBufferGetConstMappedRange(p->staging, 0, (size_t)bytes);
  const uint32_t n = capacity < p->capacity ? capacity : p->capacity;
  for (uint32_t i = 0; slots != NULL && i < n; i++) {
    out[i * 4u] = slots[i * 8u];
    out[i * 4u + 1u] = slots[i * 8u + 1u];
    out[i * 4u + 2u] = slots[i * 8u + 2u];
    out[i * 4u + 3u] = slots[i * 8u + 3u];
  }
  wgpuBufferUnmap(p->staging);
  return slots != NULL ? n : 0;
}
