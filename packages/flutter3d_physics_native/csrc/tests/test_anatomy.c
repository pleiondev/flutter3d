/*
 * The limits of an anatomy, tested in C: a spherical joint's swing held
 * further ahead than behind and further to one side than the other,
 * measured from a neutral direction that need not be where the limb rests;
 * viscous damping that takes a swing down at the rate a damped pendulum's
 * law gives; soft limits that give under a load by the load over their
 * stiffness; all of it through a snapshot; and what each refuses.
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

/* A limb a metre long hung by its end from a pivot at (0, 2, 0) on a
 * spherical joint, its axis down. */
static F3dJoint hung(F3dWorld *w, F3dBody *limb) {
  const F3dBody pivot = f3d_body_create(w, F3D_BODY_FIXED, 0, 2, 0, 0);
  *limb = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, F3D_R(1.5), 0, 1);
  f3d_body_set_shape(w, *limb, F3D_SHAPE_BOX, F3D_R(0.05), F3D_R(0.5), F3D_R(0.05));
  return f3d_joint_create(w, F3D_JOINT_SPHERICAL, pivot, *limb, 0, 2, 0, 0, -1, 0);
}

/* The limits the swing tests use: neutral down, ahead +z; 1.2 rad ahead,
 * 0.4 behind, 0.8 towards down × ahead, which is −x, and 0.3 towards +x. */
static void limit(F3dWorld *w, F3dJoint j) {
  CHECK(f3d_joint_set_swing(w, j, 1, 0, -1, 0, 0, 0, 1, F3D_R(1.2), F3D_R(0.4),
                            F3D_R(0.8), F3D_R(0.3)));
}

/* Where the limb's far end points from the pivot, unit. */
static void pointing(const F3dWorld *w, F3dBody limb, double *d) {
  f3d_real p[3];
  f3d_body_get_position(w, limb, p);
  const double x = p[0], y = p[1] - 2.0, z = p[2];
  const double l = sqrt(x * x + y * y + z * z);
  d[0] = x / l;
  d[1] = y / l;
  d[2] = z / l;
}

/* The limb knocked at [vx], [vz] m/s, and the furthest it swung from down
 * the way it was knocked, before it swung back through down; with
 * [limited], inside the limits above. */
static double knocked(f3d_real vx, f3d_real vz, int limited) {
  F3dWorld *w = world();
  F3dBody limb;
  const F3dJoint j = hung(w, &limb);
  if (limited) limit(w, j);
  f3d_body_set_velocity(w, limb, vx, 0, vz);
  const double speed = sqrt((double)vx * vx + (double)vz * vz);
  double most = 0;
  for (int i = 0; i < 120; i++) {
    run(w, 1);
    double d[3];
    pointing(w, limb, d);
    if ((d[0] * vx + d[2] * vz) / speed <= 0) break;
    const double swing = acos(fmax(-1.0, fmin(1.0, -d[1])));
    if (swing > most) most = swing;
  }
  f3d_world_destroy(w);
  return most;
}

static void test_four_sides(void) {
  /* Free, a knock of 6 m/s swings it past level every way. */
  CHECK(knocked(0, 6, 0) > M_PI / 2);
  CHECK(knocked(0, -6, 0) > M_PI / 2);
  /* Limited, it stops at each side's own limit, give or take what the
   * joint's soft spring lets through as it strikes. Mutation: measure every
   * side against the ahead limit — behind and the two sides swing on. */
  CHECK_NEAR(knocked(0, 6, 1), 1.2, 0.05);
  CHECK_NEAR(knocked(0, -6, 1), 0.4, 0.05);
  CHECK_NEAR(knocked(-6, 0, 1), 0.8, 0.05);
  CHECK_NEAR(knocked(6, 0, 1), 0.3, 0.05);
  /* Between ahead and the wide side, the ellipse: the swing stops short
   * of either limit alone. At 45 degrees the ellipse through 1.2 and 0.8
   * is at 1 / √((cos/1.2)² + (sin/0.8)²). */
  const double c = cos(M_PI / 4), s = sin(M_PI / 4);
  const double ellipse = 1.0 / sqrt((c / 1.2) * (c / 1.2) + (s / 0.8) * (s / 0.8));
  CHECK_NEAR(knocked((f3d_real)(-6 * s), (f3d_real)(6 * c), 1), ellipse, 0.06);
}

