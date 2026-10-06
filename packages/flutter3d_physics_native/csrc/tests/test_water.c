/*
 * Water over ground, tested in C: what it refuses, a lake at rest staying
 * at rest over a bumpy bed, a dam breaking with not a drop made or lost, a
 * spring feeding a stream off a cliff into a pond, the spray only at the
 * cliff, a stone's waves, a ball floating as deep as Archimedes says, the
 * flow carrying a float, an open edge letting water go, and water through
 * a snapshot.
 */
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "check.h"

static void run(F3dWorld *w, int steps) {
  for (int i = 0; i < steps; i++) f3d_world_step(w, F3D_R(1.0) / 60);
}

static double total(F3dWorld *w, F3dWater water) {
  f3d_real held, lost;
  f3d_water_volume(w, water, &held, &lost);
  return (double)held + (double)lost;
}

static void test_refusals(void) {
  F3dWorld *w = f3d_world_create();
  f3d_real ground[4] = {0, 0, 0, 0};
  CHECK(f3d_water_create(w, 0, 2, 1, 0, 0, 0, ground) == 0);
  CHECK(f3d_water_create(w, 2, 2, 0, 0, 0, 0, ground) == 0);
  CHECK(f3d_water_create(w, 2, 2, 1, 0, 0, 0, NULL) == 0);
  ground[2] = nan_value();
  CHECK(f3d_water_create(w, 2, 2, 1, 0, 0, 0, ground) == 0);
  ground[2] = 0;
  const F3dWater water = f3d_water_create(w, 2, 2, 1, 0, 0, 0, ground);
  CHECK(water == 1);
  CHECK(f3d_water_set_source(w, water, F3D_WATER_MOST_SOURCES, 0, 0, 1, 1) == 0);
  CHECK(f3d_water_set_source(w, water, 0, 0, 0, 1, -1) == 0);
  CHECK(f3d_water_set_bed(w, water, -1, 0) == 0);
  f3d_real out[4];
  CHECK(f3d_water_sample(w, water, 5, 5, out) == 0);
  CHECK(f3d_water_destroy(w, water) == 1);
  CHECK(!f3d_water_is_valid(w, water));
  CHECK(f3d_water_destroy(w, water) == 0);
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
  const F3dWater water = f3d_water_create(w, 32, 32, F3D_R(0.25), 0, 0, 0, ground);
  f3d_water_fill(w, water, 0, 0, 8, 8, F3D_R(0.5));
  run(w, 300);
  f3d_real surface[32 * 32], flow[2 * 32 * 32];
  f3d_water_read(w, water, surface, NULL);
  f3d_water_read_flow(w, water, flow);
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
  const F3dWater water = f3d_water_create(w, 64, 16, F3D_R(0.1), 0, 0, 0, ground);
  f3d_water_fill(w, water, 0, 0, 2, F3D_R(1.6), F3D_R(0.5));
  const double before = total(w, water);
  double far_end = 0;
  for (int i = 0; i < 600; i++) {
    run(w, 1);
    f3d_real s[4];
    f3d_water_sample(w, water, F3D_R(6.35), F3D_R(0.8), s);
    if (s[1] > far_end) far_end = s[1];
  }
  CHECK_NEAR(total(w, water), before, 1e-5 * before);
  /* The wave reached the far end, four metres off, and piled up there. */
  CHECK(far_end > 0.15);
  f3d_world_destroy(w);
}

/* A stream bed from a spring down a slope to a cliff three metres high,
 * and a pond at its foot: [nx] × 24 cells of a quarter metre. */
static F3dWater falls(F3dWorld *w, f3d_real *ground, int nx) {
  for (int j = 0; j < 24; j++) {
    for (int i = 0; i < nx; i++) {
      const double x = i * 0.25;
      const double channel = 0.4 * fabs((j - 12) * 0.25);
      ground[i + j * nx] = (f3d_real)(x < 12 ? 4.0 - 0.1 * x + channel
                                             : 0.02 * fabs(x - 18) + 0.2 * channel);
    }
  }
  const F3dWater water = f3d_water_create(w, (uint32_t)nx, 24, F3D_R(0.25), 0, 0, 0, ground);
  f3d_water_fill(w, water, F3D_R(12.2), 0, 24, 6, F3D_R(0.8));
  f3d_water_set_source(w, water, 0, 1, 3, F3D_R(0.5), F3D_R(0.05));
  return water;
}

