/*
 * The laws of motion a rigid body keeps, tested in C against their closed
 * forms: a fall under gravity alone; the acceleration of a sum of forces,
 * F = m a; a torque's change of angular momentum, dL/dt = τ, about an axis
 * that is not a principal one; momentum, angular momentum and energy kept
 * through a glancing elastic collision; Archimedes' push on a body under
 * water and on one floating; Coulomb's friction on a slope; and a
 * pendulum's period.
 */
#include <math.h>
#include <stdlib.h>

#include "check.h"

/* Water's density as a pool starts, kg/m³: the catalogue's. */
static const double WATER = (double)F3D_MAT_WATER_DENSITY;

static F3dWorld *vacuum(void) {
  F3dWorld *w = f3d_world_create();
  /* Air too thin to slow anything; not nought, which the world refuses. */
  f3d_world_set_air(w, F3D_STANDARD_AIR_TEMPERATURE, F3D_R(1e-30));
  f3d_world_set_sleep(w, 0, 0);
  return w;
}

static void run(F3dWorld *w, int steps, f3d_real dt) {
  for (int i = 0; i < steps; i++) f3d_world_step(w, dt);
}

static void test_free_fall(void) {
  /* Dropped from rest, a body is falling at g·t after t, and has fallen
   * g·t²/2 — within the half step the integrator lags it. */
  F3dWorld *w = vacuum();
  const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 100, 0, 3);
  f3d_body_set_shape(w, b, F3D_SHAPE_SPHERE, F3D_R(0.2), 0, 0);
  run(w, 120, F3D_R(1.0) / 120);
  f3d_real v[3], p[3];
  f3d_body_get_velocity(w, b, v);
  f3d_body_get_position(w, b, p);
  CHECK_NEAR(-v[1], world_gravity(w), 1e-4);
  CHECK_NEAR(100 - p[1], 0.5 * world_gravity(w), 0.01);
  f3d_world_destroy(w);
}

static void test_sum_of_forces(void) {
  /* Three forces on four kilograms, and gravity: the body accelerates at
   * their sum over its mass, every step it is pushed. */
  F3dWorld *w = vacuum();
  const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 4);
  f3d_body_set_shape(w, b, F3D_SHAPE_BOX, F3D_R(0.5), F3D_R(0.5), F3D_R(0.5));
  for (int i = 0; i < 60; i++) {
    f3d_body_add_force(w, b, 10, 0, 0);
    f3d_body_add_force(w, b, -2, 30, 0);
    f3d_body_add_force(w, b, 0, 0, 8);
    f3d_world_step(w, F3D_R(1.0) / 60);
  }
  f3d_real v[3];
  f3d_body_get_velocity(w, b, v);
  /* One second: (8, 30 − 4g, 8) / 4. */
  CHECK_NEAR(v[0], 8.0 / 4, 1e-4);
  CHECK_NEAR(v[1], (30 - 4 * world_gravity(w)) / 4, 1e-4);
  CHECK_NEAR(v[2], 8.0 / 4, 1e-4);
  f3d_world_destroy(w);
}

/* The body's angular momentum in the world's frame: R I Rᵀ ω. */
static void momentum(F3dWorld *w, F3dBody b, double out[3]) {
  f3d_real t[6], q[4], s[3];
  f3d_body_get_inertia_tensor(w, b, t);
  f3d_body_get_orientation(w, b, q);
  f3d_body_get_angular_velocity(w, b, s);
  const double x = q[0], y = q[1], z = q[2], qw = q[3];
  const double r[3][3] = {
      {1 - 2 * (y * y + z * z), 2 * (x * y - z * qw), 2 * (x * z + y * qw)},
      {2 * (x * y + z * qw), 1 - 2 * (x * x + z * z), 2 * (y * z - x * qw)},
      {2 * (x * z - y * qw), 2 * (y * z + x * qw), 1 - 2 * (x * x + y * y)}};
  const double ib[3][3] = {{t[0], t[3], t[4]}, {t[3], t[1], t[5]}, {t[4], t[5], t[2]}};
  /* Rᵀω, then I times it, then R back. */
  double wb[3], lb[3];
  for (int i = 0; i < 3; i++) wb[i] = r[0][i] * s[0] + r[1][i] * s[1] + r[2][i] * s[2];
  for (int i = 0; i < 3; i++) lb[i] = ib[i][0] * wb[0] + ib[i][1] * wb[1] + ib[i][2] * wb[2];
  for (int i = 0; i < 3; i++) out[i] = r[i][0] * lb[0] + r[i][1] * lb[1] + r[i][2] * lb[2];
}

