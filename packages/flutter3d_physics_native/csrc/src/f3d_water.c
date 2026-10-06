/*
 * Water over ground — a stream, a pond, a waterfall into it.
 *
 * Shallow water (after Chentanez and Müller, 2010): in each column of a
 * grid the water moves as one, with its depth at the column's centre and
 * its velocity across each face between two columns. A step is cut into
 * substeps no longer than a quarter of the time a wave takes to cross a
 * cell, and in each:
 *
 *   1. the springs well up;
 *   2. the velocities are carried along themselves, backwards from where
 *      they are to where they came from;
 *   3. each face is pushed by the slope of the surface across it, g·Δη/Δx,
 *      the surface being the ground, the water and what bodies standing in
 *      it fill; held back by Manning's friction, g·n²·|u|·u / h^(4/3),
 *      taken implicitly so it never turns the flow round; and pulled by
 *      the wind's stress on the surface over the depth;
 *   4. water crosses each face, as much as its velocity carries of the
 *      depth on the side it comes from, and a column that would give more
 *      than it holds gives what it holds, every face it gives through cut
 *      alike — so the water is never less than none and none is made.
 *
 * A face with no water on the side it would carry from carries nothing,
 * and water does not climb onto dry ground standing above its surface.
 * Water crossing a face where the ground drops by more than a cell — a
 * drop steeper than forty-five degrees — onto a surface lower than its own
 * by as much does not go into the next column: it leaves as a drop of spray at the face, flies, and lands
 * in the water or on the ground where it comes down, putting its volume
 * and its push there. That is a waterfall, and the waves at its foot.
 *
 * A dynamic body in the water stands in the columns it fills, seen as the
 * ball of its own volume: the surface rises by what it fills, so a stone
 * dropped in pushes waves out from where it went in, and it is held up by
 * the weight of what it displaces, ρgV, at the middle of what is under
 * water. The flow drags it by ½ρC_d·A|Δv|Δv over the part of it under
 * water, never more than would stop it against the flow in one step.
 *
 * Every loop runs in grid order, the spray in the order it was made, so
 * the same world pours the same water everywhere.
 */
#include "f3d_internal.h"

/* kg/m³. */
#define F3D_WATER_DENSITY F3D_R(1000.0)
/* How thin water is still water, m: below it a column is dry. */
#define F3D_WATER_DRY F3D_R(1e-4)
/* Wind's drag on water (Large and Pond's open-sea value). */
#define F3D_WIND_ON_WATER F3D_R(1.3e-3)
/* A ball's drag across the flow. */
#define F3D_BODY_IN_WATER F3D_R(0.8)
/* The most substeps a step is cut into; past them the flow is held to
 * what the last allows. */
#define F3D_WATER_MOST_SUBSTEPS 32u

/* ------------------------------------------------------------- the grid */

typedef struct Grid {
  F3dWaterSlot *slot;
  uint32_t nx, nz, n;
  f3d_real cell, area;
  f3d_real *ground, *depth, *u, *w, *filled;
} Grid;

static uint32_t reals_of(uint32_t nx, uint32_t nz) {
  return 3u * nx * nz + (nx + 1u) * nz + nx * (nz + 1u);
}

static F3dWaterSlot *water_of(const F3dWorld *world, F3dWater water) {
  if (water == 0 || water > world->s.water_count) return NULL;
  F3dWaterSlot *w = &world->waters[water - 1u];
  return w->live ? w : NULL;
}

static Grid grid_of(const F3dWorld *world, F3dWaterSlot *w) {
  Grid g;
  g.slot = w;
  g.nx = w->nx;
  g.nz = w->nz;
  g.n = w->nx * w->nz;
  g.cell = w->cell;
  g.area = w->cell * w->cell;
  g.ground = world->water_data + w->first;
  g.depth = g.ground + g.n;
  g.u = g.depth + g.n;
  g.w = g.u + (g.nx + 1u) * g.nz;
  g.filled = g.w + g.nx * (g.nz + 1u);
  return g;
}

/* The surface over cell c, above the grid's origin. */
static f3d_real surface(const Grid *g, uint32_t c) {
  return g->ground[c] + g->depth[c] + g->filled[c] / g->area;
}

/* The cell (x, z) falls in, relative to the world's origin, or −1. */
static int32_t cell_at(const Grid *g, f3d_real x, f3d_real z) {
  const f3d_real fx = (x - g->slot->origin.x) / g->cell;
  const f3d_real fz = (z - g->slot->origin.z) / g->cell;
  if (!(fx >= F3D_R(0.0) && fz >= F3D_R(0.0))) return -1;
  const uint32_t i = (uint32_t)fx, j = (uint32_t)fz;
  if (i >= g->nx || j >= g->nz) return -1;
  return (int32_t)(i + j * g->nx);
}

/* x^(1/3) for x ≥ 0, by Newton's method: the same bits everywhere. */
static f3d_real cube_root(f3d_real x) {
  if (!(x > F3D_R(0.0))) return F3D_R(0.0);
  f3d_real y = x > F3D_R(1.0) ? f3d_sqrt(x) : F3D_R(1.0);
  for (int i = 0; i < 40; i++) y -= (y * y * y - x) / (F3D_R(3.0) * y * y);
  return y;
}

/* A velocity grid read between its samples: [count_x] × [count_z] of them,
 * the first at (x0, z0) in cells, clamped at its edges. */
