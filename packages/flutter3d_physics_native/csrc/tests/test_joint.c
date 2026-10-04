/*
 * Joints, tested in C — P9, phase 7: each against the physics it has to
 * reproduce. The core's arctangent against the library's, a pendulum's
 * period, a rod holding its length, a rope that is slack until it is taut,
 * a spring's period, a welded cantilever, a hinge's limits and motor, a
 * slider on its axis, joined bodies that do not collide, a chain asleep as
 * one, the force a rod holds a weight with, joints through a snapshot, and
 * a spherical joint's swing held in a cone and its twist between limits,
 * and what its friction and cone refuse.
 */
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "check.h"

#ifdef F3D_REAL_DOUBLE
#define TIGHT 1e-12
#else
#define TIGHT 3e-7
#endif

static F3dWorld *still_world(void) {
  F3dWorld *w = f3d_world_create();
  f3d_world_set_air(w, F3D_R(293.15), F3D_R(1e-30));
  f3d_world_set_sleep(w, 0, 0);
  return w;
}

static F3dBody anchor(F3dWorld *w, f3d_real x, f3d_real y, f3d_real z) {
  return f3d_body_create(w, F3D_BODY_FIXED, x, y, z, 0);
}

static F3dBody ball(F3dWorld *w, f3d_real x, f3d_real y, f3d_real z,
                    f3d_real r, f3d_real m) {
  const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, x, y, z, m);
  f3d_body_set_shape(w, b, F3D_SHAPE_SPHERE, r, 0, 0);
  return b;
}

static void run(F3dWorld *w, int steps) {
  for (int i = 0; i < steps; i++) f3d_world_step(w, F3D_R(1.0 / 60.0));
}

static void test_arctangent(void) {
  double worst = 0;
  for (int i = -720; i <= 720; i++) {
    const double a = i * M_PI / 360.0 * 0.999;
    for (int k = 0; k < 3; k++) {
      const double r = k == 0 ? 1.0 : (k == 1 ? 1e-3 : 37.5);
      const double y = r * sin(a), x = r * cos(a);
      const double got = f3d_atan2((f3d_real)y, (f3d_real)x);
      const double want = atan2((double)(f3d_real)y, (double)(f3d_real)x);
      const double e = fabs(got - want);
      if (e > worst) worst = e;
    }
  }
  CHECK(worst < TIGHT * 4);
  CHECK(f3d_atan2(0, 0) == 0);
  CHECK_NEAR(f3d_atan2(0, -1), M_PI, TIGHT);
}

static void test_pendulum(void) {
  /* A small ball on a hinge a metre below its pivot, let go at five
   * degrees: a physical pendulum, its period 2π √((L² + 2/5 r²) / (g L)). */
  F3dWorld *w = still_world();
  const double length = 1.0, r = 0.05, start = 5.0 * M_PI / 180.0;
  const F3dBody pivot = anchor(w, 0, 2, 0);
  const F3dBody bob = ball(w, (f3d_real)(length * sin(start)),
                           (f3d_real)(2 - length * cos(start)), 0, (f3d_real)r, 1);
  const F3dJoint hinge =
      f3d_joint_create(w, F3D_JOINT_REVOLUTE, pivot, bob, 0, 2, 0, 0, 0, 1);
  CHECK(hinge != 0);
  /* Time between the bob's crossings of the bottom, going the same way. */
  double last = 0, first = -1, crossings = 0, t = 0;
  f3d_real prev[3];
  f3d_body_get_position(w, bob, prev);
  for (int i = 0; i < 1200; i++) {
    f3d_world_step(w, F3D_R(1.0 / 240.0));
    t += 1.0 / 240.0;
    f3d_real p[3];
    f3d_body_get_position(w, bob, p);
    if (prev[0] > 0 && p[0] <= 0) {
      const double at = t - (1.0 / 240.0) * p[0] / (p[0] - prev[0]);
      if (first < 0) first = at;
      last = at;
      crossings++;
    }
    prev[0] = p[0];
  }
  const double period = (last - first) / (crossings - 1);
  const double want =
      2 * M_PI * sqrt((length * length + 0.4 * r * r) / (9.81 * length));
  CHECK_NEAR(period, want, 0.01);
  /* Its angle is the hinge's: about the axis, from where it started. */
  f3d_real angle;
  CHECK(f3d_joint_get_value(w, hinge, &angle) == 1);
  f3d_real p[3];
  f3d_body_get_position(w, bob, p);
  const double swung = atan2((double)p[0], 2.0 - (double)p[1]);
  CHECK_NEAR(angle, swung - start, 2e-3);
  f3d_world_destroy(w);
}

