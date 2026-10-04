/*
 * The fast mode, tested in C — P9, phase 11: a world of every shape steps
 * to the same snapshot on one thread, two, three and eight, every step —
 * other bits than the deterministic mode's, its contacts solved in colour
 * order — and still rests a crate where it should, holds a stack of ten
 * up until it sleeps, keeps the mode through a snapshot, rests a hundred
 * balls on one plank with more contacts than colours, bounces, and holds
 * a bob on a hinge.
 */
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "check.h"
#include "scene.h"

static void test_same_bits(void) {
  F3dWorld *one = scene();
  CHECK(!f3d_world_fast(one));
  CHECK(f3d_world_set_fast(one, 1) && f3d_world_fast(one));
  const uint32_t counts[3] = {2, 3, 8};
  F3dWorld *many[3];
  for (int k = 0; k < 3; k++) {
    many[k] = scene();
    f3d_world_set_fast(many[k], 1);
    CHECK(f3d_world_set_threads(many[k], counts[k]));
  }
  F3dWorld *careful = scene();
  const uint32_t size = 4u << 20;
  uint8_t *a = (uint8_t *)malloc(size), *b = (uint8_t *)malloc(size);
  int differing = 0, unlike = 0;
  for (int step = 0; step < 240; step++) {
    f3d_world_step(one, F3D_R(1.0 / 60.0));
    f3d_world_step(careful, F3D_R(1.0 / 60.0));
    const uint32_t na = f3d_world_snapshot_write(one, a, size);
    CHECK(na > 0);
    for (int k = 0; k < 3; k++) {
      f3d_world_step(many[k], F3D_R(1.0 / 60.0));
      const uint32_t nb = f3d_world_snapshot_write(many[k], b, size);
      differing += na != nb || memcmp(a, b, na) != 0;
    }
    static f3d_real p[400 * F3D_TRANSFORM_FLOATS], q[400 * F3D_TRANSFORM_FLOATS];
    const uint32_t n = f3d_world_read_transforms(one, p, NULL, 400);
    CHECK(n == f3d_world_read_transforms(careful, q, NULL, 400));
    unlike += memcmp(p, q, (size_t)n * F3D_TRANSFORM_FLOATS * sizeof(f3d_real)) != 0;
  }
  CHECK(differing == 0);
  /* Solved in another order, the deterministic mode lands elsewhere. */
  CHECK(unlike > 0);
  free(a);
  free(b);
  for (int k = 0; k < 3; k++) f3d_world_destroy(many[k]);
  f3d_world_destroy(one);
  f3d_world_destroy(careful);
}

static void test_still_physics(void) {
  /* A crate on a floor, and a stack of ten beside it, on four threads. */
  F3dWorld *w = f3d_world_create();
  f3d_world_set_gravity(w, 0, F3D_R(-9.81), 0);
  CHECK(f3d_world_set_fast(w, 1) && f3d_world_set_threads(w, 4));
  const F3dBody floor = f3d_body_create(w, F3D_BODY_FIXED, 0, F3D_R(-0.5), 0, 0);
  f3d_body_set_shape(w, floor, F3D_SHAPE_BOX, 20, F3D_R(0.5), 20);
  const F3dBody crate = f3d_body_create(w, F3D_BODY_DYNAMIC, -3, 1, 0, 1);
  f3d_body_set_shape(w, crate, F3D_SHAPE_BOX, F3D_R(0.5), F3D_R(0.5), F3D_R(0.5));
  F3dBody stack[10];
  for (int i = 0; i < 10; i++) {
    stack[i] = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, F3D_R(0.25) + (f3d_real)i * F3D_R(0.5), 0, 1);
    f3d_body_set_shape(w, stack[i], F3D_SHAPE_BOX, F3D_R(0.25), F3D_R(0.25), F3D_R(0.25));
  }
  for (int i = 0; i < 600; i++) f3d_world_step(w, F3D_R(1.0 / 60.0));
  f3d_real p[3];
  f3d_body_get_position(w, crate, p);
  CHECK_NEAR(p[1], 0.5, 0.01);
  CHECK_NEAR(p[0], -3, 1e-3);
  f3d_body_get_position(w, stack[9], p);
  /* The top of ten half-metre boxes, upright: 4.75 m less the give of ten
   * joints, and walked a few centimetres aside as it settled — 5.4 here,
   * 1.4 in the deterministic mode, which solves each step bottom up. A
   * stack that fell would be metres off. */
  CHECK(p[1] > F3D_R(4.65) && p[1] < F3D_R(4.76));
  CHECK(p[0] * p[0] + p[2] * p[2] < F3D_R(0.01));
  CHECK(f3d_body_is_asleep(w, stack[9]));
  /* The mode goes with a snapshot, and the threads do not. */
  const uint32_t size = f3d_world_snapshot_size(w);
  uint8_t *buffer = (uint8_t *)malloc(size);
  CHECK(f3d_world_snapshot_write(w, buffer, size) == size);
  F3dWorld *restored = f3d_world_create();
  CHECK(f3d_world_restore(restored, buffer, size));
  CHECK(f3d_world_fast(restored));
  CHECK(f3d_world_threads(restored) == 1);
  CHECK(f3d_world_set_fast(restored, 0) && !f3d_world_fast(restored));
  free(buffer);
  f3d_world_destroy(restored);
  f3d_world_destroy(w);
}

