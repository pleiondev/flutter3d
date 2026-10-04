/*
 * Threads, tested in C — P9, phase 11: a world of every kind of shape — a
 * mesh for ground, a hull, boxes, balls, capsules, cylinders and a chain
 * on hinges, filtered and sleeping — stepped on one thread, two, three and
 * eight steps to the same snapshot, byte for byte, every step; and asking
 * for no threads or too many is refused.
 */
#include <stdlib.h>
#include <string.h>

#include "check.h"

static F3dWorld *scene(void) {
  F3dWorld *w = f3d_world_create();
  f3d_world_set_gravity(w, 0, F3D_R(-9.81), 0);
  /* Ground: a mesh of a gentle bowl, twelve metres across. */
  enum { SIDE = 13 };
  f3d_real v[SIDE * SIDE * 3];
  uint32_t t[(SIDE - 1) * (SIDE - 1) * 6];
  for (int j = 0; j < SIDE; j++) {
    for (int i = 0; i < SIDE; i++) {
      const f3d_real x = (f3d_real)(i - 6), z = (f3d_real)(j - 6);
      v[(j * SIDE + i) * 3] = x;
      v[(j * SIDE + i) * 3 + 1] = (x * x + z * z) * F3D_R(0.02);
      v[(j * SIDE + i) * 3 + 2] = z;
    }
  }
  uint32_t n = 0;
  for (int j = 0; j + 1 < SIDE; j++) {
    for (int i = 0; i + 1 < SIDE; i++) {
      const uint32_t a = (uint32_t)(j * SIDE + i);
      const uint32_t q[6] = {a, a + SIDE, a + 1, a + 1, a + SIDE, a + SIDE + 1};
      for (int k = 0; k < 6; k++) t[n++] = q[k];
    }
  }
  const uint32_t mesh = f3d_world_create_mesh(w, v, SIDE * SIDE, t, n / 3);
  const F3dBody ground = f3d_body_create(w, F3D_BODY_FIXED, 0, 0, 0, 0);
  f3d_body_set_mesh(w, ground, mesh);
  const f3d_real rock[18] = {F3D_R(0.3), 0, 0, F3D_R(-0.3), 0, 0, 0, F3D_R(0.4), 0,
                             0, F3D_R(-0.2), 0, 0, 0, F3D_R(0.3), 0, 0, F3D_R(-0.3)};
  const uint32_t hull = f3d_world_create_hull(w, rock, 6);
  /* Three hundred bodies of five kinds in a loose block above it. */
  for (int i = 0; i < 300; i++) {
    const f3d_real x = (f3d_real)(i % 10) * F3D_R(0.7) - F3D_R(3.2);
    const f3d_real z = (f3d_real)((i / 10) % 10) * F3D_R(0.7) - F3D_R(3.2);
    const f3d_real y = F3D_R(1.5) + (f3d_real)(i / 100) * F3D_R(0.8);
    const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, x + (f3d_real)(i % 3) * F3D_R(0.05), y, z, 1);
    switch (i % 5) {
      case 0: f3d_body_set_shape(w, b, F3D_SHAPE_BOX, F3D_R(0.25), F3D_R(0.2), F3D_R(0.3)); break;
      case 1: f3d_body_set_shape(w, b, F3D_SHAPE_SPHERE, F3D_R(0.25), 0, 0); break;
      case 2: f3d_body_set_shape(w, b, F3D_SHAPE_CAPSULE, F3D_R(0.15), F3D_R(0.2), 0); break;
      case 3: f3d_body_set_shape(w, b, F3D_SHAPE_CYLINDER, F3D_R(0.2), F3D_R(0.2), 0); break;
      default: f3d_body_set_hull(w, b, hull); break;
    }
    f3d_body_set_angular_velocity(w, b, (f3d_real)(i % 7) * F3D_R(0.3), 0, (f3d_real)(i % 4) * F3D_R(0.2));
    if (i % 11 == 0) f3d_body_set_collision_filter(w, b, 2u, ~1u);
  }
  /* A chain of eight links on hinges hanging from a fixed post. */
  F3dBody last = f3d_body_create(w, F3D_BODY_FIXED, 4, 5, 0, 0);
  f3d_body_set_shape(w, last, F3D_SHAPE_BOX, F3D_R(0.1), F3D_R(0.1), F3D_R(0.1));
  for (int k = 0; k < 8; k++) {
    const F3dBody link = f3d_body_create(w, F3D_BODY_DYNAMIC, 4 + (f3d_real)(k + 1) * F3D_R(0.4), 5, 0, F3D_R(0.5));
    f3d_body_set_shape(w, link, F3D_SHAPE_BOX, F3D_R(0.18), F3D_R(0.05), F3D_R(0.05));
    f3d_joint_create(w, F3D_JOINT_REVOLUTE, last, link, 4 + (f3d_real)k * F3D_R(0.4) + F3D_R(0.2), 5, 0, 0, 0, 1);
    last = link;
  }
  return w;
}

