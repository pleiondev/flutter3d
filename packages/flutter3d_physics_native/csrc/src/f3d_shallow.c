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
 * water, C_d a ball's at its Reynolds number, never more than would stop
 * it against the flow in one step; the water it must move with it to speed
 * up adds half what it displaces to its inertia; and the flow is pushed
 * back as hard as it drags, so a body driven through it leaves a wake.
 *
 * What the water is — its density, viscosity and surface tension — is the
 * water's own: honey creeps, lava holds a stone up and lets it sink
 * slowly.
 *
 * Every loop runs in grid order, the spray in the order it was made, so
 * the same world pours the same water everywhere.
 */
#include "f3d_internal.h"

/* What a new water is: water's density, kg/m³. */
#define F3D_WATER_DENSITY F3D_R(1000.0)
/* How thin water is still water, m: below it a column is dry. */
#define F3D_SHALLOW_DRY F3D_R(1e-4)
/* Wind's drag on water (Large and Pond's open-sea value). */
#define F3D_WIND_ON_WATER F3D_R(1.3e-3)
/* And its surface tension, N/m, and viscosity, Pa·s, at room
 * temperature. */
#define F3D_WATER_TENSION F3D_R(0.072)
#define F3D_WATER_VISCOSITY F3D_R(1.0e-3)
/* How many e-foldings of growth part a sheet (Grant and Middleman). */
#define F3D_BREAKUP_GROWTH F3D_R(12.0)
/* The bubbles a plunging sheet drags down are a few millimetres across
 * (Chanson), and rise at the terminal speed bubbles of that size share,
 * about 0.23 m/s whatever their size between one and ten millimetres
 * (Clift, Grace and Weber). */
#define F3D_BUBBLE_RADIUS F3D_R(0.002)
#define F3D_BUBBLE_RISE F3D_R(0.23)
/* A crown's drops: about a centimetre across. */
#define F3D_CROWN_DROP F3D_R(0.01)

/* The most substeps a step is cut into; past them the flow is held to
 * what the last allows. */
#define F3D_SHALLOW_MOST_SUBSTEPS 32u

/* Water whose fastest flow stays under this, m/s, for this long, s, with
 * nothing in it, nothing feeding or draining it, no wind on it and nothing
 * going over a lip, rests: a millimetre a second is far below any ripple
 * anyone draws, and a pond left alone costs nothing until something
 * stirs it. */
#define F3D_SHALLOW_CALM F3D_R(1e-3)
#define F3D_SHALLOW_SETTLES F3D_R(1.0)

/* ------------------------------------------------------------- the grid */

typedef struct Grid {
  F3dShallowSlot *slot;
  uint32_t nx, nz, n;
  f3d_real cell, area;
  f3d_real *ground, *depth, *u, *w, *filled;
} Grid;

static uint32_t reals_of(uint32_t nx, uint32_t nz) {
  return 3u * nx * nz + (nx + 1u) * nz + nx * (nz + 1u);
}

static F3dShallowSlot *water_of(const F3dWorld *world, F3dShallow water) {
  if (water == 0 || water > world->s.shallow_count) return NULL;
  F3dShallowSlot *w = &world->shallows[water - 1u];
  return w->live ? w : NULL;
}

/* Water changed from outside: stepped again from the next step on. */
static void wake(F3dShallowSlot *w) {
  w->calm = F3D_R(0.0);
  w->resting = 0u;
}

