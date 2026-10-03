/*
 * The world, its arena and its step, tested in C — P9, phase 0.
 *
 * Built and run by test/c_unit_test.dart with every warning an error and
 * the address and undefined-behaviour sanitisers on, so a use after free or
 * an overflow in the arena fails here before it fails in a game.
 */
#include <stdio.h>
#include <string.h>

#include "f3d_internal.h"
#include "f3d_physics.h"

static int g_failures = 0;
static int g_checks = 0;

#define CHECK(cond)                                                     \
  do {                                                                  \
    g_checks++;                                                         \
    if (!(cond)) {                                                      \
      g_failures++;                                                     \
      fprintf(stderr, "%s:%d: CHECK(%s) failed\n", __FILE__, __LINE__,  \
              #cond);                                                   \
    }                                                                   \
  } while (0)

static float nan_value(void) {
  volatile float zero = 0.0f;
  return zero / zero;
}

static float inf_value(void) {
  volatile float zero = 0.0f;
  return 1.0f / zero;
}

static void test_abi_and_defaults(void) {
  CHECK(f3d_abi_version() == F3D_ABI_VERSION);
  F3dWorld *w = f3d_world_create();
  CHECK(w != NULL);
  float g[3];
  f3d_world_get_gravity(w, g);
  CHECK(g[0] == 0.0f && g[1] == -9.81f && g[2] == 0.0f);
  CHECK(f3d_world_body_count(w) == 0);
  f3d_world_set_gravity(w, 1.0f, 2.0f, 3.0f);
  f3d_world_get_gravity(w, g);
  CHECK(g[0] == 1.0f && g[1] == 2.0f && g[2] == 3.0f);
  f3d_world_destroy(w);
  f3d_world_destroy(NULL); /* Allowed. */
}

static void test_buffers(void) {
  float *a = (float *)f3d_buffer_alloc(64 * sizeof(float));
  float *b = (float *)f3d_buffer_alloc(8);
  CHECK(a != NULL && b != NULL && (void *)a != (void *)b);
  for (int i = 0; i < 64; i++) a[i] = (float)i;
  CHECK(a[63] == 63.0f);
  f3d_buffer_free(a);
  f3d_buffer_free(b);
  f3d_buffer_free(NULL); /* Allowed. */
}

static void test_refusals(void) {
  F3dWorld *w = f3d_world_create();
  CHECK(f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 0.0f) == 0);
  CHECK(f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, -1.0f) == 0);
  CHECK(f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, nan_value()) == 0);
  CHECK(f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, inf_value()) == 0);
  CHECK(f3d_body_create(w, (F3dBodyType)7, 0, 0, 0, 1.0f) == 0);
  CHECK(f3d_body_create(w, F3D_BODY_DYNAMIC, nan_value(), 0, 0, 1.0f) == 0);
  CHECK(f3d_body_create(w, F3D_BODY_DYNAMIC, 0, inf_value(), 0, 1.0f) == 0);
  /* A fixed body's mass is not read, so nought is fine there. */
  CHECK(f3d_body_create(w, F3D_BODY_FIXED, 0, 0, 0, 0.0f) != 0);
  CHECK(f3d_world_body_count(w) == 1);
  f3d_world_destroy(w);
}

static void test_handles(void) {
  F3dWorld *w = f3d_world_create();
  const F3dBody a = f3d_body_create(w, F3D_BODY_DYNAMIC, 1, 2, 3, 2.0f);
  const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, 4, 5, 6, 1.0f);
  CHECK(a != 0 && b != 0 && a != b);
  CHECK(f3d_body_is_valid(w, a) && f3d_body_is_valid(w, b));
  CHECK(!f3d_body_is_valid(w, 0));
  /* A slot past the arena's high-water mark, with a plausible generation. */
  CHECK(!f3d_body_is_valid(w, ((uint64_t)1 << 32) | 999u));

  CHECK(f3d_body_destroy(w, a) == 1);
  CHECK(f3d_body_destroy(w, a) == 0);
  CHECK(!f3d_body_is_valid(w, a));
  CHECK(f3d_world_body_count(w) == 1);

  /* The freed slot is reused with a new generation: the old handle still
   * names nothing, and the new one names the new body. */
  const F3dBody c = f3d_body_create(w, F3D_BODY_DYNAMIC, 7, 8, 9, 1.0f);
  CHECK((uint32_t)c == (uint32_t)a);
  CHECK((c >> 32) == (a >> 32) + 1);
  CHECK(!f3d_body_is_valid(w, a));
  float p[3];
  CHECK(f3d_body_get_position(w, a, p) == 0);
  CHECK(f3d_body_get_position(w, c, p) == 1);
  CHECK(p[0] == 7.0f && p[1] == 8.0f && p[2] == 9.0f);

  /* Every accessor refuses a stale handle. */
  CHECK(f3d_body_set_velocity(w, a, 1, 1, 1) == 0);
  CHECK(f3d_body_get_velocity(w, a, p) == 0);
  CHECK(f3d_body_set_position(w, a, 1, 1, 1) == 0);
  f3d_world_destroy(w);
}

