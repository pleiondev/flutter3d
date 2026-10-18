/*
 * Vehicles, tested in C: what a vehicle refuses, a car at rest on its
 * springs at the height statics puts it, a drive that accelerates it at
 * F / m, a brake that stops it and never backs it up, a steering angle that
 * turns it at v tan(a) / L, a tyre that slides on ice where it gripped on
 * tarmac, a car on its roof with no wheel down, and a vehicle in a
 * snapshot.
 */
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "check.h"

#define MASS 1200.0
#define STIFFNESS 30000.0

static void run(F3dWorld *w, int steps) {
  for (int i = 0; i < steps; i++) f3d_world_step(w, F3D_R(1.0) / 60);
}

static F3dWorld *road(void) {
  F3dWorld *w = f3d_world_create();
  /* Thin air: drag would take a few per cent of what is measured. */
  f3d_world_set_air(w, F3D_STANDARD_AIR_TEMPERATURE, F3D_R(1e-30));
  const F3dBody floor = f3d_body_create(w, F3D_BODY_FIXED, 0, F3D_R(-0.5), 0, 0);
  f3d_body_set_shape(w, floor, F3D_SHAPE_BOX, 500, F3D_R(0.5), 500);
  f3d_body_set_friction(w, floor, F3D_R(0.0));
  return w;
}

/* A car of 1200 kg: a box 1.8 × 0.6 × 4 m, four wheels 2.6 m apart, up +y
 * and forward +z. */
static F3dVehicle car(F3dWorld *w, f3d_real y, f3d_real grip, F3dBody *chassis) {
  *chassis = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, y, 0, F3D_R(MASS));
  f3d_body_set_shape(w, *chassis, F3D_SHAPE_BOX, F3D_R(0.9), F3D_R(0.3), F3D_R(2.0));
  const F3dVehicle v = f3d_vehicle_create(w, *chassis, 0, 1, 0, 0, 0, 1);
  for (int i = 0; i < 4; i++) {
    const f3d_real wheel[F3D_WHEEL_FLOATS] = {
        i % 2 ? F3D_R(0.8) : F3D_R(-0.8), F3D_R(-0.2), i < 2 ? F3D_R(1.3) : F3D_R(-1.3),
        F3D_R(0.4), F3D_R(0.35), F3D_R(STIFFNESS), F3D_R(3000.0), grip};
    CHECK(f3d_vehicle_add_wheel(w, v, wheel) == i);
  }
  return v;
}

static void read(F3dWorld *w, F3dVehicle v, f3d_real out[4][F3D_WHEEL_STATE_FLOATS]) {
  CHECK(f3d_vehicle_read_wheels(w, v, &out[0][0], 4) == 4);
}

static void test_refusals(void) {
  F3dWorld *w = road();
  const F3dBody fixed = f3d_body_create(w, F3D_BODY_FIXED, 0, 0, 0, 0);
  CHECK(f3d_vehicle_create(w, fixed, 0, 1, 0, 0, 0, 1) == 0);
  const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 1, 0, 1);
  CHECK(f3d_vehicle_create(w, b, 0, 1, 0, 0, 1, 1) == 0);
  CHECK(f3d_vehicle_create(w, b, 0, 0, 0, 0, 0, 1) == 0);
  const F3dVehicle v = f3d_vehicle_create(w, b, 0, 1, 0, 0, 0, 1);
  CHECK(v == 1);
  f3d_real wheel[F3D_WHEEL_FLOATS] = {0, 0, 0, F3D_R(0.4), F3D_R(0.3), 1000, 100, 1};
  wheel[4] = 0;
  CHECK(f3d_vehicle_add_wheel(w, v, wheel) == -1);
  wheel[4] = F3D_R(0.3);
  wheel[0] = nan_value();
  CHECK(f3d_vehicle_add_wheel(w, v, wheel) == -1);
  wheel[0] = 0;
  for (uint32_t i = 0; i < F3D_VEHICLE_MOST_WHEELS; i++) {
    CHECK(f3d_vehicle_add_wheel(w, v, wheel) == (int)i);
  }
  CHECK(f3d_vehicle_add_wheel(w, v, wheel) == -1);
  CHECK(f3d_vehicle_set_wheel(w, v, 0, 0, 0, -1) == 0);
  CHECK(f3d_vehicle_set_wheel(w, v, 8, 0, 0, 0) == 0);
  CHECK(f3d_vehicle_destroy(w, v) == 1);
  CHECK(!f3d_vehicle_is_valid(w, v));
  CHECK(f3d_vehicle_destroy(w, v) == 0);
  /* A vehicle goes with its chassis. */
  const F3dVehicle again = f3d_vehicle_create(w, b, 0, 1, 0, 0, 0, 1);
  CHECK(again == 2);
  f3d_body_destroy(w, b);
  CHECK(!f3d_vehicle_is_valid(w, again));
  f3d_world_destroy(w);
}

