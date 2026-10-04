/*
 * Convex shapes, tested in C — P9, phase 5: GJK's distances and EPA's
 * depths against the closed forms, manifolds from faces and edges, hulls
 * built and weighed, rounded shapes, the inertia of every new shape, a
 * cylinder rolling down a slope at 2/3 g sin θ, and hulls in a snapshot.
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

static F3dPlaced shape(uint32_t kind, F3dVec3 size, F3dVec3 at, F3dQuat q) {
  F3dPlaced p;
  memset(&p, 0, sizeof p);
  p.kind = kind;
  p.size = size;
  p.at = at;
  p.axes = f3d_mat_of(q);
  return p;
}

static uint32_t collide(const F3dPlaced *a, const F3dPlaced *b, F3dManifold *m) {
  memset(m, 0, sizeof *m);
  return f3d_collide(a, b, F3D_R(0.02), m);
}

static const F3dPlaced *floor_box(void) {
  static F3dPlaced f;
  f = shape(F3D_SHAPE_BOX, f3d_v3(10, F3D_R(0.5), 10), f3d_v3(0, F3D_R(-0.5), 0),
            identity);
  return &f;
}

static void test_distances(void) {
  F3dManifold m;
  const F3dPlaced cyl = shape(F3D_SHAPE_CYLINDER, f3d_v3(F3D_R(0.5), 1, 0),
                              f3d_v3(0, 0, 0), identity);
  /* A box a centimetre from the cylinder's side: a gap within the margin,
   * straight out along x. */
  const F3dPlaced near = shape(F3D_SHAPE_BOX, f3d_v3(F3D_R(0.5), F3D_R(0.5), F3D_R(0.5)),
                               f3d_v3(F3D_R(1.01), 0, 0), identity);
  CHECK(collide(&near, &cyl, &m) > 0);
  CHECK_NEAR(m.normal.x, 1, 1e-4);
  for (uint32_t i = 0; i < m.count; i++) CHECK_NEAR(m.points[i].depth, -0.01, 1e-4);
  const F3dPlaced far = shape(F3D_SHAPE_BOX, f3d_v3(F3D_R(0.5), F3D_R(0.5), F3D_R(0.5)),
                              f3d_v3(F3D_R(1.05), 0, 0), identity);
  CHECK(collide(&far, &cyl, &m) == 0);
  /* Deep: a small cylinder sunk thirty-five centimetres into the top of a
   * big box goes out upwards, as deep as it is in. */
  const F3dPlaced big = shape(F3D_SHAPE_BOX, f3d_v3(1, 1, 1), f3d_v3(0, 0, 0), identity);
  const F3dPlaced plug = shape(F3D_SHAPE_CYLINDER, f3d_v3(F3D_R(0.25), F3D_R(0.25), 0),
                               f3d_v3(0, F3D_R(0.9), 0), identity);
  CHECK(collide(&plug, &big, &m) > 0);
  CHECK_NEAR(m.normal.y, 1, 1e-4);
  double deepest = -1;
  for (uint32_t i = 0; i < m.count; i++) deepest = fmax(deepest, m.points[i].depth);
  CHECK_NEAR(deepest, 0.35, 1e-4);
  /* A cone's apex a centimetre into a floor. */
  const F3dPlaced upside = shape(F3D_SHAPE_CONE, f3d_v3(F3D_R(0.3), 1, 0),
                                 f3d_v3(0, F3D_R(0.74), 0),
                                 turn_about(f3d_v3(1, 0, 0), M_PI));
  CHECK(collide(&upside, floor_box(), &m) == 1);
  CHECK_NEAR(m.points[0].depth, 0.01, 1e-4);
  CHECK_NEAR(m.normal.y, 1, 1e-4);
}

