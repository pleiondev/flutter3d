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
  f3d_world_set_air(w, F3D_R(293.15), F3D_R(1e-30));
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
  const double squeeze = MASS * 9.81 / 4 / STIFFNESS;
  const double height = 0.2 + 0.35 + (0.4 - squeeze);
  f3d_real at[3];
  f3d_body_get_position(w, chassis, at);
  CHECK_NEAR(at[1], height, 2e-3);
  f3d_real wheels[4][F3D_WHEEL_STATE_FLOATS];
  read(w, v, wheels);
  for (int i = 0; i < 4; i++) {
    CHECK(wheels[i][0] == 1);
    /* Asleep within a millimetre of rest: the springs as it stopped. */
    CHECK_NEAR(wheels[i][11], MASS * 9.81 / 4, 15);
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
  /* 1200 N on each rear wheel: two metres a second, every second. */
  f3d_vehicle_set_wheel(w, v, 2, 0, 1200, 0);
  f3d_vehicle_set_wheel(w, v, 3, 0, 1200, 0);
  run(w, 120);
  f3d_real vel[3];
  f3d_body_get_velocity(w, chassis, vel);
  CHECK_NEAR(vel[2], 4.0, 0.08);
  CHECK(fabs((double)vel[0]) < 1e-3);
  f3d_real wheels[4][F3D_WHEEL_STATE_FLOATS];
  read(w, v, wheels);
  CHECK_NEAR(wheels[0][4], vel[2] / 0.35, 0.05);
  CHECK(wheels[0][3] > 10);
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
  f3d_real spin[3], at[3];
  f3d_body_get_angular_velocity(w, chassis, spin);
  f3d_body_get_position(w, chassis, at);
  /* Left is +x when forward is +z and up +y; turning left is +y spin. */
  CHECK(at[0] > F3D_R(0.5));
  CHECK_NEAR(spin[1], 5 * tan(0.2) / 2.6, 0.04);
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
  test_pushes_back();
  test_ice();
  test_upside_down();
  test_snapshot();
  return finish();
}
