/*
 * How bodies move, tested in C — P9: a kinematic body that goes where it is
 * sent and pushes what it meets, shapes as inertia, the turn that keeps
 * angular momentum, impulses and the force bus, damping, the wind's drag,
 * and sleep.
 */
#include <math.h>

#include "check.h"

/* The precision a long run is held to: f32's, or much better in f64. */
#ifdef F3D_REAL_DOUBLE
#define LOOSE 1e-9
#else
#define LOOSE 1e-4
#endif

static void test_inertia(void) {
  F3dWorld *w = f3d_world_create();
  const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 2);
  f3d_real i[3];
  /* A point has none, and does not turn. */
  f3d_body_get_inertia(w, b, i);
  CHECK(i[0] == 0 && i[1] == 0 && i[2] == 0);
  f3d_body_set_angular_velocity(w, b, 1, 2, 3);
  f3d_real spin[3];
  f3d_body_get_angular_velocity(w, b, spin);
  CHECK(spin[0] == 0 && spin[1] == 0 && spin[2] == 0);

  CHECK(f3d_body_set_shape(w, b, F3D_SHAPE_SPHERE, F3D_R(0.5), 0, 0) == 1);
  f3d_body_get_inertia(w, b, i);
  CHECK_NEAR(i[0], 0.4 * 2 * 0.25, 1e-6);
  CHECK(i[0] == i[1] && i[1] == i[2]);

  /* A box 2 × 4 × 6: m/12 · (h² + d²) with the full widths. */
  CHECK(f3d_body_set_shape(w, b, F3D_SHAPE_BOX, 1, 2, 3) == 1);
  f3d_body_get_inertia(w, b, i);
  CHECK_NEAR(i[0], 2.0 / 12.0 * (16 + 36), 1e-6);
  CHECK_NEAR(i[1], 2.0 / 12.0 * (4 + 36), 1e-6);
  CHECK_NEAR(i[2], 2.0 / 12.0 * (4 + 16), 1e-6);

  /* A capsule with no straight part is a sphere. */
  CHECK(f3d_body_set_shape(w, b, F3D_SHAPE_CAPSULE, F3D_R(0.5), 0, 0) == 1);
  f3d_body_get_inertia(w, b, i);
  CHECK_NEAR(i[0], 0.4 * 2 * 0.25, 1e-6);
  CHECK_NEAR(i[1], 0.4 * 2 * 0.25, 1e-6);
  /* A long one is easier to turn about its axis than across it. */
  CHECK(f3d_body_set_shape(w, b, F3D_SHAPE_CAPSULE, F3D_R(0.1), 1, 0) == 1);
  f3d_body_get_inertia(w, b, i);
  CHECK(i[1] < i[0] && i[0] == i[2]);

  /* A fixed body has its inertia but never turns. */
  const F3dBody pinned = f3d_body_create(w, F3D_BODY_FIXED, 0, 0, 0, 1);
  f3d_body_set_shape(w, pinned, F3D_SHAPE_SPHERE, 1, 0, 0);
  f3d_body_set_angular_velocity(w, pinned, 1, 0, 0);
  f3d_body_get_angular_velocity(w, pinned, spin);
  CHECK(spin[0] == 0);
  f3d_world_destroy(w);
}

/* L = R I Rᵀ ω, in doubles. */
static void momentum(F3dWorld *w, F3dBody b, double *l) {
  f3d_real q[4], spin[3], inertia[3];
  f3d_body_get_orientation(w, b, q);
  f3d_body_get_angular_velocity(w, b, spin);
  f3d_body_get_inertia(w, b, inertia);
  F3dQuat qq = {q[0], q[1], q[2], q[3]};
  const F3dSym3 m =
      f3d_sym_turned(qq, f3d_sym_diag(inertia[0], inertia[1], inertia[2]));
  l[0] = (double)m.xx * spin[0] + (double)m.xy * spin[1] + (double)m.xz * spin[2];
  l[1] = (double)m.xy * spin[0] + (double)m.yy * spin[1] + (double)m.yz * spin[2];
  l[2] = (double)m.xz * spin[0] + (double)m.yz * spin[1] + (double)m.zz * spin[2];
}

