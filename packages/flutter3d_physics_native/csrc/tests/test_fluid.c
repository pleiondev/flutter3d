/*
 * Fluid on the CPU, tested in C — P9, phase 10: rest density is what the
 * kernel sums to on a lattice, a lone particle falls as semi-implicit
 * Euler sums, viscosity takes the slide of two that pass, a dam of a
 * thousand breaks and reaches the far wall, and settles as deep as its
 * volume over the tank's floor, inside the tank, squeezed by a few per
 * cent at most, no flatter at the floor, its sloshing dying down; slots
 * fill round and round, and bad input is refused.
 */
#include <math.h>
#include <string.h>

#include "check.h"

static F3dFluidSettings settings(void) {
  F3dFluidSettings s;
  memset(&s, 0, sizeof s);
  s.gravity[1] = F3D_R(-9.81);
  s.tank_min[0] = F3D_R(-0.5);
  s.tank_min[2] = F3D_R(-0.25);
  s.tank_max[0] = F3D_R(0.5);
  s.tank_max[1] = F3D_R(10.0);
  s.tank_max[2] = F3D_R(0.25);
  s.viscosity = F3D_R(0.01);
  s.relaxation = F3D_R(10.0);
  s.substeps = 2;
  s.iterations = 4;
  return s;
}

static void run(F3dFluid *f, const F3dFluidSettings *s, int steps) {
  for (int i = 0; i < steps; i++) f3d_fluid_step(f, s, F3D_R(1.0 / 60.0));
}

/* The mean speed over a tenth of a second from now. */
static double mean_speed(F3dFluid *f, const F3dFluidSettings *s, uint32_t n, f3d_real *a,
                         f3d_real *b) {
  f3d_fluid_read(f, a, n);
  run(f, s, 6);
  f3d_fluid_read(f, b, n);
  double sum = 0;
  for (uint32_t i = 0; i < n; i++) {
    double v2 = 0;
    for (int k = 0; k < 3; k++) v2 += pow(((double)b[i * 4 + k] - a[i * 4 + k]) * 10.0, 2);
    sum += sqrt(v2);
  }
  return sum / n;
}

static void test_rest_density(void) {
  /* Poly6 over a lattice of 5 cm, its kernel 10 cm wide: the 33 points
   * within reach. */
  F3dFluid *f = f3d_fluid_create(4, F3D_R(0.05));
  CHECK(f != NULL && f3d_fluid_capacity(f) == 4);
  const double h = 0.1, pi = 3.14159265358979323846;
  double rest = 0;
  for (int x = -2; x <= 2; x++) {
    for (int y = -2; y <= 2; y++) {
      for (int z = -2; z <= 2; z++) {
        const double d = h * h - (x * x + y * y + z * z) * 0.0025;
        if (d > 0) rest += 315.0 / (64.0 * pi * pow(h, 9)) * d * d * d;
      }
    }
  }
  /* CHECK_NEAR scales its tolerance by values past one: a part in 10⁵. */
  CHECK_NEAR(f3d_fluid_rest_density(f), rest, 1e-5);
  f3d_fluid_destroy(f);
}

static void test_lone_particle(void) {
  /* Nothing near it: its own density is short of rest, so nothing pushes
   * it, and it falls as gravity sums in substeps of a hundred-and-
   * twentieth. */
  F3dFluid *f = f3d_fluid_create(1, F3D_R(0.05));
  const f3d_real in[6] = {0, 5, 0, F3D_R(0.5), 0, 0};
  CHECK(f3d_fluid_add(f, in, 1) == 0);
  const F3dFluidSettings s = settings();
  run(f, &s, 30);
  f3d_real out[4];
  CHECK(f3d_fluid_read(f, out, 1) == 1);
  const double h = 1.0 / 120.0;
  CHECK_NEAR(out[0], 0.5 * 60 * h, 1e-5);
  CHECK_NEAR(out[1], 5 - 9.81 * h * h * 60 * 61 / 2, 1e-4);
  CHECK(out[3] > 0 && out[3] < 0.5);
  f3d_fluid_destroy(f);
}

