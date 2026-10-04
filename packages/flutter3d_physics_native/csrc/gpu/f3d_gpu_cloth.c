/*
 * Cloth on the GPU — P9, phase 10: what f3d_cloth.c does, a dispatch a
 * colour. The constraints come coloured from the core (f3d_cloth_edges),
 * so both solve the same ones in the same order of colours; inside a
 * colour no two share a point, so nothing is summed in an order the GPU
 * chooses, and the two agree to the GPU's rounding. Which colour a
 * dispatch solves is a uniform bound at an offset of its own.
 */
#include <stdlib.h>
#include <string.h>

#include "f3d_gpu_internal.h"

#define POINT_BYTES 16u
#define EDGE_BYTES 16u
#define PARAMS_BYTES 80u
#define MAX_BALLS 16u
#define BALLS_BYTES (MAX_BALLS * 16u)
/* A colour's range, at offsets a uniform's dynamic binding allows. */
#define RANGE_STRIDE 256u

struct F3dGpuCloth {
  F3dGpu *gpu;
  uint32_t point_count;
  uint32_t colour_count;
  uint32_t ball_count;
  uint32_t *colour_size;
  float *inv_mass;
  uint64_t frame;
  WGPUBuffer params;
  WGPUBuffer balls;
  WGPUBuffer ranges;
  WGPUBuffer position;
  WGPUBuffer previous;
  WGPUBuffer velocity;
  WGPUBuffer edges;
  F3dGpuKernels kernels;
  F3dGpuReadback readback;
};

enum { PREDICT, SOLVE, COLLIDE, KERNELS };

static const char *const kEntries[KERNELS] = {"predict", "solve", "collide"};

static const char kClothShader[] =
    "struct Params {\n"
    "  gravity_h : vec4<f32>,   // gravity, the substep\n"
    "  wind_drift : vec4<f32>,  // the wind, what drag keeps of the difference\n"
    "  misc : vec4<f32>,        // what damping keeps, 1/h², the floor, the thickness\n"
    "  extra : vec4<f32>,       // friction\n"
    "  counts : vec4<u32>,      // points, balls\n"
    "};\n"
    "struct Balls { b : array<vec4<f32>, 16> };\n"
    "struct Range { start : u32, count : u32, pad0 : u32, pad1 : u32 };\n"
    "struct Edge { a : u32, b : u32, rest : f32, compliance : f32 };\n"
    "@group(0) @binding(0) var<uniform> P : Params;\n"
    "@group(0) @binding(1) var<uniform> B : Balls;\n"
    "@group(0) @binding(2) var<uniform> R : Range;\n"
    "@group(0) @binding(3) var<storage, read_write> position : array<vec4<f32>>;\n"
    "@group(0) @binding(4) var<storage, read_write> previous : array<vec4<f32>>;\n"
    "@group(0) @binding(5) var<storage, read_write> velocity : array<vec4<f32>>;\n"
    "@group(0) @binding(6) var<storage, read> edges : array<Edge>;\n"
    "@compute @workgroup_size(64)\n"
    "fn predict(@builtin(global_invocation_id) id : vec3<u32>) {\n"
    "  let i = id.x;\n"
    "  if (i >= P.counts.x) { return; }\n"
    "  let p = position[i];\n"
    "  previous[i] = p;\n"
    "  if (p.w == 0.0) { return; }\n"
    "  var v = velocity[i].xyz + P.gravity_h.xyz * P.gravity_h.w;\n"
    "  v = P.wind_drift.xyz + (v - P.wind_drift.xyz) * P.wind_drift.w;\n"
    "  v = v * P.misc.x;\n"
    "  velocity[i] = vec4<f32>(v, 0.0);\n"
    "  position[i] = vec4<f32>(p.xyz + v * P.gravity_h.w, p.w);\n"
    "}\n"
    "@compute @workgroup_size(64)\n"
    "fn solve(@builtin(global_invocation_id) id : vec3<u32>) {\n"
    "  if (id.x >= R.count) { return; }\n"
    "  let e = edges[R.start + id.x];\n"
    "  let pa = position[e.a];\n"
    "  let pb = position[e.b];\n"
    "  let w = pa.w + pb.w + e.compliance * P.misc.y;\n"
    "  if (!(w > 0.0)) { return; }\n"
    "  let d = pa.xyz - pb.xyz;\n"
    "  let len = sqrt(dot(d, d));\n"
    "  if (!(len > 0.0)) { return; }\n"
    "  let lambda = (e.rest - len) / w;\n"
    "  let n = d * (1.0 / len);\n"
    "  position[e.a] = vec4<f32>(pa.xyz + n * (pa.w * lambda), pa.w);\n"
    "  position[e.b] = vec4<f32>(pb.xyz + n * (-pb.w * lambda), pb.w);\n"
    "}\n"
    "fn rub(x : vec3<f32>, was : vec3<f32>, n : vec3<f32>) -> vec3<f32> {\n"
    "  let moved = x - was;\n"
    "  let slide = moved + n * -dot(moved, n);\n"
    "  return x + slide * -P.extra.x;\n"
    "}\n"
    "@compute @workgroup_size(64)\n"
    "fn collide(@builtin(global_invocation_id) id : vec3<u32>) {\n"
    "  let i = id.x;\n"
    "  if (i >= P.counts.x) { return; }\n"
    "  let p = position[i];\n"
    "  if (p.w == 0.0) {\n"
    "    velocity[i] = vec4<f32>(0.0);\n"
    "    return;\n"
    "  }\n"
    "  var x = p.xyz;\n"
    "  let was = previous[i].xyz;\n"
    "  for (var k = 0u; k < P.counts.y; k = k + 1u) {\n"
    "    let ball = B.b[k];\n"
    "    let d = x - ball.xyz;\n"
    "    let len = sqrt(dot(d, d));\n"
    "    let reach = ball.w + P.misc.w;\n"
    "    if (!(len < reach)) { continue; }\n"
    "    var n = vec3<f32>(0.0, 1.0, 0.0);\n"
    "    if (len > 0.0) { n = d * (1.0 / len); }\n"
    "    x = ball.xyz + n * reach;\n"
    "    x = rub(x, was, n);\n"
    "  }\n"
    "  if (x.y < P.misc.z) {\n"
    "    x.y = P.misc.z;\n"
    "    x = rub(x, was, vec3<f32>(0.0, 1.0, 0.0));\n"
    "  }\n"
    "  position[i] = vec4<f32>(x, p.w);\n"
    "  velocity[i] = vec4<f32>((x - was) * (1.0 / P.gravity_h.w), 0.0);\n"
    "}\n";

