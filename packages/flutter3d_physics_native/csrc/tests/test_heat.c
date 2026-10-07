/*
 * Heat and fire on bodies, tested in C — P9: the heat bus, Newton's
 * cooling against its closed form and a thick ball against the series, a
 * log that catches at its surface, radiation that cannot overshoot, wind
 * that cools, ignition, a fire that burns its fuel out, and water that
 * keeps a body from catching and puts a fire out.
 */
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "check.h"

static F3dBody wood_block(F3dWorld *w) {
  /* A pine block ten centimetres on a side: 0.6 kg. Fixed, so it stays
   * where it is while it burns. */
  const F3dBody b = f3d_body_create(w, F3D_BODY_FIXED, 0, 0, 0, F3D_R(0.6));
  f3d_body_set_shape(w, b, F3D_SHAPE_BOX, F3D_R(0.05), F3D_R(0.05), F3D_R(0.05));
  F3dMaterial m;
  f3d_material_preset(F3D_MATERIAL_WOOD, &m);
  f3d_body_set_material(w, b, &m);
  return b;
}

static int burning(F3dWorld *w, F3dBody b) {
  int on = 0;
  f3d_body_is_burning(w, b, &on);
  return on;
}

static void test_materials(void) {
  F3dMaterial m;
  for (int kind = F3D_MATERIAL_INERT; kind <= F3D_MATERIAL_STONE; kind++) {
    CHECK(f3d_material_preset((F3dMaterialKind)kind, &m) == 1);
    CHECK(m.specific_heat > 0 && m.emissivity > 0 && m.emissivity <= 1);
    CHECK(m.fuel_fraction < 1);
  }
  CHECK(f3d_material_preset((F3dMaterialKind)99, &m) == 0);
  F3dWorld *w = f3d_world_create();
  const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 2);
  f3d_material_preset(F3D_MATERIAL_WOOD, &m);
  F3dMaterial bad = m;
  bad.specific_heat = 0;
  CHECK(f3d_body_set_material(w, b, &bad) == 0);
  bad = m;
  bad.emissivity = 2;
  CHECK(f3d_body_set_material(w, b, &bad) == 0);
  bad = m;
  bad.fuel_fraction = 1;
  CHECK(f3d_body_set_material(w, b, &bad) == 0);
  bad = m;
  bad.flame_feedback = -1;
  CHECK(f3d_body_set_material(w, b, &bad) == 0);
  bad = m;
  bad.burn_rate = nan_value();
  CHECK(f3d_body_set_material(w, b, &bad) == 0);
  CHECK(f3d_body_set_material(w, b, NULL) == 0);
  CHECK(f3d_body_set_material(w, b, &m) == 1);
  f3d_real fuel;
  f3d_body_get_fuel(w, b, &fuel);
  CHECK_NEAR(fuel, 2 * 0.8, 1e-6);
  /* A new body is at the air's temperature. */
  f3d_real t;
  f3d_body_get_temperature(w, b, &t);
  CHECK(t == F3D_R(293.15));
  CHECK(f3d_body_set_temperature(w, b, 0) == 0);
  CHECK(f3d_body_set_temperature(w, b, nan_value()) == 0);
  CHECK(f3d_body_add_heat(w, b, inf_value()) == 0);
  CHECK(f3d_body_add_water(w, b, nan_value()) == 0);
  f3d_world_destroy(w);
}

static void test_heat_bus(void) {
  /* A point has no surface to lose heat through: two kilojoules into two
   * kilograms of a thousand J/(kg K) is one kelvin, exactly. */
  F3dWorld *w = f3d_world_create();
  f3d_world_set_gravity(w, 0, 0, 0);
  const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 2);
  f3d_body_add_heat(w, b, 1500);
  f3d_body_add_heat(w, b, 500);
  f3d_world_step(w, F3D_R(0.25));
  f3d_real t;
  f3d_body_get_temperature(w, b, &t);
  CHECK_NEAR(t, 294.15, 1e-6);
  /* Spent: the next step adds nothing. */
  f3d_world_step(w, F3D_R(0.25));
  f3d_body_get_temperature(w, b, &t);
  CHECK_NEAR(t, 294.15, 1e-6);
  /* And taken out the same way. */
  f3d_body_add_heat(w, b, -4000);
  f3d_world_step(w, 1);
  f3d_body_get_temperature(w, b, &t);
  CHECK_NEAR(t, 292.15, 1e-6);
  f3d_world_destroy(w);
}

