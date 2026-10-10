/*
 * Particles on the GPU — P9, phase 10: a compute shader that does what
 * f3d_particles.c does, line for line.
 */
#include <stdlib.h>
#include <string.h>

#include "f3d_gpu_internal.h"

struct F3dGpuParticles {
  F3dGpu *gpu;
  uint32_t capacity;
  uint32_t next;
  uint64_t frame;
  WGPUBuffer slots;
  WGPUBuffer forces;
  F3dGpuKernels kernels;
  F3dGpuReadback readback;
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

/* Thirty-two bytes a slot: position and life, velocity and a spare. */
#define SLOT_BYTES 32u
/* Sixty-four bytes of forces, as the shader's struct lays them out. */
#define FORCES_BYTES 64u

F3dGpuParticles *f3d_gpu_particles_create(F3dGpu *gpu, uint32_t capacity) {
  if (gpu == NULL || capacity == 0 || capacity > (1u << 22)) return NULL;
  F3dGpuParticles *p = (F3dGpuParticles *)calloc(1, sizeof(F3dGpuParticles));
  if (p == NULL) return NULL;
  p->gpu = gpu;
  p->capacity = capacity;
  const uint64_t bytes = (uint64_t)capacity * SLOT_BYTES;
  p->slots = f3d_gpu_buffer(
      gpu, WGPUBufferUsage_Storage | WGPUBufferUsage_CopyDst | WGPUBufferUsage_CopySrc, bytes);
  p->forces = f3d_gpu_buffer(gpu, WGPUBufferUsage_Uniform | WGPUBufferUsage_CopyDst,
                             FORCES_BYTES);
  if (p->slots == NULL || p->forces == NULL ||
      !f3d_gpu_readback_create(&p->readback, gpu, bytes)) {
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
  static const char *const entries[] = {"step"};
  const F3dGpuBinding kinds[] = {F3D_GPU_STORAGE, F3D_GPU_UNIFORM};
  const WGPUBuffer buffers[] = {p->slots, p->forces};
  const uint64_t sizes[] = {bytes, FORCES_BYTES};
  if (!f3d_gpu_kernels_create(&p->kernels, gpu, kParticleShader, entries, 1, kinds, buffers,
                              sizes, 2)) {
    f3d_gpu_particles_destroy(p);
    return NULL;
  }
  return p;
}

void f3d_gpu_particles_destroy(F3dGpuParticles *p) {
  if (p == NULL) return;
  f3d_gpu_kernels_release(&p->kernels);
  f3d_gpu_readback_release(&p->readback);
  if (p->forces != NULL) wgpuBufferRelease(p->forces);
  if (p->slots != NULL) wgpuBufferRelease(p->slots);
  free(p);
}

uint32_t f3d_gpu_particles_emit(F3dGpuParticles *p, const float *data, uint32_t count) {
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
    wgpuQueueWriteBuffer(p->gpu->queue, p->slots, (uint64_t)p->next * SLOT_BYTES, slot,
                         sizeof slot);
    p->next = (p->next + 1u) % p->capacity;
  }
  return first;
}

void f3d_gpu_particles_step(F3dGpuParticles *p, const F3dGpuParticleForces *f, float dt,
                            uint32_t steps) {
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
  /* One dispatch a step: each is its own usage scope, so a step sees the
   * last one's writes. */
  for (uint32_t s = 0; s < steps; s++) f3d_gpu_dispatch(pass, &p->kernels, 0, p->capacity);
  wgpuComputePassEncoderEnd(pass);
  wgpuComputePassEncoderRelease(pass);
  WGPUCommandBuffer commands = wgpuCommandEncoderFinish(encoder, NULL);
  wgpuQueueSubmit(p->gpu->queue, 1, &commands);
  wgpuCommandBufferRelease(commands);
  wgpuCommandEncoderRelease(encoder);
  p->frame++;
}

static void copy_particles(const void *mapped, void *out, uint32_t n) {
  const float *slots = (const float *)mapped;
  float *o = (float *)out;
  for (uint32_t i = 0; i < n; i++) {
    o[i * 4u] = slots[i * 8u];
    o[i * 4u + 1u] = slots[i * 8u + 1u];
    o[i * 4u + 2u] = slots[i * 8u + 2u];
    o[i * 4u + 3u] = slots[i * 8u + 3u];
  }
}

uint32_t f3d_gpu_particles_read(F3dGpuParticles *p, float *out, uint32_t capacity) {
  const uint32_t n = capacity < p->capacity ? capacity : p->capacity;
  /* Always the slots as they are now, read again if read before: frames
   * are counted from one, the slots as emitted before any step. */
  p->readback.taken = 0;
  return f3d_gpu_readback_take(&p->readback, p->gpu, p->slots, p->frame + 1u, 1,
                               copy_particles, out, n) != 0
             ? n
             : 0;
}
