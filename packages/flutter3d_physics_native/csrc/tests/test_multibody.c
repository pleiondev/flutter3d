/*
 * Multibodies, tested in C: what a multibody refuses, a pendulum's period
 * against 2π √(L / g), a chain of twenty links with a weight a hundred
 * times theirs on its end whose joints do not come apart, a floating pair
 * on a hinge landing on a floor, a hinge held in its limits, a motor
 * reaching its speed, links that do not collide with their parents, and a
 * multibody in a snapshot.
 */
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "check.h"

static void run(F3dWorld *w, int steps) {
  for (int i = 0; i < steps; i++) f3d_world_step(w, F3D_R(1.0) / 60);
}

static F3dWorld *still_air(void) {
  F3dWorld *w = f3d_world_create();
  f3d_world_set_air(w, F3D_R(293.15), F3D_R(1e-30));
  f3d_world_set_sleep(w, 0, 0);
  return w;
}

static F3dBody post(F3dWorld *w, f3d_real x, f3d_real y) {
  const F3dBody b = f3d_body_create(w, F3D_BODY_FIXED, x, y, 0, 0);
  f3d_body_set_shape(w, b, F3D_SHAPE_BOX, F3D_R(0.05), F3D_R(0.05), F3D_R(0.05));
  return b;
}

static F3dBody ball(F3dWorld *w, f3d_real x, f3d_real y, f3d_real mass,
                    f3d_real radius) {
  const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, x, y, 0, mass);
  f3d_body_set_shape(w, b, F3D_SHAPE_SPHERE, radius, 0, 0);
  return b;
}

static void test_refusals(void) {
  F3dWorld *w = still_air();
  const F3dBody root = post(w, 0, 3);
  const F3dMultibody m = f3d_multibody_create(w, root);
  CHECK(m == 1);
  CHECK(f3d_multibody_create(w, root) == 0);
  const F3dBody fixed = post(w, 1, 3);
  CHECK(f3d_multibody_add_link(w, m, 0, fixed, F3D_JOINT_REVOLUTE, 0, 3, 0, 0, 0, 1) == -1);
  const F3dBody b = ball(w, 1, 3, 1, F3D_R(0.1));
  CHECK(f3d_multibody_add_link(w, m, 1, b, F3D_JOINT_REVOLUTE, 0, 3, 0, 0, 0, 1) == -1);
  CHECK(f3d_multibody_add_link(w, m, 0, b, F3D_JOINT_DISTANCE, 0, 3, 0, 0, 0, 1) == -1);
  CHECK(f3d_multibody_add_link(w, m, 0, b, F3D_JOINT_REVOLUTE, 0, 3, 0, 0, 0, 0) == -1);
  CHECK(f3d_multibody_add_link(w, m, 0, b, F3D_JOINT_REVOLUTE, nan_value(), 3, 0, 0, 0, 1) == -1);
  CHECK(f3d_multibody_add_link(w, m, 0, b, F3D_JOINT_REVOLUTE, 0, 3, 0, 0, 0, 1) == 1);
  CHECK(f3d_multibody_add_link(w, m, 0, b, F3D_JOINT_REVOLUTE, 0, 3, 0, 0, 0, 1) == -1);
  CHECK(f3d_multibody_link_count(w, m) == 2);
  CHECK(f3d_multibody_dof_count(w, m) == 1);
  CHECK(f3d_multibody_set_limits(w, m, 1, 1, 1, -1) == 0);
  CHECK(f3d_multibody_set_limits(w, m, 0, 1, -1, 1) == 0);
  CHECK(f3d_multibody_set_motor(w, m, 1, 1, 0, -1) == 0);
  /* A link taken out of the world takes the multibody with it. */
  f3d_body_destroy(w, b);
  run(w, 1);
  CHECK(!f3d_multibody_is_valid(w, m));
  f3d_world_destroy(w);
}

