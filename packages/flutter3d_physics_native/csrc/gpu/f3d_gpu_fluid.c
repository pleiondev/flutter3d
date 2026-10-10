/*
 * Fluid on the GPU — P9, phase 10: what f3d_fluid.c does, pass for pass
 * and in the same order of arithmetic, read a frame late. The grid's lists
 * are built with atomicExchange, so neighbours are summed in whatever
 * order the GPU inserted them: the CPU's to the GPU's rounding.
 */
#include <stdlib.h>
#include <string.h>

#include "f3d_gpu_internal.h"

#define PARTICLE_BYTES 16u
#define PARAMS_BYTES 128u

struct F3dGpuFluid {
  F3dGpu *gpu;
  uint32_t capacity;
  uint32_t cells;
  uint32_t count;
  uint32_t next_slot;
  uint64_t frame;
  float spacing;
  float h;
  float poly6;
  float spiky;
  float rest_density;
  WGPUBuffer params;
  WGPUBuffer position;
  WGPUBuffer predicted;
  WGPUBuffer velocity;
  WGPUBuffer scratch;
  WGPUBuffer lambda;
  WGPUBuffer head;
  WGPUBuffer link;
  F3dGpuKernels kernels;
  F3dGpuReadback readback;
};

enum {
  CLEAR_CELLS,
  PREDICT,
  DENSITY,
  SPREAD,
  ADOPT_SPREAD,
  VELOCITY,
  SMOOTH,
  FINISH,
  KERNELS
};

static const char *const kEntries[KERNELS] = {
    "clear_cells", "predict", "density", "spread", "adopt_spread", "take_velocity", "smoothen", "finish",
};

