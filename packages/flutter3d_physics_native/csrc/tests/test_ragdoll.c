/*
 * A ragdoll, tested in C — P9, phase 13: eleven bodies on ten joints — the
 * spine, the neck, the shoulders and the hips ball joints in cones with
 * their twist limited, the elbows and the knees hinges with limits, every
 * joint with friction — falls to the floor and goes to sleep there, is
 * knocked along by a bullet and sleeps again, and tumbles down a flight of
 * stairs. Throughout, every joint holds its point within a few centimetres
 * and its limits within a few degrees as it strikes, and to a fraction of
 * a millimetre at rest; nothing is ever not finite or flung away; and it
 * steps to the same bits on one thread and four, in the deterministic
 * mode and the fast one. */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "check.h"

enum { BODIES = 11, JOINTS = 10 };

/* What every joint resists turning with, N m. */
#define FRICTION F3D_R(2.0)

/* Where each joint is on each of its bodies, and what it may do. */
typedef struct Ragdoll {
  F3dBody body[BODIES];
  F3dJoint joint[JOINTS];
  int a[JOINTS], b[JOINTS];
  f3d_real local_a[JOINTS][3], local_b[JOINTS][3];
  /* A ball joint's cone and twist, or a hinge's angle: limits. */
  int ball[JOINTS];
  f3d_real cone[JOINTS], lower[JOINTS], upper[JOINTS];
} Ragdoll;

enum { PELVIS, CHEST, HEAD, ARM_L, ARM_R, FOREARM_L, FOREARM_R, THIGH_L, THIGH_R, SHIN_L, SHIN_R };

/* Its rest pose, standing, its feet at the origin: position, shape, mass. */
static const struct Part {
  f3d_real p[3];
  F3dShapeKind kind;
  f3d_real a, b, c, mass;
} parts[BODIES] = {
    [PELVIS] = {{0, F3D_R(1.0), 0}, F3D_SHAPE_BOX, F3D_R(0.15), F3D_R(0.08), F3D_R(0.1), 10},
    [CHEST] = {{0, F3D_R(1.35), 0}, F3D_SHAPE_BOX, F3D_R(0.17), F3D_R(0.2), F3D_R(0.1), 15},
    [HEAD] = {{0, F3D_R(1.72), 0}, F3D_SHAPE_SPHERE, F3D_R(0.11), 0, 0, 4},
    [ARM_L] = {{F3D_R(-0.25), F3D_R(1.35), 0}, F3D_SHAPE_CAPSULE, F3D_R(0.05), F3D_R(0.1), 0, 2},
    [ARM_R] = {{F3D_R(0.25), F3D_R(1.35), 0}, F3D_SHAPE_CAPSULE, F3D_R(0.05), F3D_R(0.1), 0, 2},
    [FOREARM_L] = {{F3D_R(-0.25), F3D_R(1.05), 0}, F3D_SHAPE_CAPSULE, F3D_R(0.045), F3D_R(0.1), 0, F3D_R(1.5)},
    [FOREARM_R] = {{F3D_R(0.25), F3D_R(1.05), 0}, F3D_SHAPE_CAPSULE, F3D_R(0.045), F3D_R(0.1), 0, F3D_R(1.5)},
    [THIGH_L] = {{F3D_R(-0.1), F3D_R(0.725), 0}, F3D_SHAPE_CAPSULE, F3D_R(0.07), F3D_R(0.15), 0, 7},
    [THIGH_R] = {{F3D_R(0.1), F3D_R(0.725), 0}, F3D_SHAPE_CAPSULE, F3D_R(0.07), F3D_R(0.15), 0, 7},
    [SHIN_L] = {{F3D_R(-0.1), F3D_R(0.27), 0}, F3D_SHAPE_CAPSULE, F3D_R(0.055), F3D_R(0.16), 0, 4},
    [SHIN_R] = {{F3D_R(0.1), F3D_R(0.27), 0}, F3D_SHAPE_CAPSULE, F3D_R(0.055), F3D_R(0.16), 0, 4},
};

/* Its joints: the bodies, the point and axis in the rest pose, and the
 * cone and twist of a ball joint or the angles of a hinge. */