static void test_pendulum(void) {
  /* A kilogram on a metre, let go five hundredths of a radian out: it
   * swings back through the bottom every π √(L / g). */
  F3dWorld *w = still_air();
  const F3dBody pivot = post(w, 0, 3);
  const double start = 0.05;
  const F3dBody bob = ball(w, (f3d_real)sin(start), (f3d_real)(3 - cos(start)), 1, F3D_R(0.01));
  const F3dMultibody m = f3d_multibody_create(w, pivot);
  CHECK(f3d_multibody_add_link(w, m, 0, bob, F3D_JOINT_REVOLUTE, 0, 3, 0, 0, 0, 1) == 1);
  f3d_real joint[8], last = 0;
  double crossings[3];
  int found = 0;
  for (int i = 1; i <= 600 && found < 3; i++) {
    f3d_world_step(w, F3D_R(1.0) / 120);
    f3d_real at[3];
    f3d_body_get_position(w, bob, at);
    if (i > 1 && ((last < 0) != (at[0] < 0))) {
      crossings[found++] = (i - 1 + last / (last - at[0])) / 120.0;
    }
    last = at[0];
  }
  CHECK(found == 3);
  const double half = M_PI * sqrt(1.0 / 9.81);
  CHECK_NEAR(crossings[2] - crossings[0], 2 * half, 0.01);
  /* It reads as the angle it swings through. */
  f3d_multibody_read_joint(w, m, 1, joint);
  CHECK(fabs((double)joint[0]) <= start * 1.02);
  f3d_world_destroy(w);
}

/* How far apart the two sides of link [k]'s joint are, as anchors. */
static double gap(F3dWorld *w, F3dBody parent, F3dBody child, F3dVec3 anchor_p,
                  F3dVec3 anchor_c) {
  f3d_real pp[3], pq[4], cp[3], cq[4];
  f3d_body_get_position(w, parent, pp);
  f3d_body_get_orientation(w, parent, pq);
  f3d_body_get_position(w, child, cp);
  f3d_body_get_orientation(w, child, cq);
  const F3dQuat qp = {pq[0], pq[1], pq[2], pq[3]}, qc = {cq[0], cq[1], cq[2], cq[3]};
  const F3dMat3 mp = f3d_mat_of(qp), mc = f3d_mat_of(qc);
  F3dVec3 a = f3d_v3(pp[0], pp[1], pp[2]), b = f3d_v3(cp[0], cp[1], cp[2]);
  a = f3d_add(a, f3d_add(f3d_add(f3d_scale(mp.c[0], anchor_p.x), f3d_scale(mp.c[1], anchor_p.y)),
                         f3d_scale(mp.c[2], anchor_p.z)));
  b = f3d_add(b, f3d_add(f3d_add(f3d_scale(mc.c[0], anchor_c.x), f3d_scale(mc.c[1], anchor_c.y)),
                         f3d_scale(mc.c[2], anchor_c.z)));
  const F3dVec3 d = f3d_sub(a, b);
  return sqrt((double)f3d_dot(d, d));
}

static void test_heavy_chain(void) {
  /* Twenty links of a tenth of a kilogram, laid out sideways, and a ten
   * kilogram weight on the end: let go, it swings down hard. As separate
   * joints the light links stretch under the weight; here there is
   * nothing to stretch. */
  F3dWorld *w = still_air();
  const F3dBody top = post(w, 0, 10);
  const F3dMultibody m = f3d_multibody_create(w, top);
  F3dBody links[21];
  links[0] = top;
  for (int k = 1; k <= 20; k++) {
    const int heavy = k == 20;
    links[k] = f3d_body_create(w, F3D_BODY_DYNAMIC, (f3d_real)k * F3D_R(0.2) - F3D_R(0.1), 10, 0,
                               heavy ? 10 : F3D_R(0.1));
    f3d_body_set_shape(w, links[k], F3D_SHAPE_BOX, F3D_R(0.1), F3D_R(0.02), F3D_R(0.02));
    CHECK(f3d_multibody_add_link(w, m, (uint32_t)(k - 1), links[k], F3D_JOINT_REVOLUTE,
                                 (f3d_real)(k - 1) * F3D_R(0.2), 10, 0, 0, 0, 1) == k);
  }
  CHECK(f3d_multibody_dof_count(w, m) == 20);
  /* Laid out straight, every link's box meets its neighbours' at the
   * joints, and none of them is a contact. */
  run(w, 1);
  CHECK(f3d_world_contact_count(w) == 0);
  double worst = 0;
  for (int i = 0; i < 180; i++) {
    run(w, 1);
    for (int k = 2; k <= 20; k++) {
      const double g = gap(w, links[k - 1], links[k], f3d_v3(F3D_R(0.1), 0, 0),
                           f3d_v3(F3D_R(-0.1), 0, 0));
      if (g > worst) worst = g;
    }
  }
  CHECK(worst < 1e-4);
  /* And it has swung: the weight is below the post, not beside it. */
  f3d_real at[3];
  f3d_body_get_position(w, links[20], at);
  CHECK(at[1] < 8);
  f3d_world_destroy(w);
}

