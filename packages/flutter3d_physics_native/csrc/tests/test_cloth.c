/*
 * Cloth on the CPU, tested in C — P9, phase 10: a weight on a constraint
 * of compliance α stretches it by α m g, a rigid pendulum keeps its length
 * and swings through the bottom at √(2 g L), a sheet pinned by two corners
 * hangs without stretching, drapes over a ball and lies on the floor
 * without passing into either, the wind carries a loose point at the speed
 * drag gives it, a carried pin carries the cloth, no two
 * constraints of a colour share a point, and bad input is refused.
 */
#include <math.h>
#include <string.h>

#include "check.h"

static F3dClothSettings settings(void) {
  F3dClothSettings s;
  memset(&s, 0, sizeof s);
  s.gravity[1] = F3D_R(-9.81);
  s.floor_y = F3D_R(-1e9);
  s.substeps = 16;
  return s;
}

static void run(F3dCloth *c, const F3dClothSettings *s, int steps) {
  for (int i = 0; i < steps; i++) f3d_cloth_step(c, s, F3D_R(1.0 / 60.0));
}

/* A sheet of n × n points a metre wide in the xz plane at height [y], held
 * by its structural, shear and bending edges; the two corners of its first
 * row pinned when [pinned]. */
enum { SIDE = 16 };
static F3dCloth *sheet(f3d_real y, int pinned, f3d_real compliance) {
  static f3d_real points[SIDE * SIDE * 4];
  static uint32_t edges[SIDE * SIDE * 12];
  static f3d_real comp[SIDE * SIDE * 6];
  const f3d_real step = F3D_R(1.0) / (SIDE - 1);
  for (int j = 0; j < SIDE; j++) {
    for (int i = 0; i < SIDE; i++) {
      f3d_real *p = points + (j * SIDE + i) * 4;
      p[0] = (f3d_real)i * step - F3D_R(0.5);
      p[1] = y;
      p[2] = (f3d_real)j * step - F3D_R(0.5);
      p[3] = F3D_R(SIDE * SIDE) / F3D_R(0.2); /* 200 g in all */
    }
  }
  if (pinned) {
    points[3] = 0;
    points[(SIDE - 1) * 4 + 3] = 0;
  }
  uint32_t n = 0;
  for (int j = 0; j < SIDE; j++) {
    for (int i = 0; i < SIDE; i++) {
      const uint32_t at = (uint32_t)(j * SIDE + i);
      const int links[6][2] = {{1, 0}, {0, 1}, {1, 1}, {1, -1}, {2, 0}, {0, 2}};
      for (int k = 0; k < 6; k++) {
        const int ii = i + links[k][0], jj = j + links[k][1];
        if (ii < 0 || ii >= SIDE || jj < 0 || jj >= SIDE) continue;
        edges[n * 2] = at;
        edges[n * 2 + 1] = (uint32_t)(jj * SIDE + ii);
        comp[n] = k < 2 ? compliance : compliance * 10;
        n++;
      }
    }
  }
  return f3d_cloth_create(points, SIDE * SIDE, edges, comp, n);
}

static void test_spring(void) {
  /* A kilogram on a constraint of compliance 10⁻³ m/N below a pin: it
   * settles g (α m + h²) lower — the spring's α m g, and XPBD's own sag of
   * g h² a substep — times what damping keeps of a substep's fall. */
  const f3d_real points[8] = {0, 0, 0, 0, 0, -1, 0, 1};
  const uint32_t edge[2] = {0, 1};
  const f3d_real alpha = F3D_R(1e-3);
  F3dCloth *c = f3d_cloth_create(points, 2, edge, &alpha, 1);
  CHECK(c != NULL && f3d_cloth_point_count(c) == 2 && f3d_cloth_colour_count(c) == 1);
  F3dClothSettings s = settings();
  s.damping = F3D_R(5.0);
  run(c, &s, 600);
  f3d_real out[8];
  CHECK(f3d_cloth_read(c, out, 2) == 2);
  const double h = 1.0 / 960.0;
  const double keep = 1.0 / (1.0 + 5.0 * h);
  CHECK_NEAR(-1.0 - out[5], 9.81 * (1e-3 + h * h) * keep, 5e-5);
  /* The pin did not move. */
  CHECK(out[0] == 0 && out[1] == 0 && out[3] == 0);
  CHECK(out[7] == 1);
  f3d_cloth_destroy(c);
}

