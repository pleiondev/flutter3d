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
#include "scene.h"

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
