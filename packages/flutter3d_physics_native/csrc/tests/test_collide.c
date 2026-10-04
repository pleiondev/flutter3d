/*
 * Contacts, tested in C — P9, phase 2: every pair of shapes against its
 * closed form, turned boxes with whole faces, the sweep against every pair
 * tried, contact events, filters, islands that sleep and wake as one, heat
 * across a contact, and contacts carried through a snapshot.
 */
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "check.h"

#ifdef F3D_REAL_DOUBLE
#define TIGHT 1e-9
#else
#define TIGHT 1e-5
#endif

static F3dQuat turn_about(F3dVec3 axis, double angle) {
  const double s = sin(angle / 2);
  F3dQuat q = {(f3d_real)(axis.x * s), (f3d_real)(axis.y * s),
               (f3d_real)(axis.z * s), (f3d_real)cos(angle / 2)};
  return q;
}

static const F3dQuat identity = {0, 0, 0, 1};

static F3dPlaced placed(uint32_t kind, F3dVec3 size, F3dVec3 at, F3dQuat q) {
  F3dPlaced p;
  memset(&p, 0, sizeof p);
  p.kind = kind;
  p.size = size;
  p.at = at;
  p.axes = f3d_mat_of(q);
  return p;
}

static F3dPlaced ball(f3d_real r, F3dVec3 at) {
  return placed(F3D_SHAPE_SPHERE, f3d_v3(r, 0, 0), at, identity);
}

static F3dPlaced box(F3dVec3 half, F3dVec3 at, F3dQuat q) {
  return placed(F3D_SHAPE_BOX, half, at, q);
}

static F3dPlaced capsule(f3d_real r, f3d_real half, F3dVec3 at, F3dQuat q) {
  return placed(F3D_SHAPE_CAPSULE, f3d_v3(r, half, 0), at, q);
}

static uint32_t collide(const F3dPlaced *a, const F3dPlaced *b, F3dManifold *m) {
  memset(m, 0, sizeof *m);
  return f3d_collide(a, b, F3D_R(0.02), m);
}

static void test_balls(void) {
  F3dManifold m;
  const F3dPlaced a = ball(1, f3d_v3(0, F3D_R(1.9), 0));
  const F3dPlaced b = ball(1, f3d_v3(0, 0, 0));
  CHECK(collide(&a, &b, &m) == 1);
  CHECK_NEAR(m.normal.y, 1, TIGHT);
  CHECK_NEAR(m.points[0].depth, 0.1, TIGHT);
  CHECK_NEAR(m.points[0].point.y, 0.95, TIGHT);
  CHECK(m.touching);
  /* A gap within the margin is a contact with a negative depth, and not
   * touching. */
  const F3dPlaced near = ball(1, f3d_v3(0, F3D_R(2.01), 0));
  CHECK(collide(&near, &b, &m) == 1);
  CHECK_NEAR(m.points[0].depth, -0.01, TIGHT);
  CHECK(!m.touching);
  /* Within the solver's slop is touching: as close as it holds a body. */
  const F3dPlaced held = ball(1, f3d_v3(0, F3D_R(2.004), 0));
  CHECK(collide(&held, &b, &m) == 1 && m.touching);
  const F3dPlaced far = ball(1, f3d_v3(0, F3D_R(2.03), 0));
  CHECK(collide(&far, &b, &m) == 0);
  /* Concentric: up, as flutter3d_physics parts them. */
  CHECK(collide(&b, &b, &m) == 1);
  CHECK(m.normal.y == 1);
  CHECK_NEAR(m.points[0].depth, 2, TIGHT);
}