static void test_rests(void) {
  F3dWorld *w = road();
  F3dBody chassis;
  const F3dVehicle v = car(w, 1, 1, &chassis);
  run(w, 180);
  /* Each spring holds a quarter of the weight: squeezed m g / 4k. */
  const double squeeze = MASS * STANDARD_G / 4 / STIFFNESS;
  const double height = 0.2 + 0.35 + (0.4 - squeeze);
  f3d_real at[3];
  f3d_body_get_position(w, chassis, at);
  CHECK_NEAR(at[1], height, 2e-3);
  f3d_real wheels[4][F3D_WHEEL_STATE_FLOATS];
  read(w, v, wheels);
  for (int i = 0; i < 4; i++) {
    CHECK(wheels[i][0] == 1);
    /* Asleep within a millimetre of rest: the springs as it stopped. */
    CHECK_NEAR(wheels[i][11], MASS * STANDARD_G / 4, 15);
    CHECK_NEAR(wheels[i][1], 0.4 - squeeze, 2e-3);
    CHECK_NEAR(wheels[i][6], 0.35, 2e-3);
  }
  f3d_world_destroy(w);
}

static void test_drives_and_brakes(void) {
  F3dWorld *w = road();
  F3dBody chassis;
  const F3dVehicle v = car(w, F3D_R(0.86), 1, &chassis);
  run(w, 60);
  /* 1200 N on each rear wheel, less the tyres' rolling resistance, μ m g:
   * (2400 − 0.015 × 1200 × STANDARD_G) / 1200 metres a second, every second. */
  f3d_vehicle_set_wheel(w, v, 2, 0, 1200, 0);
  f3d_vehicle_set_wheel(w, v, 3, 0, 1200, 0);
  run(w, 120);
  f3d_real vel[3];
  f3d_body_get_velocity(w, chassis, vel);
  CHECK_NEAR(vel[2], 2 * (2400 - F3D_WHEEL_ROLLING_DEFAULT * MASS * STANDARD_G) / MASS, 0.08);
  CHECK(fabs((double)vel[0]) < 1e-3);
  f3d_real wheels[4][F3D_WHEEL_STATE_FLOATS];
  read(w, v, wheels);
  CHECK_NEAR(wheels[0][4], vel[2] / 0.35, 0.05);
  /* Rolled as far as it went: half its speed over two seconds. */
  CHECK(wheels[0][3] > 0.9 * vel[2] / 0.35);
  /* Off the drive, the brakes on hard: stopped, and not reversing. */
  for (uint32_t i = 0; i < 4; i++) f3d_vehicle_set_wheel(w, v, i, 0, 0, 4000);
  run(w, 120);
  f3d_body_get_velocity(w, chassis, vel);
  CHECK(fabs((double)vel[2]) < 0.02);
  f3d_real at[3];
  f3d_body_get_position(w, chassis, at);
  const double stopped = at[2];
  run(w, 60);
  f3d_body_get_position(w, chassis, at);
  CHECK_NEAR(at[2], stopped, 1e-3);
  f3d_world_destroy(w);
}

