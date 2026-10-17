/*
 * The limits of an anatomy, tested in C: a spherical joint's swing held
 * further ahead than behind and further to one side than the other,
 * measured from a neutral direction that need not be where the limb rests;
 * viscous damping that takes a swing down at the rate a damped pendulum's
 * law gives; soft limits that give under a load by the load over their
 * stiffness, or stiffen past the limit as (k0 / b)(e^(bδ) − 1) says, with
 * a stiffness of their own at each limit; all of it through a snapshot;
 * and what each refuses.
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

/* A limb of [mass] kilograms along +x from a hinge about z, between −0.2
 * and 0.2 rad, its limits soft at [k0] and stiffening at [growth] past
 * them, [lower] and [upper] at each limit where not nought, under gravity
 * [g] along y: where it hangs after four seconds. */
static double held(double mass, f3d_real k0, f3d_real growth, f3d_real lower,
                   f3d_real upper, f3d_real g) {
  F3dWorld *w = world();
  f3d_world_set_gravity(w, 0, g, 0);
  const F3dBody pivot = f3d_body_create(w, F3D_BODY_FIXED, 0, 2, 0, 0);
  const F3dBody limb =
      f3d_body_create(w, F3D_BODY_DYNAMIC, F3D_R(0.5), 2, 0, (f3d_real)mass);
  f3d_body_set_shape(w, limb, F3D_SHAPE_BOX, F3D_R(0.5), F3D_R(0.05), F3D_R(0.05));
  const F3dJoint j = f3d_joint_create(w, F3D_JOINT_REVOLUTE, pivot, limb, 0, 2, 0, 0, 0, 1);
  CHECK(f3d_joint_set_limits(w, j, 1, F3D_R(-0.2), F3D_R(0.2)));
  CHECK(f3d_joint_set_damping(w, j, 1, F3D_R(2.0 * mass)));
  CHECK(f3d_joint_set_limit_softness(w, j, 1, k0, 1));
  CHECK(f3d_joint_set_limit_stiffness(w, j, 1, growth, lower, upper, 0, 0, 0, 0));
  run(w, 240);
  f3d_real angle;
  f3d_joint_get_value(w, j, &angle);
  f3d_world_destroy(w);
  return angle;
}

/* How far past −0.2 the limb above hangs, by the law: its weight's moment,
 * m g (l/2) cos θ, carried by (k0 / b)(e^(bδ) − 1), or k0 δ with no b. */
static double overshoot_by_law(double mass, double k0, double b) {
  double delta = 0;
  for (int i = 0; i < 100; i++) {
    const double load = mass * STANDARD_G * 0.5 * cos(-0.2 - delta);
    delta = b > 0 ? log(1 + b * load / k0) / b : load / k0;
  }
  return delta;
}

static void test_exponential_limits(void) {
  /* Past its limit the tissue holds back (k0 / b)(e^(bδ) − 1): the limb
   * hangs where that carries its weight, for loads from a few newton
   * metres to a few hundred. k0 = 150 N m/rad, the lumbar spine's in
   * flexion at the end of its range, b = 8.6 /rad, the knee's capsule
   * past full extension. Mutation: hold it back by k0 δ — the heavy limb
   * hangs straight down, past −1.5 rad. */
  const double k0 = 150, b = 8.6;
  const double masses[] = {2, 20, 60, 90};
  for (int i = 0; i < 4; i++) {
    const double want = -0.2 - overshoot_by_law(masses[i], k0, b);
    CHECK_NEAR(held(masses[i], (f3d_real)k0, (f3d_real)b, 0, 0,
                    -STANDARD_G),
               want, 0.01);
  }
  /* Stiffening as k0 e^(bδ): about 3000 N m/rad 0.35 rad past the limit,
   * twenty times what it was there. Read off two loads either side of
   * that, as the load between over the overshoot between. */
  const double m1 = 72, m2 = 88;
  const double d1 = -0.2 - held(m1, (f3d_real)k0, (f3d_real)b, 0, 0, -STANDARD_G);
  const double d2 = -0.2 - held(m2, (f3d_real)k0, (f3d_real)b, 0, 0, -STANDARD_G);
  const double l1 = m1 * STANDARD_G * 0.5 * cos(-0.2 - d1);
  const double l2 = m2 * STANDARD_G * 0.5 * cos(-0.2 - d2);
  const double stiffness = (l2 - l1) / (d2 - d1);
  CHECK_NEAR((d1 + d2) / 2, 0.35, 0.02);
  CHECK_NEAR(stiffness / (k0 * exp(b * (d1 + d2) / 2)), 1, 0.08);
  CHECK_NEAR(stiffness / 3000, 1, 0.13);
  /* With no growth it is the linear spring it was. */
  CHECK_NEAR(held(2, 100, 0, 0, 0, -STANDARD_G),
             -0.2 - overshoot_by_law(2, 100, 0), 0.01);
}