static void test_manifolds(void) {
  F3dManifold m;
  /* A cylinder standing on its end rests on four points of its rim. */
  const F3dPlaced standing = shape(F3D_SHAPE_CYLINDER, f3d_v3(F3D_R(0.5), 1, 0),
                                   f3d_v3(0, F3D_R(0.99), 0), identity);
  CHECK(collide(&standing, floor_box(), &m) == 4);
  for (uint32_t i = 0; i < m.count; i++) {
    CHECK_NEAR(m.points[i].depth, 0.01, 1e-4);
    const double r = sqrt((double)m.points[i].point.x * m.points[i].point.x +
                          (double)m.points[i].point.z * m.points[i].point.z);
    CHECK_NEAR(r, 0.5, 1e-4);
  }
  /* Lying on its side, along a line its length. */
  const F3dPlaced lying = shape(F3D_SHAPE_CYLINDER, f3d_v3(F3D_R(0.5), 1, 0),
                                f3d_v3(0, F3D_R(0.49), 0),
                                turn_about(f3d_v3(0, 0, 1), M_PI / 2));
  CHECK(collide(&lying, floor_box(), &m) == 2);
  CHECK_NEAR(fabs((double)(m.points[0].point.x - m.points[1].point.x)), 2, 1e-3);
  CHECK_NEAR(m.points[0].depth, 0.01, 1e-4);
  /* A cone on its base: four points; on its slant: two, apex and rim. */
  const F3dPlaced cone = shape(F3D_SHAPE_CONE, f3d_v3(F3D_R(0.4), 1, 0),
                               f3d_v3(0, F3D_R(0.24), 0), identity);
  CHECK(collide(&cone, floor_box(), &m) == 4);
  /* Tipped by a right angle and the half-angle α = atan(r / H), its
   * slant lies flat: lowered until the slant is a centimetre in, it rests
   * on apex and rim. */
  const double slope = atan(0.4 / 1.0);
  /* The slant's outward normal (H, r) turned to point straight down. */
  const F3dQuat tip = turn_about(f3d_v3(0, 0, 1), -(M_PI / 2 + slope));
  F3dPlaced tipped = shape(F3D_SHAPE_CONE, f3d_v3(F3D_R(0.4), 1, 0),
                           f3d_v3(0, 0, 0), tip);
  const F3dVec3 apex = f3d_madd(tipped.at, tipped.axes.c[1], F3D_R(0.75));
  const F3dVec3 rim = f3d_madd(f3d_madd(tipped.at, tipped.axes.c[1], F3D_R(-0.25)),
                               tipped.axes.c[0], F3D_R(0.4));
  CHECK_NEAR(apex.y, rim.y, 1e-5);
  tipped.at.y = -apex.y - F3D_R(0.01);
  CHECK(collide(&tipped, floor_box(), &m) == 2);
  CHECK_NEAR(m.points[0].depth, 0.01, 1e-3);
  CHECK_NEAR(m.points[1].depth, 0.01, 1e-3);
}

static F3dWorld *world_with_cube_hull(uint32_t *hull, f3d_real half) {
  F3dWorld *w = f3d_world_create();
  /* Eight corners, shifted by (1, 2, 3), and points inside that are not
   * corners. */
  f3d_real pts[3 * 11];
  int n = 0;
  for (int i = 0; i < 8; i++) {
    pts[n++] = F3D_R(1.0) + ((i & 1) ? half : -half);
    pts[n++] = F3D_R(2.0) + ((i & 2) ? half : -half);
    pts[n++] = F3D_R(3.0) + ((i & 4) ? half : -half);
  }
  const f3d_real inside[9] = {1, 2, 3, F3D_R(1.1), F3D_R(2.1), F3D_R(2.9),
                              F3D_R(0.9), F3D_R(1.95), F3D_R(3.05)};
  for (int i = 0; i < 9; i++) pts[n++] = inside[i];
  *hull = f3d_world_create_hull(w, pts, 11);
  return w;
}