static void test_floating_lands(void) {
  /* Two boxes on a hinge, floating, dropped onto a floor: they land, come
   * to rest on it, and their hinge holds. */
  F3dWorld *w = still_air();
  const F3dBody floor = f3d_body_create(w, F3D_BODY_FIXED, 0, F3D_R(-0.5), 0, 0);
  f3d_body_set_shape(w, floor, F3D_SHAPE_BOX, 10, F3D_R(0.5), 10);
  const F3dBody a = f3d_body_create(w, F3D_BODY_DYNAMIC, F3D_R(-0.3), 2, 0, 1);
  const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, F3D_R(0.3), 2, 0, 1);
  f3d_body_set_shape(w, a, F3D_SHAPE_BOX, F3D_R(0.3), F3D_R(0.1), F3D_R(0.2));
  f3d_body_set_shape(w, b, F3D_SHAPE_BOX, F3D_R(0.3), F3D_R(0.1), F3D_R(0.2));
  const F3dMultibody m = f3d_multibody_create(w, a);
  CHECK(f3d_multibody_dof_count(w, m) == 6);
  CHECK(f3d_multibody_add_link(w, m, 0, b, F3D_JOINT_REVOLUTE, 0, 2, 0, 0, 0, 1) == 1);
  run(w, 240);
  f3d_real pa[3], pb[3], va[3];
  f3d_body_get_position(w, a, pa);
  f3d_body_get_position(w, b, pb);
  f3d_body_get_velocity(w, a, va);
  CHECK_NEAR(pa[1], 0.1, 0.01);
  CHECK_NEAR(pb[1], 0.1, 0.01);
  CHECK(fabs((double)va[1]) < 0.01);
  CHECK(gap(w, a, b, f3d_v3(F3D_R(0.3), 0, 0), f3d_v3(F3D_R(-0.3), 0, 0)) < 1e-4);
  f3d_world_destroy(w);
}

static void test_limits_and_motor(void) {
  /* A rod on a hinge, let go level, held within a third of a radian. */
  F3dWorld *w = still_air();
  const F3dBody pivot = post(w, 0, 3);
  const F3dBody rod = ball(w, 1, 3, 1, F3D_R(0.05));
  const F3dMultibody m = f3d_multibody_create(w, pivot);
  f3d_multibody_add_link(w, m, 0, rod, F3D_JOINT_REVOLUTE, 0, 3, 0, 0, 0, 1);
  CHECK(f3d_multibody_set_limits(w, m, 1, 1, F3D_R(-0.3), F3D_R(0.3)) == 1);
  f3d_real joint[8];
  double lowest = 0;
  for (int i = 0; i < 120; i++) {
    run(w, 1);
    f3d_multibody_read_joint(w, m, 1, joint);
    if (joint[0] < lowest) lowest = joint[0];
  }
  CHECK(lowest >= -0.3 - 1e-4);
  CHECK(lowest < -0.29);
  /* A wheel on an upright axle, which gravity does not turn: its motor
   * brings it to two radians a second. */
  const F3dBody axle = post(w, 5, 3);
  const F3dBody wheel = f3d_body_create(w, F3D_BODY_DYNAMIC, 5, 3, 0, 2);
  f3d_body_set_shape(w, wheel, F3D_SHAPE_CYLINDER, F3D_R(0.5), F3D_R(0.05), 0);
  const F3dMultibody spun = f3d_multibody_create(w, axle);
  f3d_multibody_add_link(w, spun, 0, wheel, F3D_JOINT_REVOLUTE, 5, 3, 0, 0, 1, 0);
  CHECK(f3d_multibody_set_motor(w, spun, 1, 1, 2, 50) == 1);
  run(w, 60);
  f3d_multibody_read_joint(w, spun, 1, joint);
  CHECK_NEAR(joint[1], 2, 1e-3);
  f3d_real spin[3];
  f3d_body_get_angular_velocity(w, wheel, spin);
  CHECK_NEAR(spin[1], 2, 1e-3);
  /* A weak motor gets there slowly: a quarter newton metre turns a
   * quarter kilogram square metre at one radian a second each second. */
  f3d_multibody_set_motor(w, spun, 1, 1, -2, F3D_R(0.25));
  run(w, 60);
  f3d_multibody_read_joint(w, spun, 1, joint);
  CHECK_NEAR(joint[1], 1, 0.02);
  f3d_world_destroy(w);
}