static void test_hinge_keeps_its_plane(void) {
  /* Pushed across its plane, a ball on a hinge does not leave it: the
   * hinge locks every turn but its own. On a spherical joint the same push
   * swings it out. */
  for (int ball_joint = 0; ball_joint < 2; ball_joint++) {
    F3dWorld *w = still_world();
    const F3dBody pivot = anchor(w, 0, 2, 0);
    const F3dBody bob = ball(w, 0, 1, 0, F3D_R(0.1), 1);
    f3d_joint_create(w, ball_joint ? F3D_JOINT_SPHERICAL : F3D_JOINT_REVOLUTE,
                     pivot, bob, 0, 2, 0, 0, 0, 1);
    f3d_body_set_velocity(w, bob, 1, 0, 1);
    run(w, 30);
    f3d_real p[3];
    f3d_body_get_position(w, bob, p);
    if (ball_joint) {
      CHECK(fabs((double)p[2]) > 0.1);
    } else {
      CHECK(fabs((double)p[2]) < 1e-3);
    }
    f3d_world_destroy(w);
  }
}

static void test_rod_and_rope(void) {
  F3dWorld *w = still_world();
  /* A rod of two metres, swung hard: it holds its length to a millimetre. */
  const F3dBody pivot = anchor(w, 0, 3, 0);
  const F3dBody bob = ball(w, 2, 3, 0, F3D_R(0.1), 1);
  const F3dJoint rod = f3d_joint_create_distance(w, pivot, bob, 0, 3, 0, 2, 3, 0);
  f3d_body_set_velocity(w, bob, 0, 0, 3);
  double worst = 0;
  for (int i = 0; i < 300; i++) {
    f3d_world_step(w, F3D_R(1.0 / 60.0));
    f3d_real len;
    f3d_joint_get_value(w, rod, &len);
    if (fabs((double)len - 2) > worst) worst = fabs((double)len - 2);
  }
  CHECK(worst < 1e-3);
  /* Hanging still from it, it holds the weight: m g, upward on the bob,
   * which is the joint's B. */
  f3d_body_set_position(w, bob, 0, 1, 0);
  f3d_body_set_velocity(w, bob, 0, 0, 0);
  run(w, 240);
  f3d_real force[3];
  CHECK(f3d_joint_get_force(w, rod, force) == 1);
  CHECK_NEAR(force[1], 9.81, 0.02);
  /* The rod holding the weight made a rope a metre longer: what it held
   * as a rod lets go, and the weight falls the metre. */
  CHECK(f3d_joint_set_length(w, rod, 3, 0, 3) == 1);
  CHECK(f3d_joint_set_spring(w, rod, 1, 0, 0) == 1);
  run(w, 120);
  f3d_real stretched;
  f3d_joint_get_value(w, rod, &stretched);
  CHECK_NEAR(stretched, 3, 2e-3);
  /* A rope of two metres from a ball a metre below: slack, it falls
   * freely until the rope is taut, and then no further. */
  const F3dBody hook = anchor(w, 10, 3, 0);
  const F3dBody load = ball(w, 10, 2, 0, F3D_R(0.1), 1);
  const F3dJoint rope = f3d_joint_create_distance(w, hook, load, 10, 3, 0, 10, 2, 0);
  CHECK(f3d_joint_set_length(w, rope, 2, 0, 2) == 1);
  CHECK(f3d_joint_set_spring(w, rope, 1, 0, 0) == 1);
  CHECK(f3d_joint_set_length(w, rope, 2, F3D_R(2.5), 3) == 0);
  run(w, 20);
  f3d_real v[3];
  f3d_body_get_velocity(w, load, v);
  CHECK_NEAR(v[1], -9.81 * 20.0 / 60.0, 1e-3);
  run(w, 240);
  f3d_real len;
  f3d_joint_get_value(w, rope, &len);
  CHECK(len <= 2.001 && len > 1.99);
  f3d_world_destroy(w);
}

