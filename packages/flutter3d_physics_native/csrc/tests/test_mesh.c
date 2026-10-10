/*
 * Triangle meshes, tested in C — P9, phase 6: a mesh built and its internal
 * edges found, bodies of every shape resting on one, a crate sliding over a
 * fine grid without tripping on its seams, a mesh seen from behind letting
 * a body through, a ball rolling down a sloped mesh at 5/7 g sin θ, and a
 * mesh through a snapshot.
 */
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "check.h"

/* A flat grid of n × n squares, 2·half across, in the plane y = 0, each
 * square two triangles facing up, its vertices shared. Turned by [q]. */
static uint32_t grid(F3dWorld *w, int n, double half, F3dQuat q, F3dBody *body) {
  const int side = n + 1;
  f3d_real *v = (f3d_real *)malloc((size_t)side * side * 3 * sizeof(f3d_real));
  uint32_t *t = (uint32_t *)malloc((size_t)n * n * 6 * sizeof(uint32_t));
  for (int j = 0; j < side; j++) {
    for (int i = 0; i < side; i++) {
      f3d_real *p = &v[(j * side + i) * 3];
      p[0] = (f3d_real)(-half + 2 * half * i / n);
      p[1] = 0;
      p[2] = (f3d_real)(-half + 2 * half * j / n);
    }
  }
  int k = 0;
  for (int j = 0; j < n; j++) {
    for (int i = 0; i < n; i++) {
      const uint32_t v00 = (uint32_t)(j * side + i), v10 = v00 + 1;
      const uint32_t v01 = v00 + (uint32_t)side, v11 = v01 + 1;
      t[k++] = v00;
      t[k++] = v11;
      t[k++] = v10;
      t[k++] = v00;
      t[k++] = v01;
      t[k++] = v11;
    }
  }
  const uint32_t mesh =
      f3d_world_create_mesh(w, v, (uint32_t)(side * side), t, (uint32_t)(n * n * 2));
  free(v);
  free(t);
  if (body != NULL) {
    *body = f3d_body_create(w, F3D_BODY_FIXED, 0, 0, 0, 0);
    f3d_body_set_mesh(w, *body, mesh);
    f3d_body_set_orientation(w, *body, q.x, q.y, q.z, q.w);
  }
  return mesh;
}

static const F3dQuat identity = {0, 0, 0, 1};

static F3dQuat turn_about(F3dVec3 axis, double angle) {
  const double s = sin(angle / 2);
  F3dQuat q = {(f3d_real)(axis.x * s), (f3d_real)(axis.y * s),
               (f3d_real)(axis.z * s), (f3d_real)cos(angle / 2)};
  return q;
}

static void run(F3dWorld *w, int steps) {
  for (int i = 0; i < steps; i++) f3d_world_step(w, F3D_R(1.0 / 60.0));
}

static void test_building(void) {
  F3dWorld *w = f3d_world_create();
  /* A grid of four by four: 32 triangles, 56 edges, 16 round the rim,
   * the other 40 shared across a flat fold. */
  const uint32_t mesh = grid(w, 4, 2, identity, NULL);
  CHECK(mesh == 1);
  CHECK(f3d_world_mesh_triangle_count(w, mesh) == 32);
  CHECK(f3d_world_mesh_internal_edges(w, mesh) == 40);
  /* Two triangles folded along z: as a tent, the fold sticks out and is a
   * real edge; as a dip, it is hollow and internal. */
  const f3d_real tent_v[12] = {0, 1, -1, 0, 1, 1, -1, 0, 0, 1, 0, 0};
  const uint32_t tent_t[6] = {0, 1, 3, 0, 2, 1};
  const uint32_t tent = f3d_world_create_mesh(w, tent_v, 4, tent_t, 2);
  CHECK(f3d_world_mesh_internal_edges(w, tent) == 0);
  const f3d_real dip_v[12] = {0, 0, -1, 0, 0, 1, -1, 1, 0, 1, 1, 0};
  const uint32_t dip = f3d_world_create_mesh(w, dip_v, 4, tent_t, 2);
  CHECK(f3d_world_mesh_internal_edges(w, dip) == 1);
  /* Refused: no triangles, an index past the vertices, a vertex not
   * finite; and a dynamic body cannot be a mesh. */
  const uint32_t bad_t[3] = {0, 1, 9};
  CHECK(f3d_world_create_mesh(w, tent_v, 4, bad_t, 1) == 0);
  CHECK(f3d_world_create_mesh(w, tent_v, 4, tent_t, 0) == 0);
  f3d_real nan_v[12];
  memcpy(nan_v, tent_v, sizeof nan_v);
  nan_v[5] = nan_value();
  CHECK(f3d_world_create_mesh(w, nan_v, 4, tent_t, 2) == 0);
  const F3dBody moving = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 1);
  CHECK(f3d_body_set_mesh(w, moving, mesh) == 0);
  f3d_world_destroy(w);
}