static void test_hulls(void) {
  uint32_t hull;
  F3dWorld *w = world_with_cube_hull(&hull, F3D_R(0.5));
  CHECK(hull == 1);
  CHECK(f3d_world_hull_vertex_count(w, hull) == 8);
  f3d_real offset[3];
  CHECK(f3d_world_get_hull_offset(w, hull, offset) == 1);
  CHECK_NEAR(offset[0], 1, 1e-6);
  CHECK_NEAR(offset[1], 2, 1e-6);
  CHECK_NEAR(offset[2], 3, 1e-6);
  CHECK_NEAR(w->hulls[0].volume, 1, 1e-6);
  CHECK_NEAR(w->hulls[0].surface, 6, 1e-6);
  /* A body shaped as it weighs as a box of the same size. */
  const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 3);
  CHECK(f3d_body_set_hull(w, b, hull) == 1);
  f3d_real t[6];
  f3d_body_get_inertia_tensor(w, b, t);
  CHECK_NEAR(t[0], 3.0 / 3.0 * 0.5, 1e-5);
  CHECK_NEAR(t[1], 0.5, 1e-5);
  CHECK(fabs((double)t[3]) < 1e-6 && fabs((double)t[4]) < 1e-6);
  /* And collides as one: on a floor, the same four corners and depth. */
  F3dManifold hm, bm;
  F3dPlaced h = f3d_placed_of(w, f3d_slot_of(w, b));
  h.at = f3d_v3(0, F3D_R(0.49), 0);
  const F3dPlaced box = shape(F3D_SHAPE_BOX, f3d_v3(F3D_R(0.5), F3D_R(0.5), F3D_R(0.5)),
                              f3d_v3(0, F3D_R(0.49), 0), identity);
  CHECK(collide(&h, floor_box(), &hm) == 4);
  CHECK(collide(&box, floor_box(), &bm) == 4);
  for (uint32_t i = 0; i < 4; i++) CHECK_NEAR(hm.points[i].depth, 0.01, 1e-4);
  CHECK_NEAR(hm.normal.y, bm.normal.y, 1e-5);
  /* Refused: too few points, all in a plane, or not finite. */
  const f3d_real flat[12] = {0, 0, 0, 1, 0, 0, 0, 0, 1, 1, 0, 1};
  CHECK(f3d_world_create_hull(w, flat, 4) == 0);
  CHECK(f3d_world_create_hull(w, flat, 3) == 0);
  f3d_real bad[12] = {0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1};
  bad[4] = nan_value();
  CHECK(f3d_world_create_hull(w, bad, 4) == 0);
  CHECK(f3d_body_set_hull(w, b, 7) == 0);
  /* A tetrahedron's centre of mass is the mean of its corners. */
  const f3d_real tetra[12] = {0, 0, 0, 4, 0, 0, 0, 4, 0, 0, 0, 4};
  const uint32_t t2 = f3d_world_create_hull(w, tetra, 4);
  CHECK(t2 == 2);
  f3d_world_get_hull_offset(w, t2, offset);
  CHECK_NEAR(offset[0], 1, 1e-6);
  CHECK_NEAR(w->hulls[1].volume, 64.0 / 6.0, 1e-5);
  f3d_world_destroy(w);
}