static void test_steers(void) {
  F3dWorld *w = road();
  F3dBody chassis;
  const F3dVehicle v = car(w, F3D_R(0.86), 1, &chassis);
  run(w, 30);
  f3d_body_set_velocity(w, chassis, 0, 0, 5);
  /* Both front wheels turned a fifth of a radian to the left, enough drive
   * to hold five metres a second against the tyres' drag in the turn. */
  const f3d_real a = F3D_R(0.2);
  f3d_vehicle_set_wheel(w, v, 0, a, 0, 0);
  f3d_vehicle_set_wheel(w, v, 1, a, 0, 0);
  for (int i = 0; i < 90; i++) {
    f3d_real vel[3];
    f3d_body_get_velocity(w, chassis, vel);
    const double speed = sqrt((double)(vel[0] * vel[0] + vel[2] * vel[2]));
    const f3d_real push = (f3d_real)(600 * (5 - speed));
    f3d_vehicle_set_wheel(w, v, 2, 0, push, 0);
    f3d_vehicle_set_wheel(w, v, 3, 0, push, 0);
    run(w, 1);
  }
  f3d_real spin[3], at[3], vel[3];
  f3d_body_get_angular_velocity(w, chassis, spin);
  f3d_body_get_position(w, chassis, at);
  f3d_body_get_velocity(w, chassis, vel);
  /* The drive holds a little under five against the rolling resistance:
   * the turn is the speed it holds. */
  const double speed = sqrt((double)(vel[0] * vel[0] + vel[2] * vel[2]));
  CHECK(speed > 4.5);
  /* Left is +x when forward is +z and up +y; turning left is +y spin. */
  CHECK(at[0] > F3D_R(0.5));
  CHECK_NEAR(spin[1], speed * tan(0.2) / 2.6, 0.04);
  f3d_world_destroy(w);
}

static void test_drives_through_a_turn(void) {
  /* The same drive with the front wheels turned: the tyres solved through
   * the chassis's mass and inertia together let it round the curve, and it
   * gains what it does on the straight but for a per cent or two. Solved a
   * wheel at a time as a quarter of the mass, they fought each other and it
   * gained half. */
  f3d_real speeds[2];
  for (int turning = 0; turning < 2; turning++) {
    F3dWorld *w = road();
    F3dBody chassis;
    const F3dVehicle v = car(w, F3D_R(0.86), 1, &chassis);
    run(w, 60);
    f3d_vehicle_set_wheel(w, v, 0, turning ? F3D_R(0.1) : 0, 0, 0);
    f3d_vehicle_set_wheel(w, v, 1, turning ? F3D_R(0.1) : 0, 0, 0);
    f3d_vehicle_set_wheel(w, v, 2, 0, 1200, 0);
    f3d_vehicle_set_wheel(w, v, 3, 0, 1200, 0);
    run(w, 60);
    f3d_real vel[3];
    f3d_body_get_velocity(w, chassis, vel);
    speeds[turning] = f3d_sqrt(vel[0] * vel[0] + vel[2] * vel[2]);
    f3d_world_destroy(w);
  }
  CHECK_NEAR(speeds[1], speeds[0], 0.02);
}

static void test_climbs_a_plank(void) {
  /* A plank three centimetres wide and six high across the road, crossed
   * at five metres a second: eight centimetres a step. A ray down each
   * wheel's middle steps over it and the car never feels it; the wheel's
   * rim meets it and the car rides up over it. */
  F3dWorld *w = road();
  const F3dBody plank = f3d_body_create(w, F3D_BODY_FIXED, 0, F3D_R(0.03), 6, 0);
  f3d_body_set_shape(w, plank, F3D_SHAPE_BOX, 3, F3D_R(0.03), F3D_R(0.015));
  F3dBody chassis;
  car(w, F3D_R(0.86), 1, &chassis);
  run(w, 60);
  f3d_body_set_velocity(w, chassis, 0, 0, 5);
  double most = 0;
  for (int i = 0; i < 150; i++) {
    run(w, 1);
    f3d_real vel[3];
    f3d_body_get_velocity(w, chassis, vel);
    if (fabs((double)vel[1]) > most) most = fabs((double)vel[1]);
  }
  CHECK(most > 0.05);
  /* And over it: it went on past the plank. */
  f3d_real at[3];
  f3d_body_get_position(w, chassis, at);
  CHECK(at[2] > 10);
  f3d_world_destroy(w);
}

