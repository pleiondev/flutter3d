/*
 * Heat and fire on bodies, tested in C — P9: a burner on stone, an
 * explosion's push by solid angle, the heat bus, still air's cooling against
 * Churchill's correlation and a thick ball against the series, a
 * log that catches at its surface, radiation that cannot overshoot, wind
 * that cools, ignition, a fire that burns its fuel out, and water that
 * keeps a body from catching and puts a fire out.
 */
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "check.h"

/* A pine block ten centimetres on a side: 0.6 kg, at [x] along the
 * ground. Fixed, so it stays where it is while it burns. */
static F3dBody wood_block_at(F3dWorld *w, f3d_real x) {
  const F3dBody b = f3d_body_create(w, F3D_BODY_FIXED, x, 0, 0, F3D_R(0.6));
  f3d_body_set_shape(w, b, F3D_SHAPE_BOX, F3D_R(0.05), F3D_R(0.05), F3D_R(0.05));
  F3dMaterial m;
  f3d_material_preset(F3D_MATERIAL_WOOD, &m);
  f3d_body_set_material(w, b, &m);
  return b;
}

static F3dBody wood_block(F3dWorld *w) { return wood_block_at(w, 0); }

static int burning(F3dWorld *w, F3dBody b) {
  int on = 0;
  f3d_body_is_burning(w, b, &on);
  return on;
}