static void test_resting(void) {
  F3dWorld *w = f3d_world_create();
  f3d_world_set_air(w, F3D_STANDARD_AIR_TEMPERATURE, F3D_R(1e-30));
  F3dBody ground;
  grid(w, 10, 10, identity, &ground);
  const f3d_real pts[24] = {-.4f, -.4f, -.4f, .4f, -.4f, -.4f, -.4f, .4f, -.4f, .4f, .4f, -.4f,
                            -.4f, -.4f, .4f,  .4f, -.4f, .4f,  -.4f, .4f, .4f,  .4f, .4f, .4f};
  const uint32_t hull = f3d_world_create_hull(w, pts, 8);
  /* A ball over a triangle's middle and one over a vertex; a crate across
   * a seam; a capsule lying down; a cylinder on end; a hull cube. */
  const F3dBody ball = f3d_body_create(w, F3D_BODY_DYNAMIC, F3D_R(0.3), F3D_R(0.31), F3D_R(0.7), 1);
  f3d_body_set_shape(w, ball, F3D_SHAPE_SPHERE, F3D_R(0.3), 0, 0);
  const F3dBody on_vertex = f3d_body_create(w, F3D_BODY_DYNAMIC, 2, F3D_R(0.31), 2, 1);
  f3d_body_set_shape(w, on_vertex, F3D_SHAPE_SPHERE, F3D_R(0.3), 0, 0);
  const F3dBody crate = f3d_body_create(w, F3D_BODY_DYNAMIC, -3, F3D_R(0.51), F3D_R(-3.0), 1);
  f3d_body_set_shape(w, crate, F3D_SHAPE_BOX, F3D_R(0.5), F3D_R(0.5), F3D_R(0.5));
  const F3dBody log = f3d_body_create(w, F3D_BODY_DYNAMIC, 4, F3D_R(0.21), -4, 1);
  f3d_body_set_shape(w, log, F3D_SHAPE_CAPSULE, F3D_R(0.2), F3D_R(0.7), 0);
  const F3dQuat lying = turn_about(f3d_v3(0, 0, 1), M_PI / 2);
  f3d_body_set_orientation(w, log, lying.x, lying.y, lying.z, lying.w);
  const F3dBody can = f3d_body_create(w, F3D_BODY_DYNAMIC, -5, F3D_R(0.61), 5, 1);
  f3d_body_set_shape(w, can, F3D_SHAPE_CYLINDER, F3D_R(0.3), F3D_R(0.6), 0);
  const F3dBody cube = f3d_body_create(w, F3D_BODY_DYNAMIC, 6, F3D_R(0.41), 0, 1);
  f3d_body_set_hull(w, cube, hull);
  run(w, 240);
  const F3dBody bodies[6] = {ball, on_vertex, crate, log, can, cube};
  const double heights[6] = {0.3, 0.3, 0.5, 0.2, 0.6, 0.4};
  for (int k = 0; k < 6; k++) {
    f3d_real p[3];
    f3d_body_get_position(w, bodies[k], p);
    CHECK(fabs((double)p[1] - heights[k]) < 0.01);
    CHECK(f3d_body_is_asleep(w, bodies[k]));
  }
  /* The crate rests on four points, across the triangles it spans. */
  int crate_points = 0;
  for (uint32_t i = 0; i < w->s.manifold_count; i++) {
    const F3dManifold *m = &w->manifolds[i];
    if (m->b == crate || m->a == crate) crate_points = (int)m->count;
  }
  CHECK(crate_points == 4);
  /* The box query finds the ground. */
  F3dBody found[8];
  CHECK(f3d_world_query_box(w, -1, -1, -1, 1, 1, 1, found, 8) >= 2);
  CHECK(found[0] == ground);
  f3d_world_destroy(w);
}

