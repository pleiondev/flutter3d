/*
 * Fluid on the CPU — P9, phase 10: the reference for the GPU's, and the
 * fallback where there is none. See f3d_physics.h for what it does; the
 * WGSL in f3d_gpu_fluid.c does the same, pass for pass.
 *
 * Position-based fluids (Macklin and Müller, 2013), each substep:
 *
 *   1. gravity into the velocity, a predicted position from it, and each
 *      particle into its cell of a hashed grid as wide as the kernel, with
 *      the cell it went in kept beside it;
 *   2. as many times as the settings say: each particle's density from its
 *      neighbours and the tank's walls, and the multiplier that would bring
 *      it to rest density — only ever pushing apart, never pulling, so
 *      particles do not clump; then each particle moved by its own and its
 *      neighbours' multipliers, pushed off the walls, and held inside;
 *   3. the velocity from where it went, smoothed towards its neighbours'
 *      (XSPH viscosity), and the position taken.
 *
 * A wall counts as the fluid going on past it: layers of still particles
 * the spacing apart, the first half a spacing beyond the wall, each right
 * under the particle — so they add to its density, and push it straight
 * off the wall as a neighbour of the same multiplier would. Without them
 * a particle by the floor has no neighbours below, is short of density,
 * and the water above presses the bottom layer flat against the floor:
 * 325 particles where a layer holds 200, and the water too shallow.
 *
 * Each pass reads what the last wrote and writes only its own particle's,
 * so the GPU runs every particle of a pass at once. Mass is one per
 * particle, and rest density is what the kernel sums to over a cubic
 * lattice of the spacing.
 */
#include "f3d_internal.h"

struct F3dFluid {
  F3dVec3 *position;
  F3dVec3 *predicted;
  F3dVec3 *velocity;
  F3dVec3 *next;
  f3d_real *lambda;
  f3d_real *density;
  uint32_t *cell_head;
  uint32_t *next_in_cell;
  int32_t *cell;
  uint32_t cells;
  uint32_t capacity;
  uint32_t count;
  uint32_t next_slot;
  f3d_real spacing;
  f3d_real h;
  f3d_real rest_density;
  f3d_real poly6;
  f3d_real spiky;
  /* The tank's walls, for the step under way. */
  F3dVec3 tank_min;
  F3dVec3 tank_max;
};

#define NONE 0xFFFFFFFFu
/* π, for the kernels' constants: a number, not a call. */
#define PI F3D_R(3.14159265358979323846)

static f3d_real poly6(const F3dFluid *f, f3d_real r2) {
  const f3d_real d = f->h * f->h - r2;
  return d > F3D_R(0.0) ? f->poly6 * d * d * d : F3D_R(0.0);
}

/* The spiky kernel's gradient at [d], |d| = [r]: towards d, falling to
 * nought at h. */
static F3dVec3 spiky(const F3dFluid *f, F3dVec3 d, f3d_real r) {
  if (!(r > F3D_R(0.0)) || !(r < f->h)) return f3d_v3(0, 0, 0);
  const f3d_real k = f->h - r;
  return f3d_scale(d, f->spiky * k * k / r);
}