static void test_pushes_back(void) {
  /* A car on a free platform as heavy as itself, on a floor with no
   * friction: driving forward pushes the platform back, and what the two
   * carry together stays nought. */
  F3dWorld *w = road();
  const F3dBody deck = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, F3D_R(0.25), 0, F3D_R(MASS));
  f3d_body_set_shape(w, deck, F3D_SHAPE_BOX, 4, F3D_R(0.25), 20);
  f3d_body_set_friction(w, deck, F3D_R(0.0));
  F3dBody chassis;
  const F3dVehicle v = car(w, F3D_R(1.36), 1, &chassis);
  run(w, 60);
  f3d_vehicle_set_wheel(w, v, 2, 0, 1200, 0);
  f3d_vehicle_set_wheel(w, v, 3, 0, 1200, 0);
  run(w, 60);
  f3d_real car_v[3], deck_v[3];
  f3d_body_get_velocity(w, chassis, car_v);
  f3d_body_get_velocity(w, deck, deck_v);
  CHECK(car_v[2] > F3D_R(0.5));
  CHECK_NEAR(deck_v[2], -car_v[2], 0.05);
  f3d_world_destroy(w);
}

static void test_ice(void) {
  /* At twenty metres a second the front wheels turned hard: on tarmac
   * they hold, on ice they slide and say how far past their grip. */
  for (int ice = 0; ice < 2; ice++) {
    F3dWorld *w = road();
    F3dBody chassis;
    const F3dVehicle v = car(w, F3D_R(0.86), ice ? F3D_R(0.08) : F3D_R(1.2), &chassis);
    run(w, 30);
    f3d_body_set_velocity(w, chassis, 0, 0, 20);
    f3d_vehicle_set_wheel(w, v, 0, F3D_R(0.15), 0, 0);
    f3d_vehicle_set_wheel(w, v, 1, F3D_R(0.15), 0, 0);
    run(w, 20);
    f3d_real wheels[4][F3D_WHEEL_STATE_FLOATS];
    read(w, v, wheels);
    if (ice) {
      CHECK(wheels[0][13] > F3D_R(0.5));
      CHECK(fabs((double)wheels[0][12]) > 1.0);
    } else {
      CHECK(wheels[2][13] == 0);
    }
    f3d_world_destroy(w);
  }
}

static void test_upside_down(void) {
  F3dWorld *w = road();
  F3dBody chassis;
  const F3dVehicle v = car(w, F3D_R(0.31), 1, &chassis);
  /* On its roof: the rays point at the sky. */
  f3d_body_set_orientation(w, chassis, 0, 0, 1, 0);
  run(w, 60);
  f3d_real wheels[4][F3D_WHEEL_STATE_FLOATS];
  read(w, v, wheels);
  for (int i = 0; i < 4; i++) CHECK(wheels[i][0] == 0);
  f3d_real at[3];
  f3d_body_get_position(w, chassis, at);
  CHECK_NEAR(at[1], 0.3, 0.01);
  f3d_world_destroy(w);
}

/* A chassis of [mass] on four wheels of [stiffness] and [damping], let go
 * [lift] above where its springs hold it — less than they squeeze, so no
 * wheel leaves the road and the springs stay linear — stepped at [hz]: how far above
 * that it is after each of [steps] steps, into [out]. Its heave is one
 * damped oscillator, m x'' = −4k x − 4c x', the four springs side by side. */
