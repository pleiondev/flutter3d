/*
 * Liquid on the core, tested in C: a lone particle falls as semi-implicit
 * Euler sums, rests on a floor a radius up, keeps inside a glass it falls
 * into and off the foot of one it falls beside, and a block of them in a
 * box settles at its rest density; a parcel falls as the world falls, runs
 * along a wall it is thrown at, is drawn back to one it drifts off while
 * slow, and grows its ripples only in the air; a mode rings at gravity's
 * frequency, decays, and stands no higher than Stokes' limit; and records
 * of no kind, or cut short, are refused with nothing moved.
 */
#include <math.h>
#include <string.h>

#include "check.h"

static const double PI_D = 3.14159265358979323846;

/* The settings for particles [spacing] apart, with the lattice sums the
 * Dart side works out, of water with no cohesion. */
static F3dLiquidParticleSettings particle_settings(double spacing, double dt) {
  F3dLiquidParticleSettings s;
  memset(&s, 0, sizeof s);
  s.gravity[1] = F3D_R(-9.81);
  s.spacing = (f3d_real)spacing;
  s.density = F3D_R(998.2);
  s.kinematic_viscosity = F3D_R(1.0e-6);
  const double h = 2.0 * spacing;
  double sum = 0, gradient2 = 0;
  for (int a = -2; a <= 2; a++) {
    for (int b = -2; b <= 2; b++) {
      for (int c = -2; c <= 2; c++) {
        const double r2 = (double)(a * a + b * b + c * c) * spacing * spacing;
        if (r2 >= h * h) continue;
        const double d = h * h - r2;
        sum += 315.0 / (64.0 * PI_D * pow(h, 9)) * d * d * d;
        const double r = sqrt(r2);
        if (r > 1e-12) {
          const double f = 45.0 / (PI_D * pow(h, 6)) * (h - r) * (h - r);
          gradient2 += f * f;
        }
      }
    }
  }
  s.lattice_sum = (f3d_real)sum;
  s.rest_stiffness = (f3d_real)(gradient2 / (sum * sum));
  s.dt = (f3d_real)dt;
  s.substeps = 1;
  s.iterations = 4;
  return s;
}

/* A vessel record: a tube of [radius] and [height] standing at [x] [y]
 * [z], upright, its glass [thickness] thick. */
static uint32_t tube(f3d_real *out, uint32_t kind, f3d_real x, f3d_real y, f3d_real z,
                     f3d_real radius, f3d_real height, f3d_real thickness) {
  const f3d_real head[19] = {(f3d_real)kind, x, y, z, 1, 0, 0, 0, 1, 0, 0, 0, 1,
                             thickness, 0, height, radius, radius, 3};
  memcpy(out, head, sizeof head);
  const f3d_real profile[6] = {0, 0, radius, 0, radius, height};
  memcpy(out + 19, profile, sizeof profile);
  return 25u;
}

static void lone_particle(void) {
  /* Falls as semi-implicit Euler sums: after n substeps of h, gh²n(n+1)/2.
   * From the origin, as the Dart side hands particles over about their
   * middle: a velocity read off a move a metre out keeps a tenth of the
   * digits in f32. */
  F3dLiquidParticleSettings s = particle_settings(0.002, 0.001);
  s.substeps = 100;
  f3d_real p[6] = {0, 0, 0, 0, 0, 0};
  CHECK(f3d_liquid_particles(p, 1, NULL, 0, &s) == 1);
  CHECK_NEAR(p[1], -9.81 * 1e-6 * 100 * 101 / 2, 1e-6);
  CHECK_NEAR(p[4], -9.81 * 0.1, 1e-4);
  CHECK(p[0] == F3D_R(0.0) && p[2] == F3D_R(0.0));

  /* On a floor it stays on it: never through, never thrown off. Alone,
   * nothing is compressed, so the density passes stop before the walls
   * are asked, and it sinks into the floor by up to a piece a substep and
   * is put back the next — as the reference does. */
  const f3d_real floor[5] = {(f3d_real)F3D_LIQUID_PLANE, 0, 1, 0, 0};
  f3d_real q[6] = {0, F3D_R(0.01), 0, 0, 0, 0};
  int on = 1;
  for (int i = 0; i < 200; i++) {
    CHECK(f3d_liquid_particles(q, 1, floor, 5, &s) == 1);
    if (i > 10) on = on && q[1] > F3D_R(0.0) && q[1] < F3D_R(0.002);
  }
  CHECK(on);
}