static const struct Link {
  int a, b, ball;
  f3d_real at[3], axis[3], cone, lower, upper;
} links[JOINTS] = {
    {PELVIS, CHEST, 1, {0, F3D_R(1.1), 0}, {0, 1, 0}, F3D_R(0.5), F3D_R(-0.4), F3D_R(0.4)},
    {CHEST, HEAD, 1, {0, F3D_R(1.58), 0}, {0, 1, 0}, F3D_R(0.6), F3D_R(-0.7), F3D_R(0.7)},
    {CHEST, ARM_L, 1, {F3D_R(-0.25), F3D_R(1.5), 0}, {0, -1, 0}, F3D_R(1.5), -1, 1},
    {CHEST, ARM_R, 1, {F3D_R(0.25), F3D_R(1.5), 0}, {0, -1, 0}, F3D_R(1.5), -1, 1},
    {ARM_L, FOREARM_L, 0, {F3D_R(-0.25), F3D_R(1.2), 0}, {1, 0, 0}, 0, 0, F3D_R(2.4)},
    {ARM_R, FOREARM_R, 0, {F3D_R(0.25), F3D_R(1.2), 0}, {1, 0, 0}, 0, 0, F3D_R(2.4)},
    {PELVIS, THIGH_L, 1, {F3D_R(-0.1), F3D_R(0.94), 0}, {0, -1, 0}, F3D_R(1.2), F3D_R(-0.5), F3D_R(0.5)},
    {PELVIS, THIGH_R, 1, {F3D_R(0.1), F3D_R(0.94), 0}, {0, -1, 0}, F3D_R(1.2), F3D_R(-0.5), F3D_R(0.5)},
    {THIGH_L, SHIN_L, 0, {F3D_R(-0.1), F3D_R(0.495), 0}, {1, 0, 0}, 0, F3D_R(-2.4), 0},
    {THIGH_R, SHIN_R, 0, {F3D_R(0.1), F3D_R(0.495), 0}, {1, 0, 0}, 0, F3D_R(-2.4), 0},
};

static void make(F3dWorld *w, Ragdoll *r, f3d_real ox, f3d_real oy, f3d_real oz) {
  memset(r, 0, sizeof *r);
  for (int i = 0; i < BODIES; i++) {
    const struct Part *p = &parts[i];
    r->body[i] = f3d_body_create(w, F3D_BODY_DYNAMIC, ox + p->p[0], oy + p->p[1], oz + p->p[2], p->mass);
    CHECK(f3d_body_set_shape(w, r->body[i], p->kind, p->a, p->b, p->c));
  }
  for (int k = 0; k < JOINTS; k++) {
    const struct Link *l = &links[k];
    r->a[k] = l->a;
    r->b[k] = l->b;
    r->ball[k] = l->ball;
    r->cone[k] = l->cone;
    r->lower[k] = l->lower;
    r->upper[k] = l->upper;
    for (int d = 0; d < 3; d++) {
      r->local_a[k][d] = l->at[d] - parts[l->a].p[d];
      r->local_b[k][d] = l->at[d] - parts[l->b].p[d];
    }
    r->joint[k] = f3d_joint_create(w, l->ball ? F3D_JOINT_SPHERICAL : F3D_JOINT_REVOLUTE, r->body[l->a],
                                   r->body[l->b], ox + l->at[0], oy + l->at[1], oz + l->at[2], l->axis[0],
                                   l->axis[1], l->axis[2]);
    CHECK(f3d_joint_is_valid(w, r->joint[k]));
    CHECK(f3d_joint_set_limits(w, r->joint[k], 1, l->lower, l->upper));
    /* Friction in every joint, or it never stops: a head rolls on the
     * floor and a leg about its own length with nothing to slow them. */
    if (l->ball) {
      CHECK(f3d_joint_set_cone(w, r->joint[k], 1, l->cone));
      CHECK(f3d_joint_set_friction(w, r->joint[k], 1, FRICTION));
    } else {
      CHECK(f3d_joint_set_motor(w, r->joint[k], 1, 0, FRICTION));
    }
  }
}

/* A point on a body, its own coordinates turned by its orientation. */
static void on_body(const F3dWorld *w, F3dBody b, const f3d_real *local, double *out) {
  f3d_real p[3], q[4];
  f3d_body_get_position(w, b, p);
  f3d_body_get_orientation(w, b, q);
  const double x = q[0], y = q[1], z = q[2], s = q[3];
  const double v[3] = {local[0], local[1], local[2]};
  /* t = 2 q×v; v' = v + s t + q×t. */
  const double t[3] = {2 * (y * v[2] - z * v[1]), 2 * (z * v[0] - x * v[2]), 2 * (x * v[1] - y * v[0])};
  out[0] = p[0] + v[0] + s * t[0] + (y * t[2] - z * t[1]);
  out[1] = p[1] + v[1] + s * t[1] + (z * t[0] - x * t[2]);
  out[2] = p[2] + v[2] + s * t[2] + (x * t[1] - y * t[0]);
}

/* The worst a ragdoll did this step: a joint's points apart, m; a limit
 * overstepped, radians; the fastest body, m/s; and whether anything was
 * not finite. */
typedef struct Worst {
  double gap, over, speed;
  int bad;
} Worst;

