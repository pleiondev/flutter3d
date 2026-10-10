/*
 * Water over ground, tested in C: what it refuses, a lake at rest staying
 * at rest over a bumpy bed, a dam breaking with not a drop made or lost, a
 * spring feeding a stream off a cliff into a pond, the spray only at the
 * cliff, a stone's waves, a ball floating as deep as Archimedes says, the
 * flow carrying a float, a jet mixing into a pool, an open edge letting water go, a weir
 * holding a pool at the head Poleni's law gives, a current let in at one edge and out at
 * another, a wall of cells holding a dam, and water through a snapshot.
 */
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "check.h"

static void run(F3dWorld *w, int steps) {
  for (int i = 0; i < steps; i++) f3d_world_step(w, F3D_R(1.0) / 60);
}

static double total(F3dWorld *w, F3dShallow water) {
  f3d_real held, lost;
  f3d_shallow_volume(w, water, &held, &lost);
  return (double)held + (double)lost;
}

static void test_refusals(void) {
  F3dWorld *w = f3d_world_create();
  f3d_real ground[4] = {0, 0, 0, 0};
  CHECK(f3d_shallow_create(w, 0, 2, 1, 0, 0, 0, ground) == 0);
  CHECK(f3d_shallow_create(w, 2, 2, 0, 0, 0, 0, ground) == 0);
  CHECK(f3d_shallow_create(w, 2, 2, 1, 0, 0, 0, NULL) == 0);
  ground[2] = nan_value();
  CHECK(f3d_shallow_create(w, 2, 2, 1, 0, 0, 0, ground) == 0);
  ground[2] = 0;
  const F3dShallow water = f3d_shallow_create(w, 2, 2, 1, 0, 0, 0, ground);
  CHECK(water == 1);
  CHECK(f3d_shallow_set_source(w, water, F3D_SHALLOW_MOST_SOURCES, 0, 0, 1, 1) == 0);
  CHECK(f3d_shallow_set_source(w, water, 0, 0, 0, 1, nan_value()) == 0);
  CHECK(f3d_shallow_set_source(w, water, 0, 0, 0, -1, 1) == 0);
  CHECK(f3d_shallow_set_bed(w, water, -1, 0) == 0);
  f3d_real out[4];
  CHECK(f3d_shallow_sample(w, water, 5, 5, out) == 0);
  CHECK(f3d_shallow_destroy(w, water) == 1);
  CHECK(!f3d_shallow_is_valid(w, water));
  CHECK(f3d_shallow_destroy(w, water) == 0);
  f3d_world_destroy(w);
}

static void test_lake_at_rest(void) {
  /* Still water over a bumpy bed stays still: the slope of the surface,
   * not of the ground, drives it. */
  F3dWorld *w = f3d_world_create();
  f3d_real ground[32 * 32];
  for (int j = 0; j < 32; j++) {
    for (int i = 0; i < 32; i++) {
      ground[i + j * 32] = (f3d_real)(0.3 * sin(i * 0.7) * cos(j * 0.5));
    }
  }
  const F3dShallow water = f3d_shallow_create(w, 32, 32, F3D_R(0.25), 0, 0, 0, ground);
  f3d_shallow_fill(w, water, 0, 0, 8, 8, F3D_R(0.5));
  run(w, 300);
  f3d_real surface[32 * 32], flow[2 * 32 * 32];
  f3d_shallow_read(w, water, surface, NULL);
  f3d_shallow_read_flow(w, water, flow);
  for (int c = 0; c < 32 * 32; c++) {
    CHECK_NEAR(surface[c], 0.5, 1e-5);
    CHECK(fabs((double)flow[2 * c]) < 1e-5 && fabs((double)flow[2 * c + 1]) < 1e-5);
  }
  f3d_world_destroy(w);
}

static void test_dam_break(void) {
  /* Half a metre of water held at one end of a closed channel, let go: it
   * runs to the far end and back, and not a drop is made or lost. */
  F3dWorld *w = f3d_world_create();
  f3d_real ground[64 * 16];
  memset(ground, 0, sizeof ground);
  const F3dShallow water = f3d_shallow_create(w, 64, 16, F3D_R(0.1), 0, 0, 0, ground);
  f3d_shallow_fill(w, water, 0, 0, 2, F3D_R(1.6), F3D_R(0.5));
  const double before = total(w, water);
  double far_end = 0;
  for (int i = 0; i < 600; i++) {
    run(w, 1);
    f3d_real s[4];
    f3d_shallow_sample(w, water, F3D_R(6.35), F3D_R(0.8), s);
    if (s[1] > far_end) far_end = s[1];
  }
  CHECK_NEAR(total(w, water), before, 1e-5 * before);
  /* The wave reached the far end, four metres off, and piled up there. */
  CHECK(far_end > 0.15);
  f3d_world_destroy(w);
}

/* A stream bed from a spring down a slope to a cliff three metres high,
 * and a pond at its foot: [nx] × 24 cells of a quarter metre. */
static F3dShallow falls(F3dWorld *w, f3d_real *ground, int nx) {
  for (int j = 0; j < 24; j++) {
    for (int i = 0; i < nx; i++) {
      const double x = i * 0.25;
      const double channel = 0.4 * fabs((j - 12) * 0.25);
      ground[i + j * nx] = (f3d_real)(x < 12 ? 4.0 - 0.1 * x + channel
                                             : 0.02 * fabs(x - 18) + 0.2 * channel);
    }
  }
  const F3dShallow water = f3d_shallow_create(w, (uint32_t)nx, 24, F3D_R(0.25), 0, 0, 0, ground);
  f3d_shallow_fill(w, water, F3D_R(12.2), 0, 24, 6, F3D_R(0.8));
  f3d_shallow_set_source(w, water, 0, 1, 3, F3D_R(0.5), F3D_R(0.05));
  return water;
}

