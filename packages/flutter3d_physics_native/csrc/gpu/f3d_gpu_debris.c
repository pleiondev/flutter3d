/*
 * Debris on the GPU — P9, phase 10: the visual bodies, read a frame late.
 * The WGSL does what f3d_debris.c does, pass for pass and line for line;
 * see there for why. The grid's lists are built with atomicExchange, so a
 * cell's bodies come in whatever order the GPU inserted them, and a body's
 * impulses are summed in that order: the same as the CPU's to the GPU's
 * rounding, not to the bit.
 */
#include <stdlib.h>
#include <string.h>

#include "f3d_gpu_internal.h"

/* Sixty-four bytes a body, as the shader's Body lays them out. */
#define BODY_BYTES 64u
#define MOTION_BYTES 32u
#define PARAMS_BYTES 64u
#define MAX_STATICS 64u
#define STATICS_BYTES (MAX_STATICS * 32u)

struct F3dGpuDebris {
  F3dGpu *gpu;
  uint32_t capacity;
  uint32_t cells;
  uint32_t next;
  uint32_t static_count;
  uint64_t frame;
  float max_radius;
  WGPUBuffer params;
  WGPUBuffer statics;
  WGPUBuffer bodies;
  WGPUBuffer motion;
  WGPUBuffer contacts;
  WGPUBuffer head;
  WGPUBuffer next_in_cell;
  F3dGpuKernels kernels;
  F3dGpuReadback readback;
};

enum { CLEAR_CELLS, GRAVITY_GRID, COUNT_CONTACTS, SOLVE, ADOPT, INTEGRATE, KERNELS };

static const char *const kEntries[KERNELS] = {
    "clear_cells", "gravity_grid", "count_contacts", "solve", "adopt", "integrate",
};