static void test_pendulum(void) {
  /* A rigid rod a metre long, let go level: through the bottom at
   * √(2 g L), its length kept to a millimetre all the way. */
  const f3d_real points[8] = {0, 0, 0, 0, 1, 0, 0, 1};
  const uint32_t edge[2] = {0, 1};
  const f3d_real rigid = 0;
  F3dCloth *c = f3d_cloth_create(points, 2, edge, &rigid, 1);
  const F3dClothSettings s = settings();
  f3d_real out[8], last[8];
  f3d_cloth_read(c, last, 2);
  double fastest = 0, worst_length = 0;
  for (int i = 0; i < 60; i++) {
    run(c, &s, 1);
    f3d_cloth_read(c, out, 2);
    const double len = sqrt((double)out[4] * out[4] + (double)out[5] * out[5] + (double)out[6] * out[6]);
    worst_length = fmax(worst_length, fabs(len - 1.0));
    const double dx = out[4] - last[4], dy = out[5] - last[5];
    fastest = fmax(fastest, sqrt(dx * dx + dy * dy) * 60.0);
    memcpy(last, out, sizeof out);
  }
  CHECK(worst_length < 1e-3);
  /* Five per cent: CHECK_NEAR scales its tolerance by values past one. */
  CHECK_NEAR(fastest, sqrt(2 * 9.81), 0.05);
  f3d_cloth_destroy(c);
}

static void test_hanging(void) {
  F3dCloth *c = sheet(0, 1, F3D_R(1e-7));
  CHECK(c != NULL);
  F3dClothSettings s = settings();
  s.damping = F3D_R(1.0);
  run(c, &s, 180);
  static f3d_real out[SIDE * SIDE * 4];
  f3d_cloth_read(c, out, SIDE * SIDE);
  /* The pins stayed; the cloth hangs below them, all of it finite. */
  CHECK(out[0] == F3D_R(-0.5) && out[1] == 0 && out[2] == F3D_R(-0.5));
  CHECK(out[(SIDE - 1) * 4] == F3D_R(0.5));
  int finite = 1;
  double lowest = 0, stretch = 0;
  for (int i = 0; i < SIDE * SIDE; i++) {
    finite &= isfinite(out[i * 4]) && isfinite(out[i * 4 + 1]) && isfinite(out[i * 4 + 2]);
    lowest = fmin(lowest, (double)out[i * 4 + 1]);
  }
  /* No structural edge is more than 2% longer than it was. */
  for (int j = 0; j < SIDE; j++) {
    for (int i = 0; i + 1 < SIDE; i++) {
      const f3d_real *a = out + (j * SIDE + i) * 4, *b = out + (j * SIDE + i + 1) * 4;
      const double d = sqrt(pow(a[0] - b[0], 2) + pow(a[1] - b[1], 2) + pow(a[2] - b[2], 2));
      stretch = fmax(stretch, d * (SIDE - 1) - 1.0);
    }
  }
  CHECK(finite);
  CHECK(lowest < -0.8 && lowest > -1.1);
  CHECK(stretch < 0.02);
  /* SIDE² points and up to twelve edges each want at least twelve
   * colours, and greedy takes few more; as the GPU is given them, every
   * colour's constraints share no point, run end to end, and each is as
   * long as it started. */
  const uint32_t colours = f3d_cloth_colour_count(c), count = f3d_cloth_edge_count(c);
  CHECK(colours >= 12 && colours <= 24);
  static uint32_t pairs[SIDE * SIDE * 12], start[257], seen[SIDE * SIDE];
  static f3d_real rest[SIDE * SIDE * 6], comp[SIDE * SIDE * 6];
  f3d_cloth_edges(c, pairs, rest, comp, start);
  CHECK(start[0] == 0 && start[colours] == count);
  int shared = 0, ordered = 1;
  for (uint32_t k = 0; k < colours; k++) {
    ordered &= start[k] < start[k + 1];
    for (uint32_t e = start[k]; e < start[k + 1]; e++) {
      for (int end = 0; end < 2; end++) {
        const uint32_t p = pairs[e * 2 + (uint32_t)end];
        shared += seen[p] == k + 1;
        seen[p] = k + 1;
      }
    }
  }
  CHECK(shared == 0);
  CHECK(ordered);
  /* The first edge given, (0, 1), a structural one a fifteenth long. */
  CHECK(pairs[0] == 0 && pairs[1] == 1);
  CHECK_NEAR(rest[0], 1.0 / 15.0, 1e-6);
  CHECK(comp[0] == F3D_R(1e-7));
  /* Carried by a pin, it follows. */
  f3d_cloth_move_point(c, 0, F3D_R(-0.5), F3D_R(1.0), F3D_R(-0.5));
  f3d_cloth_move_point(c, SIDE - 1, F3D_R(0.5), F3D_R(1.0), F3D_R(-0.5));
  run(c, &s, 120);
  f3d_cloth_read(c, out, SIDE * SIDE);
  CHECK(out[1] == 1 && out[(SIDE - 1) * 4 + 1] == 1);
  CHECK(out[(SIDE * SIDE - 1) * 4 + 1] > F3D_R(0.0));
  f3d_cloth_destroy(c);
}