static void test_waterfall(void) {
  /* A spring of fifty litres a second runs down the slope as a stream, off
   * the cliff as spray, and into the pond: twenty seconds put in exactly
   * one cubic metre more, wherever it is. */
  F3dWorld *w = f3d_world_create();
  f3d_real *ground = (f3d_real *)malloc(96 * 24 * sizeof(f3d_real));
  const F3dShallow water = falls(w, ground, 96);
  const double before = total(w, water);
  uint32_t most = 0;
  f3d_real spray[F3D_SPRAY_FLOATS * 64];
  int all_at_cliff = 1;
  for (int i = 0; i < 1200; i++) {
    run(w, 1);
    if (w->s.spray_count > most) most = w->s.spray_count;
    /* Every drop is off the cliff, over the pond, and never above where
     * the stream left it. */
    const uint32_t n = f3d_world_read_spray(w, spray, NULL, 64);
    for (uint32_t k = 0; k < n; k++) {
      const f3d_real *d = &spray[k * F3D_SPRAY_FLOATS];
      if (d[0] < 11.9 || d[1] > 3.0) all_at_cliff = 0;
    }
  }
  CHECK_NEAR(total(w, water), before + 1.0, 1e-4 * before);
  CHECK(most > 10);
  CHECK(all_at_cliff);
  /* The sheet keeps to continuity: every piece of it carries the flow it
   * left with, thickness × speed × width, and the faster it has fallen the
   * thinner it is. */
  f3d_real all[F3D_SPRAY_FLOATS * 4096];
  const uint32_t n = f3d_world_read_spray(w, all, NULL, 4096);
  double top_thick = 0, low_thick = 1, top_y = -1e9, low_y = 1e9;
  int sheets = 0;
  for (uint32_t k = 0; k < n; k++) {
    const f3d_real *d = &all[k * F3D_SPRAY_FLOATS];
    if (d[9] != F3D_SPRAY_SHEET) continue;
    sheets++;
    if (d[1] > top_y) {
      top_y = d[1];
      top_thick = d[8];
    }
    if (d[1] < low_y) {
      low_y = d[1];
      low_thick = d[8];
    }
  }
  CHECK(sheets > 10);
  CHECK(low_thick < 0.8 * top_thick);
  /* Plunging into the pond it drags air down: bubbles in the water below
   * the falls, and none above the cliff. */
  f3d_real bubbles[F3D_BUBBLE_FLOATS * 1024];
  const uint32_t b = f3d_world_read_bubbles(w, bubbles, NULL, 1024);
  CHECK(b > 0);
  int below = 1;
  for (uint32_t k = 0; k < b; k++) below &= bubbles[k * F3D_BUBBLE_FLOATS] > 12.0;
  CHECK(below);
  /* The stream runs: a shallow sheet moving downhill. */
  f3d_real s[4];
  f3d_shallow_sample(w, water, 6, 3, s);
  CHECK(s[1] > 0.02 && s[1] < 0.3);
  CHECK(s[2] > 0.3);
  /* The spring stopped, the falls run dry, and the bubbles rise and are
   * gone at the surface within seconds. */
  f3d_shallow_set_source(w, water, 0, 1, 3, F3D_R(0.5), 0);
  run(w, 900);
  CHECK(f3d_world_read_bubbles(w, NULL, NULL, 1024) == 0);
  free(ground);
  f3d_world_destroy(w);
}

static void test_no_spray_on_level_ground(void) {
  /* A dam breaking on level ground throws waves steeper than a cell, and
   * none of it is a waterfall. */
  F3dWorld *w = f3d_world_create();
  f3d_real ground[64 * 16];
  memset(ground, 0, sizeof ground);
  const F3dShallow water = f3d_shallow_create(w, 64, 16, F3D_R(0.05), 0, 0, 0, ground);
  f3d_shallow_fill(w, water, 0, 0, 1, 1, F3D_R(0.6));
  uint32_t most = 0;
  for (int i = 0; i < 300; i++) {
    run(w, 1);
    if (w->s.spray_count > most) most = w->s.spray_count;
  }
  CHECK(most == 0);
  f3d_world_destroy(w);
}

/* A pond [n] cells of [cell] across, a metre deep, centred on the origin,
 * with a floor under it: what reaches the bottom stops there, as the
 * water's ground is only where the water stands on. */
static F3dShallow pond(F3dWorld *w, int n, f3d_real cell) {
  f3d_real *ground = (f3d_real *)calloc((size_t)n * n, sizeof(f3d_real));
  const F3dShallow water =
      f3d_shallow_create(w, (uint32_t)n, (uint32_t)n, cell, -n * cell / 2, 0, -n * cell / 2, ground);
  free(ground);
  f3d_shallow_fill(w, water, -99, -99, 99, 99, 1);
  const F3dBody floor = f3d_body_create(w, F3D_BODY_FIXED, 0, F3D_R(-0.5), 0, 0);
  f3d_body_set_shape(w, floor, F3D_SHAPE_BOX, (f3d_real)n * cell, F3D_R(0.5),
                     (f3d_real)n * cell);
  return water;
}

static void test_stone_makes_waves(void) {
  /* A five kilogram stone dropped in raises a wave a metre off, and the
   * pond holds what it held. */
  F3dWorld *w = f3d_world_create();
  const F3dShallow water = pond(w, 48, F3D_R(0.1));
  const double before = total(w, water);
  const F3dBody stone = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, F3D_R(1.5), 0, 5);
  f3d_body_set_shape(w, stone, F3D_SHAPE_SPHERE, F3D_R(0.1), 0, 0);
  double most = 0;
  uint32_t splash = 0;
  for (int i = 0; i < 120; i++) {
    run(w, 1);
    if (w->s.spray_count > splash) splash = w->s.spray_count;
    f3d_real s[4];
    f3d_shallow_sample(w, water, 1, 0, s);
    if (fabs((double)s[0] - 1.0) > most) most = fabs((double)s[0] - 1.0);
  }
  /* Two millimetres a metre off: most of what it pushed aside flew up
   * as its crown and came down nearer. */
  CHECK(most > 0.0015);
  CHECK_NEAR(total(w, water), before, 1e-5 * before);
  /* Falling a metre and a half, it came in at five metres a second, far
   * faster than a wave runs off a ball its size: it threw a crown. */
  CHECK(splash > 0);
  f3d_world_destroy(w);
  /* Set down on the water, it pushes the water aside no faster than the
   * waves take it, and throws nothing. */
  w = f3d_world_create();
  pond(w, 48, F3D_R(0.1));
  const F3dBody gentle = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, F3D_R(1.05), 0, F3D_R(0.5));
  f3d_body_set_shape(w, gentle, F3D_SHAPE_SPHERE, F3D_R(0.1), 0, 0);
  splash = 0;
  for (int i = 0; i < 60; i++) {
    run(w, 1);
    if (w->s.spray_count > splash) splash = w->s.spray_count;
  }
  CHECK(splash == 0);
  f3d_world_destroy(w);
}

/* The first drops a body dropped into the pond throws, and how fast it came
 * in: a box or a ball [shape] of 0.1 m, turned [tilt] about x, let go a
 * metre above the water. */