static void measure(const F3dWorld *w, const Ragdoll *r, Worst *worst) {
  for (int k = 0; k < JOINTS; k++) {
    double pa[3], pb[3];
    on_body(w, r->body[r->a[k]], r->local_a[k], pa);
    on_body(w, r->body[r->b[k]], r->local_b[k], pb);
    const double gap = sqrt((pa[0] - pb[0]) * (pa[0] - pb[0]) + (pa[1] - pb[1]) * (pa[1] - pb[1]) +
                            (pa[2] - pb[2]) * (pa[2] - pb[2]));
    if (!isfinite(gap)) worst->bad = 1;
    if (gap > worst->gap) worst->gap = gap;
    f3d_real value = 0, swing = 0;
    f3d_joint_get_value(w, r->joint[k], &value);
    double over = fmax((double)(r->lower[k] - value), (double)(value - r->upper[k]));
    if (r->ball[k]) {
      f3d_joint_get_swing(w, r->joint[k], &swing);
      over = fmax(over, (double)(swing - r->cone[k]));
    }
    if (over > worst->over) worst->over = over;
  }
  for (int i = 0; i < BODIES; i++) {
    f3d_real v[3];
    f3d_body_get_velocity(w, r->body[i], v);
    const double speed = sqrt((double)v[0] * v[0] + (double)v[1] * v[1] + (double)v[2] * v[2]);
    if (!isfinite(speed)) worst->bad = 1;
    if (speed > worst->speed) worst->speed = speed;
  }
}

static int asleep(const F3dWorld *w, const Ragdoll *r) {
  for (int i = 0; i < BODIES; i++) {
    if (!f3d_body_is_asleep(w, r->body[i])) return 0;
  }
  return 1;
}

static F3dWorld *floor_world(void) {
  F3dWorld *w = f3d_world_create();
  f3d_world_set_gravity(w, 0, F3D_R(-9.81), 0);
  const F3dBody floor = f3d_body_create(w, F3D_BODY_FIXED, 0, F3D_R(-0.5), 0, 0);
  f3d_body_set_shape(w, floor, F3D_SHAPE_BOX, 20, F3D_R(0.5), 20);
  /* Eight substeps, as a ragdoll wants: at four an arm struck on a stair
   * edge swings past its cone by a quarter of a radian for a step. */
  f3d_world_set_substeps(w, 8);
  return w;
}

/* Held, under [gap] metres and [over] radians, nothing faster than
 * [speed] and everything finite. */
static void held(const Worst *worst, double gap, double over, double speed) {
  CHECK(!worst->bad);
  CHECK(worst->gap < gap);
  CHECK(worst->over < over);
  CHECK(worst->speed < speed);
}

/* Dropped from half a metre, leaning forward: it folds onto the floor,
 * lies there, and sleeps as one; and then a bullet knocks it along. */
static void test_floor_and_bullet(void) {
  F3dWorld *w = floor_world();
  Ragdoll r;
  make(w, &r, 0, F3D_R(0.5), 0);
  f3d_body_set_velocity(w, r.body[CHEST], 0, 0, F3D_R(1.5));
  f3d_body_set_angular_velocity(w, r.body[CHEST], F3D_R(2.0), 0, F3D_R(0.5));
  Worst worst = {0};
  int slept = -1;
  for (int step = 0; step < 900 && slept < 0; step++) {
    f3d_world_step(w, F3D_R(1.0 / 60.0));
    measure(w, &r, &worst);
    if (asleep(w, &r)) slept = step;
  }
  /* A centimetre and a half and two degrees at the worst, as it lands;
   * asleep within two seconds, lying down, its joints held to a fraction
   * of a millimetre and a degree. */
  held(&worst, 0.015, 0.03, 8);
  CHECK(slept > 0 && slept < 150);
  Worst rest = {0};
  measure(w, &r, &rest);
  held(&rest, 0.002, 0.01, 1e-6);
  f3d_real p[3];
  f3d_body_get_position(w, r.body[HEAD], p);
  CHECK(p[1] < F3D_R(0.2));
  /* A bullet, thirty grams at three hundred metres a second, at the chest
   * from two metres off along x. */
  f3d_real chest[3];
  f3d_body_get_position(w, r.body[CHEST], chest);
  const F3dBody bullet = f3d_body_create(w, F3D_BODY_DYNAMIC, chest[0] - 2, chest[1], chest[2], F3D_R(0.03));
  f3d_body_set_shape(w, bullet, F3D_SHAPE_SPHERE, F3D_R(0.01), 0, 0);
  f3d_body_set_bullet(w, bullet, 1);
  f3d_body_set_velocity(w, bullet, 300, 0, 0);
  Worst hit = {0};
  double pushed = 0;
  int woke = 0, slept_again = -1;
  for (int step = 0; step < 300 && slept_again < 0; step++) {
    f3d_world_step(w, F3D_R(1.0 / 60.0));
    measure(w, &r, &hit);
    f3d_real v[3];
    f3d_body_get_velocity(w, r.body[CHEST], v);
    if (v[0] > pushed) pushed = v[0];
    if (!f3d_body_is_asleep(w, r.body[CHEST])) woke = 1;
    if (step > 30 && asleep(w, &r)) slept_again = step;
  }
  /* It woke, took a good part of the bullet's 9 N s — the chest alone
   * would go at 0.6 m/s — kept the bullet out, held, and slept again. */
  CHECK(woke);
  CHECK(pushed > 0.2 && pushed < 0.7);
  f3d_real bp[3];
  f3d_body_get_position(w, bullet, bp);
  CHECK(bp[0] < chest[0]);
  held(&hit, 0.01, 0.02, 2);
  CHECK(slept_again > 0);
  f3d_world_destroy(w);
}

