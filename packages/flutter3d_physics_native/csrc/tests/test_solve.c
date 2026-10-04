/*
 * The solver, tested in C — P9, phase 3: each test against the physics it
 * has to reproduce. A crate comes to rest and sleeps, a stack of ten
 * stands, a ball bounces back with its restitution's share, a crate slides
 * down a slope at g(sin θ − μ cos θ) and holds on a steeper μ, a ball rolls
 * down it at 5/7 g sin θ without slipping, a collision keeps its momentum,
 * a crate stood on its edge falls flat, and one spawned inside the floor is
 * pushed out no faster than the push limit.
 */
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "check.h"

static const F3dQuat identity = {0, 0, 0, 1};

static F3dQuat turn_about(F3dVec3 axis, double angle) {
  const double s = sin(angle / 2);
  F3dQuat q = {(f3d_real)(axis.x * s), (f3d_real)(axis.y * s),
               (f3d_real)(axis.z * s), (f3d_real)cos(angle / 2)};
  return q;
}

/* A world with a floor whose top is at y = 0, turned by [q] about the
 * origin. */
static F3dWorld *with_floor(F3dQuat q, F3dBody *floor) {
  F3dWorld *w = f3d_world_create();
  f3d_world_set_air(w, F3D_R(293.15), F3D_R(1e-30));
  const F3dMat3 m = f3d_mat_of(q);
  const F3dVec3 at = f3d_scale(m.c[1], F3D_R(-0.5));
  *floor = f3d_body_create(w, F3D_BODY_FIXED, at.x, at.y, at.z, 0);
  f3d_body_set_shape(w, *floor, F3D_SHAPE_BOX, 20, F3D_R(0.5), 20);
  f3d_body_set_orientation(w, *floor, q.x, q.y, q.z, q.w);
  return w;
}

static F3dBody crate(F3dWorld *w, F3dVec3 at, F3dQuat q, f3d_real half) {
  const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, at.x, at.y, at.z, 1);
  f3d_body_set_shape(w, b, F3D_SHAPE_BOX, half, half, half);
  f3d_body_set_orientation(w, b, q.x, q.y, q.z, q.w);
  return b;
}

static void run(F3dWorld *w, double seconds) {
  const int steps = (int)(seconds * 60.0 + 0.5);
  for (int i = 0; i < steps; i++) f3d_world_step(w, F3D_R(1.0 / 60.0));
}

static double length(const f3d_real *v) {
  return sqrt((double)v[0] * v[0] + (double)v[1] * v[1] + (double)v[2] * v[2]);
}

static void test_crate_comes_to_rest(void) {
  F3dBody floor;
  F3dWorld *w = with_floor(identity, &floor);
  const F3dBody b = crate(w, f3d_v3(0, F3D_R(0.51), 0), identity, F3D_R(0.5));
  run(w, 3);
  f3d_real p[3], v[3], q[4];
  f3d_body_get_position(w, b, p);
  f3d_body_get_velocity(w, b, v);
  f3d_body_get_orientation(w, b, q);
  /* On the floor, sunk no further than the slop, still, unturned. */
  CHECK(p[1] > F3D_R(0.5) - F3D_R(0.006) && p[1] < F3D_R(0.5));
  CHECK(length(v) < 1e-3);
  CHECK_NEAR(fabs((double)q[3]), 1, 1e-5);
  CHECK(f3d_body_is_asleep(w, b));
  /* The floor held its weight: four points pushing m g h a substep between
   * them, on the last step it was awake. */
  double held = 0;
  for (uint32_t i = 0; i < w->s.manifold_count; i++) {
    for (uint32_t k = 0; k < w->manifolds[i].count; k++) {
      held += w->manifolds[i].points[k].normal_impulse;
    }
  }
  CHECK_NEAR(held, 9.81 / 240.0, 2e-2);
  f3d_world_destroy(w);
}