F3dGpuCloth *f3d_gpu_cloth_create(F3dGpu *gpu, const float *points, uint32_t point_count,
                                  const uint32_t *pairs, const float *rest,
                                  const float *compliance, uint32_t edge_count,
                                  const uint32_t *colour_start, uint32_t colour_count) {
  if (gpu == NULL || point_count == 0 || point_count > (1u << 22) || colour_count > 256u ||
      edge_count > (1u << 24) || (colour_count > 0 && colour_start[colour_count] != edge_count)) {
    return NULL;
  }
  for (uint32_t e = 0; e < edge_count; e++) {
    if (pairs[e * 2u] >= point_count || pairs[e * 2u + 1u] >= point_count) return NULL;
  }
  F3dGpuCloth *c = (F3dGpuCloth *)calloc(1, sizeof(F3dGpuCloth));
  if (c == NULL) return NULL;
  c->gpu = gpu;
  c->point_count = point_count;
  c->colour_count = colour_count;
  c->colour_size = (uint32_t *)calloc(colour_count > 0 ? colour_count : 1u, sizeof(uint32_t));
  c->inv_mass = (float *)calloc(point_count, sizeof(float));
  const uint64_t point_bytes = (uint64_t)point_count * POINT_BYTES;
  const uint64_t edge_bytes = (uint64_t)(edge_count > 0 ? edge_count : 1u) * EDGE_BYTES;
  const uint64_t range_bytes = (uint64_t)(colour_count > 0 ? colour_count : 1u) * RANGE_STRIDE;
  const WGPUBufferUsage uniform = WGPUBufferUsage_Uniform | WGPUBufferUsage_CopyDst;
  const WGPUBufferUsage storage = WGPUBufferUsage_Storage | WGPUBufferUsage_CopyDst;
  c->params = f3d_gpu_buffer(gpu, uniform, PARAMS_BYTES);
  c->balls = f3d_gpu_buffer(gpu, uniform, BALLS_BYTES);
  c->ranges = f3d_gpu_buffer(gpu, uniform, range_bytes);
  c->position = f3d_gpu_buffer(gpu, storage | WGPUBufferUsage_CopySrc, point_bytes);
  c->previous = f3d_gpu_buffer(gpu, storage, point_bytes);
  c->velocity = f3d_gpu_buffer(gpu, storage, point_bytes);
  c->edges = f3d_gpu_buffer(gpu, storage, edge_bytes);
  uint8_t *ranges = (uint8_t *)calloc(1, (size_t)range_bytes);
  float *start = (float *)calloc(point_count, POINT_BYTES);
  uint8_t *edge_data = (uint8_t *)calloc(1, (size_t)edge_bytes);
  void *zero = calloc(1, BALLS_BYTES > point_bytes ? BALLS_BYTES : (size_t)point_bytes);
  if (c->colour_size == NULL || c->inv_mass == NULL || c->params == NULL || c->balls == NULL ||
      c->ranges == NULL || c->position == NULL || c->previous == NULL || c->velocity == NULL ||
      c->edges == NULL || ranges == NULL || start == NULL || edge_data == NULL || zero == NULL ||
      !f3d_gpu_readback_create(&c->readback, gpu, point_bytes)) {
    free(ranges);
    free(start);
    free(edge_data);
    free(zero);
    f3d_gpu_cloth_destroy(c);
    return NULL;
  }
  for (uint32_t i = 0; i < point_count; i++) {
    for (int k = 0; k < 3; k++) start[i * 4u + (uint32_t)k] = points[i * 4u + (uint32_t)k];
    c->inv_mass[i] = points[i * 4u + 3u] > 0.0f ? points[i * 4u + 3u] : 0.0f;
    start[i * 4u + 3u] = c->inv_mass[i];
  }
  for (uint32_t e = 0; e < edge_count; e++) {
    const float comp = compliance[e] > 0.0f ? compliance[e] : 0.0f;
    memcpy(edge_data + e * EDGE_BYTES, &pairs[e * 2u], 8u);
    memcpy(edge_data + e * EDGE_BYTES + 8u, &rest[e], 4u);
    memcpy(edge_data + e * EDGE_BYTES + 12u, &comp, 4u);
  }
  for (uint32_t k = 0; k < colour_count; k++) {
    const uint32_t range[2] = {colour_start[k], colour_start[k + 1u] - colour_start[k]};
    c->colour_size[k] = range[1];
    memcpy(ranges + (size_t)k * RANGE_STRIDE, range, sizeof range);
  }
  wgpuQueueWriteBuffer(gpu->queue, c->position, 0, start, (size_t)point_bytes);
  wgpuQueueWriteBuffer(gpu->queue, c->previous, 0, start, (size_t)point_bytes);
  wgpuQueueWriteBuffer(gpu->queue, c->velocity, 0, zero, (size_t)point_bytes);
  wgpuQueueWriteBuffer(gpu->queue, c->balls, 0, zero, BALLS_BYTES);
  wgpuQueueWriteBuffer(gpu->queue, c->edges, 0, edge_data, (size_t)edge_bytes);
  wgpuQueueWriteBuffer(gpu->queue, c->ranges, 0, ranges, (size_t)range_bytes);
  free(ranges);
  free(start);
  free(edge_data);
  free(zero);
  const F3dGpuBinding kinds[] = {F3D_GPU_UNIFORM, F3D_GPU_UNIFORM, F3D_GPU_UNIFORM_AT,
                                 F3D_GPU_STORAGE, F3D_GPU_STORAGE, F3D_GPU_STORAGE,
                                 F3D_GPU_READ_ONLY};
  const WGPUBuffer buffers[] = {c->params,   c->balls,    c->ranges, c->position,
                                c->previous, c->velocity, c->edges};
  const uint64_t sizes[] = {PARAMS_BYTES, BALLS_BYTES, 16u,       point_bytes,
                            point_bytes,  point_bytes, edge_bytes};
  if (!f3d_gpu_kernels_create(&c->kernels, gpu, kClothShader, kEntries, KERNELS, kinds, buffers,
                              sizes, 7)) {
    f3d_gpu_cloth_destroy(c);
    return NULL;
  }
  return c;
}