static void test_same_bits(void) {
  F3dWorld *one = scene();
  CHECK(f3d_world_threads(one) == 1);
  const uint32_t counts[3] = {2, 3, 8};
  F3dWorld *many[3];
  for (int k = 0; k < 3; k++) {
    many[k] = scene();
    CHECK(f3d_world_set_threads(many[k], counts[k]));
    CHECK(f3d_world_threads(many[k]) == counts[k]);
  }
  /* Room for the snapshot once the contacts have come: it grows with them. */
  const uint32_t size = 4u << 20;
  uint8_t *a = (uint8_t *)malloc(size), *b = (uint8_t *)malloc(size);
  int differing = 0, contacts = 0;
  for (int step = 0; step < 240; step++) {
    f3d_world_step(one, F3D_R(1.0 / 60.0));
    const uint32_t na = f3d_world_snapshot_write(one, a, size);
    CHECK(na > 0 && na <= size);
    contacts = contacts > (int)f3d_world_contact_count(one) ? contacts : (int)f3d_world_contact_count(one);
    for (int k = 0; k < 3; k++) {
      f3d_world_step(many[k], F3D_R(1.0 / 60.0));
      const uint32_t nb = f3d_world_snapshot_write(many[k], b, size);
      differing += na == 0 || na != nb || memcmp(a, b, na) != 0;
    }
  }
  CHECK(differing == 0);
  /* There was something to share out: hundreds of contacts at once. */
  CHECK(contacts > 300);
  /* Back to one thread, still the same. */
  CHECK(f3d_world_set_threads(many[2], 1));
  CHECK(f3d_world_threads(many[2]) == 1);
  f3d_world_step(one, F3D_R(1.0 / 60.0));
  f3d_world_step(many[2], F3D_R(1.0 / 60.0));
  const uint32_t na = f3d_world_snapshot_write(one, a, size);
  CHECK(na == f3d_world_snapshot_write(many[2], b, size) && memcmp(a, b, na) == 0);
  free(a);
  free(b);
  for (int k = 0; k < 3; k++) f3d_world_destroy(many[k]);
  f3d_world_destroy(one);
}

static void test_refused(void) {
  F3dWorld *w = f3d_world_create();
  CHECK(!f3d_world_set_threads(w, 0));
  CHECK(!f3d_world_set_threads(w, 65));
  CHECK(f3d_world_threads(w) == 1);
  CHECK(f3d_world_set_threads(w, 64));
  CHECK(f3d_world_set_threads(w, 64));
  CHECK(f3d_world_threads(w) == 64);
  /* An empty world steps on all of them. */
  f3d_world_step(w, F3D_R(1.0 / 60.0));
  f3d_world_destroy(w);
}

int main(void) {
  test_same_bits();
  test_refused();
  return finish();
}
