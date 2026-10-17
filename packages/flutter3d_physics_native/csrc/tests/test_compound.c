/*
 * Compound shapes, tested in C: what a compound refuses, its centre of
 * mass and inertia against the closed forms, a dumbbell and a table at rest
 * on a floor, a ray between a dumbbell's balls, two compounds stacked, a
 * hull as a part, and compounds in a snapshot.
 */
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "check.h"

/* One part: kind, size, place; unturned, unrounded. */
typedef struct Part {
  uint32_t kind;
  f3d_real a, b, c;
  f3d_real x, y, z;
} Part;

static uint32_t compound_of(F3dWorld *w, const Part *parts, uint32_t n,
                            const F3dQuat *turns) {
  uint32_t kinds[F3D_COMPOUND_MOST_PARTS + 1];
  f3d_real reals[(F3D_COMPOUND_MOST_PARTS + 1) * F3D_COMPOUND_PART_FLOATS];
  for (uint32_t i = 0; i < n; i++) {
    f3d_real *r = &reals[i * F3D_COMPOUND_PART_FLOATS];
    kinds[i] = parts[i].kind;
    r[0] = parts[i].a;
    r[1] = parts[i].b;
    r[2] = parts[i].c;
    r[3] = 0;
    r[4] = parts[i].x;
    r[5] = parts[i].y;
    r[6] = parts[i].z;
    const F3dQuat q = turns != NULL ? turns[i] : (F3dQuat){0, 0, 0, 1};
    r[7] = q.x;
    r[8] = q.y;
    r[9] = q.z;
    r[10] = q.w;
  }
  return f3d_world_create_compound(w, kinds, NULL, reals, n);
}

static F3dWorld *floored(void) {
  F3dWorld *w = f3d_world_create();
  const F3dBody floor = f3d_body_create(w, F3D_BODY_FIXED, 0, F3D_R(-0.5), 0, 0);
  f3d_body_set_shape(w, floor, F3D_SHAPE_BOX, 20, F3D_R(0.5), 20);
  return w;
}

static void run(F3dWorld *w, int steps) {
  for (int i = 0; i < steps; i++) f3d_world_step(w, F3D_R(1.0) / 60);
}

static void test_refusals(void) {
  F3dWorld *w = f3d_world_create();
  const Part ball = {F3D_SHAPE_SPHERE, F3D_R(0.2), 0, 0, 0, 0, 0};
  CHECK(compound_of(w, &ball, 0, NULL) == 0);
  Part many[F3D_COMPOUND_MOST_PARTS + 1];
  for (uint32_t i = 0; i <= F3D_COMPOUND_MOST_PARTS; i++) many[i] = ball;
  CHECK(compound_of(w, many, F3D_COMPOUND_MOST_PARTS + 1, NULL) == 0);
  CHECK(compound_of(w, many, F3D_COMPOUND_MOST_PARTS, NULL) == 1);
  const Part mesh = {F3D_SHAPE_MESH, 1, 1, 1, 0, 0, 0};
  const Part point = {F3D_SHAPE_POINT, 0, 0, 0, 0, 0, 0};
  const Part nested = {F3D_SHAPE_COMPOUND, 1, 1, 1, 0, 0, 0};
  const Part flat = {F3D_SHAPE_BOX, 1, 0, 1, 0, 0, 0};
  const Part lost = {F3D_SHAPE_SPHERE, F3D_R(0.2), 0, 0, nan_value(), 0, 0};
  CHECK(compound_of(w, &mesh, 1, NULL) == 0);
  CHECK(compound_of(w, &point, 1, NULL) == 0);
  CHECK(compound_of(w, &nested, 1, NULL) == 0);
  CHECK(compound_of(w, &flat, 1, NULL) == 0);
  CHECK(compound_of(w, &lost, 1, NULL) == 0);
  const F3dQuat none = {0, 0, 0, 0};
  CHECK(compound_of(w, &ball, 1, &none) == 0);
  /* A hull part names a hull the world holds. */
  const uint32_t kind = F3D_SHAPE_HULL;
  f3d_real r[F3D_COMPOUND_PART_FLOATS] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1};
  const uint32_t missing = 3;
  CHECK(f3d_world_create_compound(w, &kind, NULL, r, 1) == 0);
  CHECK(f3d_world_create_compound(w, &kind, &missing, r, 1) == 0);
  CHECK(f3d_world_compound_part_count(w, 1) == F3D_COMPOUND_MOST_PARTS);
  CHECK(f3d_world_compound_part_count(w, 2) == 0);
  const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 1);
  CHECK(f3d_body_set_compound(w, b, 2) == 0);
  CHECK(f3d_body_set_compound(w, b, 1) == 1);
  f3d_world_destroy(w);
}

