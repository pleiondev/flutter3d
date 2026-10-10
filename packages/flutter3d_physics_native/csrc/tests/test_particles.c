/*
 * Particles on the CPU, tested in C — P9, phase 10: a spark's flight is
 * semi-implicit Euler's to the bit, drag carries it to the wind, a floor
 * turns its fall back by the restitution, a slot is used again round and
 * round, and a dead particle is still.
 */
#include <string.h>

#include "check.h"

static F3dParticleForces calm(void) {
  F3dParticleForces f;
  memset(&f, 0, sizeof f);
  f.gravity[1] = -F3D_STANDARD_GRAVITY;
  f.floor_y = F3D_R(-1e9);
  return f;
}

static void test_flight(void) {
  /* Thrown at (3, 4, 0) m/s with no drag: after n steps of h,
   * x = 3 n h and y = 4 n h − g h² n(n + 1)/2, semi-implicit Euler's own
   * sums. */
  F3dParticles *p = f3d_particles_create(4);
  CHECK(p != NULL && f3d_particles_capacity(p) == 4);
  const f3d_real spark[7] = {0, 0, 0, 3, 4, 0, 10};
  CHECK(f3d_particles_emit(p, spark, 1) == 0);
  const F3dParticleForces f = calm();
  const int n = 60;
  const f3d_real h = F3D_R(1.0 / 60.0);
  for (int i = 0; i < n; i++) f3d_particles_step(p, &f, h);
  f3d_real out[16];
  CHECK(f3d_particles_read(p, out, 4) == 4);
  CHECK_NEAR(out[0], 3.0 * n * (double)h, 1e-5);
  CHECK_NEAR(out[1], 4.0 * n * (double)h - STANDARD_G * (double)h * (double)h * n * (n + 1) / 2, 1e-4);
  CHECK_NEAR(out[3], 10 - n * (double)h, 1e-5);
  /* The other slots were never alive and did not move. */
  CHECK(out[4] == 0 && out[7] == 0);
  f3d_particles_destroy(p);
}

static void test_drag_and_floor(void) {
  F3dParticles *p = f3d_particles_create(2);
  F3dParticleForces f = calm();
  f.gravity[1] = 0;
  f.wind[0] = 5;
  f.drag = 2;
  const f3d_real still[7] = {0, 0, 0, 0, 0, 0, 100};
  f3d_particles_emit(p, still, 1);
  for (int i = 0; i < 600; i++) f3d_particles_step(p, &f, F3D_R(1.0 / 60.0));
  f3d_real out[8];
  f3d_particles_read(p, out, 2);
  /* Ten seconds at two per second: the wind's speed, to a part in a
   * million; it travelled 5 t less the 5/2 it took to catch up. */
  CHECK_NEAR(out[0], 50 - 2.5, 0.05);
  f3d_particles_destroy(p);
  /* Dropped onto a floor at nought with restitution a half: it comes back
   * up at half the speed it hit at, and slides half as fast. */
  p = f3d_particles_create(1);
  f = calm();
  f.floor_y = 0;
  f.restitution = F3D_R(0.5);
  f.friction = F3D_R(0.5);
  const f3d_real drop[7] = {0, F3D_R(0.001), 0, 2, -10, 0, 100};
  f3d_particles_emit(p, drop, 1);
  f3d_particles_step(p, &f, F3D_R(1.0 / 60.0));
  f3d_particles_read(p, out, 1);
  CHECK(out[1] == 0);
  f3d_particles_step(p, &f, F3D_R(1.0 / 60.0));
  f3d_particles_read(p, out, 1);
  /* Up at (10 + g h)/2 less a step of gravity, for a sixtieth. */
  const double up = (10 + STANDARD_G / 60.0) / 2 - STANDARD_G / 60.0;
  CHECK_NEAR(out[1], up / 60.0, 1e-5);
  CHECK_NEAR(out[0], 2.0 / 60.0 + 1.0 / 60.0, 1e-5);
  f3d_particles_destroy(p);
}

static void test_slots_and_life(void) {
  F3dParticles *p = f3d_particles_create(3);
  const F3dParticleForces f = calm();
  const f3d_real a[7] = {1, 0, 0, 0, 0, 0, F3D_R(0.05)};
  const f3d_real b[14] = {2, 0, 0, 0, 0, 0, 10, 3, 0, 0, 0, 0, 0, 10};
  CHECK(f3d_particles_emit(p, a, 1) == 0);
  CHECK(f3d_particles_emit(p, b, 2) == 1);
  /* The fourth takes the first slot again: the oldest goes. */
  const f3d_real c[7] = {4, 0, 0, 0, 0, 0, F3D_R(0.04)};
  CHECK(f3d_particles_emit(p, c, 1) == 0);
  f3d_real out[12];
  f3d_particles_read(p, out, 3);
  CHECK(out[0] == 4);
  /* With a twenty-fifth of a second it dies in its third step of a
   * sixtieth, and then stays where it died. */
  for (int i = 0; i < 3; i++) f3d_particles_step(p, &f, F3D_R(1.0 / 60.0));
  f3d_particles_read(p, out, 3);
  CHECK(out[3] <= 0);
  const f3d_real fell = out[1];
  for (int i = 0; i < 30; i++) f3d_particles_step(p, &f, F3D_R(1.0 / 60.0));
  f3d_particles_read(p, out, 3);
  CHECK(out[1] == fell);
  CHECK(out[5] < -1);
  CHECK(f3d_particles_create(0) == NULL);
  f3d_particles_destroy(NULL);
  f3d_particles_destroy(p);
}

int main(void) {
  test_flight();
  test_drag_and_floor();
  test_slots_and_life();
  return finish();
}
