/*
 * Cloth on the CPU — P9, phase 10: the reference for the GPU's, and the
 * fallback where there is none. See f3d_physics.h for what it does; the
 * WGSL in f3d_gpu_cloth.c does the same, pass for pass.
 *
 * XPBD in small steps (Macklin et al., 2019): every substep predicts the
 * points, solves each constraint once with its multiplier starting from
 * nought — so a compliance α holds a constraint as a spring of stiffness
 * 1/α — and takes the velocity from where the points went. The
 * constraints are coloured greedily when the cloth is made and stored
 * colour by colour; inside a colour no two share a point, so the order
 * they are solved in changes nothing, not even the rounding.
 */
#include "f3d_internal.h"

typedef struct Edge {
  uint32_t a, b;
  f3d_real rest;
  f3d_real compliance;
} Edge;

/* Colours a point's constraints may take: a bit each. */
#define MAX_COLOURS 256u

struct F3dCloth {
  F3dVec3 *position;
  F3dVec3 *previous;
  F3dVec3 *velocity;
  f3d_real *inv_mass;
  uint32_t point_count;
  Edge *edges;
  uint32_t edge_count;
  /* Colour c's constraints are edges[colour_start[c]] up to
   * edges[colour_start[c + 1]]. */
  uint32_t *colour_start;
  uint32_t colour_count;
  f3d_real balls[F3D_CLOTH_MAX_BALLS * 4u];
  uint32_t ball_count;
};

F3dCloth *f3d_cloth_create(const f3d_real *points, uint32_t point_count, const uint32_t *edges,
                           const f3d_real *compliance, uint32_t edge_count) {
  if (point_count == 0 || point_count > (1u << 24) || edge_count > (1u << 26)) return NULL;
  for (uint32_t e = 0; e < edge_count; e++) {
    const uint32_t a = edges[e * 2u], b = edges[e * 2u + 1u];
    if (a >= point_count || b >= point_count || a == b) return NULL;
  }
  F3dCloth *c = (F3dCloth *)f3d_alloc(sizeof(F3dCloth));
  if (c == NULL) return NULL;
  f3d_zero(c, sizeof(F3dCloth));
  const size_t vec_bytes = (size_t)point_count * sizeof(F3dVec3);
  c->position = (F3dVec3 *)f3d_alloc(vec_bytes);
  c->previous = (F3dVec3 *)f3d_alloc(vec_bytes);
  c->velocity = (F3dVec3 *)f3d_alloc(vec_bytes);
  c->inv_mass = (f3d_real *)f3d_alloc((size_t)point_count * sizeof(f3d_real));
  c->edges = (Edge *)f3d_alloc((size_t)(edge_count > 0 ? edge_count : 1u) * sizeof(Edge));
  /* Each point's colours taken, and each edge's colour, for the sort. */
  uint64_t *taken = (uint64_t *)f3d_alloc((size_t)point_count * (MAX_COLOURS / 64u) *
                                          sizeof(uint64_t));
  uint32_t *colour = (uint32_t *)f3d_alloc((size_t)(edge_count > 0 ? edge_count : 1u) *
                                           sizeof(uint32_t));
  c->colour_start = (uint32_t *)f3d_alloc((MAX_COLOURS + 1u) * sizeof(uint32_t));
  if (c->position == NULL || c->previous == NULL || c->velocity == NULL || c->inv_mass == NULL ||
      c->edges == NULL || taken == NULL || colour == NULL || c->colour_start == NULL) {
    f3d_free(taken);
    f3d_free(colour);
    f3d_cloth_destroy(c);
    return NULL;
  }
  c->point_count = point_count;
  c->edge_count = edge_count;
  for (uint32_t i = 0; i < point_count; i++) {
    const f3d_real *p = points + (size_t)i * F3D_CLOTH_FLOATS;
    c->position[i] = f3d_v3(p[0], p[1], p[2]);
    c->previous[i] = c->position[i];
    c->velocity[i] = f3d_v3(0, 0, 0);
    c->inv_mass[i] = p[3] > F3D_R(0.0) ? p[3] : F3D_R(0.0);
  }
  /* Greedy colouring: each edge the first colour neither of its points has
   * yet. */
  f3d_zero(taken, (size_t)point_count * (MAX_COLOURS / 64u) * sizeof(uint64_t));
  f3d_zero(c->colour_start, (MAX_COLOURS + 1u) * sizeof(uint32_t));
  for (uint32_t e = 0; e < edge_count; e++) {
    const uint32_t a = edges[e * 2u], b = edges[e * 2u + 1u];
    uint32_t k = 0;
    while (k < MAX_COLOURS &&
           (((taken[a * 4u + k / 64u] | taken[b * 4u + k / 64u]) >> (k % 64u)) & 1u)) {
      k++;
    }
    if (k == MAX_COLOURS) {
      f3d_free(taken);
      f3d_free(colour);
      f3d_cloth_destroy(c);
      return NULL;
    }
    taken[a * 4u + k / 64u] |= (uint64_t)1 << (k % 64u);
    taken[b * 4u + k / 64u] |= (uint64_t)1 << (k % 64u);
    colour[e] = k;
    c->colour_start[k + 1u]++;
    if (k + 1u > c->colour_count) c->colour_count = k + 1u;
  }
  for (uint32_t k = 0; k < MAX_COLOURS; k++) c->colour_start[k + 1u] += c->colour_start[k];
  /* Sorted by colour, in the order given inside each. */
  uint32_t fill[MAX_COLOURS];
  for (uint32_t k = 0; k < MAX_COLOURS; k++) fill[k] = c->colour_start[k];
  for (uint32_t e = 0; e < edge_count; e++) {
    const uint32_t a = edges[e * 2u], b = edges[e * 2u + 1u];
    Edge *to = &c->edges[fill[colour[e]]++];
    to->a = a;
    to->b = b;
    const F3dVec3 d = f3d_sub(c->position[a], c->position[b]);
    to->rest = f3d_sqrt(f3d_dot(d, d));
    to->compliance = compliance[e] > F3D_R(0.0) ? compliance[e] : F3D_R(0.0);
  }
  f3d_free(taken);
  f3d_free(colour);
  return c;
}

