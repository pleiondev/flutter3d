/*
 * A joint's drive, tested in C: a muscle's tone, an active torque that pulls
 * a joint towards a posture with a stiffness and a damping and never more
 * than its most torque, and a level that fades to a floor over a time
 * constant, keeping the bodies awake until it is there; held by a hinge and
 * a ball alike, through a snapshot, and what each setting refuses.
 */
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "check.h"

static F3dWorld *world(void) {
  F3dWorld *w = f3d_world_create();
  f3d_world_set_air(w, F3D_STANDARD_AIR_TEMPERATURE, F3D_R(1e-30));
  f3d_world_set_sleep(w, 0, 0);
  return w;
}

static void run(F3dWorld *w, int steps) {
  for (int i = 0; i < steps; i++) f3d_world_step(w, F3D_R(1.0 / 60.0));
}

/* A limb of a kilogram a metre long along +x from a pivot at (0, 2, 0),
 * on a hinge about z or a ball, damped a little, held level by a drive of
 * [k] N m/rad, [c] N m s/rad and at most [most] N m towards how it was
 * made, its weight's moment, g / 2 N m, pulling it down; with [most]
 * below nought, no drive at all. */
static F3dJoint level_limb(F3dWorld *w, F3dJointType type, f3d_real k,
                           f3d_real c, f3d_real most, F3dBody *limb) {
  const F3dBody pivot = f3d_body_create(w, F3D_BODY_FIXED, 0, 2, 0, 0);
  *limb = f3d_body_create(w, F3D_BODY_DYNAMIC, F3D_R(0.5), 2, 0, 1);
  f3d_body_set_shape(w, *limb, F3D_SHAPE_BOX, F3D_R(0.5), F3D_R(0.05), F3D_R(0.05));
  const F3dJoint j = f3d_joint_create(w, type, pivot, *limb, 0, 2, 0, 0, 0, 1);
  CHECK(f3d_joint_set_damping(w, j, 1, F3D_R(0.5)));
  if (most >= 0) CHECK(f3d_joint_set_drive(w, j, 1, 0, 0, 0, 1, k, c, most));
  return j;
}

/* How far below level the limb's far end points, radians. */
static double drop(const F3dWorld *w, F3dBody limb) {
  f3d_real p[3];
  f3d_body_get_position(w, limb, p);
  return atan2(-(double)(p[1] - 2), sqrt((double)p[0] * p[0] + (double)p[2] * p[2]));
}

/* Where the drive holds the limb by the law: k θ = (g / 2) cos θ. */
static double held_by_law(double k) {
  double theta = 0;
  for (int i = 0; i < 100; i++) theta = STANDARD_G * 0.5 * cos(theta) / k;
  return theta;
}

static void test_holds_a_posture(void) {
  /* On a hinge and on a ball, the drive holds the limb where its spring
   * carries the weight's moment. Mutation: read the stiffness per degree, or
   * drop it — the limb hangs a radian or more lower. */
  const double k = 60;
  for (int t = 0; t < 2; t++) {
    F3dWorld *w = world();
    F3dBody limb;
    level_limb(w, t ? F3D_JOINT_SPHERICAL : F3D_JOINT_REVOLUTE, (f3d_real)k, 5,
               1000, &limb);
    run(w, 240);
    CHECK_NEAR(drop(w, limb), held_by_law(k), 0.01);
    f3d_world_destroy(w);
  }
  /* Stiffer than the substep holds, on a hinge and a ball, it holds
   * steady, as stiff as the joint's locks. Mutation: take the stiffness as
   * asked — at a million N m/rad the limb shakes by half a radian. */
  for (int t = 0; t < 2; t++) {
    F3dWorld *w = world();
    F3dBody limb;
    level_limb(w, t ? F3D_JOINT_SPHERICAL : F3D_JOINT_REVOLUTE, 1e6, 0, 1e6,
               &limb);
    double most = 0;
    for (int i = 0; i < 120; i++) {
      run(w, 1);
      most = fmax(most, fabs(drop(w, limb)));
    }
    CHECK(most < 2e-3);
    f3d_world_destroy(w);
  }
}