/* The mean temperature above the air, over where it started, of a ball of
 * radius 5 cm and a kilogram at 1000 J/(kg K) and [conductivity], that
 * does not radiate, after cooling in still air for 3000 s. */
static double cooled(f3d_real conductivity) {
  F3dWorld *w = f3d_world_create();
  f3d_world_set_gravity(w, 0, 0, 0);
  const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 1);
  f3d_body_set_shape(w, b, F3D_SHAPE_SPHERE, F3D_R(0.05), 0, 0);
  F3dMaterial m;
  f3d_material_preset(F3D_MATERIAL_INERT, &m);
  m.emissivity = 0;
  m.conductivity = conductivity;
  f3d_body_set_material(w, b, &m);
  f3d_body_set_temperature(w, b, F3D_R(393.15));
  for (int i = 0; i < 3000; i++) f3d_world_step(w, 1);
  f3d_real t;
  f3d_body_get_temperature(w, b, &t);
  f3d_world_destroy(w);
  return ((double)t - 293.15) / 100.0;
}

static void test_newton_cooling(void) {
  /* A ball that does not radiate cools by convection alone, in still air
   * at 10.45 W/(m² K). Of copper, all one temperature throughout (Biot's
   * number hr/k a thousandth): T − Tₐ = (T₀ − Tₐ) e^(−hA t / C). */
  const double area = 4 * 3.14159265358979 * 0.05 * 0.05;
  const double tau = 1000.0 / (10.45 * area);
  CHECK_NEAR(cooled(400), exp(-3000.0 / tau), 1e-3);
  /* Of a conductivity of 1 W/(m K), Biot's number is a half, and its
   * surface runs cold ahead of its middle: it cools slower than that, as
   * the series solution for a sphere says — its mean at 0.4097 of where it
   * started, summed to forty terms, where one temperature would be at
   * 0.3735. The heat balance integral is within a few per cent of it. */
  CHECK_NEAR(cooled(1), 0.4097, 0.015);
}

static void test_radiation_cannot_overshoot(void) {
  /* A sheet of steel at a thousand kelvin, stepped a hundred seconds at a
   * time: every step lands between where it was and the air, never past
   * the air. */
  F3dWorld *w = f3d_world_create();
  const F3dBody b = f3d_body_create(w, F3D_BODY_FIXED, 0, 0, 0, F3D_R(0.01));
  f3d_body_set_shape(w, b, F3D_SHAPE_BOX, F3D_R(0.1), F3D_R(0.0005), F3D_R(0.1));
  F3dMaterial m;
  f3d_material_preset(F3D_MATERIAL_STEEL, &m);
  f3d_body_set_material(w, b, &m);
  f3d_body_set_temperature(w, b, 1000);
  f3d_real last = 1000, t = 0;
  int ok = 1;
  for (int i = 0; i < 50; i++) {
    f3d_world_step(w, 100);
    f3d_body_get_temperature(w, b, &t);
    /* Within rounding: at the air's temperature a step can land an ulp
     * either side of it. */
    ok &= t <= last * (1 + 1e-12) && t >= F3D_R(293.15) * (1 - 1e-12);
    last = t;
  }
  CHECK(ok);
  CHECK_NEAR(t, 293.15, 1e-4);
  f3d_world_destroy(w);
}

static void test_wind_cools(void) {
  F3dWorld *w = f3d_world_create();
  const F3dBody still = f3d_body_create(w, F3D_BODY_FIXED, 0, 0, 0, 1);
  const F3dBody windy = f3d_body_create(w, F3D_BODY_FIXED, 10, 0, 0, 1);
  f3d_body_set_shape(w, still, F3D_SHAPE_SPHERE, F3D_R(0.1), 0, 0);
  f3d_body_set_shape(w, windy, F3D_SHAPE_SPHERE, F3D_R(0.1), 0, 0);
  f3d_body_set_temperature(w, still, 400);
  f3d_body_set_temperature(w, windy, 400);
  /* Wind only where the second one stands. */
  const f3d_real grid[6] = {0, 0, 0, 10, 0, 0};
  f3d_world_set_wind_grid(w, 0, 0, 0, 10, 2, 1, 1, grid);
  for (int i = 0; i < 100; i++) f3d_world_step(w, 1);
  f3d_real a, b;
  f3d_body_get_temperature(w, still, &a);
  f3d_body_get_temperature(w, windy, &b);
  CHECK(b < a);
  CHECK(a < 400);
  f3d_world_destroy(w);
}