static Grid grid_of(const F3dWorld *world, F3dShallowSlot *w) {
  Grid g;
  g.slot = w;
  g.nx = w->nx;
  g.nz = w->nz;
  g.n = w->nx * w->nz;
  g.cell = w->cell;
  g.area = w->cell * w->cell;
  g.ground = world->shallow_data + w->first;
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

/* x^(1/3) for x ≥ 0, by Newton's method: the same bits everywhere. x is
 * first brought into [1, 8) by eighths, which is exact, and halves its root
 * as often; a straight line through the ends of that range starts Newton
 * within a fifth of the root. Past its first step Newton comes down on the
 * root from above, so it stops when a step no longer goes down. It is
 * asked once a face a substep, so its cost is the water's. */
static f3d_real cube_root(f3d_real x) {
  if (!(x > F3D_R(0.0))) return F3D_R(0.0);
  f3d_real scale = F3D_R(1.0);
  while (x >= F3D_R(8.0)) {
    x *= F3D_R(0.125);
    scale *= F3D_R(2.0);
  }
  while (x < F3D_R(1.0)) {
    x *= F3D_R(8.0);
    scale *= F3D_R(0.5);
  }
  f3d_real y = F3D_R(1.0) + (x - F3D_R(1.0)) / F3D_R(7.0);
  for (int i = 0; i < 40; i++) {
    const f3d_real next = y - (y * y * y - x) / (F3D_R(3.0) * y * y);
    if (i > 0 && !(next < y)) break;
    y = next;
  }
  return y * scale;
}

/* The natural logarithm of x > 0: x brought into [1, 2) by halving or
 * doubling, which is exact, and ln m = 2·atanh((m − 1)/(m + 1)) by its
 * series. The same bits everywhere, as the core's other functions are. */
static f3d_real natural_log(f3d_real x) {
  if (!(x > F3D_R(0.0))) return F3D_R(0.0);
  int k = 0;
  while (x >= F3D_R(2.0)) {
    x *= F3D_R(0.5);
    k++;
  }
  while (x < F3D_R(1.0)) {
    x *= F3D_R(2.0);
    k--;
  }
  const f3d_real t = (x - F3D_R(1.0)) / (x + F3D_R(1.0));
  const f3d_real t2 = t * t;
  f3d_real term = t, sum = F3D_R(0.0);
  for (int n = 1; n < 30; n += 2) {
    sum += term / (f3d_real)n;
    term *= t2;
  }
  return F3D_R(2.0) * sum + (f3d_real)k * F3D_R(0.69314718055994531);
}

/* e^y: y less a whole number of ln 2, the rest by its series, then doubled
 * or halved back, exactly. */
static f3d_real natural_exp(f3d_real y) {
  const f3d_real ln2 = F3D_R(0.69314718055994531);
  int k = 0;
  while (y >= ln2) {
    y -= ln2;
    k++;
  }
  while (y < F3D_R(0.0)) {
    y += ln2;
    k--;
  }
  f3d_real term = F3D_R(1.0), sum = F3D_R(1.0);
  for (int n = 1; n < 20; n++) {
    term *= y / (f3d_real)n;
    sum += term;
  }
  for (; k > 0; k--) sum *= F3D_R(2.0);
  for (; k < 0; k++) sum *= F3D_R(0.5);
  return sum;
}

/* x^a for x > 0. */
static f3d_real power(f3d_real x, f3d_real a) {
  if (!(x > F3D_R(0.0))) return F3D_R(0.0);
  return natural_exp(a * natural_log(x));
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

F3dShallow f3d_shallow_create(F3dWorld *world, uint32_t nx, uint32_t nz,
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
      world->shallow_data,
      ((size_t)world->s.shallow_reals + size) * sizeof(f3d_real));
  if (data == NULL) return 0;
  world->shallow_data = data;
  F3dShallowSlot *all = (F3dShallowSlot *)f3d_realloc(
      world->shallows, ((size_t)world->s.shallow_count + 1u) * sizeof(F3dShallowSlot));
  if (all == NULL) return 0;
  world->shallows = all;
  F3dShallowSlot *w = &all[world->s.shallow_count];
  f3d_zero(w, sizeof *w);
  w->live = 1;
  w->nx = nx;
  w->nz = nz;
  w->first = world->s.shallow_reals;
  w->cell = cell;
  w->origin = f3d_v3(ox, oy, oz);
  w->roughness = F3D_R(0.03);
  w->density = F3D_WATER_DENSITY;
  w->viscosity = F3D_WATER_VISCOSITY;
  w->tension = F3D_WATER_TENSION;
  f3d_real *mine = data + w->first;
  f3d_zero(mine, (size_t)size * sizeof(f3d_real));
  f3d_copy(mine, ground, (size_t)nx * nz * sizeof(f3d_real));
  world->s.shallow_reals += size;
  world->s.shallow_count++;
  return world->s.shallow_count;
}

int f3d_shallow_destroy(F3dWorld *world, F3dShallow water) {
  F3dShallowSlot *w = water_of(world, water);
  if (w == NULL) return 0;
  /* Its reals closed up: every later water's move down by its share. */
  const uint32_t size = reals_of(w->nx, w->nz);
  const uint32_t from = w->first + size;
  for (uint32_t k = from; k < world->s.shallow_reals; k++) {
    world->shallow_data[k - size] = world->shallow_data[k];
  }
  world->s.shallow_reals -= size;
  for (uint32_t i = 0; i < world->s.shallow_count; i++) {
    F3dShallowSlot *o = &world->shallows[i];
    if (o->live && o->first > w->first) o->first -= size;
  }
  w->live = 0;
  /* Its spray falls with it. */
  uint32_t kept = 0;
  for (uint32_t k = 0; k < world->s.spray_count; k++) {
    if (world->spray[k].water != water) world->spray[kept++] = world->spray[k];
  }
  world->s.spray_count = kept;
  kept = 0;
  for (uint32_t k = 0; k < world->s.bubble_count; k++) {
    if (world->bubbles[k].water != water) world->bubbles[kept++] = world->bubbles[k];
  }
  world->s.bubble_count = kept;
  return 1;
}

int f3d_shallow_is_valid(const F3dWorld *world, F3dShallow water) {
  return water_of(world, water) != NULL;
}

int f3d_shallow_set_ground(F3dWorld *world, F3dShallow water,
                         const f3d_real *ground) {
  F3dShallowSlot *w = water_of(world, water);
  if (w == NULL || ground == NULL) return 0;
  for (uint32_t c = 0; c < w->nx * w->nz; c++) {
    if (!f3d_finite(ground[c])) return 0;
  }
  Grid g = grid_of(world, w);
  f3d_copy(g.ground, ground, (size_t)g.n * sizeof(f3d_real));
  wake(w);
  return 1;
}

int f3d_shallow_fill(F3dWorld *world, F3dShallow water, f3d_real x0, f3d_real z0,
                   f3d_real x1, f3d_real z1, f3d_real level) {
  F3dShallowSlot *w = water_of(world, water);
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
  wake(w);
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

int f3d_shallow_pour(F3dWorld *world, F3dShallow water, f3d_real x, f3d_real z,
                   f3d_real radius, f3d_real volume) {
  F3dShallowSlot *w = water_of(world, water);
  if (w == NULL || !(f3d_finite(x) && f3d_finite(z) && f3d_finite(radius) &&
                     radius >= F3D_R(0.0) && f3d_finite(volume))) {
    return 0;
  }
  Grid g = grid_of(world, w);
  spread(&g, x, z, radius, volume);
  wake(w);
  return 1;
}

int f3d_shallow_set_source(F3dWorld *world, F3dShallow water, uint32_t index,
                         f3d_real x, f3d_real z, f3d_real radius,
                         f3d_real rate) {
  F3dShallowSlot *w = water_of(world, water);
  if (w == NULL || index >= F3D_SHALLOW_MOST_SOURCES) return 0;
  if (!(f3d_finite(x) && f3d_finite(z) && f3d_finite(radius) &&
        radius >= F3D_R(0.0) && f3d_finite(rate))) {
    return 0;
  }
  F3dShallowSource *s = &w->sources[index];
  s->x = x;
  s->z = z;
  s->radius = radius;
  s->rate = rate;
  if (index >= w->source_count) w->source_count = index + 1u;
  wake(w);
  return 1;
}

int f3d_shallow_set_bed(F3dWorld *world, F3dShallow water, f3d_real roughness,
                      int open_edges) {
  F3dShallowSlot *w = water_of(world, water);
  if (w == NULL || !(f3d_finite(roughness) && roughness >= F3D_R(0.0))) return 0;
  w->roughness = roughness;
  w->open_edges = open_edges ? 1u : 0u;
  wake(w);
  return 1;
}

int f3d_shallow_set_fluid(F3dWorld *world, F3dShallow water, f3d_real density,
                        f3d_real viscosity, f3d_real tension) {
  F3dShallowSlot *w = water_of(world, water);
  if (w == NULL || !(f3d_finite(density) && density > F3D_R(0.0)) ||
      !(f3d_finite(viscosity) && viscosity > F3D_R(0.0)) ||
      !(f3d_finite(tension) && tension > F3D_R(0.0))) {
    return 0;
  }
  w->density = density;
  w->viscosity = viscosity;
  w->tension = tension;
  wake(w);
  return 1;
}

int f3d_shallow_sample(const F3dWorld *world, F3dShallow water, f3d_real x,
                     f3d_real z, f3d_real *out) {
  F3dShallowSlot *w = water_of(world, water);
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

int f3d_shallow_read(const F3dWorld *world, F3dShallow water, f3d_real *heights,
                   f3d_real *depths) {
  F3dShallowSlot *w = water_of(world, water);
  if (w == NULL) return 0;
  const Grid g = grid_of(world, w);
  for (uint32_t c = 0; c < g.n; c++) {
    if (heights != NULL) heights[c] = surface(&g, c);
    if (depths != NULL) depths[c] = g.depth[c];
  }
  return 1;
}

int f3d_shallow_read_flow(const F3dWorld *world, F3dShallow water,
                        f3d_real *velocity) {
  F3dShallowSlot *w = water_of(world, water);
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

int f3d_shallow_volume(const F3dWorld *world, F3dShallow water, f3d_real *held,
                     f3d_real *lost) {
  F3dShallowSlot *w = water_of(world, water);
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
                              F3dShallow *waters, uint32_t capacity) {
  uint32_t written = 0;
  for (uint32_t k = 0; k < world->s.spray_count && written < capacity; k++) {
    const F3dSpray *d = &world->spray[k];
    if (spray != NULL) {
      f3d_real *o = spray + (size_t)written * F3D_SPRAY_FLOATS;
      const f3d_real speed = f3d_sqrt(f3d_dot(d->velocity, d->velocity));
      o[0] = d->at.x;
      o[1] = d->at.y;
      o[2] = d->at.z;
      o[3] = d->velocity.x;
      o[4] = d->velocity.y;
      o[5] = d->velocity.z;
      o[6] = d->volume;
      o[7] = d->width;
      o[8] = d->kind == F3D_SPRAY_SHEET
                 ? (speed > F3D_R(0.0) ? d->flow / (d->width * speed) : F3D_R(0.0))
                 : d->width;
      o[9] = (f3d_real)d->kind;
      o[10] = (f3d_real)d->face;
    }
    if (waters != NULL) waters[written] = d->water;
    written++;
  }
  return written;
}

uint32_t f3d_world_read_bubbles(const F3dWorld *world, f3d_real *bubbles,
                                F3dShallow *waters, uint32_t capacity) {
  uint32_t written = 0;
  for (uint32_t k = 0; k < world->s.bubble_count && written < capacity; k++) {
    const F3dBubbles *b = &world->bubbles[k];
    if (bubbles != NULL) {
      f3d_real *o = bubbles + (size_t)written * F3D_BUBBLE_FLOATS;
      o[0] = b->at.x;
      o[1] = b->at.y;
      o[2] = b->at.z;
      o[3] = b->radius;
      o[4] = b->air;
    }
    if (waters != NULL) waters[written] = b->water;
    written++;
  }
  return written;
}

/* ------------------------------------------------------------- the step */

/* [d] into the world's falling water; 0 when it has no room for more. */
static int add_spray(F3dWorld *world, const F3dSpray *d) {
  if (world->s.spray_count >= F3D_SHALLOW_MOST_SPRAY) return 0;
  if (world->spray == NULL) {
    world->spray = (F3dSpray *)f3d_alloc(F3D_SHALLOW_MOST_SPRAY * sizeof(F3dSpray));
    if (world->spray == NULL) return 0;
  }
  world->spray[world->s.spray_count++] = *d;
  return 1;
}

/* Drops off [water] at [at], [diameter] across, with [velocity] and
 * [volume]; when the world has no room for them their water goes into cell
 * [fallback], where they would have come from. */
static void throw_drops(F3dWorld *world, Grid *g, F3dShallow water, F3dVec3 at,
                        F3dVec3 velocity, f3d_real volume, f3d_real diameter,
                        uint32_t fallback) {
  F3dSpray d;
  f3d_zero(&d, sizeof d);
  d.at = at;
  d.velocity = velocity;
  d.volume = volume;
  d.water = water;
  d.kind = F3D_SPRAY_DROPS;
  d.width = diameter;
  if (!add_spray(world, &d)) g->depth[fallback] += volume / g->area;
}

/* A cloud of [air] m³ of bubbles in [water] at [at]; when the world has no
 * room for more, the air is not shown — it is not water, and nothing is
 * lost that the water holds. */
static void add_bubbles(F3dWorld *world, F3dShallow water, F3dVec3 at,
                        f3d_real air) {
  if (!(air > F3D_R(0.0)) || world->s.bubble_count >= F3D_SHALLOW_MOST_BUBBLES) return;
  if (world->bubbles == NULL) {
    world->bubbles =
        (F3dBubbles *)f3d_alloc(F3D_SHALLOW_MOST_BUBBLES * sizeof(F3dBubbles));
    if (world->bubbles == NULL) return;
  }
  F3dBubbles *b = &world->bubbles[world->s.bubble_count++];
  f3d_zero(b, sizeof *b);
  b->at = at;
  b->radius = F3D_BUBBLE_RADIUS;
  b->air = air;
  b->water = water;
}

/* The flow across column [c], x and z: its faces' mean. */
static F3dVec3 column_flow(const Grid *g, uint32_t c) {
  const uint32_t i = c % g->nx, j = c / g->nx, ux = g->nx + 1u;
  return f3d_v3(F3D_R(0.5) * (g->u[i + j * ux] + g->u[i + 1u + j * ux]),
                F3D_R(0.0),
                F3D_R(0.5) * (g->w[i + j * g->nx] + g->w[i + (j + 1u) * g->nx]));
}

/* Column [c]'s flow moved by [dv], x and z, the whole column alike: half on
 * each of its faces. */
static void push_column(Grid *g, uint32_t c, F3dVec3 dv) {
  const uint32_t i = c % g->nx, j = c / g->nx, ux = g->nx + 1u;
  g->u[i + j * ux] += F3D_R(0.5) * dv.x;
  g->u[i + 1u + j * ux] += F3D_R(0.5) * dv.x;
  g->w[i + j * g->nx] += F3D_R(0.5) * dv.z;
  g->w[i + (j + 1u) * g->nx] += F3D_R(0.5) * dv.z;
}

/* [volume] of a body standing in column [c]. What it fills now that it did
 * not, it pushes aside: that much water leaves the column, into [pushed]
 * for the ring round it, with the flow it had, into [carried], so the
 * surface over it stays where it was, a bulge runs out from it, and no
 * momentum is lost on the way. When it fills less, the surface over it
 * sinks and the water flows back in by itself. */
static void stand(Grid *g, f3d_real *was, uint32_t c, f3d_real volume,
                  f3d_real *pushed, F3dVec3 *carried) {
  g->filled[c] += volume;
  const f3d_real more = volume - was[c];
  was[c] = f3d_max(was[c] - volume, F3D_R(0.0));
  if (more > F3D_R(0.0)) {
    const f3d_real take = f3d_min(more, g->depth[c] * g->area);
    g->depth[c] -= take / g->area;
    *pushed += take;
    *carried = f3d_madd(*carried, column_flow(g, c), take);
  }
}

/* The volume bodies fill in each column, and what the water does to them:
 * held up by what they displace, dragged by the flow. */
static void bodies_in(F3dWorld *world, Grid *g, F3dShallow water, f3d_real dt) {
  const F3dShallowSlot *w = g->slot;
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
        if (!(g->depth[c] > F3D_SHALLOW_DRY)) continue;
        level += before[c];
        ring_cells[wet++] = c;
      }
    }
    if (wet == 0) continue;
    level /= (f3d_real)wet;
    /* And how the surface round it slopes, by least squares over the same
     * ring: a body on a slope of the surface is pushed down it, as the
     * pressure under a wave's flank pushes. Its own bow wave is in that
     * slope, so a body driven through the liquid also feels the waves it
     * makes. */
    f3d_real sxx = F3D_R(0.0), szz = F3D_R(0.0), sxz = F3D_R(0.0);
    f3d_real sxe = F3D_R(0.0), sze = F3D_R(0.0);
    for (uint32_t k = 0; k < wet; k++) {
      const uint32_t c = ring_cells[k];
      const f3d_real cx = ((f3d_real)(c % g->nx) + F3D_R(0.5)) * g->cell - p.x;
      const f3d_real cz = ((f3d_real)(c / g->nx) + F3D_R(0.5)) * g->cell - p.z;
      const f3d_real e = before[c] - level;
      sxx += cx * cx;
      szz += cz * cz;
      sxz += cx * cz;
      sxe += cx * e;
      sze += cz * e;
    }
    const f3d_real det = sxx * szz - sxz * sxz;
    const f3d_real slope_x = det > F3D_R(0.0) ? (sxe * szz - sze * sxz) / det : F3D_R(0.0);
    const f3d_real slope_z = det > F3D_R(0.0) ? (sze * sxx - sxe * sxz) / det : F3D_R(0.0);
    f3d_real pushed = F3D_R(0.0);
    F3dVec3 carried = f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
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
          stand(g, was, i + j * g->nx, displaced * chord / weight, &pushed, &carried);
        }
      }
      if (pass == 0 && !(weight > F3D_R(0.0))) {
        if (ci >= 0 && cj >= 0 && ci < (int32_t)g->nx && cj < (int32_t)g->nz) {
          stand(g, was, (uint32_t)ci + (uint32_t)cj * g->nx, displaced, &pushed,
                &carried);
        }
        break;
      }
    }
    /* Coming in faster than a wave can carry the water away from it,
     * √(g·r), it throws what the waves cannot take up as a crown: the share
     * 1 − c/v of what it pushed aside leaves the ring as spray, outwards and
     * up at forty-five degrees at the speed it came in by beyond the
     * wave's. The rest goes into the ring. */
    const f3d_real gravity = f3d_sqrt(f3d_dot(world->s.gravity, world->s.gravity));
    const f3d_real wave = f3d_sqrt(gravity * r);
    const f3d_real in = gravity > F3D_R(0.0)
                            ? f3d_dot(s->velocity, world->s.gravity) / gravity
                            : F3D_R(0.0);
    f3d_real crown = F3D_R(0.0);
    if (in > wave && pushed > F3D_R(0.0)) crown = pushed * (F3D_R(1.0) - wave / in);
    const f3d_real kept = pushed - crown;
    const F3dVec3 up = gravity > F3D_R(0.0)
                           ? f3d_scale(world->s.gravity, F3D_R(-1.0) / gravity)
                           : f3d_v3(F3D_R(0.0), F3D_R(1.0), F3D_R(0.0));
    const f3d_real out = (in - wave) * F3D_R(0.70710678);
    /* What goes into the ring keeps the flow it had: each ring column's
     * flow becomes the mix of its own and what came in, by volume. */
    const F3dVec3 came = pushed > F3D_R(0.0) ? f3d_scale(carried, F3D_R(1.0) / pushed)
                                             : f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
    for (uint32_t k = 0; k < wet; k++) {
      const uint32_t c = ring_cells[k];
      const f3d_real added = kept / ((f3d_real)wet * g->area);
      const f3d_real share = added / (g->depth[c] + added);
      push_column(g, c, f3d_scale(f3d_sub(came, column_flow(g, c)), share));
      g->depth[c] += added;
      if (!(crown > F3D_R(0.0))) continue;
      const uint32_t i = c % g->nx, j = c / g->nx;
      const F3dVec3 at = f3d_add(w->origin, f3d_v3(((f3d_real)i + F3D_R(0.5)) * g->cell,
                                                    before[c],
                                                    ((f3d_real)j + F3D_R(0.5)) * g->cell));
      F3dVec3 away = f3d_v3(at.x - s->position.x, F3D_R(0.0), at.z - s->position.z);
      const f3d_real len = f3d_sqrt(f3d_dot(away, away));
      away = len > F3D_R(0.0) ? f3d_scale(away, F3D_R(1.0) / len) : away;
      throw_drops(world, g, water, at, f3d_add(f3d_scale(away, out), f3d_scale(up, out)),
                  crown / (f3d_real)wet, F3D_CROWN_DROP, c);
    }
    /* Held up: the weight of the water it displaces, against gravity. */
    F3dVec3 force = f3d_scale(world->s.gravity, -w->density * displaced);
    /* Froude and Krylov's: the surface's slope pushes what it holds up
     * along it, ρgV down the slope. */
    const f3d_real g_mag = f3d_sqrt(f3d_dot(world->s.gravity, world->s.gravity));
    force.x -= w->density * g_mag * displaced * slope_x;
    force.z -= w->density * g_mag * displaced * slope_z;
    /* The water round it moves with it as it speeds up: half the water it
     * displaces, a ball's added mass, on its inertia — in the integrator,
     * where it holds for a body as light as a bubble. */
    s->added_mass += F3D_R(0.5) * w->density * displaced;
    /* Dragged: by the flow against how it moves through it, over the part
     * of it under water, as hard as a ball's drag at its Reynolds number
     * Re = ρ|Δv|D/μ says — Schiller and Naumann's 24/Re·(1 + 0.15·Re^0.687),
     * which is Stokes's 6πμrv when the water is thick or the body small
     * and slow, up to Re = 1000 and Newton's 0.44 past it — and no more
     * than stops it against the flow in a step. */
    const f3d_real fx = (middle.x - w->origin.x) / g->cell;
    const f3d_real fz = (middle.z - w->origin.z) / g->cell;
    const F3dVec3 flow = f3d_v3(flow_x(g, fx, fz), F3D_R(0.0), flow_z(g, fx, fz));
    const F3dVec3 rel = f3d_sub(s->velocity, flow);
    const f3d_real speed = f3d_sqrt(f3d_dot(rel, rel));
    if (speed > F3D_R(0.0)) {
      const f3d_real under = f3d_min(displaced / volume, F3D_R(1.0));
      const f3d_real re = w->density * speed * F3D_R(2.0) * r / w->viscosity;
      const f3d_real cd =
          re < F3D_R(1000.0)
              ? F3D_R(24.0) / re * (F3D_R(1.0) + F3D_R(0.15) * power(re, F3D_R(0.687)))
              : F3D_R(0.44);
      f3d_real drag = F3D_R(0.5) * w->density * cd * F3D_PI * r * r * under *
                      speed * speed;
      if (s->inverse_mass > F3D_R(0.0)) {
        drag = f3d_min(drag, speed * (F3D_R(1.0) / s->inverse_mass + s->added_mass) / dt);
      }
      const F3dVec3 dragged = f3d_scale(rel, -drag / speed);
      force = f3d_add(force, dragged);
      /* And the water is pushed back as hard: the drag's reverse over the
       * step, along the flow, goes into the water round it — the columns
       * it stands in and the ring its displaced water went to — all alike,
       * so a body driven through water sets it moving: a wake behind it,
       * and the water it shoulders aside. */
      f3d_real held = F3D_R(0.0);
      for (int pass = 0; pass < 2; pass++) {
        for (int32_t j = cj - (int32_t)ring; j <= cj + (int32_t)ring; j++) {
          for (int32_t i = ci - (int32_t)ring; i <= ci + (int32_t)ring; i++) {
            if (i < 0 || j < 0 || i >= (int32_t)g->nx || j >= (int32_t)g->nz) continue;
            const f3d_real cx = ((f3d_real)i + F3D_R(0.5)) * g->cell - p.x;
            const f3d_real cz = ((f3d_real)j + F3D_R(0.5)) * g->cell - p.z;
            if (cx * cx + cz * cz > (r + F3D_R(1.5) * g->cell) * (r + F3D_R(1.5) * g->cell)) continue;
            const uint32_t c = (uint32_t)i + (uint32_t)j * g->nx;
            if (!(g->depth[c] > F3D_SHALLOW_DRY)) continue;
            if (pass == 0) {
              held += w->density * g->depth[c] * g->area;
              continue;
            }
            push_column(g, c, f3d_scale(dragged, -dt / held));
          }
        }
        if (!(held > F3D_R(0.0))) break;
      }
    }
    s->force = f3d_add(s->force, force);
    s->torque = f3d_add(s->torque, f3d_cross(f3d_sub(middle, s->position), force));
    if (s->flags & F3D_FLAG_ASLEEP) f3d_wake(world, s);
  }
  f3d_free(ring_cells);
  f3d_free(before);
}