static f3d_real bilinear(const f3d_real *v, uint32_t count_x, uint32_t count_z,
                         f3d_real x, f3d_real z) {
  x = f3d_clamp(x, F3D_R(0.0), (f3d_real)(count_x - 1u));
  z = f3d_clamp(z, F3D_R(0.0), (f3d_real)(count_z - 1u));
  uint32_t i = (uint32_t)x, j = (uint32_t)z;
  if (i >= count_x - 1u) i = count_x > 1u ? count_x - 2u : 0u;
  if (j >= count_z - 1u) j = count_z > 1u ? count_z - 2u : 0u;
  const f3d_real fx = count_x > 1u ? x - (f3d_real)i : F3D_R(0.0);
  const f3d_real fz = count_z > 1u ? z - (f3d_real)j : F3D_R(0.0);
  const uint32_t i1 = count_x > 1u ? i + 1u : i;
  const uint32_t j1 = count_z > 1u ? j + 1u : j;
  const f3d_real a = v[i + j * count_x], b = v[i1 + j * count_x];
  const f3d_real c = v[i + j1 * count_x], d = v[i1 + j1 * count_x];
  return (a + (b - a) * fx) + ((c + (d - c) * fx) - (a + (b - a) * fx)) * fz;
}

/* The flow at a point in cells: its x velocity from the x faces, which
 * stand at whole x and half z, and its z velocity from the z faces. */
static f3d_real flow_x(const Grid *g, f3d_real x, f3d_real z) {
  return bilinear(g->u, g->nx + 1u, g->nz, x, z - F3D_R(0.5));
}

static f3d_real flow_z(const Grid *g, f3d_real x, f3d_real z) {
  return bilinear(g->w, g->nx, g->nz + 1u, x - F3D_R(0.5), z);
}

/* ------------------------------------------------------- making and data */

F3dWater f3d_water_create(F3dWorld *world, uint32_t nx, uint32_t nz,
                          f3d_real cell, f3d_real ox, f3d_real oy, f3d_real oz,
                          const f3d_real *ground) {
  if (nx == 0 || nz == 0 || nx > 4096u || nz > 4096u || ground == NULL) return 0;
  if (!(f3d_finite(cell) && cell > F3D_R(0.0) && f3d_finite(ox) &&
        f3d_finite(oy) && f3d_finite(oz))) {
    return 0;
  }
  for (uint32_t c = 0; c < nx * nz; c++) {
    if (!f3d_finite(ground[c])) return 0;
  }
  const uint32_t size = reals_of(nx, nz);
  f3d_real *data = (f3d_real *)f3d_realloc(
      world->water_data,
      ((size_t)world->s.water_reals + size) * sizeof(f3d_real));
  if (data == NULL) return 0;
  world->water_data = data;
  F3dWaterSlot *all = (F3dWaterSlot *)f3d_realloc(
      world->waters, ((size_t)world->s.water_count + 1u) * sizeof(F3dWaterSlot));
  if (all == NULL) return 0;
  world->waters = all;
  F3dWaterSlot *w = &all[world->s.water_count];
  f3d_zero(w, sizeof *w);
  w->live = 1;
  w->nx = nx;
  w->nz = nz;
  w->first = world->s.water_reals;
  w->cell = cell;
  w->origin = f3d_v3(ox, oy, oz);
  w->roughness = F3D_R(0.03);
  f3d_real *mine = data + w->first;
  f3d_zero(mine, (size_t)size * sizeof(f3d_real));
  f3d_copy(mine, ground, (size_t)nx * nz * sizeof(f3d_real));
  world->s.water_reals += size;
  world->s.water_count++;
  return world->s.water_count;
}

int f3d_water_destroy(F3dWorld *world, F3dWater water) {
  F3dWaterSlot *w = water_of(world, water);
  if (w == NULL) return 0;
  /* Its reals closed up: every later water's move down by its share. */
  const uint32_t size = reals_of(w->nx, w->nz);
  const uint32_t from = w->first + size;
  for (uint32_t k = from; k < world->s.water_reals; k++) {
    world->water_data[k - size] = world->water_data[k];
  }
  world->s.water_reals -= size;
  for (uint32_t i = 0; i < world->s.water_count; i++) {
    F3dWaterSlot *o = &world->waters[i];
    if (o->live && o->first > w->first) o->first -= size;
  }
  w->live = 0;
  /* Its spray falls with it. */
  uint32_t kept = 0;
  for (uint32_t k = 0; k < world->s.spray_count; k++) {
    if (world->spray[k].water != water) world->spray[kept++] = world->spray[k];
  }
  world->s.spray_count = kept;
  return 1;
}

int f3d_water_is_valid(const F3dWorld *world, F3dWater water) {
  return water_of(world, water) != NULL;
}

int f3d_water_set_ground(F3dWorld *world, F3dWater water,
                         const f3d_real *ground) {
  F3dWaterSlot *w = water_of(world, water);
  if (w == NULL || ground == NULL) return 0;
  for (uint32_t c = 0; c < w->nx * w->nz; c++) {
    if (!f3d_finite(ground[c])) return 0;
  }
  Grid g = grid_of(world, w);
  f3d_copy(g.ground, ground, (size_t)g.n * sizeof(f3d_real));
  return 1;
}