static void test_waterfall(void) {
  /* A spring of fifty litres a second runs down the slope as a stream, off
   * the cliff as spray, and into the pond: twenty seconds put in exactly
   * one cubic metre more, wherever it is. */
  F3dWorld *w = f3d_world_create();
  f3d_real *ground = (f3d_real *)malloc(96 * 24 * sizeof(f3d_real));
  const F3dWater water = falls(w, ground, 96);
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
  /* The stream runs: a shallow sheet moving downhill. */
  f3d_real s[4];
  f3d_water_sample(w, water, 6, 3, s);
  CHECK(s[1] > 0.02 && s[1] < 0.3);
  CHECK(s[2] > 0.3);
  free(ground);
  f3d_world_destroy(w);
}

static void test_no_spray_on_level_ground(void) {
  /* A dam breaking on level ground throws waves steeper than a cell, and
   * none of it is a waterfall. */
  F3dWorld *w = f3d_world_create();
  f3d_real ground[64 * 16];
  memset(ground, 0, sizeof ground);
  const F3dWater water = f3d_water_create(w, 64, 16, F3D_R(0.05), 0, 0, 0, ground);
  f3d_water_fill(w, water, 0, 0, 1, 1, F3D_R(0.6));
  uint32_t most = 0;
  for (int i = 0; i < 300; i++) {
    run(w, 1);
    if (w->s.spray_count > most) most = w->s.spray_count;
  }
  CHECK(most == 0);
  f3d_world_destroy(w);
}

/* A pond [n] cells of [cell] across, a metre deep, centred on the origin. */
static F3dWater pond(F3dWorld *w, int n, f3d_real cell) {
  f3d_real *ground = (f3d_real *)calloc((size_t)n * n, sizeof(f3d_real));
  const F3dWater water =
      f3d_water_create(w, (uint32_t)n, (uint32_t)n, cell, -n * cell / 2, 0, -n * cell / 2, ground);
  free(ground);
  f3d_water_fill(w, water, -99, -99, 99, 99, 1);
  return water;
}

static void test_stone_makes_waves(void) {
  /* A five kilogram stone dropped in raises a wave a metre off, and the
   * pond holds what it held. */
  F3dWorld *w = f3d_world_create();
  const F3dWater water = pond(w, 48, F3D_R(0.1));
  const double before = total(w, water);
  const F3dBody stone = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, F3D_R(1.5), 0, 5);
  f3d_body_set_shape(w, stone, F3D_SHAPE_SPHERE, F3D_R(0.1), 0, 0);
  double most = 0;
  for (int i = 0; i < 120; i++) {
    run(w, 1);
    f3d_real s[4];
    f3d_water_sample(w, water, 1, 0, s);
    if (fabs((double)s[0] - 1.0) > most) most = fabs((double)s[0] - 1.0);
  }
  CHECK(most > 0.003);
  CHECK_NEAR(total(w, water), before, 1e-5 * before);
  f3d_world_destroy(w);
}