static void test_drape(void) {
  /* Dropped onto a ball of 30 cm, then onto the floor beside nothing: no
   * point closer to the ball's centre than its radius and the thickness,
   * none below the floor and the thickness. */
  F3dCloth *c = sheet(F3D_R(0.8), 0, F3D_R(1e-6));
  F3dClothSettings s = settings();
  s.thickness = F3D_R(0.01);
  s.friction = F3D_R(0.3);
  s.floor_y = 0;
  s.damping = F3D_R(0.5);
  const f3d_real ball[4] = {0, F3D_R(0.3), 0, F3D_R(0.3)};
  CHECK(f3d_cloth_set_balls(c, ball, 1));
  run(c, &s, 180);
  static f3d_real out[SIDE * SIDE * 4];
  f3d_cloth_read(c, out, SIDE * SIDE);
  double nearest = 1e9, lowest = 1e9, top = -1e9;
  for (int i = 0; i < SIDE * SIDE; i++) {
    const f3d_real *p = out + i * 4;
    nearest = fmin(nearest, sqrt(pow(p[0], 2) + pow(p[1] - 0.3, 2) + pow(p[2], 2)));
    lowest = fmin(lowest, (double)p[1]);
    top = fmax(top, (double)p[1]);
  }
  CHECK(nearest > 0.31 - 1e-4);
  CHECK(lowest > 0.01 - 1e-6);
  /* It lies over the top of the ball — no point is right over it, the
   * nearest a thirtieth of a metre off, so a little under its top and the
   * thickness — hanging down its sides below its centre. */
  CHECK(top > 0.6 && top < 0.62);
  CHECK(lowest < 0.3);
  f3d_real many[(F3D_CLOTH_MAX_BALLS + 1) * 4];
  memset(many, 0, sizeof many);
  CHECK(!f3d_cloth_set_balls(c, many, F3D_CLOTH_MAX_BALLS + 1));
  f3d_cloth_destroy(c);
}

static void test_wind_and_floor(void) {
  /* Loose points, no constraints. In a wind of 4 m/s with drag 2 and no
   * gravity, a point's speed after n substeps is w (1 − (1 + 2 h)^−n). */
  const f3d_real points[8] = {0, 1, 0, 1, F3D_R(0.5), F3D_R(0.2), 0, 1};
  F3dCloth *c = f3d_cloth_create(points, 2, NULL, NULL, 0);
  F3dClothSettings s = settings();
  s.gravity[1] = 0;
  s.wind[0] = 4;
  s.drag = 2;
  f3d_real before[8], out[8];
  run(c, &s, 59);
  f3d_cloth_read(c, before, 2);
  run(c, &s, 1);
  f3d_cloth_read(c, out, 2);
  const double h = 1.0 / 960.0;
  const double speed = 4.0 * (1.0 - pow(1.0 + 2.0 * h, -960.0));
  CHECK_NEAR((out[0] - before[0]) * 60.0, speed, 0.01);
  CHECK(out[1] == 1);
  f3d_cloth_destroy(c);
  /* Dropped on the floor at a tenth of a metre: they lie the thickness
   * above it. */
  c = f3d_cloth_create(points, 2, NULL, NULL, 0);
  s = settings();
  s.floor_y = F3D_R(0.1);
  s.thickness = F3D_R(0.02);
  run(c, &s, 60);
  f3d_cloth_read(c, out, 2);
  CHECK_NEAR(out[1], 0.12, 1e-6);
  CHECK_NEAR(out[5], 0.12, 1e-6);
  f3d_cloth_destroy(c);
}