static void test_ball_and_box(void) {
  F3dManifold m;
  /* A box turned 45° about z stands on its edge; a ball above that edge
   * is pushed straight up, by the edge, not by a face. */
  const F3dPlaced b = box(f3d_v3(1, 1, 1), f3d_v3(0, 0, 0),
                          turn_about(f3d_v3(0, 0, 1), M_PI / 4));
  const double top = sqrt(2.0);
  const F3dPlaced a = ball(F3D_R(0.5), f3d_v3(0, (f3d_real)(top + 0.4), 0));
  CHECK(collide(&a, &b, &m) == 1);
  CHECK_NEAR(m.normal.y, 1, TIGHT);
  CHECK_NEAR(m.points[0].depth, 0.1, 1e-4);
  /* Swapped, the normal turns round. */
  CHECK(collide(&b, &a, &m) == 1);
  CHECK_NEAR(m.normal.y, -1, TIGHT);
  /* A centre inside the box goes out by the nearest face. */
  const F3dPlaced in = ball(F3D_R(0.5), f3d_v3(F3D_R(0.9), 0, 0));
  const F3dPlaced flat = box(f3d_v3(1, 1, 1), f3d_v3(0, 0, 0), identity);
  CHECK(collide(&in, &flat, &m) == 1);
  CHECK(m.normal.x == 1);
  CHECK_NEAR(m.points[0].depth, 0.6, TIGHT);
}

static void test_box_on_box(void) {
  F3dManifold m;
  const F3dPlaced floor = box(f3d_v3(5, F3D_R(0.5), 5), f3d_v3(0, F3D_R(-0.5), 0),
                              identity);
  /* A crate sunk a centimetre into the floor rests on its whole face: four
   * points at its corners, each a centimetre deep. */
  const F3dPlaced crate = box(f3d_v3(F3D_R(0.5), F3D_R(0.5), F3D_R(0.5)),
                              f3d_v3(1, F3D_R(0.49), 2), identity);
  CHECK(collide(&crate, &floor, &m) == 4);
  CHECK_NEAR(m.normal.y, 1, TIGHT);
  for (uint32_t i = 0; i < m.count; i++) {
    CHECK_NEAR(m.points[i].depth, 0.01, 1e-5);
    CHECK_NEAR(fabs((double)m.points[i].point.x - 1), 0.5, 1e-5);
    CHECK_NEAR(fabs((double)m.points[i].point.z - 2), 0.5, 1e-5);
  }
  /* Turned about the vertical, it still rests on four corners. */
  const F3dPlaced turned =
      box(f3d_v3(F3D_R(0.5), F3D_R(0.5), F3D_R(0.5)), f3d_v3(1, F3D_R(0.49), 2),
          turn_about(f3d_v3(0, 1, 0), 0.5));
  CHECK(collide(&turned, &floor, &m) == 4);
  CHECK_NEAR(m.normal.y, 1, TIGHT);
  /* The floor first: the normal out of the crate, down. */
  CHECK(collide(&floor, &turned, &m) == 4);
  CHECK_NEAR(m.normal.y, -1, TIGHT);
  /* Stood on an edge, it touches along the edge: two points. */
  const double reach = sqrt(0.5);
  const F3dPlaced edge =
      box(f3d_v3(F3D_R(0.5), F3D_R(0.5), F3D_R(0.5)),
          f3d_v3(0, (f3d_real)(reach - 0.01), 0),
          turn_about(f3d_v3(0, 0, 1), M_PI / 4));
  CHECK(collide(&edge, &floor, &m) == 2);
  CHECK_NEAR(m.normal.y, 1, TIGHT);
  CHECK_NEAR(m.points[0].depth, 0.01, 1e-4);
  CHECK_NEAR(fabs((double)(m.points[0].point.z - m.points[1].point.z)), 1, 1e-4);
  /* Two crates alike, the top one turned 45°: they meet over an octagon,
   * eight points, and the four kept must hold most of it — the deepest,
   * the furthest from it, and the widest either side — not four in a row
   * along one side. The four alternate corners span 0.586 of the 0.828 the
   * octagon covers; four in a row, about 0.35. */
  const F3dPlaced base = box(f3d_v3(F3D_R(0.5), F3D_R(0.5), F3D_R(0.5)),
                             f3d_v3(0, 0, 0), identity);
  const F3dPlaced twisted =
      box(f3d_v3(F3D_R(0.5), F3D_R(0.5), F3D_R(0.5)), f3d_v3(0, F3D_R(0.99), 0),
          turn_about(f3d_v3(0, 1, 0), M_PI / 4));
  CHECK(collide(&twisted, &base, &m) == 4);
  {
    const F3dVec3 up = f3d_v3(0, 1, 0);
    const F3dContactPoint *p = m.points;
    double best = 0;
    const int orders[3][4] = {{0, 1, 2, 3}, {0, 1, 3, 2}, {0, 2, 1, 3}};
    for (int o = 0; o < 3; o++) {
      const F3dVec3 a0 = p[orders[o][0]].point, a1 = p[orders[o][1]].point;
      const F3dVec3 a2 = p[orders[o][2]].point, a3 = p[orders[o][3]].point;
      const double area =
          0.5 * fabs((double)f3d_dot(f3d_cross(f3d_sub(a2, a0), f3d_sub(a3, a1)), up));
      if (area > best) best = area;
    }
    CHECK(best > 0.5);
  }
  /* A big box on a small one clips to the small one's face. */
  const F3dPlaced small = box(f3d_v3(F3D_R(0.2), F3D_R(0.2), F3D_R(0.2)),
                              f3d_v3(0, 0, 0), identity);
  const F3dPlaced big = box(f3d_v3(1, F3D_R(0.2), 1), f3d_v3(0, F3D_R(0.39), 0),
                            identity);
  CHECK(collide(&big, &small, &m) == 4);
  for (uint32_t i = 0; i < m.count; i++) {
    CHECK_NEAR(fabs((double)m.points[i].point.x), 0.2, 1e-5);
  }
}