static void test_spring(void) {
  /* A kilogram on a spring of two hertz, no gravity, pulled ten centimetres
   * and let go: it swings with a period of half a second. */
  F3dWorld *w = still_world();
  f3d_world_set_gravity(w, 0, 0, 0);
  const F3dBody wall = anchor(w, 0, 0, 0);
  const F3dBody mass = ball(w, 1, 0, 0, F3D_R(0.05), 1);
  const F3dJoint spring = f3d_joint_create_distance(w, wall, mass, 0, 0, 0, 1, 0, 0);
  f3d_joint_set_length(w, spring, 1, 0, 10);
  f3d_joint_set_spring(w, spring, 1, 2, 0);
  f3d_body_set_position(w, mass, F3D_R(1.1), 0, 0);
  double first = -1, last = 0, t = 0;
  int crossings = 0;
  f3d_real prev = F3D_R(0.1);
  for (int i = 0; i < 960; i++) {
    f3d_world_step(w, F3D_R(1.0 / 240.0));
    t += 1.0 / 240.0;
    f3d_real p[3];
    f3d_body_get_position(w, mass, p);
    const f3d_real x = p[0] - 1;
    if (prev > 0 && x <= 0) {
      const double at = t - (1.0 / 240.0) * x / (x - prev);
      if (first < 0) first = at;
      last = at;
      crossings++;
    }
    prev = x;
  }
  CHECK(crossings >= 6);
  CHECK_NEAR((last - first) / (crossings - 1), 0.5, 0.01);
  f3d_world_destroy(w);
}

static void test_weld(void) {
  /* A box welded to the end of another that is welded to a wall: a
   * cantilever. It sags only by the joints' give, and keeps its turn. */
  F3dWorld *w = still_world();
  const F3dBody wall = anchor(w, 0, 2, 0);
  const F3dBody arm = f3d_body_create(w, F3D_BODY_DYNAMIC, F3D_R(0.5), 2, 0, 1);
  f3d_body_set_shape(w, arm, F3D_SHAPE_BOX, F3D_R(0.5), F3D_R(0.1), F3D_R(0.1));
  const F3dBody tip = f3d_body_create(w, F3D_BODY_DYNAMIC, F3D_R(1.5), 2, 0, 1);
  f3d_body_set_shape(w, tip, F3D_SHAPE_BOX, F3D_R(0.5), F3D_R(0.1), F3D_R(0.1));
  CHECK(f3d_joint_create(w, F3D_JOINT_FIXED, wall, arm, 0, 2, 0, 0, 0, 0) != 0);
  CHECK(f3d_joint_create(w, F3D_JOINT_FIXED, arm, tip, 1, 2, 0, 0, 0, 0) != 0);
  run(w, 300);
  f3d_real p[3], q[4];
  f3d_body_get_position(w, tip, p);
  f3d_body_get_orientation(w, tip, q);
  CHECK(fabs((double)p[1] - 2) < 0.02);
  CHECK(fabs((double)p[0] - 1.5) < 0.005);
  CHECK(fabs((double)q[2]) < 0.01);
  f3d_world_destroy(w);
}