static void test_turned_hull_has_products(void) {
  /* A box's corners turned 30° about z, made a hull: its tensor in the
   * body's axes is the box's turned, products of inertia and all. */
  F3dWorld *w = f3d_world_create();
  const F3dQuat q = turn_about(f3d_v3(0, 0, 1), M_PI / 6);
  const F3dMat3 r = f3d_mat_of(q);
  f3d_real pts[24];
  const double h[3] = {1.0, 0.5, 0.25};
  for (int i = 0; i < 8; i++) {
    const F3dVec3 c = f3d_v3((f3d_real)((i & 1) ? h[0] : -h[0]),
                             (f3d_real)((i & 2) ? h[1] : -h[1]),
                             (f3d_real)((i & 4) ? h[2] : -h[2]));
    const F3dVec3 v = f3d_add(f3d_add(f3d_scale(r.c[0], c.x), f3d_scale(r.c[1], c.y)),
                              f3d_scale(r.c[2], c.z));
    pts[i * 3] = v.x;
    pts[i * 3 + 1] = v.y;
    pts[i * 3 + 2] = v.z;
  }
  const uint32_t hull = f3d_world_create_hull(w, pts, 8);
  const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 2);
  f3d_body_set_hull(w, b, hull);
  f3d_real t[6];
  f3d_body_get_inertia_tensor(w, b, t);
  const F3dSym3 diag = f3d_sym_diag((f3d_real)(2.0 / 3.0 * (h[1] * h[1] + h[2] * h[2])),
                                    (f3d_real)(2.0 / 3.0 * (h[0] * h[0] + h[2] * h[2])),
                                    (f3d_real)(2.0 / 3.0 * (h[0] * h[0] + h[1] * h[1])));
  const F3dSym3 want = f3d_sym_turned(q, diag);
  CHECK_NEAR(t[0], want.xx, 1e-4);
  CHECK_NEAR(t[1], want.yy, 1e-4);
  CHECK_NEAR(t[2], want.zz, 1e-4);
  CHECK_NEAR(t[3], want.xy, 1e-4);
  CHECK(fabs((double)t[3]) > 0.05);
  /* Spun free about no axis of its own, it keeps its angular momentum —
   * which only holds if its tensor is carried into the world's axes
   * right, products and all. L is worked out here, apart from the core:
   * ω into the body's axes, times the tensor, back out. */
  {
    F3dWorld *v = f3d_world_create();
    f3d_world_set_gravity(v, 0, 0, 0);
    f3d_world_set_sleep(v, 0, 0);
    f3d_world_set_air(v, F3D_R(293.15), F3D_R(1e-30));
    const uint32_t h2 = f3d_world_create_hull(v, pts, 8);
    const F3dBody spun = f3d_body_create(v, F3D_BODY_DYNAMIC, 0, 0, 0, 2);
    f3d_body_set_hull(v, spun, h2);
    f3d_body_set_angular_velocity(v, spun, 1, 2, F3D_R(0.5));
    double l0[3] = {0, 0, 0}, l1[3] = {0, 0, 0};
    for (int pass = 0; pass < 2; pass++) {
      if (pass) {
        for (int i = 0; i < 600; i++) f3d_world_step(v, F3D_R(1.0 / 240.0));
      }
      f3d_real q4[4], w3[3], tt[6];
      f3d_body_get_orientation(v, spun, q4);
      f3d_body_get_angular_velocity(v, spun, w3);
      f3d_body_get_inertia_tensor(v, spun, tt);
      const F3dQuat qq = {q4[0], q4[1], q4[2], q4[3]};
      const F3dMat3 rot = f3d_mat_of(qq);
      double wl[3], ll[3];
      for (int k = 0; k < 3; k++) {
        wl[k] = (double)rot.c[k].x * w3[0] + (double)rot.c[k].y * w3[1] +
                (double)rot.c[k].z * w3[2];
      }
      const double ti[3][3] = {{tt[0], tt[3], tt[4]},
                               {tt[3], tt[1], tt[5]},
                               {tt[4], tt[5], tt[2]}};
      for (int k = 0; k < 3; k++) {
        ll[k] = ti[k][0] * wl[0] + ti[k][1] * wl[1] + ti[k][2] * wl[2];
      }
      double *out = pass ? l1 : l0;
      out[0] = rot.c[0].x * ll[0] + rot.c[1].x * ll[1] + rot.c[2].x * ll[2];
      out[1] = rot.c[0].y * ll[0] + rot.c[1].y * ll[1] + rot.c[2].y * ll[2];
      out[2] = rot.c[0].z * ll[0] + rot.c[1].z * ll[1] + rot.c[2].z * ll[2];
    }
    const double size = sqrt(l0[0] * l0[0] + l0[1] * l0[1] + l0[2] * l0[2]);
    for (int k = 0; k < 3; k++) CHECK_NEAR(l1[k] / size, l0[k] / size, 1e-3);
    f3d_world_destroy(v);
  }
  /* Its inverse is the tensor's: I · I⁻¹ = 1. */
  const F3dSlot *s = f3d_slot_of(w, b);
  const F3dVec3 x = f3d_sym_times(s->inverse_inertia,
                                  f3d_sym_times(s->inertia, f3d_v3(1, 2, 3)));
  CHECK_NEAR(x.x, 1, 1e-4);
  CHECK_NEAR(x.y, 2, 1e-4);
  CHECK_NEAR(x.z, 3, 1e-4);
  f3d_world_destroy(w);
}