static void test_edge_on_edge(void) {
  F3dManifold m;
  /* Two crates stood on edges crossed at right angles: they touch at one
   * point, edge to edge, and the way apart is straight up. */
  const double reach = sqrt(0.5);
  const F3dPlaced low = box(f3d_v3(F3D_R(0.5), F3D_R(0.5), F3D_R(0.5)),
                            f3d_v3(0, 0, 0), turn_about(f3d_v3(0, 0, 1), M_PI / 4));
  const F3dPlaced high =
      box(f3d_v3(F3D_R(0.5), F3D_R(0.5), F3D_R(0.5)),
          f3d_v3(0, (f3d_real)(2 * reach - 0.01), 0),
          turn_about(f3d_v3(1, 0, 0), M_PI / 4));
  CHECK(collide(&high, &low, &m) == 1);
  CHECK_NEAR(m.normal.y, 1, 1e-4);
  CHECK_NEAR(m.points[0].depth, 0.01, 1e-4);
  CHECK_NEAR(m.points[0].point.x, 0, 1e-4);
  CHECK_NEAR(m.points[0].point.z, 0, 1e-4);
  CHECK(m.points[0].id >= 0x100u);
}

static void test_capsules(void) {
  F3dManifold m;
  const F3dPlaced floor = box(f3d_v3(5, F3D_R(0.5), 5), f3d_v3(0, F3D_R(-0.5), 0),
                              identity);
  /* Lying down, it rests on both ends. */
  const F3dQuat lying = turn_about(f3d_v3(0, 0, 1), M_PI / 2);
  const F3dPlaced log = capsule(F3D_R(0.1), F3D_R(0.5), f3d_v3(0, F3D_R(0.09), 0), lying);
  CHECK(collide(&log, &floor, &m) == 2);
  CHECK_NEAR(m.normal.y, 1, TIGHT);
  CHECK_NEAR(m.points[0].depth, 0.01, 1e-5);
  CHECK_NEAR(m.points[1].depth, 0.01, 1e-5);
  CHECK_NEAR(fabs((double)(m.points[0].point.x - m.points[1].point.x)), 1, 1e-4);
  /* Upright, on one point. */
  const F3dPlaced post = capsule(F3D_R(0.1), F3D_R(0.5), f3d_v3(0, F3D_R(0.59), 0),
                                 identity);
  CHECK(collide(&post, &floor, &m) == 1);
  CHECK_NEAR(m.points[0].depth, 0.01, 1e-5);
  /* Two lying side by side touch along their length; crossed, at a
   * point. */
  const F3dPlaced other =
      capsule(F3D_R(0.1), F3D_R(0.5), f3d_v3(F3D_R(0.25), F3D_R(0.27), 0), lying);
  CHECK(collide(&other, &log, &m) == 2);
  CHECK_NEAR(m.normal.y, 1, TIGHT);
  const F3dPlaced crossed =
      capsule(F3D_R(0.1), F3D_R(0.5), f3d_v3(0, F3D_R(0.27), 0),
              turn_about(f3d_v3(1, 0, 0), M_PI / 2));
  CHECK(collide(&crossed, &log, &m) == 1);
  CHECK_NEAR(m.normal.y, 1, TIGHT);
  CHECK_NEAR(m.points[0].depth, 0.02, 1e-5);
  /* A ball on a capsule's side. */
  const F3dPlaced pebble = ball(F3D_R(0.05), f3d_v3(F3D_R(0.3), F3D_R(0.23), 0));
  CHECK(collide(&pebble, &log, &m) == 1);
  CHECK_NEAR(m.normal.y, 1, TIGHT);
  CHECK_NEAR(m.points[0].depth, 0.01, 1e-5);
}