void f3d_cloth_destroy(F3dCloth *c) {
  if (c == NULL) return;
  f3d_free(c->position);
  f3d_free(c->previous);
  f3d_free(c->velocity);
  f3d_free(c->inv_mass);
  f3d_free(c->edges);
  f3d_free(c->colour_start);
  f3d_free(c);
}

uint32_t f3d_cloth_point_count(const F3dCloth *c) { return c->point_count; }

uint32_t f3d_cloth_colour_count(const F3dCloth *c) { return c->colour_count; }

uint32_t f3d_cloth_edge_count(const F3dCloth *c) { return c->edge_count; }

void f3d_cloth_edges(const F3dCloth *c, uint32_t *pairs, f3d_real *rest, f3d_real *compliance,
                     uint32_t *colour_start) {
  for (uint32_t e = 0; e < c->edge_count; e++) {
    pairs[e * 2u] = c->edges[e].a;
    pairs[e * 2u + 1u] = c->edges[e].b;
    rest[e] = c->edges[e].rest;
    compliance[e] = c->edges[e].compliance;
  }
  for (uint32_t k = 0; k <= c->colour_count; k++) colour_start[k] = c->colour_start[k];
}

int f3d_cloth_set_balls(F3dCloth *c, const f3d_real *balls, uint32_t count) {
  if (count > F3D_CLOTH_MAX_BALLS) return 0;
  for (uint32_t i = 0; i < count * 4u; i++) c->balls[i] = balls[i];
  c->ball_count = count;
  return 1;
}

void f3d_cloth_move_point(F3dCloth *c, uint32_t index, f3d_real x, f3d_real y, f3d_real z) {
  if (index >= c->point_count) return;
  c->position[index] = f3d_v3(x, y, z);
  c->velocity[index] = f3d_v3(0, 0, 0);
}

/* Takes [friction] of a point's slide along [n] since the substep began. */
static F3dVec3 rub(F3dVec3 x, F3dVec3 previous, F3dVec3 n, f3d_real friction) {
  const F3dVec3 moved = f3d_sub(x, previous);
  const F3dVec3 slide = f3d_madd(moved, n, -f3d_dot(moved, n));
  return f3d_madd(x, slide, -friction);
}