F3dFluid *f3d_fluid_create(uint32_t capacity, f3d_real spacing) {
  if (capacity == 0 || capacity > (1u << 22) || !(f3d_finite(spacing) && spacing > F3D_R(0.0))) {
    return NULL;
  }
  F3dFluid *f = (F3dFluid *)f3d_alloc(sizeof(F3dFluid));
  if (f == NULL) return NULL;
  f3d_zero(f, sizeof(F3dFluid));
  uint32_t cells = 1;
  while (cells < capacity * 2u) cells <<= 1;
  f->cells = cells;
  f->capacity = capacity;
  const size_t vec = (size_t)capacity * sizeof(F3dVec3);
  const size_t real = (size_t)capacity * sizeof(f3d_real);
  f->position = (F3dVec3 *)f3d_alloc(vec);
  f->predicted = (F3dVec3 *)f3d_alloc(vec);
  f->velocity = (F3dVec3 *)f3d_alloc(vec);
  f->next = (F3dVec3 *)f3d_alloc(vec);
  f->lambda = (f3d_real *)f3d_alloc(real);
  f->density = (f3d_real *)f3d_alloc(real);
  f->cell_head = (uint32_t *)f3d_alloc((size_t)cells * sizeof(uint32_t));
  f->next_in_cell = (uint32_t *)f3d_alloc((size_t)capacity * sizeof(uint32_t));
  f->cell = (int32_t *)f3d_alloc((size_t)capacity * 3u * sizeof(int32_t));
  if (f->position == NULL || f->predicted == NULL || f->velocity == NULL || f->next == NULL ||
      f->lambda == NULL || f->density == NULL || f->cell_head == NULL ||
      f->next_in_cell == NULL || f->cell == NULL) {
    f3d_fluid_destroy(f);
    return NULL;
  }
  f3d_zero(f->density, real);
  f->spacing = spacing;
  f->h = spacing * F3D_R(2.0);
  const f3d_real h2 = f->h * f->h;
  const f3d_real h3 = h2 * f->h;
  f->poly6 = F3D_R(315.0) / (F3D_R(64.0) * PI * h3 * h3 * h3);
  f->spiky = F3D_R(-45.0) / (PI * h3 * h3);
  /* Rest density: the kernel summed over a cubic lattice of the spacing. */
  f3d_real rest = 0;
  for (int x = -2; x <= 2; x++) {
    for (int y = -2; y <= 2; y++) {
      for (int z = -2; z <= 2; z++) {
        const f3d_real r2 = (f3d_real)(x * x + y * y + z * z) * spacing * spacing;
        rest += poly6(f, r2);
      }
    }
  }
  f->rest_density = rest;
  return f;
}

void f3d_fluid_destroy(F3dFluid *f) {
  if (f == NULL) return;
  f3d_free(f->position);
  f3d_free(f->predicted);
  f3d_free(f->velocity);
  f3d_free(f->next);
  f3d_free(f->lambda);
  f3d_free(f->density);
  f3d_free(f->cell_head);
  f3d_free(f->next_in_cell);
  f3d_free(f->cell);
  f3d_free(f);
}

uint32_t f3d_fluid_capacity(const F3dFluid *f) { return f->capacity; }

f3d_real f3d_fluid_rest_density(const F3dFluid *f) { return f->rest_density; }

uint32_t f3d_fluid_add(F3dFluid *f, const f3d_real *data, uint32_t count) {
  const uint32_t first = f->next_slot;
  for (uint32_t i = 0; i < count; i++) {
    const f3d_real *in = data + (size_t)i * 6u;
    const uint32_t at = f->next_slot;
    f->position[at] = f3d_v3(in[0], in[1], in[2]);
    f->velocity[at] = f3d_v3(in[3], in[4], in[5]);
    f->density[at] = 0;
    f->next_slot = (f->next_slot + 1u) % f->capacity;
    if (f->count < f->capacity) f->count++;
  }
  return first;
}

static int32_t cell_coord(f3d_real x, f3d_real inv_cell) {
  const f3d_real v = f3d_clamp(x * inv_cell, F3D_R(-1e9), F3D_R(1e9));
  int32_t t = (int32_t)v;
  if ((f3d_real)t > v) t--;
  return t;
}

static uint32_t cell_hash(int32_t x, int32_t y, int32_t z, uint32_t cells) {
  return (((uint32_t)x * 73856093u) ^ ((uint32_t)y * 19349663u) ^
          ((uint32_t)z * 83492791u)) &
         (cells - 1u);
}

/* The walls' share of a particle at [p]: the density of the still layers
 * past each wall within reach, and the push of their spiky gradients,
 * which in-plane cancel and leave the normal. */
typedef struct Walls {
  f3d_real density;
  F3dVec3 push;
} Walls;