static const char kDebrisShader[] =
    "struct Body { pos_r : vec4<f32>, vel_m : vec4<f32>, spin_i : vec4<f32>, turn : vec4<f32> };\n"
    "struct Motion { v : vec4<f32>, w : vec4<f32> };\n"
    "struct Still { a : vec4<f32>, b : vec4<f32> };\n"
    "struct Params {\n"
    "  gravity_h : vec4<f32>,  // gravity, the substep\n"
    "  material : vec4<f32>,   // friction, restitution, what damping keeps of v and w\n"
    "  limits : vec4<f32>,     // the speed limit, one over the cell\n"
    "  counts : vec4<u32>,     // slots, cells, still shapes\n"
    "};\n"
    "struct Statics { s : array<Still, 64> };\n"
    "@group(0) @binding(0) var<uniform> P : Params;\n"
    "@group(0) @binding(1) var<uniform> S : Statics;\n"
    "@group(0) @binding(2) var<storage, read_write> bodies : array<Body>;\n"
    "@group(0) @binding(3) var<storage, read_write> motion : array<Motion>;\n"
    "@group(0) @binding(4) var<storage, read_write> contacts : array<u32>;\n"
    "@group(0) @binding(5) var<storage, read_write> head : array<atomic<u32>>;\n"
    "@group(0) @binding(6) var<storage, read_write> next_in_cell : array<u32>;\n"
    "const NONE : u32 = 0xFFFFFFFFu;\n"
    "const SLOP : f32 = 0.0005;\n"
    "const PUSH : f32 = 0.8;\n"
    "const MAX_PUSH : f32 = 3.0;\n"
    "const BOUNCE_SPEED : f32 = 1.0;\n"
    "fn coord(x : f32) -> i32 { return i32(floor(clamp(x * P.limits.y, -1e9, 1e9))); }\n"
    "fn cell_of(p : vec3<f32>) -> vec3<i32> { return vec3<i32>(coord(p.x), coord(p.y), coord(p.z)); }\n"
    "fn hash(c : vec3<i32>) -> u32 {\n"
    "  return ((bitcast<u32>(c.x) * 73856093u) ^ (bitcast<u32>(c.y) * 19349663u) ^\n"
    "          (bitcast<u32>(c.z) * 83492791u)) & (P.counts.y - 1u);\n"
    "}\n"
    "struct Touch { n : vec3<f32>, gap : f32 };\n"
    "fn touch_pair(lo : Body, hi : Body) -> Touch {\n"
    "  let d = lo.pos_r.xyz - hi.pos_r.xyz;\n"
    "  let len = sqrt(dot(d, d));\n"
    "  var t : Touch;\n"
    "  t.n = vec3<f32>(0.0, 1.0, 0.0);\n"
    "  if (len > 0.0) { t.n = d * (1.0 / len); }\n"
    "  t.gap = len - lo.pos_r.w - hi.pos_r.w;\n"
    "  return t;\n"
    "}\n"
    "fn touch_still(b : Body, s : Still) -> Touch {\n"
    "  var t : Touch;\n"
    "  let p = b.pos_r.xyz;\n"
    "  if (s.b.w == 0.0) {\n"
    "    t.n = s.a.xyz;\n"
    "    t.gap = dot(p, t.n) - s.a.w - b.pos_r.w;\n"
    "    return t;\n"
    "  }\n"
    "  let c = s.a.xyz;\n"
    "  let d = p - clamp(p, c - s.b.xyz, c + s.b.xyz);\n"
    "  let len = sqrt(dot(d, d));\n"
    "  if (len > 0.0) {\n"
    "    t.n = d * (1.0 / len);\n"
    "    t.gap = len - b.pos_r.w;\n"
    "    return t;\n"
    "  }\n"
    "  let depth = s.b.xyz - abs(p - c);\n"
    "  var axis = 0u;\n"
    "  var best = depth.x;\n"
    "  if (depth.y < best) { best = depth.y; axis = 1u; }\n"
    "  if (depth.z < best) { best = depth.z; axis = 2u; }\n"
    "  var n = vec3<f32>(0.0);\n"
    "  n[axis] = select(1.0, -1.0, p[axis] < c[axis]);\n"
    "  t.n = n;\n"
    "  t.gap = -best - b.pos_r.w;\n"
    "  return t;\n"
    "}\n"
    "fn surface(b : Body, n : vec3<f32>) -> vec3<f32> {\n"
    "  return b.vel_m.xyz + cross(b.spin_i.xyz, n * -b.pos_r.w);\n"
    "}\n"
    "fn impulse(lo : Body, n_lo : u32, hi : Body, n_hi : u32, still : bool, t : Touch) -> vec3<f32> {\n"
    "  let reach = select(0.25 * (lo.pos_r.w + hi.pos_r.w), lo.pos_r.w, still);\n"
    "  if (!(t.gap <= reach)) { return vec3<f32>(0.0); }\n"
    "  var rel = surface(lo, t.n);\n"
    "  if (!still) { rel = rel - surface(hi, -t.n); }\n"
    "  let vn = dot(rel, t.n);\n"
    "  let h = P.gravity_h.w;\n"
    "  var goal = min(max(-t.gap - SLOP, 0.0) * PUSH / h, MAX_PUSH);\n"
    "  if (t.gap > 0.0) { goal = -t.gap / h; }\n"
    "  if (vn < -BOUNCE_SPEED && t.gap <= SLOP) { goal = max(goal, -P.material.y * vn); }\n"
    "  let dvn = goal - vn;\n"
    "  if (!(dvn > 0.0)) { return vec3<f32>(0.0); }\n"
    "  let w_lo = lo.vel_m.w * f32(n_lo);\n"
    "  let w_hi = select(hi.vel_m.w * f32(n_hi), 0.0, still);\n"
    "  let pn = dvn / (w_lo + w_hi);\n"
    "  var p = t.n * pn;\n"
    "  let vt = rel - t.n * vn;\n"
    "  let slide = sqrt(dot(vt, vt));\n"
    "  if (slide > 0.0) {\n"
    "    var k = (lo.vel_m.w + lo.pos_r.w * lo.pos_r.w * lo.spin_i.w) * f32(n_lo);\n"
    "    if (!still) { k = k + (hi.vel_m.w + hi.pos_r.w * hi.pos_r.w * hi.spin_i.w) * f32(n_hi); }\n"
    "    let pt = min(slide / k, P.material.x * pn);\n"
    "    p = p - vt * (pt / slide);\n"
    "  }\n"
    "  return p;\n"
    "}\n"
    "@compute @workgroup_size(64)\n"
    "fn clear_cells(@builtin(global_invocation_id) id : vec3<u32>) {\n"
    "  if (id.x >= P.counts.y) { return; }\n"
    "  atomicStore(&head[id.x], NONE);\n"
    "}\n"
    "@compute @workgroup_size(64)\n"
    "fn gravity_grid(@builtin(global_invocation_id) id : vec3<u32>) {\n"
    "  let i = id.x;\n"
    "  if (i >= P.counts.x) { return; }\n"
    "  let b = bodies[i];\n"
    "  if (!(b.pos_r.w > 0.0)) { return; }\n"
    "  var v = b.vel_m.xyz + P.gravity_h.xyz * P.gravity_h.w;\n"
    "  let speed2 = dot(v, v);\n"
    "  if (speed2 > P.limits.x * P.limits.x) { v = v * (P.limits.x / sqrt(speed2)); }\n"
    "  bodies[i].vel_m = vec4<f32>(v, b.vel_m.w);\n"
    "  next_in_cell[i] = atomicExchange(&head[hash(cell_of(b.pos_r.xyz))], i);\n"
    "}\n"
    "fn gather(i : u32, counting : bool) {\n"
    "  let b = bodies[i];\n"
    "  if (!(b.pos_r.w > 0.0)) { return; }\n"
    "  var count = 0u;\n"
    "  var dv = b.vel_m.xyz;\n"
    "  var dw = b.spin_i.xyz;\n"
    "  let c = cell_of(b.pos_r.xyz);\n"
    "  for (var x = c.x - 1; x <= c.x + 1; x = x + 1) {\n"
    "    for (var y = c.y - 1; y <= c.y + 1; y = y + 1) {\n"
    "      for (var z = c.z - 1; z <= c.z + 1; z = z + 1) {\n"
    "        var j = atomicLoad(&head[hash(vec3<i32>(x, y, z))]);\n"
    "        loop {\n"
    "          if (j == NONE) { break; }\n"
    "          let after = next_in_cell[j];\n"
    "          let o = bodies[j];\n"
    "          // Another cell sharing this one's hash: met there.\n"
    "          if (j != i && all(cell_of(o.pos_r.xyz) == vec3<i32>(x, y, z))) {\n"
    "            let lower = i < j;\n"
    "            var lo = o;\n"
    "            var hi = b;\n"
    "            if (lower) { lo = b; hi = o; }\n"
    "            let t = touch_pair(lo, hi);\n"
    "            if (counting) {\n"
    "              if (t.gap <= 0.25 * (lo.pos_r.w + hi.pos_r.w)) { count = count + 1u; }\n"
    "            } else {\n"
    "              let n_lo = contacts[select(j, i, lower)];\n"
    "              let n_hi = contacts[select(i, j, lower)];\n"
    "              let p = impulse(lo, n_lo, hi, n_hi, false, t);\n"
    "              let sign = select(-1.0, 1.0, lower);\n"
    "              let mine = p * sign;\n"
    "              dv = dv + mine * b.vel_m.w;\n"
    "              dw = dw + cross(t.n * sign * -b.pos_r.w, mine) * b.spin_i.w;\n"
    "            }\n"
    "          }\n"
    "          j = after;\n"
    "        }\n"
    "      }\n"
    "    }\n"
    "  }\n"
    "  for (var k = 0u; k < P.counts.z; k = k + 1u) {\n"
    "    let t = touch_still(b, S.s[k]);\n"
    "    if (counting) {\n"
    "      if (t.gap <= b.pos_r.w) { count = count + 1u; }\n"
    "    } else {\n"
    "      let p = impulse(b, contacts[i], b, 0u, true, t);\n"
    "      dv = dv + p * b.vel_m.w;\n"
    "      dw = dw + cross(t.n * -b.pos_r.w, p) * b.spin_i.w;\n"
    "    }\n"
    "  }\n"
    "  if (counting) {\n"
    "    contacts[i] = count;\n"
    "  } else {\n"
    "    motion[i] = Motion(vec4<f32>(dv, 0.0), vec4<f32>(dw, 0.0));\n"
    "  }\n"
    "}\n"
    "@compute @workgroup_size(64)\n"
    "fn count_contacts(@builtin(global_invocation_id) id : vec3<u32>) {\n"
    "  if (id.x < P.counts.x) { gather(id.x, true); }\n"
    "}\n"
    "@compute @workgroup_size(64)\n"
    "fn solve(@builtin(global_invocation_id) id : vec3<u32>) {\n"
    "  if (id.x < P.counts.x) { gather(id.x, false); }\n"
    "}\n"
    "@compute @workgroup_size(64)\n"
    "fn adopt(@builtin(global_invocation_id) id : vec3<u32>) {\n"
    "  let i = id.x;\n"
    "  if (i >= P.counts.x || !(bodies[i].pos_r.w > 0.0)) { return; }\n"
    "  bodies[i].vel_m = vec4<f32>(motion[i].v.xyz, bodies[i].vel_m.w);\n"
    "  bodies[i].spin_i = vec4<f32>(motion[i].w.xyz, bodies[i].spin_i.w);\n"
    "}\n"
    "@compute @workgroup_size(64)\n"
    "fn integrate(@builtin(global_invocation_id) id : vec3<u32>) {\n"
    "  let i = id.x;\n"
    "  if (i >= P.counts.x) { return; }\n"
    "  let b = bodies[i];\n"
    "  if (!(b.pos_r.w > 0.0)) { return; }\n"
    "  let h = P.gravity_h.w;\n"
    "  let v = motion[i].v.xyz * P.material.z;\n"
    "  let w = motion[i].w.xyz * P.material.w;\n"
    "  let q = b.turn;\n"
    "  let k = 0.5 * h;\n"
    "  var r = vec4<f32>(q.x + k * (w.x * q.w + w.y * q.z - w.z * q.y),\n"
    "                    q.y + k * (w.y * q.w + w.z * q.x - w.x * q.z),\n"
    "                    q.z + k * (w.z * q.w + w.x * q.y - w.y * q.x),\n"
    "                    q.w - k * (w.x * q.x + w.y * q.y + w.z * q.z));\n"
    "  r = r / sqrt(dot(r, r));\n"
    "  bodies[i] = Body(vec4<f32>(b.pos_r.xyz + v * h, b.pos_r.w), vec4<f32>(v, b.vel_m.w),\n"
    "                   vec4<f32>(w, b.spin_i.w), r);\n"
    "}\n";