static void heave(double mass, double stiffness, double damping, double lift,
                  int hz, int steps, double *out) {
  F3dWorld *w = road();
  f3d_world_set_sleep(w, 0, 0);
  const double rest = 0.2 + 0.35 + 0.4 - mass * STANDARD_G / 4 / stiffness;
  const F3dBody chassis =
      f3d_body_create(w, F3D_BODY_DYNAMIC, 0, (f3d_real)(rest + lift), 0, (f3d_real)mass);
  f3d_body_set_shape(w, chassis, F3D_SHAPE_BOX, F3D_R(0.9), F3D_R(0.3), F3D_R(2.0));
  const F3dVehicle v = f3d_vehicle_create(w, chassis, 0, 1, 0, 0, 0, 1);
  for (int i = 0; i < 4; i++) {
    const f3d_real wheel[F3D_WHEEL_FLOATS] = {
        i % 2 ? F3D_R(0.8) : F3D_R(-0.8), F3D_R(-0.2), i < 2 ? F3D_R(1.3) : F3D_R(-1.3),
        F3D_R(0.4), F3D_R(0.35), (f3d_real)stiffness, (f3d_real)damping, 1};
    CHECK(f3d_vehicle_add_wheel(w, v, wheel) == i);
  }
  for (int i = 0; i < steps; i++) {
    f3d_world_step(w, F3D_R(1.0) / (f3d_real)hz);
    f3d_real at[3];
    f3d_body_get_position(w, chassis, at);
    out[i] = (double)at[1] - rest;
  }
  f3d_world_destroy(w);
}

/* The damped frequency and the damping ratio [x] rings at, sampled every
 * [dt]: the frequency from the time between its first and third crossings
 * of nought, a period; the ratio from the log decrement of its swings
 * either side, each extreme found on the parabola through its three
 * samples, δ = ln(A₁ / A₂) over half a period, ζ = δ / √(π² + δ²). */
static void ring(const double *x, int n, double dt, double *omega, double *zeta) {
  double crossing[3];
  int crossings = 0;
  double swing[2];
  int swings = 0;
  for (int i = 1; i < n - 1 && (crossings < 3 || swings < 2); i++) {
    if (crossings < 3 && (x[i - 1] < 0) != (x[i] < 0)) {
      crossing[crossings++] = (i - 1 + x[i - 1] / (x[i - 1] - x[i])) * dt;
    }
    const double a = x[i - 1], b = x[i], c = x[i + 1];
    if (crossings > 0 && swings < 2 && fabs(b) >= fabs(a) && fabs(b) > fabs(c)) {
      const double curve = a - 2 * b + c;
      swing[swings++] = fabs(b - (a - c) * (a - c) / (8 * curve));
    }
  }
  CHECK(crossings == 3 && swings == 2);
  *omega = 2 * M_PI / (crossing[2] - crossing[0]);
  const double d = log(swing[0] / swing[1]);
  *zeta = d / sqrt(M_PI * M_PI + d * d);
}

/* The heave of a car on its springs against the closed form: frequency
 * ω_d = ω_n √(1 − ζ²), ω_n = √(4k / m), and damping ratio ζ = 4c / 2√(4k m).
 * A tonne and a fifth at sixty steps a second, ω dt a sixth; and forty
 * kilograms on the same springs, ringing at nine hertz, stepped at six
 * hundred to resolve it. Both are what the springs and dampers make of
 * their mass, solved together: no wheel carries more than its share. */
static void test_heave_rings_as_the_closed_form(void) {
  static double x[2400];
  const struct {
    double mass, damping, lift;
    int hz;
  } cars[2] = {{MASS, 1200.0, 0.03, 60}, {40.0, 219.0, 0.002, 600}};
  for (int k = 0; k < 2; k++) {
    const double m = cars[k].mass, c = cars[k].damping;
    heave(m, STIFFNESS, c, cars[k].lift, cars[k].hz, 2400, x);
    const double natural = sqrt(4 * STIFFNESS / m);
    const double zeta = 4 * c / (2 * sqrt(4 * STIFFNESS * m));
    double omega, measured;
    ring(x, 2400, 1.0 / cars[k].hz, &omega, &measured);
    CHECK_NEAR(omega, natural * sqrt(1 - zeta * zeta), 0.02);
    CHECK(fabs(measured - zeta) < 0.1 * zeta);
  }
}