static void test_refused(void) {
  const f3d_real points[8] = {0, 0, 0, 1, 1, 0, 0, 1};
  const f3d_real comp[1] = {0};
  const uint32_t self[2] = {1, 1}, outside[2] = {0, 2};
  CHECK(f3d_cloth_create(points, 2, self, comp, 1) == NULL);
  CHECK(f3d_cloth_create(points, 2, outside, comp, 1) == NULL);
  CHECK(f3d_cloth_create(points, 0, NULL, NULL, 0) == NULL);
  /* No edges at all is a cloth of loose points. */
  F3dCloth *c = f3d_cloth_create(points, 2, NULL, NULL, 0);
  CHECK(c != NULL && f3d_cloth_colour_count(c) == 0);
  f3d_cloth_destroy(c);
  f3d_cloth_destroy(NULL);
}

/* ------------------------------------------------- f3d_cloth_solve */

static F3dClothSolveSettings solve_settings(void) {
  F3dClothSolveSettings s;
  memset(&s, 0, sizeof s);
  s.gravity[1] = F3D_R(-9.81);
  s.damping = F3D_R(0.02);
  s.thickness = F3D_R(0.01);
  s.substeps = 8;
  s.iterations = 2;
  return s;
}

static void solve(F3dCloth *c, const F3dClothSolveSettings *s, int steps) {
  for (int i = 0; i < steps; i++) f3d_cloth_solve(c, s, F3D_R(1.0 / 60.0));
}

/* The sheet() above, with its triangles, two to a quad. */
static F3dCloth *solve_sheet(f3d_real y) {
  F3dCloth *c = sheet(y, 0, 0);
  static uint32_t corners[(SIDE - 1) * (SIDE - 1) * 6];
  uint32_t n = 0;
  for (uint32_t j = 0; j + 1 < SIDE; j++) {
    for (uint32_t i = 0; i + 1 < SIDE; i++) {
      const uint32_t tl = j * SIDE + i, tr = tl + 1, bl = tl + SIDE, br = bl + 1;
      const uint32_t quad[6] = {tl, bl, br, tl, br, tr};
      for (int k = 0; k < 6; k++) corners[n++] = quad[k];
    }
  }
  CHECK(f3d_cloth_set_triangles(c, corners, n / 3u));
  return c;
}