/* One substep of [h] seconds. */
/* What crossed each face onto a drop over a step: its volume, its push and
 * the column it left, the faces x first then z. */
typedef struct Lip {
  f3d_real *volume;
  F3dVec3 *push;
  uint32_t *from;
} Lip;

static void substep(F3dWorld *world, Grid *g, Lip *lip, f3d_real h,
                    f3d_real *u_old, f3d_real *w_old, f3d_real *out) {
  F3dShallowSlot *ws = g->slot;
  const uint32_t nx = g->nx, nz = g->nz, ux = nx + 1u;
  const f3d_real gravity = f3d_sqrt(f3d_dot(world->s.gravity, world->s.gravity));
  /* 1. The springs. */
  for (uint32_t k = 0; k < ws->source_count; k++) {
    const F3dShallowSource *s = &ws->sources[k];
    if (s->rate != F3D_R(0.0)) spread(g, s->x, s->z, s->radius, s->rate * h);
  }
  /* 2. The velocities carried along themselves, conserving momentum
   * (Stelling and Duinmeijer, 2003): what crosses a face is what the depth
   * flux carries, hu with h the upwind column's — the same flux that moves
   * the water in step 4 — taken to each column's middle as the mean of its
   * two faces' and carrying the upwind face's velocity, and a face's
   * velocity changes by the momentum that flows into the two half columns
   * round it less what that inflow's own mass would have carried at its
   * velocity. So no momentum is made or lost in carrying it, and a hydraulic
   * jump stands where it should; the substeps keep each within a quarter of
   * a cell, inside the scheme's reach. */
  f3d_copy(u_old, g->u, (size_t)ux * nz * sizeof(f3d_real));
  f3d_copy(w_old, g->w, (size_t)nx * (nz + 1u) * sizeof(f3d_real));
  {
    const f3d_real *d = g->depth;
    /* The depth flux across x face (i, j) and z face (i, j), m²/s. */
#define QX(i, j) (u_old[(i) + (j) * ux] *                                      \
                  (u_old[(i) + (j) * ux] > F3D_R(0.0)                          \
                       ? ((i) > 0u ? d[(i) - 1u + (j) * nx] : F3D_R(0.0))     \
                       : ((i) < nx ? d[(i) + (j) * nx] : F3D_R(0.0))))
#define QZ(i, j) (w_old[(i) + (j) * nx] *                                      \
                  (w_old[(i) + (j) * nx] > F3D_R(0.0)                          \
                       ? ((j) > 0u ? d[(i) + ((j) - 1u) * nx] : F3D_R(0.0))   \
                       : ((j) < nz ? d[(i) + (j) * nx] : F3D_R(0.0))))
    const f3d_real k = h / g->cell;
    for (uint32_t j = 0; j < nz; j++) {
      for (uint32_t i = 1; i < nx; i++) {
        const uint32_t f = i + j * ux;
        const f3d_real depth = F3D_R(0.5) * (d[i - 1u + j * nx] + d[i + j * nx]);
        if (!(depth > F3D_SHALLOW_DRY)) continue;
        const f3d_real uf = u_old[f];
        /* Along x: the columns either side, their mean flux and the face
         * upwind of their middle. */
        const f3d_real ql = F3D_R(0.5) * (QX(i - 1u, j) + QX(i, j));
        const f3d_real qr = F3D_R(0.5) * (QX(i, j) + QX(i + 1u, j));
        const f3d_real ul = ql > F3D_R(0.0) ? u_old[f - 1u] : uf;
        const f3d_real ur = qr > F3D_R(0.0) ? uf : u_old[f + 1u];
        f3d_real a = qr * ur - ql * ul - uf * (qr - ql);
        /* Across z: the fluxes over the half columns' tops and bottoms. */
        const f3d_real qt = F3D_R(0.5) * (QZ(i - 1u, j + 1u) + QZ(i, j + 1u));
        const f3d_real qb = F3D_R(0.5) * (QZ(i - 1u, j) + QZ(i, j));
        const f3d_real ut = qt > F3D_R(0.0) ? uf : (j + 1u < nz ? u_old[f + ux] : uf);
        const f3d_real ub = qb > F3D_R(0.0) ? (j > 0u ? u_old[f - ux] : uf) : uf;
        a += qt * ut - qb * ub - uf * (qt - qb);
        g->u[f] = uf - k * a / depth;
      }
    }
    for (uint32_t j = 1; j < nz; j++) {
      for (uint32_t i = 0; i < nx; i++) {
        const uint32_t f = i + j * nx;
        const f3d_real depth = F3D_R(0.5) * (d[i + (j - 1u) * nx] + d[i + j * nx]);
        if (!(depth > F3D_SHALLOW_DRY)) continue;
        const f3d_real wf = w_old[f];
        const f3d_real qb = F3D_R(0.5) * (QZ(i, j - 1u) + QZ(i, j));
        const f3d_real qt = F3D_R(0.5) * (QZ(i, j) + QZ(i, j + 1u));
        const f3d_real wb = qb > F3D_R(0.0) ? w_old[f - nx] : wf;
        const f3d_real wt = qt > F3D_R(0.0) ? wf : w_old[f + nx];
        f3d_real a = qt * wt - qb * wb - wf * (qt - qb);
        const f3d_real qr = F3D_R(0.5) * (QX(i + 1u, j - 1u) + QX(i + 1u, j));
        const f3d_real ql = F3D_R(0.5) * (QX(i, j - 1u) + QX(i, j));
        const f3d_real wr = qr > F3D_R(0.0) ? wf : (i + 1u < nx ? w_old[f + 1u] : wf);
        const f3d_real wl = ql > F3D_R(0.0) ? (i > 0u ? w_old[f - 1u] : wf) : wf;
        a += qr * wr - ql * wl - wf * (qr - ql);
        g->w[f] = wf - k * a / depth;
      }
    }
