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
#include "ragdoll.h"

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

/* Standing on the top stair and pushed off it: it tumbles down. */
static void test_stairs(void) {
  F3dWorld *w = stairs_world();
  Ragdoll r;
  make(w, &r, 0, 2, 0);
  push_off(w, &r);
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
    push_off(one, &r1);
    push_off(four, &r4);
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
