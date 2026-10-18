/*
 * Debris on the CPU, tested in C — P9, phase 10: a ball comes to rest on a
 * floor and on a box, rolls down a slope at 5/7 g sin θ and slides at
 * g sin θ without friction, two balls meeting head on keep their momentum
 * and swap their speeds or stick by the restitution, a free cluster keeps
 * its momentum, a ball lands in a shallow groove without a hop, a ball
 * whose centre is inside a box leaves by the nearest face, a column of ten
 * gives under twelve millimetres, and a heap of five hundred settles in a
 * pen without blowing up or leaking.
 */
#include <math.h>
#include <string.h>

#include "check.h"

static F3dDebrisSettings settings(void) {
  F3dDebrisSettings s;
  memset(&s, 0, sizeof s);
  s.gravity[1] = -F3D_STANDARD_GRAVITY;
  s.friction = F3D_R(0.6);
  s.restitution = F3D_R(0.0);
  s.max_speed = F3D_R(50.0);
  s.substeps = 8;
  s.iterations = 4;
  return s;
}

static void ball(f3d_real *out, f3d_real x, f3d_real y, f3d_real z, f3d_real vx,
                 f3d_real vy, f3d_real vz, f3d_real r, f3d_real m) {
  out[0] = x;
  out[1] = y;
  out[2] = z;
  out[3] = vx;
  out[4] = vy;
  out[5] = vz;
  out[6] = r;
  out[7] = m;
}

static const f3d_real kFloor[8] = {0, 1, 0, 0, 0, 0, 0, 0};

static void run(F3dDebris *d, const F3dDebrisSettings *s, int steps) {
  for (int i = 0; i < steps; i++) f3d_debris_step(d, s, F3D_R(1.0 / 60.0));
}

static void test_rest(void) {
  F3dDebris *d = f3d_debris_create(4);
  CHECK(d != NULL && f3d_debris_capacity(d) == 4);
  CHECK(f3d_debris_set_statics(d, kFloor, 1));
  f3d_real in[8], out[32];
  ball(in, 0, F3D_R(0.5), 0, 0, 0, 0, F3D_R(0.1), 1);
  CHECK(f3d_debris_add(d, in, 1) == 0);
  const F3dDebrisSettings s = settings();
  run(d, &s, 180);
  f3d_debris_read(d, out, 4);
  /* On the floor, sunk no more than a millimetre, still, unturned. */
  CHECK(out[1] > F3D_R(0.099) && out[1] < F3D_R(0.1005));
  const f3d_real y = out[1];
  run(d, &s, 60);
  f3d_debris_read(d, out, 4);
  CHECK_NEAR(out[1], y, 1e-5);
  CHECK_NEAR(out[6], 1.0, 1e-6);
  CHECK(out[7] == F3D_R(0.1));
  /* The empty slots stayed empty. */
  CHECK(out[15] == 0 && out[14] == 1);
  f3d_debris_destroy(d);

  /* On a box a metre high, beside it past it to the floor. */
  d = f3d_debris_create(2);
  const f3d_real statics[16] = {0, 1, 0, 0, 0, 0, 0, 0,
                                0, F3D_R(0.5), 0, 0, F3D_R(0.5), F3D_R(0.5), F3D_R(0.5), 1};
  CHECK(f3d_debris_set_statics(d, statics, 2));
  f3d_real two[16];
  ball(two, 0, 2, 0, 0, 0, 0, F3D_R(0.1), 1);
  ball(two + 8, F3D_R(0.75), 2, 0, 0, 0, 0, F3D_R(0.1), 1);
  f3d_debris_add(d, two, 2);
  run(d, &s, 240);
  f3d_debris_read(d, out, 2);
  CHECK(out[1] > F3D_R(1.099) && out[1] < F3D_R(1.1005));
  CHECK(out[9] > F3D_R(0.099) && out[9] < F3D_R(0.1005));
  CHECK_NEAR(out[8], 0.75, 1e-3);
  f3d_debris_destroy(d);
}