static void test_neutral_is_not_rest(void) {
  /* The limb made pointing along +z, square to the neutral, which is down,
   * and pulled along +z: with only 0.6 rad allowed ahead, it is brought
   * back to 0.6 and held there. Mutation: measure from the limb's own axis
   * — it stays out along +z. */
  F3dWorld *w = world();
  f3d_world_set_gravity(w, 0, 0, F3D_R(9.81));
  const F3dBody pivot = f3d_body_create(w, F3D_BODY_FIXED, 0, 2, 0, 0);
  const F3dBody limb = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 2, F3D_R(0.5), 1);
  f3d_body_set_shape(w, limb, F3D_SHAPE_BOX, F3D_R(0.05), F3D_R(0.05), F3D_R(0.5));
  const F3dJoint j = f3d_joint_create(w, F3D_JOINT_SPHERICAL, pivot, limb, 0, 2, 0, 0, 0, 1);
  CHECK(f3d_joint_set_swing(w, j, 1, 0, -1, 0, 0, 0, 1, F3D_R(0.6), F3D_R(0.6), F3D_R(0.6), F3D_R(0.6)));
  CHECK(f3d_joint_set_damping(w, j, 1, 1));
  run(w, 120);
  double d[3];
  pointing(w, limb, d);
  CHECK_NEAR(acos(-d[1]), 0.6, 0.02);
  CHECK(d[2] > 0);
  f3d_world_destroy(w);
}

/* A pendulum on a hinge about z: a box a metre long hung by its end, swung
 * a tenth of a radian, damped at [c] N m s/rad; the swings' peaks, and the
 * time between them, over [seconds]. */
static int damped(f3d_real c, double seconds, double *peaks, int most) {
  F3dWorld *w = world();
  const F3dBody pivot = f3d_body_create(w, F3D_BODY_FIXED, 0, 2, 0, 0);
  const F3dBody limb = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, F3D_R(1.5), 0, 1);
  f3d_body_set_shape(w, limb, F3D_SHAPE_BOX, F3D_R(0.05), F3D_R(0.5), F3D_R(0.05));
  const F3dJoint j = f3d_joint_create(w, F3D_JOINT_REVOLUTE, pivot, limb, 0, 2, 0, 0, 0, 1);
  if (c > 0) CHECK(f3d_joint_set_damping(w, j, 1, c));
  f3d_body_set_angular_velocity(w, limb, 0, 0, F3D_R(0.5));
  f3d_body_set_velocity(w, limb, F3D_R(0.25), 0, 0);
  int n = 0;
  double before = 0, last = 0;
  for (int i = 0; i < (int)(seconds * 60) && n < most; i++) {
    run(w, 1);
    f3d_real angle;
    f3d_joint_get_value(w, j, &angle);
    if (i > 1 && last > before && last > angle) peaks[n++] = last;
    before = last;
    last = angle;
  }
  f3d_world_destroy(w);
  return n;
}

static void test_damping(void) {
  /* About its end a uniform rod of a kilogram and a metre turns with
   * I = m l²/3 + its width's share; damped at c, its swing falls as
   * exp(−c t / 2I) — from one peak to the next by exp(−c T / 2I), T its
   * period. Mutation: drop the damping's implicit denominator, or apply it
   * in both passes — the decay is off by a half. */
  double free_peaks[8], peaks[8];
  const int nf = damped(0, 12, free_peaks, 8);
  const int n = damped(F3D_R(0.05), 12, peaks, 8);
  CHECK(nf >= 6 && n >= 6);
  /* Undamped, it keeps its swing. */
  CHECK_NEAR(free_peaks[5], free_peaks[0], 0.01);
  const double inertia = (1.0 * 1.0 + 0.1 * 0.1) / 12.0 + 0.25;
  const double period = 2 * M_PI * sqrt(inertia / (STANDARD_G * 0.5));
  const double want = exp(-0.05 * 5 * period / (2 * inertia));
  CHECK_NEAR(peaks[5] / peaks[0], want, 0.02);
}

/* A limb along +x from a hinge about z, between −0.2 and 0.2 rad, let go
 * under gravity: where it hangs after three seconds, its limit [soft] or
 * hard. */
static double sagged(f3d_real stiffness) {
  F3dWorld *w = world();
  const F3dBody pivot = f3d_body_create(w, F3D_BODY_FIXED, 0, 2, 0, 0);
  const F3dBody limb = f3d_body_create(w, F3D_BODY_DYNAMIC, F3D_R(0.5), 2, 0, 1);
  f3d_body_set_shape(w, limb, F3D_SHAPE_BOX, F3D_R(0.5), F3D_R(0.05), F3D_R(0.05));
  const F3dJoint j = f3d_joint_create(w, F3D_JOINT_REVOLUTE, pivot, limb, 0, 2, 0, 0, 0, 1);
  CHECK(f3d_joint_set_limits(w, j, 1, F3D_R(-0.2), F3D_R(0.2)));
  CHECK(f3d_joint_set_damping(w, j, 1, 2));
  if (stiffness > 0) CHECK(f3d_joint_set_limit_softness(w, j, 1, stiffness, 1));
  run(w, 180);
  f3d_real angle;
  f3d_joint_get_value(w, j, &angle);
  f3d_world_destroy(w);
  return angle;
}