static void test_solve_obstacles(void) {
  /* A ball, a box as its six planes and a ground: dropped on each, no point
   * ends up inside it and all of them finite. */
  static f3d_real state[SIDE * SIDE * F3D_CLOTH_STATE_FLOATS];
  F3dClothSolveSettings s = solve_settings();

  F3dCloth *c = solve_sheet(F3D_R(0.8));
  const f3d_real ball[5] = {F3D_CLOTH_BALL, 0, F3D_R(0.3), 0, F3D_R(0.3)};
  CHECK(f3d_cloth_set_obstacles(c, ball, 5));
  solve(c, &s, 90);
  f3d_cloth_read_state(c, state);
  double nearest = 1e9, top = -1e9;
  for (int i = 0; i < SIDE * SIDE; i++) {
    const f3d_real *p = state + i * F3D_CLOTH_STATE_FLOATS;
    CHECK(isfinite(p[0]) && isfinite(p[1]) && isfinite(p[2]));
    nearest = fmin(nearest, sqrt(pow(p[0], 2) + pow(p[1] - 0.3, 2) + pow(p[2], 2)));
    top = fmax(top, (double)p[1]);
  }
  CHECK(nearest > 0.3 + 0.01 - 1e-4);
  CHECK(top > 0.6 && top < 0.63);
  f3d_cloth_destroy(c);

  /* A box 0.4 m on a side, its top at 0.4. */
  c = solve_sheet(F3D_R(0.8));
  const f3d_real box[2 + 6 * 4] = {
      F3D_CLOTH_CONVEX, 6, 1, 0, 0, F3D_R(0.2), -1, 0, 0, F3D_R(0.2), 0, 1, 0, F3D_R(0.4),
      0, -1, 0, 0, 0, 0, 1, F3D_R(0.2), 0, 0, -1, F3D_R(0.2),
  };
  CHECK(f3d_cloth_set_obstacles(c, box, 26));
  solve(c, &s, 90);
  f3d_cloth_read_state(c, state);
  int inside = 0;
  top = -1e9;
  for (int i = 0; i < SIDE * SIDE; i++) {
    const f3d_real *p = state + i * F3D_CLOTH_STATE_FLOATS;
    inside += fabs(p[0]) < 0.2 && fabs(p[2]) < 0.2 && p[1] < 0.4 && p[1] > 0;
    top = fmax(top, (double)p[1]);
  }
  CHECK(inside == 0);
  /* Lying on its top, a little tented where it bends over the edges. */
  CHECK(top > 0.41 - 1e-4 && top < 0.45);
  f3d_cloth_destroy(c);

  /* A ground of 3 × 3 samples a metre apart, sloping up along x, its
   * corner at (−1, 0, −1): the sheet, held by friction, lies on the slope
   * the thickness above it. */
  c = solve_sheet(F3D_R(1.5));
  const f3d_real ground[8 + 9] = {F3D_CLOTH_GROUND, -1, 0, -1, 1, 3, 3, 1,
                                  0, F3D_R(0.5), 1, 0, F3D_R(0.5), 1, 0, F3D_R(0.5), 1};
  CHECK(f3d_cloth_set_obstacles(c, ground, 17));
  s.friction = 1;
  solve(c, &s, 120);
  f3d_cloth_read_state(c, state);
  double worst = 0;
  for (int i = 0; i < SIDE * SIDE; i++) {
    const f3d_real *p = state + i * F3D_CLOTH_STATE_FLOATS;
    worst = fmax(worst, fabs(p[1] - (0.5 * (p[0] + 1.0) + 0.01)));
  }
  CHECK(worst < 0.005);
  f3d_cloth_destroy(c);
}

static void test_solve_wind_and_self(void) {
  /* One loose triangle in the yz plane, no gravity: a wind along x carries
   * it along x, one along y past its edge does nothing to it. */
  const f3d_real tri[12] = {0, 0, 0, 1, 0, 1, 0, 1, 0, 0, 1, 1};
  const uint32_t corners[3] = {0, 1, 2};
  F3dClothSolveSettings s = solve_settings();
  s.gravity[1] = 0;
  s.damping = 0;
  s.wind[0] = 4;
  s.wind_drag = 2;
  F3dCloth *c = f3d_cloth_create(tri, 3, NULL, NULL, 0);
  CHECK(f3d_cloth_set_triangles(c, corners, 1));
  solve(c, &s, 30);
  f3d_real state[3 * F3D_CLOTH_STATE_FLOATS];
  f3d_cloth_read_state(c, state);
  CHECK(state[0] > F3D_R(0.01) && state[3] > F3D_R(0.0) && state[3] < F3D_R(4.0));
  CHECK(state[1] == 0 && state[2] == 0);
  s.wind[0] = 0;
  s.wind[1] = 4;
  f3d_cloth_destroy(c);
  c = f3d_cloth_create(tri, 3, NULL, NULL, 0);
  CHECK(f3d_cloth_set_triangles(c, corners, 1));
  solve(c, &s, 30);
  f3d_cloth_read_state(c, state);
  CHECK(state[0] == 0 && state[1] == 0 && state[3] == 0);
  f3d_cloth_destroy(c);
  /* A corner out of range is refused. */
  c = f3d_cloth_create(tri, 3, NULL, NULL, 0);
  const uint32_t out_of_range[3] = {0, 1, 3};
  CHECK(!f3d_cloth_set_triangles(c, out_of_range, 1));
  f3d_cloth_destroy(c);

  /* Two loose points a metre apart at rest, put a centimetre apart: with a
   * self-thickness of 0.1 one pass parts them to it; neighbours at rest
   * stay. */
  const f3d_real two[8] = {0, 0, 0, 1, 1, 0, 0, 1};
  f3d_real moved[14] = {0, 0, 0, 0, 0, 0, 1, F3D_R(0.01), 0, 0, 0, 0, 0, 1};
  s = solve_settings();
  s.gravity[1] = 0;
  s.substeps = 1;
  s.iterations = 1;
  s.self_thickness = F3D_R(0.1);
  c = f3d_cloth_create(two, 2, NULL, NULL, 0);
  f3d_cloth_write_state(c, moved);
  solve(c, &s, 1);
  f3d_real out[14];
  f3d_cloth_read_state(c, out);
  CHECK_NEAR(out[7] - out[0], 0.1, 1e-5);
  /* Neighbours at rest are left to their constraints. */
  const f3d_real close[6] = {0, 0, 0, F3D_R(0.01), 0, 0};
  f3d_cloth_set_rest(c, close);
  f3d_cloth_write_state(c, moved);
  solve(c, &s, 1);
  f3d_cloth_read_state(c, out);
  CHECK_NEAR(out[7] - out[0], 0.01, 1e-6);
  f3d_cloth_destroy(c);
}