static const char kFluidShader[] =
    "struct Params {\n"
    "  gravity_h : vec4<f32>,  // gravity, the substep\n"
    "  kernel : vec4<f32>,     // its width, poly6's and spiky's constants, rest density\n"
    "  tank_lo : vec4<f32>,    // the tank's low corner, one over the cell\n"
    "  tank_hi : vec4<f32>,    // the tank's high corner, viscosity\n"
    "  misc : vec4<f32>,       // relaxation, spacing\n"
    "  counts : vec4<u32>,     // particles, cells\n"
    "  wall_lo : vec4<f32>,    // the tank's walls\n"
    "  wall_hi : vec4<f32>,\n"
    "};\n"
    "@group(0) @binding(0) var<uniform> P : Params;\n"
    "@group(0) @binding(1) var<storage, read_write> position : array<vec4<f32>>;\n"
    "@group(0) @binding(2) var<storage, read_write> predicted : array<vec4<f32>>;\n"
    "@group(0) @binding(3) var<storage, read_write> velocity : array<vec4<f32>>;\n"
    "@group(0) @binding(4) var<storage, read_write> scratch : array<vec4<f32>>;\n"
    "@group(0) @binding(5) var<storage, read_write> lam : array<vec4<f32>>;\n"
    "@group(0) @binding(6) var<storage, read_write> head : array<atomic<u32>>;\n"
    "@group(0) @binding(7) var<storage, read_write> link : array<vec4<i32>>;\n"
    "const NONE : u32 = 0xFFFFFFFFu;\n"
    "fn coord(x : f32) -> i32 { return i32(floor(clamp(x * P.tank_lo.w, -1e9, 1e9))); }\n"
    "fn hash(c : vec3<i32>) -> u32 {\n"
    "  return ((bitcast<u32>(c.x) * 73856093u) ^ (bitcast<u32>(c.y) * 19349663u) ^\n"
    "          (bitcast<u32>(c.z) * 83492791u)) & (P.counts.y - 1u);\n"
    "}\n"
    "fn poly6(r2 : f32) -> f32 {\n"
    "  let d = P.kernel.x * P.kernel.x - r2;\n"
    "  if (d > 0.0) { return P.kernel.y * d * d * d; }\n"
    "  return 0.0;\n"
    "}\n"
    "fn spiky(d : vec3<f32>, r : f32) -> vec3<f32> {\n"
    "  if (!(r > 0.0) || !(r < P.kernel.x)) { return vec3<f32>(0.0); }\n"
    "  let k = P.kernel.x - r;\n"
    "  return d * (P.kernel.z * k * k / r);\n"
    "}\n"
    "@compute @workgroup_size(64)\n"
    "fn clear_cells(@builtin(global_invocation_id) id : vec3<u32>) {\n"
    "  if (id.x < P.counts.y) { atomicStore(&head[id.x], NONE); }\n"
    "}\n"
    "@compute @workgroup_size(64)\n"
    "fn predict(@builtin(global_invocation_id) id : vec3<u32>) {\n"
    "  let i = id.x;\n"
    "  if (i >= P.counts.x) { return; }\n"
    "  let v = velocity[i].xyz + P.gravity_h.xyz * P.gravity_h.w;\n"
    "  let p = position[i].xyz + v * P.gravity_h.w;\n"
    "  velocity[i] = vec4<f32>(v, 0.0);\n"
    "  predicted[i] = vec4<f32>(p, 0.0);\n"
    "  let c = vec3<i32>(coord(p.x), coord(p.y), coord(p.z));\n"
    "  let after = atomicExchange(&head[hash(c)], i);\n"
    "  link[i] = vec4<i32>(bitcast<i32>(after), c);\n"
    "}\n"
    "struct Walls { density : f32, push : vec3<f32> };\n"
    "// As f3d_fluid.c's walls(): still layers past each wall within reach.\n"
    "fn walls(p : vec3<f32>) -> Walls {\n"
    "  var w : Walls;\n"
    "  w.density = 0.0;\n"
    "  w.push = vec3<f32>(0.0);\n"
    "  let s = P.misc.y;\n"
    "  let h = P.kernel.x;\n"
    "  for (var axis = 0u; axis < 3u; axis = axis + 1u) {\n"
    "    for (var side = 0u; side < 2u; side = side + 1u) {\n"
    "      var off = P.wall_hi[axis] - p[axis];\n"
    "      if (side == 0u) { off = p[axis] - P.wall_lo[axis]; }\n"
    "      var normal = 0.0;\n"
    "      for (var z = off + s * 0.5; z < h; z = z + s) {\n"
    "        for (var i = -2; i <= 2; i = i + 1) {\n"
    "          for (var j = -2; j <= 2; j = j + 1) {\n"
    "            let r2 = f32(i * i + j * j) * s * s + z * z;\n"
    "            if (!(r2 < h * h)) { continue; }\n"
    "            w.density = w.density + poly6(r2);\n"
    "            let r = sqrt(r2);\n"
    "            let k = h - r;\n"
    "            normal = normal + P.kernel.z * k * k / r * z;\n"
    "          }\n"
    "        }\n"
    "      }\n"
    "      var dir = vec3<f32>(0.0);\n"
    "      dir[axis] = select(-1.0, 1.0, side == 0u);\n"
    "      w.push = w.push + dir * normal;\n"
    "    }\n"
    "  }\n"
    "  return w;\n"
    "}\n"
    "struct Sum { density : f32, gradient : vec3<f32>, gradient2 : f32, total : vec3<f32> };\n"
    "// What a pass sums over a particle's neighbours: 0 density, 1 spread, 2 smooth.\n"
    "fn neighbours(i : u32, visit : u32) -> Sum {\n"
    "  var sum : Sum;\n"
    "  sum.density = 0.0;\n"
    "  sum.gradient = vec3<f32>(0.0);\n"
    "  sum.gradient2 = 0.0;\n"
    "  sum.total = vec3<f32>(0.0);\n"
    "  let p = predicted[i].xyz;\n"
    "  let c = link[i].yzw;\n"
    "  let rest = P.kernel.w;\n"
    "  for (var x = c.x - 1; x <= c.x + 1; x = x + 1) {\n"
    "    for (var y = c.y - 1; y <= c.y + 1; y = y + 1) {\n"
    "      for (var z = c.z - 1; z <= c.z + 1; z = z + 1) {\n"
    "        var j = atomicLoad(&head[hash(vec3<i32>(x, y, z))]);\n"
    "        loop {\n"
    "          if (j == NONE) { break; }\n"
    "          let lj = link[j];\n"
    "          let after = bitcast<u32>(lj.x);\n"
    "          if (all(lj.yzw == vec3<i32>(x, y, z))) {\n"
    "            let d = p - predicted[j].xyz;\n"
    "            let r2 = dot(d, d);\n"
    "            if (r2 < P.kernel.x * P.kernel.x) {\n"
    "              let r = sqrt(r2);\n"
    "              if (visit == 0u) {\n"
    "                sum.density = sum.density + poly6(r2);\n"
    "                if (j != i) {\n"
    "                  let g = spiky(d, r) * (1.0 / rest);\n"
    "                  sum.gradient = sum.gradient + g;\n"
    "                  sum.gradient2 = sum.gradient2 + dot(g, g);\n"
    "                }\n"
    "              } else if (visit == 1u) {\n"
    "                if (j != i) { sum.total = sum.total + spiky(d, r) * (lam[i].x + lam[j].x); }\n"
    "              } else if (j != i) {\n"
    "                sum.total = sum.total + (velocity[j].xyz - velocity[i].xyz) * (poly6(r2) / rest);\n"
    "              }\n"
    "            }\n"
    "          }\n"
    "          j = after;\n"
    "        }\n"
    "      }\n"
    "    }\n"
    "  }\n"
    "  if (visit == 0u) {\n"
    "    let w = walls(p);\n"
    "    sum.density = sum.density + w.density;\n"
    "    sum.gradient = sum.gradient + w.push * (1.0 / rest);\n"
    "  } else if (visit == 1u) {\n"
    "    let w = walls(p);\n"
    "    sum.total = sum.total + w.push * (lam[i].x + lam[i].x);\n"
    "  }\n"
    "  return sum;\n"
    "}\n"
    "@compute @workgroup_size(64)\n"
    "fn density(@builtin(global_invocation_id) id : vec3<u32>) {\n"
    "  let i = id.x;\n"
    "  if (i >= P.counts.x) { return; }\n"
    "  let sum = neighbours(i, 0u);\n"
    "  let crowd = max(sum.density / P.kernel.w - 1.0, 0.0);\n"
    "  let lambda = -crowd / (sum.gradient2 + dot(sum.gradient, sum.gradient) + P.misc.x);\n"
    "  lam[i] = vec4<f32>(lambda, sum.density, 0.0, 0.0);\n"
    "}\n"
    "@compute @workgroup_size(64)\n"
    "fn spread(@builtin(global_invocation_id) id : vec3<u32>) {\n"
    "  let i = id.x;\n"
    "  if (i >= P.counts.x) { return; }\n"
    "  let sum = neighbours(i, 1u);\n"
    "  let p = predicted[i].xyz + sum.total * (1.0 / P.kernel.w);\n"
    "  scratch[i] = vec4<f32>(clamp(p, P.tank_lo.xyz, P.tank_hi.xyz), 0.0);\n"
    "}\n"
    "@compute @workgroup_size(64)\n"
    "fn adopt_spread(@builtin(global_invocation_id) id : vec3<u32>) {\n"
    "  if (id.x < P.counts.x) { predicted[id.x] = scratch[id.x]; }\n"
    "}\n"
    "@compute @workgroup_size(64)\n"
    "fn take_velocity(@builtin(global_invocation_id) id : vec3<u32>) {\n"
    "  let i = id.x;\n"
    "  if (i >= P.counts.x) { return; }\n"
    "  velocity[i] = vec4<f32>((predicted[i].xyz - position[i].xyz) * (1.0 / P.gravity_h.w), 0.0);\n"
    "}\n"
    "@compute @workgroup_size(64)\n"
    "fn smoothen(@builtin(global_invocation_id) id : vec3<u32>) {\n"
    "  let i = id.x;\n"
    "  if (i >= P.counts.x) { return; }\n"
    "  let sum = neighbours(i, 2u);\n"
    "  scratch[i] = vec4<f32>(velocity[i].xyz + sum.total * P.tank_hi.w, 0.0);\n"
    "}\n"
    "@compute @workgroup_size(64)\n"
    "fn finish(@builtin(global_invocation_id) id : vec3<u32>) {\n"
    "  let i = id.x;\n"
    "  if (i >= P.counts.x) { return; }\n"
    "  velocity[i] = scratch[i];\n"
    "  position[i] = vec4<f32>(predicted[i].xyz, lam[i].y / P.kernel.w);\n"
    "}\n";