void f3d_gpu_cloth_destroy(F3dGpuCloth *c) {
  if (c == NULL) return;
  f3d_gpu_kernels_release(&c->kernels);
  f3d_gpu_readback_release(&c->readback);
  const WGPUBuffer buffers[] = {c->params,   c->balls,    c->ranges, c->position,
                                c->previous, c->velocity, c->edges};
  for (size_t i = 0; i < sizeof buffers / sizeof buffers[0]; i++) {
    if (buffers[i] != NULL) wgpuBufferRelease(buffers[i]);
  }
  free(c->colour_size);
  free(c->inv_mass);
  free(c);
}

int f3d_gpu_cloth_set_balls(F3dGpuCloth *c, const float *balls, uint32_t count) {
  if (count > MAX_BALLS) return 0;
  float all[MAX_BALLS * 4u];
  memset(all, 0, sizeof all);
  if (count > 0) memcpy(all, balls, (size_t)count * 4u * sizeof(float));
  wgpuQueueWriteBuffer(c->gpu->queue, c->balls, 0, all, sizeof all);
  c->ball_count = count;
  return 1;
}

void f3d_gpu_cloth_move_point(F3dGpuCloth *c, uint32_t index, float x, float y, float z) {
  if (index >= c->point_count) return;
  const float p[4] = {x, y, z, c->inv_mass[index]};
  const float still[4] = {0, 0, 0, 0};
  const uint64_t at = (uint64_t)index * POINT_BYTES;
  wgpuQueueWriteBuffer(c->gpu->queue, c->position, at, p, sizeof p);
  wgpuQueueWriteBuffer(c->gpu->queue, c->velocity, at, still, sizeof still);
}