int f3d_water_fill(F3dWorld *world, F3dWater water, f3d_real x0, f3d_real z0,
                   f3d_real x1, f3d_real z1, f3d_real level) {
  F3dWaterSlot *w = water_of(world, water);
  if (w == NULL || !(f3d_finite(x0) && f3d_finite(z0) && f3d_finite(x1) &&
                     f3d_finite(z1) && f3d_finite(level))) {
    return 0;
  }
  Grid g = grid_of(world, w);
  for (uint32_t j = 0; j < g.nz; j++) {
    for (uint32_t i = 0; i < g.nx; i++) {
      const f3d_real x = w->origin.x + ((f3d_real)i + F3D_R(0.5)) * g.cell;
      const f3d_real z = w->origin.z + ((f3d_real)j + F3D_R(0.5)) * g.cell;
      if (x < f3d_min(x0, x1) || x > f3d_max(x0, x1) || z < f3d_min(z0, z1) ||
          z > f3d_max(z0, z1)) {
        continue;
      }
      const uint32_t c = i + j * g.nx;
      g.depth[c] = f3d_max(level - g.ground[c], F3D_R(0.0));
    }
  }
  return 1;
}

/* [volume] over the cells whose centres are within [radius] of (x, z),
 * alike, or into the one cell (x, z) is in when none are; taken out as far
 * as there is water. Returns what went in. */
static f3d_real spread(const Grid *g, f3d_real x, f3d_real z, f3d_real radius,
                       f3d_real volume) {
  const F3dVec3 o = g->slot->origin;
  uint32_t count = 0;
  for (int pass = 0; pass < 2; pass++) {
    f3d_real given = F3D_R(0.0);
    for (uint32_t j = 0; j < g->nz; j++) {
      const f3d_real cz = o.z + ((f3d_real)j + F3D_R(0.5)) * g->cell - z;
      if (f3d_abs(cz) > radius) continue;
      for (uint32_t i = 0; i < g->nx; i++) {
        const f3d_real cx = o.x + ((f3d_real)i + F3D_R(0.5)) * g->cell - x;
        if (cx * cx + cz * cz > radius * radius) continue;
        if (pass == 0) {
          count++;
          continue;
        }
        const uint32_t c = i + j * g->nx;
        const f3d_real want = volume / (f3d_real)count / g->area;
        const f3d_real next = f3d_max(g->depth[c] + want, F3D_R(0.0));
        given += (next - g->depth[c]) * g->area;
        g->depth[c] = next;
      }
    }
    if (pass == 1) return given;
    if (count == 0) {
      const int32_t c = cell_at(g, x, z);
      if (c < 0) return F3D_R(0.0);
      const f3d_real next = f3d_max(g->depth[c] + volume / g->area, F3D_R(0.0));
      const f3d_real gave = (next - g->depth[c]) * g->area;
      g->depth[c] = next;
      return gave;
    }
  }
  return F3D_R(0.0);
}

int f3d_water_pour(F3dWorld *world, F3dWater water, f3d_real x, f3d_real z,
                   f3d_real radius, f3d_real volume) {
  F3dWaterSlot *w = water_of(world, water);
  if (w == NULL || !(f3d_finite(x) && f3d_finite(z) && f3d_finite(radius) &&
                     radius >= F3D_R(0.0) && f3d_finite(volume))) {
    return 0;
  }
  Grid g = grid_of(world, w);
  spread(&g, x, z, radius, volume);
  return 1;
}

int f3d_water_set_source(F3dWorld *world, F3dWater water, uint32_t index,
                         f3d_real x, f3d_real z, f3d_real radius,
                         f3d_real rate) {
  F3dWaterSlot *w = water_of(world, water);
  if (w == NULL || index >= F3D_WATER_MOST_SOURCES) return 0;
  if (!(f3d_finite(x) && f3d_finite(z) && f3d_finite(radius) &&
        radius >= F3D_R(0.0) && f3d_finite(rate) && rate >= F3D_R(0.0))) {
    return 0;
  }
  F3dWaterSource *s = &w->sources[index];
  s->x = x;
  s->z = z;
  s->radius = radius;
  s->rate = rate;
  if (index >= w->source_count) w->source_count = index + 1u;
  return 1;
}

int f3d_water_set_bed(F3dWorld *world, F3dWater water, f3d_real roughness,
                      int open_edges) {
  F3dWaterSlot *w = water_of(world, water);
  if (w == NULL || !(f3d_finite(roughness) && roughness >= F3D_R(0.0))) return 0;
  w->roughness = roughness;
  w->open_edges = open_edges ? 1u : 0u;
  return 1;
}

int f3d_water_sample(const F3dWorld *world, F3dWater water, f3d_real x,
                     f3d_real z, f3d_real *out) {
  F3dWaterSlot *w = water_of(world, water);
  if (w == NULL || out == NULL) return 0;
  const Grid g = grid_of(world, w);
  const int32_t c = cell_at(&g, x, z);
  if (c < 0) return 0;
  const f3d_real fx = (x - w->origin.x) / g.cell;
  const f3d_real fz = (z - w->origin.z) / g.cell;
  out[0] = surface(&g, (uint32_t)c);
  out[1] = g.depth[c];
  out[2] = flow_x(&g, fx, fz);
  out[3] = flow_z(&g, fx, fz);
  return 1;
}

int f3d_water_read(const F3dWorld *world, F3dWater water, f3d_real *heights,
                   f3d_real *depths) {
  F3dWaterSlot *w = water_of(world, water);
  if (w == NULL) return 0;
  const Grid g = grid_of(world, w);
  for (uint32_t c = 0; c < g.n; c++) {
    if (heights != NULL) heights[c] = surface(&g, c);
    if (depths != NULL) depths[c] = g.depth[c];
  }
  return 1;
}