static void test_motor_moves_the_tree(void) {
  /* An arm of two links on upright hinges, the second free: the motor on
   * the shoulder swings the arm, and the elbow, pushed by nothing, lags
   * behind it — the tree answers the motor, not the shoulder alone. */
  F3dWorld *w = still_air();
  const F3dBody base = post(w, 0, 3);
  const F3dBody upper = f3d_body_create(w, F3D_BODY_DYNAMIC, F3D_R(0.5), 3, 0, 1);
  const F3dBody lower = f3d_body_create(w, F3D_BODY_DYNAMIC, F3D_R(1.5), 3, 0, 1);
  f3d_body_set_shape(w, upper, F3D_SHAPE_BOX, F3D_R(0.5), F3D_R(0.05), F3D_R(0.05));
  f3d_body_set_shape(w, lower, F3D_SHAPE_BOX, F3D_R(0.5), F3D_R(0.05), F3D_R(0.05));
  const F3dMultibody m = f3d_multibody_create(w, base);
  f3d_multibody_add_link(w, m, 0, upper, F3D_JOINT_REVOLUTE, 0, 3, 0, 0, 1, 0);
  f3d_multibody_add_link(w, m, 1, lower, F3D_JOINT_REVOLUTE, 1, 3, 0, 0, 1, 0);
  f3d_multibody_set_motor(w, m, 1, 1, 3, 2);
  run(w, 10);
  f3d_real shoulder[8], elbow[8];
  f3d_multibody_read_joint(w, m, 1, shoulder);
  f3d_multibody_read_joint(w, m, 2, elbow);
  CHECK(shoulder[1] > F3D_R(0.1));
  CHECK(elbow[1] < -F3D_R(0.05));
  f3d_world_destroy(w);
}

static void test_cone(void) {
  /* A ball hanging a metre under a ball joint, knocked sideways at four
   * metres a second and spun about its rod. In a cone of half a radian and
   * a twist of three tenths it stays inside both; without one it swings
   * past a radian and turns freely. */
  for (int coned = 0; coned < 2; coned++) {
    F3dWorld *w = still_air();
    const F3dBody top = post(w, 0, 3);
    const F3dBody bob = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 2, 0, 1);
    f3d_body_set_shape(w, bob, F3D_SHAPE_BOX, F3D_R(0.1), F3D_R(0.1), F3D_R(0.1));
    const F3dMultibody m = f3d_multibody_create(w, top);
    CHECK(f3d_multibody_add_link(w, m, 0, bob, F3D_JOINT_SPHERICAL, 0, 3, 0, 0, -1, 0) == 1);
    if (coned) {
      CHECK(f3d_multibody_set_cone(w, m, 1, 1, 0, F3D_R(0.3)) == 0);
      CHECK(f3d_multibody_set_cone(w, m, 1, 1, F3D_R(0.5), F3D_R(4.0)) == 0);
      CHECK(f3d_multibody_set_cone(w, m, 1, 1, F3D_R(0.5), F3D_R(0.3)) == 1);
    }
    f3d_body_set_velocity(w, bob, 4, 0, 0);
    f3d_body_set_angular_velocity(w, bob, 0, 4, 0);
    double most_swing = 0, most_twist = 0, most_out_at_edge = 0;
    for (int i = 0; i < 120; i++) {
      run(w, 1);
      f3d_real j[8];
      f3d_multibody_read_joint(w, m, 1, j);
      /* The rod's direction, the turn applied to straight down. */
      const F3dQuat q = {j[0], j[1], j[2], j[3]};
      const F3dMat3 r = f3d_mat_of(q);
      /* (0,-1,0) turned is -c1; how far down it points is c1.y. */
      const double down = (double)r.c[1].y;
      const double swing = acos(down > 1 ? 1 : down);
      if (swing > most_swing) most_swing = swing;
      /* The twist: twice the angle of the turn's part about the rod. */
      const double along = -(double)q.y;
      double tw = 2 * atan2(along, (double)q.w);
      if (tw > M_PI) tw -= 2 * M_PI;
      if (tw < -M_PI) tw += 2 * M_PI;
      if (fabs(tw) > most_twist) most_twist = fabs(tw);
      /* At the cone's edge, the spin the link keeps carries it no further
       * out. */
      if (fabs(tw) > 0.299) {
        const F3dVec3 rod = f3d_scale(r.c[1], F3D_R(-1.0));
        const double turning =
            (tw > 0 ? 1 : -1) * (double)f3d_dot(f3d_v3(j[4], j[5], j[6]), rod);
        if (turning > most_out_at_edge) most_out_at_edge = turning;
      }
      if (swing > 0.499) {
        const F3dVec3 out = f3d_scale(r.c[1], F3D_R(-1.0));
        const F3dVec3 bend = f3d_cross(f3d_v3(0, -1, 0), out);
        const double bent = sqrt((double)f3d_dot(bend, bend));
        const double rate = (double)f3d_dot(f3d_v3(j[4], j[5], j[6]), bend) / bent;
        if (rate > most_out_at_edge) most_out_at_edge = rate;
      }
    }
    if (coned) {
      CHECK(most_out_at_edge < 0.05);
      f3d_real j[8];
      CHECK(most_swing <= 0.5 + 0.01);
      CHECK(most_swing > 0.45);
      CHECK(most_twist <= 0.3 + 0.02);
      CHECK(most_twist > 0.25);
      /* Put a radian out by hand, it reads back inside after one step. */
      f3d_body_set_velocity(w, bob, 0, 0, 0);
      f3d_body_set_angular_velocity(w, bob, 0, 0, 0);
      /* A ball joint is read from how the link is turned: turned a
       * radian about z, it swings out a radian. */
      f3d_body_set_orientation(w, bob, 0, 0, (f3d_real)sin(0.5), (f3d_real)cos(0.5));
      run(w, 1);
      f3d_multibody_read_joint(w, m, 1, j);
      const F3dQuat back = {j[0], j[1], j[2], j[3]};
      const double down = (double)f3d_mat_of(back).c[1].y;
      CHECK(acos(down > 1 ? 1 : down) <= 0.5 + 1e-3);
      /* Turned a radian about its rod, it twists back to the edge. */
      f3d_body_set_orientation(w, bob, 0, (f3d_real)sin(0.5), 0, (f3d_real)cos(0.5));
      f3d_body_set_angular_velocity(w, bob, 0, 0, 0);
      run(w, 1);
      f3d_multibody_read_joint(w, m, 1, j);
      CHECK(fabs(2 * atan2(-(double)j[1], (double)j[3])) <= 0.3 + 1e-3);
    } else {
      CHECK(most_swing > 1.0);
      CHECK(most_twist > 1.0);
    }
    f3d_world_destroy(w);
  }
}