static void test_materials(void) {
  F3dMaterial m;
  /* Every preset is one a body takes. Mutation: charcoal's glow set below
   * where it catches. */
  for (int kind = F3D_MATERIAL_INERT; kind <= F3D_MATERIAL_PARAFFIN; kind++) {
    CHECK(f3d_material_preset((F3dMaterialKind)kind, &m) == 1);
    CHECK(m.specific_heat > 0 && m.emissivity > 0 && m.emissivity <= 1);
    CHECK(m.fuel_fraction < 1);
    F3dWorld *any = f3d_world_create();
    const F3dBody body = f3d_body_create(any, F3D_BODY_DYNAMIC, 0, 0, 0, 1);
    CHECK(f3d_body_set_material(any, body, &m) == 1);
    f3d_world_destroy(any);
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
  bad = m;
  bad.soot_yield = F3D_R(1.5);
  CHECK(f3d_body_set_material(w, b, &bad) == 0);
  CHECK(f3d_body_set_material(w, b, NULL) == 0);
  CHECK(f3d_body_set_material(w, b, &m) == 1);
  f3d_real fuel;
  f3d_body_get_fuel(w, b, &fuel);
  CHECK_NEAR(fuel, 2 * 0.8, 1e-6);
  /* A new body is at the air's temperature. */
  f3d_real t;
  f3d_body_get_temperature(w, b, &t);
  CHECK(t == F3D_STANDARD_AIR_TEMPERATURE);
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
 * does not radiate, after cooling in still air for 3000 s. Held where it
 * is under gravity: still air cools a body by the buoyancy of what it
 * warms, and without gravity there is none. */
static double cooled(f3d_real conductivity) {
  F3dWorld *w = f3d_world_create();
  const F3dBody b = f3d_body_create(w, F3D_BODY_FIXED, 0, 0, 0, 1);
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

/* W/(m² K) still air at 293.15 K gives a ball [d] across at [ts], by
 * Churchill's correlation, Nu = 2 + 0.589 Ra^¼ / (1 + (0.469/Pr)^(9/16))^(4/9)
 * (Incropera eq. 9.35), the air's properties at the film's temperature from
 * Incropera's table A.4, between its rows at 250, 300 and 350 K. */
static double still_air_h(double d, double ts) {
  const double ta = 293.15, film = 0.5 * (ts + ta);
  const double rows[3][4] = {{250, 11.44e-6, 22.3e-3, 0.720},
                             {300, 15.89e-6, 26.3e-3, 0.707},
                             {350, 20.92e-6, 30.0e-3, 0.700}};
  const int i = film > 300 ? 1 : 0;
  const double f = (film - rows[i][0]) / (rows[i + 1][0] - rows[i][0]);
  double air[4];
  for (int k = 1; k < 4; k++) air[k] = rows[i][k] + f * (rows[i + 1][k] - rows[i][k]);
  /* The world's air is 1.204 kg/m³: ν by its density against an
   * atmosphere's at 293.15 K. */
  const double nu = air[1] *
                    ((double)F3D_STANDARD_ATMOSPHERE /
                     ((double)F3D_GAS_CONSTANT / (double)F3D_MOLAR_MASS_OF_DRY_AIR * ta)) /
                    (double)F3D_STANDARD_AIR_DENSITY;
  const double ra = STANDARD_G * fabs(ts - ta) * d * d * d * air[3] / (film * nu * nu);
  const double nusselt =
      2 + 0.589 * pow(ra, 0.25) / pow(1 + pow(0.469 / air[3], 9.0 / 16.0), 4.0 / 9.0);
  return nusselt * air[2] / d;
}

/* The mean of a ball's temperature above its surroundings over where it
 * started, cooled from one temperature at Biot's number [bi] = h r / k to
 * Fourier's [fo] = α t / r²: the series of Incropera §5.6, summed to forty
 * terms, each root of 1 − ζ cot ζ = Bi found by bisection. */
static double ball_series(double bi, double fo) {
  double sum = 0;
  for (int n = 1; n <= 40; n++) {
    double lo = (n - 1) * M_PI + 1e-9, hi = n * M_PI - 1e-9;
    for (int i = 0; i < 200; i++) {
      const double mid = 0.5 * (lo + hi);
      if (1 - mid / tan(mid) - bi < 0) lo = mid; else hi = mid;
    }
    const double z = 0.5 * (lo + hi);
    const double c = 4 * (sin(z) - z * cos(z)) / (2 * z - sin(2 * z));
    sum += c * 3 * (sin(z) - z * cos(z)) / (z * z * z) * exp(-z * z * fo);
  }
  return sum;
}

static void test_newton_cooling(void) {
  /* A ball that does not radiate cools by convection alone, in still air.
   * Of copper, all one temperature throughout (Biot's number hr/k under a
   * thousandth): C dT/dt = −h(T) A (T − Tₐ), integrated here by fourth-order
   * Runge–Kutta at the world's own second. */
  const double area = 4 * M_PI * 0.05 * 0.05;
  double t = 393.15;
  for (int i = 0; i < 3000; i++) {
#define RATE(x) (-still_air_h(0.1, (x)) * area * ((x) - 293.15) / 1000.0)
    const double k1 = RATE(t), k2 = RATE(t + 0.5 * k1), k3 = RATE(t + 0.5 * k2),
                 k4 = RATE(t + k3);
#undef RATE
    t += (k1 + 2 * k2 + 2 * k3 + k4) / 6;
  }
  const double lumped = (t - 293.15) / 100.0;
  CHECK_NEAR(cooled(400), lumped, 1e-3);
  /* Of a conductivity of 1 W/(m K), Biot's number is about four tenths,
   * and its surface runs cold ahead of its middle: it cools slower than
   * that, as the series solution for a sphere says, at the one h that
   * brings a lumped ball to the same place. The heat balance integral is
   * within a few per cent of it. */
  const double h = -log(lumped) * 1000.0 / (area * 3000.0);
  const double alpha = 1.0 / (1000.0 / (4.0 / 3.0 * M_PI * 0.05 * 0.05 * 0.05));
  CHECK(cooled(1) > lumped);
  CHECK_NEAR(cooled(1), ball_series(h * 0.05, alpha * 3000.0 / (0.05 * 0.05)), 0.015);
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
     * either side of it, a float's or a double's. */
    const double ulp = sizeof(f3d_real) == sizeof(float) ? 1e-6 : 1e-12;
    ok &= t <= last * (1 + ulp) && t >= F3D_STANDARD_AIR_TEMPERATURE * (1 - ulp);
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
  f3d_body_set_temperature(w, block, 650);
  f3d_world_step(w, F3D_R(0.1));
  CHECK(!burning(w, block));
  /* Above it, it catches, and says so. */
  f3d_body_set_temperature(w, block, 690);
  f3d_world_step(w, F3D_R(0.1));
  CHECK(burning(w, block));
  CHECK(f3d_world_read_events(w, bodies, NULL, kinds, 8) == 1);
  CHECK(bodies[0] == block && kinds[0] == F3D_EVENT_IGNITED);
  /* Heated through past its ignition point, its surface is alight all
   * over at once, and gives off heat from the next step. */
  f3d_real t, mass, fuel, release;
  f3d_world_step(w, F3D_R(0.1));
  f3d_body_get_heat_release(w, block, &release);
  CHECK(release > 0);
  for (int i = 0; i < 30; i++) f3d_world_step(w, F3D_R(0.1));
  f3d_real early_mass, early_fuel;
  f3d_body_get_mass(w, block, &early_mass);
  f3d_body_get_fuel(w, block, &early_fuel);
  /* Heated through past its ignition temperature, all of it gives off gas
   * at the rate pine's kinetics give there, not only its surface: faster
   * than the 11 g/(m² s) a surface fire on wood burns at (burn_rate). What
   * burns is fuel, and comes off the mass gram for gram. */
  for (int i = 0; i < 100; i++) f3d_world_step(w, F3D_R(0.1));
  f3d_body_get_mass(w, block, &mass);
  f3d_body_get_fuel(w, block, &fuel);
  const double rate = ((double)early_mass - (double)mass) / 10.0;
  CHECK(rate / 0.06 > 0.011);
  CHECK_NEAR((double)early_fuel - (double)fuel, (double)early_mass - (double)mass, 1e-6);
  /* It gives off heat as it burns, its fire where the body is. */
  f3d_body_get_heat_release(w, block, &release);
  CHECK(release > 0);
  F3dBody handle = 0;
  CHECK(f3d_world_read_fires(w, fires, &handle, 2) == 1);
  CHECK(handle == block && fires[3] == release);
  /* Its char thickens and glows hotter than the wood catches at, and holds
   * the flame's heat off the wood beneath; its middle cools as it burns.
   * Alone, with nothing else's heat on it, it burns minutes, not to the
   * end: once its gas falls below the firepoint it goes out, wood left
   * under its char — a lone block of wood does not burn itself away. */
  int steps = 0;
  while (burning(w, block) && steps < 20000) {
    f3d_world_step(w, F3D_R(0.1));
    steps++;
  }
  CHECK(steps * 0.1 > 120 && steps * 0.1 < 1200);
  CHECK(f3d_world_read_events(w, bodies, NULL, kinds, 8) == 1);
  CHECK(kinds[0] == F3D_EVENT_EXTINGUISHED);
  f3d_body_get_fuel(w, block, &fuel);
  CHECK(fuel > 0);
  f3d_body_get_mass(w, block, &mass);
  CHECK(mass > 0.12 && mass < early_mass);
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
  const double e = (double)F3D_MAT_GRANITE_EMISSIVITY, sigma = (double)F3D_STEFAN_BOLTZMANN,
               ta = (double)F3D_STANDARD_AIR_TEMPERATURE;
  const double area = 4 * M_PI * 0.2 * 0.2;
  const double s = 0.2 / 0.5;
  const double share = 0.5 * (1 - sqrt(1 - s * s));
  const double gain = e * share * e * sigma * area * (pow(1000, 4) - pow(ta, 4)) * 0.1;
  /* Ten kilograms of granite at its specific heat; its own losses, at the
   * room's temperature, nought. */
  const double capacity = 10 * (double)F3D_MAT_GRANITE_SPECIFIC_HEAT;
  CHECK_NEAR(near, gain / capacity, 0.01 * gain / capacity);
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
  /* A crate packed full, half a metre of pine on a side, 62.5 kg: the core
   * takes a body as solid through, and ten kilograms of planks spread
   * over half a metre would be a wood as light as cork, whose char holds
   * no flame. */
  const F3dBody b = f3d_body_create(w, F3D_BODY_FIXED, x, y, 0, F3D_R(62.5));
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
  f3d_body_set_temperature(w, all[0], 690);
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
  /* A crate hot all through shines on those it stands a couple of
   * centimetres from, the one on it and the one beside it, and both catch
   * within seconds, once heat enough lies under their faces to hold a
   * flame. Solid pine with nothing more to heat it burns near its
   * firepoint, its flame giving back most of what it makes; the one four
   * metres off only warms. */
  int when[5];
  f3d_real far;
  blaze(0, when, &far);
  CHECK(when[0] == 0);
  CHECK(when[1] > 0 && when[1] < 60);
  CHECK(when[2] > 0 && when[2] < 60);
  CHECK(when[4] < 0);
  CHECK(far < 310);
  /* Two metres a second along the row lays the flame towards the crate
   * beside it: it catches no later than in still air, and the far one
   * still only warms. */
  int windy[5];
  blaze(2, windy, &far);
  CHECK(windy[2] > 0 && windy[2] <= when[2]);
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
  f3d_body_set_part_temperature(w, b, 0, 690);
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
   * of the one below, in the time that flame takes to bring it to its
   * ignition temperature. Laid flat and lit at one end, it warms the part
   * beside the fire and goes no further, as a lone log on its side does in
   * still air: its flame stands over the burning end, not along it. Its
   * edge creeps onto the part beside only once conduction has warmed that
   * part's surface past the coolest a flame's edge creeps over (the LIFT
   * test's minimum), later than the flame climbs the upright one, and no
   * further. */
  int up[5], flat[5];
  f3d_real peak_up, peak_flat;
  burn_beam(1, up, &peak_up);
  burn_beam(0, flat, &peak_flat);
  CHECK(up[0] == 0);
  for (int k = 1; k < 5; k++) CHECK(up[k] > up[k - 1]);
  CHECK(flat[0] == 0);
  CHECK(flat[1] < 0 || flat[1] > up[1]);
  for (int k = 2; k < 5; k++) CHECK(flat[k] < 0);
  F3dMaterial pine;
  f3d_material_preset(F3D_MATERIAL_WOOD, &pine);
  CHECK(peak_flat > 300 && peak_flat < pine.spread_minimum);
  F3dWorld *w = f3d_world_create();
  const F3dBody b = beam(w, 0);
  CHECK(f3d_body_set_part_temperature(w, b, 0, 690) == 1);
  CHECK(f3d_body_set_part_temperature(w, b, 5, 690) == 0);
  f3d_real t;
  f3d_body_get_temperature(w, b, &t);
  CHECK_NEAR(t, (690 + 4 * 293.15) / 5, 0.01);
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
  f3d_body_set_part_temperature(w, bar, 0, 900);
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
  f3d_body_set_part_temperature(w, c, 0, 690);
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
   * wood a millimetre or so in the first seconds, so the face in the flame
   * reaches ignition while its middle is near the room's temperature: it
   * catches there within a minute or two, in the time a thick solid takes
   * under the flame's flux. Its surface as a whole is well above its
   * middle by then, though the side away from the flame is not alight.
   * Heated through, as one temperature, it would need 26 MJ to reach
   * ignition, half an hour of what the flame gives it. */
  F3dWorld *w = f3d_world_create();
  const F3dBody under = log_at(w, F3D_R(0.15));
  const F3dBody over = log_at(w, F3D_R(0.46));
  f3d_body_set_temperature(w, under, 690);
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
  CHECK(skin > mean + 100);
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
  int on = 0;
  for (int i = 0; i < steps && !on; i++) {
    f3d_world_step(w, F3D_R(1.0) / 60);
    on = burning(w, beam);
  }
  f3d_world_destroy(w);
  return on;
}

static void test_a_red_hot_stone_lights_wood_it_touches(void) {
  /* Where a stone at 1100 K touches pine, both surfaces are at once at
   * what their effusivities √(kρc) weigh them to: granite's is seven times
   * pine's, so the wood there is near 1000 K at once, and alight within a
   * minute, once the heat laid under the spot holds a flame — though the
   * beam's four tonnes as a whole have barely warmed. A stone at 450 K
   * holds the spot below pine's 663 K and lights nothing. */
  CHECK(beam_under_a_stone(1100, 60));
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
  f3d_body_set_temperature(w, log, 690);
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
  const double dry = 0.6 * (double)F3D_MAT_WOOD_SPECIFIC_HEAT,
               wet = 0.1 * (double)F3D_MAT_WATER_SPECIFIC_HEAT;
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
   * boils off, and it does not catch until it has. Each block from here
   * stands ten metres from the last, out of the others' flames. */
  const F3dBody wet_block = wood_block_at(w, 10);
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
      if (water < w0) held |= t == F3D_MAT_WATER_BOILING_POINT;
      CHECK(t <= F3D_MAT_WATER_BOILING_POINT);
    }
    w0 = water;
  }
  CHECK(held);
  CHECK(!caught_wet);
  CHECK(burning(w, wet_block));
  f3d_world_read_events(w, bodies, NULL, kinds, 8);

  /* Caught under that flux with its middle still cold, it burns on only
   * while the heat stays on — taken away, the wood under the flame draws
   * more than the flame gives, as a lone thick piece of wood does. Half a
   * kilogram on the burning block puts it out. */
  for (int i = 0; i < 100; i++) {
    f3d_body_add_heat(w, wet_block, 2000);
    f3d_world_step(w, F3D_R(0.1));
  }
  CHECK(burning(w, wet_block));
  f3d_body_add_water(w, wet_block, F3D_R(0.5));
  f3d_world_step(w, F3D_R(0.1));
  CHECK(!burning(w, wet_block));
  CHECK(f3d_world_read_events(w, bodies, NULL, kinds, 8) == 1);
  CHECK(bodies[0] == wet_block && kinds[0] == F3D_EVENT_EXTINGUISHED);
  f3d_body_get_surface_temperature(w, wet_block, &t);
  CHECK(t == F3D_MAT_WATER_BOILING_POINT);
  /* Too little only hisses: a gram on a block that has burnt for a minute
   * and a half boils off its glowing char at once, and it burns on. */
  const F3dBody dry_block = wood_block_at(w, 20);
  f3d_body_set_temperature(w, dry_block, 690);
  for (int i = 0; i < 1000; i++) f3d_world_step(w, F3D_R(0.1));
  CHECK(burning(w, dry_block));
  f3d_body_add_water(w, dry_block, F3D_R(0.001));
  f3d_world_step(w, F3D_R(0.1));
  CHECK(burning(w, dry_block));
  f3d_body_get_water(w, dry_block, &water);
  CHECK(water == 0);
  f3d_world_destroy(w);
}

/* What burns leaves char: over its fire a layer that glows hotter than the
 * wood catches at, covering as much of the surface as has burnt, and still
 * there, black and cooling, once water has put the fire out. Wood that has
 * never burnt has none. */
static void test_char_stays_where_it_burnt(void) {
  F3dWorld *w = f3d_world_create();
  const F3dBody block = wood_block(w);
  f3d_real share = 1, depth = 1, t = 0;
  CHECK(f3d_body_get_char(w, block, &share, &depth, &t) == 1);
  CHECK(share == 0 && depth == 0);
  f3d_body_set_temperature(w, block, 690);
  for (int i = 0; i < 600; i++) f3d_world_step(w, F3D_R(0.1));
  CHECK(burning(w, block));
  f3d_body_get_char(w, block, &share, &depth, &t);
  CHECK(share > 0.5 && share <= 1);
  CHECK(depth > 1e-4 && depth < 0.05);
  F3dMaterial pine;
  f3d_material_preset(F3D_MATERIAL_WOOD, &pine);
  CHECK(t > pine.ignition_temperature);
  f3d_body_add_water(w, block, F3D_R(0.5));
  for (int i = 0; i < 100; i++) f3d_world_step(w, F3D_R(0.1));
  CHECK(!burning(w, block));
  f3d_real after = 0, cooled = 0;
  f3d_body_get_char(w, block, &after, NULL, &cooled);
  CHECK(after == share);
  CHECK(cooled < t);
  CHECK(f3d_body_get_char(w, (F3dBody)0, NULL, NULL, NULL) == 0);
  f3d_world_destroy(w);
}

/* A thatched roof with a red-hot stone lying on it, and the same mass of
 * the same stuff as a solid slab. Straw is a bed of fine elements:
 * Anderson's fuel model 3, tall grass, σ = 1500 ft⁻¹ = 4921 m⁻¹ and
 * Rothermel's particle density of 32 lb/ft³ = 513 kg/m³ (USDA INT-122,
 * 1982; INT-115, 1972). The bed's elements heat through, nothing draws
 * heat into it from under its fire and no crust insulates it, so its fire
 * grows over it; the slab's char and cold mass hold its patch at the
 * firepoint until it goes out. */
static f3d_real roof_with_a_stone(int bed, int seconds, int *alight) {
  F3dWorld *w = f3d_world_create();
  const F3dBody roof = f3d_body_create(w, F3D_BODY_FIXED, 0, 0, 0, 800);
  f3d_body_set_shape(w, roof, F3D_SHAPE_BOX, F3D_R(2.3), F3D_R(0.2), F3D_R(2.3));
  F3dMaterial straw;
  f3d_material_preset(F3D_MATERIAL_PAPER, &straw);
  if (bed) {
    straw.element_surface = 4921;
    straw.element_density = 513;
  }
  CHECK(f3d_body_set_material(w, roof, &straw) == 1);
  const F3dBody stone = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, F3D_R(0.55), 0, 400);
  f3d_body_set_shape(w, stone, F3D_SHAPE_SPHERE, F3D_R(0.35), 0, 0);
  F3dMaterial rock;
  f3d_material_preset(F3D_MATERIAL_STONE, &rock);
  f3d_body_set_material(w, stone, &rock);
  f3d_body_set_temperature(w, stone, 1300);
  for (int i = 0; i < seconds * 60; i++) f3d_world_step(w, F3D_R(1.0) / 60);
  f3d_body_is_burning(w, roof, alight);
  f3d_real q = 0;
  f3d_body_get_heat_release(w, roof, &q);
  f3d_world_destroy(w);
  return q;
}

static void test_a_bed_of_straw_burns_on(void) {
  int alight = 0;
  const f3d_real early = roof_with_a_stone(1, 5, &alight);
  CHECK(alight);
  const f3d_real later = roof_with_a_stone(1, 30, &alight);
  CHECK(alight);
  CHECK(later > 4 * early);
  /* The slab: out within half a minute. */
  roof_with_a_stone(0, 30, &alight);
  CHECK(!alight);
  /* What reaches the bed heats its elements through as deep as radiation
   * passes between them, 4/(βσ), and no deeper: its surface rises V/(Aδ)
   * times as far as its mean does. */
  F3dWorld *h = f3d_world_create();
  const F3dBody heap = f3d_body_create(h, F3D_BODY_FIXED, 0, 0, 0, 800);
  f3d_body_set_shape(h, heap, F3D_SHAPE_BOX, F3D_R(2.3), F3D_R(0.2), F3D_R(2.3));
  F3dMaterial straw;
  f3d_material_preset(F3D_MATERIAL_PAPER, &straw);
  straw.element_surface = 4921;
  straw.element_density = 513;
  f3d_body_set_material(h, heap, &straw);
  f3d_body_add_heat(h, heap, F3D_R(8e5));
  f3d_world_step(h, F3D_R(1e-3));
  f3d_real mean, skin;
  f3d_body_get_temperature(h, heap, &mean);
  f3d_body_get_surface_temperature(h, heap, &skin);
  const double volume = 4.6 * 0.4 * 4.6, area = 2 * 4.6 * 4.6 + 4 * 4.6 * 0.4;
  const double depth = 4.0 / (800.0 / volume / 513.0 * 4921.0);
  CHECK_NEAR((skin - 293.15) / (mean - 293.15), volume / area / depth, 0.01);
  f3d_world_destroy(h);
  /* A flame held to it lights it in the time its fine elements take to
   * heat through, ρ_p c ΔT / (σ q''), not in a solid's (π/4) kρc
   * (ΔT / q'')², which for straw's own k, ρ and c is a tenth of it: no
   * sooner than under the flame's whole 50 kW/m². */
  h = f3d_world_create();
  const F3dBody tuft = f3d_body_create(h, F3D_BODY_FIXED, 0, 0, 0, 800);
  f3d_body_set_shape(h, tuft, F3D_SHAPE_BOX, F3D_R(2.3), F3D_R(0.2), F3D_R(2.3));
  f3d_body_set_material(h, tuft, &straw);
  int on = 0, steps = 0;
  while (!on && steps < 10000) {
    f3d_body_hold_flame(h, tuft, 0, F3D_R(0.2), 0, F3D_R(5e4), F3D_R(2.5e-3), 1300);
    f3d_world_step(h, F3D_R(1e-3));
    f3d_body_is_burning(h, tuft, &on);
    steps++;
  }
  const double thin = 513.0 * straw.specific_heat * (straw.ignition_temperature - 293.15) /
                      (4921.0 * 5e4);
  CHECK(on && steps * 1e-3 >= thin && steps * 1e-3 < 2 * thin);
  f3d_world_destroy(h);
  /* A bed's elements need a density of their own. */
  F3dWorld *w = f3d_world_create();
  const F3dBody b = f3d_body_create(w, F3D_BODY_FIXED, 0, 0, 0, 1);
  F3dMaterial bad;
  f3d_material_preset(F3D_MATERIAL_PAPER, &bad);
  bad.element_surface = 4921;
  CHECK(f3d_body_set_material(w, b, &bad) == 0);
  f3d_world_destroy(w);
}

/* A flame held to a cool block — a torch's, 50 kW/m² over a few square
 * centimetres — lights it in the time a thick solid takes to reach its
 * ignition temperature under that flux, tens of seconds for pine, as a cone
 * calorimeter does; not at once, and only the spot it is held to. */
static void test_a_held_flame_lights_a_block(void) {
  F3dWorld *w = f3d_world_create();
  const F3dBody block = wood_block(w);
  int steps = 0;
  while (!burning(w, block) && steps < 1200) {
    f3d_body_hold_flame(w, block, 0, F3D_R(-0.05), 0, F3D_R(5e4), F3D_R(2.5e-3),
                        F3D_R(1300.0));
    f3d_world_step(w, F3D_R(0.1));
    steps++;
  }
  CHECK(burning(w, block));
  CHECK(steps * 0.1 > 10 && steps * 0.1 < 60);
  f3d_real at;
  f3d_body_get_heat_release(w, block, &at);
  /* What a surface fire over all its 0.06 m² would give off. */
  CHECK(at < 0.011 * 0.06 * 1.5e7);
  f3d_world_destroy(w);
}

static void test_a_burner_burns_on_stone(void) {
  /* A gram a second of pine burnt on a granite ball — a brazier's fire: it
   * is alight from the step it is fed and says so, though stone has no
   * fuel of its own; it gives off what burns, 15 kW, less what its flame
   * hands the stone, which warms; and the stone loses no mass. Fed nothing,
   * it goes out. A fuel that does not burn, or a rate below nought, is
   * refused. */
  F3dWorld *w = f3d_world_create();
  const F3dBody s = f3d_body_create(w, F3D_BODY_FIXED, 0, 0, 0, 10);
  f3d_body_set_shape(w, s, F3D_SHAPE_SPHERE, F3D_R(0.1), 0, 0);
  F3dMaterial stone, wood;
  f3d_material_preset(F3D_MATERIAL_STONE, &stone);
  f3d_material_preset(F3D_MATERIAL_WOOD, &wood);
  f3d_body_set_material(w, s, &stone);
  CHECK(f3d_body_set_burner(w, s, -1, &wood) == 0);
  CHECK(f3d_body_set_burner(w, s, F3D_R(0.001), &stone) == 0);
  CHECK(f3d_body_set_burner(w, s, F3D_R(0.001), &wood) == 1);
  F3dBody bodies[8];
  uint32_t kinds[8];
  f3d_world_step(w, F3D_R(0.1));
  CHECK(burning(w, s));
  CHECK(f3d_world_read_events(w, bodies, NULL, kinds, 8) == 1);
  CHECK(bodies[0] == s && kinds[0] == F3D_EVENT_IGNITED);
  for (int i = 0; i < 600; i++) f3d_world_step(w, F3D_R(0.1));
  f3d_real release, t, mass;
  f3d_body_get_heat_release(w, s, &release);
  CHECK(release > 0.5 * 0.001 * 1.5e7 && release < 0.001 * 1.5e7);
  f3d_body_get_temperature(w, s, &t);
  CHECK(t > 300);
  f3d_body_get_mass(w, s, &mass);
  CHECK(mass == 10);
  CHECK(f3d_body_set_burner(w, s, 0, NULL) == 1);
  f3d_world_step(w, F3D_R(0.1));
  CHECK(!burning(w, s));
  CHECK(f3d_world_read_events(w, bodies, NULL, kinds, 8) == 1);
  f3d_world_destroy(w);
}

/* A fire says what soot it makes a joule: its own material's yield over
 * its heat of combustion, or its burner's fuel's. Mutations: the yield
 * written as it is, kg/kg; a burner's fire read with the body's own. */
static void test_a_fire_says_its_soot(void) {
  F3dWorld *w = f3d_world_create();
  const F3dBody block = wood_block(w);
  f3d_body_set_temperature(w, block, 700);
  F3dMaterial wood, rubber, stone;
  f3d_material_preset(F3D_MATERIAL_WOOD, &wood);
  f3d_material_preset(F3D_MATERIAL_RUBBER, &rubber);
  f3d_material_preset(F3D_MATERIAL_STONE, &stone);
  const F3dBody s = f3d_body_create(w, F3D_BODY_FIXED, 5, 0, 0, 10);
  f3d_body_set_shape(w, s, F3D_SHAPE_SPHERE, F3D_R(0.1), 0, 0);
  f3d_body_set_material(w, s, &stone);
  f3d_body_set_burner(w, s, F3D_R(0.001), &rubber);
  f3d_world_step(w, F3D_R(0.1));
  f3d_real fires[F3D_FIRE_FLOATS * 4];
  F3dBody handles[4];
  const uint32_t n = f3d_world_read_fires(w, fires, handles, 4);
  CHECK(n == 2);
  for (uint32_t k = 0; k < n; k++) {
    const F3dMaterial *fuel = handles[k] == s ? &rubber : &wood;
    CHECK_NEAR(fires[k * F3D_FIRE_FLOATS + 12] / (fuel->soot_yield / fuel->heat_of_combustion),
               1.0, 1e-5);
  }
  f3d_world_destroy(w);
}

/* Corrugated board in a 50 kW/m² flame catches in 6.75 to 8 s, as the
 * cone measured it (UL FSRI, Corrugated Cardboard): the kρc its three
 * times to catch fit, past what its surface loses at 350 °C
 * (doc/derivations/flame_spread.md). Mutations: kρc 0.244 (kW/m² K)² s,
 * the fit with no critical flux — 10.6 s; 0.10 — 4.4 s. */
static void test_cardboard_catches_as_the_cone_measured(void) {
  F3dWorld *w = f3d_world_create();
  const F3dBody box = f3d_body_create(w, F3D_BODY_FIXED, 0, 0, 0, F3D_R(0.32));
  f3d_body_set_shape(w, box, F3D_SHAPE_BOX, F3D_R(0.05), F3D_R(0.05), F3D_R(0.05));
  F3dMaterial board;
  f3d_material_preset(F3D_MATERIAL_CARDBOARD, &board);
  f3d_body_set_material(w, box, &board);
  int steps = 0;
  while (!burning(w, box) && steps < 3000) {
    f3d_body_hold_flame(w, box, 0, F3D_R(-0.05), 0, F3D_R(5e4), F3D_R(2.5e-3),
                        F3D_R(1300.0));
    f3d_world_step(w, F3D_R(0.01));
    steps++;
  }
  CHECK(burning(w, box));
  CHECK(steps * 0.01 >= 6.75 && steps * 0.01 <= 8.0);
  f3d_world_destroy(w);
}

/* Over cold straw a thatch fire's edge creeps at Φ / (kρc (T_ig − T_s)²),
 * which its preset makes the 2.7 mm/s Rothermel's model gives its bed
 * with no wind (doc/derivations/flame_spread.md). Mutation: plywood's Φ,
 * 12.9 kW²/m³ — 0.1 m/s. */
static void test_thatch_creeps_at_rothermels_rate(void) {
  F3dMaterial m;
  f3d_material_preset(F3D_MATERIAL_THATCH, &m);
  const double ahead = m.ignition_temperature - 293.15;
  CHECK_NEAR(m.flame_spread / (m.ignition_inertia * ahead * ahead), 2.68e-3, 0.02);
}

/* A lump of charcoal glows on while it is heated as hard as glowing
 * coals heat one among them, and goes out short of it: a torch's
 * 106 kW/m² keeps it burning, a newspaper fire's 60 does not hold it
 * (doc/derivations/charcoal_glow.md); taken out of the flame, it goes
 * out. Mutations: its least burning 0.3 g/(m² s) — the 60 kW/m² holds
 * it; its heat of gasification 6.66 MJ/kg — the same. */
static int coal_held_in(f3d_real flux, int *after) {
  F3dWorld *w = f3d_world_create();
  const double side = 0.0355;
  const F3dBody coal =
      f3d_body_create(w, F3D_BODY_FIXED, 0, 0, 0, (f3d_real)(345 * side * side * side));
  const f3d_real h = (f3d_real)(side / 2);
  f3d_body_set_shape(w, coal, F3D_SHAPE_BOX, h, h, h);
  F3dMaterial charcoal;
  f3d_material_preset(F3D_MATERIAL_CHARCOAL, &charcoal);
  f3d_body_set_material(w, coal, &charcoal);
  for (int i = 0; i < 300; i++) {
    /* All of it in the flame, as a coal among coals is. */
    f3d_body_hold_flame(w, coal, 0, -h, 0, flux, (f3d_real)(6 * side * side), F3D_R(1366.0));
    f3d_world_step(w, F3D_R(0.01));
  }
  const int held = burning(w, coal);
  for (int i = 0; i < 300; i++) f3d_world_step(w, F3D_R(0.01));
  *after = burning(w, coal);
  f3d_world_destroy(w);
  return held;
}

static void test_charcoal_glows_only_as_hot_as_a_heap(void) {
  int after = 1;
  CHECK(coal_held_in(F3D_R(1.056e5), &after));
  CHECK(!after);
  CHECK(!coal_held_in(F3D_R(6e4), &after));
}

static void test_an_explosion_pushes_by_solid_angle(void) {
  /* A kilogram of TNT, 4.184 MJ, between two balls of ten centimetres and
   * a kilogram, one a metre off, one two. Its products carry 0.69 of it as
   * momentum √(2·E_G·m), 2.40 kN s, and each ball takes the share of it its
   * disc is of the sphere about the charge, r²/4d²: 6 m/s for the near one,
   * a quarter of that for the far, each straight away from the charge. The
   * rest of the energy warms them by the same shares. */
  F3dWorld *w = f3d_world_create();
  f3d_world_set_gravity(w, 0, 0, 0);
  const F3dBody near = f3d_body_create(w, F3D_BODY_DYNAMIC, 1, 0, 0, 1);
  const F3dBody far = f3d_body_create(w, F3D_BODY_DYNAMIC, -2, 0, 0, 1);
  f3d_body_set_shape(w, near, F3D_SHAPE_SPHERE, F3D_R(0.1), 0, 0);
  f3d_body_set_shape(w, far, F3D_SHAPE_SPHERE, F3D_R(0.1), 0, 0);
  CHECK(f3d_world_explode(w, 0, 0, 0, -1, 0) == 0);
  CHECK(f3d_world_explode(w, 0, 0, 0, F3D_R(4.184e6), 0) == 2);
  f3d_world_step(w, F3D_R(0.001));
  f3d_real vn[3], vf[3], tn, tf;
  f3d_body_get_velocity(w, near, vn);
  f3d_body_get_velocity(w, far, vf);
  const double momentum = sqrt(2 * 0.7115 * 4.184e6);
  CHECK_NEAR(vn[0], momentum * 0.1 * 0.1 / 4, 0.05 * momentum * 0.0025);
  CHECK(fabs((double)vn[1]) < 1e-6 && fabs((double)vn[2]) < 1e-6);
  CHECK(vf[0] < 0);
  CHECK_NEAR(vn[0] / -vf[0], 4, 0.1);
  f3d_body_get_temperature(w, near, &tn);
  f3d_body_get_temperature(w, far, &tf);
  CHECK(tn > tf && tf > F3D_STANDARD_AIR_TEMPERATURE);
  f3d_world_destroy(w);
}

int main(void) {
  test_a_burner_burns_on_stone();
  test_a_fire_says_its_soot();
  test_cardboard_catches_as_the_cone_measured();
  test_thatch_creeps_at_rothermels_rate();
  test_charcoal_glows_only_as_hot_as_a_heap();
  test_an_explosion_pushes_by_solid_angle();
  test_materials();
  test_heat_bus();
  test_newton_cooling();
  test_radiation_cannot_overshoot();
  test_wind_cools();
  test_fire();
  test_a_held_flame_lights_a_block();
  test_char_stays_where_it_burnt();
  test_a_bed_of_straw_burns_on();
  test_radiation_between_bodies();
  test_fire_spreads();
  test_a_beam_burns_from_one_end();
  test_a_log_catches_at_its_surface();
  test_a_red_hot_stone_lights_wood_it_touches();
  test_burning_body_gets_lighter();
  test_water();
  return finish();
}