F3dGpuDebris *f3d_gpu_debris_create(F3dGpu *gpu, uint32_t capacity) {
  if (gpu == NULL || capacity == 0 || capacity > (1u << 20)) return NULL;
  F3dGpuDebris *d = (F3dGpuDebris *)calloc(1, sizeof(F3dGpuDebris));
  if (d == NULL) return NULL;
  d->gpu = gpu;
  d->capacity = capacity;
  uint32_t cells = 1;
  while (cells < capacity * 2u) cells <<= 1;
  d->cells = cells;
  const WGPUBufferUsage storage = WGPUBufferUsage_Storage | WGPUBufferUsage_CopyDst;
  const uint64_t body_bytes = (uint64_t)capacity * BODY_BYTES;
  d->params = f3d_gpu_buffer(gpu, WGPUBufferUsage_Uniform | WGPUBufferUsage_CopyDst, PARAMS_BYTES);
  d->statics = f3d_gpu_buffer(gpu, WGPUBufferUsage_Uniform | WGPUBufferUsage_CopyDst, STATICS_BYTES);
  d->bodies = f3d_gpu_buffer(gpu, storage | WGPUBufferUsage_CopySrc, body_bytes);
  d->motion = f3d_gpu_buffer(gpu, storage, (uint64_t)capacity * MOTION_BYTES);
  d->contacts = f3d_gpu_buffer(gpu, storage, (uint64_t)capacity * 4u);
  d->head = f3d_gpu_buffer(gpu, storage, (uint64_t)cells * 4u);
  d->next_in_cell = f3d_gpu_buffer(gpu, storage, (uint64_t)capacity * 4u);
  if (d->params == NULL || d->statics == NULL || d->bodies == NULL || d->motion == NULL ||
      d->contacts == NULL || d->head == NULL || d->next_in_cell == NULL ||
      !f3d_gpu_readback_create(&d->readback, gpu, body_bytes)) {
    f3d_gpu_debris_destroy(d);
    return NULL;
  }
  /* Every slot empty: radius nought, unturned. */
  float *empty = (float *)calloc(capacity, BODY_BYTES);
  void *zero = calloc(1, STATICS_BYTES);
  if (empty == NULL || zero == NULL) {
    free(empty);
    free(zero);
    f3d_gpu_debris_destroy(d);
    return NULL;
  }
  for (uint32_t i = 0; i < capacity; i++) empty[i * 16u + 15u] = 1.0f;
  wgpuQueueWriteBuffer(gpu->queue, d->bodies, 0, empty, (size_t)body_bytes);
  wgpuQueueWriteBuffer(gpu->queue, d->statics, 0, zero, STATICS_BYTES);
  free(empty);
  free(zero);
  const F3dGpuBinding kinds[] = {F3D_GPU_UNIFORM, F3D_GPU_UNIFORM, F3D_GPU_STORAGE,
                                 F3D_GPU_STORAGE, F3D_GPU_STORAGE, F3D_GPU_STORAGE,
                                 F3D_GPU_STORAGE};
  const WGPUBuffer buffers[] = {d->params,   d->statics, d->bodies,      d->motion,
                                d->contacts, d->head,    d->next_in_cell};
  const uint64_t sizes[] = {PARAMS_BYTES,
                            STATICS_BYTES,
                            body_bytes,
                            (uint64_t)capacity * MOTION_BYTES,
                            (uint64_t)capacity * 4u,
                            (uint64_t)cells * 4u,
                            (uint64_t)capacity * 4u};
  if (!f3d_gpu_kernels_create(&d->kernels, gpu, kDebrisShader, kEntries, KERNELS, kinds,
                              buffers, sizes, 7)) {
    f3d_gpu_debris_destroy(d);
    return NULL;
  }
  return d;
}