static void test_turning(void) {
  F3dWorld *w = f3d_world_create();
  f3d_world_set_gravity(w, 0, 0, 0);
  f3d_world_set_sleep(w, 0, 0);
  /* About a principal axis, the spin is kept exactly and the orientation
   * stays a unit quaternion. */
  const F3dBody steady = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 1);
  f3d_body_set_shape(w, steady, F3D_SHAPE_BOX, 1, 2, 3);
  f3d_body_set_angular_velocity(w, steady, 0, 2, 0);
  /* Off its axes, a box wobbles: its spin changes and its angular momentum
   * does not. */
  const F3dBody wobbly = f3d_body_create(w, F3D_BODY_DYNAMIC, 5, 0, 0, 1);
  f3d_body_set_shape(w, wobbly, F3D_SHAPE_BOX, F3D_R(0.1), F3D_R(0.5), 1);
  f3d_body_set_angular_velocity(w, wobbly, 3, 1, F3D_R(0.5));
  double l0[3];
  momentum(w, wobbly, l0);
  f3d_real s0[3];
  f3d_body_get_angular_velocity(w, wobbly, s0);
  for (int i = 0; i < 2000; i++) f3d_world_step(w, F3D_R(1.0 / 240.0));
  f3d_real spin[3], q[4];
  f3d_body_get_angular_velocity(w, steady, spin);
  CHECK(spin[0] == 0 && spin[1] == 2 && spin[2] == 0);
  f3d_body_get_orientation(w, steady, q);
  CHECK_NEAR(q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3], 1, LOOSE);
  /* Two radians a second for 2000/240 s, turned about y. */
  const double angle = 2.0 * 2000.0 / 240.0;
  CHECK_NEAR(q[1], sin(angle / 2), 1e-3);
  CHECK_NEAR(q[3], cos(angle / 2), 1e-3);
  double l1[3];
  momentum(w, wobbly, l1);
  const double l0n = sqrt(l0[0] * l0[0] + l0[1] * l0[1] + l0[2] * l0[2]);
  for (int k = 0; k < 3; k++) CHECK_NEAR(l1[k] / l0n, l0[k] / l0n, 10 * LOOSE);
  f3d_body_get_angular_velocity(w, wobbly, spin);
  CHECK(fabs((double)spin[0] - s0[0]) > 1e-2 ||
        fabs((double)spin[1] - s0[1]) > 1e-2);
  f3d_world_destroy(w);
}

/* Air too thin to slow anything by a bit: what a test of the motion alone
 * wants. Not nought, which the world refuses. */
static void vacuum(F3dWorld *w) { f3d_world_set_air(w, F3D_STANDARD_AIR_TEMPERATURE, F3D_R(1e-30)); }

static void test_impulses_and_forces(void) {
  F3dWorld *w = f3d_world_create();
  f3d_world_set_gravity(w, 0, 0, 0);
  vacuum(w);
  const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 2);
  f3d_body_set_shape(w, b, F3D_SHAPE_SPHERE, F3D_R(0.5), 0, 0);
  /* Through the centre: J / m, and no spin. */
  f3d_body_apply_impulse(w, b, 4, 0, 0);
  f3d_real v[3], spin[3];
  f3d_body_get_velocity(w, b, v);
  CHECK(v[0] == 2 && v[1] == 0);
  /* At a point: the same push, and r × J / I of spin. */
  f3d_body_apply_impulse_at(w, b, 0, 2, 0, F3D_R(0.5), 0, 0);
  f3d_body_get_velocity(w, b, v);
  CHECK(v[0] == 2 && v[1] == 1);
  f3d_body_get_angular_velocity(w, b, spin);
  CHECK_NEAR(spin[2], 0.5 * 2 / (0.4 * 2 * 0.25), 1e-6);
  CHECK(spin[0] == 0 && spin[1] == 0);

  /* A force over one step is F/m · dt, then spent. */
  const F3dBody c = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 2);
  f3d_body_add_force(w, c, 1, 0, 0);
  f3d_body_add_force(w, c, 3, 0, 0);
  f3d_world_step(w, F3D_R(0.5));
  f3d_body_get_velocity(w, c, v);
  CHECK(v[0] == 1);
  f3d_world_step(w, F3D_R(0.5));
  f3d_body_get_velocity(w, c, v);
  CHECK(v[0] == 1);
  /* A torque likewise, through I⁻¹. */
  const F3dBody d = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 1);
  f3d_body_set_shape(w, d, F3D_SHAPE_SPHERE, 1, 0, 0);
  f3d_body_add_torque(w, d, 0, F3D_R(0.4), 0);
  f3d_world_step(w, F3D_R(0.5));
  f3d_body_get_angular_velocity(w, d, spin);
  CHECK_NEAR(spin[1], 0.5, 1e-6);
  /* Locked, it keeps its push and loses its turn. */
  f3d_body_lock_rotation(w, d, 1);
  f3d_body_get_angular_velocity(w, d, spin);
  CHECK(spin[1] == 0);
  f3d_body_add_torque(w, d, 0, 1, 0);
  f3d_body_apply_impulse_at(w, d, 1, 0, 0, 0, 1, 0);
  f3d_world_step(w, F3D_R(0.5));
  f3d_body_get_angular_velocity(w, d, spin);
  CHECK(spin[0] == 0 && spin[1] == 0 && spin[2] == 0);
  f3d_body_get_velocity(w, d, v);
  CHECK(v[0] == 1);
  /* A fixed body takes nothing. */
  const F3dBody pinned = f3d_body_create(w, F3D_BODY_FIXED, 0, 0, 0, 1);
  f3d_body_apply_impulse(w, pinned, 1, 0, 0);
  f3d_body_add_force(w, pinned, 1, 0, 0);
  f3d_world_step(w, 1);
  f3d_body_get_velocity(w, pinned, v);
  CHECK(v[0] == 0);
  f3d_world_destroy(w);
}

