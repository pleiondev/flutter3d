/*
 * A ragdoll for the C tests: eleven bodies on ten joints — the spine, the
 * neck, the shoulders and the hips ball joints in cones with their twist
 * limited, the elbows and the knees hinges with limits, every joint with
 * friction — and the floor and the flight of stairs it is dropped on.
 * Include after check.h.
 */
#ifndef F3D_TEST_RAGDOLL_H_
#define F3D_TEST_RAGDOLL_H_

#include <string.h>

#include "f3d_physics.h"

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

/* Pushed off the top stair, forward and a little aside, the chest
 * turned: so that it tumbles down in three dimensions, not in a plane. */
static void push_off(F3dWorld *w, const Ragdoll *r) {
  for (int i = 0; i < BODIES; i++) f3d_body_set_velocity(w, r->body[i], F3D_R(1.5), 0, F3D_R(0.3));
  f3d_body_set_angular_velocity(w, r->body[CHEST], F3D_R(0.5), 1, -2);
}

#endif