static void test_mass(void) {
  F3dWorld *w = f3d_world_create();
  /* A dumbbell: two balls of 0.2 m half a metre either side, plus a third
   * ball off to one side that moves the centre a third of the way to it. */
  const Part dumbbell[2] = {{F3D_SHAPE_SPHERE, F3D_R(0.2), 0, 0, F3D_R(-0.5), 0, 0},
                            {F3D_SHAPE_SPHERE, F3D_R(0.2), 0, 0, F3D_R(0.5), 0, 0}};
  const uint32_t d = compound_of(w, dumbbell, 2, NULL);
  f3d_real offset[3];
  CHECK(f3d_world_get_compound_offset(w, d, offset) == 1);
  CHECK_NEAR(offset[0], 0, 1e-6);
  const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 2);
  f3d_body_set_compound(w, b, d);
  f3d_real inertia[6];
  f3d_body_get_inertia_tensor(w, b, inertia);
  /* Each ball a kilogram: 2/5 m r² about its own centre, and m d² more
   * across the bar. */
  const double own = 0.4 * 1 * 0.04;
  CHECK_NEAR(inertia[0], 2 * own, 1e-5);
  CHECK_NEAR(inertia[1], 2 * (own + 0.25), 1e-5);
  CHECK_NEAR(inertia[2], 2 * (own + 0.25), 1e-5);
  CHECK_NEAR(inertia[3], 0, 1e-6);

  const Part three[3] = {{F3D_SHAPE_SPHERE, F3D_R(0.2), 0, 0, 0, 0, 0},
                         {F3D_SHAPE_SPHERE, F3D_R(0.2), 0, 0, 0, 0, 0},
                         {F3D_SHAPE_SPHERE, F3D_R(0.2), 0, 0, 0, F3D_R(0.9), 0}};
  const uint32_t t = compound_of(w, three, 3, NULL);
  f3d_world_get_compound_offset(w, t, offset);
  CHECK_NEAR(offset[1], 0.3, 1e-6);

  /* One box turned a quarter about z is the box with x and y swapped. */
  const double s = sqrt(0.5);
  const F3dQuat quarter = {0, 0, (f3d_real)s, (f3d_real)s};
  const Part slab = {F3D_SHAPE_BOX, F3D_R(0.5), F3D_R(0.1), F3D_R(0.2), 0, 0, 0};
  const F3dBody turned = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 3);
  f3d_body_set_compound(w, turned, compound_of(w, &slab, 1, &quarter));
  const F3dBody plain = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 3);
  f3d_body_set_shape(w, plain, F3D_SHAPE_BOX, F3D_R(0.1), F3D_R(0.5), F3D_R(0.2));
  f3d_real a[6], p[6];
  f3d_body_get_inertia_tensor(w, turned, a);
  f3d_body_get_inertia_tensor(w, plain, p);
  for (int k = 0; k < 6; k++) CHECK_NEAR(a[k], p[k], 1e-5);
  f3d_world_destroy(w);
}

static void test_dumbbell_rests_level(void) {
  F3dWorld *w = floored();
  /* The bar along x, its balls touching the floor: both ends must hold it.
   * Joined along the deepest part's normal, both balls' points share it. */
  const Part dumbbell[3] = {{F3D_SHAPE_SPHERE, F3D_R(0.2), 0, 0, F3D_R(-0.5), 0, 0},
                            {F3D_SHAPE_SPHERE, F3D_R(0.2), 0, 0, F3D_R(0.5), 0, 0},
                            {F3D_SHAPE_CAPSULE, F3D_R(0.04), F3D_R(0.4), 0, 0, 0, 0}};
  const double s = sqrt(0.5);
  const F3dQuat along_x[3] = {{0, 0, 0, 1}, {0, 0, 0, 1},
                              {0, 0, (f3d_real)s, (f3d_real)s}};
  const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, F3D_R(0.5), 0, 4);
  f3d_body_set_compound(w, b, compound_of(w, dumbbell, 3, along_x));
  run(w, 180);
  f3d_real at[3], q[4], v[3];
  f3d_body_get_position(w, b, at);
  f3d_body_get_orientation(w, b, q);
  f3d_body_get_velocity(w, b, v);
  CHECK_NEAR(at[1], 0.2, 0.01);
  CHECK(fabs((double)q[0]) < 1e-3 && fabs((double)q[2]) < 1e-3);
  CHECK(fabs((double)v[1]) < 1e-2);
  f3d_world_destroy(w);
}