static void test_fire(void) {
  F3dWorld *w = f3d_world_create();
  const F3dBody block = wood_block(w);
  F3dBody bodies[8];
  uint32_t kinds[8];
  f3d_real fires[F3D_FIRE_FLOATS * 2];
  CHECK(f3d_world_read_fires(w, fires, NULL, 2) == 0);
  /* Below its ignition point it only cools. */
  f3d_body_set_temperature(w, block, 560);
  f3d_world_step(w, F3D_R(0.1));
  CHECK(!burning(w, block));
  /* Above it, it catches, and says so. */
  f3d_body_set_temperature(w, block, 600);
  f3d_world_step(w, F3D_R(0.1));
  CHECK(burning(w, block));
  CHECK(f3d_world_read_events(w, bodies, NULL, kinds, 8) == 1);
  CHECK(bodies[0] == block && kinds[0] == F3D_EVENT_IGNITED);
  /* Alight, it loses 11 g/s per m² of its 0.06 m², gives 15 MJ/kg, and
   * keeps three tenths of it: it heats itself, and the rest leaves. */
  for (int i = 0; i < 100; i++) f3d_world_step(w, F3D_R(0.1));
  f3d_real t, mass, fuel, release;
  f3d_body_get_temperature(w, block, &t);
  CHECK(t > 600);
  const double rate = 0.011 * 0.06;
  f3d_body_get_mass(w, block, &mass);
  CHECK_NEAR(mass, 0.6 - rate * 10.0, 1e-4);
  f3d_body_get_fuel(w, block, &fuel);
  CHECK_NEAR(fuel, 0.48 - rate * 10.0, 1e-4);
  f3d_body_get_heat_release(w, block, &release);
  CHECK_NEAR(release, 0.7 * rate * 1.5e7, 1e-4);
  F3dBody handle = 0;
  CHECK(f3d_world_read_fires(w, fires, &handle, 2) == 1);
  CHECK(handle == block && fires[3] == release);
  /* It burns until its fuel is gone, about twelve minutes, then goes out
   * and cools, a fifth of its mass left as char. */
  int steps = 0;
  while (burning(w, block) && steps < 10000) {
    f3d_world_step(w, F3D_R(0.1));
    steps++;
  }
  CHECK_NEAR(steps * 0.1 + 10.1, 0.48 / rate, 1e-2);
  CHECK(f3d_world_read_events(w, bodies, NULL, kinds, 8) == 1);
  CHECK(kinds[0] == F3D_EVENT_BURNT_OUT);
  f3d_body_get_fuel(w, block, &fuel);
  CHECK(fuel == 0);
  f3d_body_get_mass(w, block, &mass);
  CHECK_NEAR(mass, 0.12, 1e-4);
  f3d_body_get_heat_release(w, block, &release);
  for (int i = 0; i < 100; i++) f3d_world_step(w, 1);
  f3d_body_get_temperature(w, block, &t);
  CHECK(t < 600 && !burning(w, block));
  /* Inert matter never catches, however hot. */
  const F3dBody stone = f3d_body_create(w, F3D_BODY_FIXED, 0, 0, 0, 1);
  f3d_body_set_shape(w, stone, F3D_SHAPE_SPHERE, F3D_R(0.1), 0, 0);
  f3d_body_set_temperature(w, stone, 2000);
  f3d_world_step(w, F3D_R(0.1));
  CHECK(!burning(w, stone));
  f3d_world_destroy(w);
}

static F3dBody stone_ball(F3dWorld *w, f3d_real x) {
  const F3dBody b = f3d_body_create(w, F3D_BODY_FIXED, x, 0, 0, 10);
  f3d_body_set_shape(w, b, F3D_SHAPE_SPHERE, F3D_R(0.2), 0, 0);
  F3dMaterial m;
  f3d_material_preset(F3D_MATERIAL_STONE, &m);
  f3d_body_set_material(w, b, &m);
  return b;
}

/* What a stone ball of 0.2 m at [hot] K gives, in one tenth of a second,
 * to one at the air's temperature [d] metres off, as the cold one's rise in
 * kelvin over what it does alone; with a wall between them when [walled]. */
