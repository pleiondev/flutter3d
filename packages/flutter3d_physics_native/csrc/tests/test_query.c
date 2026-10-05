/*
 * Queries and characters, tested in C — P9, phase 9: rays against every
 * shape's closed form and against a mesh, the nearest of many and all of
 * them in order, a thousand rays against trying every ball, overlaps,
 * casts, and a character on floors, against walls, up slopes and steps,
 * landing, keeping to a slope going down, and under a ceiling.
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

static F3dBody fixed_shape(F3dWorld *w, F3dShapeKind kind, f3d_real a,
                           f3d_real b, f3d_real c, F3dVec3 at, F3dQuat q) {
  const F3dBody body = f3d_body_create(w, F3D_BODY_FIXED, at.x, at.y, at.z, 0);
  f3d_body_set_shape(w, body, kind, a, b, c);
  f3d_body_set_orientation(w, body, q.x, q.y, q.z, q.w);
  return body;
}

static int ray(F3dWorld *w, F3dVec3 o, F3dVec3 d, f3d_real max, F3dBody *b,
               f3d_real *hit) {
  return f3d_world_ray_cast(w, o.x, o.y, o.z, d.x, d.y, d.z, max, ~0u, 0, b, hit);
}

static void test_rays_on_shapes(void) {
  F3dWorld *w = f3d_world_create();
  F3dBody b;
  f3d_real hit[F3D_HIT_FLOATS];
  /* A ball of half a metre at (0, 0, 0): from x = −5 along x, 4.5 away,
   * the normal back at the ray. */
  const F3dBody ball = fixed_shape(w, F3D_SHAPE_SPHERE, F3D_R(0.5), 0, 0, f3d_v3(0, 0, 0), identity);
  CHECK(ray(w, f3d_v3(-5, 0, 0), f3d_v3(2, 0, 0), 10, &b, hit) == 1);
  CHECK(b == ball);
  CHECK_NEAR(hit[6], 4.5, 1e-5);
  CHECK_NEAR(hit[3], -1, 1e-5);
  CHECK_NEAR(hit[0], -0.5, 1e-5);
  /* Too short, aimed past, or starting inside: nothing. */
  CHECK(ray(w, f3d_v3(-5, 0, 0), f3d_v3(1, 0, 0), 4, &b, hit) == 0);
  CHECK(ray(w, f3d_v3(-5, 1, 0), f3d_v3(1, 0, 0), 10, &b, hit) == 0);
  CHECK(ray(w, f3d_v3(0, 0, 0), f3d_v3(1, 0, 0), 10, &b, hit) == 0);
  CHECK(ray(w, f3d_v3(-5, 0, 0), f3d_v3(0, 0, 0), 10, &b, hit) == 0);
  /* A box turned 45° about z: its edge toward the ray, a metre and a
   * quarter of root two out. */
  const F3dBody box = fixed_shape(w, F3D_SHAPE_BOX, 1, 1, 1, f3d_v3(0, 10, 0),
                                  turn_about(f3d_v3(0, 0, 1), M_PI / 4));
  CHECK(ray(w, f3d_v3(-5, F3D_R(10.2), 0), f3d_v3(1, 0, 0), 10, &b, hit) == 1);
  CHECK(b == box);
  CHECK_NEAR(hit[6], 5 - (sqrt(2.0) - 0.2), 1e-5);
  CHECK_NEAR(hit[3], -sqrt(0.5), 1e-5);
  CHECK_NEAR(hit[4], sqrt(0.5), 1e-5);
  /* An upright cylinder, a lying capsule, a cone on its base and a hull
   * cube, each from the side: met at their surface, normal outward. */
  const F3dBody cyl = fixed_shape(w, F3D_SHAPE_CYLINDER, F3D_R(0.5), 1, 0, f3d_v3(0, 20, 0), identity);
  CHECK(ray(w, f3d_v3(-5, F3D_R(20.3), 0), f3d_v3(1, 0, 0), 10, &b, hit) == 1);
  CHECK(b == cyl);
  CHECK_NEAR(hit[6], 4.5, 1e-3);
  CHECK_NEAR(hit[3], -1, 1e-3);
  /* From inside it, nothing: a ray that starts in a shape does not see
   * it. */
  CHECK(ray(w, f3d_v3(0, 20, 0), f3d_v3(1, 0, 0), F3D_R(0.4), &b, hit) == 0);
  const F3dBody cap = fixed_shape(w, F3D_SHAPE_CAPSULE, F3D_R(0.3), 1, 0, f3d_v3(0, 30, 0),
                                  turn_about(f3d_v3(0, 0, 1), M_PI / 2));
  CHECK(ray(w, f3d_v3(F3D_R(0.5), 35, 0), f3d_v3(0, -1, 0), 10, &b, hit) == 1);
  CHECK(b == cap);
  CHECK_NEAR(hit[6], 4.7, 1e-3);
  CHECK_NEAR(hit[4], 1, 1e-3);
  /* The cone's base is a quarter of its height below its centre. */
  const F3dBody cone = fixed_shape(w, F3D_SHAPE_CONE, F3D_R(0.5), 2, 0, f3d_v3(0, 40, 0), identity);
  CHECK(ray(w, f3d_v3(0, 35, 0), f3d_v3(0, 1, 0), 10, &b, hit) == 1);
  CHECK(b == cone);
  CHECK_NEAR(hit[6], 4.5, 1e-3);
  CHECK_NEAR(hit[4], -1, 1e-3);
  const f3d_real corners[24] = {-1, -1, -1, 1, -1, -1, -1, 1, -1, 1, 1, -1,
                                -1, -1, 1,  1, -1, 1,  -1, 1, 1,  1, 1, 1};
  const uint32_t hull = f3d_world_create_hull(w, corners, 8);
  const F3dBody cube = f3d_body_create(w, F3D_BODY_FIXED, 0, 50, 0, 0);
  f3d_body_set_hull(w, cube, hull);
  CHECK(ray(w, f3d_v3(-5, F3D_R(50.5), F3D_R(0.5)), f3d_v3(1, 0, 0), 10, &b, hit) == 1);
  CHECK(b == cube);
  CHECK_NEAR(hit[6], 4, 1e-3);
  /* A mesh: from the front, met; from behind, not. */
  const f3d_real v[12] = {-2, 60, -2, 2, 60, -2, 2, 60, 2, -2, 60, 2};
  const uint32_t t[6] = {0, 2, 1, 0, 3, 2};
  const F3dBody ground = f3d_body_create(w, F3D_BODY_FIXED, 0, 0, 0, 0);
  f3d_body_set_mesh(w, ground, f3d_world_create_mesh(w, v, 4, t, 2));
  CHECK(ray(w, f3d_v3(F3D_R(0.5), 65, F3D_R(0.5)), f3d_v3(0, -1, 0), 10, &b, hit) == 1);
  CHECK(b == ground);
  CHECK_NEAR(hit[6], 5, 1e-5);
  CHECK_NEAR(hit[4], 1, 1e-5);
  CHECK(ray(w, f3d_v3(F3D_R(0.5), 55, F3D_R(0.5)), f3d_v3(0, 1, 0), 4.9f, &b, hit) == 0);
  f3d_world_destroy(w);
}