/* A crate slid across a grid of fine triangles at five metres a second on
 * no friction: the most it moves up or down. Its face meets the triangles'
 * faces, so this holds the merging of their contacts into one manifold;
 * the internal edges are held by the ball rolling down a mesh, whose
 * contacts land on seams. */
static double slide(void) {
  F3dWorld *w = f3d_world_create();
  f3d_world_set_air(w, F3D_STANDARD_AIR_TEMPERATURE, F3D_R(1e-30));
  f3d_world_set_sleep(w, 0, 0);
  F3dBody ground;
  grid(w, 100, 10, identity, &ground);
  f3d_body_set_friction(w, ground, 0);
  const F3dBody crate = f3d_body_create(w, F3D_BODY_DYNAMIC, -8, F3D_R(0.25), F3D_R(0.03), 1);
  f3d_body_set_shape(w, crate, F3D_SHAPE_BOX, F3D_R(0.25), F3D_R(0.25), F3D_R(0.25));
  f3d_body_set_friction(w, crate, 0);
  run(w, 30);
  f3d_body_set_velocity(w, crate, 5, 0, 0);
  double most = 0;
  for (int i = 0; i < 150; i++) {
    f3d_world_step(w, F3D_R(1.0 / 60.0));
    f3d_real v[3];
    f3d_body_get_velocity(w, crate, v);
    if (fabs((double)v[1]) > most) most = fabs((double)v[1]);
  }
  f3d_world_destroy(w);
  return most;
}

static void test_no_bumps_at_seams(void) {
  const double smooth = slide();
  CHECK(smooth < 0.05);
}

/* A corner of a room as one mesh: a floor four metres square at y = 0 and
 * a wall two metres high along x = 1, facing back into the room. */
static F3dBody corner(F3dWorld *w) {
  const f3d_real v[] = {-2, 0, -2, 1, 0, -2, 1, 0, 2, -2, 0, 2,
                        1,  2, -2, 1, 2, 2};
  /* The floor faces up; the wall faces −x. */
  const uint32_t t[] = {0, 3, 2, 0, 2, 1, 1, 2, 5, 1, 5, 4};
  const uint32_t mesh = f3d_world_create_mesh(w, v, 6, t, 4);
  const F3dBody b = f3d_body_create(w, F3D_BODY_FIXED, 0, 0, 0, 0);
  f3d_body_set_mesh(w, b, mesh);
  /* No friction: what comes at the wall reaches it at full speed. */
  f3d_body_set_friction(w, b, 0);
  return b;
}

/* How far [body], [half] across in x and [low] below its origin, ends up
 * into the floor and into the wall at worst, run into the corner at three
 * metres a second. */
static void into_corner(F3dWorld *w, F3dBody body, double half, double low,
                        double *floor, double *wall) {
  f3d_body_set_friction(w, body, 0);
  f3d_body_set_velocity(w, body, 3, 0, 0);
  *floor = 0;
  *wall = 0;
  for (int i = 0; i < 120; i++) {
    f3d_world_step(w, F3D_R(1.0 / 60.0));
    f3d_real p[3];
    f3d_body_get_position(w, body, p);
    if (low - (double)p[1] > *floor) *floor = low - (double)p[1];
    if ((double)p[0] + half - 1 > *wall) *wall = (double)p[0] + half - 1;
  }
}