static double warmed(double hot, double d, int walled, double *source) {
  f3d_real t[2];
  for (int pair = 0; pair < 2; pair++) {
    F3dWorld *w = f3d_world_create();
    const F3dBody a = pair ? stone_ball(w, 0) : 0;
    const F3dBody b = stone_ball(w, (f3d_real)d);
    if (walled) {
      const F3dBody wall = f3d_body_create(w, F3D_BODY_FIXED, (f3d_real)(d / 2), 0, 0, 0);
      f3d_body_set_shape(w, wall, F3D_SHAPE_BOX, F3D_R(0.02), 1, 1);
    }
    if (pair) f3d_body_set_temperature(w, a, (f3d_real)hot);
    f3d_world_step(w, F3D_R(0.1));
    f3d_body_get_temperature(w, b, &t[pair]);
    if (pair && source != NULL) {
      f3d_real ta;
      f3d_body_get_temperature(w, a, &ta);
      *source = ta;
    }
    f3d_world_destroy(w);
  }
  return (double)t[1] - (double)t[0];
}

static void test_radiation_between_bodies(void) {
  /* A ball at 1000 K catches, on one half a metre off, its solid angle's
   * share of what it gives above the room — εσA(T⁴ − Tₐ⁴) — as much as the
   * other's emissivity takes in. The hot one gave that up to the room
   * already: it cools exactly as it would alone. */
  double hot_in_pair, hot_alone;
  const double near = warmed(1000, 0.5, 0, &hot_in_pair);
  {
    F3dWorld *w = f3d_world_create();
    const F3dBody a = stone_ball(w, 0);
    f3d_body_set_temperature(w, a, 1000);
    f3d_world_step(w, F3D_R(0.1));
    f3d_real t;
    f3d_body_get_temperature(w, a, &t);
    hot_alone = t;
    f3d_world_destroy(w);
  }
  CHECK(hot_in_pair == hot_alone);
  const double e = 0.93, sigma = 5.670374419e-8, ta = 293.15;
  const double area = 4 * M_PI * 0.2 * 0.2;
  const double s = 0.2 / 0.5;
  const double share = 0.5 * (1 - sqrt(1 - s * s));
  const double gain = e * share * e * sigma * area * (pow(1000, 4) - pow(ta, 4)) * 0.1;
  /* Ten kilograms of stone at 840 J/(kg K); its own losses, at the room's
   * temperature, nought. */
  CHECK_NEAR(near, gain / (10 * 840), 0.01 * gain / (10 * 840));
  /* Two metres off it fills a sixteenth of the sky it did. */
  CHECK(warmed(1000, 2, 0, NULL) < near / 10);
  /* A wall between them: nothing. */
  CHECK(warmed(1000, 0.5, 1, NULL) == 0);
  /* A cold ball draws heat from one at the room's temperature. */
  CHECK(warmed(200, 0.5, 0, NULL) < 0);
  /* And one at the room's temperature gives nothing. */
  CHECK(warmed(ta, 0.5, 0, NULL) == 0);
}

static F3dBody crate(F3dWorld *w, f3d_real x, f3d_real y) {
  /* A wooden crate half a metre on a side, ten kilograms of planks. */
  const F3dBody b = f3d_body_create(w, F3D_BODY_FIXED, x, y, 0, 10);
  f3d_body_set_shape(w, b, F3D_SHAPE_BOX, F3D_R(0.25), F3D_R(0.25), F3D_R(0.25));
  F3dMaterial m;
  f3d_material_preset(F3D_MATERIAL_WOOD, &m);
  f3d_body_set_material(w, b, &m);
  return b;
}

/* When each of a burning crate, one stacked on it, one beside it, the next
 * in that row and one four metres off catches, s, or −1; and how warm the
 * far one gets. A wind of [wind] m/s blows along the row. */
static void blaze(f3d_real wind, int when[5], f3d_real *far_peak) {
  F3dWorld *w = f3d_world_create();
  f3d_world_set_wind(w, wind, 0, 0);
  const F3dBody all[5] = {crate(w, 0, F3D_R(0.25)), crate(w, 0, F3D_R(0.76)),
                          crate(w, F3D_R(0.52), F3D_R(0.25)),
                          crate(w, F3D_R(1.1), F3D_R(0.25)),
                          crate(w, 4, F3D_R(0.25))};
  f3d_body_set_temperature(w, all[0], 700);
  for (int k = 0; k < 5; k++) when[k] = -1;
  *far_peak = 0;
  for (int i = 0; i < 1500; i++) {
    f3d_world_step(w, 1);
    for (int k = 0; k < 5; k++) {
      if (when[k] < 0 && burning(w, all[k])) when[k] = i;
    }
    f3d_real t;
    f3d_body_get_temperature(w, all[4], &t);
    if (t > *far_peak) *far_peak = t;
  }
  f3d_world_destroy(w);
}