static void test_nearest_and_all(void) {
  F3dWorld *w = f3d_world_create();
  F3dBody balls[5];
  for (int i = 0; i < 5; i++) {
    balls[i] = fixed_shape(w, F3D_SHAPE_SPHERE, F3D_R(0.25), 0, 0,
                           f3d_v3((f3d_real)(4 - i) * 2, 0, 0), identity);
  }
  F3dBody b;
  f3d_real hit[F3D_HIT_FLOATS];
  CHECK(ray(w, f3d_v3(-1, 0, 0), f3d_v3(1, 0, 0), 100, &b, hit) == 1);
  CHECK(b == balls[4]);
  F3dBody all[3];
  f3d_real hits[3 * F3D_HIT_FLOATS];
  CHECK(f3d_world_ray_cast_all(w, -1, 0, 0, 1, 0, 0, 100, ~0u, 0, all, hits, 3) == 5);
  CHECK(all[0] == balls[4] && all[1] == balls[3] && all[2] == balls[2]);
  CHECK(hits[6] < hits[F3D_HIT_FLOATS + 6] && hits[F3D_HIT_FLOATS + 6] < hits[2 * F3D_HIT_FLOATS + 6]);
  /* Ignoring the nearest, or masking every layer it has, finds the next. */
  CHECK(f3d_world_ray_cast(w, -1, 0, 0, 1, 0, 0, 100, ~0u, balls[4], &b, hit) == 1);
  CHECK(b == balls[3]);
  f3d_body_set_collision_filter(w, balls[4], 2, ~0u);
  CHECK(f3d_world_ray_cast(w, -1, 0, 0, 1, 0, 0, 100, ~2u, 0, &b, hit) == 1);
  CHECK(b == balls[3]);
  f3d_world_destroy(w);
}

