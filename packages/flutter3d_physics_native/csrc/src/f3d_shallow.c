/*
 * Water over ground — a stream, a pond, a waterfall into it.
 *
 * Shallow water (after Chentanez and Müller, 2010): in each column of a
 * grid the water moves as one, with its depth at the column's centre and
 * its velocity across each face between two columns. A step is cut into
 * substeps no longer than a quarter of the time a wave takes to cross a
 * cell, nor than the fluid's own viscosity lets a cell's momentum spread
 * stably, and in each:
 *
 *   1. the springs well up, the outlets take what their weirs pass, and the
 *      edges let in what they are given;
 *   2. the velocities are carried along themselves;
 *   3. each face is pushed by the slope of the surface across it, g·Δη/Δx,
 *      the surface being the ground, the water and what bodies standing in
 *      it fill; held back by Manning's friction, g·n²·|u|·u / h^(4/3), with
 *      the roughness of the cells either side, taken implicitly so it never
 *      turns the flow round; and pulled by the wind's stress on the surface
 *      over the depth. Where the ground falls away under a face and the
 *      water beyond stands below the lip, nothing downstream holds the flow
 *      back: it crosses at the critical speed √(g·h) of the depth above the
 *      lip, or faster if it came faster — a free overfall (Rouse, 1936);
 *   4. water crosses each face, as much as its velocity carries of the
 *      depth on the side it comes from that stands above the higher of the
 *      two beds (hydrostatic reconstruction, Audusse and colleagues, 2004),
 *      and a column that would give more than it holds gives what it holds,
 *      every face it gives through cut alike — so the water is never less
 *      than none and none is made.
 *
 * Water going over a free overfall flies when it would still be in the air
 * past the middle of the next column: its centre's height over the water
 * below more than g·(Δx/2)²/2u², the drop of a jet leaving the lip at u.
 * It leaves the grid as a sheet of spray at the face, flies, and lands in
 * the water or on the ground where it comes down, putting its volume and
 * its push there. That is a waterfall, and the waves at its foot; a chute
 * whose water reaches the next column before it is past it runs down it as
 * flow, however steep.
 *
 * A body in the water — dynamic, fixed or moved by its velocity — stands in
 * the columns its shape fills: the vertical chord through it at points two
 * to a cell, and no fewer than sixteen across it, cut by the ground below
 * and by the surface of the column the point is in, gives the volume under
 * water in each column and its middle, the whole scaled to the shape's own
 * volume. What it fills raises the surface, so a stone dropped in pushes
 * waves out from where it went in, a pier stands in a current and a boat
 * leaves a wake. A dynamic body is held up by the weight of what it
 * displaces, ρgV, at the middle of what is under water, so a box floating
 * on its side rights itself as its metacentre says and a log floats along
 * its length; dragged by the flow, as hard as its shape and its Reynolds
 * number say, over the area it shows the flow; made heavier to speed up by
 * the water it must move with it; and the flow is pushed back as hard as
 * it drags.
 *
 * What the water is — its density, viscosity and surface tension — is the
 * water's own: honey creeps, lava holds a stone up and lets it sink
 * slowly.
 *
 * The grid lies in x and z and its water stands on y: what pulls the water
 * down is gravity's part along −y, and a body is held up along +y.
 *
 * Every loop runs in grid order, the spray in the order it was made, so
 * the same world pours the same water everywhere.
 */
#include "f3d_internal.h"

/* What a new water is is water, at 20 °C: its density, viscosity, surface
 * tension and what heat sees of it are the catalogue's (F3D_MAT_WATER_*,
 * from f3d_materials.g.h). */
/* How thin water is still water, m: below it a column is dry. */
#define F3D_SHALLOW_DRY F3D_R(1e-4)
/* The drag coefficient of the wind's stress on a liquid's surface (Large
 * and Pond's open-sea value): a law's number, not a substance's. */
#define F3D_WIND_STRESS_DRAG F3D_R(1.3e-3)
/* How many e-foldings of growth part a sheet (Grant and Middleman). */
#define F3D_BREAKUP_GROWTH F3D_R(12.0)
/* The bubbles a plunging sheet drags down are a few millimetres across
 * (Chanson), and rise at the terminal speed bubbles of that size share,
 * about 0.23 m/s whatever their size between one and ten millimetres
 * (Clift, Grace and Weber). */
#define F3D_BUBBLE_RADIUS F3D_R(0.002)
#define F3D_BUBBLE_RISE F3D_R(0.23)

/* When water rests unless the world says otherwise: no cell holding more
 * than a metre of water moving a millimetre a second does, for a second. */
#define F3D_REST_ENERGY F3D_R(5e-4)
#define F3D_REST_TIME F3D_R(1.0)

/* ------------------------------------------------------------- the grid */

typedef struct Grid {
  F3dShallowSlot *slot;
  uint32_t nx, nz, n;
  f3d_real cell, area;
  f3d_real *ground, *depth, *u, *w, *filled, *rough, *wall;
} Grid;

static uint32_t reals_of(uint32_t nx, uint32_t nz) {
  return 5u * nx * nz + (nx + 1u) * nz + nx * (nz + 1u);
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
  g.rough = g.filled + g.n;
  g.wall = g.rough + g.n;
  return g;
}

/* What pulls the water down: gravity's part along −y. */
static f3d_real gravity_down(const F3dWorld *world) {
  return f3d_max(-world->s.gravity.y, F3D_R(0.0));
}

/* The surface over cell c, above the grid's origin. */
static f3d_real surface(const Grid *g, uint32_t c) {
  return g->ground[c] + g->depth[c] + g->filled[c] / g->area;
}

static int walled(const Grid *g, uint32_t c) { return g->wall[c] != F3D_R(0.0); }

static int wet(const Grid *g, uint32_t c) {
  return g->depth[c] > F3D_SHALLOW_DRY && !walled(g, c);
}

/* Manning's roughness of cell c. */
static f3d_real roughness_at(const Grid *g, uint32_t c) {
  return g->rough[c] < F3D_R(0.0) ? g->slot->roughness : g->rough[c];
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
  if (!f3d_finite(x)) return x;
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
  if (!f3d_finite(x)) return x;
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
  /* Past these e^y is outside every float this core computes in: nought,
   * or as large as can be, without walking there a ln 2 at a time. */
  if (!(y > F3D_R(-700.0))) return F3D_R(0.0);
  if (y > F3D_R(700.0)) return y;
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
  w->density = F3D_MAT_WATER_DENSITY;
  w->viscosity = F3D_MAT_WATER_VISCOSITY;
  w->tension = F3D_MAT_WATER_SURFACE_TENSION;
  w->temperature = world->s.air_temperature > F3D_R(0.0) ? world->s.air_temperature
                                                         : F3D_STANDARD_AIR_TEMPERATURE;
  w->specific_heat = F3D_MAT_WATER_SPECIFIC_HEAT;
  w->conductivity = F3D_MAT_WATER_CONDUCTIVITY;
  w->expansion = F3D_MAT_WATER_VOLUMETRIC_EXPANSION;
  w->boils = 1u;
  f3d_real *mine = data + w->first;
  f3d_zero(mine, (size_t)size * sizeof(f3d_real));
  f3d_copy(mine, ground, (size_t)nx * nz * sizeof(f3d_real));
  /* Every cell as rough as the water says. */
  f3d_real *rough = mine + 3u * nx * nz + (nx + 1u) * nz + nx * (nz + 1u);
  for (uint32_t c = 0; c < nx * nz; c++) rough[c] = F3D_R(-1.0);
  world->s.shallow_reals += size;
  world->s.shallow_count++;
  return world->s.shallow_count;
}

/* A compound's parts' heat, while the world holds them; null otherwise. */
static F3dLump *lumps_in(F3dWorld *world, const F3dSlot *s) {
  if (s->lumps == 0 || s->lumps - 1u + s->lump_count > world->s.lump_count) return NULL;
  return &world->lumps[s->lumps - 1u];
}

/* Every body [water] last found standing in it, out of it. */
static void dry_bodies(F3dWorld *world, F3dShallow water) {
  for (uint32_t b = 0; b < world->s.used; b++) {
    F3dSlot *s = &world->slots[b];
    if (s->liquid != water) continue;
    s->liquid = 0;
    s->submerged = F3D_R(0.0);
    s->liquid_speed = F3D_R(0.0);
    F3dLump *l = lumps_in(world, s);
    for (uint32_t k = 0; l != NULL && k < s->lump_count; k++) l[k].immersed = F3D_R(0.0);
  }
}

int f3d_shallow_destroy(F3dWorld *world, F3dShallow water) {
  F3dShallowSlot *w = water_of(world, water);
  if (w == NULL) return 0;
  dry_bodies(world, water);
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
      if (walled(&g, c)) continue;
      g.depth[c] = f3d_max(level - g.ground[c], F3D_R(0.0));
    }
  }
  wake(w);
  return 1;
}

uint32_t f3d_shallow_fill_basin(F3dWorld *world, F3dShallow water, f3d_real x,
                                f3d_real z, f3d_real level) {
  F3dShallowSlot *w = water_of(world, water);
  if (w == NULL || !(f3d_finite(x) && f3d_finite(z) && f3d_finite(level))) return 0;
  Grid g = grid_of(world, w);
  const f3d_real fx = (x - w->origin.x) / g.cell, fz = (z - w->origin.z) / g.cell;
  if (!(fx >= F3D_R(0.0) && fz >= F3D_R(0.0) && fx < (f3d_real)g.nx && fz < (f3d_real)g.nz)) {
    return 0;
  }
  const uint32_t start = (uint32_t)fx + (uint32_t)fz * g.nx;
  if (walled(&g, start) || !(g.ground[start] < level)) return 0;
  /* Side by side from the start, first in first out: the cells in the order
   * they were reached, so the same basin fills alike everywhere. */
  uint32_t *queue = (uint32_t *)f3d_alloc((size_t)g.n * sizeof(uint32_t) + 8u);
  uint8_t *seen = (uint8_t *)f3d_alloc((size_t)g.n + 8u);
  if (queue == NULL || seen == NULL) {
    f3d_free(queue);
    f3d_free(seen);
    return 0;
  }
  f3d_zero(seen, (size_t)g.n);
  uint32_t head = 0, tail = 0;
  queue[tail++] = start;
  seen[start] = 1;
  while (head < tail) {
    const uint32_t c = queue[head++];
    g.depth[c] = level - g.ground[c];
    const uint32_t i = c % g.nx, j = c / g.nx;
    const int32_t near[4][2] = {{-1, 0}, {1, 0}, {0, -1}, {0, 1}};
    for (int k = 0; k < 4; k++) {
      const int32_t ii = (int32_t)i + near[k][0], jj = (int32_t)j + near[k][1];
      if (ii < 0 || jj < 0 || ii >= (int32_t)g.nx || jj >= (int32_t)g.nz) continue;
      const uint32_t q = (uint32_t)ii + (uint32_t)jj * g.nx;
      if (seen[q] || walled(&g, q) || !(g.ground[q] < level)) continue;
      seen[q] = 1;
      queue[tail++] = q;
    }
  }
  f3d_free(queue);
  f3d_free(seen);
  wake(w);
  return tail;
}

int f3d_shallow_set_depth(F3dWorld *world, F3dShallow water, const f3d_real *depth) {
  F3dShallowSlot *w = water_of(world, water);
  if (w == NULL || depth == NULL) return 0;
  for (uint32_t c = 0; c < w->nx * w->nz; c++) {
    if (!(f3d_finite(depth[c]) && depth[c] >= F3D_R(0.0))) return 0;
  }
  Grid g = grid_of(world, w);
  for (uint32_t c = 0; c < g.n; c++) if (!walled(&g, c)) g.depth[c] = depth[c];
  wake(w);
  return 1;
}

/* [volume] over the cells whose centres are within [radius] of (x, z),
 * alike, or into the one cell (x, z) is in when none are; taken out as far
 * as there is water. Walls take none. Returns what went in. */
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
        const uint32_t c = i + j * g->nx;
        if (walled(g, c)) continue;
        if (pass == 0) {
          count++;
          continue;
        }
        const f3d_real want = volume / (f3d_real)count / g->area;
        const f3d_real next = f3d_max(g->depth[c] + want, F3D_R(0.0));
        given += (next - g->depth[c]) * g->area;
        g->depth[c] = next;
      }
    }
    if (pass == 1) return given;
    if (count == 0) {
      const int32_t c = cell_at(g, x, z);
      if (c < 0 || walled(g, (uint32_t)c)) return F3D_R(0.0);
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
  for (int k = 0; k < 4; k++) {
    w->edge_kind[k] = open_edges ? F3D_EDGE_OPEN : F3D_EDGE_WALL;
    w->edge_value[k] = F3D_R(0.0);
  }
  wake(w);
  return 1;
}

int f3d_shallow_set_edge(F3dWorld *world, F3dShallow water, uint32_t side,
                         uint32_t kind, f3d_real value) {
  F3dShallowSlot *w = water_of(world, water);
  if (w == NULL || side > 3u || kind > F3D_EDGE_LEVEL || !f3d_finite(value)) return 0;
  w->edge_kind[side] = kind;
  w->edge_value[side] = value;
  wake(w);
  return 1;
}

int f3d_shallow_set_outlet(F3dWorld *world, F3dShallow water, uint32_t index,
                           f3d_real x, f3d_real z, f3d_real crest,
                           f3d_real width, f3d_real coefficient) {
  F3dShallowSlot *w = water_of(world, water);
  if (w == NULL || index >= F3D_SHALLOW_MOST_OUTLETS) return 0;
  if (!(f3d_finite(x) && f3d_finite(z) && f3d_finite(crest) &&
        f3d_finite(width) && width >= F3D_R(0.0) && f3d_finite(coefficient))) {
    return 0;
  }
  F3dShallowOutlet *o = &w->outlets[index];
  o->x = x;
  o->z = z;
  o->crest = crest;
  o->width = width;
  o->coefficient = coefficient;
  o->kind = F3D_OUTLET_WEIR;
  if (index >= w->outlet_count) w->outlet_count = index + 1u;
  wake(w);
  return 1;
}