static void glass(void) {
  /* Dropped into a tube eight millimetres across, it lands on the floor
   * inside and stays there: in pieces, it does not pass through a glass
   * thinner than a particle. */
  F3dLiquidParticleSettings s = particle_settings(0.002, 1.0 / 480.0);
  s.substeps = 2;
  f3d_real walls[25];
  const uint32_t length =
      tube(walls, F3D_LIQUID_INSIDE, 0, 0, 0, F3D_R(0.004), F3D_R(0.05), F3D_R(0.0005));
  f3d_real p[6] = {F3D_R(0.001), F3D_R(0.04), 0, 0, -2, 0};
  int in = 1;
  for (int i = 0; i < 240; i++) {
    CHECK(f3d_liquid_particles(p, 1, walls, length, &s) == 1);
    in = in && p[1] > F3D_R(0.0) && p[0] * p[0] + p[2] * p[2] <= F3D_R(0.004) * F3D_R(0.004);
  }
  CHECK(in);
  CHECK(p[1] < F3D_R(0.002));

  /* Beside its foot, under the inside's floor, it is pushed out sideways
   * by the outside, not up into the glass. */
  f3d_real outside[25];
  const uint32_t n2 =
      tube(outside, F3D_LIQUID_OUTSIDE, 0, F3D_R(0.002), 0, F3D_R(0.004), F3D_R(0.05),
           F3D_R(0.0005));
  f3d_real q[6] = {F3D_R(0.0042), F3D_R(0.001), 0, 0, 0, 0};
  s.gravity[1] = 0;
  CHECK(f3d_liquid_particles(q, 1, outside, n2, &s) == 1);
  CHECK_NEAR(q[0], 0.004 + 0.0005 + 0.001, 1e-6);
  CHECK_NEAR(q[1], 0.001, 1e-7);
}

static void block(void) {
  /* Six by six by six in a box six spacings wide settles at its rest
   * density: its mean height three spacings, to five per cent, nothing
   * out through the walls. */
  const double sp = 0.005;
  F3dLiquidParticleSettings s = particle_settings(sp, 1.0 / 1200.0);
  s.substeps = 2;
  static f3d_real p[216 * 6];
  int n = 0;
  for (int i = 0; i < 6; i++) {
    for (int j = 0; j < 6; j++) {
      for (int k = 0; k < 6; k++) {
        f3d_real *q = p + n * 6;
        q[0] = (f3d_real)((i + 0.5) * sp);
        q[1] = (f3d_real)((j + 0.5) * sp);
        q[2] = (f3d_real)((k + 0.5) * sp);
        q[3] = q[4] = q[5] = 0;
        n++;
      }
    }
  }
  const f3d_real w = (f3d_real)(6 * sp);
  const f3d_real box[25] = {
      0, 0, 1, 0, 0,  0, 1, 0, 0, 0,  0, -1, 0, 0, -w,  0, 0, 0, 1, 0,  0, 0, 0, -1, -w,
  };
  for (int t = 0; t < 600; t++) CHECK(f3d_liquid_particles(p, (uint32_t)n, box, 25, &s) == 1);
  double mean = 0;
  int inside = 1;
  for (int i = 0; i < n; i++) {
    const f3d_real *q = p + i * 6;
    mean += (double)q[1];
    inside = inside && q[0] >= F3D_R(-1e-5) && q[0] <= w + F3D_R(1e-5) && q[2] >= F3D_R(-1e-5) &&
             q[2] <= w + F3D_R(1e-5) && q[1] >= F3D_R(-1e-5);
  }
  CHECK(inside);
  CHECK_NEAR(mean / n, 3.0 * sp, 0.15 * sp);
}