static void test_fire_spreads(void) {
  /* In still air the fire climbs first, into the crate standing in its
   * flame, then reaches the one beside it, which both fires shine on, and
   * then the next in the row, eight centimetres from it; the one four
   * metres off only warms. */
  int when[5];
  f3d_real far;
  blaze(0, when, &far);
  CHECK(when[0] == 0);
  CHECK(when[1] > 0 && when[1] < 300);
  CHECK(when[2] > when[1]);
  CHECK(when[3] > when[2] && when[4] < 0);
  CHECK(far < 310);
  /* Two metres a second along the row lays the flame over the crate beside
   * it, away from the one above: the fire runs downwind, down the row. */
  int windy[5];
  blaze(2, windy, &far);
  CHECK(windy[2] > 0 && windy[2] < windy[1]);
  CHECK(windy[3] > windy[2]);
  CHECK(windy[4] < 0);
}

/* A pine beam two metres long, ten centimetres square, as five boxes end
 * to end: one fixed body of 16 kg, lying along x or standing along y. */
static F3dBody beam(F3dWorld *w, int upright) {
  uint32_t kinds[5];
  f3d_real reals[5 * F3D_COMPOUND_PART_FLOATS];
  memset(reals, 0, sizeof reals);
  for (int k = 0; k < 5; k++) {
    kinds[k] = F3D_SHAPE_BOX;
    f3d_real *r = &reals[k * F3D_COMPOUND_PART_FLOATS];
    const f3d_real along = (f3d_real)(-0.8 + 0.4 * k);
    r[0] = upright ? F3D_R(0.05) : F3D_R(0.2);
    r[1] = upright ? F3D_R(0.2) : F3D_R(0.05);
    r[2] = F3D_R(0.05);
    r[upright ? 5 : 4] = along;
    r[10] = 1;
  }
  const uint32_t shape = f3d_world_create_compound(w, kinds, NULL, reals, 5);
  const F3dBody b = f3d_body_create(w, F3D_BODY_FIXED, 0,
                                    upright ? F3D_R(1.0) : F3D_R(0.05), 0, 16);
  f3d_body_set_compound(w, b, shape);
  F3dMaterial m;
  f3d_material_preset(F3D_MATERIAL_WOOD, &m);
  f3d_body_set_material(w, b, &m);
  return b;
}

/* When each part of a beam lit at its first part catches, s, or −1. */
static void burn_beam(int upright, int when[5], f3d_real *second_part_peak) {
  F3dWorld *w = f3d_world_create();
  const F3dBody b = beam(w, upright);
  f3d_body_set_part_temperature(w, b, 0, 700);
  for (int k = 0; k < 5; k++) when[k] = -1;
  *second_part_peak = 0;
  for (int i = 0; i < 3000; i++) {
    f3d_world_step(w, 1);
    for (int k = 0; k < 5; k++) {
      int on = 0;
      f3d_body_is_part_burning(w, b, (uint32_t)k, &on);
      if (on && when[k] < 0) when[k] = i;
    }
    f3d_real t;
    f3d_body_get_part_temperature(w, b, 1, &t);
    if (t > *second_part_peak) *second_part_peak = t;
  }
  f3d_world_destroy(w);
}