static void test_corner(void) {
  /* A box run into the corner rests on the floor and stops at the wall:
   * the mesh meets it with two faces, and both hold. With one manifold a
   * pair, the deeper face's, the other face let it in. */
  F3dWorld *w = f3d_world_create();
  f3d_world_set_sleep(w, 0, 0);
  corner(w);
  const F3dBody box = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, F3D_R(0.25), 0, 1);
  f3d_body_set_shape(w, box, F3D_SHAPE_BOX, F3D_R(0.25), F3D_R(0.25), F3D_R(0.25));
  run(w, 20);
  double floor, wall;
  into_corner(w, box, 0.25, 0.25, &floor, &wall);
  CHECK(floor < 0.01);
  CHECK(wall < 0.01);
  /* Pressed into the corner, it has two manifolds with the room. */
  f3d_body_set_velocity(w, box, 1, 0, 0);
  f3d_world_step(w, F3D_R(1.0 / 60.0));
  int manifolds = 0;
  for (uint32_t i = 0; i < w->s.manifold_count; i++) {
    if (w->manifolds[i].b == box || w->manifolds[i].a == box) manifolds++;
  }
  CHECK(manifolds == 2);
  f3d_world_destroy(w);
  /* A bench of three boxes, one body, the same. */
  w = f3d_world_create();
  f3d_world_set_sleep(w, 0, 0);
  corner(w);
  const uint32_t kinds[3] = {F3D_SHAPE_BOX, F3D_SHAPE_BOX, F3D_SHAPE_BOX};
  f3d_real reals[3 * F3D_COMPOUND_PART_FLOATS] = {0};
  const f3d_real parts[3][6] = {{0, F3D_R(0.45), 0, F3D_R(0.4), F3D_R(0.05), F3D_R(0.2)},
                                {F3D_R(-0.35), F3D_R(0.2), 0, F3D_R(0.05), F3D_R(0.2), F3D_R(0.2)},
                                {F3D_R(0.35), F3D_R(0.2), 0, F3D_R(0.05), F3D_R(0.2), F3D_R(0.2)}};
  for (int k = 0; k < 3; k++) {
    f3d_real *r = &reals[k * F3D_COMPOUND_PART_FLOATS];
    /* Size, rounding, place, turn. */
    r[0] = parts[k][3];
    r[1] = parts[k][4];
    r[2] = parts[k][5];
    r[4] = parts[k][0];
    r[5] = parts[k][1];
    r[6] = parts[k][2];
    r[10] = 1;
  }
  const uint32_t bench_shape = f3d_world_create_compound(w, kinds, NULL, reals, 3);
  CHECK(bench_shape != 0);
  f3d_real offset[3];
  f3d_world_get_compound_offset(w, bench_shape, offset);
  const F3dBody bench = f3d_body_create(w, F3D_BODY_DYNAMIC, -1, offset[1], 0, 5);
  CHECK(f3d_body_set_compound(w, bench, bench_shape) == 1);
  run(w, 30);
  into_corner(w, bench, 0.4, (double)offset[1], &floor, &wall);
  CHECK(floor < 0.01);
  CHECK(wall < 0.01);
  f3d_world_destroy(w);
}

static void test_one_sided(void) {
  /* A ball under the grid going up passes through it, as through the back
   * of a wall. */
  F3dWorld *w = f3d_world_create();
  f3d_world_set_gravity(w, 0, 0, 0);
  f3d_world_set_air(w, F3D_STANDARD_AIR_TEMPERATURE, F3D_R(1e-30));
  F3dBody ground;
  grid(w, 4, 4, identity, &ground);
  const F3dBody ball = f3d_body_create(w, F3D_BODY_DYNAMIC, F3D_R(0.3), -1, F3D_R(0.3), 1);
  f3d_body_set_shape(w, ball, F3D_SHAPE_SPHERE, F3D_R(0.2), 0, 0);
  f3d_body_set_velocity(w, ball, 0, 2, 0);
  run(w, 60);
  f3d_real p[3], v[3];
  f3d_body_get_position(w, ball, p);
  f3d_body_get_velocity(w, ball, v);
  CHECK(p[1] > F3D_R(0.5));
  CHECK_NEAR(v[1], 2, 1e-4);
  /* Resting half through it from below, it is left there: seen from
   * behind, the floor is not there to push it anywhere. */
  const F3dBody under = f3d_body_create(w, F3D_BODY_DYNAMIC, F3D_R(-1.3), F3D_R(-0.1), F3D_R(1.3), 1);
  f3d_body_set_shape(w, under, F3D_SHAPE_SPHERE, F3D_R(0.2), 0, 0);
  run(w, 30);
  f3d_body_get_position(w, under, p);
  CHECK_NEAR(p[1], -0.1, 1e-6);
  /* Coming down onto it from above, it stops. */
  f3d_body_set_velocity(w, ball, 0, -2, 0);
  run(w, 120);
  f3d_body_get_position(w, ball, p);
  CHECK(fabs((double)p[1] - 0.2) < 0.01);
  f3d_world_destroy(w);
}