static void test_table_stands(void) {
  F3dWorld *w = floored();
  /* A top 1.2 × 0.05 × 0.8 on four legs 0.7 high: it stands on its legs,
   * the top 0.725 above the floor. */
  const Part table[5] = {
      {F3D_SHAPE_BOX, F3D_R(0.6), F3D_R(0.025), F3D_R(0.4), 0, F3D_R(0.725), 0},
      {F3D_SHAPE_BOX, F3D_R(0.03), F3D_R(0.35), F3D_R(0.03), F3D_R(-0.55), F3D_R(0.35), F3D_R(-0.35)},
      {F3D_SHAPE_BOX, F3D_R(0.03), F3D_R(0.35), F3D_R(0.03), F3D_R(0.55), F3D_R(0.35), F3D_R(-0.35)},
      {F3D_SHAPE_BOX, F3D_R(0.03), F3D_R(0.35), F3D_R(0.03), F3D_R(-0.55), F3D_R(0.35), F3D_R(0.35)},
      {F3D_SHAPE_BOX, F3D_R(0.03), F3D_R(0.35), F3D_R(0.03), F3D_R(0.55), F3D_R(0.35), F3D_R(0.35)}};
  const uint32_t c = compound_of(w, table, 5, NULL);
  f3d_real offset[3];
  f3d_world_get_compound_offset(w, c, offset);
  const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, offset[1] + F3D_R(0.05), 0, 20);
  f3d_body_set_compound(w, b, c);
  run(w, 240);
  f3d_real at[3], q[4];
  f3d_body_get_position(w, b, at);
  f3d_body_get_orientation(w, b, q);
  CHECK_NEAR(at[1], offset[1], 0.01);
  CHECK(fabs((double)q[0]) < 1e-3 && fabs((double)q[2]) < 1e-3);
  /* A ball dropped on the top lands on it, not on the floor beneath. */
  const F3dBody ball = f3d_body_create(w, F3D_BODY_DYNAMIC, F3D_R(0.1), 2, 0, F3D_R(0.5));
  f3d_body_set_shape(w, ball, F3D_SHAPE_SPHERE, F3D_R(0.1), 0, 0);
  run(w, 120);
  f3d_body_get_position(w, ball, at);
  CHECK_NEAR(at[1], 0.85, 0.01);
  f3d_world_destroy(w);
}

static void test_rays(void) {
  F3dWorld *w = f3d_world_create();
  f3d_world_set_gravity(w, 0, 0, 0);
  const Part dumbbell[2] = {{F3D_SHAPE_SPHERE, F3D_R(0.2), 0, 0, F3D_R(-0.5), 0, 0},
                            {F3D_SHAPE_SPHERE, F3D_R(0.2), 0, 0, F3D_R(0.5), 0, 0}};
  const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 1);
  f3d_body_set_compound(w, b, compound_of(w, dumbbell, 2, NULL));
  f3d_world_step(w, F3D_R(1.0) / 60);
  F3dBody hit_body = 0;
  f3d_real hit[7];
  /* Down onto the right ball: met at its top. */
  CHECK(f3d_world_ray_cast(w, F3D_R(0.5), 3, 0, 0, -1, 0, 10, ~0u, 0, &hit_body, hit) == 1);
  CHECK(hit_body == b);
  CHECK_NEAR(hit[1], 0.2, 1e-4);
  CHECK_NEAR(hit[4], 1, 1e-4);
  /* Along the bar from the left: the nearer ball. */
  CHECK(f3d_world_ray_cast(w, -3, 0, 0, 1, 0, 0, 10, ~0u, 0, &hit_body, hit) == 1);
  CHECK_NEAR(hit[0], -0.7, 1e-4);
  /* Down between them, where there is no part: nothing. */
  CHECK(f3d_world_ray_cast(w, 0, 3, 0, 0, -1, 0, 10, ~0u, 0, &hit_body, hit) == 0);
  f3d_world_destroy(w);
}

static void test_stacked(void) {
  F3dWorld *w = floored();
  /* Two crosses of two boxes each, one dropped on the other: compound on
   * compound, every pair of parts tried. */
  const double s = sqrt(0.5);
  const F3dQuat turns[2] = {{0, 0, 0, 1}, {0, (f3d_real)s, 0, (f3d_real)s}};
  const Part cross[2] = {{F3D_SHAPE_BOX, F3D_R(0.5), F3D_R(0.1), F3D_R(0.1), 0, 0, 0},
                         {F3D_SHAPE_BOX, F3D_R(0.5), F3D_R(0.1), F3D_R(0.1), 0, 0, 0}};
  const uint32_t c = compound_of(w, cross, 2, turns);
  const F3dBody low = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, F3D_R(0.1), 0, 2);
  const F3dBody high = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, F3D_R(0.6), 0, 2);
  f3d_body_set_compound(w, low, c);
  f3d_body_set_compound(w, high, c);
  run(w, 240);
  f3d_real a[3], b[3];
  f3d_body_get_position(w, low, a);
  f3d_body_get_position(w, high, b);
  CHECK_NEAR(a[1], 0.1, 0.01);
  CHECK_NEAR(b[1], 0.3, 0.01);
  /* A compound's ball on a small block: the parts' spheres only just
   * meet, so a pair skipped by too tight a reach falls through. */
  const F3dBody block = f3d_body_create(w, F3D_BODY_FIXED, 5, F3D_R(0.2), 0, 0);
  f3d_body_set_shape(w, block, F3D_SHAPE_BOX, F3D_R(0.2), F3D_R(0.2), F3D_R(0.2));
  const Part ball = {F3D_SHAPE_SPHERE, F3D_R(0.2), 0, 0, 0, 0, 0};
  const F3dBody on = f3d_body_create(w, F3D_BODY_DYNAMIC, 5, F3D_R(0.7), 0, 1);
  f3d_body_set_compound(w, on, compound_of(w, &ball, 1, NULL));
  run(w, 120);
  f3d_body_get_position(w, on, a);
  CHECK_NEAR(a[1], 0.6, 0.01);
  f3d_world_destroy(w);
}