static void first_crown(int shape, f3d_real tilt, f3d_real *in, f3d_real *up,
                        f3d_real *out) {
  F3dWorld *w = f3d_world_create();
  pond(w, 48, F3D_R(0.1));
  const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, F3D_R(2.1), 0, 4);
  f3d_body_set_shape(w, b, (uint32_t)shape, F3D_R(0.1), F3D_R(0.1), F3D_R(0.1));
  f3d_real sn = (f3d_real)sin(0.5 * tilt), cs = (f3d_real)cos(0.5 * tilt);
  f3d_body_set_orientation(w, b, sn, 0, 0, cs);
  *in = *up = *out = 0;
  f3d_real spray[F3D_SPRAY_FLOATS * 256];
  for (int i = 0; i < 120 && *in == 0; i++) {
    f3d_real v[3];
    f3d_body_get_velocity(w, b, v);
    run(w, 1);
    const uint32_t n = f3d_world_read_spray(w, spray, NULL, 256);
    for (uint32_t k = 0; k < n; k++) {
      const f3d_real *d = &spray[k * F3D_SPRAY_FLOATS];
      *in = -v[1];
      *up += d[4] / (f3d_real)n;
      *out += (f3d_real)sqrt((double)(d[3] * d[3] + d[5] * d[5])) / (f3d_real)n;
    }
  }
  f3d_world_destroy(w);
}

static void test_a_splash_by_what_strikes(void) {
  /* A box falling flat on its face throws its crown out and up alike, one
   * in one, at 1.6 times the speed it came in at (Peters and colleagues'
   * disc); a ball throws a curtain straight up at a quarter of it
   * (Aristoff and Bush). A step of gravity on the drops is within the
   * tolerance. */
  f3d_real in, up, out;
  first_crown(F3D_SHAPE_BOX, 0, &in, &up, &out);
  CHECK(in > 4);
  CHECK_NEAR(out, 1.6 * 0.70710678 * in, 0.1 * in);
  CHECK_NEAR(up, 1.6 * 0.70710678 * in, 0.1 * in);
  first_crown(F3D_SHAPE_SPHERE, 0, &in, &up, &out);
  CHECK(in > 4);
  CHECK_NEAR(up, 0.25 * in, 0.05 * in);
  CHECK(out < 0.01 * in);
  /* Tilted ten degrees, its edge goes in well before the air under its
   * face is out, and it splashes as a rounded body does. */
  first_crown(F3D_SHAPE_BOX, (f3d_real)(10 * M_PI / 180), &in, &up, &out);
  CHECK(in > 4);
  CHECK_NEAR(up, 0.25 * in, 0.05 * in);
}

static void test_a_drop_splashes_into_drops_of_its_weber_number(void) {
  /* A drop of 3 mm striking a pond at 10 m/s, We = ρv²D/σ ≈ 4100, far
   * past the 77 < K < 180 Mundo measured over: its crown breaks into drops
   * of 2.54·We^(−3/5) of its diameter, about 52 µm
   * (doc/derivations/splash_drops.md), thrown up off the surface. With no
   * gravity, so it lands at the speed it was given. Mutations: Mundo's
   * min(8.72·e^(−0.0281K'), 1) back in land() — its drops come out a
   * millionth of a micrometre; the drops thrown from where the drop's
   * last piece of flight carried it under — they land again at once and
   * none is left. */
  F3dWorld *w = f3d_world_create();
  const F3dShallow water = pond(w, 32, F3D_R(0.25));
  f3d_world_set_gravity(w, 0, 0, 0);
  const double d0 = 0.003, v = 10.0;
  w->spray = (F3dSpray *)f3d_alloc(F3D_SHALLOW_MOST_SPRAY * sizeof(F3dSpray));
  CHECK(w->spray != NULL);
  F3dSpray drop;
  f3d_zero(&drop, sizeof drop);
  drop.at = f3d_v3(F3D_R(0.3), F3D_R(1.05), F3D_R(0.3));
  drop.velocity = f3d_v3(0, (f3d_real)-v, 0);
  drop.volume = (f3d_real)(M_PI / 6 * d0 * d0 * d0);
  drop.water = water;
  drop.kind = F3D_SPRAY_DROPS;
  drop.width = (f3d_real)d0;
  w->spray[w->s.spray_count++] = drop;
  run(w, 1);
  const F3dShallowSlot *ws = &w->shallows[water - 1u];
  const double we = (double)ws->density * v * v * d0 / (double)ws->tension;
  f3d_real spray[F3D_SPRAY_FLOATS * 16];
  const uint32_t n = f3d_world_read_spray(w, spray, NULL, 16);
  CHECK(n == 8);
  for (uint32_t k = 0; k < n; k++) {
    CHECK_NEAR(spray[k * F3D_SPRAY_FLOATS + 7] / (2.54 * pow(we, -0.6) * d0), 1.0, 0.01);
  }
  f3d_world_destroy(w);
}

static void test_floats_as_deep_as_it_weighs(void) {
  /* A ball of 0.2 m at six tenths of water's density, dropped into a
   * pond: it rides with three fifths of it under, its centre 2.7 cm below
   * the surface on the whole, bobbing on the waves its fall made as the
   * pond's walls throw them back. */
  const double r = 0.2, mass = 600 * 4.0 / 3.0 * M_PI * r * r * r;
  F3dWorld *w = f3d_world_create();
  const F3dShallow water = pond(w, 64, F3D_R(0.1));
  const F3dBody ball = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, F3D_R(0.973), 0, (f3d_real)mass);
  f3d_body_set_shape(w, ball, F3D_SHAPE_SPHERE, (f3d_real)r, 0, 0);
  run(w, 300);
  /* The surface away from the ball, over the same ten seconds: the waves
   * pass it as they pass the ball, and one sample at the end caught a
   * crest or a trough — 5 mm apart between the two precisions. */
  double sum = 0, surface = 0, lo = 9, hi = -9;
  for (int i = 0; i < 600; i++) {
    run(w, 1);
    f3d_real p[3], s[4];
    f3d_body_get_position(w, ball, p);
    f3d_shallow_sample(w, water, 2, 0, s);
    sum += p[1];
    surface += s[0];
    lo = fmin(lo, p[1]);
    hi = fmax(hi, p[1]);
  }
  /* Below the surface by what three fifths under puts it, give or take a
   * centimetre of the grid's ten. */
  CHECK_NEAR((sum - surface) / 600, -0.027, 0.01);
  CHECK(hi - lo < 0.1);
  f3d_world_destroy(w);
}

static void test_flow_carries_a_float(void) {
  /* A float on a stream drifts downstream with it. */
  F3dWorld *w = f3d_world_create();
  f3d_real *ground = (f3d_real *)malloc(96 * 24 * sizeof(f3d_real));
  const F3dShallow water = falls(w, ground, 96);
  run(w, 600);
  const F3dBody cork = f3d_body_create(w, F3D_BODY_DYNAMIC, 3, F3D_R(3.9), 3, F3D_R(0.5));
  f3d_body_set_shape(w, cork, F3D_SHAPE_SPHERE, F3D_R(0.08), 0, 0);
  run(w, 120);
  f3d_real p[3];
  f3d_body_get_position(w, cork, p);
  CHECK(p[0] > 3.5);
  (void)water;
  free(ground);
  f3d_world_destroy(w);
}