int f3d_water_read_flow(const F3dWorld *world, F3dWater water,
                        f3d_real *velocity) {
  F3dWaterSlot *w = water_of(world, water);
  if (w == NULL || velocity == NULL) return 0;
  const Grid g = grid_of(world, w);
  for (uint32_t j = 0; j < g.nz; j++) {
    for (uint32_t i = 0; i < g.nx; i++) {
      const uint32_t c = i + j * g.nx;
      velocity[2u * c] = F3D_R(0.5) * (g.u[i + j * (g.nx + 1u)] +
                                       g.u[i + 1u + j * (g.nx + 1u)]);
      velocity[2u * c + 1u] =
          F3D_R(0.5) * (g.w[i + j * g.nx] + g.w[i + (j + 1u) * g.nx]);
    }
  }
  return 1;
}

int f3d_water_volume(const F3dWorld *world, F3dWater water, f3d_real *held,
                     f3d_real *lost) {
  F3dWaterSlot *w = water_of(world, water);
  if (w == NULL) return 0;
  const Grid g = grid_of(world, w);
  f3d_real v = F3D_R(0.0);
  for (uint32_t c = 0; c < g.n; c++) v += g.depth[c] * g.area;
  for (uint32_t k = 0; k < world->s.spray_count; k++) {
    if (world->spray[k].water == water) v += world->spray[k].volume;
  }
  if (held != NULL) *held = v;
  if (lost != NULL) *lost = w->lost;
  return 1;
}

uint32_t f3d_world_read_spray(const F3dWorld *world, f3d_real *spray,
                              F3dWater *waters, uint32_t capacity) {
  uint32_t written = 0;
  for (uint32_t k = 0; k < world->s.spray_count && written < capacity; k++) {
    const F3dSpray *d = &world->spray[k];
    if (spray != NULL) {
      f3d_real *o = spray + (size_t)written * F3D_SPRAY_FLOATS;
      o[0] = d->at.x;
      o[1] = d->at.y;
      o[2] = d->at.z;
      o[3] = d->velocity.x;
      o[4] = d->velocity.y;
      o[5] = d->velocity.z;
      o[6] = d->volume;
    }
    if (waters != NULL) waters[written] = d->water;
    written++;
  }
  return written;
}

/* ------------------------------------------------------------- the step */

/* A drop of spray off [water] at [at] with [velocity] and [volume]; when
 * the world has no room for another, its water goes into cell [fallback]
 * at once. */
static void throw_spray(F3dWorld *world, Grid *g, F3dWater water, F3dVec3 at,
                        F3dVec3 velocity, f3d_real volume, uint32_t fallback) {
  if (world->s.spray_count < F3D_WATER_MOST_SPRAY) {
    if (world->spray == NULL) {
      world->spray = (F3dSpray *)f3d_alloc(F3D_WATER_MOST_SPRAY * sizeof(F3dSpray));
    }
    if (world->spray != NULL) {
      F3dSpray *d = &world->spray[world->s.spray_count++];
      f3d_zero(d, sizeof *d);
      d->at = at;
      d->velocity = velocity;
      d->volume = volume;
      d->water = water;
      return;
    }
  }
  g->depth[fallback] += volume / g->area;
}

/* [volume] of a body standing in column [c]. What it fills now that it did
 * not, it pushes aside: that much water leaves the column, into [pushed]
 * for the ring round it, so the surface over it stays where it was and a
 * bulge runs out from it. When it fills less, the surface over it sinks
 * and the water flows back in by itself. */
static void stand(Grid *g, f3d_real *was, uint32_t c, f3d_real volume,
                  f3d_real *pushed) {
  g->filled[c] += volume;
  const f3d_real more = volume - was[c];
  was[c] = f3d_max(was[c] - volume, F3D_R(0.0));
  if (more > F3D_R(0.0)) {
    const f3d_real take = f3d_min(more, g->depth[c] * g->area);
    g->depth[c] -= take / g->area;
    *pushed += take;
  }
}

/* The volume bodies fill in each column, and what the water does to them:
 * held up by what they displace, dragged by the flow. */