#undef QX
#undef QZ
  }
  /* 2½. Turbulence: the flow's own eddies mix its momentum sideways, so a
   * jet driven into a pool by a waterfall widens and slows instead of
   * crossing it as a thin stripe. Two kinds: the eddies the grid sees,
   * Smagorinsky's ν = (C·Δ)²·|S| with C = 0.15 and |S| the shear of the
   * flow in the cell; and the eddies as big as the water is deep, which a
   * depth-averaged flow cannot see, Fischer's transverse mixing
   * ε = 0.15·h·u* with u* the friction velocity Manning's bed gives,
   * n·|U|·√g / h^(1/6). Each face's velocity spreads to its neighbours',
   * explicitly and never faster than a quarter of a cell's mixing a
   * substep. Where it is dry there is nothing to mix. */
  {
    f3d_copy(u_old, g->u, (size_t)ux * nz * sizeof(f3d_real));
    f3d_copy(w_old, g->w, (size_t)nx * (nz + 1u) * sizeof(f3d_real));
    const f3d_real mix = F3D_R(0.15) * g->cell;
    const f3d_real most_nu = F3D_R(0.25) * g->cell * g->cell / h;
    /* And the fluid's own: what holds honey or lava together. */
    const f3d_real nu_fluid = ws->viscosity / ws->density;
    for (uint32_t c = 0; c < g->n; c++) {
      out[c] = F3D_R(0.0);
      if (!(g->depth[c] > F3D_SHALLOW_DRY)) continue;
      const uint32_t i = c % nx, j = c / nx;
      const f3d_real ux_ = (u_old[i + 1u + j * ux] - u_old[i + j * ux]) / g->cell;
      const f3d_real wz_ = (w_old[i + (j + 1u) * nx] - w_old[i + j * nx]) / g->cell;
      const f3d_real uz_ = (j + 1u < nz && j > 0u)
                               ? (u_old[i + (j + 1u) * ux] - u_old[i + (j - 1u) * ux]) /
                                     (F3D_R(2.0) * g->cell)
                               : F3D_R(0.0);
      const f3d_real wx_ = (i + 1u < nx && i > 0u)
                               ? (w_old[i + 1u + j * nx] - w_old[i - 1u + j * nx]) /
                                     (F3D_R(2.0) * g->cell)
                               : F3D_R(0.0);
      const f3d_real shear = f3d_sqrt(F3D_R(2.0) * (ux_ * ux_ + wz_ * wz_) +
                                      (uz_ + wx_) * (uz_ + wx_));
      const f3d_real d = g->depth[c];
      const f3d_real speed = f3d_sqrt(
          F3D_R(0.25) * (u_old[i + j * ux] + u_old[i + 1u + j * ux]) *
              (u_old[i + j * ux] + u_old[i + 1u + j * ux]) +
          F3D_R(0.25) * (w_old[i + j * nx] + w_old[i + (j + 1u) * nx]) *
              (w_old[i + j * nx] + w_old[i + (j + 1u) * nx]));
      const f3d_real friction =
          ws->roughness * speed * f3d_sqrt(gravity) / f3d_sqrt(cube_root(d));
      out[c] = f3d_min(mix * mix * shear + F3D_R(0.15) * d * friction + nu_fluid,
                       most_nu);
    }
    const f3d_real k = h / (g->cell * g->cell);
    for (uint32_t j = 0; j < nz; j++) {
      for (uint32_t i = 1; i < nx; i++) {
        const f3d_real nu = F3D_R(0.5) * (out[i - 1u + j * nx] + out[i + j * nx]);
        if (!(nu > F3D_R(0.0))) continue;
        const uint32_t f = i + j * ux;
        const f3d_real lap = u_old[f - 1u] + u_old[f + 1u] - F3D_R(4.0) * u_old[f] +
                             (j > 0u ? u_old[f - ux] : u_old[f]) +
                             (j + 1u < nz ? u_old[f + ux] : u_old[f]);
        g->u[f] += nu * k * lap;
      }
    }
    for (uint32_t j = 1; j < nz; j++) {
      for (uint32_t i = 0; i < nx; i++) {
        const f3d_real nu = F3D_R(0.5) * (out[i + (j - 1u) * nx] + out[i + j * nx]);
        if (!(nu > F3D_R(0.0))) continue;
        const uint32_t f = i + j * nx;
        const f3d_real lap = w_old[f - nx] + w_old[f + nx] - F3D_R(4.0) * w_old[f] +
                             (i > 0u ? w_old[f - 1u] : w_old[f]) +
                             (i + 1u < nx ? w_old[f + 1u] : w_old[f]);
        g->w[f] += nu * k * lap;
      }
    }
  }
  /* 3. The slope, the bed and the wind, face by face. With no wind field
   * the wind is the same everywhere, and asked once. */
  const f3d_real most = F3D_R(0.5) * g->cell / h;
  const int even_wind = world->grid == NULL || world->s.grid_n[0] == 0;
  f3d_real everywhere[3];
  f3d_world_sample_wind(world, ws->origin.x, ws->origin.y, ws->origin.z, everywhere);
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
          v[f] = g->depth[c] > F3D_SHALLOW_DRY
                     ? (outwards_positive ? f3d_max(inner, F3D_R(0.0))
                                          : f3d_min(inner, F3D_R(0.0)))
                     : F3D_R(0.0);
          continue;
        }
        const uint32_t a = axis == 0 ? (i - 1u) + j * nx : i + (j - 1u) * nx;
        const uint32_t b = axis == 0 ? i + j * nx : i + j * nx;
        const f3d_real da = g->depth[a], db = g->depth[b];
        if (!(da > F3D_SHALLOW_DRY) && !(db > F3D_SHALLOW_DRY)) {
          v[f] = F3D_R(0.0);
          continue;
        }
        const f3d_real ea = surface(g, a), eb = surface(g, b);
        f3d_real vel = v[f] - gravity * h * (eb - ea) / g->cell;
        /* Nothing to carry from a dry side, and no climbing onto dry
         * ground above the surface. */
        if (vel > F3D_R(0.0) && (!(da > F3D_SHALLOW_DRY) || ea < g->ground[b])) {
          vel = F3D_R(0.0);
        }
        if (vel < F3D_R(0.0) && (!(db > F3D_SHALLOW_DRY) || eb < g->ground[a])) {
          vel = F3D_R(0.0);
        }
        /* The wind's stress over the depth. */
        const f3d_real depth = F3D_R(0.5) * (da + db);
        if (depth > F3D_SHALLOW_DRY) {
          const f3d_real x = axis == 0 ? (f3d_real)i : (f3d_real)i + F3D_R(0.5);
          const f3d_real z = axis == 0 ? (f3d_real)j + F3D_R(0.5) : (f3d_real)j;
          f3d_real wind[3] = {everywhere[0], everywhere[1], everywhere[2]};
          if (!even_wind) {
            f3d_world_sample_wind(world, ws->origin.x + x * g->cell,
                                  ws->origin.y + F3D_R(0.5) * (ea + eb),
                                  ws->origin.z + z * g->cell, wind);
          }
          const f3d_real along = axis == 0 ? wind[0] : wind[2];
          const f3d_real across = axis == 0 ? wind[2] : wind[0];
          const f3d_real speed = f3d_sqrt(along * along + across * across);
          vel += h * world->s.air_density * F3D_WIND_ON_WATER * speed * along /
                 (ws->density * depth);
          /* The ground's hold, implicit: Manning's where the flow is
           * turbulent, or a laminar film's 3νU/h² where the fluid is thick
           * or the water thin and slow enough that it is more — whichever
           * holds harder, as a friction factor is the larger of the two. */
          const f3d_real h43 = depth * cube_root(depth);
          const f3d_real turbulent = gravity * n2 * f3d_abs(vel) / h43;
          const f3d_real laminar =
              F3D_R(3.0) * ws->viscosity / (ws->density * depth * depth);
          vel /= F3D_R(1.0) + h * f3d_max(turbulent, laminar);
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
         * surface below it by more than that: it goes over the lip, kept for
         * the sheet the face throws at the end of the step. Waves on level
         * ground are not a waterfall, however steep. */
        const f3d_real fall = g->ground[from] + g->depth[from] - surface(g, (uint32_t)to);
        if (g->ground[from] - g->ground[(uint32_t)to] > g->cell && fall > g->cell) {
          const uint32_t fi = axis == 0 ? f : ux * nz + f;
          const F3dVec3 vel = axis == 0 ? f3d_v3(v[f], F3D_R(0.0), F3D_R(0.0))
                                        : f3d_v3(F3D_R(0.0), F3D_R(0.0), v[f]);
          lip->volume[fi] += moved;
          lip->push[fi] = f3d_madd(lip->push[fi], vel, moved);
          lip->from[fi] = (uint32_t)from;
          continue;
        }
        next[to] += moved / g->area;
      }
    }
  }
  for (uint32_t c = 0; c < g->n; c++) g->depth[c] = f3d_max(next[c], F3D_R(0.0));
}