static void test_stack_stands(void) {
  /* Ten crates a metre on a side, one on another. Each joint settles to
   * the slop and the soft contact's give under the weight above it — under
   * a centimetre — the pile does not walk sideways, and once it sleeps it
   * does not move again. */
  F3dBody floor;
  F3dWorld *w = with_floor(identity, &floor);
  F3dBody boxes[10];
  for (int i = 0; i < 10; i++) {
    boxes[i] = crate(w, f3d_v3(0, F3D_R(0.5) + (f3d_real)i, 0), identity,
                     F3D_R(0.5));
  }
  run(w, 2);
  f3d_real early[3];
  f3d_body_get_position(w, boxes[9], early);
  run(w, 8);
  f3d_real p[3];
  f3d_body_get_position(w, boxes[9], p);
  CHECK(p[0] == early[0] && p[1] == early[1] && p[2] == early[2]);
  CHECK(fabs((double)p[0]) < 0.02 && fabs((double)p[2]) < 0.02);
  CHECK(p[1] > F3D_R(9.5) - 10 * F3D_R(0.01) && p[1] < F3D_R(9.5));
  for (int i = 1; i < 10; i++) {
    f3d_real lo[3], hi[3];
    f3d_body_get_position(w, boxes[i - 1], lo);
    f3d_body_get_position(w, boxes[i], hi);
    CHECK(hi[1] - lo[1] > F3D_R(0.99) && hi[1] - lo[1] < 1);
  }
  int asleep = 1;
  for (int i = 0; i < 10; i++) asleep &= f3d_body_is_asleep(w, boxes[i]);
  CHECK(asleep);
  f3d_world_destroy(w);
}

static void test_bounce(void) {
  /* Dropped from two metres onto the floor with a restitution of a half:
   * it leaves at half the speed it arrived with. */
  F3dBody floor;
  F3dWorld *w = with_floor(identity, &floor);
  const F3dBody ball = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, F3D_R(2.25), 0, 1);
  f3d_body_set_shape(w, ball, F3D_SHAPE_SPHERE, F3D_R(0.25), 0, 0);
  f3d_body_set_restitution(w, ball, F3D_R(0.5));
  double fastest_down = 0, fastest_up = 0;
  for (int i = 0; i < 120; i++) {
    f3d_world_step(w, F3D_R(1.0 / 60.0));
    f3d_real v[3];
    f3d_body_get_velocity(w, ball, v);
    if (v[1] < -fastest_down) fastest_down = -v[1];
    if (v[1] > fastest_up) fastest_up = v[1];
  }
  CHECK_NEAR(fastest_down, sqrt(2 * 9.81 * 2), 0.03);
  CHECK_NEAR(fastest_up, 0.5 * fastest_down, 0.03);
  f3d_world_destroy(w);
}

static void test_slope(void) {
  /* A slope of thirty degrees. With μ = 0.3 a crate slides down it at
   * g (sin θ − μ cos θ); with μ = 0.7, more than tan θ, it holds. */
  const double theta = M_PI / 6;
  const F3dQuat q = turn_about(f3d_v3(0, 0, 1), theta);
  const F3dMat3 m = f3d_mat_of(q);
  for (int grip = 0; grip < 2; grip++) {
    F3dBody floor;
    F3dWorld *w = with_floor(q, &floor);
    const f3d_real mu = grip ? F3D_R(0.7) : F3D_R(0.3);
    f3d_body_set_friction(w, floor, mu);
    const F3dBody b = crate(w, f3d_scale(m.c[1], F3D_R(0.499)), q, F3D_R(0.25));
    f3d_body_set_shape(w, b, F3D_SHAPE_BOX, F3D_R(0.5), F3D_R(0.25), F3D_R(0.5));
    f3d_body_set_position(w, b, m.c[1].x * F3D_R(0.249), m.c[1].y * F3D_R(0.249),
                          m.c[1].z * F3D_R(0.249));
    f3d_body_set_friction(w, b, mu);
    run(w, 0.5);
    f3d_real v0[3];
    f3d_body_get_velocity(w, b, v0);
    run(w, 1);
    f3d_real v1[3];
    f3d_body_get_velocity(w, b, v1);
    /* Down the slope is −x of the slope's own frame. */
    const double along0 = -f3d_dot(f3d_v3(v0[0], v0[1], v0[2]), m.c[0]);
    const double along1 = -f3d_dot(f3d_v3(v1[0], v1[1], v1[2]), m.c[0]);
    if (grip) {
      CHECK(fabs(along1) < 1e-2);
    } else {
      const double a = 9.81 * (sin(theta) - 0.3 * cos(theta));
      CHECK_NEAR(along1 - along0, a, 0.03);
    }
    f3d_world_destroy(w);
  }
}