static void test_column_spreads(void) {
  /* Two metres of water in one cell of a flat floor runs out of all four
   * sides at once, stepped a whole second at a time — more than the
   * substeps a step may be cut into can keep within a quarter of a cell:
   * the cell gives what it holds and no more, so none is made, and nowhere
   * is there less than none. */
  F3dWorld *w = f3d_world_create();
  f3d_real ground[16 * 16];
  memset(ground, 0, sizeof ground);
  const F3dShallow water = f3d_shallow_create(w, 16, 16, F3D_R(0.2), 0, 0, 0, ground);
  f3d_shallow_pour(w, water, F3D_R(1.7), F3D_R(1.7), 0, F3D_R(0.08));
  const double before = total(w, water);
  f3d_real depth[16 * 16];
  double least = 1;
  for (int i = 0; i < 20; i++) {
    f3d_world_step(w, 1);
    f3d_shallow_read(w, water, NULL, depth);
    for (int c = 0; c < 16 * 16; c++) least = fmin(least, depth[c]);
  }
  CHECK(least >= 0);
  CHECK_NEAR(total(w, water), before, 1e-6 * before + 1e-9);
  f3d_world_destroy(w);
}

static void test_jet_mixes_into_a_pool(void) {
  /* A jet two cells wide driven into a pool a metre deep at two metres a
   * second, as a waterfall drives one: its eddies mix it with the still
   * water round it, so in a second it has slowed and widened instead of
   * crossing the pool as a stripe as fast as it came in. */
  F3dWorld *w = f3d_world_create();
  f3d_real ground[96 * 32];
  memset(ground, 0, sizeof ground);
  const F3dShallow water = f3d_shallow_create(w, 96, 32, F3D_R(0.1), 0, 0, 0, ground);
  f3d_shallow_fill(w, water, -9, -9, 99, 99, 1);
  const F3dShallowSlot *slot = &w->shallows[water - 1u];
  f3d_real *u = w->shallow_data + slot->first + 2u * 96u * 32u;
  for (int j = 15; j <= 16; j++)
    for (int i = 5; i <= 25; i++) u[i + j * 97] = 2;
  run(w, 60);
  f3d_real flow[2 * 96 * 32];
  f3d_shallow_read_flow(w, water, flow);
  double peak = 0, aside = 0;
  for (int i = 0; i < 96; i++) {
    peak = fmax(peak, fabs(flow[2 * (i + 15 * 96)]));
    aside = fmax(aside, fabs(flow[2 * (i + 20 * 96)]));
  }
  /* Unmixed, the jet still runs at 1.55 m/s a second on. */
  CHECK(peak < 1.0);
  CHECK(aside > 0.1);
  f3d_world_destroy(w);
}

/* A pool [depth] deep of [nx] × [nx] cells of [cell], of a fluid of
 * [density] and [viscosity], and a ball of radius [r] and [mass] held at
 * its middle [under] below the surface, still. */
static F3dBody ball_in(F3dWorld *w, uint32_t nx, f3d_real cell, f3d_real depth,
                       f3d_real density, f3d_real viscosity, f3d_real r,
                       f3d_real mass, f3d_real under) {
  f3d_real *ground = (f3d_real *)calloc(nx * nx, sizeof(f3d_real));
  const F3dShallow water = f3d_shallow_create(w, nx, nx, cell, 0, 0, 0, ground);
  free(ground);
  f3d_shallow_fill(w, water, -9, -9, 99, 99, depth);
  CHECK(f3d_shallow_set_fluid(w, water, density, viscosity, F3D_R(0.07)) == 1);
  const f3d_real mid = F3D_R(0.5) * (f3d_real)nx * cell;
  const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, mid, depth - under, mid, mass);
  f3d_body_set_shape(w, b, F3D_SHAPE_SPHERE, r, 0, 0);
  return b;
}

static void test_fluids(void) {
  /* What a water is can be set, and only to what a fluid can be. */
  F3dWorld *w = f3d_world_create();
  f3d_real ground[4] = {0, 0, 0, 0};
  const F3dShallow water = f3d_shallow_create(w, 2, 2, 1, 0, 0, 0, ground);
  CHECK(f3d_shallow_set_fluid(w, water, 1420, 10, F3D_R(0.05)) == 1);
  CHECK(f3d_shallow_set_fluid(w, water, 0, 10, F3D_R(0.05)) == 0);
  CHECK(f3d_shallow_set_fluid(w, water, 1420, -1, F3D_R(0.05)) == 0);
  CHECK(f3d_shallow_set_fluid(w, water, 1420, 10, NAN) == 0);
  CHECK(f3d_shallow_set_fluid(w, water + 1u, 1420, 10, F3D_R(0.05)) == 0);
  f3d_world_destroy(w);
}

static void test_ball_settles_through_honey(void) {
  /* A steel ball two centimetres across in honey (1420 kg/m³, 10 Pa·s)
   * falls at Stokes's speed 2(ρ_s − ρ)gr²/9μ, 139 mm/s, which at Re 0.39
   * Schiller and Naumann's correction makes 8% slower: 129 mm/s. */
  F3dWorld *w = f3d_world_create();
  const f3d_real r = F3D_R(0.01);
  const f3d_real mass = F3D_R(7800.0) * F3D_R(4.0) / F3D_R(3.0) * F3D_PI * r * r * r;
  const F3dBody b = ball_in(w, 16, F3D_R(0.1), 1, 1420, 10, r, mass, F3D_R(0.3));
  run(w, 120);
  f3d_real v[3];
  f3d_body_get_velocity(w, b, v);
  const double stokes = 2.0 * (7800.0 - 1420.0) * STANDARD_G * 1e-4 / (9.0 * 10.0);
  const double re = 1420.0 * stokes * 0.02 / 10.0;
  const double expected = stokes / (1.0 + 0.15 * pow(re, 0.687));
  CHECK_NEAR(-v[1], expected, 0.02 * expected);
  f3d_world_destroy(w);
}

static void test_ball_falls_through_water_at_newtons_speed(void) {
  /* A ball of twenty centimetres and twice water's density falls through
   * water at Re 5·10⁵, where the drag is Newton's 0.44:
   * v = √(8gr(ρ_s/ρ − 1)/3C_d), 2.44 m/s. */
  F3dWorld *w = f3d_world_create();
  const f3d_real r = F3D_R(0.1);
  const f3d_real mass = F3D_R(2000.0) * F3D_R(4.0) / F3D_R(3.0) * F3D_PI * r * r * r;
  const F3dBody b = ball_in(w, 16, F3D_R(0.25), 8, 1000, F3D_R(0.001), r, mass, F3D_R(0.5));
  run(w, 120);
  f3d_real v[3];
  f3d_body_get_velocity(w, b, v);
  const double newton = sqrt(8.0 * STANDARD_G * 0.1 * (2.0 - 1.0) / (3.0 * 0.44));
  /* CHECK_NEAR scales its tolerance by what it wants past one. */
  CHECK_NEAR(-v[1], newton, 0.03);
  f3d_world_destroy(w);
}