static double uniform(unsigned *state) {
  *state = *state * 1664525u + 1013904223u;
  return (*state >> 8) / 16777216.0;
}

static void test_rays_against_every_ball(void) {
  /* Three hundred balls and a thousand rays: the nearest the tree finds is
   * the nearest trying every ball finds. */
  enum { N = 300 };
  F3dWorld *w = f3d_world_create();
  unsigned seed = 99u;
  F3dVec3 at[N];
  f3d_real r[N];
  F3dBody balls[N];
  for (int i = 0; i < N; i++) {
    at[i] = f3d_v3((f3d_real)(uniform(&seed) * 40 - 20), (f3d_real)(uniform(&seed) * 40 - 20),
                   (f3d_real)(uniform(&seed) * 40 - 20));
    r[i] = (f3d_real)(0.2 + uniform(&seed));
    balls[i] = fixed_shape(w, F3D_SHAPE_SPHERE, r[i], 0, 0, at[i], identity);
  }
  int agree = 1;
  for (int q = 0; q < 1000; q++) {
    const F3dVec3 o = f3d_v3((f3d_real)(uniform(&seed) * 60 - 30), (f3d_real)(uniform(&seed) * 60 - 30),
                             (f3d_real)(uniform(&seed) * 60 - 30));
    F3dVec3 d = f3d_v3((f3d_real)(uniform(&seed) - 0.5), (f3d_real)(uniform(&seed) - 0.5),
                       (f3d_real)(uniform(&seed) - 0.5));
    d = f3d_scale(d, F3D_R(1.0) / f3d_sqrt(f3d_dot(d, d)));
    double best = 1e30;
    int who = -1;
    for (int i = 0; i < N; i++) {
      const F3dVec3 m = f3d_sub(o, at[i]);
      const double b = f3d_dot(m, d), c = f3d_dot(m, m) - (double)r[i] * r[i];
      if (c <= 0 || b > 0 || b * b - c < 0) continue;
      const double t = -b - sqrt(b * b - c);
      if (t < best && t <= 80) {
        best = t;
        who = i;
      }
    }
    F3dBody b;
    f3d_real hit[F3D_HIT_FLOATS];
    const int found = ray(w, o, d, 80, &b, hit);
    if (who < 0) {
      agree &= !found;
    } else {
      agree &= found && b == balls[who] && fabs((double)hit[6] - best) < 1e-3;
    }
  }
  CHECK(agree);
  f3d_world_destroy(w);
}