static void test_floats_as_deep_as_it_weighs(void) {
  /* A ball of 0.2 m at six tenths of water's density, dropped into a
   * pond: it rides with three fifths of it under, its centre 2.7 cm below
   * the surface on the whole, bobbing on the waves its fall made as the
   * pond's walls throw them back. */
  const double r = 0.2, mass = 600 * 4.0 / 3.0 * M_PI * r * r * r;
  F3dWorld *w = f3d_world_create();
  const F3dWater water = pond(w, 64, F3D_R(0.1));
  const F3dBody ball = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, F3D_R(0.973), 0, (f3d_real)mass);
  f3d_body_set_shape(w, ball, F3D_SHAPE_SPHERE, (f3d_real)r, 0, 0);
  run(w, 300);
  double sum = 0, lo = 9, hi = -9;
  for (int i = 0; i < 600; i++) {
    run(w, 1);
    f3d_real p[3];
    f3d_body_get_position(w, ball, p);
    sum += p[1];
    lo = fmin(lo, p[1]);
    hi = fmax(hi, p[1]);
  }
  f3d_real s[4];
  f3d_water_sample(w, water, 2, 0, s);
  /* Below the surface by what three fifths under puts it, give or take a
   * centimetre of the grid's ten. */
  CHECK_NEAR(sum / 600 - s[0], -0.027, 0.01);
  CHECK(hi - lo < 0.1);
  f3d_world_destroy(w);
}

static void test_flow_carries_a_float(void) {
  /* A float on a stream drifts downstream with it. */
  F3dWorld *w = f3d_world_create();
  f3d_real *ground = (f3d_real *)malloc(96 * 24 * sizeof(f3d_real));
  const F3dWater water = falls(w, ground, 96);
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
  const F3dWater water = f3d_water_create(w, 16, 16, F3D_R(0.2), 0, 0, 0, ground);
  f3d_water_pour(w, water, F3D_R(1.7), F3D_R(1.7), 0, F3D_R(0.08));
  const double before = total(w, water);
  f3d_real depth[16 * 16];
  double least = 1;
  for (int i = 0; i < 20; i++) {
    f3d_world_step(w, 1);
    f3d_water_read(w, water, NULL, depth);
    for (int c = 0; c < 16 * 16; c++) least = fmin(least, depth[c]);
  }
  CHECK(least >= 0);
  CHECK_NEAR(total(w, water), before, 1e-6 * before + 1e-9);
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
  const F3dWater water = f3d_water_create(w, 40, 4, F3D_R(0.1), 0, 0, 0, ground);
  f3d_water_fill(w, water, 0, 0, F3D_R(2.95), F3D_R(0.4), F3D_R(0.1));
  /* All of it already running at the step at two metres a second. */
  F3dWaterSlot *slot = &w->waters[water - 1u];
  f3d_real *u = w->water_data + slot->first + 2u * 40u * 4u;
  for (int j = 0; j < 4; j++) {
    for (int i = 1; i <= 30; i++) u[i + j * 41] = 2;
  }
  double on_step = 0;
  for (int i = 0; i < 240; i++) {
    run(w, 1);
    f3d_real depth[40 * 4];
    f3d_water_read(w, water, NULL, depth);
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
  const F3dWater water = f3d_water_create(w, 32, 8, F3D_R(0.25), 0, 0, 0, ground);
  f3d_water_set_bed(w, water, F3D_R(0.03), 1);
  f3d_water_pour(w, water, 1, 1, F3D_R(0.5), 1);
  run(w, 600);
  f3d_real held, lost;
  f3d_water_volume(w, water, &held, &lost);
  CHECK(lost > 0.3);
  CHECK_NEAR(held + lost, 1, 1e-4);
  f3d_world_destroy(w);
}

static void test_snapshot(void) {
  /* Mid-fall, with spray in the air and a float on the pond, a snapshot
   * goes on exactly as the world would have. */
  F3dWorld *w = f3d_world_create();
  f3d_real *ground = (f3d_real *)malloc(96 * 24 * sizeof(f3d_real));
  const F3dWater water = falls(w, ground, 96);
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
  f3d_water_read(w, water, a, NULL);
  f3d_water_read(copy, water, b, NULL);
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

int main(void) {
  test_refusals();
  test_lake_at_rest();
  test_dam_break();
  test_waterfall();
  test_no_spray_on_level_ground();
  test_stone_makes_waves();
  test_floats_as_deep_as_it_weighs();
  test_flow_carries_a_float();
  test_column_spreads();
  test_no_climbing_a_dry_bank();
  test_open_edge();
  test_snapshot();
  return finish();
}