static void test_hinge_limits_and_motor(void) {
  F3dWorld *w = still_world();
  f3d_world_set_gravity(w, 0, 0, 0);
  /* A door on a vertical hinge, limited to half a radian either way and
   * kicked hard: it stops at the limit. */
  const F3dBody frame = anchor(w, 0, 1, 0);
  const F3dBody door = f3d_body_create(w, F3D_BODY_DYNAMIC, F3D_R(0.5), 1, 0, 10);
  f3d_body_set_shape(w, door, F3D_SHAPE_BOX, F3D_R(0.5), 1, F3D_R(0.02));
  const F3dJoint hinge =
      f3d_joint_create(w, F3D_JOINT_REVOLUTE, frame, door, 0, 1, 0, 0, 1, 0);
  CHECK(f3d_joint_set_limits(w, hinge, 1, F3D_R(-0.5), F3D_R(0.5)) == 1);
  CHECK(f3d_joint_set_limits(w, hinge, 1, 1, -1) == 0);
  f3d_body_set_angular_velocity(w, door, 0, 6, 0);
  double most = 0;
  for (int i = 0; i < 120; i++) {
    f3d_world_step(w, F3D_R(1.0 / 60.0));
    f3d_real a;
    f3d_joint_get_value(w, hinge, &a);
    if (fabs((double)a) > most) most = fabs((double)a);
  }
  CHECK(most < 0.52 && most > 0.45);
  /* Limits off and a motor on: it turns at the motor's speed. */
  f3d_joint_set_limits(w, hinge, 0, 0, 0);
  CHECK(f3d_joint_set_motor(w, hinge, 1, 2, 1000) == 1);
  run(w, 60);
  f3d_real spin[3];
  f3d_body_get_angular_velocity(w, door, spin);
  CHECK_NEAR(spin[1], 2, 1e-3);
  /* Too weak a motor against a held door cannot turn it: a motor of a
   * newton-metre against a hundred holding it back. */
  const F3dBody stuck = f3d_body_create(w, F3D_BODY_DYNAMIC, F3D_R(5.5), 1, 0, 10);
  f3d_body_set_shape(w, stuck, F3D_SHAPE_BOX, F3D_R(0.5), 1, F3D_R(0.02));
  const F3dBody post = anchor(w, 5, 1, 0);
  const F3dJoint weak =
      f3d_joint_create(w, F3D_JOINT_REVOLUTE, post, stuck, 5, 1, 0, 0, 1, 0);
  f3d_joint_set_motor(w, weak, 1, 2, 1);
  for (int i = 0; i < 60; i++) {
    f3d_body_add_torque(w, stuck, 0, -100, 0);
    f3d_world_step(w, F3D_R(1.0 / 60.0));
  }
  f3d_body_get_angular_velocity(w, stuck, spin);
  CHECK(spin[1] < 0);
  f3d_world_destroy(w);
}

static void test_slider(void) {
  /* A block on a slider tilted thirty degrees, no friction: it slides
   * along the axis at g sin θ and nowhere else, stops at its limit, and a
   * motor drives it back up. */
  F3dWorld *w = still_world();
  const double theta = M_PI / 6;
  const F3dBody rail = anchor(w, 0, 0, 0);
  const F3dBody block = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 2);
  f3d_body_set_shape(w, block, F3D_SHAPE_BOX, F3D_R(0.1), F3D_R(0.1), F3D_R(0.1));
  const f3d_real ux = (f3d_real)cos(theta), uy = (f3d_real)sin(theta);
  const F3dJoint slide =
      f3d_joint_create(w, F3D_JOINT_PRISMATIC, rail, block, 0, 0, 0, ux, uy, 0);
  CHECK(slide != 0);
  CHECK(f3d_joint_create(w, F3D_JOINT_PRISMATIC, rail, block, 0, 0, 0, 0, 0, 0) == 0);
  run(w, 30);
  f3d_real travel;
  f3d_joint_get_value(w, slide, &travel);
  /* Down the axis by g sin θ h² n(n + 1)/2 after n substeps of h:
   * semi-implicit Euler's ½ a t², taken a substep at a time. */
  const double h = 1.0 / 240.0, n = 120.0;
  CHECK_NEAR(travel, -9.81 * sin(theta) * h * h * n * (n + 1) / 2, 1e-4);
  f3d_real p[3], q[4];
  f3d_body_get_position(w, block, p);
  const double off = fabs(-(double)p[0] * uy + (double)p[1] * ux);
  CHECK(off < 1e-3);
  f3d_body_get_orientation(w, block, q);
  CHECK(fabs((double)q[3]) > 0.99999);
  f3d_joint_set_limits(w, slide, 1, -1, 1);
  run(w, 120);
  f3d_joint_get_value(w, slide, &travel);
  CHECK(travel > -1.01 && travel < -0.98);
  f3d_joint_set_motor(w, slide, 1, F3D_R(0.5), 1000);
  run(w, 60);
  f3d_real v[3];
  f3d_body_get_velocity(w, block, v);
  CHECK_NEAR((double)v[0] * ux + (double)v[1] * uy, 0.5, 1e-3);
  f3d_world_destroy(w);
}