static void bodies_in(F3dWorld *world, Grid *g, f3d_real dt) {
  const F3dWaterSlot *w = g->slot;
  /* Last step's surface, before this step's bodies stand in it. */
  f3d_real *before = (f3d_real *)f3d_alloc((size_t)g->n * 2u * sizeof(f3d_real) + 8u);
  if (before == NULL) return;
  /* And what bodies filled of each column then. */
  f3d_real *was = before + g->n;
  for (uint32_t c = 0; c < g->n; c++) {
    before[c] = surface(g, c);
    was[c] = g->filled[c];
    g->filled[c] = F3D_R(0.0);
  }
  uint32_t *ring_cells = NULL;
  uint32_t ring_room = 0;
  for (uint32_t b = 0; b < world->s.used; b++) {
    F3dSlot *s = &world->slots[b];
    if (!s->live || s->type != F3D_BODY_DYNAMIC || s->shape == F3D_SHAPE_POINT ||
        s->shape == F3D_SHAPE_MESH) {
      continue;
    }
    f3d_real volume;
    if (s->shape == F3D_SHAPE_COMPOUND && s->hull != 0) {
      volume = world->compounds[s->hull - 1u].volume;
    } else {
      volume = f3d_shape_volume(world, s->shape, s->size, s->rounding, s->hull);
    }
    if (!(volume > F3D_R(0.0))) continue;
    const f3d_real r = cube_root(volume * F3D_R(3.0) / (F3D_R(4.0) * F3D_PI));
    /* Where it will be at the end of the step: the water's push measured
     * there, so the push answers the move it is about to make rather than
     * the one it made, and a body bobbing in it loses its swing instead of
     * gaining it. */
    const F3dVec3 p = f3d_sub(f3d_madd(s->position, s->velocity, dt), w->origin);
    const f3d_real lo_x = (p.x - r) / g->cell, hi_x = (p.x + r) / g->cell;
    const f3d_real lo_z = (p.z - r) / g->cell, hi_z = (p.z + r) / g->cell;
    if (hi_x < F3D_R(0.0) || hi_z < F3D_R(0.0) || lo_x > (f3d_real)g->nx ||
        lo_z > (f3d_real)g->nz) {
      continue;
    }
    const uint32_t i0 = (uint32_t)f3d_max(lo_x, F3D_R(0.0));
    const uint32_t j0 = (uint32_t)f3d_max(lo_z, F3D_R(0.0));
    const uint32_t i1 = (uint32_t)f3d_min(hi_x, (f3d_real)(g->nx - 1u));
    const uint32_t j1 = (uint32_t)f3d_min(hi_z, (f3d_real)(g->nz - 1u));
    /* The level round it: the surface of the wet cells in a ring just
     * past its edge, last step. Measured in its own columns, the water
     * would be standing on what the body itself pushed up. */
    const uint32_t ring = (uint32_t)(r / g->cell) + 2u;
    const int32_t ci = (int32_t)(p.x / g->cell), cj = (int32_t)(p.z / g->cell);
    const uint32_t side = 2u * ring + 1u;
    if (side * side > ring_room) {
      uint32_t *more = (uint32_t *)f3d_realloc(ring_cells, (size_t)side * side * sizeof(uint32_t));
      if (more == NULL) break;
      ring_cells = more;
      ring_room = side * side;
    }
    f3d_real level = F3D_R(0.0);
    uint32_t wet = 0;
    for (int32_t j = cj - (int32_t)ring; j <= cj + (int32_t)ring; j++) {
      for (int32_t i = ci - (int32_t)ring; i <= ci + (int32_t)ring; i++) {
        if (i < 0 || j < 0 || i >= (int32_t)g->nx || j >= (int32_t)g->nz) continue;
        const f3d_real cx = ((f3d_real)i + F3D_R(0.5)) * g->cell - p.x;
        const f3d_real cz = ((f3d_real)j + F3D_R(0.5)) * g->cell - p.z;
        const f3d_real d = f3d_sqrt(cx * cx + cz * cz);
        if (d < r || d > r + F3D_R(1.5) * g->cell) continue;
        const uint32_t c = (uint32_t)i + (uint32_t)j * g->nx;
        if (!(g->depth[c] > F3D_WATER_DRY)) continue;
        level += before[c];
        ring_cells[wet++] = c;
      }
    }
    if (wet == 0) continue;
    level /= (f3d_real)wet;
    f3d_real pushed = F3D_R(0.0);
    /* What is under water: the ball's cap below the level round it,
     * exactly, whatever the grid; and the middle of that cap, where the
     * water holds it up. */
    const f3d_real z = f3d_clamp(level - p.y, -r, r);
    const f3d_real cap = r + z;
    const f3d_real displaced = F3D_PI * cap * cap * (F3D_R(3.0) * r - cap) / F3D_R(3.0);
    if (!(displaced > F3D_R(0.0))) continue;
    const f3d_real below = F3D_R(3.0) * (F3D_R(2.0) * r - cap) * (F3D_R(2.0) * r - cap) /
                           (F3D_R(4.0) * (F3D_R(3.0) * r - cap));
    const F3dVec3 middle = f3d_v3(s->position.x, w->origin.y + p.y - below,
                                  s->position.z);
    /* Where it stands in the water, for the waves: shared over its columns
     * as long as its chord is in each, all in the one it is over when it
     * is smaller than a cell. */
    f3d_real weight = F3D_R(0.0);
    for (int pass = 0; pass < 2; pass++) {
      for (uint32_t j = j0; j <= j1; j++) {
        for (uint32_t i = i0; i <= i1; i++) {
          const f3d_real cx = ((f3d_real)i + F3D_R(0.5)) * g->cell - p.x;
          const f3d_real cz = ((f3d_real)j + F3D_R(0.5)) * g->cell - p.z;
          const f3d_real rho2 = cx * cx + cz * cz;
          if (rho2 >= r * r) continue;
          const f3d_real chord = f3d_sqrt(r * r - rho2);
          if (pass == 0) {
            weight += chord;
            continue;
          }
          stand(g, was, i + j * g->nx, displaced * chord / weight, &pushed);
        }
      }
      if (pass == 0 && !(weight > F3D_R(0.0))) {
        if (ci >= 0 && cj >= 0 && ci < (int32_t)g->nx && cj < (int32_t)g->nz) {
          stand(g, was, (uint32_t)ci + (uint32_t)cj * g->nx, displaced, &pushed);
        }
        break;
      }
    }
    for (uint32_t k = 0; k < wet; k++) {
      g->depth[ring_cells[k]] += pushed / ((f3d_real)wet * g->area);
    }
    /* Held up: the weight of the water it displaces, against gravity. */
    F3dVec3 force = f3d_scale(world->s.gravity,
                              -F3D_WATER_DENSITY * displaced);
    /* Dragged: by the flow against how it moves through it, over the part
     * of it under water, no more than stops it against the flow in a
     * step. */
    const f3d_real fx = (middle.x - w->origin.x) / g->cell;
    const f3d_real fz = (middle.z - w->origin.z) / g->cell;
    const F3dVec3 flow = f3d_v3(flow_x(g, fx, fz), F3D_R(0.0), flow_z(g, fx, fz));
    const F3dVec3 rel = f3d_sub(s->velocity, flow);
    const f3d_real speed = f3d_sqrt(f3d_dot(rel, rel));
    if (speed > F3D_R(0.0)) {
      const f3d_real under = f3d_min(displaced / volume, F3D_R(1.0));
      f3d_real drag = F3D_R(0.5) * F3D_WATER_DENSITY * F3D_BODY_IN_WATER *
                      F3D_PI * r * r * under * speed * speed;
      if (s->inverse_mass > F3D_R(0.0)) {
        drag = f3d_min(drag, speed / (s->inverse_mass * dt));
      }
      force = f3d_madd(force, rel, -drag / speed);
    }
    s->force = f3d_add(s->force, force);
    s->torque = f3d_add(s->torque, f3d_cross(f3d_sub(middle, s->position), force));
    if (s->flags & F3D_FLAG_ASLEEP) f3d_wake(world, s);
  }
  f3d_free(ring_cells);
  f3d_free(before);
}