static void test_overlaps_and_casts(void) {
  F3dWorld *w = f3d_world_create();
  const F3dBody a = fixed_shape(w, F3D_SHAPE_BOX, F3D_R(0.5), F3D_R(0.5), F3D_R(0.5), f3d_v3(0, 0, 0), identity);
  const F3dBody b = fixed_shape(w, F3D_SHAPE_SPHERE, F3D_R(0.5), 0, 0, f3d_v3(2, 0, 0), identity);
  fixed_shape(w, F3D_SHAPE_SPHERE, F3D_R(0.5), 0, 0, f3d_v3(10, 0, 0), identity);
  F3dBody out[4];
  /* A ball at (1, 0, 0) of 0.6 overlaps both the box and the first ball,
   * in slot order, and not the far one. */
  CHECK(f3d_world_overlap_shape(w, F3D_SHAPE_SPHERE, F3D_R(0.6), 0, 0, 0, 1, 0, 0,
                                0, 0, 0, 1, ~0u, 0, out, 4) == 2);
  CHECK(out[0] == a && out[1] == b);
  /* Half a centimetre short of each: neither. */
  CHECK(f3d_world_overlap_shape(w, F3D_SHAPE_SPHERE, F3D_R(0.495), 0, 0, 0, 1, 0, 0,
                                0, 0, 0, 1, ~0u, 0, out, 4) == 0);
  CHECK(f3d_world_overlap_shape(w, F3D_SHAPE_SPHERE, F3D_R(0.6), 0, 0, 0, 1, 0, 0,
                                0, 0, 0, 1, ~0u, a, out, 4) == 1);
  CHECK(f3d_world_overlap_shape(w, (F3dShapeKind)9, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1,
                                ~0u, 0, out, 4) == 0);
  /* A ball of 0.25 cast from x = −5 along x by 10 meets the box at
   * x = −0.75: four and a quarter of ten. */
  F3dBody hitb;
  f3d_real hit[F3D_HIT_FLOATS];
  CHECK(f3d_world_cast_shape(w, F3D_SHAPE_SPHERE, F3D_R(0.25), 0, 0, 0, -5, 0, 0, 0, 0, 0, 1,
                             10, 0, 0, ~0u, 0, &hitb, hit) == 1);
  CHECK(hitb == a);
  CHECK_NEAR(hit[6], 0.425, 1e-4);
  CHECK_NEAR(hit[3], -1, 1e-4);
  /* A box cast down onto the box: as far as their faces. */
  CHECK(f3d_world_cast_shape(w, F3D_SHAPE_BOX, F3D_R(0.2), F3D_R(0.2), F3D_R(0.2), 0, 0, 3, 0,
                             0, 0, 0, 1, 0, -4, 0, ~0u, 0, &hitb, hit) == 1);
  CHECK_NEAR(hit[6], (3.0 - 0.7) / 4.0, 1e-4);
  CHECK_NEAR(hit[4], 1, 1e-4);
  /* Overlapping where it starts: met at nought. */
  CHECK(f3d_world_cast_shape(w, F3D_SHAPE_SPHERE, F3D_R(0.25), 0, 0, 0, F3D_R(0.5), 0, 0, 0, 0, 0, 1,
                             0, 5, 0, ~0u, 0, &hitb, hit) == 1);
  CHECK(hit[6] == 0);
  /* Missing everything. */
  CHECK(f3d_world_cast_shape(w, F3D_SHAPE_SPHERE, F3D_R(0.25), 0, 0, 0, -5, 5, 0, 0, 0, 0, 1,
                             10, 0, 0, ~0u, 0, &hitb, hit) == 0);
  f3d_world_destroy(w);
}

/* A level: a floor, a wall at x = 3, a step 0.3 high at z = 3, a ledge
 * 0.5 high at z = −3, a gentle slope and a steep one, and a ceiling. */