static void test_joined_do_not_collide(void) {
  /* Two crates welded half inside each other: they stay so. Told to
   * collide, they are pushed apart and the weld holds against it. */
  F3dWorld *w = still_world();
  f3d_world_set_gravity(w, 0, 0, 0);
  const F3dBody a = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 1);
  const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, F3D_R(0.5), 0, 0, 1);
  f3d_body_set_shape(w, a, F3D_SHAPE_BOX, F3D_R(0.5), F3D_R(0.5), F3D_R(0.5));
  f3d_body_set_shape(w, b, F3D_SHAPE_BOX, F3D_R(0.5), F3D_R(0.5), F3D_R(0.5));
  const F3dJoint joint = f3d_joint_create(w, F3D_JOINT_SPHERICAL, a, b,
                                          F3D_R(0.25), 0, 0, 0, 0, 0);
  run(w, 60);
  CHECK(f3d_world_contact_count(w) == 0);
  f3d_real pa[3], pb[3];
  f3d_body_get_position(w, a, pa);
  f3d_body_get_position(w, b, pb);
  CHECK_NEAR(pb[0] - pa[0], 0.5, 1e-4);
  f3d_joint_set_collide(w, joint, 1);
  run(w, 2);
  CHECK(f3d_world_contact_count(w) > 0);
  /* Taken away with a body, the joint goes too. */
  CHECK(f3d_world_joint_count(w) == 1);
  f3d_body_destroy(w, b);
  CHECK(f3d_world_joint_count(w) == 0);
  CHECK(!f3d_joint_is_valid(w, joint));
  f3d_world_destroy(w);
}

static void test_chain(void) {
  /* Ten links on spherical joints hanging from a hook: the chain hangs
   * straight, its links a link apart, and sleeps as one island; a tug on
   * the last wakes the first. */
  F3dWorld *w = f3d_world_create();
  f3d_world_set_air(w, F3D_R(293.15), F3D_R(1e-30));
  const F3dBody hook = anchor(w, 0, 10, 0);
  F3dBody links[10];
  F3dBody above = hook;
  for (int i = 0; i < 10; i++) {
    links[i] = ball(w, 0, F3D_R(9.75) - F3D_R(0.5) * (f3d_real)i, 0, F3D_R(0.1), F3D_R(0.5));
    const f3d_real y = F3D_R(10.0) - F3D_R(0.5) * (f3d_real)i;
    CHECK(f3d_joint_create(w, F3D_JOINT_SPHERICAL, above, links[i], 0, y, 0, 0, 0, 0) != 0);
    above = links[i];
  }
  run(w, 300);
  f3d_real p[3];
  f3d_body_get_position(w, links[9], p);
  CHECK(fabs((double)p[0]) < 1e-3);
  CHECK(fabs((double)p[1] - 5.25) < 0.02);
  int asleep = 1;
  for (int i = 0; i < 10; i++) asleep &= f3d_body_is_asleep(w, links[i]);
  CHECK(asleep);
  f3d_body_apply_impulse(w, links[9], 1, 0, 0);
  f3d_world_step(w, F3D_R(1.0 / 60.0));
  CHECK(!f3d_body_is_asleep(w, links[0]));
  f3d_world_destroy(w);
}

