/*
 * Continuous collision, tested in C — P9, phase 8: a fast ball through a
 * thin wall without it and stopped with it, a bullet stopped by a box and
 * by a mesh, a fast ball passing close by a box and not slowed, two fast
 * balls meeting head on, a bullet free to roll on a floor, a fast ball onto
 * a mesh floor, and an elastic bounce at fifty metres a second.
 */
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "check.h"

static F3dWorld *quiet(int speculative) {
  F3dWorld *w = f3d_world_create();
  f3d_world_set_gravity(w, 0, 0, 0);
  f3d_world_set_air(w, F3D_STANDARD_AIR_TEMPERATURE, F3D_R(1e-30));
  f3d_world_set_sleep(w, 0, 0);
  f3d_world_set_speculative(w, speculative);
  return w;
}

static F3dBody ball(F3dWorld *w, f3d_real x, f3d_real y, f3d_real r) {
  const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, x, y, 0, 1);
  f3d_body_set_shape(w, b, F3D_SHAPE_SPHERE, r, 0, 0);
  return b;
}

static F3dBody wall(F3dWorld *w) {
  /* A centimetre thick, at x = 0. */
  const F3dBody b = f3d_body_create(w, F3D_BODY_FIXED, 0, 0, 0, 0);
  f3d_body_set_shape(w, b, F3D_SHAPE_BOX, F3D_R(0.005), 2, 2);
  return b;
}

static void run(F3dWorld *w, int steps) {
  for (int i = 0; i < steps; i++) f3d_world_step(w, F3D_R(1.0 / 60.0));
}

static f3d_real x_of(F3dWorld *w, F3dBody b) {
  f3d_real p[3];
  f3d_body_get_position(w, b, p);
  return p[0];
}

static void test_thin_wall(void) {
  /* Three hundred metres a second, five metres a step: without soft
   * collision the ball is past the wall before any contact sees it. */
  for (int soft = 0; soft < 2; soft++) {
    F3dWorld *w = quiet(soft);
    wall(w);
    const F3dBody b = ball(w, -2, 0, F3D_R(0.05));
    f3d_body_set_velocity(w, b, 300, 0, 0);
    run(w, 10);
    if (soft) {
      CHECK(x_of(w, b) < 0);
      CHECK(x_of(w, b) > -0.06);
    } else {
      CHECK(x_of(w, b) > 1);
    }
    f3d_world_destroy(w);
  }
}

static void test_bullets(void) {
  /* With soft collision off, a bullet still stops: swept to its time of
   * impact, against a box and against a mesh one triangle thick. */
  F3dWorld *w = quiet(0);
  wall(w);
  const F3dBody b = ball(w, -2, 0, F3D_R(0.05));
  CHECK(f3d_body_set_bullet(w, b, 1) == 1);
  f3d_body_set_velocity(w, b, 500, 0, 0);
  run(w, 10);
  CHECK(x_of(w, b) < 0);
  CHECK(x_of(w, b) > -0.07);
  /* A mesh wall at x = 10, facing the bullet: wound counter-clockwise
   * seen from −x. */
  const f3d_real v[12] = {10, -2, -2, 10, 2, -2, 10, 2, 2, 10, -2, 2};
  const uint32_t t[6] = {0, 2, 1, 0, 3, 2};
  const uint32_t mesh = f3d_world_create_mesh(w, v, 4, t, 2);
  const F3dBody screen = f3d_body_create(w, F3D_BODY_FIXED, 0, 0, 0, 0);
  f3d_body_set_mesh(w, screen, mesh);
  const F3dBody c = ball(w, 5, 5, F3D_R(0.05));
  f3d_body_set_bullet(w, c, 1);
  f3d_body_set_position(w, c, 5, 0, 0);
  f3d_body_set_velocity(w, c, 500, 0, 0);
  run(w, 10);
  CHECK(x_of(w, c) < 10);
  CHECK(x_of(w, c) > 9.93);
  /* Leaving a wall it is near — five centimetres off, inside the wall's
   * leaf, so the sweep looks at it — a bullet is not called back to it:
   * moving away is no impact. */
  const F3dBody e = ball(w, F3D_R(-0.1), 3, F3D_R(0.05));
  f3d_body_set_bullet(w, e, 1);
  f3d_body_set_position(w, e, F3D_R(-0.1), 0, F3D_R(1.5));
  f3d_body_set_velocity(w, e, -300, 0, 0);
  run(w, 2);
  CHECK(x_of(w, e) < -9);
  /* Not a bullet, it goes through. */
  const F3dBody d = ball(w, 5, 1, F3D_R(0.05));
  f3d_body_set_velocity(w, d, 500, 0, 0);
  run(w, 10);
  CHECK(x_of(w, d) > 11);
  f3d_world_destroy(w);
}

