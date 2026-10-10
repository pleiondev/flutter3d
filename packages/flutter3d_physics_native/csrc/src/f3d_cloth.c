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
  /* Where it was in the order the cloth was made with, which
   * f3d_cloth_set_compliance is given its compliances in. */
  uint32_t given;
} Edge;

/* Colours a point's constraints may take: a bit each. */
#define MAX_COLOURS 256u

/* The sheet against itself, for f3d_cloth_solve: a spatial hash counted
 * into flat arrays, and the close pairs it found. Made the first time a
 * step asks for it. */
typedef struct SelfPairs {
  uint32_t *cell_start; /* 2n + 2: the table and one past it */
  uint32_t *entries;    /* n */
  int32_t *cells;       /* 3n */
  F3dVec3 *built_at;    /* n */
  uint32_t *pair_start; /* n + 1 */
  uint32_t *pairs;
  uint32_t pair_capacity;
  int built;
} SelfPairs;

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
  /* What f3d_cloth_solve keeps besides: each constraint's multiplier, the
   * rest shape, the triangles, the obstacles and where each record starts,
   * each point's push from them this substep and its widest triangle. */
  f3d_real *lambda;
  F3dVec3 *rest;
  uint32_t *triangles;
  uint32_t triangle_count;
  f3d_real *obstacles;
  uint32_t *obstacle_at;
  uint32_t obstacle_count;
  int any_round;
  F3dVec3 *contact;
  f3d_real *span;
  SelfPairs self;
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
  c->lambda = (f3d_real *)f3d_alloc((size_t)(edge_count > 0 ? edge_count : 1u) * sizeof(f3d_real));
  c->rest = (F3dVec3 *)f3d_alloc(vec_bytes);
  c->contact = (F3dVec3 *)f3d_alloc(vec_bytes);
  c->span = (f3d_real *)f3d_alloc((size_t)point_count * sizeof(f3d_real));
  if (c->position == NULL || c->previous == NULL || c->velocity == NULL || c->inv_mass == NULL ||
      c->edges == NULL || taken == NULL || colour == NULL || c->colour_start == NULL ||
      c->lambda == NULL || c->rest == NULL || c->contact == NULL || c->span == NULL) {
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
    c->rest[i] = c->position[i];
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
    to->given = e;
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
  f3d_free(c->lambda);
  f3d_free(c->rest);
  f3d_free(c->triangles);
  f3d_free(c->obstacles);
  f3d_free(c->obstacle_at);
  f3d_free(c->contact);
  f3d_free(c->span);
  f3d_free(c->self.cell_start);
  f3d_free(c->self.entries);
  f3d_free(c->self.cells);
  f3d_free(c->self.built_at);
  f3d_free(c->self.pair_start);
  f3d_free(c->self.pairs);
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

/* ---------------------------------------------------- f3d_cloth_solve
 *
 * What flutter3d_physics's stepCloth does, step for step, so a run on the
 * core drapes its cloth as a run on the reference does: xpbd_solver.dart
 * and cloth_collision.dart say why each step is the way it is, and the
 * comments here only where the two part. They part in the order the
 * constraints go (colour by colour here, so nothing depends on which of a
 * colour came first; structural, bending and shear there) and in the
 * rounding, f32 here and doubles there. */

int f3d_cloth_set_triangles(F3dCloth *c, const uint32_t *corners, uint32_t count) {
  f3d_free(c->triangles);
  c->triangles = NULL;
  c->triangle_count = 0;
  if (count == 0) return 1;
  if (count > (1u << 26)) return 0;
  for (uint32_t k = 0; k < count * 3u; k++) {
    if (corners[k] >= c->point_count) return 0;
  }
  c->triangles = (uint32_t *)f3d_alloc((size_t)count * 3u * sizeof(uint32_t));
  if (c->triangles == NULL) return 0;
  f3d_copy(c->triangles, corners, (size_t)count * 3u * sizeof(uint32_t));
  c->triangle_count = count;
  return 1;
}

void f3d_cloth_set_rest(F3dCloth *c, const f3d_real *xyz) {
  for (uint32_t i = 0; i < c->point_count; i++) {
    c->rest[i] = f3d_v3(xyz[i * 3u], xyz[i * 3u + 1u], xyz[i * 3u + 2u]);
  }
}

void f3d_cloth_set_compliance(F3dCloth *c, const f3d_real *compliance) {
  for (uint32_t e = 0; e < c->edge_count; e++) {
    const f3d_real a = compliance[c->edges[e].given];
    c->edges[e].compliance = a > F3D_R(0.0) ? a : F3D_R(0.0);
  }
}

void f3d_cloth_set_lengths(F3dCloth *c, const f3d_real *length) {
  for (uint32_t e = 0; e < c->edge_count; e++) {
    const f3d_real l = length[c->edges[e].given];
    c->edges[e].rest = l > F3D_R(0.0) ? l : F3D_R(0.0);
  }
}

/* A real that is a whole number from [least] to [most], as a count, or -1. */
static int64_t whole(f3d_real x, int64_t least, int64_t most) {
  if (!(x >= (f3d_real)least && x <= (f3d_real)most)) return -1;
  const int64_t n = (int64_t)x;
  return (f3d_real)n == x ? n : -1;
}

/* How many reals the record at [r] takes, of [left]; 0 when it is not one. */
static uint32_t record_length(const f3d_real *r, uint32_t left) {
  switch (whole(r[0], 0, 3)) {
    case F3D_CLOTH_BALL:
      return left >= 5u ? 5u : 0u;
    case F3D_CLOTH_CAPSULE:
      return left >= 6u ? 6u : 0u;
    case F3D_CLOTH_CONVEX: {
      if (left < 2u) return 0;
      const int64_t planes = whole(r[1], 0, 1 << 16);
      if (planes < 0 || (uint64_t)left < 2u + 4u * (uint64_t)planes) return 0;
      return 2u + 4u * (uint32_t)planes;
    }
    case F3D_CLOTH_GROUND: {
      if (left < 8u || !(r[4] > F3D_R(0.0))) return 0;
      const int64_t columns = whole(r[5], 2, 1 << 15), rows = whole(r[6], 2, 1 << 15);
      if (columns < 0 || rows < 0) return 0;
      const uint64_t need = 8u + (uint64_t)columns * (uint64_t)rows;
      return (uint64_t)left < need ? 0u : (uint32_t)need;
    }
    default:
      return 0;
  }
}

int f3d_cloth_set_obstacles(F3dCloth *c, const f3d_real *records, uint32_t length) {
  uint32_t count = 0;
  for (uint32_t at = 0; at < length; count++) {
    const uint32_t n = record_length(records + at, length - at);
    if (n == 0) return 0;
    at += n;
  }
  f3d_real *data = NULL;
  uint32_t *starts = NULL;
  if (count > 0) {
    data = (f3d_real *)f3d_alloc((size_t)length * sizeof(f3d_real));
    starts = (uint32_t *)f3d_alloc((size_t)count * sizeof(uint32_t));
    if (data == NULL || starts == NULL) {
      f3d_free(data);
      f3d_free(starts);
      return 0;
    }
    f3d_copy(data, records, (size_t)length * sizeof(f3d_real));
  }
  int round = 0;
  for (uint32_t at = 0, k = 0; k < count; k++) {
    starts[k] = at;
    const uint32_t kind = (uint32_t)data[at];
    round |= kind == F3D_CLOTH_BALL || kind == F3D_CLOTH_CAPSULE;
    at += record_length(data + at, length - at);
  }
  f3d_free(c->obstacles);
  f3d_free(c->obstacle_at);
  c->obstacles = data;
  c->obstacle_at = starts;
  c->obstacle_count = count;
  c->any_round = round;
  return 1;
}

void f3d_cloth_write_state(F3dCloth *c, const f3d_real *state) {
  for (uint32_t i = 0; i < c->point_count; i++) {
    const f3d_real *s = state + (size_t)i * F3D_CLOTH_STATE_FLOATS;
    c->position[i] = f3d_v3(s[0], s[1], s[2]);
    c->previous[i] = c->position[i];
    c->velocity[i] = f3d_v3(s[3], s[4], s[5]);
    c->inv_mass[i] = s[6] > F3D_R(0.0) ? s[6] : F3D_R(0.0);
  }
}

void f3d_cloth_read_state(const F3dCloth *c, f3d_real *state) {
  for (uint32_t i = 0; i < c->point_count; i++) {
    f3d_real *s = state + (size_t)i * F3D_CLOTH_STATE_FLOATS;
    s[0] = c->position[i].x;
    s[1] = c->position[i].y;
    s[2] = c->position[i].z;
    s[3] = c->velocity[i].x;
    s[4] = c->velocity[i].y;
    s[5] = c->velocity[i].z;
    s[6] = c->inv_mass[i];
  }
}

/* Damping, gravity and the wind into a predicted position; the start of
 * the substep kept in previous. */
static void predict(F3dCloth *c, const F3dClothSolveSettings *s, f3d_real h) {
  const F3dVec3 g = f3d_v3(s->gravity[0], s->gravity[1], s->gravity[2]);
  const f3d_real damped = F3D_R(1.0) - s->damping;
  for (uint32_t i = 0; i < c->point_count; i++) {
    c->previous[i] = c->position[i];
    if (c->inv_mass[i] == F3D_R(0.0)) continue;
    const F3dVec3 v = f3d_madd(f3d_scale(c->velocity[i], damped), g, h);
    c->position[i] = f3d_madd(c->position[i], v, h);
  }
  if (s->wind_drag == F3D_R(0.0) || c->triangle_count == 0) return;
  /* Drag along each triangle's normal, from where the substep started and
   * the velocity it started with, as a force: Δx = F w h². */
  const F3dVec3 air = f3d_v3(s->wind[0], s->wind[1], s->wind[2]);
  const f3d_real h2 = h * h;
  const f3d_real third = F3D_R(1.0) / F3D_R(3.0);
  for (uint32_t t = 0; t < c->triangle_count; t++) {
    const uint32_t *k = c->triangles + t * 3u;
    const F3dVec3 xa = c->previous[k[0]], xb = c->previous[k[1]], xc = c->previous[k[2]];
    const F3dVec3 cross = f3d_cross(f3d_sub(xb, xa), f3d_sub(xc, xa));
    const f3d_real len = f3d_sqrt(f3d_dot(cross, cross));
    if (len < F3D_R(1e-12)) continue;
    const F3dVec3 n = f3d_scale(cross, F3D_R(1.0) / len);
    const F3dVec3 mean = f3d_scale(
        f3d_add(f3d_add(c->velocity[k[0]], c->velocity[k[1]]), c->velocity[k[2]]), third);
    const f3d_real relative = f3d_dot(n, f3d_sub(air, mean));
    const f3d_real force = s->wind_drag * relative * (len * F3D_R(0.5)) * third;
    for (int corner = 0; corner < 3; corner++) {
      const uint32_t i = k[corner];
      const f3d_real w = c->inv_mass[i];
      if (w == F3D_R(0.0)) continue;
      /* A drag cannot turn the relative velocity round in one substep. */
      const f3d_real dv = f3d_abs(force * w * h);
      const f3d_real most = f3d_abs(relative);
      const f3d_real scale = dv > most && dv > F3D_R(0.0) ? most / dv : F3D_R(1.0);
      c->position[i] = f3d_madd(c->position[i], n, force * w * h2 * scale);
    }
  }
}

/* One XPBD pass over every constraint, colour by colour, each multiplier
 * carried from the substep's earlier passes. */
static void solve_edges(F3dCloth *c, f3d_real inv_h2) {
  for (uint32_t k = 0; k < c->colour_count; k++) {
    for (uint32_t e = c->colour_start[k]; e < c->colour_start[k + 1u]; e++) {
      const Edge *edge = &c->edges[e];
      const f3d_real wa = c->inv_mass[edge->a], wb = c->inv_mass[edge->b];
      const f3d_real w = wa + wb;
      if (w == F3D_R(0.0)) continue;
      const F3dVec3 d = f3d_sub(c->position[edge->a], c->position[edge->b]);
      const f3d_real len = f3d_sqrt(f3d_dot(d, d));
      if (len < F3D_R(1e-12)) continue;
      const f3d_real alpha = edge->compliance * inv_h2;
      const f3d_real step = (edge->rest - len - alpha * c->lambda[e]) / (w + alpha);
      c->lambda[e] += step;
      const F3dVec3 n = f3d_scale(d, F3D_R(1.0) / len);
      c->position[edge->a] = f3d_madd(c->position[edge->a], n, wa * step);
      c->position[edge->b] = f3d_madd(c->position[edge->b], n, -wb * step);
    }
  }
}

/* Each point's widest triangle where the sheet stands now: the circumradius,
 * or half the longest edge of an obtuse one. */
static void widest_triangles(F3dCloth *c) {
  f3d_zero(c->span, (size_t)c->point_count * sizeof(f3d_real));
  for (uint32_t t = 0; t < c->triangle_count; t++) {
    const uint32_t *k = c->triangles + t * 3u;
    const F3dVec3 a = c->position[k[0]], b = c->position[k[1]], p = c->position[k[2]];
    const F3dVec3 ab = f3d_sub(b, a), ac = f3d_sub(p, a), bc = f3d_sub(p, b);
    const F3dVec3 cross = f3d_cross(ab, ac);
    const f3d_real twice_area = f3d_sqrt(f3d_dot(cross, cross));
    if (twice_area <= F3D_R(1e-12)) continue;
    const f3d_real ab2 = f3d_dot(ab, ab), ac2 = f3d_dot(ac, ac), bc2 = f3d_dot(bc, bc);
    const f3d_real longest2 = f3d_max(ab2, f3d_max(ac2, bc2));
    const f3d_real r = longest2 > ab2 + ac2 + bc2 - longest2
                           ? F3D_R(0.5) * f3d_sqrt(longest2)
                           : f3d_sqrt(ab2 * ac2 * bc2) / (F3D_R(2.0) * twice_area);
    for (int j = 0; j < 3; j++) {
      if (r > c->span[k[j]]) c->span[k[j]] = r;
    }
  }
}

/* How far from a round shape's core a point has to sit so a triangle of
 * reach [span] there keeps its plane half a thickness clear. */
static f3d_real clearing(f3d_real radius, f3d_real thickness, f3d_real span) {
  const f3d_real contact = radius + thickness;
  if (!(span > F3D_R(0.0))) return contact;
  const f3d_real plane = radius + F3D_R(0.5) * thickness;
  const f3d_real s = span < plane ? span : plane;
  const f3d_real lifted = f3d_sqrt(plane * plane + s * s);
  return lifted > contact ? lifted : contact;
}

static int out_of_ball(F3dVec3 *x, F3dVec3 d, f3d_real reach, F3dVec3 *push) {
  const f3d_real d2 = f3d_dot(d, d);
  if (d2 >= reach * reach) return 0;
  const f3d_real len = f3d_sqrt(d2);
  const F3dVec3 n = len > F3D_R(1e-12) ? f3d_scale(d, F3D_R(1.0) / len) : f3d_v3(0, 1, 0);
  *push = f3d_scale(n, reach - len);
  *x = f3d_add(*x, *push);
  return 1;
}

/* The cell index of [u], floor(u), held to ±10⁹. */
static int32_t cell_of(f3d_real u) {
  const f3d_real v = f3d_clamp(u, F3D_R(-1e9), F3D_R(1e9));
  int32_t t = (int32_t)v;
  if ((f3d_real)t > v) t--;
  return t;
}

/* The ground's drawn height under (x, z), u and v cells from sample (0, 0). */
static f3d_real ground_height(const f3d_real *r, f3d_real u, f3d_real v) {
  const int32_t columns = (int32_t)r[5], rows = (int32_t)r[6];
  const f3d_real *h = r + 8;
  int32_t column = cell_of(u), row = cell_of(v);
  column = column < 0 ? 0 : (column > columns - 2 ? columns - 2 : column);
  row = row < 0 ? 0 : (row > rows - 2 ? rows - 2 : row);
  const f3d_real du = f3d_clamp(u - (f3d_real)column, F3D_R(0.0), F3D_R(1.0));
  const f3d_real dv = f3d_clamp(v - (f3d_real)row, F3D_R(0.0), F3D_R(1.0));
  const f3d_real h00 = h[row * columns + column], h10 = h[row * columns + column + 1];
  const f3d_real h01 = h[(row + 1) * columns + column];
  const f3d_real h11 = h[(row + 1) * columns + column + 1];
  return du >= dv ? h00 + (h10 - h00) * du + (h11 - h10) * dv
                  : h00 + (h11 - h01) * du + (h01 - h00) * dv;
}

/* Pushes [x] out of the obstacle record [r] by [thickness]; whether it
 * moved, and how far into [push]. */
static int push_outside(F3dVec3 *x, const f3d_real *r, f3d_real thickness, f3d_real span,
                        F3dVec3 *push) {
  *push = f3d_v3(0, 0, 0);
  switch ((uint32_t)r[0]) {
    case F3D_CLOTH_BALL:
      return out_of_ball(x, f3d_sub(*x, f3d_v3(r[1], r[2], r[3])),
                         clearing(r[4], thickness, span), push);
    case F3D_CLOTH_CAPSULE: {
      const f3d_real ly = x->y - r[2], half = r[5];
      const f3d_real cy = ly < -half ? -half : (ly > half ? half : ly);
      return out_of_ball(x, f3d_v3(x->x - r[1], ly - cy, x->z - r[3]),
                         clearing(r[4], thickness, span), push);
    }
    case F3D_CLOTH_CONVEX: {
      const uint32_t count = (uint32_t)r[1];
      if (count == 0) return 0;
      const f3d_real *plane = r + 2;
      f3d_real best = F3D_R(1e30);
      F3dVec3 out = f3d_v3(0, 0, 0);
      for (uint32_t p = 0; p < count; p++, plane += 4) {
        const F3dVec3 n = f3d_v3(plane[0], plane[1], plane[2]);
        const f3d_real signed_distance = f3d_dot(n, *x) - plane[3];
        if (signed_distance > thickness) return 0;
        const f3d_real margin = thickness - signed_distance;
        if (margin < best) {
          best = margin;
          out = n;
        }
      }
      *push = f3d_scale(out, best);
      *x = f3d_add(*x, *push);
      return 1;
    }
    case F3D_CLOTH_GROUND: {
      /* Straight up onto the surface, only over the field and only from
       * inside its solid slab. */
      const f3d_real cell = r[4];
      const f3d_real u = (x->x - r[1]) / cell, v = (x->z - r[3]) / cell;
      if (!(u >= F3D_R(0.0) && u <= r[5] - F3D_R(1.0) && v >= F3D_R(0.0) &&
            v <= r[6] - F3D_R(1.0))) {
        return 0;
      }
      const f3d_real ground = r[2] + ground_height(r, u, v) + thickness;
      if (x->y >= ground || x->y < ground - thickness - r[7]) return 0;
      push->y = ground - x->y;
      x->y = ground;
      return 1;
    }
    default:
      return 0;
  }
}

static void resolve_obstacles(F3dCloth *c, f3d_real thickness, int span, int contact) {
  for (uint32_t i = 0; i < c->point_count; i++) {
    if (c->inv_mass[i] == F3D_R(0.0)) continue;
    const f3d_real reach = span ? c->span[i] : F3D_R(0.0);
    for (uint32_t k = 0; k < c->obstacle_count; k++) {
      F3dVec3 push;
      if (!push_outside(&c->position[i], c->obstacles + c->obstacle_at[k], thickness, reach,
                        &push)) {
        continue;
      }
      if (contact) c->contact[i] = f3d_add(c->contact[i], push);
    }
  }
}

/* Takes back up to [friction] times each point's push from how far it slid
 * along the surface this substep. */
static void obstacle_friction(F3dCloth *c, f3d_real friction) {
  for (uint32_t i = 0; i < c->point_count; i++) {
    if (c->inv_mass[i] == F3D_R(0.0)) continue;
    const f3d_real depth = f3d_sqrt(f3d_dot(c->contact[i], c->contact[i]));
    if (depth < F3D_R(1e-12)) continue;
    const F3dVec3 n = f3d_scale(c->contact[i], F3D_R(1.0) / depth);
    const F3dVec3 moved = f3d_sub(c->position[i], c->previous[i]);
    const F3dVec3 slide = f3d_madd(moved, n, -f3d_dot(moved, n));
    const f3d_real slid = f3d_sqrt(f3d_dot(slide, slide));
    if (slid < F3D_R(1e-12)) continue;
    const f3d_real cut = slid <= friction * depth ? F3D_R(1.0) : friction * depth / slid;
    c->position[i] = f3d_madd(c->position[i], slide, -cut);
  }
}

/* How far past the thickness the close pairs are gathered, in thicknesses:
 * they are gathered again only once a point has moved half of that. */
#define SELF_SKIN F3D_R(0.5)

static int self_ready(F3dCloth *c) {
  SelfPairs *s = &c->self;
  if (s->cell_start != NULL) return 1;
  const size_t n = c->point_count;
  s->cell_start = (uint32_t *)f3d_alloc((2u * n + 2u) * sizeof(uint32_t));
  s->entries = (uint32_t *)f3d_alloc(n * sizeof(uint32_t));
  s->cells = (int32_t *)f3d_alloc(3u * n * sizeof(int32_t));
  s->built_at = (F3dVec3 *)f3d_alloc(n * sizeof(F3dVec3));
  s->pair_start = (uint32_t *)f3d_alloc((n + 1u) * sizeof(uint32_t));
  s->pairs = (uint32_t *)f3d_alloc(8u * n * sizeof(uint32_t));
  s->pair_capacity = (uint32_t)(8u * n);
  if (s->cell_start != NULL && s->entries != NULL && s->cells != NULL && s->built_at != NULL &&
      s->pair_start != NULL && s->pairs != NULL) {
    return 1;
  }
  f3d_free(s->cell_start);
  f3d_free(s->entries);
  f3d_free(s->cells);
  f3d_free(s->built_at);
  f3d_free(s->pair_start);
  f3d_free(s->pairs);
  f3d_zero(s, sizeof *s);
  return 0;
}

/* The bucket of a cell: 10 bits of each coordinate, as the reference's. */
static uint32_t self_bucket(int32_t x, int32_t y, int32_t z, uint32_t table) {
  return ((((uint32_t)x & 1023u) << 20) | (((uint32_t)y & 1023u) << 10) |
          ((uint32_t)z & 1023u)) %
         table;
}

/* The own cell, then the 13 neighbours after it in lexicographic order:
 * each pair is found once. */
static const int8_t SELF_OFFSETS[14][3] = {
    {0, 0, 0},  {0, 0, 1},  {0, 1, -1}, {0, 1, 0},  {0, 1, 1},  {1, -1, -1}, {1, -1, 0},
    {1, -1, 1}, {1, 0, -1}, {1, 0, 0},  {1, 0, 1},  {1, 1, -1}, {1, 1, 0},   {1, 1, 1},
};

/* Hashes the points and lists every pair closer than [reach] that is not a
 * pair of neighbours at rest; 0 when the list could not grow. */
static int self_find(F3dCloth *c, f3d_real thickness, f3d_real reach) {
  SelfPairs *s = &c->self;
  const uint32_t n = c->point_count, table = 2u * n + 1u;
  const f3d_real inverse = F3D_R(1.0) / reach;
  f3d_zero(s->cell_start, (size_t)(table + 1u) * sizeof(uint32_t));
  for (uint32_t i = 0; i < n; i++) {
    int32_t *cell = s->cells + i * 3u;
    cell[0] = cell_of(c->position[i].x * inverse);
    cell[1] = cell_of(c->position[i].y * inverse);
    cell[2] = cell_of(c->position[i].z * inverse);
    s->cell_start[self_bucket(cell[0], cell[1], cell[2], table)]++;
  }
  uint32_t running = 0;
  for (uint32_t h = 0; h < table; h++) {
    running += s->cell_start[h];
    s->cell_start[h] = running;
  }
  s->cell_start[table] = running;
  for (uint32_t i = n; i-- > 0;) {
    const int32_t *cell = s->cells + i * 3u;
    const uint32_t h = self_bucket(cell[0], cell[1], cell[2], table);
    s->entries[--s->cell_start[h]] = i;
  }
  const f3d_real reach2 = reach * reach;
  const f3d_real rest2 = thickness * thickness * F3D_R(1.000001);
  uint32_t count = 0;
  for (uint32_t i = 0; i < n; i++) {
    s->pair_start[i] = count;
    const F3dVec3 xi = c->position[i];
    const int32_t *own = s->cells + i * 3u;
    for (int o = 0; o < 14; o++) {
      const int32_t cx = own[0] + SELF_OFFSETS[o][0], cy = own[1] + SELF_OFFSETS[o][1],
                    cz = own[2] + SELF_OFFSETS[o][2];
      const uint32_t h = self_bucket(cx, cy, cz, table);
      for (uint32_t k = s->cell_start[h]; k < s->cell_start[h + 1u]; k++) {
        const uint32_t j = s->entries[k];
        if (o == 0 && j <= i) continue;
        const F3dVec3 d = f3d_sub(c->position[j], xi);
        if (f3d_dot(d, d) >= reach2) continue;
        const int32_t *other = s->cells + j * 3u;
        if (other[0] != cx || other[1] != cy || other[2] != cz) continue;
        if (c->inv_mass[i] + c->inv_mass[j] == F3D_R(0.0)) continue;
        const F3dVec3 r = f3d_sub(c->rest[j], c->rest[i]);
        if (f3d_dot(r, r) < rest2) continue;
        if (count == s->pair_capacity) {
          if (s->pair_capacity > (1u << 30)) return 0;
          uint32_t *grown =
              (uint32_t *)f3d_realloc(s->pairs, (size_t)s->pair_capacity * 2u * sizeof(uint32_t));
          if (grown == NULL) return 0;
          s->pairs = grown;
          s->pair_capacity *= 2u;
        }
        s->pairs[count++] = j;
      }
    }
  }
  s->pair_start[n] = count;
  return 1;
}

/* Gathers the pairs again unless no point has moved half the skin since
 * they were; 0 when they could not be. */
static int self_update(F3dCloth *c, f3d_real thickness) {
  SelfPairs *s = &c->self;
  if (s->built) {
    const f3d_real half = F3D_R(0.5) * SELF_SKIN * thickness;
    const f3d_real limit = half * half;
    int moved = 0;
    for (uint32_t i = 0; i < c->point_count && !moved; i++) {
      const F3dVec3 d = f3d_sub(c->position[i], s->built_at[i]);
      moved = f3d_dot(d, d) > limit;
    }
    if (!moved) return 1;
  }
  s->built = 0;
  if (!self_find(c, thickness, thickness * (F3D_R(1.0) + SELF_SKIN))) return 0;
  f3d_copy(s->built_at, c->position, (size_t)c->point_count * sizeof(F3dVec3));
  s->built = 1;
  return 1;
}

/* Every listed pair closer than [thickness] pushed apart to it, and
 * [friction] of their slide against each other this substep taken out. */
static void self_solve(F3dCloth *c, f3d_real thickness, f3d_real friction) {
  const SelfPairs *s = &c->self;
  const f3d_real t2 = thickness * thickness;
  F3dVec3 *p = c->position;
  for (uint32_t i = 0; i < c->point_count; i++) {
    const f3d_real wi = c->inv_mass[i];
    for (uint32_t k = s->pair_start[i]; k < s->pair_start[i + 1u]; k++) {
      const uint32_t j = s->pairs[k];
      const f3d_real wj = c->inv_mass[j];
      const F3dVec3 d = f3d_sub(p[i], p[j]);
      const f3d_real d2 = f3d_dot(d, d);
      if (d2 >= t2 || d2 == F3D_R(0.0)) continue;
      const f3d_real len = f3d_sqrt(d2);
      const F3dVec3 n = f3d_scale(d, F3D_R(1.0) / len);
      const f3d_real w = wi + wj;
      const f3d_real depth = (thickness - len) / w;
      p[i] = f3d_madd(p[i], n, wi * depth);
      p[j] = f3d_madd(p[j], n, -wj * depth);
      if (friction <= F3D_R(0.0)) continue;
      const F3dVec3 r = f3d_sub(f3d_sub(p[i], c->previous[i]), f3d_sub(p[j], c->previous[j]));
      const F3dVec3 t = f3d_scale(f3d_madd(r, n, -f3d_dot(r, n)), friction / w);
      p[i] = f3d_madd(p[i], t, -wi);
      p[j] = f3d_madd(p[j], t, wj);
    }
  }
}

void f3d_cloth_solve(F3dCloth *c, const F3dClothSolveSettings *s, f3d_real dt) {
  if (!(f3d_finite(dt) && dt > F3D_R(0.0)) || s->substeps == 0) return;
  const f3d_real h = dt / (f3d_real)s->substeps;
  const f3d_real inv_h2 = F3D_R(1.0) / (h * h);
  const int contact = s->friction > F3D_R(0.0) && c->obstacle_count > 0;
  /* Without the memory for the pairs the layers pass through, rather than
   * the whole step failing. */
  const int self = s->self_thickness > F3D_R(0.0) && c->point_count > 1 && self_ready(c);
  const int span = c->any_round && c->triangle_count > 0;
  c->self.built = 0;
  if (span) widest_triangles(c);
  for (uint32_t sub = 0; sub < s->substeps; sub++) {
    predict(c, s, h);
    const int pairs = self && self_update(c, s->self_thickness);
    f3d_zero(c->lambda, (size_t)c->edge_count * sizeof(f3d_real));
    if (contact) f3d_zero(c->contact, (size_t)c->point_count * sizeof(F3dVec3));
    for (uint32_t iteration = 0; iteration < s->iterations; iteration++) {
      solve_edges(c, inv_h2);
      if (pairs) self_solve(c, s->self_thickness, s->self_friction);
      resolve_obstacles(c, s->thickness, span, contact);
    }
    if (contact) obstacle_friction(c, s->friction);
    const f3d_real inverse = F3D_R(1.0) / h;
    for (uint32_t i = 0; i < c->point_count; i++) {
      if (c->inv_mass[i] == F3D_R(0.0)) continue;
      c->velocity[i] = f3d_scale(f3d_sub(c->position[i], c->previous[i]), inverse);
    }
  }
}