/* The share of a piece that splashes back up where it lands (Mundo and
 * colleagues): a jet or drop of diameter D striking at v splashes when
 * K = Oh·Re^1.25 passes 57.7, Oh = μ/√(ρσD), Re = ρvD/μ; past it, a tenth of
 * the excess, at most half — as the reference's Jet takes it. */
static f3d_real splash_share(const F3dShallowSlot *ws, f3d_real diameter,
                             f3d_real speed) {
  if (!(diameter > F3D_R(0.0) && speed > F3D_R(0.0))) return F3D_R(0.0);
  const f3d_real oh =
      ws->viscosity / f3d_sqrt(ws->density * ws->tension * diameter);
  const f3d_real re = ws->density * speed * diameter / ws->viscosity;
  const f3d_real k = oh * re * f3d_sqrt(f3d_sqrt(re));
  return k <= F3D_R(57.7) ? F3D_R(0.0)
                          : f3d_min(F3D_R(0.5), F3D_R(0.1) * (k / F3D_R(57.7) - F3D_R(1.0)));
}

/* A piece of falling water [d] coming down in column [c] of [g]: its water
 * and its push into the column; what splashes back up thrown as a crown of
 * eight drops at three tenths of its speed (as the reference's Jet throws
 * them); and, for a sheet plunging into water, the air it drags down. */