/* The heavy car's dampers, 3000 N s/m a wheel, under forty kilograms: ζ
 * of 2.7, far past critical. It does not overshoot, and once the fast
 * root has died it creeps back to rest at the slow one, s = ω_n (ζ −
 * √(ζ² − 1)). At six hundred steps a second that is the closed form; at
 * sixty, where a step is five times what a wheel's share of the mass and
 * its damper can carry and a damper pushed whole at the step's end threw
 * the chassis off its wheels, it is the same creep, a step's first-order
 * error faster — the solve is implicit and first order in dt. */
static void test_light_chassis_creeps_back(void) {
  static double x[2400];
  const double m = 40.0, c = 3000.0;
  const double natural = sqrt(4 * STIFFNESS / m);
  const double zeta = 4 * c / (2 * sqrt(4 * STIFFNESS * m));
  const double slow = natural * (zeta - sqrt(zeta * zeta - 1));
  const int rates[2] = {600, 60};
  for (int k = 0; k < 2; k++) {
    const int hz = rates[k], steps = 4 * hz;
    heave(m, STIFFNESS, c, 0.002, hz, steps, x);
    double lowest = 0;
    for (int i = 0; i < steps; i++) lowest = x[i] < lowest ? x[i] : lowest;
    CHECK(lowest > -1e-5);
    /* From a tenth of a second to a third. */
    const int from = hz / 10 - 1, to = hz / 3 - 1;
    const double rate = log(x[from] / x[to]) / ((double)(to - from) / hz);
    CHECK_NEAR(rate, slow, k == 0 ? 0.02 : 0.15);
    CHECK(fabs(x[steps - 1]) < 1e-5);
  }
}

/* A car left with no brake on a road tilted along its length: its tyres'
 * rolling resistance holds it as a brake of μ N does, so it stays on a
 * slope with tan θ under μ and rolls down one over it, at g (sin θ −
 * μ cos θ). And with the brakes holding B besides, the threshold is
 * m g sin θ = μ m g cos θ + B. */
static f3d_real slope_speed(double degrees, double rolling, double brake) {
  F3dWorld *w = f3d_world_create();
  f3d_world_set_air(w, F3D_STANDARD_AIR_TEMPERATURE, F3D_R(1e-30));
  f3d_world_set_sleep(w, F3D_R(0.05), 0);
  const F3dBody floor = f3d_body_create(w, F3D_BODY_FIXED, 0, F3D_R(-0.5), 0, 0);
  f3d_body_set_shape(w, floor, F3D_SHAPE_BOX, 500, F3D_R(0.5), 500);
  const double half = 0.5 * degrees * M_PI / 180.0;
  f3d_body_set_orientation(w, floor, F3D_R(sin(half)), 0, 0, F3D_R(cos(half)));
  const F3dBody chassis = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 1, 0, F3D_R(MASS));
  f3d_body_set_shape(w, chassis, F3D_SHAPE_BOX, F3D_R(0.9), F3D_R(0.3), F3D_R(2.0));
  f3d_body_set_orientation(w, chassis, F3D_R(sin(half)), 0, 0, F3D_R(cos(half)));
  const F3dVehicle v = f3d_vehicle_create(w, chassis, 0, 1, 0, 0, 0, 1);
  for (int i = 0; i < 4; i++) {
    const f3d_real wheel[F3D_WHEEL_FLOATS_ALL] = {
        i % 2 ? F3D_R(0.8) : F3D_R(-0.8), F3D_R(-0.2), i < 2 ? F3D_R(1.3) : F3D_R(-1.3),
        F3D_R(0.4), F3D_R(0.35), F3D_R(STIFFNESS), F3D_R(3000.0), 1, 0, (f3d_real)rolling};
    CHECK(f3d_vehicle_add_wheel_with(w, v, wheel, F3D_WHEEL_FLOATS_ALL) == i);
    f3d_vehicle_set_wheel(w, v, (uint32_t)i, 0, 0, (f3d_real)(brake / 4));
  }
  /* Settled on its springs, then two seconds more. */
  run(w, 120);
  f3d_real from[3], vel[3];
  f3d_body_get_velocity(w, chassis, from);
  run(w, 120);
  f3d_body_get_velocity(w, chassis, vel);
  f3d_world_destroy(w);
  /* What it gained down the slope in two seconds, along it. */
  return (f3d_real)((sqrt((double)(vel[1] * vel[1] + vel[2] * vel[2])) -
                     sqrt((double)(from[1] * from[1] + from[2] * from[2]))) /
                    2.0);
}