/* One substep of [h] seconds. */
static void substep(F3dWorld *world, Grid *g, F3dWater water, f3d_real h,
                    f3d_real *u_old, f3d_real *w_old, f3d_real *out) {
  F3dWaterSlot *ws = g->slot;
  const uint32_t nx = g->nx, nz = g->nz, ux = nx + 1u;
  const f3d_real gravity = f3d_sqrt(f3d_dot(world->s.gravity, world->s.gravity));
  /* 1. The springs. */
  for (uint32_t k = 0; k < ws->source_count; k++) {
    const F3dWaterSource *s = &ws->sources[k];
    if (s->rate > F3D_R(0.0)) spread(g, s->x, s->z, s->radius, s->rate * h);
  }
  /* 2. The velocities carried along themselves. */
  f3d_copy(u_old, g->u, (size_t)ux * nz * sizeof(f3d_real));
  f3d_copy(w_old, g->w, (size_t)nx * (nz + 1u) * sizeof(f3d_real));
  Grid old = *g;
  old.u = u_old;
  old.w = w_old;
  const f3d_real step_cells = h / g->cell;
  for (uint32_t j = 0; j < nz; j++) {
    for (uint32_t i = 1; i < nx; i++) {
      const f3d_real x = (f3d_real)i, z = (f3d_real)j + F3D_R(0.5);
      const f3d_real vx = u_old[i + j * ux], vz = flow_z(&old, x, z);
      g->u[i + j * ux] = flow_x(&old, x - vx * step_cells, z - vz * step_cells);
    }
  }
  for (uint32_t j = 1; j < nz; j++) {
    for (uint32_t i = 0; i < nx; i++) {
      const f3d_real x = (f3d_real)i + F3D_R(0.5), z = (f3d_real)j;
      const f3d_real vx = flow_x(&old, x, z), vz = w_old[i + j * nx];
      g->w[i + j * nx] = flow_z(&old, x - vx * step_cells, z - vz * step_cells);
    }
  }
  /* 3. The slope, the bed and the wind, face by face. */
  const f3d_real most = F3D_R(0.5) * g->cell / h;
  const f3d_real n2 = ws->roughness * ws->roughness;
  for (int axis = 0; axis < 2; axis++) {
    const uint32_t fx_count = axis == 0 ? ux : nx;
    const uint32_t fz_count = axis == 0 ? nz : nz + 1u;
    f3d_real *v = axis == 0 ? g->u : g->w;
    for (uint32_t j = 0; j < fz_count; j++) {
      for (uint32_t i = 0; i < fx_count; i++) {
        const uint32_t f = i + j * fx_count;
        const int edge = axis == 0 ? (i == 0 || i == nx) : (j == 0 || j == nz);
        if (edge) {
          if (!ws->open_edges) {
            v[f] = F3D_R(0.0);
            continue;
          }
          /* An open edge lets out what reaches it, and nothing in. */
          const uint32_t c = axis == 0 ? (i == 0 ? j * nx : nx - 1u + j * nx)
                                       : (j == 0 ? i : i + (nz - 1u) * nx);
          const int outwards_positive = axis == 0 ? i == nx : j == nz;
          f3d_real inner = axis == 0
                               ? g->u[(i == 0 ? 1u : nx - 1u) + j * ux]
                               : g->w[i + (j == 0 ? 1u : nz - 1u) * nx];
          if (nx == 1u && axis == 0) inner = F3D_R(0.0);
          if (nz == 1u && axis == 1) inner = F3D_R(0.0);
          v[f] = g->depth[c] > F3D_WATER_DRY
                     ? (outwards_positive ? f3d_max(inner, F3D_R(0.0))
                                          : f3d_min(inner, F3D_R(0.0)))
                     : F3D_R(0.0);
          continue;
        }
        const uint32_t a = axis == 0 ? (i - 1u) + j * nx : i + (j - 1u) * nx;
        const uint32_t b = axis == 0 ? i + j * nx : i + j * nx;
        const f3d_real da = g->depth[a], db = g->depth[b];
        if (!(da > F3D_WATER_DRY) && !(db > F3D_WATER_DRY)) {
          v[f] = F3D_R(0.0);
          continue;
        }
        const f3d_real ea = surface(g, a), eb = surface(g, b);
        f3d_real vel = v[f] - gravity * h * (eb - ea) / g->cell;
        /* Nothing to carry from a dry side, and no climbing onto dry
         * ground above the surface. */
        if (vel > F3D_R(0.0) && (!(da > F3D_WATER_DRY) || ea < g->ground[b])) {
          vel = F3D_R(0.0);
        }
        if (vel < F3D_R(0.0) && (!(db > F3D_WATER_DRY) || eb < g->ground[a])) {
          vel = F3D_R(0.0);
        }
        /* The wind's stress over the depth. */
        const f3d_real depth = F3D_R(0.5) * (da + db);
        if (depth > F3D_WATER_DRY) {
          const f3d_real x = axis == 0 ? (f3d_real)i : (f3d_real)i + F3D_R(0.5);
          const f3d_real z = axis == 0 ? (f3d_real)j + F3D_R(0.5) : (f3d_real)j;
          f3d_real wind[3];
          f3d_world_sample_wind(world, ws->origin.x + x * g->cell,
                                ws->origin.y + F3D_R(0.5) * (ea + eb),
                                ws->origin.z + z * g->cell, wind);
          const f3d_real along = axis == 0 ? wind[0] : wind[2];
          const f3d_real across = axis == 0 ? wind[2] : wind[0];
          const f3d_real speed = f3d_sqrt(along * along + across * across);
          vel += h * world->s.air_density * F3D_WIND_ON_WATER * speed * along /
                 (F3D_WATER_DENSITY * depth);
          /* Manning's friction, implicit. */
          const f3d_real h43 = depth * cube_root(depth);
          vel /= F3D_R(1.0) + h * gravity * n2 * f3d_abs(vel) / h43;
        }
        v[f] = f3d_clamp(vel, -most, most);
      }
    }
  }
  /* 4. The water across the faces, no column giving more than it holds. */
  for (uint32_t c = 0; c < g->n; c++) out[c] = F3D_R(0.0);
  for (int axis = 0; axis < 2; axis++) {
    const uint32_t fx_count = axis == 0 ? ux : nx;
    const uint32_t fz_count = axis == 0 ? nz : nz + 1u;
    const f3d_real *v = axis == 0 ? g->u : g->w;
    for (uint32_t j = 0; j < fz_count; j++) {
      for (uint32_t i = 0; i < fx_count; i++) {
        const f3d_real vel = v[i + j * fx_count];
        if (vel == F3D_R(0.0)) continue;
        const int forward = vel > F3D_R(0.0);
        /* The column it comes from. */
        int32_t from;
        if (axis == 0) {
          from = forward ? (i == 0 ? -1 : (int32_t)(i - 1u + j * nx))
                         : (i == nx ? -1 : (int32_t)(i + j * nx));
        } else {
          from = forward ? (j == 0 ? -1 : (int32_t)(i + (j - 1u) * nx))
                         : (j == nz ? -1 : (int32_t)(i + j * nx));
        }
        if (from < 0) continue;
        out[from] += f3d_abs(vel) * g->depth[from] * g->cell * h;
      }
    }
  }
  /* Each column's share it can give. */
  for (uint32_t c = 0; c < g->n; c++) {
    const f3d_real has = g->depth[c] * g->area;
    out[c] = out[c] > has && out[c] > F3D_R(0.0) ? has / out[c] : F3D_R(1.0);
  }
  f3d_real *next = u_old; /* the depths after, reusing the room */
  f3d_copy(next, g->depth, (size_t)g->n * sizeof(f3d_real));
  for (int axis = 0; axis < 2; axis++) {
    const uint32_t fx_count = axis == 0 ? ux : nx;
    const uint32_t fz_count = axis == 0 ? nz : nz + 1u;
    f3d_real *v = axis == 0 ? g->u : g->w;
    for (uint32_t j = 0; j < fz_count; j++) {
      for (uint32_t i = 0; i < fx_count; i++) {
        const uint32_t f = i + j * fx_count;
        if (v[f] == F3D_R(0.0)) continue;
        const int forward = v[f] > F3D_R(0.0);
        int32_t from, to;
        if (axis == 0) {
          const int32_t left = i == 0 ? -1 : (int32_t)(i - 1u + j * nx);
          const int32_t right = i == nx ? -1 : (int32_t)(i + j * nx);
          from = forward ? left : right;
          to = forward ? right : left;
        } else {
          const int32_t below = j == 0 ? -1 : (int32_t)(i + (j - 1u) * nx);
          const int32_t above = j == nz ? -1 : (int32_t)(i + j * nx);
          from = forward ? below : above;
          to = forward ? above : below;
        }
        if (from < 0) continue;
        const f3d_real share = out[from];
        v[f] *= share;
        const f3d_real moved = f3d_abs(v[f]) * g->depth[from] * g->cell * h;
        if (!(moved > F3D_R(0.0))) continue;
        next[from] -= moved / g->area;
        if (to < 0) {
          ws->lost += moved;
          continue;
        }
        /* Off ground that drops away steeper than it is wide, onto a
         * surface below it by more than that: spray. Waves on level ground
         * are not a waterfall, however steep. */
        const f3d_real fall = g->ground[from] + g->depth[from] - surface(g, (uint32_t)to);
        if (g->ground[from] - g->ground[(uint32_t)to] > g->cell && fall > g->cell) {
          const f3d_real fx = axis == 0 ? (f3d_real)i : (f3d_real)i + F3D_R(0.5);
          const f3d_real fz = axis == 0 ? (f3d_real)j + F3D_R(0.5) : (f3d_real)j;
          const F3dVec3 at = f3d_add(
              ws->origin,
              f3d_v3(fx * g->cell,
                     g->ground[from] + F3D_R(0.5) * g->depth[from], fz * g->cell));
          const F3dVec3 vel = axis == 0 ? f3d_v3(v[f], F3D_R(0.0), F3D_R(0.0))
                                        : f3d_v3(F3D_R(0.0), F3D_R(0.0), v[f]);
          throw_spray(world, g, water, at, vel, moved, (uint32_t)to);
          continue;
        }
        next[to] += moved / g->area;
      }
    }
  }
  for (uint32_t c = 0; c < g->n; c++) g->depth[c] = f3d_max(next[c], F3D_R(0.0));
}