static void test_snapshot(void) {
  F3dWorld *w = f3d_world_create();
  const F3dBody hook = anchor(w, 0, 5, 0);
  F3dBody above = hook;
  for (int i = 0; i < 6; i++) {
    const F3dBody link = ball(w, F3D_R(0.4) * (f3d_real)(i + 1), 5, 0, F3D_R(0.1), 1);
    f3d_joint_create(w, i % 2 ? F3D_JOINT_REVOLUTE : F3D_JOINT_SPHERICAL, above, link,
                     F3D_R(0.4) * (f3d_real)i, 5, 0, 0, 0, 1);
    above = link;
  }
  run(w, 30);
  const uint32_t size = f3d_world_snapshot_size(w);
  uint8_t *snap = (uint8_t *)malloc(size);
  f3d_world_snapshot_write(w, snap, size);
  F3dWorld *v = f3d_world_create();
  CHECK(f3d_world_restore(v, snap, size) == 1);
  CHECK(f3d_world_joint_count(v) == 6);
  run(w, 120);
  run(v, 120);
  const uint32_t now = f3d_world_snapshot_size(w);
  CHECK(f3d_world_snapshot_size(v) == now);
  uint8_t *a = (uint8_t *)malloc(now), *b = (uint8_t *)malloc(now);
  f3d_world_snapshot_write(w, a, now);
  f3d_world_snapshot_write(v, b, now);
  CHECK(memcmp(a, b, now) == 0);
  free(snap);
  free(a);
  free(b);
  f3d_world_destroy(w);
  f3d_world_destroy(v);
}

static void test_refusals(void) {
  F3dWorld *w = f3d_world_create();
  const F3dBody a = ball(w, 0, 0, 0, 1, 1);
  const F3dBody b = ball(w, 1, 0, 0, 1, 1);
  CHECK(f3d_joint_create(w, F3D_JOINT_FIXED, a, a, 0, 0, 0, 0, 0, 0) == 0);
  CHECK(f3d_joint_create(w, F3D_JOINT_FIXED, a, 0, 0, 0, 0, 0, 0, 0) == 0);
  CHECK(f3d_joint_create(w, F3D_JOINT_DISTANCE, a, b, 0, 0, 0, 0, 0, 0) == 0);
  CHECK(f3d_joint_create(w, (F3dJointType)9, a, b, 0, 0, 0, 0, 0, 0) == 0);
  CHECK(f3d_joint_create(w, F3D_JOINT_FIXED, a, b, nan_value(), 0, 0, 0, 0, 0) == 0);
  const F3dJoint fixed = f3d_joint_create(w, F3D_JOINT_FIXED, a, b, 0, 0, 0, 0, 0, 0);
  CHECK(f3d_joint_set_motor(w, fixed, 1, 1, 1) == 0);
  CHECK(f3d_joint_set_limits(w, fixed, 1, -1, 1) == 0);
  CHECK(f3d_joint_set_spring(w, fixed, 1, 1, 1) == 0);
  CHECK(f3d_joint_set_length(w, fixed, 1, 0, 1) == 0);
  f3d_real out[3];
  CHECK(f3d_joint_get_value(w, fixed, out) == 1 && out[0] == 0);
  CHECK(f3d_joint_destroy(w, fixed) == 1);
  CHECK(f3d_joint_destroy(w, fixed) == 0);
  CHECK(f3d_joint_get_force(w, fixed, out) == 0);
  /* A freed slot is used again under a new generation. */
  const F3dJoint again = f3d_joint_create(w, F3D_JOINT_FIXED, a, b, 0, 0, 0, 0, 0, 0);
  CHECK((uint32_t)again == (uint32_t)fixed && (again >> 32) == (fixed >> 32) + 1);
  f3d_world_destroy(w);
}

/* A limb a metre long hung by its end from a pivot on a spherical joint,
 * its axis down, knocked sideways at 6 m/s — enough to swing it past level
 * — and the most it swung over two seconds, with a cone of [cone] radians
 * or none. */
static double knocked(f3d_real cone) {
  F3dWorld *w = still_world();
  const F3dBody pivot = anchor(w, 0, 2, 0);
  const F3dBody bob = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, F3D_R(1.5), 0, 1);
  f3d_body_set_shape(w, bob, F3D_SHAPE_BOX, F3D_R(0.05), F3D_R(0.5), F3D_R(0.05));
  const F3dJoint j = f3d_joint_create(w, F3D_JOINT_SPHERICAL, pivot, bob, 0, 2, 0, 0, -1, 0);
  if (cone > 0) CHECK(f3d_joint_set_cone(w, j, 1, cone));
  f3d_body_set_velocity(w, bob, 6, 0, F3D_R(1.5));
  double most = 0;
  f3d_real swing = 0, p[3];
  for (int i = 0; i < 120; i++) {
    run(w, 1);
    CHECK(f3d_joint_get_swing(w, j, &swing));
    if (swing > most) most = swing;
  }
  /* And the point held throughout. */
  f3d_body_get_position(w, bob, p);
  CHECK_NEAR(sqrt((double)p[0] * p[0] + (p[1] - 2.0) * (p[1] - 2.0) + (double)p[2] * p[2]), 0.5, 0.01);
  f3d_world_destroy(w);
  return most;
}