/* The most either end of a bar a metre either side of its centre along its
 * own x reaches past the plane x = 0.5. */
static double past_wall(F3dWorld *w, F3dBody bar) {
  f3d_real q[4], p[3];
  f3d_body_get_orientation(w, bar, q);
  f3d_body_get_position(w, bar, p);
  const F3dQuat qq = {q[0], q[1], q[2], q[3]};
  const F3dMat3 m = f3d_mat_of(qq);
  const double a = (double)p[0] + m.c[0].x, b = (double)p[0] - m.c[0].x;
  return fmax(a, b) - 0.5;
}

static void test_spinning_bullet(void) {
  /* A bar two metres long spun at three hundred radians a second about
   * its middle — held to 188 by the bound on a substep's turn, three radians
   * a step, more than the half turn its first and last turns would
   * read the short way round, backwards — beside a wall half a metre off:
   * its ends would turn through the wall in a step. Swept along its path,
   * place and turn, it never reaches past the wall; it strikes it with its
   * end and is thrown back, as a spun bar is. Not a bullet, it turns
   * through. */
  for (int bullet = 0; bullet < 2; bullet++) {
    F3dWorld *w = quiet(0);
    const F3dBody screen = f3d_body_create(w, F3D_BODY_FIXED, F3D_R(0.5), 0, 0, 0);
    f3d_body_set_shape(w, screen, F3D_SHAPE_BOX, F3D_R(0.005), 2, 2);
    const F3dBody bar = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 1);
    f3d_body_set_shape(w, bar, F3D_SHAPE_BOX, 1, F3D_R(0.1), F3D_R(0.1));
    /* Lying along z, clear of the wall, turning about y. */
    const f3d_real c = F3D_R(0.70710678), q = F3D_R(0.70710678);
    f3d_body_set_orientation(w, bar, 0, q, 0, c);
    f3d_body_set_angular_velocity(w, bar, 0, 300, 0);
    f3d_body_set_bullet(w, bar, bullet);
    double most = -1;
    for (int i = 0; i < 20; i++) {
      f3d_world_step(w, F3D_R(1.0 / 60.0));
      const double past = past_wall(w, bar);
      if (past > most) most = past;
    }
    if (bullet) {
      CHECK(most < 0.02);
    } else {
      CHECK(most > 0.1);
    }
    f3d_world_destroy(w);
  }
}

static void test_no_ghosts(void) {
  /* A hundred metres a second, half a metre beside a box, parallel to its
   * face: the contact soft collision makes there pushes nothing, and the
   * ball goes by at full speed. */
  F3dWorld *w = quiet(1);
  const F3dBody block = f3d_body_create(w, F3D_BODY_FIXED, 0, 0, 0, 0);
  f3d_body_set_shape(w, block, F3D_SHAPE_BOX, 1, F3D_R(0.5), 1);
  const F3dBody b = ball(w, -5, F3D_R(1.1), F3D_R(0.1));
  f3d_body_set_velocity(w, b, 100, 0, 0);
  run(w, 10);
  f3d_real v[3], p[3];
  f3d_body_get_velocity(w, b, v);
  f3d_body_get_position(w, b, p);
  CHECK_NEAR(v[0], 100, 1e-4);
  CHECK_NEAR(v[1], 0, 1e-4);
  CHECK_NEAR(p[1], 1.1, 1e-5);
  CHECK(p[0] > 5);
  f3d_world_destroy(w);
}