static void test_rolling_resistance_holds_and_lets_go(void) {
  const double mu = 0.05, g = STANDARD_G;
  /* tan θ = 0.05 is 2.86°: at 2.5° it holds. */
  CHECK(fabs((double)slope_speed(2.5, mu, 0)) < 1e-3);
  /* At 4° it rolls, at g (sin θ − μ cos θ). */
  const double t4 = 4.0 * M_PI / 180.0;
  const double pull = MASS * g * (sin(t4) - mu * cos(t4));
  CHECK_NEAR(slope_speed(4.0, mu, 0), g * (sin(t4) - mu * cos(t4)), 0.01);
  /* A brake of a little more than the pull left over holds it there; one
   * of half of it lets it go at what is left. */
  CHECK(fabs((double)slope_speed(4.0, mu, 1.2 * pull)) < 1e-3);
  CHECK_NEAR(slope_speed(4.0, mu, 0.5 * pull), 0.5 * pull / MASS, 0.01);
}

/* Coasting on the flat from ten metres a second, nothing on the drive or
 * the brake: the tyres take μ m g from it, so it slows at μ g. */
static void test_coasts_down_at_mu_g(void) {
  F3dWorld *w = road();
  F3dBody chassis;
  car(w, F3D_R(0.86), 1, &chassis);
  run(w, 60);
  f3d_body_set_velocity(w, chassis, 0, 0, 10);
  run(w, 120);
  f3d_real vel[3];
  f3d_body_get_velocity(w, chassis, vel);
  CHECK_NEAR(vel[2], 10 - 2 * F3D_WHEEL_ROLLING_DEFAULT * STANDARD_G, 0.003);
  f3d_world_destroy(w);
}

/* A wheel's width is its own: a narrow one rolls past a post that a wide
 * one, its rim reaching it, climbs. */
static void test_wheel_width(void) {
  double rose[2];
  for (int wide = 0; wide < 2; wide++) {
    F3dWorld *w = road();
    /* A kerb six centimetres high, beside the line the right wheels run
     * along, ten to forty centimetres right of their middle. */
    const F3dBody kerb = f3d_body_create(w, F3D_BODY_FIXED, F3D_R(-1.05), F3D_R(0.03), 6, 0);
    f3d_body_set_shape(w, kerb, F3D_SHAPE_BOX, F3D_R(0.15), F3D_R(0.03), F3D_R(0.5));
    const F3dBody chassis = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, F3D_R(0.86), 0, F3D_R(MASS));
    f3d_body_set_shape(w, chassis, F3D_SHAPE_BOX, F3D_R(0.9), F3D_R(0.3), F3D_R(2.0));
    const F3dVehicle v = f3d_vehicle_create(w, chassis, 0, 1, 0, 0, 0, 1);
    for (int i = 0; i < 4; i++) {
      const f3d_real wheel[F3D_WHEEL_FLOATS_ALL] = {
          i % 2 ? F3D_R(0.8) : F3D_R(-0.8), F3D_R(-0.2), i < 2 ? F3D_R(1.3) : F3D_R(-1.3),
          F3D_R(0.4), F3D_R(0.35), F3D_R(STIFFNESS), F3D_R(3000.0), 1,
          wide ? F3D_R(0.6) : F3D_R(0.1), 0};
      CHECK(f3d_vehicle_add_wheel_with(w, v, wheel, F3D_WHEEL_FLOATS_ALL) == i);
    }
    run(w, 60);
    f3d_body_set_velocity(w, chassis, 0, 0, 3);
    double most = 0;
    for (int i = 0; i < 150; i++) {
      run(w, 1);
      f3d_real wheels[4][F3D_WHEEL_STATE_FLOATS];
      read(w, v, wheels);
      const double squeezed = 0.4 - (double)wheels[0][1];
      if (squeezed > most) most = squeezed;
    }
    rose[wide] = most;
    f3d_world_destroy(w);
  }
  /* The narrow one's spring only ever held the car, a quarter of its
   * weight; the wide one's took the kerb's height on top. */
  const double held = MASS * STANDARD_G / 4 / STIFFNESS;
  CHECK(rose[0] < held + 0.02);
  CHECK(rose[1] > held + 0.04);
}