static void test_soft_limits(void) {
  /* Hard, it stops at the limit. Soft, it hangs where the spring past the
   * limit carries its weight's moment, m g (l/2) cos θ = k (−0.2 − θ).
   * Mutation: read the stiffness as hertz — it sags a radian or none. */
  CHECK_NEAR(sagged(0), -0.2, 0.01);
  const double k = 100, load = STANDARD_G * 0.5;
  double theta = -0.2;
  for (int i = 0; i < 50; i++) theta = -0.2 - load * cos(theta) / k;
  CHECK_NEAR(sagged((f3d_real)k), theta, 0.01);
  CHECK(sagged((f3d_real)k) < -0.23);
}

/* The swing limits, the damping and the softness held through a
 * snapshot: the world restored steps to the same bytes. */
static void test_snapshot(void) {
  F3dWorld *w = world();
  F3dBody limb;
  const F3dJoint j = hung(w, &limb);
  limit(w, j);
  CHECK(f3d_joint_set_damping(w, j, 1, F3D_R(0.5)));
  CHECK(f3d_joint_set_limit_softness(w, j, 1, 50, F3D_R(0.3)));
  f3d_body_set_velocity(w, limb, 0, 0, 6);
  run(w, 10);
  const uint32_t size = f3d_world_snapshot_size(w);
  uint8_t *snap = (uint8_t *)malloc(size);
  f3d_world_snapshot_write(w, snap, size);
  F3dWorld *v = f3d_world_create();
  CHECK(f3d_world_restore(v, snap, size) == 1);
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
  const F3dJoint j = hung(w, &limb);
  const F3dBody other = f3d_body_create(w, F3D_BODY_DYNAMIC, 3, 2, 0, 1);
  const F3dJoint hinge = f3d_joint_create(w, F3D_JOINT_REVOLUTE, limb, other, 3, 2, 0, 0, 0, 1);
  const F3dJoint slider = f3d_joint_create(w, F3D_JOINT_PRISMATIC, limb, other, 3, 2, 0, 1, 0, 0);
  /* Swing limits are a spherical joint's, each above nought and below 3,
   * about a neutral and an ahead that are not one direction. */
  CHECK(!f3d_joint_set_swing(w, hinge, 1, 0, -1, 0, 0, 0, 1, 1, 1, 1, 1));
  CHECK(!f3d_joint_set_swing(w, j, 1, 0, -1, 0, 0, 0, 1, 0, 1, 1, 1));
  CHECK(!f3d_joint_set_swing(w, j, 1, 0, -1, 0, 0, 0, 1, 1, 1, 3, 1));
  CHECK(!f3d_joint_set_swing(w, j, 1, 0, -1, 0, 0, 2, 0, 1, 1, 1, 1));
  CHECK(!f3d_joint_set_swing(w, j, 1, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1));
  CHECK(!f3d_joint_set_swing(w, j, 1, nan_value(), -1, 0, 0, 0, 1, 1, 1, 1, 1));
  CHECK(f3d_joint_set_swing(w, j, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0));
  /* Damping and soft limits are a turning joint's, damping nought or more,
   * stiffness above nought and a ratio nought or more. */
  CHECK(!f3d_joint_set_damping(w, slider, 1, 1));
  CHECK(!f3d_joint_set_damping(w, hinge, 1, -1));
  CHECK(f3d_joint_set_damping(w, hinge, 1, 0));
  CHECK(!f3d_joint_set_limit_softness(w, slider, 1, 1, 1));
  CHECK(!f3d_joint_set_limit_softness(w, hinge, 1, 0, 1));
  CHECK(!f3d_joint_set_limit_softness(w, hinge, 1, 1, -1));
  CHECK(f3d_joint_set_limit_softness(w, hinge, 0, 0, 0));
  f3d_world_destroy(w);
}

int main(void) {
  test_four_sides();
  test_neutral_is_not_rest();
  test_damping();
  test_soft_limits();
  test_snapshot();
  test_refusals();
  return finish();
}