static void land(F3dWorld *world, Grid *g, const F3dSpray *d, uint32_t c) {
  const F3dShallowSlot *ws = g->slot;
  wake(g->slot);
  const f3d_real speed = f3d_sqrt(f3d_dot(d->velocity, d->velocity));
  const int sheet = d->kind == F3D_SPRAY_SHEET;
  const f3d_real section = sheet && speed > F3D_R(0.0) ? d->flow / speed : F3D_R(0.0);
  const f3d_real diameter =
      sheet ? F3D_R(2.0) * f3d_sqrt(section / F3D_PI) : d->width;
  const f3d_real splash = splash_share(ws, diameter, speed);
  const f3d_real stays = d->volume * (F3D_R(1.0) - splash);
  const int wet = g->depth[c] > F3D_SHALLOW_DRY;
  /* Plunging in, it drags the water round it along and widens until it
   * reaches the bottom: its water and its push go into every wet column
   * within as far as the pool is deep where it came down, alike; onto dry
   * ground, into the one column. */
  const uint32_t ci = c % g->nx, cj = c / g->nx;
  const f3d_real reach = wet ? f3d_max(g->depth[c], g->cell) : F3D_R(0.0);
  const int32_t span = (int32_t)(reach / g->cell);
  uint32_t taken = 0;
  for (int pass = 0; pass < 2; pass++) {
    for (int32_t dj = -span; dj <= span; dj++) {
      for (int32_t di = -span; di <= span; di++) {
        const int32_t i = (int32_t)ci + di, j = (int32_t)cj + dj;
        if (i < 0 || j < 0 || i >= (int32_t)g->nx || j >= (int32_t)g->nz) continue;
        if ((f3d_real)(di * di + dj * dj) * g->cell * g->cell > reach * reach) continue;
        const uint32_t q = (uint32_t)i + (uint32_t)j * g->nx;
        if (q != c && !(g->depth[q] > F3D_SHALLOW_DRY)) continue;
        if (pass == 0) {
          taken++;
          continue;
        }
        const f3d_real part = stays / (f3d_real)taken;
        const f3d_real held = g->depth[q] * g->area;
        g->depth[q] += part / g->area;
        const f3d_real share = part / (held + part);
        const uint32_t ux = g->nx + 1u;
        const uint32_t ii = (uint32_t)i, jj = (uint32_t)j;
        g->u[ii + jj * ux] += (d->velocity.x - g->u[ii + jj * ux]) * share;
        g->u[ii + 1u + jj * ux] += (d->velocity.x - g->u[ii + 1u + jj * ux]) * share;
        g->w[ii + jj * g->nx] += (d->velocity.z - g->w[ii + jj * g->nx]) * share;
        g->w[ii + (jj + 1u) * g->nx] += (d->velocity.z - g->w[ii + (jj + 1u) * g->nx]) * share;
      }
    }
  }
  const f3d_real gravity = f3d_sqrt(f3d_dot(world->s.gravity, world->s.gravity));
  const F3dVec3 up = gravity > F3D_R(0.0)
                         ? f3d_scale(world->s.gravity, F3D_R(-1.0) / gravity)
                         : f3d_v3(F3D_R(0.0), F3D_R(1.0), F3D_R(0.0));
  if (splash > F3D_R(0.0)) {
    const F3dVec3 side = f3d_abs(up.x) < F3D_R(0.9)
                             ? f3d_v3(F3D_R(1.0), F3D_R(0.0), F3D_R(0.0))
                             : f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(1.0));
    F3dVec3 e1 = f3d_cross(up, side);
    e1 = f3d_scale(e1, F3D_R(1.0) / f3d_sqrt(f3d_dot(e1, e1)));
    const F3dVec3 e2 = f3d_cross(up, e1);
    for (uint32_t k = 0; k < 8u; k++) {
      f3d_real sn, cs;
      f3d_sin_cos(F3D_R(2.0) * F3D_PI * ((f3d_real)k + F3D_R(0.5)) / F3D_R(8.0), &sn, &cs);
      F3dVec3 out = f3d_add(f3d_scale(f3d_add(f3d_scale(e1, cs), f3d_scale(e2, sn)), F3D_R(0.6)),
                            f3d_scale(up, F3D_R(0.8)));
      out = f3d_scale(out, F3D_R(0.3) * speed / f3d_sqrt(f3d_dot(out, out)));
      throw_drops(world, g, d->water, d->at, out, d->volume * splash / F3D_R(8.0),
                  sheet ? F3D_CROWN_DROP : d->width, c);
    }
  }
  /* Air dragged down by a sheet plunging into water (Bin, 1993):
   * Q_air/Q = 0.04·Fr^0.28·(H/e)^0.4, Fr = v₀²/(g·e₀) as it left the lip, H
   * how far it fell. Into the middle of the column it plunged into. */
  if (sheet && wet && d->speed0 > F3D_R(0.0) && d->width > F3D_R(0.0) &&
      gravity > F3D_R(0.0)) {
    const f3d_real e0 = d->flow / (d->width * d->speed0);
    const f3d_real fall = d->top - d->at.y;
    if (e0 > F3D_R(0.0) && fall > F3D_R(0.0)) {
      const f3d_real fr = d->speed0 * d->speed0 / (gravity * e0);
      const f3d_real air = F3D_R(0.04) * power(fr, F3D_R(0.28)) * power(fall / e0, F3D_R(0.4)) * stays;
      const F3dVec3 at = f3d_v3(d->at.x,
                                ws->origin.y + g->ground[c] + F3D_R(0.5) * g->depth[c],
                                d->at.z);
      add_bubbles(world, d->water, at, air);
    }
  }
}