void f3d_gpu_debris_destroy(F3dGpuDebris *d) {
  if (d == NULL) return;
  f3d_gpu_kernels_release(&d->kernels);
  f3d_gpu_readback_release(&d->readback);
  const WGPUBuffer buffers[] = {d->params,   d->statics, d->bodies,      d->motion,
                                d->contacts, d->head,    d->next_in_cell};
  for (size_t i = 0; i < sizeof buffers / sizeof buffers[0]; i++) {
    if (buffers[i] != NULL) wgpuBufferRelease(buffers[i]);
  }
  free(d);
}

uint32_t f3d_gpu_debris_add(F3dGpuDebris *d, const float *data, uint32_t count) {
  const uint32_t first = d->next;
  float body[16];
  for (uint32_t i = 0; i < count; i++) {
    const float *in = data + (size_t)i * 8u;
    memset(body, 0, sizeof body);
    body[15] = 1.0f;
    const float r = in[6], m = in[7];
    if (r - r == 0.0f && m - m == 0.0f && r > 0.0f && m > 0.0f) {
      body[0] = in[0];
      body[1] = in[1];
      body[2] = in[2];
      body[3] = r;
      body[4] = in[3];
      body[5] = in[4];
      body[6] = in[5];
      body[7] = 1.0f / m;
      body[11] = 2.5f / (m * r * r);
      if (r > d->max_radius) d->max_radius = r;
    }
    wgpuQueueWriteBuffer(d->gpu->queue, d->bodies, (uint64_t)d->next * BODY_BYTES, body,
                         sizeof body);
    d->next = (d->next + 1u) % d->capacity;
  }
  return first;
}