static void test_inertia_and_rounding(void) {
  F3dWorld *w = f3d_world_create();
  const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 2);
  f3d_real i[3];
  CHECK(f3d_body_set_shape(w, b, F3D_SHAPE_CYLINDER, F3D_R(0.5), 1, 0) == 1);
  f3d_body_get_inertia(w, b, i);
  CHECK_NEAR(i[1], 0.5 * 2 * 0.25, 1e-6);
  CHECK_NEAR(i[0], 2 * (3 * 0.25 + 4 * 1.0) / 12.0, 1e-6);
  CHECK(f3d_body_set_shape(w, b, F3D_SHAPE_CONE, F3D_R(0.5), 2, 0) == 1);
  f3d_body_get_inertia(w, b, i);
  CHECK_NEAR(i[1], 0.3 * 2 * 0.25, 1e-6);
  CHECK_NEAR(i[0], 2 * (3.0 / 20.0 * 0.25 + 3.0 / 80.0 * 4.0), 1e-6);
  CHECK(f3d_body_set_shape(w, b, F3D_SHAPE_CYLINDER, 0, 1, 0) == 0);
  /* Rounded, a box weighs as the box it rounds out to, and collides as
   * one with rounded edges: a box of 0.4 rounded by 0.1 rests where a box
   * of 0.5 rests. */
  CHECK(f3d_body_set_shape(w, b, F3D_SHAPE_BOX, F3D_R(0.4), F3D_R(0.4), F3D_R(0.4)) == 1);
  CHECK(f3d_body_set_rounding(w, b, F3D_R(0.1)) == 1);
  CHECK(f3d_body_set_rounding(w, b, -1) == 0);
  f3d_body_get_inertia(w, b, i);
  CHECK_NEAR(i[0], 2.0 / 3.0 * 0.5, 1e-6);
  F3dPlaced p = f3d_placed_of(w, f3d_slot_of(w, b));
  p.at = f3d_v3(0, F3D_R(0.49), 0);
  F3dManifold m;
  CHECK(collide(&p, floor_box(), &m) == 4);
  for (uint32_t k = 0; k < 4; k++) {
    CHECK_NEAR(m.points[k].depth, 0.01, 1e-4);
    /* The flat of its face: inside the unrounded core's 0.4. */
    CHECK(fabs((double)m.points[k].point.x) <= 0.4 + 1e-4);
  }
  /* A point cannot be rounded. */
  const F3dBody pt = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 1);
  CHECK(f3d_body_set_rounding(w, pt, F3D_R(0.1)) == 0);
  f3d_world_destroy(w);
}

static void test_symmetry(void) {
  const F3dQuat q = turn_about(f3d_v3(F3D_R(0.6), F3D_R(0.8), 0), 0.7);
  const F3dQuat r = turn_about(f3d_v3(0, F3D_R(0.6), F3D_R(0.8)), -1.1);
  F3dPlaced shapes[4] = {
      shape(F3D_SHAPE_CYLINDER, f3d_v3(F3D_R(0.3), F3D_R(0.4), 0), f3d_v3(0, 0, 0), q),
      shape(F3D_SHAPE_CONE, f3d_v3(F3D_R(0.35), F3D_R(0.8), 0), f3d_v3(0, 0, 0), r),
      shape(F3D_SHAPE_BOX, f3d_v3(F3D_R(0.3), F3D_R(0.2), F3D_R(0.4)), f3d_v3(0, 0, 0), r),
      shape(F3D_SHAPE_SPHERE, f3d_v3(F3D_R(0.35), 0, 0), f3d_v3(0, 0, 0), q),
  };
  shapes[2].rounding = F3D_R(0.05);
  for (int i = 0; i < 4; i++) {
    for (int j = 0; j < 4; j++) {
      F3dPlaced a = shapes[i], b = shapes[j];
      b.at = f3d_v3(F3D_R(0.25), F3D_R(0.4), F3D_R(0.1));
      F3dManifold ab, ba;
      const uint32_t n1 = collide(&a, &b, &ab), n2 = collide(&b, &a, &ba);
      CHECK(n1 > 0 && n2 > 0);
      CHECK_NEAR(ab.normal.x, -ba.normal.x, 2e-3);
      CHECK_NEAR(ab.normal.y, -ba.normal.y, 2e-3);
      CHECK_NEAR(ab.normal.z, -ba.normal.z, 2e-3);
      double da = -1e9, db = -1e9;
      for (uint32_t k = 0; k < n1; k++) da = fmax(da, ab.points[k].depth);
      for (uint32_t k = 0; k < n2; k++) db = fmax(db, ba.points[k].depth);
      CHECK_NEAR(da, db, 2e-3);
      CHECK_NEAR(f3d_dot(ab.normal, ab.normal), 1, 1e-5);
    }
  }
}