static void test_rolling(void) {
  /* A ball on the same slope with friction to spare rolls without
   * slipping: a solid ball's acceleration is 5/7 g sin θ, and its spin is
   * its speed over its radius. */
  const double theta = M_PI / 6;
  const F3dQuat q = turn_about(f3d_v3(0, 0, 1), theta);
  const F3dMat3 m = f3d_mat_of(q);
  F3dBody floor;
  F3dWorld *w = with_floor(q, &floor);
  f3d_world_set_sleep(w, 0, 0);
  f3d_body_set_friction(w, floor, 1);
  const f3d_real r = F3D_R(0.2);
  const F3dVec3 at = f3d_scale(m.c[1], r - F3D_R(0.001));
  const F3dBody ball = f3d_body_create(w, F3D_BODY_DYNAMIC, at.x, at.y, at.z, 1);
  f3d_body_set_shape(w, ball, F3D_SHAPE_SPHERE, r, 0, 0);
  f3d_body_set_friction(w, ball, 1);
  run(w, 0.25);
  f3d_real v0[3], v1[3], spin[3];
  f3d_body_get_velocity(w, ball, v0);
  run(w, 1);
  f3d_body_get_velocity(w, ball, v1);
  f3d_body_get_angular_velocity(w, ball, spin);
  const double a = length(v1) - length(v0);
  CHECK_NEAR(a, 5.0 / 7.0 * 9.81 * sin(theta), 0.03);
  CHECK_NEAR(length(spin) * (double)r / length(v1), 1, 0.02);
  f3d_world_destroy(w);
}

static void test_fast_roll_stays_up(void) {
  /* A ball rolling at ten metres a second turns a radian and a half a
   * step. It stays on the floor within the slop: the contact follows the
   * point it touches at, not a point of the ball carried round, which
   * read a gap under a resting ball and let it sink two centimetres. */
  F3dBody floor;
  F3dWorld *w = with_floor(identity, &floor);
  f3d_world_set_sleep(w, 0, 0);
  const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, F3D_R(0.1), 0, 1);
  f3d_body_set_shape(w, b, F3D_SHAPE_SPHERE, F3D_R(0.1), 0, 0);
  run(w, 0.5);
  f3d_body_set_velocity(w, b, 10, 0, 0);
  double lowest = 1;
  for (int i = 0; i < 60; i++) {
    f3d_world_step(w, F3D_R(1.0 / 60.0));
    f3d_real p[3];
    f3d_body_get_position(w, b, p);
    if ((double)p[1] < lowest) lowest = p[1];
  }
  CHECK(lowest > 0.1 - 0.006);
  f3d_world_destroy(w);
}

static void test_thin_rod_stays_sane(void) {
  /* A rod two metres by two centimetres spun at three hundred radians a
   * second into a wall with its end: friction at its end spins it about its
   * length, where it is five thousand times easier to turn. It is thrown
   * back and spins, and nothing blows up: its spin stays within an eighth of
   * a turn a substep and its speed within reason. Before the bound it flew
   * off at hundreds of millions of radians a second. */
  F3dWorld *w = f3d_world_create();
  f3d_world_set_gravity(w, 0, 0, 0);
  f3d_world_set_air(w, F3D_R(293.15), F3D_R(1e-30));
  f3d_world_set_sleep(w, 0, 0);
  const F3dBody wall = f3d_body_create(w, F3D_BODY_FIXED, F3D_R(0.5), 0, 0, 0);
  f3d_body_set_shape(w, wall, F3D_SHAPE_BOX, F3D_R(0.05), 2, 2);
  const F3dBody rod = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 1);
  f3d_body_set_shape(w, rod, F3D_SHAPE_BOX, 1, F3D_R(0.01), F3D_R(0.01));
  f3d_body_set_orientation(w, rod, 0, F3D_R(0.70710678), 0, F3D_R(0.70710678));
  f3d_body_set_angular_velocity(w, rod, 0, 300, 0);
  f3d_body_set_bullet(w, rod, 1);
  double fastest = 0, spin = 0;
  for (int i = 0; i < 120; i++) {
    f3d_world_step(w, F3D_R(1.0 / 60.0));
    f3d_real v[3], o[3];
    f3d_body_get_velocity(w, rod, v);
    f3d_body_get_angular_velocity(w, rod, o);
    const double sv = sqrt((double)v[0] * v[0] + (double)v[1] * v[1] + (double)v[2] * v[2]);
    const double so = sqrt((double)o[0] * o[0] + (double)o[1] * o[1] + (double)o[2] * o[2]);
    if (sv > fastest) fastest = sv;
    if (so > spin) spin = so;
  }
  CHECK(fastest < 200);
  CHECK(spin <= 0.25 * M_PI * 240.0 * (1 + 1e-5));
  f3d_world_destroy(w);
}