void f3d_cloth_step(F3dCloth *c, const F3dClothSettings *s, f3d_real dt) {
  if (!(f3d_finite(dt) && dt > F3D_R(0.0))) return;
  const uint32_t substeps = s->substeps > 0 ? s->substeps : 1u;
  const f3d_real h = dt / (f3d_real)substeps;
  const F3dVec3 g = f3d_v3(s->gravity[0], s->gravity[1], s->gravity[2]);
  const F3dVec3 wind = f3d_v3(s->wind[0], s->wind[1], s->wind[2]);
  const f3d_real drift = F3D_R(1.0) / (F3D_R(1.0) + s->drag * h);
  const f3d_real keep = F3D_R(1.0) / (F3D_R(1.0) + s->damping * h);
  const f3d_real inv_h2 = F3D_R(1.0) / (h * h);
  const f3d_real floor_at = s->floor_y + s->thickness;
  for (uint32_t sub = 0; sub < substeps; sub++) {
    /* Predict. */
    for (uint32_t i = 0; i < c->point_count; i++) {
      c->previous[i] = c->position[i];
      if (c->inv_mass[i] == F3D_R(0.0)) continue;
      F3dVec3 v = f3d_madd(c->velocity[i], g, h);
      v = f3d_add(wind, f3d_scale(f3d_sub(v, wind), drift));
      v = f3d_scale(v, keep);
      c->velocity[i] = v;
      c->position[i] = f3d_madd(c->position[i], v, h);
    }
    /* The constraints, colour by colour. */
    for (uint32_t k = 0; k < c->colour_count; k++) {
      for (uint32_t e = c->colour_start[k]; e < c->colour_start[k + 1u]; e++) {
        const Edge *edge = &c->edges[e];
        const f3d_real wa = c->inv_mass[edge->a], wb = c->inv_mass[edge->b];
        const f3d_real alpha = edge->compliance * inv_h2;
        const f3d_real w = wa + wb + alpha;
        if (!(w > F3D_R(0.0))) continue;
        const F3dVec3 d = f3d_sub(c->position[edge->a], c->position[edge->b]);
        const f3d_real len = f3d_sqrt(f3d_dot(d, d));
        if (!(len > F3D_R(0.0))) continue;
        const f3d_real lambda = (edge->rest - len) / w;
        const F3dVec3 n = f3d_scale(d, F3D_R(1.0) / len);
        c->position[edge->a] = f3d_madd(c->position[edge->a], n, wa * lambda);
        c->position[edge->b] = f3d_madd(c->position[edge->b], n, -wb * lambda);
      }
    }
    /* The balls and the floor, and the velocity from where it went. */
    for (uint32_t i = 0; i < c->point_count; i++) {
      if (c->inv_mass[i] == F3D_R(0.0)) {
        c->velocity[i] = f3d_v3(0, 0, 0);
        continue;
      }
      F3dVec3 x = c->position[i];
      const F3dVec3 was = c->previous[i];
      for (uint32_t b = 0; b < c->ball_count; b++) {
        const f3d_real *ball = &c->balls[b * 4u];
        const F3dVec3 d = f3d_sub(x, f3d_v3(ball[0], ball[1], ball[2]));
        const f3d_real len = f3d_sqrt(f3d_dot(d, d));
        const f3d_real reach = ball[3] + s->thickness;
        if (!(len < reach)) continue;
        const F3dVec3 n = len > F3D_R(0.0) ? f3d_scale(d, F3D_R(1.0) / len) : f3d_v3(0, 1, 0);
        x = f3d_madd(f3d_v3(ball[0], ball[1], ball[2]), n, reach);
        x = rub(x, was, n, s->friction);
      }
      if (x.y < floor_at) {
        x.y = floor_at;
        x = rub(x, was, f3d_v3(0, 1, 0), s->friction);
      }
      c->position[i] = x;
      c->velocity[i] = f3d_scale(f3d_sub(x, was), F3D_R(1.0) / h);
    }
  }
}

uint32_t f3d_cloth_read(const F3dCloth *c, f3d_real *out, uint32_t capacity) {
  const uint32_t n = capacity < c->point_count ? capacity : c->point_count;
  for (uint32_t i = 0; i < n; i++) {
    out[i * 4u] = c->position[i].x;
    out[i * 4u + 1u] = c->position[i].y;
    out[i * 4u + 2u] = c->position[i].z;
    out[i * 4u + 3u] = c->inv_mass[i];
  }
  return n;
}