void f3d_gpu_cloth_step(F3dGpuCloth *c, const F3dGpuClothSettings *s, float dt) {
  if (!(dt > 0.0f)) return;
  c->frame++;
  const uint32_t substeps = s->substeps > 0 ? s->substeps : 1u;
  const float h = dt / (float)substeps;
  float params[20];
  params[0] = s->gravity[0];
  params[1] = s->gravity[1];
  params[2] = s->gravity[2];
  params[3] = h;
  params[4] = s->wind[0];
  params[5] = s->wind[1];
  params[6] = s->wind[2];
  params[7] = 1.0f / (1.0f + s->drag * h);
  params[8] = 1.0f / (1.0f + s->damping * h);
  params[9] = 1.0f / (h * h);
  params[10] = s->floor_y + s->thickness;
  params[11] = s->thickness;
  params[12] = s->friction;
  params[13] = params[14] = params[15] = 0.0f;
  const uint32_t counts[4] = {c->point_count, c->ball_count, 0, 0};
  memcpy(&params[16], counts, sizeof counts);
  wgpuQueueWriteBuffer(c->gpu->queue, c->params, 0, params, sizeof params);
  WGPUCommandEncoder encoder = wgpuDeviceCreateCommandEncoder(c->gpu->device, NULL);
  WGPUComputePassEncoder pass = wgpuCommandEncoderBeginComputePass(encoder, NULL);
  for (uint32_t sub = 0; sub < substeps; sub++) {
    f3d_gpu_dispatch(pass, &c->kernels, PREDICT, c->point_count);
    for (uint32_t k = 0; k < c->colour_count; k++) {
      f3d_gpu_dispatch_at(pass, &c->kernels, SOLVE, c->colour_size[k], k * RANGE_STRIDE);
    }
    f3d_gpu_dispatch(pass, &c->kernels, COLLIDE, c->point_count);
  }
  wgpuComputePassEncoderEnd(pass);
  wgpuComputePassEncoderRelease(pass);
  WGPUCommandBuffer commands = wgpuCommandEncoderFinish(encoder, NULL);
  wgpuQueueSubmit(c->gpu->queue, 1, &commands);
  wgpuCommandBufferRelease(commands);
  wgpuCommandEncoderRelease(encoder);
  f3d_gpu_readback_request(&c->readback, c->gpu, c->position, c->frame);
}

static void copy_points(const void *mapped, void *out, uint32_t n) {
  memcpy(out, mapped, (size_t)n * POINT_BYTES);
}

uint64_t f3d_gpu_cloth_read(F3dGpuCloth *c, float *out, uint32_t capacity, int wait) {
  const uint32_t n = capacity < c->point_count ? capacity : c->point_count;
  return f3d_gpu_readback_take(&c->readback, c->gpu, c->position, c->frame, wait, copy_points,
                               out, n);
}