static F3dWorld *level(void) {
  F3dWorld *w = f3d_world_create();
  fixed_shape(w, F3D_SHAPE_BOX, 50, F3D_R(0.5), 50, f3d_v3(0, F3D_R(-0.5), 0), identity);
  fixed_shape(w, F3D_SHAPE_BOX, F3D_R(0.5), 5, 50, f3d_v3(F3D_R(3.5), 5, 0), identity);
  fixed_shape(w, F3D_SHAPE_BOX, 2, F3D_R(0.15), 2, f3d_v3(0, F3D_R(0.15), 5), identity);
  fixed_shape(w, F3D_SHAPE_BOX, 2, F3D_R(0.25), 2, f3d_v3(0, F3D_R(0.25), -5), identity);
  /* The slopes rise along +x, lifted clear of the floor where the tests
   * stand on them. */
  fixed_shape(w, F3D_SHAPE_BOX, 5, F3D_R(0.5), 5, f3d_v3(-20, F3D_R(1.5), 0),
              turn_about(f3d_v3(0, 0, 1), 20.0 * M_PI / 180.0));
  fixed_shape(w, F3D_SHAPE_BOX, 5, F3D_R(0.5), 5, f3d_v3(-20, F3D_R(1.5), 20),
              turn_about(f3d_v3(0, 0, 1), 60.0 * M_PI / 180.0));
  fixed_shape(w, F3D_SHAPE_BOX, 3, F3D_R(0.5), 3, f3d_v3(20, F3D_R(2.5), 0), identity);
  return w;
}

#define R F3D_R(0.3)
#define H F3D_R(0.6)
#define STANDING (R + H + F3D_R(0.01))
#define SLOPE_COS F3D_R(0.7071)

static uint32_t walk(F3dWorld *w, f3d_real *p, F3dVec3 d, f3d_real step,
                     f3d_real *ground) {
  F3dBody gb;
  f3d_real v[3] = {0, 0, 0};
  return f3d_world_move_character(w, R, H, p, d.x, d.y, d.z, v, SLOPE_COS,
                                  step, ~0u, 0u, F3D_CHARACTER_MAY_STEP, 0,
                                  &gb, ground);
}

static void test_character(void) {
  F3dWorld *w = level();
  f3d_real g[3];
  /* Falling onto the floor: it lands, its skin above it, on ground. */
  f3d_real p[3] = {0, 3, 0};
  uint32_t flags = walk(w, p, f3d_v3(0, -5, 0), F3D_R(0.35), g);
  CHECK(flags & F3D_CHARACTER_GROUNDED);
  CHECK_NEAR(p[1], STANDING, 2e-3);
  CHECK_NEAR(g[1], 1, 1e-4);
  /* Walking on it: along, level, on ground. */
  flags = walk(w, p, f3d_v3(1, 0, 0), F3D_R(0.35), g);
  CHECK_NEAR(p[0], 1, 1e-4);
  CHECK_NEAR(p[1], STANDING, 2e-3);
  CHECK(flags & F3D_CHARACTER_GROUNDED);
  /* Into the wall at a slant: stopped at it, sliding along it. */
  flags = walk(w, p, f3d_v3(3, 0, 1), F3D_R(0.35), g);
  CHECK(flags & F3D_CHARACTER_WALL);
  CHECK_NEAR(p[0], 3 - 0.3 - 0.01, 2e-3);
  CHECK_NEAR(p[2], 1, 1e-3);
  /* Up the step of thirty centimetres; not up the ledge of fifty. */
  f3d_real q[3] = {0, STANDING, F3D_R(2.0)};
  flags = walk(w, q, f3d_v3(0, 0, 2), F3D_R(0.35), g);
  CHECK(flags & F3D_CHARACTER_STEPPED);
  CHECK_NEAR(q[1], 0.3 + STANDING, 3e-3);
  CHECK(q[2] > 3.5);
  f3d_real e[3] = {0, STANDING, F3D_R(-2.0)};
  flags = walk(w, e, f3d_v3(0, 0, -2), F3D_R(0.35), g);
  CHECK(!(flags & F3D_CHARACTER_STEPPED));
  CHECK(flags & F3D_CHARACTER_WALL);
  CHECK(e[2] > -2.71);
  /* Up the twenty-degree slope, it climbs; the sixty-degree one stops it
   * as a wall. */
  f3d_real s[3] = {-22, 5, 0};
  walk(w, s, f3d_v3(0, -10, 0), F3D_R(0.35), g);
  const f3d_real y0 = s[1];
  flags = walk(w, s, f3d_v3(1, 0, 0), F3D_R(0.35), g);
  CHECK(s[1] > y0 + 0.2);
  CHECK(flags & F3D_CHARACTER_GROUNDED);
  /* The steep one walked at from the floor at its foot. */
  f3d_real t[3] = {-23, STANDING, 20};
  const f3d_real x0 = t[0], y1 = t[1];
  flags = walk(w, t, f3d_v3(2, 0, 0), 0, g);
  CHECK(flags & F3D_CHARACTER_WALL);
  CHECK(t[1] < y1 + 0.05);
  CHECK(t[0] < x0 + 1.9);
  /* Down the gentle slope with no fall asked: it keeps to it. */
  f3d_real d[3] = {-17, 10, 0};
  walk(w, d, f3d_v3(0, -20, 0), F3D_R(0.35), g);
  const f3d_real yd = d[1];
  flags = walk(w, d, f3d_v3(-0.5f, 0, 0), F3D_R(0.35), g);
  CHECK(flags & F3D_CHARACTER_GROUNDED);
  CHECK_NEAR(d[1], yd - 0.5 * tan(20.0 * M_PI / 180.0), 3e-2);
  /* Jumping into the ceiling: stopped under it. */
  f3d_real u[3] = {20, STANDING, 0};
  flags = walk(w, u, f3d_v3(0, 3, 0), F3D_R(0.35), g);
  CHECK(flags & F3D_CHARACTER_CEILING);
  CHECK_NEAR(u[1], 2.0 - R - H - 0.01, 2e-3);
  /* Refused: no radius. */
  CHECK(walk(w, u, f3d_v3(0, 0, 0), 0, g) == walk(w, u, f3d_v3(0, 0, 0), 0, g));
  F3dBody gb;
  f3d_real v0[3] = {0, 0, 0};
  CHECK(f3d_world_move_character(w, 0, H, u, 0, 0, 0, v0, SLOPE_COS, 0, ~0u, 0u,
                                 0u, 0, &gb, g) == 0);
  f3d_world_destroy(w);
}