/* The world's falling water in flight for [dt]: each piece falling freely,
 * a sheet's ripples growing until it breaks into drops, and landing in the
 * water or on the ground below it, in pieces no longer than half a cell so
 * it does not pass through a thin sheet of water. */
static void fly_spray(F3dWorld *world, f3d_real dt) {
  uint32_t kept = 0;
  for (uint32_t k = 0; k < world->s.spray_count; k++) {
    F3dSpray d = world->spray[k];
    F3dShallowSlot *ws = water_of(world, d.water);
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
      if (d.kind == F3D_SPRAY_SHEET) {
        /* Weber's growth at the sheet's own thickness, which continuity
         * thins as it speeds up; twelve e-foldings and it is drops of 1.89
         * times that. */
        const f3d_real e = d.flow / (d.width * speed);
        const f3d_real tau = f3d_sqrt(ws->density * e * e * e / ws->tension) +
                             F3D_R(3.0) * ws->viscosity * e / ws->tension;
        if (tau > F3D_R(0.0)) d.growth += piece / tau;
        if (d.growth >= F3D_BREAKUP_GROWTH) {
          d.kind = F3D_SPRAY_DROPS;
          d.face = 0;
          d.width = F3D_R(1.89) * e;
        }
      }
      const int32_t c = cell_at(&g, d.at.x, d.at.z);
      if (c < 0) {
        /* Off the grid: gone from this water. */
        ws->lost += d.volume;
        landed = 1;
        break;
      }
      if (d.at.y - ws->origin.y <= surface(&g, (uint32_t)c)) {
        land(world, &g, &d, (uint32_t)c);
        landed = 1;
      }
    }
    if (!landed) world->spray[kept++] = d;
  }
  world->s.spray_count = kept;
}

/* The world's bubbles for [dt]: each cloud carried by the flow where it is
 * and rising at its bubbles' terminal speed — water's, or in a liquid thick
 * enough to hold them back the slower Hadamard–Rybczynski ρgr²/3μ — gone
 * when it reaches the surface or leaves the water. */
static void rise_bubbles(F3dWorld *world, f3d_real dt) {
  const f3d_real gravity = f3d_sqrt(f3d_dot(world->s.gravity, world->s.gravity));
  const F3dVec3 up = gravity > F3D_R(0.0)
                         ? f3d_scale(world->s.gravity, F3D_R(-1.0) / gravity)
                         : f3d_v3(F3D_R(0.0), F3D_R(1.0), F3D_R(0.0));
  uint32_t kept = 0;
  for (uint32_t k = 0; k < world->s.bubble_count; k++) {
    F3dBubbles b = world->bubbles[k];
    F3dShallowSlot *ws = water_of(world, b.water);
    if (ws == NULL) continue;
    Grid g = grid_of(world, ws);
    const f3d_real fx = (b.at.x - ws->origin.x) / g.cell;
    const f3d_real fz = (b.at.z - ws->origin.z) / g.cell;
    const F3dVec3 flow = f3d_v3(flow_x(&g, fx, fz), F3D_R(0.0), flow_z(&g, fx, fz));
    const f3d_real rise = f3d_min(
        F3D_BUBBLE_RISE,
        ws->density * gravity * F3D_BUBBLE_RADIUS * F3D_BUBBLE_RADIUS /
            (F3D_R(3.0) * ws->viscosity));
    b.at = f3d_madd(f3d_madd(b.at, flow, dt), up, rise * dt);
    const int32_t c = cell_at(&g, b.at.x, b.at.z);
    if (c < 0 || !(g.depth[c] > F3D_SHALLOW_DRY)) continue;
    if (b.at.y - ws->origin.y >= surface(&g, (uint32_t)c)) continue;
    world->bubbles[kept++] = b;
  }
  world->s.bubble_count = kept;
}