static void test_torque_changes_angular_momentum(void) {
  /* A brick turning about no principal axis, a steady torque on it: its
   * angular momentum grows by the torque times the time, whatever its
   * spin does meanwhile. */
  F3dWorld *w = vacuum();
  f3d_world_set_gravity(w, 0, 0, 0);
  const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 2);
  f3d_body_set_shape(w, b, F3D_SHAPE_BOX, F3D_R(0.1), F3D_R(0.3), F3D_R(0.6));
  f3d_body_set_angular_velocity(w, b, 1, F3D_R(0.5), F3D_R(-0.3));
  double l0[3];
  momentum(w, b, l0);
  const double tau[3] = {0.2, -0.1, 0.05};
  const int steps = 240;
  for (int i = 0; i < steps; i++) {
    f3d_body_add_torque(w, b, F3D_R(tau[0]), F3D_R(tau[1]), F3D_R(tau[2]));
    f3d_world_step(w, F3D_R(1.0) / 240);
  }
  double l1[3];
  momentum(w, b, l1);
  for (int k = 0; k < 3; k++) CHECK_NEAR(l1[k], l0[k] + tau[k] * 1.0, 0.01);
  f3d_world_destroy(w);
}

static double kinetic(F3dWorld *w, F3dBody b) {
  f3d_real v[3], m;
  f3d_body_get_velocity(w, b, v);
  f3d_body_get_mass(w, b, &m);
  double l[3];
  momentum(w, b, l);
  f3d_real s[3];
  f3d_body_get_angular_velocity(w, b, s);
  return 0.5 * m * (v[0] * v[0] + v[1] * v[1] + v[2] * v[2]) +
         0.5 * (l[0] * s[0] + l[1] * s[1] + l[2] * s[2]);
}

static void test_glancing_collision_keeps_what_it_should(void) {
  /* A ball sent past another's side, no gravity, elastic: what the two
   * carry in momentum, in angular momentum about the origin — each one's
   * own spin and its momentum's moment — and in energy is what they
   * carried before. */
  F3dWorld *w = vacuum();
  f3d_world_set_gravity(w, 0, 0, 0);
  const F3dBody a = f3d_body_create(w, F3D_BODY_DYNAMIC, -2, F3D_R(0.25), 0, 1);
  const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 3);
  f3d_body_set_shape(w, a, F3D_SHAPE_SPHERE, F3D_R(0.3), 0, 0);
  f3d_body_set_shape(w, b, F3D_SHAPE_BOX, F3D_R(0.3), F3D_R(0.3), F3D_R(0.3));
  f3d_body_set_restitution(w, a, 1);
  f3d_body_set_restitution(w, b, 1);
  f3d_body_set_friction(w, a, 0);
  f3d_body_set_friction(w, b, 0);
  f3d_body_set_velocity(w, a, 4, 0, 0);
  double before_p[3] = {0, 0, 0}, before_l[3] = {0, 0, 0};
  double after_p[3] = {0, 0, 0}, after_l[3] = {0, 0, 0};
  const F3dBody both[2] = {a, b};
  for (int pass = 0; pass < 2; pass++) {
    double *p = pass ? after_p : before_p, *l = pass ? after_l : before_l;
    for (int k = 0; k < 2; k++) {
      f3d_real x[3], v[3], m;
      f3d_body_get_position(w, both[k], x);
      f3d_body_get_velocity(w, both[k], v);
      f3d_body_get_mass(w, both[k], &m);
      double spin[3];
      momentum(w, both[k], spin);
      for (int i = 0; i < 3; i++) p[i] += m * v[i];
      l[0] += m * (x[1] * v[2] - x[2] * v[1]) + spin[0];
      l[1] += m * (x[2] * v[0] - x[0] * v[2]) + spin[1];
      l[2] += m * (x[0] * v[1] - x[1] * v[0]) + spin[2];
    }
    if (!pass) run(w, 120, F3D_R(1.0) / 120);
  }
  const double e = kinetic(w, a) + kinetic(w, b);
  for (int i = 0; i < 3; i++) {
    CHECK_NEAR(after_p[i], before_p[i], 1e-3);
    CHECK_NEAR(after_l[i], before_l[i], 0.02);
  }
  /* Elastic: the energy it came in with, but for the little the contact's
   * softness spends. */
  CHECK_NEAR(e, 0.5 * 1 * 16, 0.05 * 8);
  /* And the box was hit: it moves and it turns. */
  f3d_real vb[3];
  f3d_body_get_velocity(w, b, vb);
  CHECK(vb[0] > F3D_R(0.3));
  f3d_world_destroy(w);
}