static void test_a_beam_burns_from_one_end(void) {
  /* A compound's parts have their heat each. A beam stood on end and lit at
   * the bottom burns upwards a part at a time, each catching in the flame
   * of the one below. Laid flat and lit at one end, it warms the part
   * beside the fire and goes no further, as a lone log on its side does in
   * still air: its flame stands over the burning end, not along it. */
  int up[5], flat[5];
  f3d_real peak_up, peak_flat;
  burn_beam(1, up, &peak_up);
  burn_beam(0, flat, &peak_flat);
  CHECK(up[0] == 0);
  for (int k = 1; k < 5; k++) CHECK(up[k] > up[k - 1]);
  CHECK(flat[0] == 0);
  for (int k = 1; k < 5; k++) CHECK(flat[k] < 0);
  CHECK(peak_flat > 310 && peak_flat < 573);
  F3dWorld *w = f3d_world_create();
  const F3dBody b = beam(w, 0);
  CHECK(f3d_body_set_part_temperature(w, b, 0, 700) == 1);
  CHECK(f3d_body_set_part_temperature(w, b, 5, 700) == 0);
  f3d_real t;
  f3d_body_get_temperature(w, b, &t);
  CHECK_NEAR(t, (700 + 4 * 293.15) / 5, 0.01);
  f3d_world_destroy(w);
  /* Heat given to the body as a whole warms every part alike: shared out
   * by what each holds. */
  w = f3d_world_create();
  const F3dBody even = beam(w, 0);
  f3d_body_add_heat(w, even, 16 * 1700 * 10);
  f3d_world_step(w, F3D_R(0.001));
  for (uint32_t k = 0; k < 5; k++) {
    f3d_real tk;
    f3d_body_get_part_temperature(w, even, k, &tk);
    CHECK_NEAR(tk, 303.15, 0.05);
  }
  f3d_world_destroy(w);
  /* A steel bar's parts pass heat along it: one end at 800 K warms the part
   * beside it by conduction within a minute, far more than the air and the
   * glow could. */
  w = f3d_world_create();
  const F3dBody bar = beam(w, 0);
  F3dMaterial steel;
  f3d_material_preset(F3D_MATERIAL_STEEL, &steel);
  f3d_body_set_material(w, bar, &steel);
  f3d_body_set_part_temperature(w, bar, 0, 800);
  for (int i = 0; i < 60; i++) f3d_world_step(w, 1);
  f3d_real next_to;
  f3d_body_get_part_temperature(w, bar, 1, &next_to);
  CHECK(next_to > 330);
  f3d_world_destroy(w);
  /* The body said it caught once, when its first part did. */
  F3dBody bodies[16];
  uint32_t kinds[16];
  w = f3d_world_create();
  const F3dBody c = beam(w, 0);
  f3d_body_set_part_temperature(w, c, 0, 700);
  f3d_world_step(w, 1);
  CHECK(f3d_world_read_events(w, bodies, NULL, kinds, 16) == 1);
  CHECK(kinds[0] == F3D_EVENT_IGNITED);
  /* A fire is where its part burns, at that end of the beam. */
  f3d_real fires[F3D_FIRE_FLOATS * 4];
  F3dBody named[4];
  CHECK(f3d_world_read_fires(w, fires, named, 4) == 1);
  CHECK(named[0] == c);
  CHECK_NEAR(fires[0], -0.8, 1e-5);
  /* A step after it caught, the beam is lighter by what that part burnt,
   * the rest untouched. */
  f3d_world_step(w, 1);
  f3d_real mass;
  f3d_body_get_mass(w, c, &mass);
  CHECK(mass < 16 && mass > 16 - 0.01);
  /* Heat held to the other end goes into that end. */
  f3d_real before;
  f3d_body_get_part_temperature(w, c, 3, &before);
  CHECK(f3d_body_add_heat_at(w, c, F3D_R(0.85), F3D_R(0.05), 0, 500000) == 1);
  f3d_world_step(w, F3D_R(0.01));
  f3d_real end, middle;
  f3d_body_get_part_temperature(w, c, 4, &end);
  f3d_body_get_part_temperature(w, c, 3, &middle);
  /* Half a megajoule on 3.2 kg of pine: about ninety kelvin. */
  CHECK(end > 370);
  CHECK(middle < before + 1);
  /* Through a snapshot, every part goes on as it would have. */
  const uint32_t size = f3d_world_snapshot_size(w);
  uint8_t *bytes = (uint8_t *)malloc(size);
  CHECK(f3d_world_snapshot_write(w, bytes, size) == size);
  F3dWorld *copy = f3d_world_create();
  CHECK(f3d_world_restore(copy, bytes, size) == 1);
  for (int i = 0; i < 50; i++) {
    f3d_world_step(w, 1);
    f3d_world_step(copy, 1);
  }
  for (uint32_t k = 0; k < 5; k++) {
    f3d_real x, y;
    f3d_body_get_part_temperature(w, c, k, &x);
    f3d_body_get_part_temperature(copy, c, k, &y);
    CHECK(x == y);
  }
  free(bytes);
  f3d_world_destroy(copy);
  f3d_world_destroy(w);
}