static void test_a_light_ball_carries_water_with_it(void) {
  /* A ping-pong ball, 2.7 g in 33 cm³, let go under water: what holds it
   * up is ρVg less its weight, and what it must speed up is itself and half
   * the water it displaces, so it starts up at 15.5 m/s² — not the 112 it
   * would with nothing to carry. */
  F3dWorld *w = f3d_world_create();
  const f3d_real r = F3D_R(0.02);
  const F3dBody b = ball_in(w, 16, F3D_R(0.1), 1, 1000, F3D_R(0.001), r, F3D_R(0.0027), F3D_R(0.5));
  const f3d_real dt = F3D_R(1.0) / 240;
  f3d_world_step(w, dt);
  f3d_real v[3];
  f3d_body_get_velocity(w, b, v);
  const double volume = 4.0 / 3.0 * M_PI * 0.02 * 0.02 * 0.02;
  const double up = ((1000.0 * volume - 0.0027) * STANDARD_G) / (0.0027 + 0.5 * 1000.0 * volume);
  CHECK_NEAR(v[1], up * (double)dt, 0.05 * up * (double)dt);
  f3d_world_destroy(w);
}

static void test_a_bag_of_air_lifts_what_it_is_tied_to(void) {
  /* A stone of thirty kilograms on the bottom of a pool eight metres deep,
   * a rope of a metre to a bag of 113 litres of air: the bag's lift less
   * the stone's weight in water is some 88 kilograms up, and the stone
   * goes with the bag. The bag's own two kilograms carry fifty of water
   * with them; were the rope to see only those two, it would pass the
   * stone a twenty-sixth of the lift and leave it where it lay. */
  F3dWorld *w = f3d_world_create();
  f3d_real *ground = (f3d_real *)calloc(16 * 16, sizeof(f3d_real));
  const F3dShallow water = f3d_shallow_create(w, 16, 16, F3D_R(0.5), 0, 0, 0, ground);
  free(ground);
  f3d_shallow_fill(w, water, -9, -9, 99, 99, 8);
  const F3dBody stone = f3d_body_create(w, F3D_BODY_DYNAMIC, 4, F3D_R(0.1), 4, 30);
  f3d_body_set_shape(w, stone, F3D_SHAPE_SPHERE, F3D_R(0.1), 0, 0);
  const F3dBody bag = f3d_body_create(w, F3D_BODY_DYNAMIC, 4, F3D_R(1.1), 4, 2);
  f3d_body_set_shape(w, bag, F3D_SHAPE_SPHERE, F3D_R(0.3), 0, 0);
  const F3dJoint rope = f3d_joint_create_distance(w, stone, bag, 4, F3D_R(0.1), 4, 4,
                                                  F3D_R(1.1), 4);
  CHECK(rope != 0);
  run(w, 60);
  f3d_real at[3], v[3];
  f3d_body_get_position(w, stone, at);
  f3d_body_get_velocity(w, stone, v);
  CHECK(at[1] > F3D_R(0.5));
  CHECK(v[1] > F3D_R(0.5));
  f3d_world_destroy(w);
}

/* Every cell's x momentum, kg·m/s. */
static double water_momentum_x(F3dWorld *w, F3dShallow water, uint32_t n, f3d_real cell) {
  f3d_real *depth = (f3d_real *)malloc(n * sizeof(f3d_real));
  f3d_real *flow = (f3d_real *)malloc(2u * n * sizeof(f3d_real));
  f3d_shallow_read(w, water, NULL, depth);
  f3d_shallow_read_flow(w, water, flow);
  double p = 0.0;
  for (uint32_t c = 0; c < n; c++) p += 1000.0 * (double)depth[c] * (double)cell * (double)cell * (double)flow[2 * c];
  free(depth);
  free(flow);
  return p;
}

static void test_a_body_driven_through_water_sets_it_moving(void) {
  /* A ball as dense as water sent through a still pool at two metres a
   * second slows as the water drags it, and the water takes up what it
   * loses: the momentum the ball and the water it carried gave up is the
   * pool's, and the water in its wake runs the way it went. Over a quarter
   * of a second: the flow's own advection, semi-Lagrangian, wears momentum
   * away as it goes — a patch of flow alone in this pool loses eight per
   * cent in half a second — so the balance is held while that is small. */
  F3dWorld *w = f3d_world_create();
  const f3d_real r = F3D_R(0.15);
  const double volume = 4.0 / 3.0 * M_PI * 0.15 * 0.15 * 0.15;
  const f3d_real mass = (f3d_real)(1000.0 * volume);
  const F3dBody b = ball_in(w, 64, F3D_R(0.1), 1, 1000, F3D_R(0.001), r, mass, F3D_R(0.5));
  CHECK(f3d_shallow_set_bed(w, 1u, 0, 0) == 1);
  f3d_body_set_velocity(w, b, 2, 0, 0);
  f3d_real p0[3];
  f3d_body_get_position(w, b, p0);
  run(w, 15);
  f3d_real v[3], p[3];
  f3d_body_get_velocity(w, b, v);
  f3d_body_get_position(w, b, p);
  CHECK(v[0] < F3D_R(1.9));
  const double carried = (double)mass + 0.5 * 1000.0 * volume;
  const double given = carried * (2.0 - (double)v[0]);
  const double taken = water_momentum_x(w, 1u, 64u * 64u, F3D_R(0.1));
  CHECK_NEAR(taken, given, 0.15);
  /* Behind it, where it passed, the water runs after it. */
  f3d_real behind[4];
  f3d_shallow_sample(w, 1u, F3D_R(0.5) * (p0[0] + p[0]), p[2], behind);
  CHECK(behind[2] > F3D_R(0.02));
  f3d_world_destroy(w);
}