static void test_head_on(void) {
  /* Two balls at two hundred metres a second each, straight at each
   * other: with soft collision they meet; without, they pass. */
  for (int soft = 0; soft < 2; soft++) {
    F3dWorld *w = quiet(soft);
    const F3dBody a = ball(w, -3, 0, F3D_R(0.1));
    const F3dBody b = ball(w, 3, 0, F3D_R(0.1));
    f3d_body_set_velocity(w, a, 200, 0, 0);
    f3d_body_set_velocity(w, b, -200, 0, 0);
    run(w, 6);
    if (soft) {
      CHECK(x_of(w, a) < x_of(w, b));
    } else {
      CHECK(x_of(w, a) > x_of(w, b));
    }
    f3d_world_destroy(w);
  }
}

static void test_bullet_rolls(void) {
  /* A bullet resting on a floor and pushed along it: it is not held at
   * where each step began. */
  F3dWorld *w = f3d_world_create();
  f3d_world_set_air(w, F3D_STANDARD_AIR_TEMPERATURE, F3D_R(1e-30));
  f3d_world_set_sleep(w, 0, 0);
  const F3dBody floor = f3d_body_create(w, F3D_BODY_FIXED, 0, F3D_R(-0.5), 0, 0);
  f3d_body_set_shape(w, floor, F3D_SHAPE_BOX, 50, F3D_R(0.5), 50);
  const F3dBody b = ball(w, 0, F3D_R(0.1), F3D_R(0.1));
  f3d_body_set_bullet(w, b, 1);
  run(w, 30);
  f3d_body_set_velocity(w, b, 10, 0, 0);
  run(w, 60);
  CHECK(x_of(w, b) > 5);
  f3d_real p[3];
  f3d_body_get_position(w, b, p);
  CHECK(fabs((double)p[1] - 0.1) < 0.006);
  f3d_world_destroy(w);
}

static void test_onto_a_mesh(void) {
  /* Dropped onto a one-triangle-thick mesh floor at a hundred metres a
   * second: it stops on it. */
  F3dWorld *w = f3d_world_create();
  f3d_world_set_air(w, F3D_STANDARD_AIR_TEMPERATURE, F3D_R(1e-30));
  const f3d_real v[12] = {-5, 0, -5, 5, 0, -5, 5, 0, 5, -5, 0, 5};
  const uint32_t t[6] = {0, 2, 1, 0, 3, 2};
  const uint32_t mesh = f3d_world_create_mesh(w, v, 4, t, 2);
  const F3dBody ground = f3d_body_create(w, F3D_BODY_FIXED, 0, 0, 0, 0);
  f3d_body_set_mesh(w, ground, mesh);
  const F3dBody b = ball(w, F3D_R(0.3), 10, F3D_R(0.1));
  f3d_body_set_velocity(w, b, 0, -100, 0);
  run(w, 120);
  f3d_real p[3];
  f3d_body_get_position(w, b, p);
  CHECK(fabs((double)p[1] - 0.1) < 0.01);
  f3d_world_destroy(w);
}

static void test_fast_bounce(void) {
  /* Elastic, at fifty metres a second at the wall: it comes back at fifty,
   * not stopped and not through. */
  F3dWorld *w = quiet(1);
  wall(w);
  const F3dBody b = ball(w, -3, 0, F3D_R(0.1));
  f3d_body_set_restitution(w, b, 1);
  f3d_body_set_velocity(w, b, 50, 0, 0);
  run(w, 30);
  f3d_real v[3];
  f3d_body_get_velocity(w, b, v);
  CHECK_NEAR(v[0], -50, 0.02);
  CHECK(x_of(w, b) < 0);
  f3d_world_destroy(w);
}

int main(void) {
  test_thin_wall();
  test_bullets();
  test_spinning_bullet();
  test_no_ghosts();
  test_head_on();
  test_bullet_rolls();
  test_onto_a_mesh();
  test_fast_bounce();
  return finish();
}