/* π, a number for the kernels' constants. */
#define PI 3.14159265358979323846f

F3dGpuFluid *f3d_gpu_fluid_create(F3dGpu *gpu, uint32_t capacity, float spacing) {
  if (gpu == NULL || capacity == 0 || capacity > (1u << 22) || !(spacing > 0.0f) ||
      spacing - spacing != 0.0f) {
    return NULL;
  }
  F3dGpuFluid *f = (F3dGpuFluid *)calloc(1, sizeof(F3dGpuFluid));
  if (f == NULL) return NULL;
  f->gpu = gpu;
  f->capacity = capacity;
  uint32_t cells = 1;
  while (cells < capacity * 2u) cells <<= 1;
  f->cells = cells;
  /* The kernels, as f3d_fluid_create works them out. */
  f->spacing = spacing;
  f->h = spacing * 2.0f;
  const float h2 = f->h * f->h;
  const float h3 = h2 * f->h;
  f->poly6 = 315.0f / (64.0f * PI * h3 * h3 * h3);
  f->spiky = -45.0f / (PI * h3 * h3);
  float rest = 0;
  for (int x = -2; x <= 2; x++) {
    for (int y = -2; y <= 2; y++) {
      for (int z = -2; z <= 2; z++) {
        const float d = f->h * f->h - (float)(x * x + y * y + z * z) * spacing * spacing;
        rest += d > 0.0f ? f->poly6 * d * d * d : 0.0f;
      }
    }
  }
  f->rest_density = rest;
  const uint64_t bytes = (uint64_t)capacity * PARTICLE_BYTES;
  const WGPUBufferUsage storage = WGPUBufferUsage_Storage | WGPUBufferUsage_CopyDst;
  f->params = f3d_gpu_buffer(gpu, WGPUBufferUsage_Uniform | WGPUBufferUsage_CopyDst, PARAMS_BYTES);
  f->position = f3d_gpu_buffer(gpu, storage | WGPUBufferUsage_CopySrc, bytes);
  f->predicted = f3d_gpu_buffer(gpu, storage, bytes);
  f->velocity = f3d_gpu_buffer(gpu, storage, bytes);
  f->scratch = f3d_gpu_buffer(gpu, storage, bytes);
  f->lambda = f3d_gpu_buffer(gpu, storage, bytes);
  f->head = f3d_gpu_buffer(gpu, storage, (uint64_t)cells * 4u);
  f->link = f3d_gpu_buffer(gpu, storage, bytes);
  void *zero = calloc(1, (size_t)bytes);
  if (f->params == NULL || f->position == NULL || f->predicted == NULL || f->velocity == NULL ||
      f->scratch == NULL || f->lambda == NULL || f->head == NULL || f->link == NULL ||
      zero == NULL || !f3d_gpu_readback_create(&f->readback, gpu, bytes)) {
    free(zero);
    f3d_gpu_fluid_destroy(f);
    return NULL;
  }
  wgpuQueueWriteBuffer(gpu->queue, f->lambda, 0, zero, (size_t)bytes);
  free(zero);
  const F3dGpuBinding kinds[] = {F3D_GPU_UNIFORM, F3D_GPU_STORAGE, F3D_GPU_STORAGE,
                                 F3D_GPU_STORAGE, F3D_GPU_STORAGE, F3D_GPU_STORAGE,
                                 F3D_GPU_STORAGE, F3D_GPU_STORAGE};
  const WGPUBuffer buffers[] = {f->params,  f->position, f->predicted, f->velocity,
                                f->scratch, f->lambda,   f->head,      f->link};
  const uint64_t sizes[] = {PARAMS_BYTES, bytes, bytes, bytes, bytes,
                            bytes,        (uint64_t)cells * 4u, bytes};
  if (!f3d_gpu_kernels_create(&f->kernels, gpu, kFluidShader, kEntries, KERNELS, kinds, buffers,
                              sizes, 8)) {
    f3d_gpu_fluid_destroy(f);
    return NULL;
  }
  return f;
}