static Walls walls(const F3dFluid *f, F3dVec3 p) {
  Walls w;
  w.density = 0;
  w.push = f3d_v3(0, 0, 0);
  const f3d_real at[3] = {p.x, p.y, p.z};
  const f3d_real lo[3] = {f->tank_min.x, f->tank_min.y, f->tank_min.z};
  const f3d_real hi[3] = {f->tank_max.x, f->tank_max.y, f->tank_max.z};
  const f3d_real s = f->spacing;
  for (int axis = 0; axis < 3; axis++) {
    for (int side = 0; side < 2; side++) {
      const f3d_real off = side == 0 ? at[axis] - lo[axis] : hi[axis] - at[axis];
      f3d_real normal = 0;
      for (f3d_real z = off + s * F3D_R(0.5); z < f->h; z += s) {
        for (int i = -2; i <= 2; i++) {
          for (int j = -2; j <= 2; j++) {
            const f3d_real r2 = (f3d_real)(i * i + j * j) * s * s + z * z;
            if (!(r2 < f->h * f->h)) continue;
            w.density += poly6(f, r2);
            const f3d_real r = f3d_sqrt(r2);
            const f3d_real k = f->h - r;
            normal += f->spiky * k * k / r * z;
          }
        }
      }
      F3dVec3 dir = f3d_v3(0, 0, 0);
      const f3d_real sign = side == 0 ? F3D_R(1.0) : F3D_R(-1.0);
      if (axis == 0) dir.x = sign;
      if (axis == 1) dir.y = sign;
      if (axis == 2) dir.z = sign;
      w.push = f3d_madd(w.push, dir, normal);
    }
  }
  return w;
}

/* What a neighbour pass does with one neighbour. */
typedef enum Visit { DENSITY, MOVE, SMOOTH } Visit;

typedef struct Sum {
  f3d_real density;
  F3dVec3 gradient;
  f3d_real gradient2;
  F3dVec3 move;
  F3dVec3 smooth;
} Sum;

/* Sums [visit] over particle [i]'s neighbours: every particle in the 27
 * cells round the one it went in, met in the cell it went in. */
static Sum neighbours(const F3dFluid *f, uint32_t i, Visit visit) {
  Sum sum;
  f3d_zero(&sum, sizeof sum);
  const F3dVec3 p = f->predicted[i];
  const int32_t *c = &f->cell[i * 3u];
  for (int32_t x = c[0] - 1; x <= c[0] + 1; x++) {
    for (int32_t y = c[1] - 1; y <= c[1] + 1; y++) {
      for (int32_t z = c[2] - 1; z <= c[2] + 1; z++) {
        for (uint32_t j = f->cell_head[cell_hash(x, y, z, f->cells)]; j != NONE;
             j = f->next_in_cell[j]) {
          const int32_t *cj = &f->cell[j * 3u];
          if (cj[0] != x || cj[1] != y || cj[2] != z) continue;
          const F3dVec3 d = f3d_sub(p, f->predicted[j]);
          const f3d_real r2 = f3d_dot(d, d);
          if (!(r2 < f->h * f->h)) continue;
          const f3d_real r = f3d_sqrt(r2);
          switch (visit) {
            case DENSITY: {
              sum.density += poly6(f, r2);
              if (j == i) break;
              const F3dVec3 g = f3d_scale(spiky(f, d, r), F3D_R(1.0) / f->rest_density);
              sum.gradient = f3d_add(sum.gradient, g);
              sum.gradient2 += f3d_dot(g, g);
              break;
            }
            case MOVE:
              if (j == i) break;
              sum.move = f3d_madd(sum.move, spiky(f, d, r), f->lambda[i] + f->lambda[j]);
              break;
            case SMOOTH:
              if (j == i) break;
              sum.smooth = f3d_madd(sum.smooth, f3d_sub(f->velocity[j], f->velocity[i]),
                                    poly6(f, r2) / f->rest_density);
              break;
          }
        }
      }
    }
  }
  if (visit == DENSITY || visit == MOVE) {
    const Walls w = walls(f, p);
    if (visit == DENSITY) {
      sum.density += w.density;
      sum.gradient = f3d_madd(sum.gradient, w.push, F3D_R(1.0) / f->rest_density);
    } else {
      /* As a neighbour with the particle's own multiplier. */
      sum.move = f3d_madd(sum.move, w.push, f->lambda[i] + f->lambda[i]);
    }
  }
  return sum;
}