/* Every kind against every kind, turned, both ways round: the normal turns
 * round with the order and the depths stay. */
static void test_symmetry(void) {
  const F3dQuat q = turn_about(f3d_v3(F3D_R(0.6), F3D_R(0.8), 0), 0.7);
  const F3dQuat r = turn_about(f3d_v3(0, F3D_R(0.6), F3D_R(0.8)), -1.1);
  F3dPlaced shapes[3] = {
      ball(F3D_R(0.4), f3d_v3(0, 0, 0)),
      box(f3d_v3(F3D_R(0.4), F3D_R(0.3), F3D_R(0.2)), f3d_v3(0, 0, 0), q),
      capsule(F3D_R(0.2), F3D_R(0.3), f3d_v3(0, 0, 0), r),
  };
  for (int i = 0; i < 3; i++) {
    for (int j = 0; j < 3; j++) {
      F3dPlaced a = shapes[i], b = shapes[j];
      b.at = f3d_v3(F3D_R(0.3), F3D_R(0.45), F3D_R(0.1));
      F3dManifold ab, ba;
      const uint32_t n1 = collide(&a, &b, &ab);
      const uint32_t n2 = collide(&b, &a, &ba);
      CHECK(n1 > 0 && n2 > 0);
      CHECK_NEAR(ab.normal.x, -ba.normal.x, 1e-4);
      CHECK_NEAR(ab.normal.y, -ba.normal.y, 1e-4);
      CHECK_NEAR(ab.normal.z, -ba.normal.z, 1e-4);
      double da = -1e9, db = -1e9;
      for (uint32_t k = 0; k < n1; k++) da = fmax(da, ab.points[k].depth);
      for (uint32_t k = 0; k < n2; k++) db = fmax(db, ba.points[k].depth);
      CHECK_NEAR(da, db, 1e-4);
      /* A unit normal. */
      CHECK_NEAR(f3d_dot(ab.normal, ab.normal), 1, 1e-5);
    }
  }
}

static double uniform(unsigned *state) {
  *state = *state * 1664525u + 1013904223u;
  return (*state >> 8) / 16777216.0;
}

static F3dBody add_shape(F3dWorld *w, F3dBodyType type, int kind, F3dVec3 at,
                         F3dQuat q, double s) {
  const F3dBody b = f3d_body_create(w, type, at.x, at.y, at.z, 1);
  f3d_body_set_orientation(w, b, q.x, q.y, q.z, q.w);
  if (kind == 1) f3d_body_set_shape(w, b, F3D_SHAPE_SPHERE, (f3d_real)s, 0, 0);
  if (kind == 2) {
    f3d_body_set_shape(w, b, F3D_SHAPE_BOX, (f3d_real)s, (f3d_real)(s * 0.6),
                       (f3d_real)(s * 1.3));
  }
  if (kind == 3) {
    f3d_body_set_shape(w, b, F3D_SHAPE_CAPSULE, (f3d_real)(s * 0.4),
                       (f3d_real)s, 0);
  }
  return b;
}