static void test_flow_keeps_its_momentum(void) {
  /* A patch of water moving at a metre a second in a still pool spreads,
   * mixes and makes waves, and in half a second the pool's momentum is
   * what it was: carried as a flux of hu, not by tracing velocities back,
   * which wore eight per cent of it away. */
  F3dWorld *w = f3d_world_create();
  f3d_real *ground = (f3d_real *)calloc(64 * 64, sizeof(f3d_real));
  const F3dShallow water = f3d_shallow_create(w, 64, 64, F3D_R(0.1), 0, 0, 0, ground);
  free(ground);
  f3d_shallow_fill(w, water, -9, -9, 99, 99, 1);
  f3d_shallow_set_bed(w, water, 0, 0);
  const F3dShallowSlot *slot = &w->shallows[water - 1u];
  f3d_real *u = w->shallow_data + slot->first + 2u * 64u * 64u;
  for (int j = 28; j <= 35; j++)
    for (int i = 28; i <= 36; i++) u[i + j * 65] = 1;
  const double before = water_momentum_x(w, water, 64u * 64u, F3D_R(0.1));
  run(w, 30);
  CHECK_NEAR(water_momentum_x(w, water, 64u * 64u, F3D_R(0.1)), before, 0.005);
  f3d_world_destroy(w);
}

static void test_a_float_slides_down_the_surface(void) {
  /* A ball half as dense as water floating where the surface slopes one in
   * fifty is pushed down the slope by the pressure under it, ρgV·s, and
   * starts down at two thirds of g·s: the water it carries is half what it
   * displaces, which is its own mass. */
  F3dWorld *w = f3d_world_create();
  enum { N = 32 };
  f3d_real ground[N * N];
  memset(ground, 0, sizeof ground);
  const F3dShallow water = f3d_shallow_create(w, N, N, F3D_R(0.1), 0, 0, 0, ground);
  const F3dShallowSlot *slot = &w->shallows[water - 1u];
  f3d_real *depth = w->shallow_data + slot->first + N * N;
  for (int j = 0; j < N; j++)
    for (int i = 0; i < N; i++) depth[i + j * N] = F3D_R(1.0) - F3D_R(0.02) * F3D_R(0.1) * ((f3d_real)i - F3D_R(15.5));
  const f3d_real r = F3D_R(0.1);
  const f3d_real mass = F3D_R(500.0) * F3D_R(4.0) / F3D_R(3.0) * F3D_PI * r * r * r;
  const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, F3D_R(1.6), 1, F3D_R(1.6), mass);
  f3d_body_set_shape(w, b, F3D_SHAPE_SPHERE, r, 0, 0);
  const f3d_real dt = F3D_R(1.0) / 60;
  f3d_world_step(w, dt);
  f3d_real v[3];
  f3d_body_get_velocity(w, b, v);
  const double expected = 2.0 / 3.0 * STANDARD_G * 0.02 * (double)dt;
  CHECK_NEAR(v[0], expected, 0.1 * expected);
  CHECK_NEAR(v[2], 0.0, 0.05 * expected);
  f3d_world_destroy(w);
}

static void test_a_thick_film_runs_as_nusselt_says(void) {
  /* Oil a thousand times thicker than water, two centimetres deep, down a
   * slope of one in a hundred: a laminar film, whose mean speed is
   * gSh²/3ν, 13 mm/s — where Manning's rough bed would have had it at
   * fifteen centimetres a second. */
  F3dWorld *w = f3d_world_create();
  enum { NX = 64, NZ = 4 };
  f3d_real ground[NX * NZ];
  for (int j = 0; j < NZ; j++)
    for (int i = 0; i < NX; i++) ground[i + j * NX] = F3D_R(1.0) - F3D_R(0.001) * (f3d_real)i;
  const F3dShallow water = f3d_shallow_create(w, NX, NZ, F3D_R(0.1), 0, 0, 0, ground);
  CHECK(f3d_shallow_set_fluid(w, water, 1000, 1, F3D_R(0.03)) == 1);
  f3d_shallow_set_bed(w, water, F3D_R(0.03), 1);
  const F3dShallowSlot *slot = &w->shallows[water - 1u];
  f3d_real *depth = w->shallow_data + slot->first + NX * NZ;
  for (int c = 0; c < NX * NZ; c++) depth[c] = F3D_R(0.02);
  run(w, 300);
  f3d_real at[4];
  f3d_shallow_sample(w, water, F3D_R(3.2), F3D_R(0.2), at);
  const double h = (double)at[1];
  const double nusselt = STANDARD_G * 0.01 * h * h / (3.0 * 0.001);
  CHECK(h > 0.015 && h < 0.025);
  CHECK_NEAR(at[2], nusselt, 0.1 * nusselt);
  f3d_world_destroy(w);
}

static void test_no_climbing_a_dry_bank(void) {
  /* A sheet of water ten centimetres deep running at a step half a metre
   * high at two metres a second: a flow that fast runs up a wall by
   * v²/2g, twenty centimetres, so it piles up against the step and none
   * gets onto it. */
  F3dWorld *w = f3d_world_create();
  f3d_real ground[40 * 4];
  for (int j = 0; j < 4; j++) {
    for (int i = 0; i < 40; i++) ground[i + j * 40] = i >= 30 ? F3D_R(0.5) : 0;
  }
  const F3dShallow water = f3d_shallow_create(w, 40, 4, F3D_R(0.1), 0, 0, 0, ground);
  f3d_shallow_fill(w, water, 0, 0, F3D_R(2.95), F3D_R(0.4), F3D_R(0.1));
  /* All of it already running at the step at two metres a second. */
  F3dShallowSlot *slot = &w->shallows[water - 1u];
  f3d_real *u = w->shallow_data + slot->first + 2u * 40u * 4u;
  for (int j = 0; j < 4; j++) {
    for (int i = 1; i <= 30; i++) u[i + j * 41] = 2;
  }
  double on_step = 0;
  for (int i = 0; i < 240; i++) {
    run(w, 1);
    f3d_real depth[40 * 4];
    f3d_shallow_read(w, water, NULL, depth);
    for (int j = 0; j < 4; j++) {
      for (int k = 30; k < 40; k++) on_step = fmax(on_step, depth[k + j * 40]);
    }
  }
  CHECK(on_step == 0);
  f3d_world_destroy(w);
}

static void test_open_edge(void) {
  /* A channel open at its ends lets go of what reaches them, and says how
   * much: what is held and what ran off is what there was. */
  F3dWorld *w = f3d_world_create();
  f3d_real ground[32 * 8];
  for (int j = 0; j < 8; j++) {
    for (int i = 0; i < 32; i++) ground[i + j * 32] = (f3d_real)(1.0 - 0.03 * i);
  }
  const F3dShallow water = f3d_shallow_create(w, 32, 8, F3D_R(0.25), 0, 0, 0, ground);
  f3d_shallow_set_bed(w, water, F3D_R(0.03), 1);
  f3d_shallow_pour(w, water, 1, 1, F3D_R(0.5), 1);
  run(w, 600);
  f3d_real held, lost;
  f3d_shallow_volume(w, water, &held, &lost);
  CHECK(lost > 0.3);
  CHECK_NEAR(held + lost, 1, 1e-4);
  f3d_world_destroy(w);
}