void f3d_gpu_fluid_destroy(F3dGpuFluid *f) {
  if (f == NULL) return;
  f3d_gpu_kernels_release(&f->kernels);
  f3d_gpu_readback_release(&f->readback);
  const WGPUBuffer buffers[] = {f->params,  f->position, f->predicted, f->velocity,
                                f->scratch, f->lambda,   f->head,      f->link};
  for (size_t i = 0; i < sizeof buffers / sizeof buffers[0]; i++) {
    if (buffers[i] != NULL) wgpuBufferRelease(buffers[i]);
  }
  free(f);
}

float f3d_gpu_fluid_rest_density(const F3dGpuFluid *f) { return f->rest_density; }

uint32_t f3d_gpu_fluid_add(F3dGpuFluid *f, const float *data, uint32_t count) {
  const uint32_t first = f->next_slot;
  for (uint32_t i = 0; i < count; i++) {
    const float *in = data + (size_t)i * 6u;
    const float p[4] = {in[0], in[1], in[2], 0.0f};
    const float v[4] = {in[3], in[4], in[5], 0.0f};
    const uint64_t at = (uint64_t)f->next_slot * PARTICLE_BYTES;
    wgpuQueueWriteBuffer(f->gpu->queue, f->position, at, p, sizeof p);
    wgpuQueueWriteBuffer(f->gpu->queue, f->velocity, at, v, sizeof v);
    f->next_slot = (f->next_slot + 1u) % f->capacity;
    if (f->count < f->capacity) f->count++;
  }
  return first;
}