static void test_sweep_finds_every_pair(void) {
  /* Two hundred shapes of every kind, turned every way, crowded into a few
   * metres: the sweep must find exactly the pairs that trying every pair
   * finds. */
  enum { N = 200 };
  F3dWorld *w = f3d_world_create();
  f3d_world_set_gravity(w, 0, 0, 0);
  f3d_world_set_sleep(w, 0, 0);
  unsigned seed = 12345u;
  F3dBody bodies[N];
  for (int i = 0; i < N; i++) {
    const F3dVec3 at = f3d_v3((f3d_real)(uniform(&seed) * 6),
                              (f3d_real)(uniform(&seed) * 3),
                              (f3d_real)(uniform(&seed) * 6));
    const F3dQuat q = turn_about(
        f3d_v3(F3D_R(0.48), F3D_R(0.6), F3D_R(0.64)), uniform(&seed) * 6.28);
    bodies[i] = add_shape(w, i % 7 == 0 ? F3D_BODY_FIXED : F3D_BODY_DYNAMIC,
                          1 + i % 3, at, q, 0.15 + uniform(&seed) * 0.3);
  }
  /* One point among them, which touches nothing. */
  f3d_body_create(w, F3D_BODY_DYNAMIC, 1, 1, 1, 1);
  f3d_world_step(w, F3D_R(1e-6));
  int expected = 0;
  for (int i = 0; i < N; i++) {
    for (int j = i + 1; j < N; j++) {
      const F3dSlot *a = f3d_slot_of(w, bodies[i]);
      const F3dSlot *b = f3d_slot_of(w, bodies[j]);
      if (a->type == F3D_BODY_FIXED && b->type == F3D_BODY_FIXED) continue;
      const F3dPlaced pa = f3d_placed_of(w, a), pb = f3d_placed_of(w, b);
      F3dManifold m;
      memset(&m, 0, sizeof m);
      if (f3d_collide(&pa, &pb, w->s.contact_margin, &m) > 0) expected++;
    }
  }
  CHECK((int)w->s.manifold_count == expected);
  CHECK(expected > 20);
  /* In order of their slots. */
  int sorted = 1;
  for (uint32_t i = 1; i < w->s.manifold_count; i++) {
    const F3dManifold *p = &w->manifolds[i - 1], *q = &w->manifolds[i];
    const uint64_t kp = ((p->a & 0xffffffffu) << 32) | (p->b & 0xffffffffu);
    const uint64_t kq = ((q->a & 0xffffffffu) << 32) | (q->b & 0xffffffffu);
    sorted &= kp < kq;
  }
  CHECK(sorted);
  /* What the reader hands out adds up. */
  const uint32_t points = f3d_world_contact_count(w);
  f3d_real *contacts = (f3d_real *)malloc(points * F3D_CONTACT_FLOATS * sizeof(f3d_real));
  F3dBody *pairs = (F3dBody *)malloc(points * 2 * sizeof(F3dBody));
  CHECK(f3d_world_read_contacts(w, contacts, pairs, points) == points);
  CHECK(f3d_body_is_valid(w, pairs[0]) && f3d_body_is_valid(w, pairs[1]));
  free(contacts);
  free(pairs);
  f3d_world_destroy(w);
}

static uint32_t events(F3dWorld *w, F3dBody *bodies, F3dBody *others,
                       uint32_t *kinds) {
  return f3d_world_read_events(w, bodies, others, kinds, 16);
}

static void test_contact_events(void) {
  F3dWorld *w = f3d_world_create();
  f3d_world_set_gravity(w, 0, 0, 0);
  f3d_world_set_sleep(w, 0, 0);
  f3d_world_set_air(w, 293, F3D_R(1e-30));
  const F3dBody wall = add_shape(w, F3D_BODY_FIXED, 2, f3d_v3(0, 0, 0), identity, 0.5);
  const F3dBody bullet = add_shape(w, F3D_BODY_DYNAMIC, 1, f3d_v3(-2, 0, 0), identity, 0.1);
  F3dBody bodies[16], others[16];
  uint32_t kinds[16];
  /* At the wall at two metres a second, a hundredth at a time: it bounces
   * off, beginning one contact and ending it. */
  f3d_body_set_restitution(w, bullet, 1);
  f3d_body_set_velocity(w, bullet, 2, 0, 0);
  uint32_t began = 0, ended = 0;
  for (int i = 0; i < 400; i++) {
    f3d_world_step(w, F3D_R(0.01));
    const uint32_t n = events(w, bodies, others, kinds);
    for (uint32_t k = 0; k < n; k++) {
      CHECK(bodies[k] == wall && others[k] == bullet);
      began += kinds[k] == F3D_EVENT_CONTACT_BEGAN;
      ended += kinds[k] == F3D_EVENT_CONTACT_ENDED;
    }
  }
  CHECK(began == 1 && ended == 1);
  /* A filter that leaves the wall out: nothing at all. */
  f3d_body_set_position(w, bullet, -2, 0, 0);
  f3d_body_set_velocity(w, bullet, 2, 0, 0);
  f3d_body_set_collision_filter(w, bullet, 2, ~1u);
  for (int i = 0; i < 400; i++) f3d_world_step(w, F3D_R(0.01));
  CHECK(events(w, bodies, others, kinds) == 0);
  /* Taken away mid-contact, the contact ends, naming who it was. */
  f3d_body_set_collision_filter(w, bullet, 1, ~0u);
  f3d_body_set_position(w, bullet, 0, 0, 0);
  f3d_body_set_velocity(w, bullet, 0, 0, 0);
  f3d_world_step(w, F3D_R(0.01));
  CHECK(events(w, bodies, others, kinds) == 1 && kinds[0] == F3D_EVENT_CONTACT_BEGAN);
  f3d_body_destroy(w, bullet);
  f3d_world_step(w, F3D_R(0.01));
  CHECK(events(w, bodies, others, kinds) == 1);
  CHECK(kinds[0] == F3D_EVENT_CONTACT_ENDED && others[0] == bullet);
  CHECK(f3d_world_contact_count(w) == 0);
  /* Margin nought: only a real overlap counts. */
  CHECK(f3d_world_set_contact_margin(w, -1) == 0);
  CHECK(f3d_world_set_contact_margin(w, 0) == 1);
  f3d_world_destroy(w);
}