/* A platform on a one-way layer: jumped up through, landed on, walked into
 * from the side and through; on any other layer, a ceiling and a wall. */
static void test_one_way(void) {
  F3dWorld *w = f3d_world_create();
  const F3dQuat identity = {0, 0, 0, 1};
  fixed_shape(w, F3D_SHAPE_BOX, 50, F3D_R(0.5), 50, f3d_v3(0, F3D_R(-0.5), 0),
              identity);
  const F3dBody platform = fixed_shape(w, F3D_SHAPE_BOX, 2, F3D_R(0.1), 2,
                                       f3d_v3(0, F3D_R(2.0), 0), identity);
  CHECK(f3d_body_set_collision_filter(w, platform, 2u, ~0u));
  F3dBody gb;
  f3d_real g[3];
  f3d_real still[3] = {0, 0, 0};
  /* Rising into it: through, to above it. */
  f3d_real p[3] = {0, STANDING, 0};
  uint32_t flags = f3d_world_move_character(w, R, H, p, 0, 3, 0, still,
                                            SLOPE_COS, 0, ~0u, 2u, 0u, 0, &gb,
                                            g);
  CHECK(!(flags & F3D_CHARACTER_CEILING));
  CHECK_NEAR(p[1], STANDING + 3, 1e-4);
  /* Falling onto it: it stands there, on the platform. */
  flags = f3d_world_move_character(w, R, H, p, 0, -2, 0, still, SLOPE_COS, 0,
                                   ~0u, 2u, 0u, 0, &gb, g);
  CHECK(flags & F3D_CHARACTER_GROUNDED);
  CHECK(gb == platform);
  CHECK_NEAR(p[1], 2.1 + R + H + 0.01, 2e-3);
  /* Walking into its side from below its top: through. */
  f3d_real s[3] = {-4, F3D_R(2.0), 0};
  flags = f3d_world_move_character(w, R, H, s, 8, 0, 0, still, SLOPE_COS, 0,
                                   ~0u, 2u, 0u, 0, &gb, g);
  CHECK(!(flags & F3D_CHARACTER_WALL));
  CHECK_NEAR(s[0], 4, 1e-4);
  /* Not one-way: the same rise stops under it. */
  f3d_real c[3] = {0, STANDING, 0};
  flags = f3d_world_move_character(w, R, H, c, 0, 3, 0, still, SLOPE_COS, 0,
                                   ~0u, 0u, 0u, 0, &gb, g);
  CHECK(flags & F3D_CHARACTER_CEILING);
  CHECK(c[1] < 1.9 - R - H + 0.02);
  f3d_world_destroy(w);
}