static void test_cylinder_rolls(void) {
  /* A solid cylinder on its side, down a 30° slope with friction to spare:
   * it rolls at 2/3 g sin θ, its spin its speed over its radius. */
  const double theta = M_PI / 6;
  const F3dQuat slope = turn_about(f3d_v3(0, 0, 1), theta);
  const F3dMat3 m = f3d_mat_of(slope);
  F3dWorld *w = f3d_world_create();
  f3d_world_set_air(w, F3D_R(293.15), F3D_R(1e-30));
  f3d_world_set_sleep(w, 0, 0);
  const F3dVec3 at = f3d_scale(m.c[1], F3D_R(-0.5));
  const F3dBody ground = f3d_body_create(w, F3D_BODY_FIXED, at.x, at.y, at.z, 0);
  f3d_body_set_shape(w, ground, F3D_SHAPE_BOX, 30, F3D_R(0.5), 30);
  f3d_body_set_orientation(w, ground, slope.x, slope.y, slope.z, slope.w);
  f3d_body_set_friction(w, ground, 1);
  /* Its axis along z, across the slope. */
  const F3dQuat across = turn_about(f3d_v3(1, 0, 0), M_PI / 2);
  const F3dQuat q = {
      slope.w * across.x + slope.x * across.w + slope.y * across.z - slope.z * across.y,
      slope.w * across.y - slope.x * across.z + slope.y * across.w + slope.z * across.x,
      slope.w * across.z + slope.x * across.y - slope.y * across.x + slope.z * across.w,
      slope.w * across.w - slope.x * across.x - slope.y * across.y - slope.z * across.z};
  const f3d_real r = F3D_R(0.3);
  const F3dVec3 c = f3d_scale(m.c[1], r - F3D_R(0.001));
  const F3dBody wheel = f3d_body_create(w, F3D_BODY_DYNAMIC, c.x, c.y, c.z, 2);
  f3d_body_set_shape(w, wheel, F3D_SHAPE_CYLINDER, r, F3D_R(0.2), 0);
  f3d_body_set_orientation(w, wheel, q.x, q.y, q.z, q.w);
  f3d_body_set_friction(w, wheel, 1);
  for (int i = 0; i < 15; i++) f3d_world_step(w, F3D_R(1.0 / 60.0));
  f3d_real v0[3], v1[3], spin[3];
  f3d_body_get_velocity(w, wheel, v0);
  for (int i = 0; i < 60; i++) f3d_world_step(w, F3D_R(1.0 / 60.0));
  f3d_body_get_velocity(w, wheel, v1);
  f3d_body_get_angular_velocity(w, wheel, spin);
  const double s0 = sqrt((double)v0[0] * v0[0] + (double)v0[1] * v0[1] + (double)v0[2] * v0[2]);
  const double s1 = sqrt((double)v1[0] * v1[0] + (double)v1[1] * v1[1] + (double)v1[2] * v1[2]);
  CHECK_NEAR(s1 - s0, 2.0 / 3.0 * 9.81 * sin(theta), 0.03);
  const double w1 = sqrt((double)spin[0] * spin[0] + (double)spin[1] * spin[1] + (double)spin[2] * spin[2]);
  CHECK_NEAR(w1 * (double)r / s1, 1, 0.03);
  f3d_world_destroy(w);
}