static void test_slope(void) {
  /* The floor tilted by tilting gravity: θ = 0.3. Rolling, a solid ball
   * goes 5/7 g sin θ; without friction it slides at g sin θ, unturned. */
  const double theta = 0.3, g = STANDARD_G;
  for (int rolls = 1; rolls >= 0; rolls--) {
    F3dDebris *d = f3d_debris_create(1);
    f3d_debris_set_statics(d, kFloor, 1);
    f3d_real in[8], out[8];
    ball(in, 0, F3D_R(0.1), 0, 0, 0, 0, F3D_R(0.1), 2);
    f3d_debris_add(d, in, 1);
    F3dDebrisSettings s = settings();
    s.gravity[0] = (f3d_real)(g * sin(theta));
    s.gravity[1] = (f3d_real)(-g * cos(theta));
    s.friction = rolls ? F3D_R(1.0) : F3D_R(0.0);
    run(d, &s, 60);
    f3d_debris_read(d, out, 1);
    const double a = rolls ? 5.0 / 7.0 * g * sin(theta) : g * sin(theta);
    /* Two per cent: CHECK_NEAR scales its tolerance past one. */
    CHECK_NEAR(out[0], 0.5 * a, 0.02);
    CHECK_NEAR(out[1], 0.1, 1e-3);
    if (rolls) {
      /* Turned about z the way it rolls, by x / r radians. */
      const double turned = 2.0 * atan2((double)out[5], (double)out[6]);
      const double rolled = -out[0] / 0.1;
      CHECK_NEAR(cos(turned), cos(rolled), 0.01);
      CHECK_NEAR(sin(turned), sin(rolled), 0.01);
    } else {
      CHECK_NEAR(out[6], 1.0, 1e-6);
    }
    f3d_debris_destroy(d);
  }
}

static void test_head_on(void) {
  /* Equal balls, one at 2 m/s onto one at rest, no gravity: elastic, they
   * swap speeds; inelastic, they go on together at 1 m/s. Either way the
   * centre of mass goes at 1 m/s. */
  for (int elastic = 1; elastic >= 0; elastic--) {
    F3dDebris *d = f3d_debris_create(2);
    f3d_real in[16], out[16];
    ball(in, -1, 0, 0, 2, 0, 0, F3D_R(0.1), 1);
    ball(in + 8, 0, 0, 0, 0, 0, 0, F3D_R(0.1), 1);
    f3d_debris_add(d, in, 2);
    F3dDebrisSettings s = settings();
    s.gravity[1] = 0;
    s.restitution = elastic ? F3D_R(1.0) : F3D_R(0.0);
    run(d, &s, 60);
    f3d_debris_read(d, out, 2);
    CHECK_NEAR((out[0] + out[8]) / 2, -0.5 + 1.0, 1e-4);
    CHECK_NEAR(out[1], 0, 1e-6);
    if (elastic) {
      /* Met after 0.4 s; A stopped there and B went on at 2 m/s. */
      CHECK_NEAR(out[0], -0.2, 0.02);
      CHECK_NEAR(out[8], 1.2, 0.02);
    } else {
      CHECK_NEAR(out[8] - out[0], 0.2, 0.002);
    }
    f3d_debris_destroy(d);
  }
}

static void test_free_cluster(void) {
  /* Two hundred balls of different sizes and masses thrown together, no
   * gravity and nothing still: every contact gives both its bodies the
   * same impulse, so the momentum stays what it was. */
  enum { N = 200 };
  F3dDebris *d = f3d_debris_create(N);
  f3d_real in[N * 8], out[N * 8];
  double p0[3] = {0, 0, 0}, mass = 0;
  for (int i = 0; i < N; i++) {
    const f3d_real x = (f3d_real)(i % 6) * F3D_R(0.25), y = (f3d_real)((i / 6) % 6) * F3D_R(0.25),
                   z = (f3d_real)(i / 36) * F3D_R(0.25);
    const f3d_real m = F3D_R(0.5) + (f3d_real)(i % 7) * F3D_R(0.3);
    ball(in + i * 8, x, y, z, -x * 3 + (f3d_real)(i % 3), -y * 3, -z * 3, F3D_R(0.08) + (f3d_real)(i % 4) * F3D_R(0.01), m);
    p0[0] += (double)m * in[i * 8 + 3];
    p0[1] += (double)m * in[i * 8 + 4];
    p0[2] += (double)m * in[i * 8 + 5];
    mass += m;
  }
  f3d_debris_add(d, in, N);
  F3dDebrisSettings s = settings();
  s.gravity[1] = 0;
  /* The centre of mass, before and after a second. */
  double c0[3] = {0, 0, 0}, c1[3] = {0, 0, 0};
  for (int i = 0; i < N; i++) {
    for (int k = 0; k < 3; k++) c0[k] += (double)in[i * 8 + 7] * in[i * 8 + k];
  }
  run(d, &s, 60);
  f3d_debris_read(d, out, N);
  for (int i = 0; i < N; i++) {
    for (int k = 0; k < 3; k++) c1[k] += (double)in[i * 8 + 7] * out[i * 8 + k];
  }
  for (int k = 0; k < 3; k++) CHECK_NEAR((c1[k] - c0[k]) / mass, p0[k] / mass, 1e-3);
  f3d_debris_destroy(d);
}