static void test_damping(void) {
  F3dWorld *w = f3d_world_create();
  f3d_world_set_substeps(w, 1);
  f3d_world_set_gravity(w, 0, 0, 0);
  vacuum(w);
  const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 1);
  f3d_body_set_shape(w, b, F3D_SHAPE_SPHERE, 1, 0, 0);
  f3d_body_set_damping(w, b, 1, 3);
  f3d_body_set_velocity(w, b, 2, 0, 0);
  /* Under the bound on a substep's turn, π/4 in a step of a second. */
  f3d_body_set_angular_velocity(w, b, 0, 0, F3D_R(0.4));
  f3d_world_step(w, 1);
  f3d_real v[3], spin[3];
  f3d_body_get_velocity(w, b, v);
  f3d_body_get_angular_velocity(w, b, spin);
  CHECK(v[0] == 1);
  CHECK_NEAR(spin[2], 0.1, 1e-6);
  f3d_world_destroy(w);
}

static void test_drag(void) {
  /* A ball dropped in still air falls to its terminal speed, where drag
   * holds its weight: ½ ρ C π r² v² = m g. */
  F3dWorld *w = f3d_world_create();
  f3d_world_set_sleep(w, 0, 0);
  const f3d_real r = F3D_R(0.1), m = F3D_R(0.05);
  const F3dBody ball = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, m);
  f3d_body_set_shape(w, ball, F3D_SHAPE_SPHERE, r, 0, 0);
  for (int i = 0; i < 6000; i++) f3d_world_step(w, F3D_R(1.0 / 120.0));
  f3d_real v[3];
  f3d_body_get_velocity(w, ball, v);
  const double terminal =
      sqrt(2.0 * (double)m * STANDARD_G / ((double)F3D_STANDARD_AIR_DENSITY * 0.47 * 3.14159265358979 * (double)r * (double)r));
  CHECK_NEAR(-v[1], terminal, 1e-4);
  /* At a step far too long for an explicit drag — a leaf in a gale — it
   * still settles, at the same speed. */
  const F3dBody leaf = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, F3D_R(1e-4));
  f3d_body_set_shape(w, leaf, F3D_SHAPE_BOX, F3D_R(0.05), F3D_R(0.001), F3D_R(0.05));
  f3d_world_set_wind(w, 30, 0, 0);
  for (int i = 0; i < 200; i++) f3d_world_step(w, F3D_R(0.1));
  f3d_body_get_velocity(w, leaf, v);
  CHECK(f3d_finite(v[0]) && f3d_finite(v[1]));
  CHECK_NEAR(v[0], 30, 1e-4);
  /* A drag coefficient of its own changes it. */
  f3d_body_set_drag(w, ball, F3D_R(0.94));
  f3d_world_set_wind(w, 0, 0, 0);
  for (int i = 0; i < 6000; i++) f3d_world_step(w, F3D_R(1.0 / 120.0));
  f3d_body_get_velocity(w, ball, v);
  CHECK_NEAR(-v[1], terminal / sqrt(2.0), 1e-4);
  /* A point feels no wind. */
  const F3dBody point = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 1);
  f3d_world_set_gravity(w, 0, 0, 0);
  f3d_world_set_wind(w, 10, 0, 0);
  f3d_world_step(w, 1);
  f3d_body_get_velocity(w, point, v);
  CHECK(v[0] == 0);
  f3d_world_destroy(w);
}