static void test_snapshot(void) {
  /* Mid-fall, with spray in the air and a float on the pond, a snapshot
   * goes on exactly as the world would have. */
  F3dWorld *w = f3d_world_create();
  f3d_real *ground = (f3d_real *)malloc(96 * 24 * sizeof(f3d_real));
  const F3dShallow water = falls(w, ground, 96);
  const F3dBody cork = f3d_body_create(w, F3D_BODY_DYNAMIC, 18, 2, 3, F3D_R(0.5));
  f3d_body_set_shape(w, cork, F3D_SHAPE_SPHERE, F3D_R(0.08), 0, 0);
  run(w, 900);
  CHECK(w->s.spray_count > 0);
  const uint32_t size = f3d_world_snapshot_size(w);
  uint8_t *bytes = (uint8_t *)malloc(size);
  CHECK(f3d_world_snapshot_write(w, bytes, size) == size);
  F3dWorld *copy = f3d_world_create();
  CHECK(f3d_world_restore(copy, bytes, size) == 1);
  run(w, 120);
  run(copy, 120);
  f3d_real a[96 * 24], b[96 * 24];
  f3d_shallow_read(w, water, a, NULL);
  f3d_shallow_read(copy, water, b, NULL);
  CHECK(memcmp(a, b, sizeof a) == 0);
  f3d_real pa[3], pb[3];
  f3d_body_get_position(w, cork, pa);
  f3d_body_get_position(copy, cork, pb);
  CHECK(memcmp(pa, pb, sizeof pa) == 0);
  free(bytes);
  free(ground);
  f3d_world_destroy(copy);
  f3d_world_destroy(w);
}

/* A spring at one end of a closed channel and a drain of the same rate at
 * the other: the water keeps its volume and its level, and flows from the
 * one to the other at the rate over the channel's section, Q / (w·d). */
static void test_spring_and_drain_make_a_current(void) {
  F3dWorld *w = f3d_world_create();
  enum { NX = 40, NZ = 8 };
  f3d_real ground[NX * NZ];
  for (int i = 0; i < NX * NZ; i++) ground[i] = -2;
  const F3dShallow water = f3d_shallow_create(w, NX, NZ, 1, 0, 0, 0, ground);
  f3d_shallow_set_bed(w, water, F3D_R(0.02), 0);
  f3d_shallow_fill(w, water, 0, 0, NX, NZ, 0);
  const double before = total(w, water);
  /* Half a cubic metre a second through a section of eight metres by two:
   * three centimetres a second. */
  CHECK(f3d_shallow_set_source(w, water, 0, 2, 4, 2, F3D_R(0.5)) == 1);
  CHECK(f3d_shallow_set_source(w, water, 1, 38, 4, 2, F3D_R(-0.5)) == 1);
  /* The basin sloshes as it starts, a seiche of some eighteen seconds:
   * the current is its mean over a minute. */
  run(w, 60 * 60);
  f3d_real out[8];
  double level = 0, flow = 0;
  for (int i = 0; i < 60 * 60; i++) {
    run(w, 1);
    CHECK(f3d_shallow_sample(w, water, 20, 4, out) == 1);
    level += out[0] / (60 * 60);
    flow += out[2] / (60 * 60);
  }
  CHECK_NEAR(level, 0.0, 0.01);
  CHECK_NEAR(flow, 0.5 / (8 * 2), 0.2 * 0.5 / (8 * 2));
  CHECK_NEAR(total(w, water), before, 0.01 * before);
  f3d_world_destroy(w);
}

static void test_a_resting_pond_wakes_for_a_stone(void) {
  /* A pond left alone comes to rest and is not stepped; a ball dropped
   * from well above it still lands in water, makes waves and floats as
   * deep as it weighs, as in a pond that never rested. */
  const double r = 0.2, mass = 600 * 4.0 / 3.0 * M_PI * r * r * r;
  F3dWorld *w = f3d_world_create();
  const F3dShallow water = pond(w, 64, F3D_R(0.1));
  run(w, 180);
  f3d_real still[64 * 64];
  f3d_shallow_read(w, water, still, NULL);
  const F3dBody ball = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, F3D_R(3.0), 0, (f3d_real)mass);
  f3d_body_set_shape(w, ball, F3D_SHAPE_SPHERE, (f3d_real)r, 0, 0);
  run(w, 600);
  f3d_real moved[64 * 64];
  f3d_shallow_read(w, water, moved, NULL);
  double most = 0;
  for (int c = 0; c < 64 * 64; c++) most = fmax(most, fabs((double)(moved[c] - still[c])));
  CHECK(most > 1e-3);
  /* Both over the same ten seconds: the waves its splash made still run
   * round the closed pond, a centimetre either way. */
  double sum = 0, level = 0;
  for (int i = 0; i < 600; i++) {
    run(w, 1);
    f3d_real p[3], s[4];
    f3d_body_get_position(w, ball, p);
    f3d_shallow_sample(w, water, 2, 0, s);
    sum += p[1];
    level += s[0];
  }
  CHECK_NEAR((sum - level) / 600, -0.027, 0.01);
  f3d_world_destroy(w);
}

static void test_a_weir_holds_a_pool_at_poleni_head(void) {
  /* A basin forty metres by eight, its bed two metres down, fed 0.6 m³/s
   * by a spring and let out over a weir three metres long, its crest 0.6 m
   * above the datum. Come to rest, it lets out what the spring brings, and
   * the pool stands over the crest by the head Poleni's law gives that
   * flow, Q = ⅔ C_d √(2g) b H^1.5, C_d = 0.611 + 0.075 H/P (Rehbock), P the
   * crest's height over the bed — 0.17 m, found here by fixed point. */
  F3dWorld *w = f3d_world_create();
  enum { NX = 40, NZ = 8 };
  f3d_real ground[NX * NZ];
  for (int i = 0; i < NX * NZ; i++) ground[i] = -2;
  const F3dShallow water = f3d_shallow_create(w, NX, NZ, 1, 0, 0, 0, ground);
  f3d_shallow_set_bed(w, water, F3D_R(0.02), 0);
  f3d_shallow_fill(w, water, 0, 0, NX, NZ, F3D_R(0.6));
  CHECK(f3d_shallow_set_outlet(w, water, F3D_SHALLOW_MOST_OUTLETS, 38, 4, F3D_R(0.6), 3, 0) == 0);
  CHECK(f3d_shallow_set_outlet(w, water, 0, 38, 4, F3D_R(0.6), -1, 0) == 0);
  CHECK(f3d_shallow_set_outlet(w, water, 0, 38, 4, F3D_R(0.6), 3, 0) == 1);
  CHECK(f3d_shallow_set_source(w, water, 0, 2, 4, 2, F3D_R(0.6)) == 1);
  /* It fills over a time of A / (dQ/dH), some seventy seconds: ten minutes
   * brings it to rest. */
  run(w, 60 * 600);
  double head = 0.2;
  for (int i = 0; i < 50; i++) {
    const double cd = 0.611 + 0.075 * head / 2.6;
    head = pow(0.6 / (2.0 / 3.0 * cd * sqrt(2 * STANDARD_G) * 3), 2.0 / 3.0);
  }
  f3d_real out[8];
  double level = 0;
  f3d_real lost0, held;
  f3d_shallow_volume(w, water, &held, &lost0);
  for (int i = 0; i < 60 * 20; i++) {
    run(w, 1);
    f3d_shallow_sample(w, water, 30, 4, out);
    level += out[0] / (60 * 20);
  }
  f3d_real lost1;
  f3d_shallow_volume(w, water, &held, &lost1);
  CHECK_NEAR(level - 0.6, head, 0.05 * head);
  CHECK_NEAR(((double)lost1 - (double)lost0) / 20, 0.6, 0.03 * 0.6);
  f3d_world_destroy(w);
}