int f3d_gpu_debris_set_statics(F3dGpuDebris *d, const float *data, uint32_t count) {
  if (count > MAX_STATICS) return 0;
  float all[MAX_STATICS * 8u];
  memset(all, 0, sizeof all);
  if (count > 0) memcpy(all, data, (size_t)count * 8u * sizeof(float));
  wgpuQueueWriteBuffer(d->gpu->queue, d->statics, 0, all, sizeof all);
  d->static_count = count;
  return 1;
}

void f3d_gpu_debris_step(F3dGpuDebris *d, const F3dGpuDebrisSettings *s, float dt) {
  if (!(dt > 0.0f)) return;
  d->frame++;
  const float cell = d->max_radius * 3.0f;
  if (cell > 0.0f) {
    const uint32_t substeps = s->substeps > 0 ? s->substeps : 1u;
    const uint32_t iterations = s->iterations > 0 ? s->iterations : 1u;
    const float h = dt / (float)substeps;
    float params[16];
    params[0] = s->gravity[0];
    params[1] = s->gravity[1];
    params[2] = s->gravity[2];
    params[3] = h;
    params[4] = s->friction;
    params[5] = s->restitution;
    params[6] = 1.0f / (1.0f + s->linear_damping * h);
    params[7] = 1.0f / (1.0f + s->angular_damping * h);
    params[8] = s->max_speed;
    params[9] = 1.0f / cell;
    params[10] = 0.0f;
    params[11] = 0.0f;
    const uint32_t counts[4] = {d->capacity, d->cells, d->static_count, 0};
    memcpy(&params[12], counts, sizeof counts);
    wgpuQueueWriteBuffer(d->gpu->queue, d->params, 0, params, sizeof params);
    WGPUCommandEncoder encoder = wgpuDeviceCreateCommandEncoder(d->gpu->device, NULL);
    WGPUComputePassEncoder pass = wgpuCommandEncoderBeginComputePass(encoder, NULL);
    for (uint32_t sub = 0; sub < substeps; sub++) {
      f3d_gpu_dispatch(pass, &d->kernels, CLEAR_CELLS, d->cells);
      f3d_gpu_dispatch(pass, &d->kernels, GRAVITY_GRID, d->capacity);
      f3d_gpu_dispatch(pass, &d->kernels, COUNT_CONTACTS, d->capacity);
      for (uint32_t it = 0; it < iterations; it++) {
        if (it > 0) f3d_gpu_dispatch(pass, &d->kernels, ADOPT, d->capacity);
        f3d_gpu_dispatch(pass, &d->kernels, SOLVE, d->capacity);
      }
      f3d_gpu_dispatch(pass, &d->kernels, INTEGRATE, d->capacity);
    }
    wgpuComputePassEncoderEnd(pass);
    wgpuComputePassEncoderRelease(pass);
    WGPUCommandBuffer commands = wgpuCommandEncoderFinish(encoder, NULL);
    wgpuQueueSubmit(d->gpu->queue, 1, &commands);
    wgpuCommandBufferRelease(commands);
    wgpuCommandEncoderRelease(encoder);
  }
  f3d_gpu_readback_request(&d->readback, d->gpu, d->bodies, d->frame);
}

static void copy_bodies(const void *mapped, void *out, uint32_t n) {
  const float *b = (const float *)mapped;
  float *o = (float *)out;
  for (uint32_t i = 0; i < n; i++) {
    const float *body = b + (size_t)i * 16u;
    float *to = o + (size_t)i * 8u;
    to[0] = body[0];
    to[1] = body[1];
    to[2] = body[2];
    to[3] = body[12];
    to[4] = body[13];
    to[5] = body[14];
    to[6] = body[15];
    to[7] = body[3];
  }
}

uint64_t f3d_gpu_debris_read(F3dGpuDebris *d, float *out, uint32_t capacity, int wait) {
  const uint32_t n = capacity < d->capacity ? capacity : d->capacity;
  return f3d_gpu_readback_take(&d->readback, d->gpu, d->bodies, d->frame, wait, copy_bodies,
                               out, n);
}