static void test_islands(void) {
  /* Two crates stacked on a floor, and one alone across the room. With no
   * solver yet they stay where they are put, a millimetre into each
   * other. */
  F3dWorld *w = f3d_world_create();
  f3d_world_set_gravity(w, 0, 0, 0);
  const F3dBody floor = add_shape(w, F3D_BODY_FIXED, 2, f3d_v3(0, F3D_R(-0.5), 0), identity, 0.5);
  f3d_body_set_shape(w, floor, F3D_SHAPE_BOX, 10, F3D_R(0.5), 10);
  const F3dBody low = add_shape(w, F3D_BODY_DYNAMIC, 1, f3d_v3(0, F3D_R(0.499), 0), identity, 0.5);
  const F3dBody high = add_shape(w, F3D_BODY_DYNAMIC, 1, f3d_v3(0, F3D_R(1.498), 0), identity, 0.5);
  const F3dBody alone = add_shape(w, F3D_BODY_DYNAMIC, 1, f3d_v3(5, F3D_R(0.499), 0), identity, 0.5);
  F3dBody bodies[16], others[16];
  uint32_t kinds[16];
  /* The lone crate is still from the start; the stack's top only after a
   * while, so the stack sleeps later, as one. */
  f3d_body_set_velocity(w, high, F3D_R(0.1), 0, 0);
  for (int i = 0; i < 33; i++) f3d_world_step(w, F3D_R(1.0 / 60.0));
  CHECK(f3d_body_is_asleep(w, alone));
  CHECK(!f3d_body_is_asleep(w, low) && !f3d_body_is_asleep(w, high));
  f3d_body_set_velocity(w, high, 0, 0, 0);
  for (int i = 0; i < 29; i++) f3d_world_step(w, F3D_R(1.0 / 60.0));
  CHECK(!f3d_body_is_asleep(w, low));
  for (int i = 0; i < 3; i++) f3d_world_step(w, F3D_R(1.0 / 60.0));
  CHECK(f3d_body_is_asleep(w, low) && f3d_body_is_asleep(w, high));
  events(w, bodies, others, kinds);
  /* Asleep, they keep their contacts, and nothing ends. */
  const uint32_t contacts = f3d_world_contact_count(w);
  CHECK(contacts > 0);
  for (int i = 0; i < 10; i++) f3d_world_step(w, F3D_R(1.0 / 60.0));
  CHECK(f3d_world_contact_count(w) == contacts);
  CHECK(events(w, bodies, others, kinds) == 0);
  /* Knock the top one and the bottom one wakes with it; the lone crate
   * sleeps on. */
  f3d_body_apply_impulse(w, high, 1, 0, 0);
  f3d_world_step(w, F3D_R(1.0 / 60.0));
  CHECK(!f3d_body_is_asleep(w, low));
  CHECK(f3d_body_is_asleep(w, alone));
  const uint32_t n = events(w, bodies, others, kinds);
  int low_woke = 0;
  for (uint32_t k = 0; k < n; k++) {
    low_woke |= bodies[k] == low && kinds[k] == F3D_EVENT_WOKE;
  }
  CHECK(low_woke);
  f3d_world_destroy(w);
}