/* A still pool [depth] deep over a flat floor at nought. */
static F3dShallow pool(F3dWorld *w, f3d_real depth) {
  f3d_real *ground = (f3d_real *)calloc(24 * 24, sizeof(f3d_real));
  const F3dShallow water = f3d_shallow_create(w, 24, 24, F3D_R(0.5), 0, 0, 0, ground);
  free(ground);
  f3d_shallow_fill(w, water, -9, -9, 99, 99, depth);
  return water;
}

static void test_archimedes_under_water(void) {
  /* A ball of stone held deep in water and let go: what moves it is its
   * weight less the weight of the water it displaces, ρVg, and what it must
   * set moving is its mass and half that water's. */
  F3dWorld *w = vacuum();
  pool(w, 6);
  const double r = 0.25, volume = 4.0 / 3.0 * M_PI * r * r * r;
  const double mass = 2600 * volume;
  const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, 6, 3, 6, F3D_R(mass));
  f3d_body_set_shape(w, b, F3D_SHAPE_SPHERE, F3D_R(r), 0, 0);
  const f3d_real dt = F3D_R(1.0) / 480;
  f3d_world_step(w, dt);
  f3d_real v[3];
  f3d_body_get_velocity(w, b, v);
  const double a = (mass - WATER * volume) * world_gravity(w) / (mass + 0.5 * WATER * volume);
  CHECK_NEAR(-v[1], a * (double)dt, 0.03 * a * (double)dt);
  f3d_world_destroy(w);
}

static void test_archimedes_afloat(void) {
  /* A ball of half water's density laid on still water five centimetres
   * high comes to rest with half of it under, its middle at the water's
   * surface round it: the water it displaces weighs what it weighs. Let
   * fall from higher it would ride the waves its own splash made for as
   * long as a closed pool keeps them, still at the surface's level. */
  F3dWorld *w = vacuum();
  const F3dShallow water = pool(w, 4);
  const double r = 0.3, volume = 4.0 / 3.0 * M_PI * r * r * r;
  const F3dBody b =
      f3d_body_create(w, F3D_BODY_DYNAMIC, 6, F3D_R(4.05), 6, F3D_R(0.5 * WATER * volume));
  f3d_body_set_shape(w, b, F3D_SHAPE_SPHERE, F3D_R(r), 0, 0);
  run(w, 60 * 20, F3D_R(1.0) / 60);
  f3d_real p[3], v[3], here[8];
  f3d_body_get_position(w, b, p);
  f3d_body_get_velocity(w, b, v);
  CHECK(f3d_shallow_sample(w, water, p[0], p[2], here) == 1);
  CHECK_NEAR(p[1], here[0], 0.02);
  CHECK(fabs((double)v[1]) < 0.03);
  f3d_world_destroy(w);
}