int f3d_shallow_set_drain(F3dWorld *world, F3dShallow water, uint32_t index,
                          f3d_real x, f3d_real z, f3d_real invert, f3d_real area,
                          f3d_real coefficient) {
  if (!f3d_shallow_set_outlet(world, water, index, x, z, invert, area, coefficient)) {
    return 0;
  }
  water_of(world, water)->outlets[index].kind = F3D_OUTLET_DRAIN;
  return 1;
}

int f3d_shallow_set_cells(F3dWorld *world, F3dShallow water,
                          const f3d_real *roughness, const uint32_t *walls) {
  F3dShallowSlot *w = water_of(world, water);
  if (w == NULL) return 0;
  Grid g = grid_of(world, w);
  if (roughness != NULL) {
    for (uint32_t c = 0; c < g.n; c++) {
      if (!f3d_finite(roughness[c])) return 0;
    }
    for (uint32_t c = 0; c < g.n; c++) g.rough[c] = roughness[c];
  }
  if (walls != NULL) {
    for (uint32_t c = 0; c < g.n; c++) g.wall[c] = walls[c] ? F3D_R(1.0) : F3D_R(0.0);
  }
  wake(w);
  return 1;
}

int f3d_shallow_info(const F3dWorld *world, F3dShallow water, f3d_real *out) {
  F3dShallowSlot *w = water_of(world, water);
  if (w == NULL || out == NULL) return 0;
  out[0] = (f3d_real)w->substeps;
  out[1] = (f3d_real)w->overruns;
  out[2] = w->resting ? F3D_R(1.0) : F3D_R(0.0);
  out[3] = w->energy;
  return 1;
}