static void test_wind_carries(void) {
  /* With no gravity, a ball let go in a steady wind is carried towards the
   * wind's speed and never past it, along quadratic drag's closed form:
   * u = u₀ / (1 + c u₀ t), with c = ½ ρ C π r² / m. */
  F3dWorld *w = f3d_world_create();
  f3d_world_set_gravity(w, 0, 0, 0);
  f3d_world_set_sleep(w, 0, 0);
  const F3dBody ball = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, F3D_R(0.01));
  f3d_body_set_shape(w, ball, F3D_SHAPE_SPHERE, F3D_R(0.05), 0, 0);
  /* A grid wind only, so the uniform one is nought. */
  const f3d_real grid[3] = {0, 0, 5};
  f3d_world_set_wind_grid(w, 0, 0, 0, 1, 1, 1, 1, grid);
  f3d_real v[3];
  f3d_real last = 0;
  int monotone = 1;
  for (int i = 0; i < 2000; i++) {
    f3d_world_step(w, F3D_R(1.0 / 60.0));
    f3d_body_get_velocity(w, ball, v);
    monotone &= v[2] >= last && v[2] <= 5;
    last = v[2];
  }
  CHECK(monotone);
  const double c = 0.5 * (double)F3D_STANDARD_AIR_DENSITY * 0.47 * 3.14159265358979 * 0.05 * 0.05 / 0.01;
  const double t = 2000.0 / 60.0;
  CHECK_NEAR(v[2], 5.0 - 5.0 / (1.0 + c * 5.0 * t), 1e-3);
  f3d_world_destroy(w);
}

static void test_sleep(void) {
  F3dWorld *w = f3d_world_create();
  f3d_world_set_gravity(w, 0, 0, 0);
  F3dBody bodies[4];
  uint32_t kinds[4];
  const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 1);
  f3d_body_set_shape(w, b, F3D_SHAPE_SPHERE, F3D_R(0.1), 0, 0);
  f3d_body_set_velocity(w, b, F3D_R(0.01), 0, 0);
  /* Just short of half a second still: awake. */
  for (int i = 0; i < 29; i++) f3d_world_step(w, F3D_R(1.0 / 60.0));
  CHECK(!f3d_body_is_asleep(w, b));
  /* Asleep at the start of the step after the half second is up: sleep is
   * its island's to decide, where the contacts are. */
  for (int i = 0; i < 3; i++) f3d_world_step(w, F3D_R(1.0 / 60.0));
  CHECK(f3d_body_is_asleep(w, b));
  CHECK(f3d_world_read_events(w, bodies, NULL, kinds, 4) == 1);
  CHECK(bodies[0] == b && kinds[0] == F3D_EVENT_SLEPT);
  f3d_real v[3], p[3], q[3];
  f3d_body_get_velocity(w, b, v);
  CHECK(v[0] == 0);
  /* Asleep, it does not move, whatever gravity does. */
  f3d_body_get_position(w, b, p);
  f3d_world_set_gravity(w, 0, -F3D_STANDARD_GRAVITY, 0);
  f3d_world_step(w, 1);
  f3d_body_get_position(w, b, q);
  CHECK(p[1] == q[1]);
  /* Pushed, it wakes and says so. */
  f3d_body_apply_impulse(w, b, 0, 1, 0);
  CHECK(!f3d_body_is_asleep(w, b));
  CHECK(f3d_world_read_events(w, bodies, NULL, kinds, 4) == 1);
  CHECK(kinds[0] == F3D_EVENT_WOKE);
  /* A change of wind wakes what it blows on. */
  f3d_world_set_gravity(w, 0, 0, 0);
  f3d_body_set_velocity(w, b, 0, 0, 0);
  for (int i = 0; i < 60; i++) f3d_world_step(w, F3D_R(1.0 / 60.0));
  CHECK(f3d_body_is_asleep(w, b));
  f3d_world_set_wind(w, 3, 0, 0);
  CHECK(!f3d_body_is_asleep(w, b));
  /* Turning on the spot is not rest. */
  f3d_world_set_wind(w, 0, 0, 0);
  f3d_body_set_velocity(w, b, 0, 0, 0);
  f3d_body_set_angular_velocity(w, b, 0, 1, 0);
  for (int i = 0; i < 120; i++) f3d_world_step(w, F3D_R(1.0 / 60.0));
  CHECK(!f3d_body_is_asleep(w, b));
  /* A sleep time of nought turns it off. */
  f3d_world_set_sleep(w, 1, 0);
  f3d_body_set_angular_velocity(w, b, 0, 0, 0);
  for (int i = 0; i < 120; i++) f3d_world_step(w, F3D_R(1.0 / 60.0));
  CHECK(!f3d_body_is_asleep(w, b));
  f3d_world_destroy(w);
}