static void test_never_more_than_its_torque(void) {
  /* Its most torque, 3 N m, below the weight's moment, g / 2 ≈ 4.9 N m, it
   * cannot hold the limb level, however stiff: the limb falls until the
   * moment, (g / 2) cos θ, is no more than 3. With room above the moment, it
   * holds. Mutation: drop the cap — held level at 3 N m too. */
  F3dWorld *w = world();
  F3dBody limb;
  level_limb(w, F3D_JOINT_REVOLUTE, 1000, 20, 3, &limb);
  /* Saturated, its damping is spent holding: the swing dies away on the
   * joint's own damping alone, over seconds. */
  run(w, 720);
  /* Held where the moment is 3 N m, within the few per cent the substeps
   * give (3.06 at four). */
  CHECK_NEAR(STANDARD_G * 0.5 * cos(drop(w, limb)), 3, 0.04);
  f3d_world_destroy(w);
  w = world();
  level_limb(w, F3D_JOINT_REVOLUTE, 1000, 20, 6, &limb);
  run(w, 240);
  CHECK(fabs(drop(w, limb)) < 0.02);
  f3d_world_destroy(w);
  /* A ball's torque is cut as a whole, not about each axis apart. Gravity
   * down and along −z alike, the weight's 4.9 N m is 3.5 about each of y
   * and z: at most 4 N m about each axis would hold it; at most 4 in all
   * lets it swing down until the moment is 4, 0.62 rad on. Mutation: clamp
   * each axis on its own — it stays where it was. */
  w = world();
  const double g = STANDARD_G / sqrt(2.0);
  f3d_world_set_gravity(w, 0, (f3d_real)-g, (f3d_real)-g);
  level_limb(w, F3D_JOINT_SPHERICAL, 1000, 20, 4, &limb);
  run(w, 240);
  f3d_real p[3];
  f3d_body_get_position(w, limb, p);
  const double r = sqrt((double)p[0] * p[0] + (double)(p[1] - 2) * (p[1] - 2) +
                        (double)p[2] * p[2]);
  CHECK_NEAR(acos(p[0] / r), M_PI / 2 - asin(4 / (STANDARD_G * 0.5)), 0.02);
  f3d_world_destroy(w);
}

static void test_a_target_of_its_own(void) {
  /* Pulled towards a quarter turn down about z on a hinge — a target, not
   * how it was made — and no gravity: it goes there. */
  F3dWorld *w = world();
  f3d_world_set_gravity(w, 0, 0, 0);
  F3dBody limb;
  const F3dJoint j = level_limb(w, F3D_JOINT_REVOLUTE, 50, 5, 100, &limb);
  const double half = -M_PI / 8;
  CHECK(f3d_joint_set_drive(w, j, 1, 0, 0, (f3d_real)sin(half), (f3d_real)cos(half),
                            50, 5, 100));
  run(w, 240);
  CHECK_NEAR(drop(w, limb), M_PI / 4, 0.01);
  f3d_world_destroy(w);
}