static void test_resting_shapes(void) {
  /* An upright cylinder, a cone on its base and a hull cube, dropped a
   * centimetre onto a floor: each comes to rest standing, and sleeps. */
  uint32_t hull;
  F3dWorld *w = world_with_cube_hull(&hull, F3D_R(0.5));
  f3d_world_set_air(w, F3D_R(293.15), F3D_R(1e-30));
  const F3dBody floor = f3d_body_create(w, F3D_BODY_FIXED, 0, F3D_R(-0.5), 0, 0);
  f3d_body_set_shape(w, floor, F3D_SHAPE_BOX, 20, F3D_R(0.5), 20);
  const F3dBody cyl = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, F3D_R(1.01), 0, 1);
  f3d_body_set_shape(w, cyl, F3D_SHAPE_CYLINDER, F3D_R(0.3), 1, 0);
  const F3dBody cone = f3d_body_create(w, F3D_BODY_DYNAMIC, 3, F3D_R(0.26), 0, 1);
  f3d_body_set_shape(w, cone, F3D_SHAPE_CONE, F3D_R(0.4), 1, 0);
  const F3dBody cube = f3d_body_create(w, F3D_BODY_DYNAMIC, -3, F3D_R(0.51), 0, 1);
  f3d_body_set_hull(w, cube, hull);
  for (int i = 0; i < 240; i++) f3d_world_step(w, F3D_R(1.0 / 60.0));
  const F3dBody bodies[3] = {cyl, cone, cube};
  const double heights[3] = {1.0, 0.25, 0.5};
  for (int k = 0; k < 3; k++) {
    f3d_real p[3], q[4];
    f3d_body_get_position(w, bodies[k], p);
    f3d_body_get_orientation(w, bodies[k], q);
    CHECK(fabs((double)p[1] - heights[k]) < 0.01);
    CHECK_NEAR(fabs((double)q[3]), 1, 1e-3);
    CHECK(f3d_body_is_asleep(w, bodies[k]));
  }
  /* Through a snapshot, hulls and all, to the same bytes. */
  const uint32_t size = f3d_world_snapshot_size(w);
  uint8_t *snap = (uint8_t *)malloc(size);
  f3d_world_snapshot_write(w, snap, size);
  F3dWorld *v = f3d_world_create();
  CHECK(f3d_world_restore(v, snap, size) == 1);
  CHECK(v->s.hull_count == 1 && f3d_world_hull_vertex_count(v, 1) == 8);
  f3d_body_apply_impulse(w, cube, 1, 0, 0);
  f3d_body_apply_impulse(v, cube, 1, 0, 0);
  for (int i = 0; i < 60; i++) {
    f3d_world_step(w, F3D_R(1.0 / 60.0));
    f3d_world_step(v, F3D_R(1.0 / 60.0));
  }
  /* Both stepped on: compared at their sizes now, which the events since
   * have grown. */
  const uint32_t now = f3d_world_snapshot_size(w);
  uint8_t *a = (uint8_t *)malloc(now), *b = (uint8_t *)malloc(now);
  CHECK(f3d_world_snapshot_size(v) == now);
  f3d_world_snapshot_write(w, a, now);
  f3d_world_snapshot_write(v, b, now);
  CHECK(memcmp(a, b, now) == 0);
  free(snap);
  free(a);
  free(b);
  f3d_world_destroy(v);
  f3d_world_destroy(w);
}

int main(void) {
  test_distances();
  test_manifolds();
  test_hulls();
  test_turned_hull_has_products();
  test_inertia_and_rounding();
  test_symmetry();
  test_cylinder_rolls();
  test_resting_shapes();
  return finish();
}