static void test_solve_settings_reach_it(void) {
  /* A kilogram below a pin on a constraint of compliance 10⁻³: XPBD, its
   * multiplier kept across the passes, settles it α m g lower, and a
   * compliance set after it was made reaches the constraint it was given
   * for. */
  const f3d_real points[8] = {0, 0, 0, 0, 0, -1, 0, 1};
  const uint32_t edge[2] = {0, 1};
  const f3d_real stiff = 0, alpha = F3D_R(1e-3);
  F3dCloth *c = f3d_cloth_create(points, 2, edge, &stiff, 1);
  f3d_cloth_set_compliance(c, &alpha);
  F3dClothSolveSettings s = solve_settings();
  s.damping = F3D_R(0.05);
  s.iterations = 4;
  s.self_thickness = F3D_R(0.1);
  solve(c, &s, 300);
  f3d_real out[14];
  f3d_cloth_read_state(c, out);
  CHECK_NEAR(-1.0 - out[8], 9.81e-3, 2e-5);
  CHECK(out[0] == 0 && out[1] == 0 && out[6] == 0);
  /* Bad records are refused and the last kept. */
  const f3d_real ball[5] = {F3D_CLOTH_BALL, 0, F3D_R(-1.3), 0, F3D_R(0.35)};
  CHECK(f3d_cloth_set_obstacles(c, ball, 5));
  const f3d_real no_kind[5] = {F3D_R(7.0), 0, 0, 0, 1};
  const f3d_real cut_short[4] = {F3D_CLOTH_BALL, 0, 0, 0};
  const f3d_real thin_ground[8] = {F3D_CLOTH_GROUND, 0, 0, 0, 1, 1, 3, 1};
  const f3d_real half_kind[5] = {F3D_R(0.5), 0, 0, 0, 1};
  CHECK(!f3d_cloth_set_obstacles(c, no_kind, 5));
  CHECK(!f3d_cloth_set_obstacles(c, cut_short, 4));
  CHECK(!f3d_cloth_set_obstacles(c, thin_ground, 8));
  CHECK(!f3d_cloth_set_obstacles(c, half_kind, 5));
  /* The ball still there holds the weight up off its constraint. */
  s.iterations = 2;
  solve(c, &s, 60);
  f3d_cloth_read_state(c, out);
  CHECK(out[8] > F3D_R(-0.95));
  CHECK(f3d_cloth_set_obstacles(c, NULL, 0));
  /* Nothing for no substeps, or no time. */
  f3d_real before[14];
  f3d_cloth_read_state(c, before);
  s.substeps = 0;
  solve(c, &s, 1);
  s.substeps = 8;
  f3d_cloth_solve(c, &s, 0);
  f3d_cloth_read_state(c, out);
  CHECK(memcmp(before, out, sizeof out) == 0);
  f3d_cloth_destroy(c);
  /* A length given after it was made is the one it is held at. */
  c = f3d_cloth_create(points, 2, edge, &stiff, 1);
  const f3d_real two_metres = 2;
  f3d_cloth_set_lengths(c, &two_metres);
  solve(c, &s, 300);
  f3d_cloth_read_state(c, out);
  CHECK_NEAR(out[8], -2.0, 1e-3);
  f3d_cloth_destroy(c);
}

int main(void) {
  test_spring();
  test_pendulum();
  test_hanging();
  test_drape();
  test_wind_and_floor();
  test_refused();
  test_solve_obstacles();
  test_solve_wind_and_self();
  test_solve_settings_reach_it();
  return finish();
}