static void test_fades(void) {
  /* Its level falls to the floor as exp(−t / fade): after a second at a
   * fade of half a second, by e⁻² of the way. Mutation: fade per step and
   * not per substep — it falls four times as fast. */
  F3dWorld *w = world();
  F3dBody limb;
  const F3dJoint j = level_limb(w, F3D_JOINT_REVOLUTE, 60, 5, 1000, &limb);
  f3d_real level;
  CHECK(f3d_joint_get_drive_level(w, j, &level));
  CHECK(level == 1);
  CHECK(f3d_joint_set_drive_fade(w, j, F3D_R(0.1), F3D_R(0.5)));
  run(w, 60);
  CHECK(f3d_joint_get_drive_level(w, j, &level));
  CHECK_NEAR(level, 0.1 + 0.9 * exp(-2.0), 1e-4);
  /* Faded, it holds the limb as a drive of the floor's share would. */
  run(w, 480);
  CHECK_NEAR(drop(w, limb), held_by_law(60 * 0.1), 0.02);
  /* Set again while on, a drive keeps its level; off and on, it starts at
   * 1. */
  CHECK(f3d_joint_set_drive(w, j, 1, 0, 0, 0, 1, 60, 5, 1000));
  CHECK(f3d_joint_get_drive_level(w, j, &level));
  CHECK(level < F3D_R(0.11));
  CHECK(f3d_joint_set_drive(w, j, 0, 0, 0, 0, 0, 0, 0, 0));
  CHECK(f3d_joint_get_drive_level(w, j, &level));
  CHECK(level == 0);
  CHECK(f3d_joint_set_drive(w, j, 1, 0, 0, 0, 1, 60, 5, 1000));
  CHECK(f3d_joint_get_drive_level(w, j, &level));
  CHECK(level == 1);
  /* A fade of nought holds the level where it is. */
  CHECK(f3d_joint_set_drive_fade(w, j, 0, 0));
  run(w, 60);
  CHECK(f3d_joint_get_drive_level(w, j, &level));
  CHECK(level == 1);
  f3d_world_destroy(w);
}

static void test_fading_keeps_it_awake(void) {
  /* A limb held still by its tone with sleep on, its tone fading slowly:
   * it does not fall asleep held, but goes limp and hangs. Mutation: let an
   * island sleep while its drive fades — it sleeps held level and stays. */
  F3dWorld *w = f3d_world_create();
  f3d_world_set_air(w, F3D_STANDARD_AIR_TEMPERATURE, F3D_R(1e-30));
  F3dBody limb;
  const F3dJoint j = level_limb(w, F3D_JOINT_REVOLUTE, 2000, 50, 1000, &limb);
  run(w, 30);
  CHECK(f3d_joint_set_drive_fade(w, j, 0, 1));
  run(w, 900);
  CHECK(drop(w, limb) > 1.4);
  f3d_world_destroy(w);
}

static void test_without_a_drive_nothing_moves(void) {
  /* A drive turned off, or of nought stiffness and damping, steps to the
   * very bits of a joint that never had one. */
  F3dWorld *worlds[3];
  F3dBody limbs[3];
  for (int i = 0; i < 3; i++) {
    worlds[i] = world();
    const F3dJoint j =
        level_limb(worlds[i], F3D_JOINT_SPHERICAL, 60, 5, i == 0 ? -1 : 100, &limbs[i]);
    if (i == 1) CHECK(f3d_joint_set_drive(worlds[i], j, 0, 0, 0, 0, 0, 0, 0, 0));
    if (i == 2) {
      CHECK(f3d_joint_set_drive(worlds[i], j, 1, 0, 0, 0, 1, 0, 0, 100));
    }
    f3d_body_set_angular_velocity(worlds[i], limbs[i], 1, 0, 2);
    run(worlds[i], 90);
  }
  f3d_real p0[3], p1[3], p2[3];
  f3d_body_get_position(worlds[0], limbs[0], p0);
  f3d_body_get_position(worlds[1], limbs[1], p1);
  f3d_body_get_position(worlds[2], limbs[2], p2);
  CHECK(memcmp(p0, p1, sizeof p0) == 0);
  CHECK(memcmp(p0, p2, sizeof p0) == 0);
  for (int i = 0; i < 3; i++) f3d_world_destroy(worlds[i]);
}