static void test_coulomb_on_a_slope(void) {
  /* A box on a plane tilted θ, friction μ between them: it stays where
   * tan θ < μ, and where tan θ > μ slides down at g (sin θ − μ cos θ). */
  for (int steep = 0; steep < 2; steep++) {
    F3dWorld *w = vacuum();
    const double theta = steep ? 0.5 : 0.2, mu = 0.4;
    const F3dBody slope = f3d_body_create(w, F3D_BODY_FIXED, 0, 0, 0, 0);
    f3d_body_set_shape(w, slope, F3D_SHAPE_BOX, 20, F3D_R(0.5), 5);
    f3d_body_set_orientation(w, slope, 0, 0, F3D_R(sin(theta / 2)), F3D_R(cos(theta / 2)));
    f3d_body_set_friction(w, slope, F3D_R(mu));
    const F3dBody box = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 5);
    f3d_body_set_shape(w, box, F3D_SHAPE_BOX, F3D_R(0.25), F3D_R(0.25), F3D_R(0.25));
    f3d_body_set_friction(w, box, F3D_R(mu));
    f3d_body_set_orientation(w, box, 0, 0, F3D_R(sin(theta / 2)), F3D_R(cos(theta / 2)));
    /* On the plane's top face, a little in from its middle. */
    const double n[2] = {-sin(theta), cos(theta)};
    f3d_body_set_position(w, box, F3D_R(n[0] * 0.751), F3D_R(n[1] * 0.751), 0);
    run(w, 60, F3D_R(1.0) / 120);
    f3d_real v0[3];
    f3d_body_get_velocity(w, box, v0);
    run(w, 120, F3D_R(1.0) / 120);
    f3d_real v1[3];
    f3d_body_get_velocity(w, box, v1);
    const double speed0 = sqrt(v0[0] * v0[0] + v0[1] * v0[1]);
    const double speed1 = sqrt(v1[0] * v1[0] + v1[1] * v1[1]);
    if (steep) {
      const double a = world_gravity(w) * (sin(theta) - mu * cos(theta));
      CHECK_NEAR(speed1 - speed0, a * 1.0, 0.04 * a);
    } else {
      CHECK(speed1 < 0.01);
    }
    f3d_world_destroy(w);
  }
}

static void test_pendulum_period(void) {
  /* A small bob on a metre of rod, let go at five degrees: it swings with
   * period 2π √(L/g), and comes back up as high as it started. */
  F3dWorld *w = vacuum();
  const F3dBody pin = f3d_body_create(w, F3D_BODY_FIXED, 0, 10, 0, 0);
  f3d_body_set_shape(w, pin, F3D_SHAPE_SPHERE, F3D_R(0.01), 0, 0);
  const double amp = 5.0 * M_PI / 180.0, len = 1.0;
  const F3dBody bob = f3d_body_create(w, F3D_BODY_DYNAMIC, F3D_R(len * sin(amp)),
                                      F3D_R(10 - len * cos(amp)), 0, 1);
  f3d_body_set_shape(w, bob, F3D_SHAPE_SPHERE, F3D_R(0.02), 0, 0);
  f3d_body_set_collision_filter(w, bob, 1, 0);
  CHECK(f3d_joint_create_distance(w, pin, bob, 0, 10, 0, F3D_R(len * sin(amp)),
                                  F3D_R(10 - len * cos(amp)), 0) != 0);
  /* Times it crosses the middle going the way it first went: a period
   * apart. */
  const f3d_real dt = F3D_R(1.0) / 480;
  double crossings[3];
  int found = 0;
  f3d_real was[3];
  f3d_body_get_position(w, bob, was);
  double highest_late = 0.0;
  for (int i = 0; i < 480 * 8 && found < 3; i++) {
    f3d_world_step(w, dt);
    f3d_real p[3];
    f3d_body_get_position(w, bob, p);
    if (was[0] > 0 && p[0] <= 0) {
      crossings[found++] = (i + 1) * (double)dt - (double)dt * p[0] / (p[0] - was[0]);
    }
    if (found == 2) highest_late = fmax(highest_late, (double)p[1]);
    was[0] = p[0];
  }
  CHECK(found == 3);
  const double period = 2.0 * M_PI * sqrt(len / world_gravity(w));
  /* Within a part in two hundred: the small-angle formula itself is off
   * by 0.05% at five degrees. */
  CHECK_NEAR((crossings[2] - crossings[0]) / 2.0, period, 0.005 * period);
  CHECK_NEAR(highest_late, 10 - len * cos(amp), 0.002);
  f3d_world_destroy(w);
}

int main(void) {
  test_free_fall();
  test_sum_of_forces();
  test_torque_changes_angular_momentum();
  test_glancing_collision_keeps_what_it_should();
  test_archimedes_under_water();
  test_archimedes_afloat();
  test_coulomb_on_a_slope();
  test_pendulum_period();
  return finish();
}