int f3d_world_set_water_rest(F3dWorld *world, f3d_real energy, f3d_real seconds) {
  if (!(f3d_finite(energy) && energy >= F3D_R(0.0))) return 0;
  if (!(f3d_finite(seconds) && seconds >= F3D_R(0.0))) return 0;
  world->s.water_rest_energy = energy;
  world->s.water_rest_time = seconds;
  world->s.water_rest_set = 1u;
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

int f3d_shallow_set_heat(F3dWorld *world, F3dShallow water, f3d_real temperature,
                         f3d_real specific_heat, f3d_real conductivity,
                         f3d_real expansion, int boils) {
  F3dShallowSlot *w = water_of(world, water);
  if (w == NULL || !(f3d_finite(temperature) && temperature > F3D_R(0.0)) ||
      !(f3d_finite(specific_heat) && specific_heat > F3D_R(0.0)) ||
      !(f3d_finite(conductivity) && conductivity > F3D_R(0.0)) ||
      !(f3d_finite(expansion) && expansion >= F3D_R(0.0))) {
    return 0;
  }
  w->temperature = temperature;
  w->specific_heat = specific_heat;
  w->conductivity = conductivity;
  w->expansion = expansion;
  w->boils = boils != 0 ? 1u : 0u;
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
 * not, it pushes aside: when [aside], that much water leaves the column,
 * into [pushed] for the columns round it, with the flow it had, into
 * [carried], so the surface over it stays where it was, a bulge runs out
 * from it, and no momentum is lost on the way. With nowhere round it to
 * go, the water stays and the surface over it rises. When it fills less,
 * the surface over it sinks and the water flows back in by itself. */
static void stand(Grid *g, f3d_real *was, uint32_t c, f3d_real volume, int aside,
                  f3d_real *pushed, F3dVec3 *carried) {
  g->filled[c] += volume;
  const f3d_real more = volume - was[c];
  was[c] = f3d_max(was[c] - volume, F3D_R(0.0));
  if (aside && more > F3D_R(0.0)) {
    const f3d_real take = f3d_min(more, g->depth[c] * g->area);
    g->depth[c] -= take / g->area;
    *pushed += take;
    *carried = f3d_madd(*carried, column_flow(g, c), take);
  }
}

/* ------------------------------------------------------- bodies by shape */

/* The product of two turns, [a] after [b]'s. */
static F3dQuat quat_mul(F3dQuat a, F3dQuat b) {
  F3dQuat q;
  q.w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z;
  q.x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y;
  q.y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x;
  q.z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w;
  return q;
}

static F3dVec3 out_of(const F3dMat3 *m, F3dVec3 v) {
  return f3d_add(f3d_add(f3d_scale(m->c[0], v.x), f3d_scale(m->c[1], v.y)),
                 f3d_scale(m->c[2], v.z));
}

static F3dVec3 into(const F3dMat3 *m, F3dVec3 v) {
  return f3d_v3(f3d_dot(m->c[0], v), f3d_dot(m->c[1], v), f3d_dot(m->c[2], v));
}

/* One convex shape of a body where it stands: the body's own, or one part
 * of a compound. Its size grown by its rounding, as its volume is. */
typedef struct Piece {
  uint32_t kind;
  F3dVec3 size;
  /* Its centre over the water's origin, its axes in the world, and the
   * world's up in its own frame. */
  F3dVec3 at;
  F3dMat3 axes;
  F3dVec3 up;
  /* A hull's planes in the scratch: four reals each, the outward normal
   * and the distance, and its triangle's area. */
  uint32_t first_plane, plane_count;
  f3d_real volume, surface;
  /* Its box over the water's origin. */
  f3d_real lo_x, hi_x, lo_y, hi_y, lo_z, hi_z;
  /* What of it is under water this step, m³. */
  f3d_real under;
  /* Which part of its compound it is; nought for any other body. */
  uint32_t part;
} Piece;

#define PLANE_REALS 5u

/* What the bodies' pass works in, grown as it needs. */
typedef struct Scratch {
  f3d_real *planes;
  size_t plane_room;
  Piece *pieces;
  size_t piece_room;
  f3d_real *columns;
  size_t column_room;
  uint32_t *cells;
  size_t cell_room;
} Scratch;

static int make_room(void **p, size_t *room, size_t want, size_t each) {
  if (want <= *room) return 1;
  size_t next = *room > 0 ? *room : 64u;
  while (next < want) next *= 2u;
  void *more = f3d_realloc(*p, next * each);
  if (more == NULL) return 0;
  *p = more;
  *room = next;
  return 1;
}

/* [kind] of [size] and [rounding] (and [hull]) at [at] over the water's
 * origin, turned by [turn], as a piece; its hull's planes into [scratch]
 * from [*planes] on. 0 for no memory or a shape that holds nothing. */
static int piece_of(const F3dWorld *world, Scratch *scratch, uint32_t *planes,
                    uint32_t kind, F3dVec3 size, f3d_real rounding, uint32_t hull,
                    F3dVec3 at, F3dQuat turn, Piece *p) {
  f3d_zero(p, sizeof *p);
  p->kind = kind;
  p->at = at;
  p->axes = f3d_mat_of(turn);
  p->up = f3d_v3(p->axes.c[0].y, p->axes.c[1].y, p->axes.c[2].y);
  p->volume = f3d_shape_volume(world, kind, size, rounding, hull);
  p->surface = f3d_shape_surface(world, kind, size, rounding, hull);
  if (!(p->volume > F3D_R(0.0))) return 0;
  const F3dVec3 *c = p->axes.c;
  const f3d_real r = rounding;
  F3dVec3 half = f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
  F3dVec3 centre = at;
  switch (kind) {
    case F3D_SHAPE_SPHERE:
      p->size = f3d_v3(size.x + r, F3D_R(0.0), F3D_R(0.0));
      half = f3d_v3(p->size.x, p->size.x, p->size.x);
      break;
    case F3D_SHAPE_BOX:
      p->size = f3d_add(size, f3d_v3(r, r, r));
      half = f3d_v3(f3d_abs(c[0].x) * p->size.x + f3d_abs(c[1].x) * p->size.y +
                        f3d_abs(c[2].x) * p->size.z,
                    f3d_abs(c[0].y) * p->size.x + f3d_abs(c[1].y) * p->size.y +
                        f3d_abs(c[2].y) * p->size.z,
                    f3d_abs(c[0].z) * p->size.x + f3d_abs(c[1].z) * p->size.y +
                        f3d_abs(c[2].z) * p->size.z);
      break;
    case F3D_SHAPE_CAPSULE:
      p->size = f3d_v3(size.x + r, size.y, F3D_R(0.0));
      half = f3d_v3(f3d_abs(c[1].x) * p->size.y + p->size.x,
                    f3d_abs(c[1].y) * p->size.y + p->size.x,
                    f3d_abs(c[1].z) * p->size.y + p->size.x);
      break;
    case F3D_SHAPE_CYLINDER:
    case F3D_SHAPE_CONE: {
      /* A cone's height, all of it, along its axis, its centroid a quarter
       * of it above its base; a cylinder's half. */
      const int cone = kind == F3D_SHAPE_CONE;
      p->size = f3d_v3(size.x + r, size.y + r, F3D_R(0.0));
      const f3d_real along = cone ? F3D_R(0.5) * p->size.y : p->size.y;
      if (cone) centre = f3d_madd(at, c[1], F3D_R(0.25) * p->size.y);
      const f3d_real rad = p->size.x;
      half = f3d_v3(f3d_abs(c[1].x) * along + rad * f3d_sqrt(f3d_max(F3D_R(1.0) - c[1].x * c[1].x, F3D_R(0.0))),
                    f3d_abs(c[1].y) * along + rad * f3d_sqrt(f3d_max(F3D_R(1.0) - c[1].y * c[1].y, F3D_R(0.0))),
                    f3d_abs(c[1].z) * along + rad * f3d_sqrt(f3d_max(F3D_R(1.0) - c[1].z * c[1].z, F3D_R(0.0))));
      break;
    }
    case F3D_SHAPE_HULL: {
      if (hull == 0 || hull > world->s.hull_count) return 0;
      const F3dHull *h = &world->hulls[hull - 1u];
      p->size = f3d_v3(r, F3D_R(0.0), F3D_R(0.0));
      if (!make_room((void **)&scratch->planes, &scratch->plane_room,
                     ((size_t)*planes + h->triangle_count) * PLANE_REALS,
                     sizeof(f3d_real))) {
        return 0;
      }
      p->first_plane = *planes;
      p->plane_count = h->triangle_count;
      const f3d_real *v = world->hull_vertices + (size_t)h->first_vertex * 3u;
      const uint32_t *t = world->hull_triangles + (size_t)h->first_triangle * 3u;
      for (uint32_t k = 0; k < h->triangle_count; k++) {
        const f3d_real *a = v + 3u * t[3u * k], *b = v + 3u * t[3u * k + 1u],
                       *e = v + 3u * t[3u * k + 2u];
        const F3dVec3 va = f3d_v3(a[0], a[1], a[2]);
        const F3dVec3 n = f3d_cross(f3d_sub(f3d_v3(b[0], b[1], b[2]), va),
                                    f3d_sub(f3d_v3(e[0], e[1], e[2]), va));
        const f3d_real len = f3d_sqrt(f3d_dot(n, n));
        f3d_real *q = scratch->planes + (size_t)(*planes + k) * PLANE_REALS;
        if (!(len > F3D_R(0.0))) {
          q[0] = q[1] = q[2] = q[4] = F3D_R(0.0);
          q[3] = F3D_R(1.0);
          continue;
        }
        F3dVec3 unit = f3d_scale(n, F3D_R(1.0) / len);
        f3d_real dist = f3d_dot(unit, va);
        /* Outward: its centre of mass, the origin, is inside. */
        if (dist < F3D_R(0.0)) {
          unit = f3d_scale(unit, F3D_R(-1.0));
          dist = -dist;
        }
        q[0] = unit.x;
        q[1] = unit.y;
        q[2] = unit.z;
        q[3] = dist + r;
        q[4] = F3D_R(0.5) * len;
      }
      *planes += h->triangle_count;
      /* Its box from its corners where they stand. */
      f3d_real lo[3] = {F3D_R(1e30), F3D_R(1e30), F3D_R(1e30)};
      f3d_real hi[3] = {F3D_R(-1e30), F3D_R(-1e30), F3D_R(-1e30)};
      for (uint32_t k = 0; k < h->vertex_count; k++) {
        const F3dVec3 wv = out_of(&p->axes, f3d_v3(v[3u * k], v[3u * k + 1u], v[3u * k + 2u]));
        lo[0] = f3d_min(lo[0], wv.x);
        hi[0] = f3d_max(hi[0], wv.x);
        lo[1] = f3d_min(lo[1], wv.y);
        hi[1] = f3d_max(hi[1], wv.y);
        lo[2] = f3d_min(lo[2], wv.z);
        hi[2] = f3d_max(hi[2], wv.z);
      }
      p->lo_x = at.x + lo[0] - r;
      p->hi_x = at.x + hi[0] + r;
      p->lo_y = at.y + lo[1] - r;
      p->hi_y = at.y + hi[1] + r;
      p->lo_z = at.z + lo[2] - r;
      p->hi_z = at.z + hi[2] + r;
      return 1;
    }
    default:
      return 0;
  }
  p->lo_x = centre.x - half.x;
  p->hi_x = centre.x + half.x;
  p->lo_y = centre.y - half.y;
  p->hi_y = centre.y + half.y;
  p->lo_z = centre.z - half.z;
  p->hi_z = centre.z + half.z;
  return 1;
}

/* The line o + t·d against the slab |x| ≤ h of one axis, narrowing
 * [t0, t1]; 0 when it misses. */
static int slab(f3d_real o, f3d_real d, f3d_real h, f3d_real *t0, f3d_real *t1) {
  if (f3d_abs(d) < F3D_R(1e-9)) return f3d_abs(o) <= h;
  f3d_real a = (-h - o) / d, b = (h - o) / d;
  if (a > b) {
    const f3d_real s = a;
    a = b;
    b = s;
  }
  *t0 = f3d_max(*t0, a);
  *t1 = f3d_min(*t1, b);
  return *t0 < *t1;
}

/* The line o + t·d, d a unit, against a ball of radius r about c: the
 * stretch of t inside it, or 0. */
static int ball(F3dVec3 o, F3dVec3 d, F3dVec3 c, f3d_real r, f3d_real *t0,
                f3d_real *t1) {
  const F3dVec3 e = f3d_sub(o, c);
  const f3d_real b = f3d_dot(e, d), q = f3d_dot(e, e) - r * r;
  const f3d_real disc = b * b - q;
  if (!(disc > F3D_R(0.0))) return 0;
  const f3d_real s = f3d_sqrt(disc);
  *t0 = -b - s;
  *t1 = -b + s;
  return 1;
}

/* Against the infinite round tube of radius r about the local y axis,
 * narrowing [t0, t1]. */
static int tube(F3dVec3 o, F3dVec3 d, f3d_real r, f3d_real *t0, f3d_real *t1) {
  const f3d_real a = d.x * d.x + d.z * d.z;
  const f3d_real b = F3D_R(2.0) * (o.x * d.x + o.z * d.z);
  const f3d_real q = o.x * o.x + o.z * o.z - r * r;
  if (a < F3D_R(1e-12)) return q < F3D_R(0.0);
  const f3d_real disc = b * b - F3D_R(4.0) * a * q;
  if (!(disc > F3D_R(0.0))) return 0;
  const f3d_real s = f3d_sqrt(disc);
  *t0 = f3d_max(*t0, (-b - s) / (F3D_R(2.0) * a));
  *t1 = f3d_min(*t1, (-b + s) / (F3D_R(2.0) * a));
  return *t0 < *t1;
}

/* Where the vertical line through (x, z) over the water's origin passes
 * through [p]: its lowest and highest heights over the origin, or 0. */
static int chord(const Piece *p, const f3d_real *planes, f3d_real x, f3d_real z,
                 f3d_real *lo, f3d_real *hi) {
  const F3dVec3 rel = f3d_v3(x - p->at.x, F3D_R(0.0), z - p->at.z);
  const F3dVec3 o = into(&p->axes, rel);
  const F3dVec3 d = p->up;
  const f3d_real far = F3D_R(1e30);
  f3d_real t0 = -far, t1 = far;
  switch (p->kind) {
    case F3D_SHAPE_SPHERE: {
      const f3d_real q = p->size.x * p->size.x - rel.x * rel.x - rel.z * rel.z;
      if (!(q > F3D_R(0.0))) return 0;
      t1 = f3d_sqrt(q);
      t0 = -t1;
      break;
    }
    case F3D_SHAPE_BOX:
      if (!slab(o.x, d.x, p->size.x, &t0, &t1) || !slab(o.y, d.y, p->size.y, &t0, &t1) ||
          !slab(o.z, d.z, p->size.z, &t0, &t1)) {
        return 0;
      }
      break;
    case F3D_SHAPE_CYLINDER:
      if (!tube(o, d, p->size.x, &t0, &t1) || !slab(o.y, d.y, p->size.y, &t0, &t1)) return 0;
      break;
    case F3D_SHAPE_CAPSULE: {
      /* Convex: the stretch from the first of its three parts the line
       * meets to the last. */
      f3d_real a0 = far, a1 = -far, b0, b1;
      f3d_real c0 = -far, c1 = far;
      if (tube(o, d, p->size.x, &c0, &c1) && slab(o.y, d.y, p->size.y, &c0, &c1)) {
        a0 = c0;
        a1 = c1;
      }
      for (int end = -1; end <= 1; end += 2) {
        if (ball(o, d, f3d_v3(F3D_R(0.0), (f3d_real)end * p->size.y, F3D_R(0.0)),
                 p->size.x, &b0, &b1)) {
          a0 = f3d_min(a0, b0);
          a1 = f3d_max(a1, b1);
        }
      }
      if (!(a1 > a0)) return 0;
      t0 = a0;
      t1 = a1;
      break;
    }
    case F3D_SHAPE_CONE: {
      /* Its base a quarter of its height below its origin, its apex three
       * quarters above: inside where the distance from its axis is under
       * k·(apex − y), k = r/h, and above its base. */
      const f3d_real h = p->size.y, k = p->size.x / h, apex = F3D_R(0.75) * h;
      if (!slab(o.y - F3D_R(0.25) * h, d.y, F3D_R(0.5) * h, &t0, &t1)) return 0;
      const f3d_real k2 = k * k, ay = apex - o.y;
      const f3d_real a = d.x * d.x + d.z * d.z - k2 * d.y * d.y;
      const f3d_real b = F3D_R(2.0) * (o.x * d.x + o.z * d.z + k2 * ay * d.y);
      const f3d_real q = o.x * o.x + o.z * o.z - k2 * ay * ay;
      f3d_real s0 = far, s1 = -far;
      if (f3d_abs(a) < F3D_R(1e-12)) {
        if (f3d_abs(b) < F3D_R(1e-12)) {
          if (q > F3D_R(0.0)) return 0;
          s0 = t0;
          s1 = t1;
        } else if (b > F3D_R(0.0)) {
          s0 = t0;
          s1 = f3d_min(t1, -q / b);
        } else {
          s0 = f3d_max(t0, -q / b);
          s1 = t1;
        }
      } else {
        const f3d_real disc = b * b - F3D_R(4.0) * a * q;
        if (disc < F3D_R(0.0)) {
          if (a > F3D_R(0.0)) return 0;
          s0 = t0;
          s1 = t1;
        } else {
          const f3d_real sq = f3d_sqrt(disc);
          f3d_real r0 = (-b - sq) / (F3D_R(2.0) * a), r1 = (-b + sq) / (F3D_R(2.0) * a);
          if (r0 > r1) {
            const f3d_real sw = r0;
            r0 = r1;
            r1 = sw;
          }
          if (a > F3D_R(0.0)) {
            s0 = f3d_max(t0, r0);
            s1 = f3d_min(t1, r1);
          } else {
            /* Through both nappes: the slab keeps the one below the apex. */
            if (t0 < f3d_min(t1, r0)) {
              s0 = t0;
              s1 = f3d_min(t1, r0);
            }
            if (f3d_max(t0, r1) < t1) {
              s0 = f3d_min(s0, f3d_max(t0, r1));
              s1 = f3d_max(s1, t1);
            }
          }
        }
      }
      if (!(s1 > s0)) return 0;
      t0 = s0;
      t1 = s1;
      break;
    }
    case F3D_SHAPE_HULL:
      for (uint32_t k = 0; k < p->plane_count; k++) {
        const f3d_real *q = planes + (size_t)(p->first_plane + k) * PLANE_REALS;
        const F3dVec3 n = f3d_v3(q[0], q[1], q[2]);
        const f3d_real nd = f3d_dot(n, d), no = f3d_dot(n, o);
        if (f3d_abs(nd) < F3D_R(1e-12)) {
          if (no > q[3]) return 0;
          continue;
        }
        const f3d_real t = (q[3] - no) / nd;
        if (nd < F3D_R(0.0)) {
          t0 = f3d_max(t0, t);
        } else {
          t1 = f3d_min(t1, t);
        }
        if (!(t0 < t1)) return 0;
      }
      break;
    default:
      return 0;
  }
  if (!(t1 > t0)) return 0;
  *lo = p->at.y + t0;
  *hi = p->at.y + t1;
  return 1;
}

/* The area [p] shows a flow coming along [dir], a unit in its own frame:
 * a convex shape's projection, half of Σ|n·d|·A over its faces (Cauchy) —
 * exact for a ball, a box, a cylinder and a hull; for a capsule its
 * cylinder's and a ball's; for a cone its base's and its side's
 * triangle's, which bounds the true outline from above. */
static f3d_real facing_area(const Piece *p, const f3d_real *planes, F3dVec3 dir) {
  const f3d_real side = f3d_sqrt(f3d_max(F3D_R(1.0) - dir.y * dir.y, F3D_R(0.0)));
  switch (p->kind) {
    case F3D_SHAPE_SPHERE:
      return F3D_PI * p->size.x * p->size.x;
    case F3D_SHAPE_BOX:
      return F3D_R(4.0) * (f3d_abs(dir.x) * p->size.y * p->size.z +
                           f3d_abs(dir.y) * p->size.x * p->size.z +
                           f3d_abs(dir.z) * p->size.x * p->size.y);
    case F3D_SHAPE_CYLINDER:
      return F3D_PI * p->size.x * p->size.x * f3d_abs(dir.y) +
             F3D_R(4.0) * p->size.x * p->size.y * side;
    case F3D_SHAPE_CAPSULE:
      return F3D_PI * p->size.x * p->size.x + F3D_R(4.0) * p->size.x * p->size.y * side;
    case F3D_SHAPE_CONE:
      return F3D_PI * p->size.x * p->size.x * f3d_abs(dir.y) + p->size.x * p->size.y * side;
    case F3D_SHAPE_HULL: {
      f3d_real a = F3D_R(0.0);
      for (uint32_t k = 0; k < p->plane_count; k++) {
        const f3d_real *q = planes + (size_t)(p->first_plane + k) * PLANE_REALS;
        a += q[4] * f3d_abs(q[0] * dir.x + q[1] * dir.y + q[2] * dir.z);
      }
      return F3D_R(0.5) * a;
    }
    default:
      return F3D_R(0.0);
  }
}

/* Splashes, by what strikes the water.
 *
 * A flat face (Peters, van der Meer and Gordillo, JFM 724, 2013, a disc
 * struck flat): the splash sheet's front runs out at 1.6 times the impact
 * speed, measured where the sheet slopes one in one; its rim breaks into
 * drops only past an impact Weber number ρRV²/σ of 140, and below that
 * falls back whole. The air caught under the face sets the drops' size,
 * the cut-off length R·t₀^(2/3), t₀ ≈ 0.03 the air cushion's time over R/V.
 *
 * A rounded body (Aristoff and Bush, JFM 619, 2009, spheres): a curtain
 * leaves straight up along the cavity's wall at 0.25 times the impact
 * speed (±75%), a sheet 0.14 of the radius thick, and only if its own
 * Weber number ρV₀²δ₀/(2σ) passes one, faster than surface tension pulls
 * its edge back; it breaks into drops 1.89 times its thickness, as a
 * sheet's edge does (Rayleigh). */
#define F3D_SPLASH_FLAT_SPEED F3D_R(1.6)
#define F3D_SPLASH_FLAT_WEBER F3D_R(140.0)
#define F3D_SPLASH_CUSHION F3D_R(0.03)
#define F3D_SPLASH_CURTAIN_SPEED F3D_R(0.25)
#define F3D_SPLASH_CURTAIN_THICK F3D_R(0.14)

/* Whether [p] meets the water with a flat face: the face of it most
 * nearly facing down, tilted so little that its far edge comes in no
 * later than the air under it is squeezed out — 2R·tan θ within the
 * cut-off length R·t₀^(2/3). That face's radius, as a disc of its area,
 * into [radius]. A ball and a capsule have none. */
static int flat_face(const Piece *p, const f3d_real *planes, f3d_real *radius) {
  const F3dVec3 down = f3d_scale(p->up, F3D_R(-1.0));
  f3d_real best = F3D_R(0.0), area = F3D_R(0.0);
  switch (p->kind) {
    case F3D_SHAPE_BOX: {
      const f3d_real faces[3] = {F3D_R(4.0) * p->size.y * p->size.z,
                                 F3D_R(4.0) * p->size.x * p->size.z,
                                 F3D_R(4.0) * p->size.x * p->size.y};
      const f3d_real along[3] = {f3d_abs(down.x), f3d_abs(down.y), f3d_abs(down.z)};
      for (int k = 0; k < 3; k++) {
        if (along[k] > best) {
          best = along[k];
          area = faces[k];
        }
      }
      break;
    }
    case F3D_SHAPE_CYLINDER:
      best = f3d_abs(down.y);
      area = F3D_PI * p->size.x * p->size.x;
      break;
    case F3D_SHAPE_HULL:
      for (uint32_t k = 0; k < p->plane_count; k++) {
        const f3d_real *q = planes + (size_t)(p->first_plane + k) * PLANE_REALS;
        const f3d_real c = q[0] * down.x + q[1] * down.y + q[2] * down.z;
        if (c > best) {
          best = c;
          area = q[4];
        }
      }
      break;
    default:
      return 0;
  }
  if (!(best > F3D_R(0.0) && area > F3D_R(0.0))) return 0;
  *radius = f3d_sqrt(area / F3D_PI);
  const f3d_real tilt = f3d_sqrt(f3d_max(F3D_R(1.0) - best * best, F3D_R(0.0))) / best;
  return F3D_R(2.0) * tilt <= power(F3D_SPLASH_CUSHION, F3D_R(2.0) / F3D_R(3.0));
}

/* Carlson's symmetric elliptic integral R_D(x, y, z), by his duplication:
 * each round brings the three a quarter nearer each other, and twenty-four
 * leave them equal to every bit a float holds. */
static f3d_real carlson_rd(f3d_real x, f3d_real y, f3d_real z) {
  f3d_real sum = F3D_R(0.0), fac = F3D_R(1.0);
  for (int i = 0; i < 24; i++) {
    const f3d_real sx = f3d_sqrt(x), sy = f3d_sqrt(y), sz = f3d_sqrt(z);
    const f3d_real lam = sx * sy + sx * sz + sy * sz;
    sum += fac / (sz * (z + lam));
    fac *= F3D_R(0.25);
    x = F3D_R(0.25) * (x + lam);
    y = F3D_R(0.25) * (y + lam);
    z = F3D_R(0.25) * (z + lam);
  }
  const f3d_real mu = (x + y + F3D_R(3.0) * z) / F3D_R(5.0);
  return F3D_R(3.0) * sum + fac / (mu * f3d_sqrt(mu));
}

/* The water a piece must carry with it to speed up, as a share of what it
 * displaces: that of the ellipsoid of its proportions, moving along each of
 * its axes in turn (Lamb, Hydrodynamics §115: k = α/(2 − α), α the axis's
 * integral, (2/3)·abc·R_D in Carlson's form), the mean of the three — a
 * ball's 1/2, a long rod's two thirds, a thin disc's far more. */
static f3d_real carried_share(const Piece *p) {
  F3dVec3 h;
  switch (p->kind) {
    case F3D_SHAPE_SPHERE:
      return F3D_R(0.5);
    case F3D_SHAPE_BOX:
      h = p->size;
      break;
    case F3D_SHAPE_CAPSULE:
      h = f3d_v3(p->size.x, p->size.y + p->size.x, p->size.x);
      break;
    case F3D_SHAPE_CYLINDER:
      h = f3d_v3(p->size.x, p->size.y, p->size.x);
      break;
    case F3D_SHAPE_CONE:
      h = f3d_v3(p->size.x, F3D_R(0.5) * p->size.y, p->size.x);
      break;
    default:
      /* A hull: the half of its box where it stands. */
      h = f3d_v3(F3D_R(0.5) * (p->hi_x - p->lo_x), F3D_R(0.5) * (p->hi_y - p->lo_y),
                 F3D_R(0.5) * (p->hi_z - p->lo_z));
      break;
  }
  const f3d_real big = f3d_max(h.x, f3d_max(h.y, h.z));
  if (!(big > F3D_R(0.0))) return F3D_R(0.5);
  h = f3d_v3(f3d_max(h.x, F3D_R(1e-3) * big), f3d_max(h.y, F3D_R(1e-3) * big),
             f3d_max(h.z, F3D_R(1e-3) * big));
  const f3d_real abc = h.x * h.y * h.z;
  const f3d_real a2 = h.x * h.x, b2 = h.y * h.y, c2 = h.z * h.z;
  const f3d_real third = F3D_R(2.0) / F3D_R(3.0);
  const f3d_real ax = third * abc * carlson_rd(b2, c2, a2);
  const f3d_real ay = third * abc * carlson_rd(a2, c2, b2);
  const f3d_real az = third * abc * carlson_rd(a2, b2, c2);
  return (ax / (F3D_R(2.0) - ax) + ay / (F3D_R(2.0) - ay) + az / (F3D_R(2.0) - az)) /
         F3D_R(3.0);
}

/* The drag coefficient of a piece at Reynolds number [re], on the area of
 * a ball of its volume: a ball's by Schiller and Naumann,
 * 24/Re·(1 + 0.15·Re^0.687), Stokes's when slow, to Re = 1000 and
 * Newton's 0.44 past it; any other shape's by Haider and Levenspiel (1989)
 * from its sphericity φ, the surface of a ball of its volume over its
 * own. */
static f3d_real drag_coefficient(const Piece *p, f3d_real re) {
  if (!(re > F3D_R(0.0))) return F3D_R(0.0);
  if (p->kind == F3D_SHAPE_SPHERE) {
    return re < F3D_R(1000.0)
               ? F3D_R(24.0) / re * (F3D_R(1.0) + F3D_R(0.15) * power(re, F3D_R(0.687)))
               : F3D_R(0.44);
  }
  const f3d_real cr = cube_root(F3D_R(6.0) * p->volume);
  const f3d_real phi = f3d_min(
      F3D_R(1.0), cube_root(F3D_PI) * cr * cr / f3d_max(p->surface, F3D_R(1e-12)));
  const f3d_real p2 = phi * phi, p3 = p2 * phi;
  const f3d_real a = natural_exp(F3D_R(2.3288) - F3D_R(6.4581) * phi + F3D_R(2.4486) * p2);
  const f3d_real b = F3D_R(0.0964) + F3D_R(0.5565) * phi;
  const f3d_real c = natural_exp(F3D_R(4.905) - F3D_R(13.8944) * phi + F3D_R(18.4222) * p2 -
                                 F3D_R(10.2599) * p3);
  const f3d_real d = natural_exp(F3D_R(1.4681) + F3D_R(12.2584) * phi - F3D_R(20.7322) * p2 +
                                 F3D_R(15.8855) * p3);
  return F3D_R(24.0) / re * (F3D_R(1.0) + a * power(re, b)) + c / (F3D_R(1.0) + d / re);
}

/* The pieces of body [s] where it stands, into [scratch]; how many. */
static uint32_t pieces_of(const F3dWorld *world, Scratch *scratch, const F3dSlot *s,
                          F3dVec3 origin) {
  uint32_t count = 0, planes = 0;
  const F3dVec3 at = f3d_sub(s->position, origin);
  if (s->shape == F3D_SHAPE_COMPOUND) {
    if (s->hull == 0 || s->hull > world->s.compound_count) return 0;
    const F3dCompound *k = &world->compounds[s->hull - 1u];
    if (!make_room((void **)&scratch->pieces, &scratch->piece_room, k->part_count,
                   sizeof(Piece))) {
      return 0;
    }
    const F3dMat3 m = f3d_mat_of(s->orientation);
    for (uint32_t i = 0; i < k->part_count; i++) {
      const F3dCompoundPart *part = &world->compound_parts[k->first_part + i];
      if (piece_of(world, scratch, &planes, part->kind, part->size, part->rounding,
                   part->hull, f3d_add(at, out_of(&m, part->at)),
                   quat_mul(s->orientation, part->turn), &scratch->pieces[count])) {
        scratch->pieces[count].part = i;
        count++;
      }
    }
    return count;
  }
  if (!make_room((void **)&scratch->pieces, &scratch->piece_room, 1u, sizeof(Piece))) {
    return 0;
  }
  scratch->pieces[0].part = 0;
  return piece_of(world, scratch, &planes, s->shape, s->size, s->rounding, s->hull, at,
                  s->orientation, &scratch->pieces[0])
             ? 1u
             : 0u;
}

/* Reals a column of a body's box keeps: what it fills, its moment x y z,
 * and whether it is in the ring round it. */
#define COLUMN_REALS 5u

/* What the water's slope gives the bodies standing in it over a step:
 * which body fills each column most, and how much, and for each body the
 * push it has had x and z, N·s, and where it is held up, x y z over the
 * water's origin. */
#define SHOVE_REALS 5u
typedef struct Shove {
  uint32_t *owner;
  f3d_real *owned;
  f3d_real *push;
} Shove;

/* The volume bodies fill in each column, and what the water does to them:
 * held up by what they displace, dragged by the flow. Whether any of them
 * moves in it, into [stirring]. */
static void bodies_in(F3dWorld *world, Grid *g, F3dShallow water, f3d_real dt,
                      Shove *shove, int *stirring) {
  const F3dShallowSlot *w = g->slot;
  const f3d_real gd = gravity_down(world);
  const f3d_real rho = w->density;
  /* Last step's surface, before this step's bodies stand in it. */
  f3d_real *before = (f3d_real *)f3d_alloc((size_t)g->n * 2u * sizeof(f3d_real) + 8u);
  if (before == NULL) return;
  /* And what bodies filled of each column then. */
  f3d_real *was = before + g->n;
  f3d_real lowest = F3D_R(1e30), highest = F3D_R(-1e30);
  for (uint32_t c = 0; c < g->n; c++) {
    before[c] = surface(g, c);
    was[c] = g->filled[c];
    g->filled[c] = F3D_R(0.0);
    lowest = f3d_min(lowest, g->ground[c]);
    if (g->depth[c] > F3D_SHALLOW_DRY || was[c] > F3D_R(0.0)) highest = f3d_max(highest, before[c]);
  }
  /* What it found standing in it last step, measured again from nothing. */
  for (uint32_t b = 0; b < world->s.used; b++) {
    if (world->slots[b].liquid == water) world->slots[b].was_wet = 1u;
  }
  dry_bodies(world, water);
  Scratch scratch;
  f3d_zero(&scratch, sizeof scratch);
  const f3d_real wide = (f3d_real)g->nx * g->cell, deep = (f3d_real)g->nz * g->cell;
  for (uint32_t b = 0; b < world->s.used; b++) {
    F3dSlot *s = &world->slots[b];
    if (!s->live || s->shape == F3D_SHAPE_POINT || s->shape == F3D_SHAPE_MESH) continue;
    const int dynamic = s->type == F3D_BODY_DYNAMIC && s->inverse_mass > F3D_R(0.0);
    const uint32_t count = pieces_of(world, &scratch, s, w->origin);
    if (count == 0) continue;
    Piece *pieces = scratch.pieces;
    f3d_real lo_x = F3D_R(1e30), hi_x = F3D_R(-1e30), lo_z = F3D_R(1e30), hi_z = F3D_R(-1e30);
    f3d_real lo_y = F3D_R(1e30), hi_y = F3D_R(-1e30), whole = F3D_R(0.0);
    for (uint32_t k = 0; k < count; k++) {
      lo_x = f3d_min(lo_x, pieces[k].lo_x);
      hi_x = f3d_max(hi_x, pieces[k].hi_x);
      lo_y = f3d_min(lo_y, pieces[k].lo_y);
      hi_y = f3d_max(hi_y, pieces[k].hi_y);
      lo_z = f3d_min(lo_z, pieces[k].lo_z);
      hi_z = f3d_max(hi_z, pieces[k].hi_z);
      whole += pieces[k].volume;
    }
    /* Clear of the water: beside the grid, above every surface in it, or
     * below all its ground. */
    if (hi_x < F3D_R(0.0) || hi_z < F3D_R(0.0) || lo_x > wide || lo_z > deep ||
        lo_y > highest || hi_y < lowest) {
      continue;
    }
    /* Its columns, and one more all round for the ring. */
    const int32_t ci0 = (int32_t)f3d_max(lo_x / g->cell - F3D_R(1.0), F3D_R(0.0));
    const int32_t cj0 = (int32_t)f3d_max(lo_z / g->cell - F3D_R(1.0), F3D_R(0.0));
    const int32_t ci1 = (int32_t)f3d_min(hi_x / g->cell + F3D_R(1.0), (f3d_real)(g->nx - 1u));
    const int32_t cj1 = (int32_t)f3d_min(hi_z / g->cell + F3D_R(1.0), (f3d_real)(g->nz - 1u));
    if (ci1 < ci0 || cj1 < cj0) continue;
    const uint32_t ni = (uint32_t)(ci1 - ci0 + 1), nj = (uint32_t)(cj1 - cj0 + 1);
    if (!make_room((void **)&scratch.columns, &scratch.column_room,
                   (size_t)ni * nj * COLUMN_REALS, sizeof(f3d_real)) ||
        !make_room((void **)&scratch.cells, &scratch.cell_room, (size_t)ni * nj,
                   sizeof(uint32_t))) {
      break;
    }
    f3d_real *cols = scratch.columns;
    f3d_zero(cols, (size_t)ni * nj * COLUMN_REALS * sizeof(f3d_real));
    /* The waterline's area and its moments, for how the surface's hold
     * stiffens as it sinks or heels. */
    f3d_real wa = F3D_R(0.0), wax = F3D_R(0.0), waz = F3D_R(0.0);
    f3d_real waxx = F3D_R(0.0), wazz = F3D_R(0.0);
    for (uint32_t k = 0; k < count; k++) {
      Piece *p = &pieces[k];
      p->under = F3D_R(0.0);
      if (p->lo_y > highest || p->hi_y < lowest) continue;
      /* Two points to a cell and sixteen across it at least, each the
       * middle of its share of the piece's box. */
      const f3d_real span_x = p->hi_x - p->lo_x, span_z = p->hi_z - p->lo_z;
      const uint32_t sx = (uint32_t)f3d_clamp(F3D_R(2.0) * span_x / g->cell + F3D_R(1.0),
                                              F3D_R(16.0), F3D_R(128.0));
      const uint32_t sz = (uint32_t)f3d_clamp(F3D_R(2.0) * span_z / g->cell + F3D_R(1.0),
                                              F3D_R(16.0), F3D_R(128.0));
      const f3d_real dx = span_x / (f3d_real)sx, dz = span_z / (f3d_real)sz;
      const f3d_real da = dx * dz;
      /* Its chords' sum, to scale the points to its own volume: what the
       * points miss of a round edge they make up evenly. */
      f3d_real full = F3D_R(0.0);
      for (uint32_t jz = 0; jz < sz; jz++) {
        const f3d_real z = p->lo_z + ((f3d_real)jz + F3D_R(0.5)) * dz;
        for (uint32_t ix = 0; ix < sx; ix++) {
          const f3d_real x = p->lo_x + ((f3d_real)ix + F3D_R(0.5)) * dx;
          f3d_real y0, y1;
          if (chord(p, scratch.planes, x, z, &y0, &y1)) full += (y1 - y0) * da;
        }
      }
      if (!(full > F3D_R(0.0))) continue;
      const f3d_real scale = p->volume / full;
      const f3d_real dv = da * scale;
      for (uint32_t jz = 0; jz < sz; jz++) {
        const f3d_real z = p->lo_z + ((f3d_real)jz + F3D_R(0.5)) * dz;
        if (z < F3D_R(0.0) || z >= deep) continue;
        const uint32_t j = (uint32_t)(z / g->cell);
        if (j >= g->nz) continue;
        for (uint32_t ix = 0; ix < sx; ix++) {
          const f3d_real x = p->lo_x + ((f3d_real)ix + F3D_R(0.5)) * dx;
          if (x < F3D_R(0.0) || x >= wide) continue;
          const uint32_t i = (uint32_t)(x / g->cell);
          if (i >= g->nx) continue;
          const uint32_t c = i + j * g->nx;
          if (walled(g, c)) continue;
          f3d_real y0, y1;
          if (!chord(p, scratch.planes, x, z, &y0, &y1)) continue;
          const f3d_real level = before[c];
          const f3d_real bottom = f3d_max(y0, g->ground[c]);
          const f3d_real top = f3d_min(y1, level);
          if (top > bottom) {
            const f3d_real v = dv * (top - bottom);
            f3d_real *col = cols + ((size_t)((int32_t)i - ci0) + (size_t)((int32_t)j - cj0) * ni) *
                                       COLUMN_REALS;
            col[0] += v;
            col[1] += v * x;
            col[2] += v * F3D_R(0.5) * (top + bottom);
            col[3] += v * z;
            p->under += v;
          }
          if (y0 < level && level < y1 && level > g->ground[c]) {
            const f3d_real a = da * scale;
            wa += a;
            wax += a * x;
            waz += a * z;
            waxx += a * x * x;
            wazz += a * z * z;
          }
        }
      }
    }
    /* No column gives more than the water it holds and what the bodies
     * filled of it last step: a body cannot displace water that is not
     * there. */
    f3d_real displaced = F3D_R(0.0), drawn = F3D_R(0.0);
    F3dVec3 moment = f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
    for (uint32_t l = 0; l < ni * nj; l++) {
      f3d_real *col = cols + (size_t)l * COLUMN_REALS;
      if (!(col[0] > F3D_R(0.0))) continue;
      const uint32_t c = (uint32_t)(ci0 + (int32_t)(l % ni)) +
                         (uint32_t)(cj0 + (int32_t)(l / ni)) * g->nx;
      drawn += col[0];
      const f3d_real held = g->depth[c] * g->area + was[c];
      if (col[0] > held) {
        const f3d_real k = held / col[0];
        for (uint32_t m = 0; m < 4u; m++) col[m] *= k;
      }
      displaced += col[0];
      moment = f3d_add(moment, f3d_v3(col[1], col[2], col[3]));
    }
    if (!(displaced > F3D_R(0.0))) continue;
    for (uint32_t k = 0; k < count; k++) pieces[k].under *= displaced / drawn;
    /* The middle of what is under water: where the water holds it up. */
    const F3dVec3 middle = f3d_scale(moment, F3D_R(1.0) / displaced);
    /* The ring: wet columns next to those it stands in, where what it
     * pushes aside goes. */
    uint32_t rings = 0;
    for (uint32_t l = 0; l < ni * nj; l++) {
      if (!(cols[(size_t)l * COLUMN_REALS] > F3D_R(0.0))) continue;
      const int32_t li = (int32_t)(l % ni), lj = (int32_t)(l / ni);
      for (int32_t dj = -1; dj <= 1; dj++) {
        for (int32_t di = -1; di <= 1; di++) {
          const int32_t ii = li + di, jj = lj + dj;
          if (ii < 0 || jj < 0 || ii >= (int32_t)ni || jj >= (int32_t)nj) continue;
          f3d_real *n = cols + ((size_t)ii + (size_t)jj * ni) * COLUMN_REALS;
          if (n[0] > F3D_R(0.0) || n[4] != F3D_R(0.0)) continue;
          const uint32_t c = (uint32_t)(ci0 + ii) + (uint32_t)(cj0 + jj) * g->nx;
          if (!wet(g, c)) continue;
          n[4] = F3D_R(1.0);
          rings++;
        }
      }
    }
    /* Where it stands in the water, for the waves; and what it pushes
     * aside, for the ring. */
    f3d_real pushed = F3D_R(0.0);
    F3dVec3 carried = f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
    uint32_t ring_count = 0;
    for (uint32_t l = 0; l < ni * nj; l++) {
      const f3d_real *col = cols + (size_t)l * COLUMN_REALS;
      const uint32_t c = (uint32_t)(ci0 + (int32_t)(l % ni)) +
                         (uint32_t)(cj0 + (int32_t)(l / ni)) * g->nx;
      if (col[0] > F3D_R(0.0)) stand(g, was, c, col[0], rings > 0, &pushed, &carried);
      if (col[4] != F3D_R(0.0)) scratch.cells[ring_count++] = c;
    }
    /* The water round it: its columns and the ring. */
    f3d_real water_mass = F3D_R(0.0);
    for (uint32_t l = 0; l < ni * nj; l++) {
      const f3d_real *col = cols + (size_t)l * COLUMN_REALS;
      if (!(col[0] > F3D_R(0.0)) && col[4] == F3D_R(0.0)) continue;
      const uint32_t c = (uint32_t)(ci0 + (int32_t)(l % ni)) +
                         (uint32_t)(cj0 + (int32_t)(l / ni)) * g->nx;
      if (wet(g, c)) water_mass += rho * g->depth[c] * g->area;
    }
    /* Coming in faster than a wave can carry the water away from it,
     * √(g·r), r the radius of a ball of its volume, it throws what the
     * waves cannot take up as a crown: the share 1 − c/v of what it pushed
     * aside leaves the ring as spray, the rest goes into the ring. How the
     * spray leaves is the splash law of the face its lowest piece meets
     * the water with: a flat face's sheet out at 1.6 v, one in one, broken
     * into drops past We 140; a rounded body's curtain straight up at
     * 0.25 v, while it holds together against surface tension. */
    const f3d_real r = cube_root(whole * F3D_R(3.0) / (F3D_R(4.0) * F3D_PI));
    const f3d_real wave = f3d_sqrt(gd * r);
    const f3d_real in = -s->velocity.y;
    f3d_real crown = F3D_R(0.0), thrown = F3D_R(0.0), rise = F3D_R(1.0), out = F3D_R(0.0);
    f3d_real drop = F3D_R(0.0);
    if (gd > F3D_R(0.0) && in > wave && pushed > F3D_R(0.0)) {
      uint32_t low = 0;
      for (uint32_t k = 1; k < count; k++) {
        if (pieces[k].lo_y < pieces[low].lo_y) low = k;
      }
      f3d_real face = F3D_R(0.0);
      if (flat_face(&pieces[low], scratch.planes, &face)) {
        if (rho * face * in * in / w->tension > F3D_SPLASH_FLAT_WEBER) {
          thrown = F3D_SPLASH_FLAT_SPEED * in;
          rise = out = F3D_R(0.70710678118654752);
          drop = face * power(F3D_SPLASH_CUSHION, F3D_R(2.0) / F3D_R(3.0));
        }
      } else {
        const f3d_real v0 = F3D_SPLASH_CURTAIN_SPEED * in;
        const f3d_real sheet = F3D_SPLASH_CURTAIN_THICK * r;
        if (rho * v0 * v0 * sheet / (F3D_R(2.0) * w->tension) > F3D_R(1.0)) {
          thrown = v0;
          drop = F3D_R(1.89) * sheet;
        }
      }
      if (thrown > F3D_R(0.0)) crown = pushed * (F3D_R(1.0) - wave / in);
    }
    const f3d_real kept = pushed - crown;
    /* What goes into the ring keeps the flow it had: each ring column's
     * flow becomes the mix of its own and what came in, by volume. */
    const F3dVec3 came = pushed > F3D_R(0.0) ? f3d_scale(carried, F3D_R(1.0) / pushed)
                                             : f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
    for (uint32_t k = 0; k < ring_count; k++) {
      const uint32_t c = scratch.cells[k];
      const f3d_real added = kept / ((f3d_real)ring_count * g->area);
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
      throw_drops(world, g, water, at,
                  f3d_v3(away.x * out * thrown, rise * thrown, away.z * out * thrown),
                  crown / (f3d_real)ring_count, drop, c);
    }
    /* Pushed along the surface (Froude and Krylov), in the substeps: the
     * columns it fills more than any other body are its, and what the
     * water's slope across their faces gives the water, the body gets back.
     * Dynamic bodies only: nothing moves the rest. */
    if (dynamic && shove != NULL) {
      for (uint32_t l = 0; l < ni * nj; l++) {
        const f3d_real f_here = cols[(size_t)l * COLUMN_REALS];
        if (!(f_here > F3D_R(0.0))) continue;
        const uint32_t c = (uint32_t)(ci0 + (int32_t)(l % ni)) +
                           (uint32_t)(cj0 + (int32_t)(l / ni)) * g->nx;
        if (f_here > shove->owned[c]) {
          shove->owned[c] = f_here;
          shove->owner[c] = b + 1u;
        }
      }
      f3d_real *mine = shove->push + (size_t)b * SHOVE_REALS;
      mine[0] = mine[1] = F3D_R(0.0);
      mine[2] = middle.x;
      mine[3] = middle.y;
      mine[4] = middle.z;
    }
    /* Dragged: by the flow against how it moves through it at the middle
     * of what is under water, ½ρ·C_d·A·|Δv|·Δv over the area each piece
     * shows the flow — the area of a ball of its volume, as C_d is taken
     * on, by its outline that way over its mean outline, a quarter of its
     * surface (Cauchy) — and the share of it under water. Taken implicitly
     * with the water round it, the body and the water each moved by what
     * the other gives: Δv' = Δv / (1 + k·dt), k = c·(1/M + 1/m_w). */
    const F3dVec3 g_at = f3d_sub(s->position, w->origin);
    const F3dVec3 arm = f3d_sub(middle, g_at);
    const F3dVec3 flow = f3d_v3(flow_x(g, middle.x / g->cell, middle.z / g->cell),
                                F3D_R(0.0),
                                flow_z(g, middle.x / g->cell, middle.z / g->cell));
    const F3dVec3 moving = f3d_add(s->velocity, f3d_cross(s->spin, arm));
    const F3dVec3 rel = f3d_sub(moving, flow);
    const f3d_real speed = f3d_sqrt(f3d_dot(rel, rel));
    /* What of it stands in this water, for heat and the game: the water it
     * stands deepest in, where waters overlap; each part's share for a
     * compound's. Come in from none, it is wetted. */
    if (displaced > s->submerged) {
      if (s->liquid == 0 && !s->was_wet) f3d_push_event(world, f3d_handle_of(world, s), F3D_EVENT_WETTED);
      s->submerged = displaced;
      s->liquid = water;
      s->liquid_speed = speed;
      F3dLump *l = lumps_in(world, s);
      for (uint32_t k = 0; l != NULL && k < count; k++) {
        const Piece *p = &pieces[k];
        if (p->part < s->lump_count && p->volume > F3D_R(0.0)) {
          l[p->part].immersed = f3d_clamp(p->under / p->volume, F3D_R(0.0), F3D_R(1.0));
        }
      }
    }
    f3d_real share_carried = F3D_R(0.0);
    f3d_real hold = F3D_R(0.0);
    for (uint32_t k = 0; k < count; k++) {
      const Piece *p = &pieces[k];
      if (!(p->under > F3D_R(0.0))) continue;
      share_carried += carried_share(p) * p->under;
      if (!(speed > F3D_R(0.0))) continue;
      const F3dVec3 dir = into(&p->axes, f3d_scale(rel, F3D_R(1.0) / speed));
      const f3d_real dv = cube_root(F3D_R(6.0) * p->volume / F3D_PI);
      const f3d_real re = rho * speed * dv / w->viscosity;
      const f3d_real facing = facing_area(p, scratch.planes, dir);
      const f3d_real mean_outline = F3D_R(0.25) * p->surface;
      if (!(mean_outline > F3D_R(0.0))) continue;
      const f3d_real area = F3D_R(0.25) * F3D_PI * dv * dv * facing / mean_outline;
      hold += F3D_R(0.5) * rho * drag_coefficient(p, re) * area *
              f3d_min(p->under / p->volume, F3D_R(1.0)) * speed;
    }
    const f3d_real added = rho * share_carried;
    const f3d_real mass = dynamic ? F3D_R(1.0) / s->inverse_mass + added : F3D_R(0.0);
    const f3d_real give = (dynamic ? F3D_R(1.0) / mass : F3D_R(0.0)) +
                          (water_mass > F3D_R(0.0) ? F3D_R(1.0) / water_mass : F3D_R(0.0));
    /* Held up: the weight of the water it displaces, against gravity, at
     * the middle of what is under water; and pushed along the surface. */
    const F3dVec3 lift = f3d_v3(F3D_R(0.0), rho * gd * displaced, F3D_R(0.0));
    /* The drag at the end of the step, on the speed through the water
     * everything else on the body has brought it to by then — so a body
     * falls through honey at the speed its drag balances, not beside it. */
    F3dVec3 ahead = rel;
    if (dynamic) {
      const F3dVec3 pull = f3d_add(f3d_add(s->force, lift),
                                   f3d_scale(world->s.gravity, F3D_R(1.0) / s->inverse_mass));
      ahead = f3d_madd(ahead, pull, dt / mass);
    }
    const F3dVec3 impulse =
        f3d_scale(ahead, -hold * dt / (F3D_R(1.0) + hold * dt * give));
    /* The water pushed back as hard: the impulse's reverse, along the flow,
     * into the water round it — the columns it stands in and the ring its
     * displaced water went to — alike, so a body driven through water sets
     * it moving, a wake behind it, and water running past a pier slows. */
    if (water_mass > F3D_R(0.0) && hold > F3D_R(0.0)) {
      const F3dVec3 dw = f3d_scale(impulse, F3D_R(-1.0) / water_mass);
      for (uint32_t l = 0; l < ni * nj; l++) {
        const f3d_real *col = cols + (size_t)l * COLUMN_REALS;
        if (!(col[0] > F3D_R(0.0)) && col[4] == F3D_R(0.0)) continue;
        const uint32_t c = (uint32_t)(ci0 + (int32_t)(l % ni)) +
                           (uint32_t)(cj0 + (int32_t)(l / ni)) * g->nx;
        if (wet(g, c)) push_column(g, c, dw);
      }
    }
    const f3d_real stir = f3d_dot(s->velocity, s->velocity) + f3d_dot(s->spin, s->spin) * r * r;
    if (!dynamic) {
      if (stir > F3D_R(0.0)) *stirring = 1;
      continue;
    }
    F3dVec3 force = f3d_add(lift, f3d_scale(impulse, F3D_R(1.0) / dt));
    F3dVec3 torque = f3d_cross(arm, force);
    /* The surface's hold stiffens as it sinks, by ρg times its waterline's
     * area, and as it heels, by ρg·(I + V·(z_B − z_G)), I its waterline's
     * second moment — ρgV times its metacentric height. Taken implicitly,
     * as where it will be at the end of the step, Δv = (F − K·dt·v')·dt/M:
     * stable however stiff the hold or light the body. */
    if (wa > F3D_R(0.0)) {
      const f3d_real k_heave = rho * gd * wa;
      const f3d_real m_body = F3D_R(1.0) / s->inverse_mass;
      const f3d_real v_next =
          (s->velocity.y + dt * (m_body * world->s.gravity.y + s->force.y + force.y) / mass) /
          (F3D_R(1.0) + k_heave * dt * dt / mass);
      force.y -= k_heave * dt * v_next;
      const F3dSym3 inv = f3d_sym_turned(s->orientation, s->inverse_inertia);
      const f3d_real fx = wax / wa, fz = waz / wa;
      const f3d_real rise_b = middle.y - g_at.y;
      const f3d_real k_roll = rho * gd * f3d_max(wazz - wa * fz * fz + displaced * rise_b, F3D_R(0.0));
      const f3d_real k_pitch = rho * gd * f3d_max(waxx - wa * fx * fx + displaced * rise_b, F3D_R(0.0));
      const F3dVec3 spun = f3d_sym_times(inv, f3d_add(s->torque, torque));
      if (inv.xx > F3D_R(0.0) && k_roll > F3D_R(0.0)) {
        const f3d_real wx = (s->spin.x + dt * spun.x) / (F3D_R(1.0) + k_roll * dt * dt * inv.xx);
        torque.x -= k_roll * dt * wx;
      }
      if (inv.zz > F3D_R(0.0) && k_pitch > F3D_R(0.0)) {
        const f3d_real wz = (s->spin.z + dt * spun.z) / (F3D_R(1.0) + k_pitch * dt * dt * inv.zz);
        torque.z -= k_pitch * dt * wz;
      }
    }
    /* The water round it moves with it as it speeds up: on its inertia,
     * in the integrator, where it holds for a body as light as a bubble. */
    s->added_mass += added;
    s->force = f3d_add(s->force, force);
    s->torque = f3d_add(s->torque, torque);
    /* Asleep, it wakes when what the water does would move it past the
     * speed it sleeps under in the time it takes to fall asleep. */
    if (s->flags & F3D_FLAG_ASLEEP) {
      F3dVec3 net = force;
      net.y += s->force.y - force.y + world->s.gravity.y / s->inverse_mass;
      const f3d_real a = f3d_sqrt(f3d_dot(net, net)) / mass;
      if (a * world->s.sleep_time > world->s.sleep_speed || speed > world->s.sleep_speed) {
        f3d_wake(world, s);
      }
    }
    if (!(s->flags & F3D_FLAG_ASLEEP) && stir > world->s.sleep_speed * world->s.sleep_speed) {
      *stirring = 1;
    }
  }
  for (uint32_t b = 0; b < world->s.used; b++) world->slots[b].was_wet = 0;
  f3d_free(scratch.planes);
  f3d_free(scratch.pieces);
  f3d_free(scratch.columns);
  f3d_free(scratch.cells);
  f3d_free(before);
}

/* ------------------------------------------------------------ the faces */

/* What crossed each face onto a drop over a step: its volume, its push and
 * the column it left, the faces x first then z. */
typedef struct Lip {
  f3d_real *volume;
  F3dVec3 *push;
  uint32_t *from;
} Lip;

/* The depth that crosses a face from column [from] to [to], −1 off the
 * grid: the water standing above the higher of their beds (hydrostatic
 * reconstruction, Audusse and colleagues, 2004), no more than there is. */
static f3d_real crossing(const Grid *g, uint32_t from, int32_t to) {
  const f3d_real d = g->depth[from];
  if (to < 0) return d;
  const f3d_real bed = f3d_max(g->ground[from], g->ground[(uint32_t)to]);
  return f3d_clamp(surface(g, from) - bed, F3D_R(0.0), d);
}

/* Whether the face from [from] to [to] is a free overfall: the ground falls
 * away and the surface beyond is below the lip, so nothing downstream holds
 * the water back. */
static int brink(const Grid *g, uint32_t from, uint32_t to) {
  return g->ground[from] > g->ground[to] && surface(g, to) < g->ground[from];
}

/* The cell inside edge face [f] of [axis], and the side of the grid it is
 * on: 0 and 1 for x's ends, 2 and 3 for z's. */
static uint32_t edge_cell(const Grid *g, int axis, uint32_t i, uint32_t j, uint32_t *side) {
  if (axis == 0) {
    *side = i == 0 ? 0u : 1u;
    return i == 0 ? j * g->nx : g->nx - 1u + j * g->nx;
  }
  *side = j == 0 ? 2u : 3u;
  return j == 0 ? i : i + (g->nz - 1u) * g->nx;
}

/* Each edge's weight: the conveyance h^(5/3) of its wet cells, or, where
 * it is all dry, how many cells it has that are not walls — negative so
 * the faces know to share alike. */
static void edge_weights(const Grid *g, f3d_real *weights) {
  for (uint32_t side = 0; side < 4u; side++) {
    f3d_real sum = F3D_R(0.0), cells = F3D_R(0.0);
    const uint32_t along = side < 2u ? g->nz : g->nx;
    for (uint32_t k = 0; k < along; k++) {
      uint32_t s;
      const uint32_t c = side < 2u ? edge_cell(g, 0, side == 0 ? 0u : g->nx, k, &s)
                                   : edge_cell(g, 1, k, side == 2u ? 0u : g->nz, &s);
      if (walled(g, c)) continue;
      cells += F3D_R(1.0);
      const f3d_real h = g->depth[c];
      if (h > F3D_SHALLOW_DRY) {
        const f3d_real r = cube_root(h);
        sum += h * r * r;
      }
    }
    weights[side] = sum > F3D_R(0.0) ? sum : -cells;
  }
}

/* The discharge through edge cell [c] of [side], m³/s, in positive. */
static f3d_real edge_share(const Grid *g, const f3d_real *weights, uint32_t side, uint32_t c) {
  const f3d_real total = g->slot->edge_value[side];
  if (walled(g, c)) return F3D_R(0.0);
  if (weights[side] < F3D_R(0.0)) {
    /* Dry: what comes in spreads alike, and nothing goes out. */
    return total > F3D_R(0.0) ? total / -weights[side] : F3D_R(0.0);
  }
  const f3d_real h = g->depth[c];
  if (!(h > F3D_SHALLOW_DRY) || !(weights[side] > F3D_R(0.0))) return F3D_R(0.0);
  const f3d_real r = cube_root(h);
  return total * h * r * r / weights[side];
}

/* One substep of [h] seconds. Whether any face's flow had to be held to
 * the most a substep allows, into [held]. */
static void substep(F3dWorld *world, Grid *g, Lip *lip, Shove *shove, f3d_real h,
                    f3d_real *u_old, f3d_real *w_old, f3d_real *out,
                    int *held, int *drained) {
  F3dShallowSlot *ws = g->slot;
  const uint32_t nx = g->nx, nz = g->nz, ux = nx + 1u;
  const f3d_real gravity = gravity_down(world);
  /* 1. The springs. */
  for (uint32_t k = 0; k < ws->source_count; k++) {
    const F3dShallowSource *s = &ws->sources[k];
    if (s->rate != F3D_R(0.0)) spread(g, s->x, s->z, s->radius, s->rate * h);
  }
  /* The outlets: a sharp-crested weir passes Q = ⅔·C_d·√(2g)·L·H^1.5 at a
   * head H over its crest (Poleni), C_d by Rehbock (1929) as Henderson's
   * Open Channel Flow gives it, 0.611 + 0.075·H/P, P the crest's height
   * over the bed; never below the crest in one substep. */
  for (uint32_t k = 0; k < ws->outlet_count; k++) {
    const F3dShallowOutlet *o = &ws->outlets[k];
    if (!(o->width > F3D_R(0.0))) continue;
    const int32_t c = cell_at(g, o->x, o->z);
    if (c < 0 || walled(g, (uint32_t)c)) continue;
    const f3d_real crest = o->crest;
    const f3d_real head = g->ground[c] + g->depth[c] - crest;
    if (!(head > F3D_R(0.0)) || !(g->depth[c] > F3D_SHALLOW_DRY)) continue;
    f3d_real q;
    if (o->kind == F3D_OUTLET_DRAIN) {
      /* A drain, a culvert's mouth: an orifice of area A, Q = C_d·A·√(2gH)
       * at a head H over its invert (Torricelli), C_d a sharp-edged
       * orifice's 0.61: its jet's contraction, 0.62, times its velocity
       * coefficient, 0.98. */
      const f3d_real cd = o->coefficient > F3D_R(0.0) ? o->coefficient : F3D_R(0.61);
      q = cd * o->width * f3d_sqrt(F3D_R(2.0) * gravity * head);
    } else {
      const f3d_real weir = crest - g->ground[c];
      const f3d_real cd = o->coefficient > F3D_R(0.0)
                              ? o->coefficient
                              : F3D_R(0.611) + (weir > F3D_R(0.0) ? F3D_R(0.075) * head / weir
                                                                   : F3D_R(0.0));
      q = F3D_R(2.0) / F3D_R(3.0) * cd * f3d_sqrt(F3D_R(2.0) * gravity) * o->width * head *
          f3d_sqrt(head);
    }
    const f3d_real taken = f3d_min(q * h, f3d_min(head, g->depth[c]) * g->area);
    g->depth[c] -= taken / g->area;
    ws->lost += taken;
    if (taken > F3D_R(0.0)) *drained = 1;
  }
  f3d_real weights[4];
  edge_weights(g, weights);
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
   * explicitly; the substeps are cut short enough for the fluid's own
   * viscosity, and a cell whose eddies would mix faster than a quarter of
   * itself a substep is held there and counted. Where it is dry or walled
   * there is nothing to mix. */
  {
    f3d_copy(u_old, g->u, (size_t)ux * nz * sizeof(f3d_real));
    f3d_copy(w_old, g->w, (size_t)nx * (nz + 1u) * sizeof(f3d_real));
    const f3d_real mix = F3D_R(0.15) * g->cell;
    const f3d_real most_nu = F3D_R(0.25) * g->cell * g->cell / h;
    /* And the fluid's own: what holds honey or lava together. */
    const f3d_real nu_fluid = ws->viscosity / ws->density;
    for (uint32_t c = 0; c < g->n; c++) {
      out[c] = F3D_R(0.0);
      if (!wet(g, c)) continue;
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
          roughness_at(g, c) * speed * f3d_sqrt(gravity) / f3d_sqrt(cube_root(d));
      const f3d_real nu = mix * mix * shear + F3D_R(0.15) * d * friction + nu_fluid;
      if (nu > most_nu) *held = 1;
      out[c] = f3d_min(nu, most_nu);
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
  for (int axis = 0; axis < 2; axis++) {
    const uint32_t fx_count = axis == 0 ? ux : nx;
    const uint32_t fz_count = axis == 0 ? nz : nz + 1u;
    f3d_real *v = axis == 0 ? g->u : g->w;
    /* The flow before this step's slope: what a face upstream of a lip
     * brings to it. */
    const f3d_real *was = axis == 0 ? u_old : w_old;
    const uint32_t stride = axis == 0 ? 1u : nx;
    for (uint32_t j = 0; j < fz_count; j++) {
      for (uint32_t i = 0; i < fx_count; i++) {
        const uint32_t f = i + j * fx_count;
        const int edge = axis == 0 ? (i == 0 || i == nx) : (j == 0 || j == nz);
        if (edge) {
          uint32_t side;
          const uint32_t c = edge_cell(g, axis, i, j, &side);
          const int outwards_positive = side == 1u || side == 3u;
          const f3d_real sign = outwards_positive ? F3D_R(1.0) : F3D_R(-1.0);
          const uint32_t kind = walled(g, c) ? F3D_EDGE_WALL : ws->edge_kind[side];
          if (kind == F3D_EDGE_OPEN) {
            /* What reaches it runs off, and nothing comes in. */
            f3d_real inner = axis == 0
                                 ? g->u[(i == 0 ? 1u : nx - 1u) + j * ux]
                                 : g->w[i + (j == 0 ? 1u : nz - 1u) * nx];
            if (nx == 1u && axis == 0) inner = F3D_R(0.0);
            if (nz == 1u && axis == 1) inner = F3D_R(0.0);
            v[f] = g->depth[c] > F3D_SHALLOW_DRY
                       ? (outwards_positive ? f3d_max(inner, F3D_R(0.0))
                                            : f3d_min(inner, F3D_R(0.0)))
                       : F3D_R(0.0);
          } else if (kind == F3D_EDGE_FLOW) {
            /* Its share of the discharge, as the velocity over its depth;
             * the water itself goes in step 4. */
            const f3d_real q = edge_share(g, weights, side, c);
            const f3d_real d = f3d_max(g->depth[c], F3D_SHALLOW_DRY);
            v[f] = f3d_clamp(-sign * q / (d * g->cell), -most, most);
          } else if (kind == F3D_EDGE_LEVEL) {
            /* Water outside standing at the edge's level over this cell's
             * ground, pushing in or held back by the slope between. */
            const f3d_real stage = ws->edge_value[side] - ws->origin.y;
            const f3d_real outside = f3d_max(stage - g->ground[c], F3D_R(0.0));
            const f3d_real inside = surface(g, c);
            const f3d_real depth = F3D_R(0.5) * (outside + g->depth[c]);
            f3d_real vel = sign * v[f];
            vel -= gravity * h * (f3d_max(stage, g->ground[c]) - inside) / g->cell;
            if (vel > F3D_R(0.0) && !(g->depth[c] > F3D_SHALLOW_DRY)) vel = F3D_R(0.0);
            if (vel < F3D_R(0.0) && !(outside > F3D_SHALLOW_DRY)) vel = F3D_R(0.0);
            if (depth > F3D_SHALLOW_DRY) {
              const f3d_real n = roughness_at(g, c);
              const f3d_real turbulent = gravity * n * n * f3d_abs(vel) / (depth * cube_root(depth));
              const f3d_real laminar = F3D_R(3.0) * ws->viscosity / (ws->density * depth * depth);
              vel /= F3D_R(1.0) + h * f3d_max(turbulent, laminar);
            }
            if (f3d_abs(vel) > most) *held = 1;
            v[f] = sign * f3d_clamp(vel, -most, most);
          } else {
            v[f] = F3D_R(0.0);
          }
          continue;
        }
        const uint32_t a = axis == 0 ? (i - 1u) + j * nx : i + (j - 1u) * nx;
        const uint32_t b = i + j * nx;
        const f3d_real da = g->depth[a], db = g->depth[b];
        if (walled(g, a) || walled(g, b) ||
            (!(da > F3D_SHALLOW_DRY) && !(db > F3D_SHALLOW_DRY))) {
          v[f] = F3D_R(0.0);
          continue;
        }
        /* A free overfall: across the lip at the critical speed of the
         * depth above it, or as fast as the flow came to it. */
        if (brink(g, a, b) || brink(g, b, a)) {
          const int forward = brink(g, a, b);
          const uint32_t from = forward ? a : b;
          const f3d_real over = crossing(g, from, (int32_t)(forward ? b : a));
          f3d_real vel = F3D_R(0.0);
          if (over > F3D_SHALLOW_DRY) {
            /* The face behind the column it leaves, in the way it goes. */
            const int has_behind = forward ? (axis == 0 ? i > 1u : j > 1u)
                                           : (axis == 0 ? i + 1u < nx : j + 1u < nz);
            const f3d_real behind =
                has_behind ? (forward ? was[f - stride] : -was[f + stride]) : F3D_R(0.0);
            vel = f3d_max(f3d_sqrt(gravity * over), behind);
          }
          if (vel > most) *held = 1;
          vel = f3d_min(vel, most);
          v[f] = forward ? vel : -vel;
          continue;
        }
        const f3d_real ea = surface(g, a), eb = surface(g, b);
        f3d_real vel = v[f] - gravity * h * (eb - ea) / g->cell;
        /* What the bodies' share of that slope gives the water across the
         * face, each body's back to it: ρ·g·h̄·Δx·f/A·h. */
        if (shove != NULL && (g->filled[a] > F3D_R(0.0) || g->filled[b] > F3D_R(0.0))) {
          const f3d_real k = ws->density * gravity * h * F3D_R(0.5) * (da + db) * g->cell / g->area;
          const uint32_t pa = shove->owner[a], pb = shove->owner[b];
          const uint32_t m = axis == 0 ? 0u : 1u;
          if (pb != 0) shove->push[(size_t)(pb - 1u) * SHOVE_REALS + m] += k * g->filled[b];
          if (pa != 0) shove->push[(size_t)(pa - 1u) * SHOVE_REALS + m] -= k * g->filled[a];
        }
        /* Nothing to carry from a side with no water above the other's
         * ground: no climbing onto ground standing above the surface. */
        if (vel > F3D_R(0.0) && !(crossing(g, a, (int32_t)b) > F3D_SHALLOW_DRY)) vel = F3D_R(0.0);
        if (vel < F3D_R(0.0) && !(crossing(g, b, (int32_t)a) > F3D_SHALLOW_DRY)) vel = F3D_R(0.0);
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
          vel += h * world->s.air_density * F3D_WIND_STRESS_DRAG * speed * along /
                 (ws->density * depth);
          /* The ground's hold, implicit: Manning's where the flow is
           * turbulent, with the roughness of the two cells it runs between,
           * or a laminar film's 3νU/h² where the fluid is thick or the
           * water thin and slow enough that it is more — whichever holds
           * harder, as a friction factor is the larger of the two. */
          const f3d_real na = roughness_at(g, a), nb = roughness_at(g, b);
          const f3d_real n2 = F3D_R(0.5) * (na * na + nb * nb);
          const f3d_real h43 = depth * cube_root(depth);
          const f3d_real turbulent = gravity * n2 * f3d_abs(vel) / h43;
          const f3d_real laminar =
              F3D_R(3.0) * ws->viscosity / (ws->density * depth * depth);
          vel /= F3D_R(1.0) + h * f3d_max(turbulent, laminar);
        }
        if (f3d_abs(vel) > most) *held = 1;
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
        out[from] += f3d_abs(vel) * crossing(g, (uint32_t)from, to) * g->cell * h;
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
        int32_t left, right;
        if (axis == 0) {
          left = i == 0 ? -1 : (int32_t)(i - 1u + j * nx);
          right = i == nx ? -1 : (int32_t)(i + j * nx);
        } else {
          left = j == 0 ? -1 : (int32_t)(i + (j - 1u) * nx);
          right = j == nz ? -1 : (int32_t)(i + j * nx);
        }
        /* Water from outside an edge: a discharge's share, or what the
         * stage beyond carries in. */
        if (left < 0 || right < 0) {
          uint32_t side;
          const uint32_t c = edge_cell(g, axis, i, j, &side);
          const int outwards_positive = side == 1u || side == 3u;
          const int inwards = outwards_positive ? v[f] < F3D_R(0.0) : v[f] > F3D_R(0.0);
          const uint32_t kind = walled(g, c) ? F3D_EDGE_WALL : ws->edge_kind[side];
          f3d_real came = F3D_R(0.0);
          if (kind == F3D_EDGE_FLOW && ws->edge_value[side] > F3D_R(0.0)) {
            came = edge_share(g, weights, side, c) * h;
          } else if (kind == F3D_EDGE_LEVEL && inwards) {
            const f3d_real outside =
                f3d_max(ws->edge_value[side] - ws->origin.y - g->ground[c], F3D_R(0.0));
            came = f3d_abs(v[f]) * outside * g->cell * h;
          }
          if (came > F3D_R(0.0)) {
            next[c] += came / g->area;
            ws->lost -= came;
            *drained = 1;
            continue;
          }
          if (inwards || v[f] == F3D_R(0.0)) continue;
        }
        if (v[f] == F3D_R(0.0)) continue;
        const int forward = v[f] > F3D_R(0.0);
        const int32_t from = forward ? left : right;
        const int32_t to = forward ? right : left;
        if (from < 0) continue;
        const f3d_real share = out[from];
        v[f] *= share;
        const f3d_real moved =
            f3d_abs(v[f]) * crossing(g, (uint32_t)from, to) * g->cell * h;
        if (!(moved > F3D_R(0.0))) continue;
        next[from] -= moved / g->area;
        if (to < 0) {
          ws->lost += moved;
          *drained = 1;
          continue;
        }
        /* Over a free overfall, and flying past the middle of the next
         * column before it comes down to its surface: it goes over the lip,
         * kept for the sheet the face throws at the end of the step. */
        if (brink(g, (uint32_t)from, (uint32_t)to)) {
          const f3d_real speed = f3d_abs(v[f]);
          const f3d_real thick = crossing(g, (uint32_t)from, to);
          const f3d_real fall = g->ground[from] + F3D_R(0.5) * thick - surface(g, (uint32_t)to);
          const f3d_real reach = F3D_R(0.5) * g->cell;
          if (gravity * reach * reach < F3D_R(2.0) * speed * speed * fall) {
            const uint32_t fi = axis == 0 ? f : ux * nz + f;
            const F3dVec3 vel = axis == 0 ? f3d_v3(v[f], F3D_R(0.0), F3D_R(0.0))
                                          : f3d_v3(F3D_R(0.0), F3D_R(0.0), v[f]);
            lip->volume[fi] += moved;
            lip->push[fi] = f3d_madd(lip->push[fi], vel, moved);
            lip->from[fi] = (uint32_t)from;
            continue;
          }
        }
        next[to] += moved / g->area;
      }
    }
  }
  for (uint32_t c = 0; c < g->n; c++) g->depth[c] = f3d_max(next[c], F3D_R(0.0));
}

/* The share of a piece that splashes back up where it lands (O'Rourke and
 * Amsden, 2000, from Mundo and colleagues' measurements): a drop or sheet
 * of diameter D striking at v onto a film h₀ deep splashes when
 * E² = We / (min(h₀/D, 1) + 1/√Re) passes 3330 — Mundo's K = Oh·Re^1.25 of
 * 57.7 squared, onto a dry wall — and throws 1.8·10⁻⁴·(E² − 3330) of
 * itself back up, all of it at most. We = ρv²D/σ, Re = ρvD/μ. */
static f3d_real splash_share(const F3dShallowSlot *ws, f3d_real diameter,
                             f3d_real speed, f3d_real film) {
  if (!(diameter > F3D_R(0.0) && speed > F3D_R(0.0))) return F3D_R(0.0);
  const f3d_real we = ws->density * speed * speed * diameter / ws->tension;
  const f3d_real re = ws->density * speed * diameter / ws->viscosity;
  const f3d_real e2 =
      we / (f3d_min(film / diameter, F3D_R(1.0)) + F3D_R(1.0) / f3d_sqrt(re));
  return e2 <= F3D_R(3330.0) ? F3D_R(0.0)
                             : f3d_min(F3D_R(1.0), F3D_R(1.8e-4) * (e2 - F3D_R(3330.0)));
}

/* The median drop a drop's splash breaks into, over the drop's own
 * diameter, at Weber number [we]: 2.54·We^(−3/5), at most one
 * (doc/derivations/splash_drops.md). */
static f3d_real splash_drop(f3d_real we) {
  if (!(we > F3D_R(0.0))) return F3D_R(1.0);
  return f3d_min(F3D_R(2.54) * power(we, F3D_R(-0.6)), F3D_R(1.0));
}

/* A piece of falling water [d] coming down in column [c] of [g]: its water
 * and its push into the column; what splashes back up thrown as a crown of
 * eight drops at the water's splash speed and angle; and, for a sheet
 * plunging into water, the air it drags down. */
static void land(F3dWorld *world, Grid *g, const F3dSpray *d, uint32_t c) {
  const F3dShallowSlot *ws = g->slot;
  wake(g->slot);
  const f3d_real speed = f3d_sqrt(f3d_dot(d->velocity, d->velocity));
  const int sheet = d->kind == F3D_SPRAY_SHEET;
  const f3d_real section = sheet && speed > F3D_R(0.0) ? d->flow / speed : F3D_R(0.0);
  const f3d_real thick = sheet && d->width > F3D_R(0.0) ? section / d->width : F3D_R(0.0);
  const f3d_real diameter =
      sheet ? F3D_R(2.0) * f3d_sqrt(section / F3D_PI) : d->width;
  const int wet_here = g->depth[c] > F3D_SHALLOW_DRY;
  /* A sheet plunging into water deeper than it is thick goes in whole and
   * drags air down instead; onto a film or dry ground it splashes as drops
   * do. */
  const f3d_real splash = sheet && g->depth[c] >= thick
                              ? F3D_R(0.0)
                              : splash_share(ws, diameter, speed, g->depth[c]);
  const f3d_real stays = d->volume * (F3D_R(1.0) - splash);
  /* Plunging in, it drags the water round it along and widens until it
   * reaches the bottom: its water and its push go into every wet column
   * within as far as the pool is deep where it came down, alike; onto dry
   * ground, into the one column. */
  const uint32_t ci = c % g->nx, cj = c / g->nx;
  const f3d_real reach = wet_here ? f3d_max(g->depth[c], g->cell) : F3D_R(0.0);
  const int32_t span = (int32_t)(reach / g->cell);
  uint32_t taken = 0;
  for (int pass = 0; pass < 2; pass++) {
    for (int32_t dj = -span; dj <= span; dj++) {
      for (int32_t di = -span; di <= span; di++) {
        const int32_t i = (int32_t)ci + di, j = (int32_t)cj + dj;
        if (i < 0 || j < 0 || i >= (int32_t)g->nx || j >= (int32_t)g->nz) continue;
        if ((f3d_real)(di * di + dj * dj) * g->cell * g->cell > reach * reach) continue;
        const uint32_t q = (uint32_t)i + (uint32_t)j * g->nx;
        if (q != c && !wet(g, q)) continue;
        if (pass == 0) {
          taken++;
          continue;
        }
        const f3d_real part = stays / (f3d_real)taken;
        /* All of it splashed back up: nothing stays to fill or push the
         * column, which may be dry. */
        if (!(part > F3D_R(0.0))) continue;
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
  const f3d_real gravity = gravity_down(world);
  if (splash > F3D_R(0.0)) {
    /* What splashes off a film leaves as Marengo and Tropea (1999)
     * measured for drops on films: up at u/U = 0.056 + 0.057δ +
     * 0.038·10⁻³(K − K_c) and out at v/U = 0.311 − 0.077δ − (0.009 +
     * 0.024δ)·10⁻³(K − K_c) of the speed it came in at, δ = h₀/D the
     * film's depth over its diameter and K = We·Oh^(−0.4), K_c = 2100 +
     * 5880δ^1.44 where splashing starts (Cossali, Coghe and Marengo,
     * 1997); δ and K held to the 0.5–2 and below 4000 they measured over.
     * A sheet's splash breaks into drops as its edge does, 1.89 times its
     * thickness; a drop's crown into drops of a median 2.54·We^(−3/5) of
     * its own diameter, never larger than it: the capillary–inertial
     * breakup of its rim, with the coefficient the number, volume and
     * spread of the drops measured off a crown give (Xiong and colleagues,
     * arXiv:2608.29762, 2026; doc/derivations/splash_drops.md). */
    const f3d_real we = ws->density * speed * speed * diameter / ws->tension;
    const f3d_real re = ws->density * speed * diameter / ws->viscosity;
    const f3d_real oh = f3d_sqrt(we) / re;
    const f3d_real film = f3d_clamp(g->depth[c] / diameter, F3D_R(0.5), F3D_R(2.0));
    const f3d_real kv = f3d_min(we * power(oh, F3D_R(-0.4)), F3D_R(4000.0));
    const f3d_real past =
        f3d_max(kv - (F3D_R(2100.0) + F3D_R(5880.0) * power(film, F3D_R(1.44))), F3D_R(0.0));
    const f3d_real up =
        (F3D_R(0.056) + F3D_R(0.057) * film + F3D_R(0.038e-3) * past) * speed;
    const f3d_real across = f3d_max(F3D_R(0.311) - F3D_R(0.077) * film -
                                         (F3D_R(0.009) + F3D_R(0.024) * film) * F3D_R(1e-3) * past,
                                     F3D_R(0.0)) *
                            speed;
    const f3d_real size = sheet ? F3D_R(1.89) * thick : splash_drop(we) * diameter;
    /* Thrown from the surface it struck, not from where its last piece of
     * flight carried it under: from there its drops would land again
     * before they rose. */
    const F3dVec3 from = f3d_v3(d->at.x, ws->origin.y + surface(g, c), d->at.z);
    for (uint32_t k = 0; k < 8u; k++) {
      f3d_real sn, cs;
      f3d_sin_cos(F3D_R(2.0) * F3D_PI * ((f3d_real)k + F3D_R(0.5)) / F3D_R(8.0), &sn, &cs);
      const F3dVec3 velocity = f3d_v3(cs * across, up, sn * across);
      throw_drops(world, g, d->water, from, velocity, d->volume * splash / F3D_R(8.0),
                  size, c);
    }
  }
  /* Air dragged down by a sheet plunging into water (Bin, 1993):
   * Q_air/Q = 0.04·Fr^0.28·(H/e)^0.4, Fr = v₀²/(g·e₀) as it left the lip, H
   * how far it fell. Into the middle of the column it plunged into. */
  if (sheet && wet_here && d->speed0 > F3D_R(0.0) && d->width > F3D_R(0.0) &&
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

/* Where falling water coming down over wall cell [c] goes: the open
 * neighbour it came from, the way it was flying, or −1 for none. */
static int32_t off_the_wall(const Grid *g, uint32_t c, F3dVec3 velocity) {
  const int32_t i = (int32_t)(c % g->nx), j = (int32_t)(c / g->nx);
  const int back_x = f3d_abs(velocity.x) >= f3d_abs(velocity.z);
  const int32_t di = back_x ? (velocity.x > F3D_R(0.0) ? -1 : 1) : 0;
  const int32_t dj = back_x ? 0 : (velocity.z > F3D_R(0.0) ? -1 : 1);
  const int32_t ii = i + di, jj = j + dj;
  if (ii < 0 || jj < 0 || ii >= (int32_t)g->nx || jj >= (int32_t)g->nz) return -1;
  const uint32_t q = (uint32_t)ii + (uint32_t)jj * g->nx;
  return walled(g, q) ? -1 : (int32_t)q;
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
      int32_t c = cell_at(&g, d.at.x, d.at.z);
      if (c < 0) {
        /* Off the grid: gone from this water. */
        ws->lost += d.volume;
        landed = 1;
        break;
      }
      if (walled(&g, (uint32_t)c)) {
        /* Against a wall: down it, into the column it came from. */
        if (d.at.y - ws->origin.y > g.ground[c]) continue;
        c = off_the_wall(&g, (uint32_t)c, d.velocity);
        if (c < 0) {
          ws->lost += d.volume;
        } else {
          land(world, &g, &d, (uint32_t)c);
        }
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
  const f3d_real gravity = gravity_down(world);
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
    b.at = f3d_madd(b.at, flow, dt);
    b.at.y += rise * dt;
    const int32_t c = cell_at(&g, b.at.x, b.at.z);
    if (c < 0 || !wet(&g, (uint32_t)c)) continue;
    if (b.at.y - ws->origin.y >= surface(&g, (uint32_t)c)) continue;
    world->bubbles[kept++] = b;
  }
  world->s.bubble_count = kept;
}

/* How far a body reaches from its origin. */
static f3d_real reach_of(const F3dWorld *world, const F3dSlot *s) {
  const f3d_real r = s->size.x + s->rounding, h = s->size.y;
  switch (s->shape) {
    case F3D_SHAPE_SPHERE:
      return r;
    case F3D_SHAPE_BOX:
      return f3d_sqrt(f3d_dot(s->size, s->size)) + s->rounding;
    case F3D_SHAPE_CAPSULE:
      return r + h;
    case F3D_SHAPE_CYLINDER:
    case F3D_SHAPE_CONE:
      return f3d_sqrt(r * r + h * h) + s->rounding;
    case F3D_SHAPE_HULL: {
      if (s->hull == 0 || s->hull > world->s.hull_count) return F3D_R(0.0);
      const F3dHull *k = &world->hulls[s->hull - 1u];
      const F3dVec3 far = f3d_v3(f3d_max(f3d_abs(k->lo.x), f3d_abs(k->hi.x)),
                                 f3d_max(f3d_abs(k->lo.y), f3d_abs(k->hi.y)),
                                 f3d_max(f3d_abs(k->lo.z), f3d_abs(k->hi.z)));
      return f3d_sqrt(f3d_dot(far, far)) + s->rounding;
    }
    case F3D_SHAPE_COMPOUND: {
      if (s->hull == 0 || s->hull > world->s.compound_count) return F3D_R(0.0);
      const F3dCompound *k = &world->compounds[s->hull - 1u];
      const F3dVec3 far = f3d_v3(f3d_max(f3d_abs(k->lo.x), f3d_abs(k->hi.x)),
                                 f3d_max(f3d_abs(k->lo.y), f3d_abs(k->hi.y)),
                                 f3d_max(f3d_abs(k->lo.z), f3d_abs(k->hi.z)));
      return f3d_sqrt(f3d_dot(far, far));
    }
    default:
      return F3D_R(0.0);
  }
}

/* Whether resting water [ws] is stirred this step: a body awake, or moved
 * by its velocity, reaching over its grid and down to its surface by the
 * end of the step, or wind anywhere over it. Its springs and everything
 * poured or landed in it wake it as they happen. */
static int stirred(const F3dWorld *world, const F3dShallowSlot *ws, f3d_real dt) {
  const f3d_real wide = (f3d_real)ws->nx * ws->cell;
  const f3d_real deep = (f3d_real)ws->nz * ws->cell;
  /* The wind over the whole grid: once if it is the same everywhere, else
   * at its own grid's spacing across the water's box. */
  const int even_wind = world->grid == NULL || world->s.grid_n[0] == 0;
  const f3d_real spacing = even_wind ? f3d_max(wide, deep) : world->s.grid_cell;
  const uint32_t across = (uint32_t)f3d_min(wide / spacing + F3D_R(1.0), F3D_R(64.0)) + 1u;
  const uint32_t along = (uint32_t)f3d_min(deep / spacing + F3D_R(1.0), F3D_R(64.0)) + 1u;
  for (uint32_t j = 0; j <= along; j++) {
    for (uint32_t i = 0; i <= across; i++) {
      f3d_real wind[3];
      f3d_world_sample_wind(world,
                            ws->origin.x + wide * (f3d_real)i / (f3d_real)across,
                            ws->origin.y + ws->top,
                            ws->origin.z + deep * (f3d_real)j / (f3d_real)along, wind);
      if (wind[0] * wind[0] + wind[2] * wind[2] > F3D_R(0.0)) return 1;
      if (even_wind) break;
    }
    if (even_wind) break;
  }
  for (uint32_t b = 0; b < world->s.used; b++) {
    const F3dSlot *s = &world->slots[b];
    if (!s->live || s->shape == F3D_SHAPE_POINT || s->shape == F3D_SHAPE_MESH) continue;
    if (s->type == F3D_BODY_DYNAMIC) {
      if (s->flags & F3D_FLAG_ASLEEP) continue;
    } else if (f3d_dot(s->velocity, s->velocity) == F3D_R(0.0) &&
               f3d_dot(s->spin, s->spin) == F3D_R(0.0)) {
      continue;
    }
    const f3d_real r = reach_of(world, s);
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

/* The most energy any wet cell holds, J/m²: its motion's, ½ρh|u|², and its
 * surface's off the mean of its wet neighbours', ½ρg(η − η̄)², which a
 * level pool has none of however its basins lie. */
static f3d_real most_energy(const Grid *g, f3d_real gravity) {
  const f3d_real rho = g->slot->density;
  f3d_real most = F3D_R(0.0);
  for (uint32_t c = 0; c < g->n; c++) {
    if (!wet(g, c)) continue;
    const uint32_t i = c % g->nx, j = c / g->nx;
    const F3dVec3 u = column_flow(g, c);
    f3d_real e = F3D_R(0.5) * rho * g->depth[c] * (u.x * u.x + u.z * u.z);
    f3d_real sum = F3D_R(0.0), count = F3D_R(0.0);
    const int32_t near[4][2] = {{-1, 0}, {1, 0}, {0, -1}, {0, 1}};
    for (int k = 0; k < 4; k++) {
      const int32_t ii = (int32_t)i + near[k][0], jj = (int32_t)j + near[k][1];
      if (ii < 0 || jj < 0 || ii >= (int32_t)g->nx || jj >= (int32_t)g->nz) continue;
      const uint32_t q = (uint32_t)ii + (uint32_t)jj * g->nx;
      if (!wet(g, q)) continue;
      sum += surface(g, q);
      count += F3D_R(1.0);
    }
    if (count > F3D_R(0.0)) {
      const f3d_real off = surface(g, c) - sum / count;
      e += F3D_R(0.5) * rho * gravity * off * off;
    }
    most = f3d_max(most, e);
  }
  return most;
}

void f3d_step_water(F3dWorld *world, f3d_real dt) {
  if (world->s.shallow_count == 0) return;
  const f3d_real gravity = gravity_down(world);
  const f3d_real rest_energy =
      world->s.water_rest_set ? world->s.water_rest_energy : F3D_REST_ENERGY;
  const f3d_real rest_time = world->s.water_rest_set ? world->s.water_rest_time : F3D_REST_TIME;
  for (uint32_t k = 0; k < world->s.shallow_count; k++) {
    F3dShallowSlot *ws = &world->shallows[k];
    if (!ws->live) continue;
    if (ws->resting) {
      if (!stirred(world, ws, dt)) continue;
      wake(ws);
    }
    Grid g = grid_of(world, ws);
    int stirring = 0;
    Shove shove;
    shove.owner = (uint32_t *)f3d_alloc((size_t)g.n * sizeof(uint32_t) + 8u);
    shove.owned = (f3d_real *)f3d_alloc((size_t)g.n * sizeof(f3d_real) + 8u);
    shove.push = (f3d_real *)f3d_alloc((size_t)world->s.used * SHOVE_REALS * sizeof(f3d_real) + 8u);
    Shove *pushes = &shove;
    if (shove.owner == NULL || shove.owned == NULL || shove.push == NULL) {
      pushes = NULL;
    } else {
      f3d_zero(shove.owner, (size_t)g.n * sizeof(uint32_t));
      f3d_zero(shove.owned, (size_t)g.n * sizeof(f3d_real));
      f3d_zero(shove.push, (size_t)world->s.used * SHOVE_REALS * sizeof(f3d_real));
    }
    bodies_in(world, &g, k + 1u, dt, pushes, &stirring);
    /* As many substeps as keep a wave or the flow within a quarter of a
     * cell each, and the fluid's own viscosity from spreading a cell's
     * momentum further than a quarter of it (the explicit scheme's bound,
     * ν·h/Δx² ≤ 1/4); past the most a step is cut into, counted. */
    f3d_real fastest = F3D_R(0.0), deepest = F3D_R(0.0);
    for (uint32_t f = 0; f < (g.nx + 1u) * g.nz; f++) fastest = f3d_max(fastest, f3d_abs(g.u[f]));
    for (uint32_t f = 0; f < g.nx * (g.nz + 1u); f++) fastest = f3d_max(fastest, f3d_abs(g.w[f]));
    for (uint32_t c = 0; c < g.n; c++) deepest = f3d_max(deepest, g.depth[c] + g.filled[c] / g.area);
    const f3d_real wave = fastest + f3d_sqrt(gravity * deepest);
    f3d_real longest = F3D_R(0.25) * g.cell * g.cell * ws->density / ws->viscosity;
    if (wave > F3D_R(0.0)) longest = f3d_min(longest, F3D_R(0.25) * g.cell / wave);
    uint32_t count = 1;
    while ((f3d_real)count * longest < dt && count < F3D_SHALLOW_MOST_SUBSTEPS) count++;
    int held = (f3d_real)count * longest < dt;
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
    int drained = 0;
    for (uint32_t s = 0; s < count; s++) {
      substep(world, &g, &lip, pushes, h, u_old, w_old, out, &held, &drained);
    }
    /* What the water's slope gave each body, at the middle of what it
     * holds up. */
    for (uint32_t b = 0; pushes != NULL && b < world->s.used; b++) {
      const f3d_real *p = shove.push + (size_t)b * SHOVE_REALS;
      if (p[0] == F3D_R(0.0) && p[1] == F3D_R(0.0)) continue;
      F3dSlot *s = &world->slots[b];
      const F3dVec3 force = f3d_v3(p[0] / dt, F3D_R(0.0), p[1] / dt);
      const F3dVec3 arm = f3d_sub(f3d_add(ws->origin, f3d_v3(p[2], p[3], p[4])), s->position);
      s->force = f3d_add(s->force, force);
      s->torque = f3d_add(s->torque, f3d_cross(arm, force));
    }
    f3d_free(shove.owner);
    f3d_free(shove.owned);
    f3d_free(shove.push);
    ws->substeps = count;
    if (held) ws->overruns++;
    /* Each face of a lip throws what went over it this step as one piece
     * of sheet, as wide as the face, at the speed it went over with, from
     * the middle of the sheet's thickness at the lip. With no room for it,
     * the water stays on the lip for the next step. */
    const uint32_t ux = g.nx + 1u;
    int over = 0;
    for (uint32_t fi = 0; fi < (uint32_t)faces; fi++) {
      const f3d_real volume = lip.volume[fi];
      if (!(volume > F3D_R(0.0))) continue;
      over = 1;
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
    /* Still, with nothing moving in it, feeding it, draining it or going
     * over a lip, for long enough: it rests. */
    ws->energy = most_energy(&g, gravity);
    int quiet = rest_time > F3D_R(0.0) && ws->energy <= rest_energy && !stirring &&
                !drained && !over;
    for (uint32_t i = 0; quiet && i < ws->source_count; i++) {
      quiet = ws->sources[i].rate == F3D_R(0.0);
    }
    for (uint32_t i = 0; quiet && i < 4u; i++) {
      quiet = !(ws->edge_kind[i] == F3D_EDGE_FLOW && ws->edge_value[i] != F3D_R(0.0));
    }
    ws->calm = quiet ? ws->calm + dt : F3D_R(0.0);
    if (quiet && ws->calm >= rest_time) {
      f3d_real top = F3D_R(-1e30);
      for (uint32_t c = 0; c < g.n; c++) {
        if (wet(&g, c)) top = f3d_max(top, surface(&g, c));
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