static void test_snapshot(void) {
  /* The drive and its fade, mid-way, through a snapshot: the world
   * restored steps to the same bytes. */
  F3dWorld *w = world();
  F3dBody limb;
  const F3dJoint j = level_limb(w, F3D_JOINT_SPHERICAL, 80, 4, 30, &limb);
  CHECK(f3d_joint_set_drive_fade(w, j, F3D_R(0.2), F3D_R(0.3)));
  f3d_body_set_angular_velocity(w, limb, 1, 0, 3);
  run(w, 10);
  const uint32_t size = f3d_world_snapshot_size(w);
  uint8_t *snap = (uint8_t *)malloc(size);
  f3d_world_snapshot_write(w, snap, size);
  F3dWorld *v = f3d_world_create();
  CHECK(f3d_world_restore(v, snap, size) == 1);
  f3d_real level;
  CHECK(f3d_joint_get_drive_level(v, j, &level));
  CHECK(level < 1 && level > F3D_R(0.2));
  run(w, 60);
  run(v, 60);
  const uint32_t now = f3d_world_snapshot_size(w);
  uint8_t *a = (uint8_t *)malloc(now), *b = (uint8_t *)malloc(now);
  f3d_world_snapshot_write(w, a, now);
  CHECK(f3d_world_snapshot_size(v) == now);
  f3d_world_snapshot_write(v, b, now);
  CHECK(memcmp(a, b, now) == 0);
  free(snap);
  free(a);
  free(b);
  f3d_world_destroy(w);
  f3d_world_destroy(v);
}

static void test_refusals(void) {
  F3dWorld *w = world();
  F3dBody limb;
  const F3dJoint ball = level_limb(w, F3D_JOINT_SPHERICAL, 1, 1, 1, &limb);
  const F3dBody other = f3d_body_create(w, F3D_BODY_DYNAMIC, 3, 2, 0, 1);
  const F3dJoint slider = f3d_joint_create(w, F3D_JOINT_PRISMATIC, limb, other, 3, 2, 0, 1, 0, 0);
  const F3dJoint fixed = f3d_joint_create(w, F3D_JOINT_FIXED, limb, other, 3, 2, 0, 0, 0, 0);
  /* A drive is a turning joint's, its target a turn, its strengths nought
   * or more. */
  CHECK(!f3d_joint_set_drive(w, slider, 1, 0, 0, 0, 1, 1, 1, 1));
  CHECK(!f3d_joint_set_drive(w, fixed, 1, 0, 0, 0, 1, 1, 1, 1));
  CHECK(!f3d_joint_set_drive(w, ball, 1, 0, 0, 0, 0, 1, 1, 1));
  CHECK(!f3d_joint_set_drive(w, ball, 1, nan_value(), 0, 0, 1, 1, 1, 1));
  CHECK(!f3d_joint_set_drive(w, ball, 1, 0, 0, 0, 1, -1, 1, 1));
  CHECK(!f3d_joint_set_drive(w, ball, 1, 0, 0, 0, 1, 1, -1, 1));
  CHECK(!f3d_joint_set_drive(w, ball, 1, 0, 0, 0, 1, 1, 1, nan_value()));
  CHECK(f3d_joint_set_drive(w, ball, 1, 0, 0, 0, 2, 0, 0, 0));
  /* A fade, a driven joint's, its floor and time nought or more. */
  CHECK(!f3d_joint_set_drive_fade(w, slider, 0, 1));
  CHECK(!f3d_joint_set_drive_fade(w, ball, -1, 1));
  CHECK(!f3d_joint_set_drive_fade(w, ball, 0, -1));
  CHECK(!f3d_joint_set_drive_fade(w, ball, 0, nan_value()));
  CHECK(f3d_joint_set_drive_fade(w, ball, 0, 0));
  CHECK(f3d_joint_set_drive(w, ball, 0, nan_value(), 0, 0, 0, -1, -1, -1));
  CHECK(!f3d_joint_set_drive_fade(w, ball, 0, 1));
  f3d_world_destroy(w);
}

int main(void) {
  test_holds_a_posture();
  test_never_more_than_its_torque();
  test_a_target_of_its_own();
  test_fades();
  test_fading_keeps_it_awake();
  test_without_a_drive_nothing_moves();
  test_snapshot();
  test_refusals();
  return finish();
}