static void test_conduction(void) {
  /* Two steel balls of a kilogram, r = 5 cm, pressed a millimetre into each
   * other, one hot. Hertz's spot is √(Rδ) = 5 mm across with R = 2.5 cm,
   * Holm's conductance 4a / (2/k) = 0.5 W/K, and in still air at their mean
   * temperature the difference between them falls as
   * e^(−(2G + hA) t / C), never crossing. */
  F3dWorld *w = f3d_world_create();
  f3d_world_set_gravity(w, 0, 0, 0);
  f3d_world_set_air(w, 350, F3D_R(1.204));
  F3dMaterial steel;
  f3d_material_preset(F3D_MATERIAL_STEEL, &steel);
  steel.emissivity = 0;
  const F3dBody hot = add_shape(w, F3D_BODY_DYNAMIC, 1, f3d_v3(0, 0, 0), identity, 0.05);
  const F3dBody cold = add_shape(w, F3D_BODY_DYNAMIC, 1, f3d_v3(F3D_R(0.099), 0, 0), identity, 0.05);
  const F3dBody apart = add_shape(w, F3D_BODY_DYNAMIC, 1, f3d_v3(5, 0, 0), identity, 0.05);
  const F3dBody apart2 = add_shape(w, F3D_BODY_DYNAMIC, 1, f3d_v3(8, 0, 0), identity, 0.05);
  f3d_body_set_material(w, hot, &steel);
  f3d_body_set_material(w, cold, &steel);
  f3d_body_set_material(w, apart, &steel);
  f3d_body_set_material(w, apart2, &steel);
  f3d_body_set_temperature(w, hot, 400);
  f3d_body_set_temperature(w, cold, 300);
  f3d_body_set_temperature(w, apart, 400);
  f3d_body_set_temperature(w, apart2, 300);
  f3d_real th = 0, tc = 0, ta = 0, tb = 0;
  int crossed = 0;
  for (int i = 0; i < 6000; i++) {
    f3d_world_step(w, F3D_R(0.1));
    f3d_body_get_temperature(w, hot, &th);
    f3d_body_get_temperature(w, cold, &tc);
    crossed |= th < tc - F3D_R(1e-3);
  }
  f3d_body_get_temperature(w, apart, &ta);
  f3d_body_get_temperature(w, apart2, &tb);
  CHECK(!crossed);
  const double ha = 10.45 * 4 * 3.14159265358979 * 0.05 * 0.05;
  CHECK_NEAR((th - tc) / 100.0, exp(-600.0 * (2 * 0.5 + ha) / 490.0), 1e-2);
  CHECK_NEAR((ta - tb) / 100.0, exp(-600.0 * ha / 490.0), 1e-2);
  /* The air is at their mean and they are alike, so the mean holds. */
  CHECK_NEAR(0.5 * (th + tc), 350, 1e-3);

  /* A hot plate of no thermal mass is a reservoir: it warms the block on it
   * and stays as hot as it was. */
  const F3dBody plate = f3d_body_create(w, F3D_BODY_FIXED, 0, F3D_R(-10.5), 0, 0);
  f3d_body_set_shape(w, plate, F3D_SHAPE_BOX, 1, F3D_R(0.5), 1);
  f3d_body_set_material(w, plate, &steel);
  f3d_body_set_temperature(w, plate, 500);
  /* Its half height is 0.12: a millimetre into the plate's top at −10. */
  const F3dBody block = add_shape(w, F3D_BODY_DYNAMIC, 2, f3d_v3(0, F3D_R(-9.881), 0), identity, 0.2);
  f3d_body_set_material(w, block, &steel);
  f3d_body_set_temperature(w, block, 350);
  for (int i = 0; i < 600; i++) f3d_world_step(w, F3D_R(0.1));
  f3d_real tp, tbk;
  f3d_body_get_temperature(w, plate, &tp);
  f3d_body_get_temperature(w, block, &tbk);
  CHECK(tp == 500);
  CHECK(tbk > 400);
  f3d_world_destroy(w);
}