static void coincident(void) {
  /* Two lumps let go exactly on top of each other, as a stream lets go of
   * its drops: each pair on one point parts along a direction of its own,
   * and the crowd makes room for itself rather than flying apart. */
  F3dLiquidParticleSettings s = particle_settings(0.002, 1.0 / 480.0);
  s.gravity[1] = 0;
  static f3d_real p[54 * 6];
  for (int i = 0; i < 54; i++) {
    const int k = i % 27;
    f3d_real *q = p + i * 6;
    q[0] = (f3d_real)((k % 3 - 1) * 0.002);
    q[1] = (f3d_real)((k / 3 % 3 - 1) * 0.002);
    q[2] = (f3d_real)((k / 9 - 1) * 0.002);
    q[3] = q[4] = q[5] = 0;
  }
  for (int t = 0; t < 120; t++) CHECK(f3d_liquid_particles(p, 54, NULL, 0, &s) == 1);
  int apart = 1, near = 1;
  for (int i = 0; i < 27; i++) {
    const f3d_real *a = p + i * 6, *b = p + (i + 27) * 6;
    const f3d_real dx = a[0] - b[0], dy = a[1] - b[1], dz = a[2] - b[2];
    apart = apart && dx * dx + dy * dy + dz * dz > F3D_R(1e-10);
  }
  for (int i = 0; i < 54 * 6; i++) near = near && p[i] == p[i] && fabs((double)p[i]) < 0.05;
  CHECK(apart);
  CHECK(near);
}

/* A parcel of water at [x], moving at [v]: a millilitre a second for a
 * 240th of a second. */
static void parcel(f3d_real *r, const f3d_real x[3], const f3d_real v[3]) {
  memset(r, 0, F3D_LIQUID_PARCEL_FLOATS * sizeof(f3d_real));
  for (int k = 0; k < 3; k++) {
    r[k] = x[k];
    r[3 + k] = v[k];
  }
  r[9] = F3D_R(1e-6 / 240.0);
  r[10] = F3D_R(1.0 / 240.0);
  r[14] = F3D_R(998.2);
  r[15] = F3D_R(0.0728);
  r[16] = F3D_R(1.002e-3);
}

static F3dLiquidStreamSettings stream_settings(void) {
  F3dLiquidStreamSettings s;
  memset(&s, 0, sizeof s);
  s.gravity[1] = F3D_R(-9.81);
  s.dt = F3D_R(1.0 / 240.0);
  s.cling = (f3d_real)(0.0728 * (1.0 + cos(0.35)) / 998.2);
  return s;
}

static void parcels(void) {
  const F3dLiquidStreamSettings s = stream_settings();
  /* Thrown sideways, it falls as the world falls, and its ripples grow. */
  f3d_real r[F3D_LIQUID_PARCEL_FLOATS];
  const f3d_real at[3] = {0, 1, 0}, side[3] = {1, 0, 0};
  parcel(r, at, side);
  for (int i = 0; i < 24; i++) CHECK(f3d_liquid_parcels(r, 1, NULL, 0, &s) == 1);
  const double t = 0.1, h = 1.0 / 240.0;
  CHECK_NEAR(r[0], t, 1e-5);
  CHECK_NEAR(r[1], 1.0 - 9.81 * h * h * 24 * 25 / 2, 1e-5);
  CHECK_NEAR(r[11], t, 1e-5);
  CHECK(r[12] > F3D_R(0.0));
  CHECK(r[13] == F3D_R(0.0));
  CHECK_NEAR(r[7], r[1] + 9.81 * h * 24 * h, 1e-5);

  /* Thrown down at a floor, it runs along it at its sideways speed, the
   * downward part gone, and on a wall its ripples do not grow. */
  const f3d_real floor[5] = {(f3d_real)F3D_LIQUID_PLANE, 0, 1, 0, 0};
  const f3d_real low[3] = {0, F3D_R(0.003), 0}, down[3] = {F3D_R(0.2), -1, 0};
  parcel(r, low, down);
  for (int i = 0; i < 4; i++) CHECK(f3d_liquid_parcels(r, 1, floor, 5, &s) == 1);
  CHECK(r[13] == F3D_R(1.0));
  CHECK_NEAR(r[4], 0.0, 1e-6);
  CHECK_NEAR(r[3], 0.2, 1e-6);
  CHECK(r[12] == F3D_R(0.0));

  /* Off a wall, slow: drawn back to it. Fast: let go. */
  const f3d_real ceiling[5] = {(f3d_real)F3D_LIQUID_PLANE, 0, -1, 0, -1};
  const f3d_real under[3] = {0, F3D_R(0.998), 0}, still[3] = {0, 0, 0};
  parcel(r, under, still);
  r[13] = 1;
  CHECK(f3d_liquid_parcels(r, 1, ceiling, 5, &s) == 1);
  CHECK(r[13] == F3D_R(1.0));
  const f3d_real quick[3] = {0, -3, 0};
  parcel(r, under, quick);
  r[13] = 1;
  CHECK(f3d_liquid_parcels(r, 1, ceiling, 5, &s) == 1);
  CHECK(r[13] == F3D_R(0.0));
}