/* A step lower than the capsule's radius, met by the round of its foot as a
 * slope: climbed, not ridden on its edge; not climbed by a body that was
 * not standing; and the speed into a wall taken out, along it kept. */
static void test_step_and_speed(void) {
  F3dWorld *w = f3d_world_create();
  const F3dQuat identity = {0, 0, 0, 1};
  fixed_shape(w, F3D_SHAPE_BOX, 50, F3D_R(0.5), 50, f3d_v3(0, F3D_R(-0.5), 0),
              identity);
  /* A riser of 0.2 from z = 3 on; the capsule's radius is 0.3. */
  fixed_shape(w, F3D_SHAPE_BOX, 2, F3D_R(0.1), 3, f3d_v3(0, F3D_R(0.1), 6),
              identity);
  /* A wall across x = 10. */
  fixed_shape(w, F3D_SHAPE_BOX, F3D_R(0.5), 2, 20, f3d_v3(F3D_R(10.5), 2, 0),
              identity);
  F3dBody gb;
  f3d_real g[3];
  f3d_real p[3] = {0, STANDING, F3D_R(2.0)};
  f3d_real v[3] = {0, 0, 6};
  uint32_t flags = 0;
  for (int i = 0; i < 30; i++) {
    flags = f3d_world_move_character(w, R, H, p, 0, F3D_R(-0.0167), F3D_R(0.1),
                                     v, SLOPE_COS, F3D_R(0.35), ~0u, 0u,
                                     F3D_CHARACTER_MAY_STEP, 0, &gb, g);
  }
  CHECK(flags & F3D_CHARACTER_GROUNDED);
  CHECK_NEAR(p[1], 0.2 + STANDING, 3e-3);
  CHECK(p[2] > 4.5);
  /* In the air, the same riser stops it: it may not step. */
  f3d_real a[3] = {0, STANDING, F3D_R(2.5)};
  f3d_real va[3] = {0, 0, 6};
  for (int i = 0; i < 10; i++) {
    f3d_world_move_character(w, R, H, a, 0, 0, F3D_R(0.1), va, SLOPE_COS,
                             F3D_R(0.35), ~0u, 0u, 0u, 0, &gb, g);
  }
  CHECK(a[2] < 3.0);
  CHECK(a[1] < STANDING + 0.1);
  /* Into the wall at a slant: the speed into it gone, along it kept. */
  f3d_real q[3] = {9, STANDING, 0};
  f3d_real vq[3] = {3, 0, 4};
  flags = f3d_world_move_character(w, R, H, q, 1, 0, F3D_R(0.1), vq, SLOPE_COS,
                                   F3D_R(0.35), ~0u, 0u, F3D_CHARACTER_MAY_STEP,
                                   0, &gb, g);
  CHECK(flags & F3D_CHARACTER_WALL);
  CHECK_NEAR(vq[0], 0, 1e-5);
  CHECK_NEAR(vq[2], 4, 1e-5);
  f3d_world_destroy(w);
}

int main(void) {
  test_rays_on_shapes();
  test_nearest_and_all();
  test_rays_against_every_ball();
  test_overlaps_and_casts();
  test_character();
  test_one_way();
  test_step_and_speed();
  return finish();
}