/* A pine log 1.4 m long and 30 cm thick, 55 kg, fixed at height [y]. */
static F3dBody log_at(F3dWorld *w, f3d_real y) {
  const F3dBody b = f3d_body_create(w, F3D_BODY_FIXED, 0, y, 0, 55);
  f3d_body_set_shape(w, b, F3D_SHAPE_BOX, F3D_R(0.7), F3D_R(0.15), F3D_R(0.15));
  F3dMaterial m;
  f3d_material_preset(F3D_MATERIAL_WOOD, &m);
  f3d_body_set_material(w, b, &m);
  return b;
}

static void test_a_log_catches_at_its_surface(void) {
  /* A log laid on a burning one stands in its flame. Heat reaches into
   * wood a millimetre or so in the first seconds, so its surface reaches
   * ignition while its middle is near the room's temperature: it catches
   * within a minute or two, as wood in a flame does. Heated through, as
   * one temperature, it would need 26 MJ to reach ignition, half an hour
   * of what the flame gives it. */
  F3dWorld *w = f3d_world_create();
  const F3dBody under = log_at(w, F3D_R(0.15));
  const F3dBody over = log_at(w, F3D_R(0.46));
  f3d_body_set_temperature(w, under, 700);
  int when = -1;
  f3d_real mean = 0, skin = 0;
  for (int i = 0; i < 600 && when < 0; i++) {
    f3d_world_step(w, 1);
    if (burning(w, over)) {
      when = i;
      f3d_body_get_temperature(w, over, &mean);
      f3d_body_get_surface_temperature(w, over, &skin);
    }
  }
  CHECK(when > 0 && when < 180);
  CHECK(skin >= F3D_R(573.15));
  CHECK(mean < 320);
  f3d_world_destroy(w);
}

/* A granite ball laid on a beam of pine two metres a side. */
static int beam_under_a_stone(f3d_real stone_at, f3d_real seconds) {
  F3dWorld *w = f3d_world_create();
  const F3dBody beam = f3d_body_create(w, F3D_BODY_FIXED, 0, 0, 0, F3D_R(4000.0));
  f3d_body_set_shape(w, beam, F3D_SHAPE_BOX, 1, 1, 1);
  F3dMaterial m;
  f3d_material_preset(F3D_MATERIAL_WOOD, &m);
  f3d_body_set_material(w, beam, &m);
  const F3dBody stone =
      f3d_body_create(w, F3D_BODY_DYNAMIC, 0, F3D_R(1.3), 0, F3D_R(305.0));
  f3d_body_set_shape(w, stone, F3D_SHAPE_SPHERE, F3D_R(0.3), 0, 0);
  f3d_material_preset(F3D_MATERIAL_STONE, &m);
  f3d_body_set_material(w, stone, &m);
  f3d_body_set_temperature(w, stone, stone_at);
  const int steps = (int)(seconds * 60);
  for (int i = 0; i < steps; i++) f3d_world_step(w, F3D_R(1.0) / 60);
  const int on = burning(w, beam);
  f3d_world_destroy(w);
  return on;
}

static void test_a_red_hot_stone_lights_wood_it_touches(void) {
  /* Where a stone at 1100 K touches pine, both surfaces are at once at
   * what their effusivities √(kρc) weigh them to: granite's is seven times
   * pine's, so the wood there is near 1000 K and alight within a second —
   * though the beam's four tonnes as a whole have barely warmed. A stone
   * at 450 K holds the spot below pine's 573 K and lights nothing. */
  CHECK(beam_under_a_stone(1100, 1));
  CHECK(!beam_under_a_stone(450, 20));
}

static void test_burning_body_gets_lighter(void) {
  /* A dynamic log that burns loses mass and, with it, inertia; its
   * velocity stays, since what burns leaves at the body's speed. */
  F3dWorld *w = f3d_world_create();
  f3d_world_set_gravity(w, 0, 0, 0);
  f3d_world_set_sleep(w, 0, 0);
  const F3dBody log = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, F3D_R(0.6));
  f3d_body_set_shape(w, log, F3D_SHAPE_BOX, F3D_R(0.05), F3D_R(0.05), F3D_R(0.05));
  f3d_body_set_drag(w, log, F3D_R(1e-12));
  F3dMaterial m;
  f3d_material_preset(F3D_MATERIAL_WOOD, &m);
  f3d_body_set_material(w, log, &m);
  f3d_body_set_temperature(w, log, 700);
  f3d_body_set_velocity(w, log, 1, 0, 0);
  f3d_real i0[3], i1[3], v[3];
  f3d_body_get_inertia(w, log, i0);
  for (int i = 0; i < 200; i++) f3d_world_step(w, F3D_R(0.1));
  CHECK(burning(w, log));
  f3d_body_get_inertia(w, log, i1);
  CHECK(i1[0] < i0[0]);
  f3d_body_get_velocity(w, log, v);
  CHECK_NEAR(v[0], 1, 1e-6);
  f3d_world_destroy(w);
}