/* Mutation: take the internal-edge snap out of f3d_collide_mesh — a ball
 * crossing seams is caught on their edges and rolls slow. */
static void test_rolling_down_a_mesh(void) {
  const double theta = M_PI / 6;
  const F3dQuat q = turn_about(f3d_v3(0, 0, 1), theta);
  const F3dMat3 m = f3d_mat_of(q);
  F3dWorld *w = f3d_world_create();
  f3d_world_set_air(w, F3D_STANDARD_AIR_TEMPERATURE, F3D_R(1e-30));
  f3d_world_set_sleep(w, 0, 0);
  F3dBody ground;
  grid(w, 40, 20, q, &ground);
  f3d_body_set_friction(w, ground, 1);
  const f3d_real r = F3D_R(0.2);
  const F3dVec3 at = f3d_scale(m.c[1], r - F3D_R(0.001));
  const F3dBody ball = f3d_body_create(w, F3D_BODY_DYNAMIC, at.x, at.y, at.z, 1);
  f3d_body_set_shape(w, ball, F3D_SHAPE_SPHERE, r, 0, 0);
  f3d_body_set_friction(w, ball, 1);
  run(w, 15);
  f3d_real v0[3], v1[3];
  f3d_body_get_velocity(w, ball, v0);
  run(w, 60);
  f3d_body_get_velocity(w, ball, v1);
  const double s0 = sqrt((double)v0[0] * v0[0] + (double)v0[1] * v0[1] + (double)v0[2] * v0[2]);
  const double s1 = sqrt((double)v1[0] * v1[0] + (double)v1[1] * v1[1] + (double)v1[2] * v1[2]);
  CHECK_NEAR(s1 - s0, 5.0 / 7.0 * STANDARD_G * sin(theta), 0.03);
  f3d_world_destroy(w);
}

static void test_snapshot(void) {
  F3dWorld *w = f3d_world_create();
  F3dBody ground;
  grid(w, 8, 8, identity, &ground);
  for (int i = 0; i < 5; i++) {
    const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, (f3d_real)i - 2, F3D_R(0.6), 0, 1);
    f3d_body_set_shape(w, b, (F3dShapeKind)(1 + i % 4), F3D_R(0.3), F3D_R(0.3), F3D_R(0.3));
  }
  run(w, 20);
  const uint32_t size = f3d_world_snapshot_size(w);
  uint8_t *snap = (uint8_t *)malloc(size);
  f3d_world_snapshot_write(w, snap, size);
  F3dWorld *v = f3d_world_create();
  CHECK(f3d_world_restore(v, snap, size) == 1);
  CHECK(v->s.mesh_count == 1 && v->mesh_tree_count == 0);
  run(w, 60);
  run(v, 60);
  CHECK(v->mesh_tree_count == 1);
  const uint32_t now = f3d_world_snapshot_size(w);
  CHECK(f3d_world_snapshot_size(v) == now);
  uint8_t *a = (uint8_t *)malloc(now), *b = (uint8_t *)malloc(now);
  f3d_world_snapshot_write(w, a, now);
  f3d_world_snapshot_write(v, b, now);
  CHECK(memcmp(a, b, now) == 0);
  free(snap);
  free(a);
  free(b);
  f3d_world_destroy(w);
  f3d_world_destroy(v);
}

int main(void) {
  test_building();
  test_resting();
  test_no_bumps_at_seams();
  test_corner();
  test_one_sided();
  test_rolling_down_a_mesh();
  test_snapshot();
  return finish();
}
