/*
 * Snapshots, tested in C — P9: a world restored from one steps to the same
 * bits as the world it was taken from, the same world is the same bytes,
 * and a buffer that is not a snapshot of this build is refused with the
 * world left as it was.
 */
#include <stdlib.h>
#include <string.h>

#include "check.h"

/* A world with something of everything in it: bodies turning, falling
 * through a wind grid, one burning, one wet, a fixed one in a freed slot,
 * and events waiting. */
static F3dWorld *busy_world(F3dBody *keep) {
  F3dWorld *w = f3d_world_create();
  f3d_world_shift_origin(w, 1234.5, -6.25, 1e5);
  const f3d_real grid[12] = {1, 0, 0, 0, 0, 2, -1, 0, 0, 0, 3, 0};
  f3d_world_set_wind_grid(w, -5, 0, -5, 5, 2, 1, 2, grid);
  F3dMaterial wood;
  f3d_material_preset(F3D_MATERIAL_WOOD, &wood);
  for (int i = 0; i < 6; i++) {
    const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, (f3d_real)i,
                                      (f3d_real)(i * 2), 0, F3D_R(0.5) + i);
    f3d_body_set_shape(w, b, (F3dShapeKind)(1 + i % 3), F3D_R(0.2),
                       F3D_R(0.3), F3D_R(0.1));
    f3d_body_set_angular_velocity(w, b, F3D_R(0.3) * i, 1, F3D_R(-0.7));
    f3d_body_set_material(w, b, &wood);
    keep[i] = b;
  }
  f3d_body_set_temperature(w, keep[1], 650);
  f3d_body_add_water(w, keep[2], F3D_R(0.02));
  f3d_body_destroy(w, keep[3]);
  const F3dBody sleeper = f3d_body_create(w, F3D_BODY_FIXED, 9, 9, 9, 1);
  keep[3] = sleeper;
  for (int i = 0; i < 30; i++) f3d_world_step(w, F3D_R(1.0 / 60.0));
  return w;
}

static uint8_t *snapshot_of(const F3dWorld *w, uint32_t *size) {
  *size = f3d_world_snapshot_size(w);
  uint8_t *buffer = (uint8_t *)malloc(*size);
  CHECK(f3d_world_snapshot_write(w, buffer, *size) == *size);
  return buffer;
}

static void test_round_trip(void) {
  F3dBody keep[6];
  F3dWorld *a = busy_world(keep);
  uint32_t size;
  uint8_t *snap = snapshot_of(a, &size);
  /* The same world is the same bytes. */
  uint32_t again_size;
  uint8_t *again = snapshot_of(a, &again_size);
  CHECK(again_size == size && memcmp(snap, again, size) == 0);
  free(again);

  /* Restored into a world that held something else entirely, and both
   * stepped on: the same bits, all the way down. */
  F3dWorld *b = f3d_world_create();
  for (int i = 0; i < 100; i++) f3d_body_create(b, F3D_BODY_DYNAMIC, 0, 0, 0, 1);
  CHECK(f3d_world_restore(b, snap, size) == 1);
  CHECK(f3d_world_body_count(b) == f3d_world_body_count(a));
  for (int i = 0; i < 6; i++) CHECK(f3d_body_is_valid(b, keep[i]));
  for (int i = 0; i < 600; i++) {
    f3d_world_step(a, F3D_R(1.0 / 60.0));
    f3d_world_step(b, F3D_R(1.0 / 60.0));
  }
  uint32_t sa, sb;
  uint8_t *after_a = snapshot_of(a, &sa);
  uint8_t *after_b = snapshot_of(b, &sb);
  CHECK(sa == sb && memcmp(after_a, after_b, sa) == 0);
  free(after_a);
  free(after_b);
  /* Including what they said happened. */
  F3dBody ba[64], bb[64];
  uint32_t ka[64], kb[64];
  const uint32_t na = f3d_world_read_events(a, ba, ka, 64);
  const uint32_t nb = f3d_world_read_events(b, bb, kb, 64);
  CHECK(na == nb && na > 0);
  CHECK(memcmp(ba, bb, na * sizeof(F3dBody)) == 0);
  CHECK(memcmp(ka, kb, na * sizeof(uint32_t)) == 0);

  /* A body made after the snapshot is gone once it is restored, and its
   * handle with it. */
  const F3dBody late = f3d_body_create(a, F3D_BODY_DYNAMIC, 0, 0, 0, 1);
  CHECK(f3d_world_restore(a, snap, size) == 1);
  CHECK(!f3d_body_is_valid(a, late));
  /* And a world can go back to its own past and grow from there. */
  for (int i = 0; i < 200; i++) f3d_body_create(a, F3D_BODY_DYNAMIC, 0, 0, 0, 1);
  CHECK(f3d_world_body_count(a) == 206);
  free(snap);
  f3d_world_destroy(a);
  f3d_world_destroy(b);
}

static void test_refusals(void) {
  F3dBody keep[6];
  F3dWorld *a = busy_world(keep);
  uint32_t size;
  uint8_t *snap = snapshot_of(a, &size);
  /* Too small a buffer to write into. */
  CHECK(f3d_world_snapshot_write(a, snap, size - 1) == 0);
  CHECK(f3d_world_snapshot_write(a, NULL, size) == 0);

  F3dWorld *b = f3d_world_create();
  const F3dBody mine = f3d_body_create(b, F3D_BODY_DYNAMIC, 7, 7, 7, 1);
  CHECK(f3d_world_restore(b, NULL, size) == 0);
  CHECK(f3d_world_restore(b, snap, 3) == 0);
  CHECK(f3d_world_restore(b, snap, size - 1) == 0);
  /* Not a snapshot, or one from another build. */
  uint8_t *bad = (uint8_t *)malloc(size);
  memcpy(bad, snap, size);
  bad[0] ^= 1;
  CHECK(f3d_world_restore(b, bad, size) == 0);
  memcpy(bad, snap, size);
  bad[8] ^= 4; /* The real's size. */
  CHECK(f3d_world_restore(b, bad, size) == 0);
  memcpy(bad, snap, size);
  bad[4] ^= 1; /* The version. */
  CHECK(f3d_world_restore(b, bad, size) == 0);
  /* Refused, the world is as it was. */
  CHECK(f3d_world_body_count(b) == 1);
  f3d_real p[3];
  CHECK(f3d_body_get_position(b, mine, p) == 1 && p[0] == 7);
  free(bad);
  /* An empty world round-trips too. */
  F3dWorld *empty = f3d_world_create();
  uint32_t empty_size;
  uint8_t *nothing = snapshot_of(empty, &empty_size);
  CHECK(f3d_world_restore(b, nothing, empty_size) == 1);
  CHECK(f3d_world_body_count(b) == 0);
  CHECK(f3d_body_create(b, F3D_BODY_DYNAMIC, 0, 0, 0, 1) != 0);
  free(nothing);
  f3d_world_destroy(empty);
  free(snap);
  f3d_world_destroy(a);
  f3d_world_destroy(b);
}

int main(void) {
  test_round_trip();
  test_refusals();
  return finish();
}