static void test_heap(void) {
  /* Five hundred balls of three sizes poured into a pen two metres wide,
   * five layers deep: four seconds later none is through the floor or a
   * wall, none sits in another by more than a tenth of its radius, and the
   * heap is still. */
  enum { N = 500 };
  F3dDebris *d = f3d_debris_create(N);
  const f3d_real pen[40] = {0, 1, 0, 0, 0, 0, 0, 0,  1, 0, 0, -1, 0, 0, 0, 0,
                            -1, 0, 0, -1, 0, 0, 0, 0, 0, 0, 1, -1, 0, 0, 0, 0,
                            0, 0, -1, -1, 0, 0, 0, 0};
  CHECK(f3d_debris_set_statics(d, pen, 5));
  static f3d_real in[N * 8], out[N * 8], later[N * 8];
  for (int i = 0; i < N; i++) {
    const f3d_real x = F3D_R(-0.85) + (f3d_real)(i % 10) * F3D_R(0.19);
    const f3d_real z = F3D_R(-0.85) + (f3d_real)((i / 10) % 10) * F3D_R(0.19);
    const f3d_real y = F3D_R(0.3) + (f3d_real)(i / 100) * F3D_R(0.25);
    ball(in + i * 8, x + (f3d_real)(i % 3) * F3D_R(0.01), y, z, 0, -1, 0,
         F3D_R(0.05) + (f3d_real)(i % 3) * F3D_R(0.02), 1);
  }
  f3d_debris_add(d, in, N);
  F3dDebrisSettings s = settings();
  s.angular_damping = F3D_R(0.5);
  run(d, &s, 240);
  f3d_debris_read(d, out, N);
  run(d, &s, 6);
  f3d_debris_read(d, later, N);
  double worst_overlap = 0, worst_speed = 0;
  int leaked = 0;
  for (int i = 0; i < N; i++) {
    const f3d_real *a = out + i * 8;
    const f3d_real r = a[7];
    if (a[1] < r - F3D_R(0.01) || fabs((double)a[0]) > 1 - r + 0.01 ||
        fabs((double)a[2]) > 1 - r + 0.01) {
      leaked++;
    }
    for (int j = i + 1; j < N; j++) {
      const f3d_real *b = out + j * 8;
      const double dx = a[0] - b[0], dy = a[1] - b[1], dz = a[2] - b[2];
      const double depth = (double)(r + b[7]) - sqrt(dx * dx + dy * dy + dz * dz);
      const double rel = depth / fmin((double)r, (double)b[7]);
      if (rel > worst_overlap) worst_overlap = rel;
    }
    for (int k = 0; k < 3; k++) {
      const double v = fabs((double)later[i * 8 + k] - a[k]) * 10.0;
      if (v > worst_speed) worst_speed = v;
    }
  }
  CHECK(leaked == 0);
  CHECK(worst_overlap < 0.1);
  CHECK(worst_speed < 0.1);
  f3d_debris_destroy(d);
}