void f3d_fluid_step(F3dFluid *f, const F3dFluidSettings *s, f3d_real dt) {
  if (!(f3d_finite(dt) && dt > F3D_R(0.0)) || f->count == 0) return;
  const uint32_t substeps = s->substeps > 0 ? s->substeps : 1u;
  const uint32_t iterations = s->iterations > 0 ? s->iterations : 1u;
  const f3d_real h = dt / (f3d_real)substeps;
  const F3dVec3 g = f3d_v3(s->gravity[0], s->gravity[1], s->gravity[2]);
  const f3d_real inv_cell = F3D_R(1.0) / f->h;
  const f3d_real margin = f->spacing * F3D_R(0.5);
  const F3dVec3 lo = f3d_v3(s->tank_min[0] + margin, s->tank_min[1] + margin, s->tank_min[2] + margin);
  const F3dVec3 hi = f3d_v3(s->tank_max[0] - margin, s->tank_max[1] - margin, s->tank_max[2] - margin);
  const uint32_t n = f->count;
  f->tank_min = f3d_v3(s->tank_min[0], s->tank_min[1], s->tank_min[2]);
  f->tank_max = f3d_v3(s->tank_max[0], s->tank_max[1], s->tank_max[2]);
  for (uint32_t sub = 0; sub < substeps; sub++) {
    /* 1. Predict, and the grid. */
    for (uint32_t c = 0; c < f->cells; c++) f->cell_head[c] = NONE;
    for (uint32_t i = 0; i < n; i++) {
      f->velocity[i] = f3d_madd(f->velocity[i], g, h);
      f->predicted[i] = f3d_madd(f->position[i], f->velocity[i], h);
      int32_t *c = &f->cell[i * 3u];
      c[0] = cell_coord(f->predicted[i].x, inv_cell);
      c[1] = cell_coord(f->predicted[i].y, inv_cell);
      c[2] = cell_coord(f->predicted[i].z, inv_cell);
      const uint32_t at = cell_hash(c[0], c[1], c[2], f->cells);
      f->next_in_cell[i] = f->cell_head[at];
      f->cell_head[at] = i;
    }
    /* 2. Density, as many times as asked. */
    for (uint32_t it = 0; it < iterations; it++) {
      for (uint32_t i = 0; i < n; i++) {
        const Sum sum = neighbours(f, i, DENSITY);
        f->density[i] = sum.density;
        const f3d_real crowd = f3d_max(sum.density / f->rest_density - F3D_R(1.0), F3D_R(0.0));
        f->lambda[i] = -crowd / (sum.gradient2 + f3d_dot(sum.gradient, sum.gradient) + s->relaxation);
      }
      for (uint32_t i = 0; i < n; i++) {
        const Sum sum = neighbours(f, i, MOVE);
        F3dVec3 p = f3d_madd(f->predicted[i], sum.move, F3D_R(1.0) / f->rest_density);
        p.x = f3d_clamp(p.x, lo.x, hi.x);
        p.y = f3d_clamp(p.y, lo.y, hi.y);
        p.z = f3d_clamp(p.z, lo.z, hi.z);
        f->next[i] = p;
      }
      for (uint32_t i = 0; i < n; i++) f->predicted[i] = f->next[i];
    }
    /* 3. The velocity from where it went, smoothed; the position taken. */
    for (uint32_t i = 0; i < n; i++) {
      f->velocity[i] = f3d_scale(f3d_sub(f->predicted[i], f->position[i]), F3D_R(1.0) / h);
    }
    for (uint32_t i = 0; i < n; i++) {
      const Sum sum = neighbours(f, i, SMOOTH);
      f->next[i] = f3d_madd(f->velocity[i], sum.smooth, s->viscosity);
    }
    for (uint32_t i = 0; i < n; i++) {
      f->velocity[i] = f->next[i];
      f->position[i] = f->predicted[i];
    }
  }
}

uint32_t f3d_fluid_read(const F3dFluid *f, f3d_real *out, uint32_t capacity) {
  const uint32_t n = capacity < f->count ? capacity : f->count;
  for (uint32_t i = 0; i < n; i++) {
    out[i * 4u] = f->position[i].x;
    out[i * 4u + 1u] = f->position[i].y;
    out[i * 4u + 2u] = f->position[i].z;
    out[i * 4u + 3u] = f->density[i] / f->rest_density;
  }
  return n;
}