static void test_fire_warms_what_it_touches(void) {
  /* A burning block pressed against a cold one warms it through the
   * contact, and one standing apart not at all. Not to burning: wood is an
   * insulator, a contact of 10 × 10 cm passes about a hundredth of a watt
   * per kelvin, and fire crosses from log to log by its flames, which the
   * smoke grid will carry. */
  F3dWorld *w = f3d_world_create();
  f3d_world_set_gravity(w, 0, 0, 0);
  F3dMaterial wood;
  f3d_material_preset(F3D_MATERIAL_WOOD, &wood);
  const f3d_real xs[3] = {0, F3D_R(0.099), 5};
  const F3dBodyType types[3] = {F3D_BODY_FIXED, F3D_BODY_DYNAMIC, F3D_BODY_DYNAMIC};
  F3dBody blocks[3];
  for (int i = 0; i < 3; i++) {
    blocks[i] = f3d_body_create(w, types[i], xs[i], 0, 0, F3D_R(0.6));
    f3d_body_set_shape(w, blocks[i], F3D_SHAPE_BOX, F3D_R(0.05), F3D_R(0.05), F3D_R(0.05));
    f3d_body_set_material(w, blocks[i], &wood);
  }
  f3d_body_set_temperature(w, blocks[0], 700);
  for (int i = 0; i < 6000; i++) f3d_world_step(w, F3D_R(0.1));
  int burning = 0, near_burning = 0;
  f3d_body_is_burning(w, blocks[0], &burning);
  f3d_body_is_burning(w, blocks[1], &near_burning);
  f3d_real near, far;
  f3d_body_get_temperature(w, blocks[1], &near);
  f3d_body_get_temperature(w, blocks[2], &far);
  CHECK(burning);
  CHECK(near > far + 1);
  CHECK_NEAR(far, 293.15, 1e-4);
  CHECK(!near_burning);
  f3d_world_destroy(w);
}

static void test_snapshot_keeps_contacts(void) {
  F3dWorld *a = f3d_world_create();
  f3d_world_set_gravity(a, 0, F3D_R(-1), 0);
  const F3dBody floor = add_shape(a, F3D_BODY_FIXED, 2, f3d_v3(0, F3D_R(-0.5), 0), identity, 0.5);
  f3d_body_set_shape(a, floor, F3D_SHAPE_BOX, 10, F3D_R(0.5), 10);
  for (int i = 0; i < 6; i++) {
    add_shape(a, F3D_BODY_DYNAMIC, 1 + i % 3, f3d_v3((f3d_real)i * F3D_R(0.3), F3D_R(0.4), 0),
              turn_about(f3d_v3(0, 0, 1), i * 0.3), 0.2);
  }
  for (int i = 0; i < 20; i++) f3d_world_step(a, F3D_R(1.0 / 60.0));
  CHECK(a->s.manifold_count > 0);
  const uint32_t size = f3d_world_snapshot_size(a);
  uint8_t *snap = (uint8_t *)malloc(size);
  f3d_world_snapshot_write(a, snap, size);
  F3dWorld *b = f3d_world_create();
  CHECK(f3d_world_restore(b, snap, size) == 1);
  CHECK(b->s.manifold_count == a->s.manifold_count);
  for (int i = 0; i < 60; i++) {
    f3d_world_step(a, F3D_R(1.0 / 60.0));
    f3d_world_step(b, F3D_R(1.0 / 60.0));
  }
  const uint32_t sa = f3d_world_snapshot_size(a);
  uint8_t *xa = (uint8_t *)malloc(sa), *xb = (uint8_t *)malloc(sa);
  f3d_world_snapshot_write(a, xa, sa);
  CHECK(f3d_world_snapshot_size(b) == sa);
  f3d_world_snapshot_write(b, xb, sa);
  CHECK(memcmp(xa, xb, sa) == 0);
  free(snap);
  free(xa);
  free(xb);
  f3d_world_destroy(a);
  f3d_world_destroy(b);
}

int main(void) {
  test_balls();
  test_ball_and_box();
  test_box_on_box();
  test_edge_on_edge();
  test_capsules();
  test_symmetry();
  test_sweep_finds_every_pair();
  test_contact_events();
  test_islands();
  test_conduction();
  test_fire_warms_what_it_touches();
  test_snapshot_keeps_contacts();
  return finish();
}