/* Braked on a road tilted five degrees along its length: the brakes hold
 * four times what the slope pulls with, so it stays put, and does not
 * creep down by the step's pull each step. */
static void test_holds_on_a_slope(void) {
  F3dWorld *w = f3d_world_create();
  f3d_world_set_air(w, F3D_STANDARD_AIR_TEMPERATURE, F3D_R(1e-30));
  /* Awake throughout: asleep, it would hold whether the tyres did or not. */
  f3d_world_set_sleep(w, F3D_R(0.05), 0);
  const F3dBody floor = f3d_body_create(w, F3D_BODY_FIXED, 0, F3D_R(-0.5), 0, 0);
  f3d_body_set_shape(w, floor, F3D_SHAPE_BOX, 500, F3D_R(0.5), 500);
  const double half = 0.5 * 5.0 * 3.14159265358979 / 180.0;
  f3d_body_set_orientation(w, floor, F3D_R(sin(half)), 0, 0, F3D_R(cos(half)));
  F3dBody chassis;
  const F3dVehicle v = car(w, 1, 1, &chassis);
  for (int i = 0; i < 4; i++) f3d_vehicle_set_wheel(w, v, i, 0, 0, 3000);
  run(w, 120);
  f3d_real from[3], to[3];
  f3d_body_get_position(w, chassis, from);
  run(w, 180);
  f3d_body_get_position(w, chassis, to);
  CHECK(fabs((double)(to[2] - from[2])) < 1e-3);
  f3d_world_destroy(w);
}

static void test_snapshot(void) {
  F3dWorld *w = road();
  F3dBody chassis;
  const F3dVehicle v = car(w, 1, 1, &chassis);
  f3d_vehicle_set_wheel(w, v, 0, F3D_R(0.3), 0, 0);
  f3d_vehicle_set_wheel(w, v, 1, F3D_R(0.3), 0, 0);
  f3d_vehicle_set_wheel(w, v, 2, 0, 2000, 0);
  f3d_vehicle_set_wheel(w, v, 3, 0, 2000, 0);
  run(w, 45);
  const uint32_t size = f3d_world_snapshot_size(w);
  uint8_t *bytes = (uint8_t *)malloc(size);
  CHECK(f3d_world_snapshot_write(w, bytes, size) == size);
  F3dWorld *copy = f3d_world_create();
  CHECK(f3d_world_restore(copy, bytes, size) == 1);
  CHECK(f3d_vehicle_wheel_count(copy, v) == 4);
  run(w, 120);
  run(copy, 120);
  f3d_real a[4][F3D_WHEEL_STATE_FLOATS], b[4][F3D_WHEEL_STATE_FLOATS];
  read(w, v, a);
  read(copy, v, b);
  CHECK(memcmp(a, b, sizeof a) == 0);
  f3d_real pa[3], pb[3];
  f3d_body_get_position(w, chassis, pa);
  f3d_body_get_position(copy, chassis, pb);
  CHECK(memcmp(pa, pb, sizeof pa) == 0);
  free(bytes);
  f3d_world_destroy(w);
  f3d_world_destroy(copy);
}

int main(void) {
  test_refusals();
  test_rests();
  test_drives_and_brakes();
  test_steers();
  test_drives_through_a_turn();
  test_climbs_a_plank();
  test_pushes_back();
  test_ice();
  test_upside_down();
  test_heave_rings_as_the_closed_form();
  test_light_chassis_creeps_back();
  test_rolling_resistance_holds_and_lets_go();
  test_coasts_down_at_mu_g();
  test_wheel_width();
  test_holds_on_a_slope();
  test_snapshot();
  return finish();
}