static void test_edges_carry_a_current_through(void) {
  /* The same basin with no spring: half a cubic metre a second let in over
   * its west edge, its east edge held at the datum's level. The current
   * through its section of eight metres by two is three centimetres a
   * second, the level stays at the datum, and what it holds and what has
   * crossed its edges add up to what it started with. */
  F3dWorld *w = f3d_world_create();
  enum { NX = 40, NZ = 8 };
  f3d_real ground[NX * NZ];
  for (int i = 0; i < NX * NZ; i++) ground[i] = -2;
  const F3dShallow water = f3d_shallow_create(w, NX, NZ, 1, 0, 0, 0, ground);
  f3d_shallow_set_bed(w, water, F3D_R(0.02), 0);
  f3d_shallow_fill(w, water, 0, 0, NX, NZ, 0);
  const double before = total(w, water);
  CHECK(f3d_shallow_set_edge(w, water, 4, F3D_EDGE_FLOW, 1) == 0);
  CHECK(f3d_shallow_set_edge(w, water, 0, F3D_EDGE_LEVEL + 1u, 1) == 0);
  CHECK(f3d_shallow_set_edge(w, water, 0, F3D_EDGE_FLOW, F3D_R(0.5)) == 1);
  CHECK(f3d_shallow_set_edge(w, water, 1, F3D_EDGE_LEVEL, 0) == 1);
  /* The held edge reflects what reaches it, so the basin rings as a pipe
   * open at one end, a seiche of 4L/√(gh), some thirty-six seconds, that
   * its bed's friction damps only slowly: the current is its mean over ten
   * minutes. */
  run(w, 60 * 60);
  f3d_real out[8];
  double level = 0, flow = 0;
  for (int i = 0; i < 60 * 600; i++) {
    run(w, 1);
    f3d_shallow_sample(w, water, 20, 4, out);
    level += out[0] / (60 * 600);
    flow += out[2] / (60 * 600);
  }
  CHECK_NEAR(level, 0.0, 0.01);
  CHECK_NEAR(flow, 0.5 / (8 * 2), 0.1 * 0.5 / (8 * 2));
  CHECK_NEAR(total(w, water), before, 1e-3 * before);
  f3d_real info[F3D_SHALLOW_INFO_FLOATS];
  CHECK(f3d_shallow_info(w, water, info) == 1);
  CHECK(info[0] >= 1 && info[1] == 0 && info[2] == 0);
  f3d_world_destroy(w);
}

static void test_walls_hold_a_dam(void) {
  /* A metre of water on the left half of a channel and none on the right,
   * with a wall of cells between them: nothing crosses, and the left half
   * stays at rest as full as it was. Each cell's own roughness and the
   * splash it throws are refused when they are not numbers. */
  F3dWorld *w = f3d_world_create();
  enum { NX = 32, NZ = 4 };
  f3d_real ground[NX * NZ];
  uint32_t walls[NX * NZ];
  for (int i = 0; i < NX * NZ; i++) {
    ground[i] = 0;
    walls[i] = (i % NX) == NX / 2;
  }
  const F3dShallow water = f3d_shallow_create(w, NX, NZ, F3D_R(0.25), 0, 0, 0, ground);
  CHECK(f3d_shallow_set_cells(w, water, NULL, walls) == 1);
  f3d_shallow_fill(w, water, 0, 0, F3D_R(0.125) * NX, F3D_R(0.25) * NZ, 1);
  const double before = total(w, water);
  run(w, 600);
  f3d_real depth[NX * NZ];
  f3d_shallow_read(w, water, NULL, depth);
  double right = 0;
  for (int z = 0; z < NZ; z++) {
    for (int x = NX / 2 + 1; x < NX; x++) right += depth[z * NX + x];
  }
  CHECK(right == 0);
  CHECK_NEAR(total(w, water), before, 1e-6 * before);
  f3d_real rough[NX * NZ];
  for (int i = 0; i < NX * NZ; i++) rough[i] = -1;
  rough[3] = (f3d_real)NAN;
  CHECK(f3d_shallow_set_cells(w, water, rough, NULL) == 0);
  CHECK(f3d_world_set_water_rest(w, -1, 1) == 0);
  CHECK(f3d_world_set_water_rest(w, F3D_R(5e-4), 1) == 1);
  f3d_world_destroy(w);
}

int main(void) {
  test_a_weir_holds_a_pool_at_poleni_head();
  test_edges_carry_a_current_through();
  test_walls_hold_a_dam();
  test_refusals();
  test_a_resting_pond_wakes_for_a_stone();
  test_spring_and_drain_make_a_current();
  test_a_bag_of_air_lifts_what_it_is_tied_to();
  test_lake_at_rest();
  test_dam_break();
  test_waterfall();
  test_no_spray_on_level_ground();
  test_stone_makes_waves();
  test_a_splash_by_what_strikes();
  test_a_drop_splashes_into_drops_of_its_weber_number();
  test_floats_as_deep_as_it_weighs();
  test_flow_carries_a_float();
  test_column_spreads();
  test_jet_mixes_into_a_pool();
  test_fluids();
  test_ball_settles_through_honey();
  test_ball_falls_through_water_at_newtons_speed();
  test_a_light_ball_carries_water_with_it();
  test_a_body_driven_through_water_sets_it_moving();
  test_flow_keeps_its_momentum();
  test_a_float_slides_down_the_surface();
  test_a_thick_film_runs_as_nusselt_says();
  test_no_climbing_a_dry_bank();
  test_open_edge();
  test_snapshot();
  return finish();
}