static void test_snapshot(void) {
  F3dWorld *w = still_air();
  const F3dBody top = post(w, 0, 5);
  const F3dMultibody m = f3d_multibody_create(w, top);
  F3dBody last = top;
  for (int k = 1; k <= 5; k++) {
    const F3dBody b = ball(w, (f3d_real)k * F3D_R(0.4), 5, 1, F3D_R(0.1));
    f3d_multibody_add_link(w, m, (uint32_t)(k - 1), b,
                           k % 2 ? F3D_JOINT_REVOLUTE : F3D_JOINT_SPHERICAL,
                           (f3d_real)(k - 1) * F3D_R(0.4), 5, 0, 0, 0, 1);
    last = b;
  }
  f3d_body_set_velocity(w, last, 0, 0, 2);
  run(w, 30);
  const uint32_t size = f3d_world_snapshot_size(w);
  uint8_t *bytes = (uint8_t *)malloc(size);
  CHECK(f3d_world_snapshot_write(w, bytes, size) == size);
  F3dWorld *copy = f3d_world_create();
  CHECK(f3d_world_restore(copy, bytes, size) == 1);
  CHECK(f3d_multibody_link_count(copy, m) == 6);
  run(w, 90);
  run(copy, 90);
  f3d_real ta[7 * 8], tb[7 * 8];
  const uint32_t na = f3d_world_read_transforms(w, ta, NULL, 8);
  const uint32_t nb = f3d_world_read_transforms(copy, tb, NULL, 8);
  CHECK(na == nb);
  CHECK(memcmp(ta, tb, (size_t)na * 7 * sizeof(f3d_real)) == 0);
  free(bytes);
  f3d_world_destroy(w);
  f3d_world_destroy(copy);
}

int main(void) {
  test_refusals();
  test_pendulum();
  test_heavy_chain();
  test_floating_lands();
  test_limits_and_motor();
  test_motor_moves_the_tree();
  test_cone();
  test_snapshot();
  return finish();
}