static void test_stiffness_at_each_limit(void) {
  /* A hinge's two limits each with their own stiffness: hung down, the
   * limb sags past the lower by its weight over the lower's; pulled up,
   * past the upper by the upper's. Mutation: swap the two — each sags by
   * a tenth or ten times as far. */
  const double down = held(1, 1000, 0, 40, 400, -STANDARD_G);
  const double up = held(1, 1000, 0, 40, 400, STANDARD_G);
  CHECK_NEAR(down, -0.2 - overshoot_by_law(1, 40, 0), 0.01);
  CHECK_NEAR(up, 0.2 + overshoot_by_law(1, 400, 0), 0.005);
  /* Nought at a limit takes the joint's own stiffness. */
  CHECK_NEAR(held(1, 40, 0, 0, 400, -STANDARD_G), down, 1e-6);
}

/* The limb on its spherical joint, neutral down and ahead +z, limited to
 * 0.6 rad every way, soft at [ahead] and [behind] past the limit ahead and
 * the one behind, pulled ahead by gravity along +z: how far past 0.6 it
 * swings. */
static double swung_past(f3d_real ahead, f3d_real behind) {
  F3dWorld *w = world();
  f3d_world_set_gravity(w, 0, 0, F3D_R(9.81));
  F3dBody limb;
  const F3dJoint j = hung(w, &limb);
  CHECK(f3d_joint_set_swing(w, j, 1, 0, -1, 0, 0, 0, 1, F3D_R(0.6), F3D_R(0.6),
                            F3D_R(0.6), F3D_R(0.6)));
  CHECK(f3d_joint_set_damping(w, j, 1, 1));
  CHECK(f3d_joint_set_limit_softness(w, j, 1, 1000, 1));
  CHECK(f3d_joint_set_limit_stiffness(w, j, 1, 0, 0, 0, ahead, behind, 0, 0));
  run(w, 240);
  double d[3];
  pointing(w, limb, d);
  f3d_world_destroy(w);
  return acos(-d[1]) - 0.6;
}

static void test_swing_stiffness_at_each_side(void) {
  /* Swung ahead, the limit ahead's stiffness holds it: a soft one lets it
   * swing on until the spring carries its weight's moment, m g (l/2)
   * cos(0.6 + δ). Mutation: take the limit behind's stiffness ahead — it
   * stops within a hundredth of a radian. */
  const double k = 20;
  double delta = 0;
  for (int i = 0; i < 100; i++) {
    delta = STANDARD_G * 0.5 * cos(0.6 + delta) / k;
  }
  CHECK_NEAR(swung_past((f3d_real)k, 4000), delta, 0.02);
  CHECK(swung_past(4000, (f3d_real)k) < 0.01);
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
  CHECK(f3d_joint_set_limit_stiffness(w, j, 1, F3D_R(8.6), 20, 30, 40, 60, 25,
                                      35));
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
  /* The stiffening, a turning joint's: growth from nought to 100 a
   * radian, each limit's stiffness nought or more. */
  CHECK(!f3d_joint_set_limit_stiffness(w, slider, 1, 1, 0, 0, 0, 0, 0, 0));
  CHECK(!f3d_joint_set_limit_stiffness(w, hinge, 1, -1, 0, 0, 0, 0, 0, 0));
  CHECK(!f3d_joint_set_limit_stiffness(w, hinge, 1, 101, 0, 0, 0, 0, 0, 0));
  CHECK(!f3d_joint_set_limit_stiffness(w, hinge, 1, nan_value(), 0, 0, 0, 0, 0, 0));
  CHECK(!f3d_joint_set_limit_stiffness(w, j, 1, 1, 0, 0, 0, -1, 0, 0));
  CHECK(!f3d_joint_set_limit_stiffness(w, j, 1, 1, 0, 0, 0, 0, 0, nan_value()));
  CHECK(f3d_joint_set_limit_stiffness(w, j, 1, 100, 0, 0, 0, 0, 0, 0));
  CHECK(f3d_joint_set_limit_stiffness(w, hinge, 0, -1, -1, -1, -1, -1, -1, -1));
  f3d_world_destroy(w);
}

int main(void) {
  test_four_sides();
  test_neutral_is_not_rest();
  test_damping();
  test_soft_limits();
  test_exponential_limits();
  test_stiffness_at_each_limit();
  test_swing_stiffness_at_each_side();
  test_snapshot();
  test_refusals();
  return finish();
}