static void test_groove(void) {
  /* Two planes tilted 0.35 rad make a shallow groove. Each contact alone
   * would stop the whole fall along its normal, nearly twice over
   * together, and throw the ball back up; split between them, it lands
   * and stays. */
  const double a = 0.35;
  F3dDebris *d = f3d_debris_create(1);
  const f3d_real groove[16] = {(f3d_real)sin(a), (f3d_real)cos(a), 0, 0, 0, 0, 0, 0,
                               (f3d_real)-sin(a), (f3d_real)cos(a), 0, 0, 0, 0, 0, 0};
  f3d_debris_set_statics(d, groove, 2);
  f3d_real in[8], out[8];
  ball(in, 0, 1, 0, 0, 0, 0, F3D_R(0.1), 1);
  f3d_debris_add(d, in, 1);
  const F3dDebrisSettings s = settings();
  const double rest = 0.1 / cos(a);
  double rise = 0;
  int landed = 0;
  for (int i = 0; i < 120; i++) {
    run(d, &s, 1);
    f3d_debris_read(d, out, 1);
    if (out[1] < rest + 0.01) landed = 1;
    if (landed && out[1] - rest > rise) rise = out[1] - rest;
  }
  CHECK(landed);
  CHECK(rise < 0.002);
  CHECK_NEAR(out[1], rest, 0.001);
  CHECK_NEAR(out[0], 0, 1e-4);
  f3d_debris_destroy(d);
}

static void test_inside_box(void) {
  /* A slab a metre wide and twenty centimetres thick, and a ball put with
   * its centre inside it five centimetres under the top: out through the
   * top, the nearest face, not a side. */
  F3dDebris *d = f3d_debris_create(1);
  const f3d_real slab[8] = {0, 0, 0, 0, 1, F3D_R(0.1), 1, 1};
  f3d_debris_set_statics(d, slab, 1);
  f3d_real in[8], out[8];
  ball(in, F3D_R(0.5), F3D_R(0.05), F3D_R(0.2), 0, 0, 0, F3D_R(0.05), 1);
  f3d_debris_add(d, in, 1);
  const F3dDebrisSettings s = settings();
  run(d, &s, 60);
  f3d_debris_read(d, out, 1);
  CHECK(out[1] > F3D_R(0.149) && out[1] < F3D_R(0.1505));
  CHECK_NEAR(out[0], 0.5, 0.01);
  CHECK_NEAR(out[2], 0.2, 0.01);
  f3d_debris_destroy(d);
}

static void test_column(void) {
  /* Ten balls stacked straight up on the floor: each contact carries the
   * weight of those above it, and Jacobi takes it there one ball a pass,
   * so the column gives a little; pushed out at four fifths of the depth a
   * substep, by under twelve millimetres in its two metres. */
  F3dDebris *d = f3d_debris_create(10);
  f3d_debris_set_statics(d, kFloor, 1);
  f3d_real in[80], out[80];
  for (int i = 0; i < 10; i++) ball(in + i * 8, 0, F3D_R(0.1) + (f3d_real)i * F3D_R(0.2), 0, 0, 0, 0, F3D_R(0.1), 1);
  f3d_debris_add(d, in, 10);
  const F3dDebrisSettings s = settings();
  run(d, &s, 120);
  f3d_debris_read(d, out, 10);
  CHECK(out[73] > F3D_R(1.888) && out[73] < F3D_R(1.9));
  CHECK(out[72] == 0 && out[74] == 0);
  f3d_debris_destroy(d);
}

static void test_slots(void) {
  F3dDebris *d = f3d_debris_create(2);
  f3d_real in[24], out[16];
  ball(in, 1, 5, 0, 0, 0, 0, F3D_R(0.1), 1);
  ball(in + 8, 2, 5, 0, 0, 0, 0, F3D_R(0.1), 1);
  ball(in + 16, 3, 5, 0, 0, 0, 0, F3D_R(0.1), 0);
  CHECK(f3d_debris_add(d, in, 2) == 0);
  /* The third takes the first slot, and with no mass empties it. */
  CHECK(f3d_debris_add(d, in + 16, 1) == 0);
  const F3dDebrisSettings s = settings();
  run(d, &s, 10);
  f3d_debris_read(d, out, 2);
  CHECK(out[7] == 0 && out[1] == 0);
  CHECK(out[9] < 5);
  static f3d_real many[(F3D_DEBRIS_MAX_STATICS + 1) * 8];
  CHECK(!f3d_debris_set_statics(d, many, F3D_DEBRIS_MAX_STATICS + 1));
  CHECK(f3d_debris_set_statics(d, many, 0));
  CHECK(f3d_debris_create(0) == NULL);
  f3d_debris_destroy(NULL);
  f3d_debris_destroy(d);
}

int main(void) {
  test_rest();
  test_slope();
  test_head_on();
  test_free_cluster();
  test_groove();
  test_inside_box();
  test_column();
  test_heap();
  test_slots();
  return finish();
}