static void test_viscosity(void) {
  /* Two particles 6 cm apart sliding past each other at 2 cm/s each, no
   * gravity: too few to reach rest density, so nothing pushes them, and
   * only viscosity takes their slide. Without it they part 4 cm in a
   * second; at 0.5 each substep takes a twentieth of it, and they part
   * under a centimetre. */
  for (int viscous = 1; viscous >= 0; viscous--) {
    F3dFluid *f = f3d_fluid_create(2, F3D_R(0.05));
    const f3d_real in[12] = {0, 1, 0, 0, 0, F3D_R(0.02), F3D_R(0.06), 1, 0, 0, 0, F3D_R(-0.02)};
    f3d_fluid_add(f, in, 2);
    F3dFluidSettings s = settings();
    s.gravity[1] = 0;
    s.viscosity = viscous ? F3D_R(0.5) : F3D_R(0.0);
    run(f, &s, 60);
    f3d_real out[8];
    f3d_fluid_read(f, out, 2);
    const double parted = out[2] - out[6];
    if (viscous) {
      CHECK(parted < 0.01);
    } else {
      CHECK_NEAR(parted, 0.04, 1e-4);
    }
    /* Either way the pair's middle stays where it was. */
    CHECK_NEAR((out[2] + out[6]) / 2, 0, 1e-6);
    f3d_fluid_destroy(f);
  }
}

static void test_dam(void) {
  /* A block of 10³ particles 5 cm apart against one end of a tank a metre
   * long and half a metre wide: half a second on it reaches the far wall;
   * after three it lies 0.125 m³ / 0.5 m² = 25 cm deep, its centre of mass
   * half that up, and sloshes at under three fifths of its speed at one
   * second. */
  enum { N = 1000 };
  F3dFluid *f = f3d_fluid_create(N, F3D_R(0.05));
  static f3d_real in[N * 6], out[N * 4], later[N * 4];
  for (int i = 0; i < N; i++) {
    f3d_real *o = in + i * 6;
    o[0] = F3D_R(-0.475) + (f3d_real)(i % 10) * F3D_R(0.05);
    o[1] = F3D_R(0.025) + (f3d_real)(i / 100) * F3D_R(0.05);
    o[2] = F3D_R(-0.225) + (f3d_real)((i / 10) % 10) * F3D_R(0.05);
    o[3] = o[4] = o[5] = 0;
  }
  f3d_fluid_add(f, in, N);
  const F3dFluidSettings s = settings();
  run(f, &s, 30);
  f3d_fluid_read(f, out, N);
  double front = -1;
  for (int i = 0; i < N; i++) front = fmax(front, (double)out[i * 4]);
  CHECK(front > 0.47);
  run(f, &s, 30);
  const double sloshing = mean_speed(f, &s, N, out, later);
  run(f, &s, 114);
  const double calmer = mean_speed(f, &s, N, out, later);
  double height = 0, mean = 0, densest = 0;
  int outside = 0, floor_layer = 0;
  for (int i = 0; i < N; i++) {
    const f3d_real *p = out + i * 4;
    height += p[1];
    floor_layer += p[1] < 0.05;
    mean += p[3];
    densest = fmax(densest, (double)p[3]);
    if (p[0] < -0.475 - 1e-6 || p[0] > 0.475 + 1e-6 || p[1] < 0.025 - 1e-6 || p[2] < -0.225 - 1e-6 ||
        p[2] > 0.225 + 1e-6) {
      outside++;
    }
  }
  mean /= N;
  height /= N;
  CHECK(outside == 0);
  /* Its centre of mass half the depth up, sloshing or not. */
  CHECK_NEAR(height, 0.125, 0.015);
  CHECK(mean > 0.9 && mean < 1.0);
  CHECK(densest < 1.08);
  /* A layer of the lattice is 20 × 10 = 200 particles. With nothing past
   * the floor to lean on, 325 were pressed into it. */
  CHECK(floor_layer < 230);
  CHECK(calmer < 0.6 * sloshing);
  f3d_fluid_destroy(f);
}

static void test_slots(void) {
  F3dFluid *f = f3d_fluid_create(2, F3D_R(0.1));
  const f3d_real in[18] = {1, 1, 1, 0, 0, 0, 2, 2, 2, 0, 0, 0, 3, 3, 3, 0, 0, 0};
  f3d_real out[8];
  CHECK(f3d_fluid_add(f, in, 1) == 0);
  CHECK(f3d_fluid_read(f, out, 2) == 1);
  CHECK(f3d_fluid_add(f, in + 6, 2) == 1);
  CHECK(f3d_fluid_read(f, out, 2) == 2);
  /* The third went into the first slot. */
  CHECK(out[0] == 3 && out[4] == 2);
  CHECK(f3d_fluid_create(0, F3D_R(0.1)) == NULL);
  CHECK(f3d_fluid_create(4, 0) == NULL);
  CHECK(f3d_fluid_create(4, nan_value()) == NULL);
  f3d_fluid_destroy(NULL);
  f3d_fluid_destroy(f);
}

int main(void) {
  test_rest_density();
  test_lone_particle();
  test_viscosity();
  test_dam();
  test_slots();
  return finish();
}