static F3dWorld *plank(uint32_t threads) {
  /* A plank four metres square, dynamic, on the floor, under a hundred
   * balls: more contacts than colours, so some go to the overflow. */
  F3dWorld *w = f3d_world_create();
  f3d_world_set_gravity(w, 0, F3D_R(-9.81), 0);
  f3d_world_set_fast(w, 1);
  f3d_world_set_threads(w, threads);
  const F3dBody floor = f3d_body_create(w, F3D_BODY_FIXED, 0, F3D_R(-0.5), 0, 0);
  f3d_body_set_shape(w, floor, F3D_SHAPE_BOX, 20, F3D_R(0.5), 20);
  const F3dBody board = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, F3D_R(0.1), 0, 50);
  f3d_body_set_shape(w, board, F3D_SHAPE_BOX, 2, F3D_R(0.1), 2);
  for (int i = 0; i < 100; i++) {
    const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, (f3d_real)(i % 10) * F3D_R(0.4) - F3D_R(1.8),
                                      F3D_R(0.36), (f3d_real)(i / 10) * F3D_R(0.4) - F3D_R(1.8), F3D_R(0.2));
    f3d_body_set_shape(w, b, F3D_SHAPE_SPHERE, F3D_R(0.15), 0, 0);
  }
  return w;
}

static void test_overflow(void) {
  F3dWorld *one = plank(1), *four = plank(4);
  const uint32_t size = 1u << 20;
  uint8_t *a = (uint8_t *)malloc(size), *b = (uint8_t *)malloc(size);
  int differing = 0;
  for (int step = 0; step < 120; step++) {
    f3d_world_step(one, F3D_R(1.0 / 60.0));
    f3d_world_step(four, F3D_R(1.0 / 60.0));
    const uint32_t na = f3d_world_snapshot_write(one, a, size);
    differing += na == 0 || na != f3d_world_snapshot_write(four, b, size) || memcmp(a, b, na) != 0;
  }
  CHECK(differing == 0);
  /* The balls rest on the plank, the plank on the floor. */
  static f3d_real t[110 * F3D_TRANSFORM_FLOATS];
  const uint32_t n = f3d_world_read_transforms(one, t, NULL, 110);
  CHECK(n == 102);
  CHECK_NEAR(t[1 * F3D_TRANSFORM_FLOATS + 1], 0.1, 0.005);
  for (uint32_t i = 2; i < n; i++) CHECK_NEAR(t[i * F3D_TRANSFORM_FLOATS + 1], 0.35, 0.005);
  /* A point under each ball: the plank in a hundred contacts. */
  CHECK(f3d_world_contact_count(one) >= 100);
  free(a);
  free(b);
  f3d_world_destroy(one);
  f3d_world_destroy(four);
}

static f3d_real bounce(int fast) {
  F3dWorld *w = f3d_world_create();
  f3d_world_set_gravity(w, 0, F3D_R(-9.81), 0);
  f3d_world_set_fast(w, fast);
  const F3dBody floor = f3d_body_create(w, F3D_BODY_FIXED, 0, F3D_R(-0.5), 0, 0);
  f3d_body_set_shape(w, floor, F3D_SHAPE_BOX, 20, F3D_R(0.5), 20);
  const F3dBody ball = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, F3D_R(2.25), 0, 1);
  f3d_body_set_shape(w, ball, F3D_SHAPE_SPHERE, F3D_R(0.25), 0, 0);
  f3d_body_set_restitution(w, ball, F3D_R(0.8));
  f3d_real up = 0, v[3];
  for (int i = 0; i < 90; i++) {
    f3d_world_step(w, F3D_R(1.0 / 60.0));
    f3d_body_get_velocity(w, ball, v);
    if (v[1] > up) up = v[1];
  }
  f3d_world_destroy(w);
  return up;
}

static void test_bounce(void) {
  /* Dropped from two metres at restitution 0.8, through the air: one
   * contact is one colour, solved as the deterministic mode solves it, so
   * it comes back up at the same speed to the bit — some 0.74 of what it
   * struck at, the air having taken the rest. */
  const f3d_real fast = bounce(1);
  CHECK(fast == bounce(0));
  CHECK(fast > F3D_R(4.5) && fast < F3D_R(4.8));
}

static void test_hinge(void) {
  /* A bob on a hinge a metre below its pivot, swung, on two threads: the
   * joints are solved on one thread between the colours, and hold. */
  F3dWorld *w = f3d_world_create();
  f3d_world_set_gravity(w, 0, F3D_R(-9.81), 0);
  f3d_world_set_fast(w, 1);
  f3d_world_set_threads(w, 2);
  const F3dBody pivot = f3d_body_create(w, F3D_BODY_FIXED, 0, 3, 0, 0);
  const F3dBody bob = f3d_body_create(w, F3D_BODY_DYNAMIC, 1, 3, 0, 1);
  f3d_body_set_shape(w, bob, F3D_SHAPE_SPHERE, F3D_R(0.05), 0, 0);
  CHECK(f3d_joint_create(w, F3D_JOINT_REVOLUTE, pivot, bob, 0, 3, 0, 0, 0, 1) != 0);
  f3d_real lowest = 3, worst = 0, p[3];
  for (int i = 0; i < 120; i++) {
    f3d_world_step(w, F3D_R(1.0 / 60.0));
    f3d_body_get_position(w, bob, p);
    const f3d_real d = (f3d_real)sqrt((double)p[0] * p[0] + (p[1] - 3) * (p[1] - 3) + p[2] * p[2]);
    worst = d - 1 > worst ? d - 1 : (1 - d > worst ? 1 - d : worst);
    lowest = p[1] < lowest ? p[1] : lowest;
  }
  CHECK(worst < F3D_R(0.01));
  CHECK_NEAR(lowest, 2.0, 0.02);
  f3d_world_destroy(w);
}

int main(void) {
  test_same_bits();
  test_still_physics();
  test_overflow();
  test_bounce();
  test_hinge();
  return finish();
}