/* The spray of the world in flight for [dt]: falling, and landing in the
 * water or on the ground below it, in pieces no longer than half a cell so
 * it does not pass through a thin sheet of water. */
static void fly_spray(F3dWorld *world, f3d_real dt) {
  uint32_t kept = 0;
  for (uint32_t k = 0; k < world->s.spray_count; k++) {
    F3dSpray d = world->spray[k];
    F3dWaterSlot *ws = water_of(world, d.water);
    if (ws == NULL) continue;
    Grid g = grid_of(world, ws);
    f3d_real left = dt;
    int landed = 0;
    while (left > F3D_R(0.0) && !landed) {
      const f3d_real speed = f3d_sqrt(f3d_dot(d.velocity, d.velocity)) + F3D_R(1e-6);
      const f3d_real piece = f3d_min(left, F3D_R(0.5) * g.cell / speed);
      d.velocity = f3d_madd(d.velocity, world->s.gravity, piece);
      d.at = f3d_madd(d.at, d.velocity, piece);
      left -= piece;
      const int32_t c = cell_at(&g, d.at.x, d.at.z);
      if (c < 0) {
        /* Off the grid: gone from this water. */
        ws->lost += d.volume;
        landed = 1;
        break;
      }
      if (d.at.y - ws->origin.y <= surface(&g, (uint32_t)c)) {
        /* In: its water and its push, sideways, into the column. */
        const f3d_real held = g.depth[c] * g.area;
        g.depth[c] += d.volume / g.area;
        const f3d_real share = d.volume / (held + d.volume);
        const uint32_t i = (uint32_t)c % g.nx, j = (uint32_t)c / g.nx;
        const uint32_t ux = g.nx + 1u;
        g.u[i + j * ux] += (d.velocity.x - g.u[i + j * ux]) * share;
        g.u[i + 1u + j * ux] += (d.velocity.x - g.u[i + 1u + j * ux]) * share;
        g.w[i + j * g.nx] += (d.velocity.z - g.w[i + j * g.nx]) * share;
        g.w[i + (j + 1u) * g.nx] += (d.velocity.z - g.w[i + (j + 1u) * g.nx]) * share;
        landed = 1;
      }
    }
    if (!landed) world->spray[kept++] = d;
  }
  world->s.spray_count = kept;
}