static void test_cone(void) {
  /* Free, it swings past level; in a cone of 30 degrees it stops at the
   * cone, give or take what the soft limit lets through. */
  CHECK(knocked(0) > M_PI / 2);
  const double held = knocked((f3d_real)(M_PI / 6));
  CHECK(held < M_PI / 6 + 0.05);
  CHECK(held > M_PI / 6 - 0.05);
}

static void test_twist(void) {
  /* A plank hung on a spherical joint by its axis, spun about it at 8
   * rad/s: its twist stops at the limits, ±0.5, and does not swing it. */
  F3dWorld *w = still_world();
  const F3dBody pivot = anchor(w, 0, 2, 0);
  const F3dBody plank = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, F3D_R(1.5), 0, 1);
  f3d_body_set_shape(w, plank, F3D_SHAPE_BOX, F3D_R(0.4), F3D_R(0.5), F3D_R(0.05));
  const F3dJoint j = f3d_joint_create(w, F3D_JOINT_SPHERICAL, pivot, plank, 0, 2, 0, 0, -1, 0);
  CHECK(f3d_joint_set_limits(w, j, 1, F3D_R(-0.5), F3D_R(0.5)));
  CHECK(f3d_joint_set_cone(w, j, 1, F3D_R(0.2)));
  f3d_body_set_angular_velocity(w, plank, 0, 8, 0);
  double most = 0;
  f3d_real twist = 0, swing = 0;
  for (int i = 0; i < 120; i++) {
    run(w, 1);
    f3d_joint_get_value(w, j, &twist);
    if (fabs((double)twist) > most) most = fabs((double)twist);
  }
  CHECK(most < 0.55);
  CHECK(most > 0.45);
  f3d_joint_get_swing(w, j, &swing);
  CHECK(swing < F3D_R(0.25));
  /* And off, it spins on through them. */
  CHECK(f3d_joint_set_limits(w, j, 0, 0, 0));
  f3d_body_set_angular_velocity(w, plank, 0, 8, 0);
  most = 0;
  for (int i = 0; i < 30; i++) {
    run(w, 1);
    f3d_joint_get_value(w, j, &twist);
    if (fabs((double)twist) > most) most = fabs((double)twist);
  }
  CHECK(most > 1.0);
  /* A cone is a spherical joint's alone, and between nought and π. */
  const F3dBody other = ball(w, 3, 2, 0, F3D_R(0.1), 1);
  const F3dJoint hinge = f3d_joint_create(w, F3D_JOINT_REVOLUTE, pivot, other, 0, 2, 0, 0, 0, 1);
  CHECK(!f3d_joint_set_cone(w, hinge, 1, F3D_R(0.5)));
  CHECK(!f3d_joint_set_cone(w, j, 1, 0));
  CHECK(!f3d_joint_set_cone(w, j, 1, F3D_R(3.5)));
  CHECK(f3d_joint_set_cone(w, j, 0, 0));
  /* So is friction, nought or more; a hinge has a motor for it. */
  CHECK(!f3d_joint_set_friction(w, hinge, 1, 1));
  CHECK(!f3d_joint_set_friction(w, j, 1, -1));
  CHECK(f3d_joint_set_friction(w, j, 1, 0));
  f3d_world_destroy(w);
}

int main(void) {
  test_arctangent();
  test_cone();
  test_twist();
  test_pendulum();
  test_hinge_keeps_its_plane();
  test_rod_and_rope();
  test_spring();
  test_weld();
  test_hinge_limits_and_motor();
  test_slider();
  test_joined_do_not_collide();
  test_chain();
  test_snapshot();
  test_refusals();
  return finish();
}
