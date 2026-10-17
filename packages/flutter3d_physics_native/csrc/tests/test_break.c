/*
 * Joints that break, tested in C: a box hung from a fixed joint holds its
 * weight below the limit and lets go above it, a beam held out level
 * breaks by its torque, the event names both bodies, and a snapshot keeps
 * the limit.
 */
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "check.h"

static void run(F3dWorld *w, int steps) {
  for (int i = 0; i < steps; i++) f3d_world_step(w, F3D_R(1.0) / 60);
}

/* A post, and a box of [mass] kilograms hung under it on a fixed joint. */
static F3dWorld *hung(f3d_real mass, F3dBody *post, F3dBody *box,
                      F3dJoint *joint) {
  F3dWorld *w = f3d_world_create();
  *post = f3d_body_create(w, F3D_BODY_FIXED, 0, 2, 0, 0);
  f3d_body_set_shape(w, *post, F3D_SHAPE_BOX, F3D_R(0.1), F3D_R(0.1), F3D_R(0.1));
  *box = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, F3D_R(1.5), 0, mass);
  f3d_body_set_shape(w, *box, F3D_SHAPE_BOX, F3D_R(0.2), F3D_R(0.2), F3D_R(0.2));
  *joint = f3d_joint_create(w, F3D_JOINT_FIXED, *post, *box, 0, F3D_R(1.9), 0, 0, 1, 0);
  return w;
}

static void test_weight(void) {
  F3dBody post, box;
  F3dJoint joint;
  /* Ten kilograms weigh 98.1 N. */
  F3dWorld *w = hung(10, &post, &box, &joint);
  CHECK(f3d_joint_set_break(w, joint, -1, 0) == 0);
  CHECK(f3d_joint_set_break(w, joint, 0, nan_value()) == 0);
  CHECK(f3d_joint_set_break(w, joint, 120, 0) == 1);
  run(w, 60);
  CHECK(f3d_joint_is_valid(w, joint));
  f3d_real force[3];
  f3d_joint_get_force(w, joint, force);
  CHECK_NEAR(force[1], 98.1, 0.02);
  /* The same box with a limit under its weight: gone in the first step,
   * the box falling, and said so. */
  F3dWorld *weak = hung(10, &post, &box, &joint);
  f3d_joint_set_break(weak, joint, 80, 0);
  run(weak, 2);
  CHECK(!f3d_joint_is_valid(weak, joint));
  CHECK(f3d_world_joint_count(weak) == 0);
  F3dBody bodies[16], others[16];
  uint32_t kinds[16];
  const uint32_t n = f3d_world_read_events(weak, bodies, others, kinds, 16);
  int said = 0;
  for (uint32_t i = 0; i < n; i++) {
    if (kinds[i] == F3D_EVENT_JOINT_BROKEN) {
      said++;
      CHECK(bodies[i] == post && others[i] == box);
    }
  }
  CHECK(said == 1);
  run(weak, 30);
  f3d_real at[3];
  f3d_body_get_position(weak, box, at);
  CHECK(at[1] < F3D_R(1.0));
  f3d_world_destroy(w);
  f3d_world_destroy(weak);
}

static void test_torque(void) {
  /* A beam a metre long held out level from a wall by a fixed joint at its
   * end: its weight at half a metre is 4.905 N m on the joint. */
  for (int strong = 0; strong < 2; strong++) {
    F3dWorld *w = f3d_world_create();
    const F3dBody wall = f3d_body_create(w, F3D_BODY_FIXED, 0, 2, 0, 0);
    f3d_body_set_shape(w, wall, F3D_SHAPE_BOX, F3D_R(0.1), F3D_R(0.5), F3D_R(0.5));
    const F3dBody beam = f3d_body_create(w, F3D_BODY_DYNAMIC, F3D_R(0.6), 2, 0, 1);
    f3d_body_set_shape(w, beam, F3D_SHAPE_BOX, F3D_R(0.5), F3D_R(0.05), F3D_R(0.05));
    const F3dJoint j = f3d_joint_create(w, F3D_JOINT_FIXED, wall, beam, F3D_R(0.1), 2, 0, 0, 1, 0);
    /* Far more force than its weight: only the torque can break it. */
    f3d_joint_set_break(w, j, 1000, strong ? F3D_R(6.0) : F3D_R(4.0));
    run(w, 60);
    CHECK(f3d_joint_is_valid(w, j) == strong);
    if (strong) {
      f3d_real torque[3];
      f3d_joint_get_torque(w, j, torque);
      CHECK_NEAR(fabs((double)torque[2]), 4.905, 0.05);
    }
    f3d_world_destroy(w);
  }
}

static void test_snapshot_keeps_limit(void) {
  F3dBody post, box;
  F3dJoint joint;
  F3dWorld *w = hung(10, &post, &box, &joint);
  f3d_joint_set_break(w, joint, 120, 0);
  run(w, 10);
  const uint32_t size = f3d_world_snapshot_size(w);
  uint8_t *bytes = (uint8_t *)malloc(size);
  f3d_world_snapshot_write(w, bytes, size);
  F3dWorld *copy = f3d_world_create();
  CHECK(f3d_world_restore(copy, bytes, size) == 1);
  /* A pull of sixty newtons more in both: both let go on the same step. */
  int broke_w = -1, broke_c = -1;
  for (int i = 0; i < 20; i++) {
    f3d_body_add_force(w, box, 0, -60, 0);
    f3d_body_add_force(copy, box, 0, -60, 0);
    f3d_world_step(w, F3D_R(1.0) / 60);
    f3d_world_step(copy, F3D_R(1.0) / 60);
    if (broke_w < 0 && !f3d_joint_is_valid(w, joint)) broke_w = i;
    if (broke_c < 0 && !f3d_joint_is_valid(copy, joint)) broke_c = i;
  }
  CHECK(broke_w >= 0);
  CHECK(broke_w == broke_c);
  free(bytes);
  f3d_world_destroy(w);
  f3d_world_destroy(copy);
}

int main(void) {
  test_weight();
  test_torque();
  test_snapshot_keeps_limit();
  return finish();
}