void f3d_step_water(F3dWorld *world, f3d_real dt) {
  if (world->s.water_count == 0) return;
  const f3d_real gravity = f3d_sqrt(f3d_dot(world->s.gravity, world->s.gravity));
  for (uint32_t k = 0; k < world->s.water_count; k++) {
    F3dWaterSlot *ws = &world->waters[k];
    if (!ws->live) continue;
    Grid g = grid_of(world, ws);
    bodies_in(world, &g, dt);
    /* As many substeps as keep a wave or the flow within a quarter of a
     * cell each. */
    f3d_real fastest = F3D_R(0.0), deepest = F3D_R(0.0);
    for (uint32_t f = 0; f < (g.nx + 1u) * g.nz; f++) fastest = f3d_max(fastest, f3d_abs(g.u[f]));
    for (uint32_t f = 0; f < g.nx * (g.nz + 1u); f++) fastest = f3d_max(fastest, f3d_abs(g.w[f]));
    for (uint32_t c = 0; c < g.n; c++) deepest = f3d_max(deepest, g.depth[c] + g.filled[c] / g.area);
    const f3d_real wave = fastest + f3d_sqrt(gravity * deepest);
    uint32_t count = 1;
    if (wave > F3D_R(0.0)) {
      const f3d_real longest = F3D_R(0.25) * g.cell / wave;
      while ((f3d_real)count * longest < dt && count < F3D_WATER_MOST_SUBSTEPS) count++;
    }
    const size_t faces = (size_t)(g.nx + 1u) * g.nz + (size_t)g.nx * (g.nz + 1u);
    f3d_real *room = (f3d_real *)f3d_alloc((faces + 2u * (size_t)g.n) * sizeof(f3d_real) + 16u);
    if (room == NULL) continue;
    f3d_real *u_old = room;
    f3d_real *w_old = room + (size_t)(g.nx + 1u) * g.nz + g.n;
    f3d_real *out = w_old + (size_t)g.nx * (g.nz + 1u);
    /* u_old doubles as the depths' room: it is as long as the larger. */
    const f3d_real h = dt / (f3d_real)count;
    for (uint32_t s = 0; s < count; s++) substep(world, &g, k + 1u, h, u_old, w_old, out);
    f3d_free(room);
  }
  fly_spray(world, dt);
}