/* A flight of eight stairs, each a quarter of a metre down and forty
 * centimetres deep, going down along x. */
static F3dWorld *stairs_world(void) {
  F3dWorld *w = floor_world();
  for (int k = 0; k < 8; k++) {
    const f3d_real top = F3D_R(0.25) * (f3d_real)(8 - k);
    const F3dBody stair = f3d_body_create(w, F3D_BODY_FIXED, F3D_R(0.4) * (f3d_real)k, top * F3D_R(0.5), 0, 0);
    f3d_body_set_shape(w, stair, F3D_SHAPE_BOX, F3D_R(0.2), top * F3D_R(0.5), 2);
  }
  return w;
}

/* Standing on the top stair and pushed off it: it tumbles down. */
static void test_stairs(void) {
  F3dWorld *w = stairs_world();
  Ragdoll r;
  make(w, &r, 0, 2, 0);
  for (int i = 0; i < BODIES; i++) f3d_body_set_velocity(w, r.body[i], F3D_R(1.5), 0, F3D_R(0.3));
  f3d_body_set_angular_velocity(w, r.body[CHEST], F3D_R(0.5), 1, -2);
  Worst worst = {0};
  int slept = -1;
  for (int step = 0; step < 900 && slept < 0; step++) {
    f3d_world_step(w, F3D_R(1.0 / 60.0));
    measure(w, &r, &worst);
    if (asleep(w, &r)) slept = step;
  }
  /* At the foot of the stairs, two metres down and past the last, asleep
   * within six seconds; two and a half centimetres and five degrees at
   * the worst on the way. */
  f3d_real p[3];
  f3d_body_get_position(w, r.body[PELVIS], p);
  CHECK(p[0] > 3 && p[1] < F3D_R(0.5));
  CHECK(slept > 0 && slept < 360);
  held(&worst, 0.025, 0.08, 15);
  f3d_world_destroy(w);
}

/* The stairs on one thread and on four, in each mode: the same bits every
 * step. */
static void test_same_bits(void) {
  for (int fast = 0; fast < 2; fast++) {
    F3dWorld *one = stairs_world(), *four = stairs_world();
    Ragdoll r1, r4;
    make(one, &r1, 0, 2, 0);
    make(four, &r4, 0, 2, 0);
    CHECK(f3d_world_set_threads(four, 4));
    f3d_world_set_fast(one, fast);
    f3d_world_set_fast(four, fast);
    for (int i = 0; i < BODIES; i++) {
      f3d_body_set_velocity(one, r1.body[i], F3D_R(1.5), 0, F3D_R(0.3));
      f3d_body_set_velocity(four, r4.body[i], F3D_R(1.5), 0, F3D_R(0.3));
    }
    f3d_body_set_angular_velocity(one, r1.body[CHEST], F3D_R(0.5), 1, -2);
    f3d_body_set_angular_velocity(four, r4.body[CHEST], F3D_R(0.5), 1, -2);
    const uint32_t size = 1u << 20;
    uint8_t *a = (uint8_t *)malloc(size), *b = (uint8_t *)malloc(size);
    int differing = 0;
    Worst worst = {0};
    for (int step = 0; step < 300; step++) {
      f3d_world_step(one, F3D_R(1.0 / 60.0));
      f3d_world_step(four, F3D_R(1.0 / 60.0));
      measure(one, &r1, &worst);
      const uint32_t na = f3d_world_snapshot_write(one, a, size);
      const uint32_t nb = f3d_world_snapshot_write(four, b, size);
      CHECK(na > 0);
      differing += na != nb || memcmp(a, b, na) != 0;
    }
    CHECK(differing == 0);
    held(&worst, 0.025, 0.08, 15);
    free(a);
    free(b);
    f3d_world_destroy(one);
    f3d_world_destroy(four);
  }
}

int main(void) {
  test_floor_and_bullet();
  test_stairs();
  test_same_bits();
  return finish();
}