static void test_water(void) {
  F3dWorld *w = f3d_world_create();
  F3dBody bodies[8];
  uint32_t kinds[8];
  /* Water lands at the air's temperature and mixes: 0.6 kg of pine at
   * 400 K and 0.1 kg of water at 293.15 K. */
  const F3dBody warm = wood_block(w);
  f3d_body_set_temperature(w, warm, 400);
  f3d_body_add_water(w, warm, F3D_R(0.1));
  f3d_real t, water;
  f3d_body_get_temperature(w, warm, &t);
  const double dry = 0.6 * 1700, wet = 0.1 * 4186;
  CHECK_NEAR(t, (dry * 400 + wet * 293.15) / (dry + wet), 1e-6);
  f3d_body_get_water(w, warm, &water);
  CHECK_NEAR(water, 0.1, 1e-6);
  /* Taken off, it takes none of the body's temperature with it, and no
   * more than there is. */
  f3d_body_add_water(w, warm, -1);
  f3d_body_get_water(w, warm, &water);
  CHECK(water == 0);
  f3d_real after;
  f3d_body_get_temperature(w, warm, &after);
  CHECK(after == t);

  /* A wet block heated hard: its surface sits at boiling while its water
   * boils off, and it does not catch until it has. */
  const F3dBody wet_block = wood_block(w);
  f3d_body_add_water(w, wet_block, F3D_R(0.05));
  int caught_wet = 0, held = 0;
  f3d_real w0 = F3D_R(0.05);
  for (int i = 0; i < 4000 && !burning(w, wet_block); i++) {
    f3d_body_add_heat(w, wet_block, 2000);
    f3d_world_step(w, F3D_R(0.1));
    f3d_body_get_water(w, wet_block, &water);
    f3d_body_get_surface_temperature(w, wet_block, &t);
    if (water > 0) {
      caught_wet |= burning(w, wet_block);
      if (water < w0) held |= t == F3D_WATER_BOILS;
      CHECK(t <= F3D_WATER_BOILS);
    }
    w0 = water;
  }
  CHECK(held);
  CHECK(!caught_wet);
  CHECK(burning(w, wet_block));
  f3d_world_read_events(w, bodies, NULL, kinds, 8);

  /* Half a kilogram on the burning block puts it out. */
  for (int i = 0; i < 100; i++) f3d_world_step(w, F3D_R(0.1));
  CHECK(burning(w, wet_block));
  f3d_body_add_water(w, wet_block, F3D_R(0.5));
  f3d_world_step(w, F3D_R(0.1));
  CHECK(!burning(w, wet_block));
  CHECK(f3d_world_read_events(w, bodies, NULL, kinds, 8) == 1);
  CHECK(bodies[0] == wet_block && kinds[0] == F3D_EVENT_EXTINGUISHED);
  f3d_body_get_surface_temperature(w, wet_block, &t);
  CHECK(t == F3D_WATER_BOILS);
  /* Too little only hisses: ten grams on a block that has burnt for a
   * minute and a half boil away at once, and it burns on. */
  const F3dBody dry_block = wood_block(w);
  f3d_body_set_temperature(w, dry_block, 600);
  for (int i = 0; i < 1000; i++) f3d_world_step(w, F3D_R(0.1));
  CHECK(burning(w, dry_block));
  f3d_body_add_water(w, dry_block, F3D_R(0.01));
  f3d_world_step(w, F3D_R(0.1));
  CHECK(burning(w, dry_block));
  f3d_body_get_water(w, dry_block, &water);
  CHECK(water == 0);
  f3d_world_destroy(w);
}

int main(void) {
  test_materials();
  test_heat_bus();
  test_newton_cooling();
  test_radiation_cannot_overshoot();
  test_wind_cools();
  test_fire();
  test_radiation_between_bodies();
  test_fire_spreads();
  test_a_beam_burns_from_one_end();
  test_a_log_catches_at_its_surface();
  test_a_red_hot_stone_lights_wood_it_touches();
  test_burning_body_gets_lighter();
  test_water();
  return finish();
}