/* Whether resting water [ws] is stirred this step: a body that can stand in
 * it reaching over its grid and down to its surface by the end of the
 * step, or wind over it. Its springs and everything poured or landed in
 * it wake it as they happen. */
static int stirred(const F3dWorld *world, const F3dShallowSlot *ws, f3d_real dt) {
  const f3d_real wide = (f3d_real)ws->nx * ws->cell;
  const f3d_real deep = (f3d_real)ws->nz * ws->cell;
  f3d_real wind[3];
  f3d_world_sample_wind(world, ws->origin.x + F3D_R(0.5) * wide,
                        ws->origin.y + ws->top,
                        ws->origin.z + F3D_R(0.5) * deep, wind);
  if (wind[0] * wind[0] + wind[2] * wind[2] > F3D_R(0.0)) return 1;
  for (uint32_t b = 0; b < world->s.used; b++) {
    const F3dSlot *s = &world->slots[b];
    if (!s->live || s->type != F3D_BODY_DYNAMIC || s->shape == F3D_SHAPE_POINT ||
        s->shape == F3D_SHAPE_MESH) {
      continue;
    }
    const f3d_real volume = s->shape == F3D_SHAPE_COMPOUND && s->hull != 0
                                ? world->compounds[s->hull - 1u].volume
                                : f3d_shape_volume(world, s->shape, s->size,
                                                   s->rounding, s->hull);
    if (!(volume > F3D_R(0.0))) continue;
    const f3d_real r = cube_root(volume * F3D_R(3.0) / (F3D_R(4.0) * F3D_PI));
    /* Where it is and where it will be, both: a body crossing the edge in
     * one step is in it at one end or the other. */
    const F3dVec3 a = f3d_sub(s->position, ws->origin);
    const F3dVec3 e = f3d_sub(f3d_madd(s->position, s->velocity, dt), ws->origin);
    const f3d_real reach = r + ws->cell;
    if (f3d_max(a.x, e.x) < -reach || f3d_min(a.x, e.x) > wide + reach ||
        f3d_max(a.z, e.z) < -reach || f3d_min(a.z, e.z) > deep + reach ||
        f3d_min(a.y, e.y) > ws->top + reach) {
      continue;
    }
    return 1;
  }
  return 0;
}

void f3d_step_water(F3dWorld *world, f3d_real dt) {
  if (world->s.shallow_count == 0) return;
  const f3d_real gravity = f3d_sqrt(f3d_dot(world->s.gravity, world->s.gravity));
  for (uint32_t k = 0; k < world->s.shallow_count; k++) {
    F3dShallowSlot *ws = &world->shallows[k];
    if (!ws->live) continue;
    if (ws->resting) {
      if (!stirred(world, ws, dt)) continue;
      wake(ws);
    }
    Grid g = grid_of(world, ws);
    bodies_in(world, &g, k + 1u, dt);
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
      while ((f3d_real)count * longest < dt && count < F3D_SHALLOW_MOST_SUBSTEPS) count++;
    }
    const size_t faces = (size_t)(g.nx + 1u) * g.nz + (size_t)g.nx * (g.nz + 1u);
    f3d_real *room = (f3d_real *)f3d_alloc((faces + 2u * (size_t)g.n) * sizeof(f3d_real) + 16u);
    Lip lip;
    lip.volume = (f3d_real *)f3d_alloc(faces * sizeof(f3d_real) + 8u);
    lip.push = (F3dVec3 *)f3d_alloc(faces * sizeof(F3dVec3) + 8u);
    lip.from = (uint32_t *)f3d_alloc(faces * sizeof(uint32_t) + 8u);
    if (room == NULL || lip.volume == NULL || lip.push == NULL || lip.from == NULL) {
      f3d_free(room);
      f3d_free(lip.volume);
      f3d_free(lip.push);
      f3d_free(lip.from);
      continue;
    }
    f3d_zero(lip.volume, faces * sizeof(f3d_real));
    f3d_zero(lip.push, faces * sizeof(F3dVec3));
    f3d_real *u_old = room;
    f3d_real *w_old = room + (size_t)(g.nx + 1u) * g.nz + g.n;
    f3d_real *out = w_old + (size_t)g.nx * (g.nz + 1u);
    /* u_old doubles as the depths' room: it is as long as the larger. */
    const f3d_real h = dt / (f3d_real)count;
    for (uint32_t s = 0; s < count; s++) substep(world, &g, &lip, h, u_old, w_old, out);
    /* Each face of a lip throws what went over it this step as one piece
     * of sheet, as wide as the face, at the speed it went over with, from
     * the middle of the sheet's thickness at the lip. With no room for it,
     * the water stays on the lip for the next step. */
    const uint32_t ux = g.nx + 1u;
    for (uint32_t fi = 0; fi < (uint32_t)faces; fi++) {
      const f3d_real volume = lip.volume[fi];
      if (!(volume > F3D_R(0.0))) continue;
      const F3dVec3 velocity = f3d_scale(lip.push[fi], F3D_R(1.0) / volume);
      const f3d_real speed = f3d_sqrt(f3d_dot(velocity, velocity));
      const uint32_t from = lip.from[fi];
      const int x_face = fi < ux * g.nz;
      const uint32_t f = x_face ? fi : fi - ux * g.nz;
      const f3d_real fx = x_face ? (f3d_real)(f % ux) : (f3d_real)(f % g.nx) + F3D_R(0.5);
      const f3d_real fz = x_face ? (f3d_real)(f / ux) + F3D_R(0.5) : (f3d_real)(f / g.nx);
      F3dSpray d;
      f3d_zero(&d, sizeof d);
      d.water = k + 1u;
      d.kind = F3D_SPRAY_SHEET;
      d.face = fi + 1u;
      d.volume = volume;
      d.velocity = velocity;
      d.flow = volume / dt;
      d.width = g.cell;
      d.speed0 = speed;
      const f3d_real thick = speed > F3D_R(0.0) ? d.flow / (d.width * speed) : F3D_R(0.0);
      d.at = f3d_add(ws->origin, f3d_v3(fx * g.cell,
                                        g.ground[from] + F3D_R(0.5) * thick,
                                        fz * g.cell));
      d.top = d.at.y;
      if (!add_spray(world, &d)) g.depth[from] += volume / g.area;
    }
    /* Still, with nothing in it, feeding it or going over a lip, for long
     * enough: it rests. */
    int quiet = fastest < F3D_SHALLOW_CALM;
    for (uint32_t i = 0; quiet && i < ws->source_count; i++) {
      quiet = ws->sources[i].rate == F3D_R(0.0);
    }
    for (uint32_t c = 0; quiet && c < g.n; c++) quiet = g.filled[c] == F3D_R(0.0);
    for (uint32_t fi = 0; quiet && fi < (uint32_t)faces; fi++) {
      quiet = !(lip.volume[fi] > F3D_R(0.0));
    }
    ws->calm = quiet ? ws->calm + dt : F3D_R(0.0);
    if (ws->calm >= F3D_SHALLOW_SETTLES) {
      f3d_real top = F3D_R(-1e30);
      for (uint32_t c = 0; c < g.n; c++) {
        if (g.depth[c] > F3D_SHALLOW_DRY) top = f3d_max(top, surface(&g, c));
      }
      ws->top = top;
      ws->resting = 1u;
    }
    f3d_free(lip.volume);
    f3d_free(lip.push);
    f3d_free(lip.from);
    f3d_free(room);
  }
  fly_spray(world, dt);
  rise_bubbles(world, dt);
}