static void test_generation_wraps_past_nought(void) {
  F3dWorld *w = f3d_world_create();
  const F3dBody a = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 1.0f);
  /* Pretend the slot has been reused four billion times. */
  w->slots[(uint32_t)a].generation = UINT32_MAX;
  const F3dBody worn = ((uint64_t)UINT32_MAX << 32) | (uint32_t)a;
  CHECK(f3d_body_destroy(w, worn) == 1);
  const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 1.0f);
  CHECK(b != 0);
  CHECK((b >> 32) == 1);
  CHECK(f3d_body_is_valid(w, b));
  f3d_world_destroy(w);
}

static void test_growth(void) {
  enum { N = 1000 };
  static F3dBody bodies[N];
  F3dWorld *w = f3d_world_create();
  for (int i = 0; i < N; i++) {
    bodies[i] = f3d_body_create(w, F3D_BODY_DYNAMIC, (float)i, 0, 0, 1.0f);
    CHECK(bodies[i] != 0);
  }
  CHECK(f3d_world_body_count(w) == N);
  int all_valid = 1;
  for (int i = 0; i < N; i++) {
    float p[3];
    all_valid &= f3d_body_get_position(w, bodies[i], p) && p[0] == (float)i;
  }
  CHECK(all_valid);
  f3d_world_destroy(w);
}

static void test_step(void) {
  F3dWorld *w = f3d_world_create();
  f3d_world_set_gravity(w, 0.0f, -10.0f, 0.0f);
  const F3dBody falling = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 10, 0, 1.0f);
  const F3dBody pinned = f3d_body_create(w, F3D_BODY_FIXED, 0, 10, 0, 0.0f);
  const F3dBody thrown = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 3.0f);
  f3d_body_set_velocity(w, thrown, 2.0f, 0.0f, 0.0f);

  f3d_world_step(w, 0.5f);
  float p[3], v[3];
  /* Velocity first, then position with it: v = -5, y = 10 - 2.5. */
  f3d_body_get_velocity(w, falling, v);
  f3d_body_get_position(w, falling, p);
  CHECK(v[1] == -5.0f);
  CHECK(p[1] == 7.5f);
  f3d_body_get_position(w, pinned, p);
  CHECK(p[1] == 10.0f);
  /* Mass does not change a free fall. */
  f3d_body_get_position(w, thrown, p);
  CHECK(p[0] == 1.0f && p[1] == -2.5f);

  /* A step of nothing, or of nonsense, changes nothing. */
  f3d_world_step(w, 0.0f);
  f3d_world_step(w, -1.0f);
  f3d_world_step(w, nan_value());
  f3d_world_step(w, inf_value());
  f3d_body_get_position(w, falling, p);
  CHECK(p[1] == 7.5f);
  f3d_world_destroy(w);
}

static void test_read_transforms(void) {
  F3dWorld *w = f3d_world_create();
  const F3dBody a = f3d_body_create(w, F3D_BODY_DYNAMIC, 1, 0, 0, 1.0f);
  const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, 2, 0, 0, 1.0f);
  const F3dBody c = f3d_body_create(w, F3D_BODY_DYNAMIC, 3, 0, 0, 1.0f);
  f3d_body_destroy(w, b);

  float t[3 * F3D_TRANSFORM_FLOATS];
  F3dBody h[3];
  memset(t, 0, sizeof t);
  CHECK(f3d_world_read_transforms(w, t, h, 3) == 2);
  /* Slot order, skipping the freed slot. */
  CHECK(h[0] == a && h[1] == c);
  CHECK(t[0] == 1.0f && t[F3D_TRANSFORM_FLOATS] == 3.0f);
  /* Unrotated: the identity quaternion. */
  CHECK(t[3] == 0.0f && t[4] == 0.0f && t[5] == 0.0f && t[6] == 1.0f);
  /* No more than the capacity, and the handles may be left out. */
  CHECK(f3d_world_read_transforms(w, t, NULL, 1) == 1);
  CHECK(f3d_world_read_transforms(w, t, NULL, 0) == 0);
  f3d_world_destroy(w);
}

int main(void) {
  test_abi_and_defaults();
  test_buffers();
  test_refusals();
  test_handles();
  test_generation_wraps_past_nought();
  test_growth();
  test_step();
  test_read_transforms();
  if (g_failures != 0) {
    fprintf(stderr, "%d of %d checks failed\n", g_failures, g_checks);
    return 1;
  }
  printf("%d checks passed\n", g_checks);
  return 0;
}