/* A metre-wide paddle, kinematic, at [x] on a floor. */
static F3dBody paddle(F3dWorld *w, f3d_real x) {
  const F3dBody p = f3d_body_create(w, F3D_BODY_KINEMATIC, x, F3D_R(0.5), 0, 0);
  f3d_body_set_shape(w, p, F3D_SHAPE_BOX, F3D_R(0.1), F3D_R(0.5), F3D_R(0.5));
  return p;
}

static void test_kinematic(void) {
  /* A kinematic body goes where it is sent, at the speed it is given:
   * gravity does not pull it and nothing it meets holds it back. It pushes
   * a box in its way along — waking it, though the box had gone to sleep —
   * and passes through a wall, which nothing can move either. */
  F3dWorld *w = f3d_world_create();
  const F3dBody floor = f3d_body_create(w, F3D_BODY_FIXED, 0, F3D_R(-0.5), 0, 0);
  f3d_body_set_shape(w, floor, F3D_SHAPE_BOX, 20, F3D_R(0.5), 20);
  const F3dBody box = f3d_body_create(w, F3D_BODY_DYNAMIC, 2, F3D_R(0.25), 0, 5);
  f3d_body_set_shape(w, box, F3D_SHAPE_BOX, F3D_R(0.25), F3D_R(0.25), F3D_R(0.25));
  const F3dBody wall = f3d_body_create(w, F3D_BODY_FIXED, 6, F3D_R(0.5), 0, 0);
  f3d_body_set_shape(w, wall, F3D_SHAPE_BOX, F3D_R(0.1), F3D_R(0.5), F3D_R(0.5));
  const F3dBody p = paddle(w, 0);
  for (int i = 0; i < 240; i++) f3d_world_step(w, F3D_R(1.0) / 60);
  CHECK(f3d_body_is_asleep(w, box) == 1);
  CHECK(f3d_body_set_velocity(w, p, 1, 0, 0) == 1);
  for (int i = 0; i < 60 * 4; i++) f3d_world_step(w, F3D_R(1.0) / 60);
  f3d_real at[3], v[3], b[3];
  f3d_body_get_position(w, box, b);
  /* The box went ahead of it, at least as far as the paddle's face. */
  CHECK(f3d_body_is_asleep(w, box) == 0);
  CHECK(b[0] > F3D_R(4.3));
  /* Taken away before the wall would pin it there. */
  f3d_body_destroy(w, box);
  for (int i = 0; i < 60 * 4; i++) f3d_world_step(w, F3D_R(1.0) / 60);
  f3d_body_get_position(w, p, at);
  f3d_body_get_velocity(w, p, v);
  CHECK_NEAR(at[0], 8, 1e-3);
  CHECK_NEAR(at[1], 0.5, 1e-6);
  CHECK(v[0] == 1 && v[1] == 0);
  /* Sent to a pose: there after the step, turned a quarter about y. */
  const f3d_real h = F3D_R(0.70710678);
  CHECK(f3d_body_move_kinematic(w, floor, 0, 0, 0, 0, 0, 0, 1, 1) == 0);
  CHECK(f3d_body_move_kinematic(w, p, 9, F3D_R(0.5), 3, 0, 0, 0, 0, 1) == 0);
  CHECK(f3d_body_move_kinematic(w, p, 9, F3D_R(0.5), 3, 0, h, 0, h, F3D_R(0.5)) == 1);
  for (int i = 0; i < 30; i++) f3d_world_step(w, F3D_R(1.0) / 60);
  f3d_real q[4];
  f3d_body_get_position(w, p, at);
  f3d_body_get_orientation(w, p, q);
  CHECK_NEAR(at[0], 9, 1e-3);
  CHECK_NEAR(at[2], 3, 1e-3);
  CHECK_NEAR(fabs((double)q[1]), h, 2e-3);
  CHECK_NEAR(fabs((double)q[3]), h, 2e-3);
  f3d_world_destroy(w);
}

int main(void) {
  test_kinematic();
  test_inertia();
  test_turning();
  test_impulses_and_forces();
  test_damping();
  test_drag();
  test_wind_carries();
  test_sleep();
  return finish();
}