void f3d_gpu_fluid_step(F3dGpuFluid *f, const F3dGpuFluidSettings *s, float dt) {
  if (!(dt > 0.0f) || f->count == 0) return;
  f->frame++;
  const uint32_t substeps = s->substeps > 0 ? s->substeps : 1u;
  const uint32_t iterations = s->iterations > 0 ? s->iterations : 1u;
  const float h = dt / (float)substeps;
  const float margin = f->spacing * 0.5f;
  float params[32];
  params[0] = s->gravity[0];
  params[1] = s->gravity[1];
  params[2] = s->gravity[2];
  params[3] = h;
  params[4] = f->h;
  params[5] = f->poly6;
  params[6] = f->spiky;
  params[7] = f->rest_density;
  for (int k = 0; k < 3; k++) {
    params[8 + k] = s->tank_min[k] + margin;
    params[12 + k] = s->tank_max[k] - margin;
  }
  params[11] = 1.0f / f->h;
  params[15] = s->viscosity;
  params[16] = s->relaxation;
  params[17] = f->spacing;
  params[18] = params[19] = 0.0f;
  const uint32_t counts[4] = {f->count, f->cells, 0, 0};
  memcpy(&params[20], counts, sizeof counts);
  for (int k = 0; k < 3; k++) {
    params[24 + k] = s->tank_min[k];
    params[28 + k] = s->tank_max[k];
  }
  params[27] = params[31] = 0.0f;
  wgpuQueueWriteBuffer(f->gpu->queue, f->params, 0, params, sizeof params);
  WGPUCommandEncoder encoder = wgpuDeviceCreateCommandEncoder(f->gpu->device, NULL);
  WGPUComputePassEncoder pass = wgpuCommandEncoderBeginComputePass(encoder, NULL);
  const uint32_t n = f->count;
  for (uint32_t sub = 0; sub < substeps; sub++) {
    f3d_gpu_dispatch(pass, &f->kernels, CLEAR_CELLS, f->cells);
    f3d_gpu_dispatch(pass, &f->kernels, PREDICT, n);
    for (uint32_t it = 0; it < iterations; it++) {
      f3d_gpu_dispatch(pass, &f->kernels, DENSITY, n);
      f3d_gpu_dispatch(pass, &f->kernels, SPREAD, n);
      f3d_gpu_dispatch(pass, &f->kernels, ADOPT_SPREAD, n);
    }
    f3d_gpu_dispatch(pass, &f->kernels, VELOCITY, n);
    f3d_gpu_dispatch(pass, &f->kernels, SMOOTH, n);
    f3d_gpu_dispatch(pass, &f->kernels, FINISH, n);
  }
  wgpuComputePassEncoderEnd(pass);
  wgpuComputePassEncoderRelease(pass);
  WGPUCommandBuffer commands = wgpuCommandEncoderFinish(encoder, NULL);
  wgpuQueueSubmit(f->gpu->queue, 1, &commands);
  wgpuCommandBufferRelease(commands);
  wgpuCommandEncoderRelease(encoder);
  f3d_gpu_readback_request(&f->readback, f->gpu, f->position, f->frame);
}

static void copy_particles(const void *mapped, void *out, uint32_t n) {
  memcpy(out, mapped, (size_t)n * PARTICLE_BYTES);
}

uint64_t f3d_gpu_fluid_read(F3dGpuFluid *f, float *out, uint32_t capacity, int wait) {
  const uint32_t n = capacity < f->count ? capacity : f->count;
  return f3d_gpu_readback_take(&f->readback, f->gpu, f->position, f->frame, wait,
                               copy_particles, out, n);
}