static void test_collision_keeps_momentum(void) {
  /* Two balls of a kilogram head on, no gravity. Elastic, they trade
   * velocities; inelastic, they go on together; either way the momentum is
   * what it was. */
  for (int elastic = 0; elastic < 2; elastic++) {
    F3dWorld *w = f3d_world_create();
    f3d_world_set_gravity(w, 0, 0, 0);
    f3d_world_set_air(w, F3D_R(293.15), F3D_R(1e-30));
    const F3dBody a = f3d_body_create(w, F3D_BODY_DYNAMIC, -1, 0, 0, 1);
    const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, 1, 0, 0, 1);
    f3d_body_set_shape(w, a, F3D_SHAPE_SPHERE, F3D_R(0.25), 0, 0);
    f3d_body_set_shape(w, b, F3D_SHAPE_SPHERE, F3D_R(0.25), 0, 0);
    f3d_body_set_velocity(w, a, 3, 0, 0);
    f3d_body_set_velocity(w, b, -1, 0, 0);
    if (elastic) {
      f3d_body_set_restitution(w, a, 1);
      f3d_body_set_restitution(w, b, 1);
    }
    run(w, 1);
    f3d_real va[3], vb[3];
    f3d_body_get_velocity(w, a, va);
    f3d_body_get_velocity(w, b, vb);
    CHECK_NEAR(va[0] + vb[0], 2, 1e-5);
    if (elastic) {
      CHECK_NEAR(va[0], -1, 0.02);
      CHECK_NEAR(vb[0], 3, 0.02);
    } else {
      CHECK_NEAR(va[0], 1, 0.02);
      CHECK_NEAR(vb[0], 1, 0.02);
    }
    f3d_world_destroy(w);
  }
}

static void test_tips_over(void) {
  /* Stood on its edge a little past balance, a crate falls onto a face and
   * lies flat. */
  F3dBody floor;
  F3dWorld *w = with_floor(identity, &floor);
  const double angle = M_PI / 4 + 0.05;
  const double reach = sqrt(0.5) * cos(angle - M_PI / 4);
  const F3dBody b = crate(w, f3d_v3(0, (f3d_real)(reach * 0.5 / 0.5 - 0.001), 0),
                          turn_about(f3d_v3(0, 0, 1), angle), F3D_R(0.5));
  run(w, 4);
  f3d_real q[4];
  f3d_body_get_orientation(w, b, q);
  F3dQuat qq = {q[0], q[1], q[2], q[3]};
  const F3dMat3 m = f3d_mat_of(qq);
  /* Some axis of the crate is straight up. */
  const double most = fmax(fabs((double)m.c[0].y),
                           fmax(fabs((double)m.c[1].y), fabs((double)m.c[2].y)));
  CHECK_NEAR(most, 1, 1e-3);
  f3d_real p[3];
  f3d_body_get_position(w, b, p);
  CHECK(fabs((double)p[1] - 0.5) < 0.01);
  f3d_world_destroy(w);
}

static void test_pushed_out_gently(void) {
  /* Spawned thirty centimetres into the floor, a crate comes out no faster
   * than three metres a second and settles on top. Measured by how far it
   * moves a step, not by its velocity: the relaxing pass takes the push
   * back out of the velocity, which is the point of it. */
  F3dBody floor;
  F3dWorld *w = with_floor(identity, &floor);
  const F3dBody b = crate(w, f3d_v3(0, F3D_R(0.2), 0), identity, F3D_R(0.5));
  double fastest = 0, last = 0.2;
  for (int i = 0; i < 180; i++) {
    f3d_world_step(w, F3D_R(1.0 / 60.0));
    f3d_real p[3];
    f3d_body_get_position(w, b, p);
    if ((p[1] - last) * 60.0 > fastest) fastest = (p[1] - last) * 60.0;
    last = p[1];
  }
  CHECK(fastest > 1 && fastest <= 3.0 + 1e-3);
  f3d_real p[3];
  f3d_body_get_position(w, b, p);
  CHECK(fabs((double)p[1] - 0.5) < 0.01);
  f3d_world_destroy(w);
}

static void test_friction_and_restitution_refused(void) {
  F3dWorld *w = f3d_world_create();
  const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 1);
  CHECK(f3d_body_set_friction(w, b, -1) == 0);
  CHECK(f3d_body_set_friction(w, b, nan_value()) == 0);
  CHECK(f3d_body_set_restitution(w, b, F3D_R(1.5)) == 0);
  CHECK(f3d_body_set_restitution(w, b, -1) == 0);
  CHECK(f3d_body_set_friction(w, 0, 1) == 0);
  CHECK(f3d_body_set_restitution(w, b, F3D_R(0.3)) == 1);
  f3d_world_destroy(w);
}

int main(void) {
  test_crate_comes_to_rest();
  test_stack_stands();
  test_bounce();
  test_slope();
  test_rolling();
  test_fast_roll_stays_up();
  test_thin_rod_stays_sane();
  test_collision_keeps_momentum();
  test_tips_over();
  test_pushed_out_gently();
  test_friction_and_restitution_refused();
  return finish();
}