static void test_hull_part(void) {
  F3dWorld *w = floored();
  /* A cube hull half a metre on a side as the one part, moved up a metre
   * in the compound: it rests like the hull alone. */
  const f3d_real corners[24] = {-F3D_R(0.25), -F3D_R(0.25), -F3D_R(0.25),
                                F3D_R(0.25),  -F3D_R(0.25), -F3D_R(0.25),
                                -F3D_R(0.25), F3D_R(0.25),  -F3D_R(0.25),
                                F3D_R(0.25),  F3D_R(0.25),  -F3D_R(0.25),
                                -F3D_R(0.25), -F3D_R(0.25), F3D_R(0.25),
                                F3D_R(0.25),  -F3D_R(0.25), F3D_R(0.25),
                                -F3D_R(0.25), F3D_R(0.25),  F3D_R(0.25),
                                F3D_R(0.25),  F3D_R(0.25),  F3D_R(0.25)};
  const uint32_t hull = f3d_world_create_hull(w, corners, 8);
  const uint32_t kind = F3D_SHAPE_HULL;
  const f3d_real r[F3D_COMPOUND_PART_FLOATS] = {0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1};
  const uint32_t c = f3d_world_create_compound(w, &kind, &hull, r, 1);
  CHECK(c != 0);
  f3d_real offset[3];
  f3d_world_get_compound_offset(w, c, offset);
  CHECK_NEAR(offset[1], 1, 1e-6);
  const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 1, 0, 1);
  f3d_body_set_compound(w, b, c);
  f3d_real inertia[3];
  f3d_body_get_inertia(w, b, inertia);
  CHECK_NEAR(inertia[0], 1.0 / 3 * (0.0625 + 0.0625), 1e-4);
  run(w, 180);
  f3d_real at[3];
  f3d_body_get_position(w, b, at);
  CHECK_NEAR(at[1], 0.25, 0.01);
  f3d_world_destroy(w);
}

static void test_snapshot(void) {
  F3dWorld *w = floored();
  const Part dumbbell[2] = {{F3D_SHAPE_SPHERE, F3D_R(0.2), 0, 0, F3D_R(-0.5), 0, 0},
                            {F3D_SHAPE_BOX, F3D_R(0.2), F3D_R(0.2), F3D_R(0.2), F3D_R(0.5), 0, 0}};
  const uint32_t c = compound_of(w, dumbbell, 2, NULL);
  for (int i = 0; i < 4; i++) {
    const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, (f3d_real)i * F3D_R(0.3),
                                      F3D_R(0.5) + (f3d_real)i * F3D_R(0.6), 0, 2);
    f3d_body_set_compound(w, b, c);
    f3d_body_set_angular_velocity(w, b, (f3d_real)i, 1, 0);
  }
  run(w, 30);
  const uint32_t size = f3d_world_snapshot_size(w);
  uint8_t *bytes = (uint8_t *)malloc(size);
  CHECK(f3d_world_snapshot_write(w, bytes, size) == size);
  F3dWorld *copy = f3d_world_create();
  CHECK(f3d_world_restore(copy, bytes, size) == 1);
  CHECK(f3d_world_compound_part_count(copy, c) == 2);
  run(w, 120);
  run(copy, 120);
  f3d_real ta[7 * 8], tb[7 * 8];
  const uint32_t na = f3d_world_read_transforms(w, ta, NULL, 8);
  const uint32_t nb = f3d_world_read_transforms(copy, tb, NULL, 8);
  CHECK(na == nb && na == 5);
  CHECK(memcmp(ta, tb, (size_t)na * 7 * sizeof(f3d_real)) == 0);
  free(bytes);
  f3d_world_destroy(w);
  f3d_world_destroy(copy);
}

int main(void) {
  test_refusals();
  test_mass();
  test_dumbbell_rests_level();
  test_table_stands();
  test_rays();
  test_stacked();
  test_hull_part();
  test_snapshot();
  return finish();
}