static void modes(void) {
  /* With no viscosity or tension, a mode of wavenumber k over deep liquid
   * rings at ω² = gk, undamped: a step later it is a·cos ωt + (ȧ/ω)·sin ωt. */
  F3dLiquidWaveSettings s;
  memset(&s, 0, sizeof s);
  s.dt = F3D_R(0.01);
  s.g = F3D_R(9.81);
  s.depth = F3D_R(1.0);
  s.area = F3D_R(1.0);
  const double k = 50.0;
  f3d_real m[F3D_LIQUID_MODE_FLOATS] = {(f3d_real)(k * k), 1, F3D_R(1e-4), 0, 0, 0};
  f3d_liquid_modes(m, 1, &s);
  const double w = sqrt(9.81 * k);
  CHECK_NEAR(m[4], w * w, 1e-5 * w * w);
  CHECK_NEAR(m[5], 0.0, 1e-12);
  CHECK_NEAR(m[2] * 1e4, cos(w * 0.01), 1e-5);
  CHECK_NEAR(m[3] * 1e4, -w * sin(w * 0.01), 1e-4 * w);

  /* Viscous, it decays: at 2νk² in the bulk at least. */
  s.kinematic_viscosity = F3D_R(1e-3);
  f3d_real d[F3D_LIQUID_MODE_FLOATS] = {(f3d_real)(k * k), 1, F3D_R(1e-4), 0, 0, 0};
  f3d_liquid_modes(d, 1, &s);
  CHECK(d[5] >= F3D_R(2e-3 * k * k));

  /* Higher than a fourteenth of its wavelength, it breaks down to it. */
  f3d_real big[F3D_LIQUID_MODE_FLOATS] = {(f3d_real)(k * k), 2, F3D_R(0.1), 0, 0, 0};
  s.dt = F3D_R(1e-6);
  f3d_liquid_modes(big, 1, &s);
  CHECK_NEAR(fabs((double)big[2]) * 2, 2.0 * PI_D / (14.0 * k), 1e-6);
}

static void refused(void) {
  F3dLiquidParticleSettings s = particle_settings(0.002, 0.001);
  const F3dLiquidStreamSettings st = stream_settings();
  f3d_real p[6] = {0, 1, 0, 0, 0, 0};
  const f3d_real nothing[5] = {7, 0, 1, 0, 0};
  CHECK(f3d_liquid_particles(p, 1, nothing, 5, &s) == 0);
  const f3d_real short_plane[4] = {0, 0, 1, 0};
  CHECK(f3d_liquid_particles(p, 1, short_plane, 4, &s) == 0);
  f3d_real cut[25];
  tube(cut, F3D_LIQUID_INSIDE, 0, 0, 0, 1, 1, 0);
  CHECK(f3d_liquid_particles(p, 1, cut, 24, &s) == 0);
  CHECK(p[1] == F3D_R(1.0) && p[4] == F3D_R(0.0));
  f3d_real r[F3D_LIQUID_PARCEL_FLOATS];
  const f3d_real at[3] = {0, 1, 0}, v[3] = {0, 0, 0};
  parcel(r, at, v);
  CHECK(f3d_liquid_parcels(r, 1, nothing, 5, &st) == 0);
  CHECK(r[1] == F3D_R(1.0));
  s.spacing = 0;
  CHECK(f3d_liquid_particles(p, 1, NULL, 0, &s) == 0);
}

int main(void) {
  lone_particle();
  glass();
  block();
  coincident();
  parcels();
  modes();
  refused();
  return finish();
}
