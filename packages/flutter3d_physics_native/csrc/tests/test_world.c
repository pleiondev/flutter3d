/*
 * The world, its arena, its air, wind and origin, and its events, tested in
 * C — P9.
 *
 * Built and run by test/c_unit_test.dart in both precisions, with every
 * warning an error and the address and undefined-behaviour sanitisers on,
 * so a use after free or an overflow in the arena fails here before it
 * fails in a game.
 */
#include <string.h>

#include "check.h"

static void test_abi_and_defaults(void) {
  CHECK(f3d_abi_version() == F3D_ABI_VERSION);
  CHECK(f3d_real_bytes() == sizeof(f3d_real));
  F3dWorld *w = f3d_world_create();
  CHECK(w != NULL);
  f3d_real g[3];
  f3d_world_get_gravity(w, g);
  CHECK(g[0] == 0 && g[1] == F3D_R(-9.81) && g[2] == 0);
  CHECK(f3d_world_body_count(w) == 0);
  f3d_world_set_gravity(w, 1, 2, 3);
  f3d_world_get_gravity(w, g);
  CHECK(g[0] == 1 && g[1] == 2 && g[2] == 3);
  f3d_real air[2];
  f3d_world_get_air(w, air);
  CHECK(air[0] == F3D_R(293.15) && air[1] == F3D_R(1.204));
  CHECK(f3d_world_set_air(w, 0, 1) == 0);
  CHECK(f3d_world_set_air(w, 300, -1) == 0);
  CHECK(f3d_world_set_air(w, nan_value(), 1) == 0);
  CHECK(f3d_world_set_air(w, 300, 1.2f) == 1);
  f3d_world_get_air(w, air);
  CHECK(air[0] == 300 && air[1] == F3D_R(1.2f));
  CHECK(f3d_world_set_sleep(w, -1, 1) == 0);
  CHECK(f3d_world_set_sleep(w, 1, inf_value()) == 0);
  CHECK(f3d_world_set_sleep(w, 0.1f, 0) == 1);
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
  CHECK(f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 0) == 0);
  CHECK(f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, -1) == 0);
  CHECK(f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, nan_value()) == 0);
  CHECK(f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, inf_value()) == 0);
  CHECK(f3d_body_create(w, (F3dBodyType)7, 0, 0, 0, 1) == 0);
  CHECK(f3d_body_create(w, F3D_BODY_DYNAMIC, nan_value(), 0, 0, 1) == 0);
  CHECK(f3d_body_create(w, F3D_BODY_DYNAMIC, 0, inf_value(), 0, 1) == 0);
  /* A fixed body's mass is thermal only, so nought is fine there. */
  const F3dBody fixed = f3d_body_create(w, F3D_BODY_FIXED, 0, 0, 0, 0);
  CHECK(fixed != 0);
  CHECK(f3d_world_body_count(w) == 1);
  /* A setter given nonsense changes nothing and says so. */
  const F3dBody a = f3d_body_create(w, F3D_BODY_DYNAMIC, 1, 2, 3, 1);
  CHECK(f3d_body_set_position(w, a, nan_value(), 0, 0) == 0);
  CHECK(f3d_body_set_velocity(w, a, 0, inf_value(), 0) == 0);
  CHECK(f3d_body_add_force(w, a, 0, 0, nan_value()) == 0);
  CHECK(f3d_body_set_shape(w, a, F3D_SHAPE_SPHERE, 0, 0, 0) == 0);
  CHECK(f3d_body_set_shape(w, a, F3D_SHAPE_BOX, 1, -1, 1) == 0);
  CHECK(f3d_body_set_shape(w, a, F3D_SHAPE_CAPSULE, 1, -1, 0) == 0);
  CHECK(f3d_body_set_shape(w, a, (F3dShapeKind)9, 1, 1, 1) == 0);
  CHECK(f3d_body_set_damping(w, a, -1, 0) == 0);
  CHECK(f3d_body_set_drag(w, a, nan_value()) == 0);
  f3d_real p[3];
  f3d_body_get_position(w, a, p);
  CHECK(p[0] == 1 && p[1] == 2 && p[2] == 3);
  f3d_world_destroy(w);
}

static void test_handles(void) {
  F3dWorld *w = f3d_world_create();
  const F3dBody a = f3d_body_create(w, F3D_BODY_DYNAMIC, 1, 2, 3, 2);
  const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, 4, 5, 6, 1);
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
  const F3dBody c = f3d_body_create(w, F3D_BODY_DYNAMIC, 7, 8, 9, 1);
  CHECK((uint32_t)c == (uint32_t)a);
  CHECK((c >> 32) == (a >> 32) + 1);
  CHECK(!f3d_body_is_valid(w, a));
  f3d_real p[4];
  CHECK(f3d_body_get_position(w, a, p) == 0);
  CHECK(f3d_body_get_position(w, c, p) == 1);
  CHECK(p[0] == 7 && p[1] == 8 && p[2] == 9);

  /* Every accessor refuses a stale handle. */
  int burning;
  F3dMaterial m;
  f3d_material_preset(F3D_MATERIAL_WOOD, &m);
  CHECK(f3d_body_set_velocity(w, a, 1, 1, 1) == 0);
  CHECK(f3d_body_get_velocity(w, a, p) == 0);
  CHECK(f3d_body_set_position(w, a, 1, 1, 1) == 0);
  CHECK(f3d_body_set_angular_velocity(w, a, 1, 1, 1) == 0);
  CHECK(f3d_body_get_angular_velocity(w, a, p) == 0);
  CHECK(f3d_body_set_orientation(w, a, 0, 0, 0, 1) == 0);
  CHECK(f3d_body_get_orientation(w, a, p) == 0);
  CHECK(f3d_body_set_shape(w, a, F3D_SHAPE_SPHERE, 1, 0, 0) == 0);
  CHECK(f3d_body_get_inertia(w, a, p) == 0);
  CHECK(f3d_body_get_mass(w, a, p) == 0);
  CHECK(f3d_body_lock_rotation(w, a, 1) == 0);
  CHECK(f3d_body_set_damping(w, a, 0, 0) == 0);
  CHECK(f3d_body_set_drag(w, a, 0) == 0);
  CHECK(f3d_body_apply_impulse(w, a, 1, 0, 0) == 0);
  CHECK(f3d_body_apply_impulse_at(w, a, 1, 0, 0, 0, 0, 0) == 0);
  CHECK(f3d_body_add_force(w, a, 1, 0, 0) == 0);
  CHECK(f3d_body_add_torque(w, a, 1, 0, 0) == 0);
  CHECK(f3d_body_is_asleep(w, a) == 0);
  CHECK(f3d_body_wake(w, a) == 0);
  CHECK(f3d_body_set_material(w, a, &m) == 0);
  CHECK(f3d_body_set_temperature(w, a, 300) == 0);
  CHECK(f3d_body_get_temperature(w, a, p) == 0);
  CHECK(f3d_body_add_heat(w, a, 1) == 0);
  CHECK(f3d_body_add_water(w, a, 1) == 0);
  CHECK(f3d_body_get_water(w, a, p) == 0);
  CHECK(f3d_body_get_fuel(w, a, p) == 0);
  CHECK(f3d_body_is_burning(w, a, &burning) == 0);
  CHECK(f3d_body_get_heat_release(w, a, p) == 0);
  double wp[3];
  CHECK(f3d_body_get_world_position(w, a, wp) == 0);
  f3d_world_destroy(w);
}

static void test_generation_wraps_past_nought(void) {
  F3dWorld *w = f3d_world_create();
  const F3dBody a = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 1);
  /* Pretend the slot has been reused four billion times. */
  w->slots[(uint32_t)a].generation = UINT32_MAX;
  const F3dBody worn = ((uint64_t)UINT32_MAX << 32) | (uint32_t)a;
  CHECK(f3d_body_destroy(w, worn) == 1);
  const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 1);
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
    bodies[i] = f3d_body_create(w, F3D_BODY_DYNAMIC, (f3d_real)i, 0, 0, 1);
    CHECK(bodies[i] != 0);
  }
  CHECK(f3d_world_body_count(w) == N);
  int all_valid = 1;
  for (int i = 0; i < N; i++) {
    f3d_real p[3];
    all_valid &= f3d_body_get_position(w, bodies[i], p) && p[0] == (f3d_real)i;
  }
  CHECK(all_valid);
  f3d_world_destroy(w);
}

static void test_step(void) {
  F3dWorld *w = f3d_world_create();
  /* One substep: the step's own algebra, checked to the bit. */
  CHECK(f3d_world_set_substeps(w, 0) == 0);
  CHECK(f3d_world_set_substeps(w, 65) == 0);
  CHECK(f3d_world_set_substeps(w, 1) == 1);
  f3d_world_set_gravity(w, 0, -10, 0);
  const F3dBody falling = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 10, 0, 1);
  const F3dBody pinned = f3d_body_create(w, F3D_BODY_FIXED, 0, 10, 0, 0);
  const F3dBody thrown = f3d_body_create(w, F3D_BODY_DYNAMIC, 0, 0, 0, 3);
  f3d_body_set_velocity(w, thrown, 2, 0, 0);

  f3d_world_step(w, 0.5f);
  f3d_real p[3], v[3];
  /* Velocity first, then position with it: v = -5, y = 10 - 2.5. */
  f3d_body_get_velocity(w, falling, v);
  f3d_body_get_position(w, falling, p);
  CHECK(v[1] == -5);
  CHECK(p[1] == F3D_R(7.5));
  f3d_body_get_position(w, pinned, p);
  CHECK(p[1] == 10);
  /* Mass does not change a free fall. */
  f3d_body_get_position(w, thrown, p);
  CHECK(p[0] == 1 && p[1] == F3D_R(-2.5));

  /* A step of nothing, or of nonsense, changes nothing. */
  f3d_world_step(w, 0);
  f3d_world_step(w, -1);
  f3d_world_step(w, nan_value());
  f3d_world_step(w, inf_value());
  f3d_body_get_position(w, falling, p);
  CHECK(p[1] == F3D_R(7.5));
  f3d_world_destroy(w);
}

static void test_substeps(void) {
  /* A step of n substeps is n steps of dt / n, to the bit. */
  F3dWorld *a = f3d_world_create();
  F3dWorld *b = f3d_world_create();
  f3d_world_set_substeps(a, 4);
  f3d_world_set_substeps(b, 1);
  const F3dBody ba = f3d_body_create(a, F3D_BODY_DYNAMIC, 0, 10, 0, 1);
  const F3dBody bb = f3d_body_create(b, F3D_BODY_DYNAMIC, 0, 10, 0, 1);
  f3d_body_set_velocity(a, ba, 3, 1, 0);
  f3d_body_set_velocity(b, bb, 3, 1, 0);
  for (int i = 0; i < 30; i++) {
    f3d_world_step(a, F3D_R(0.25));
    for (int k = 0; k < 4; k++) f3d_world_step(b, F3D_R(0.25) / 4);
  }
  f3d_real pa[3], pb[3];
  f3d_body_get_position(a, ba, pa);
  f3d_body_get_position(b, bb, pb);
  CHECK(pa[0] == pb[0] && pa[1] == pb[1]);
  f3d_world_destroy(a);
  f3d_world_destroy(b);
}

static void test_read_transforms(void) {
  F3dWorld *w = f3d_world_create();
  const F3dBody a = f3d_body_create(w, F3D_BODY_DYNAMIC, 1, 0, 0, 1);
  const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, 2, 0, 0, 1);
  const F3dBody c = f3d_body_create(w, F3D_BODY_DYNAMIC, 3, 0, 0, 1);
  f3d_body_destroy(w, b);

  f3d_real t[3 * F3D_TRANSFORM_FLOATS];
  F3dBody h[3];
  memset(t, 0, sizeof t);
  CHECK(f3d_world_read_transforms(w, t, h, 3) == 2);
  /* Slot order, skipping the freed slot. */
  CHECK(h[0] == a && h[1] == c);
  CHECK(t[0] == 1 && t[F3D_TRANSFORM_FLOATS] == 3);
  /* Unrotated: the identity quaternion. */
  CHECK(t[3] == 0 && t[4] == 0 && t[5] == 0 && t[6] == 1);
  /* No more than the capacity, and the handles may be left out. */
  CHECK(f3d_world_read_transforms(w, t, NULL, 1) == 1);
  CHECK(f3d_world_read_transforms(w, t, NULL, 0) == 0);
  f3d_world_destroy(w);
}

static void test_origin(void) {
  /* A body ten kilometres out: f32 holds its position to a millimetre at
   * best. Moved to an origin beside it, the same body is held to a
   * micrometre, and nothing in the world has moved. */
  F3dWorld *w = f3d_world_create();
  f3d_world_set_gravity(w, 0, 0, 0);
  const F3dBody far = f3d_body_create(w, F3D_BODY_DYNAMIC, 10000, 0, 0, 1);
  double before[3], after[3], origin[3];
  f3d_body_get_world_position(w, far, before);
  f3d_world_shift_origin(w, 10000.0, 0.0, 0.0);
  f3d_world_get_origin(w, origin);
  CHECK(origin[0] == 10000.0 && origin[1] == 0.0);
  f3d_real p[3];
  f3d_body_get_position(w, far, p);
  CHECK(p[0] == 0);
  f3d_body_get_world_position(w, far, after);
  CHECK(after[0] == before[0] && after[1] == before[1]);
  /* Now a micrometre is a step it can take. */
  f3d_body_set_velocity(w, far, 1e-6f, 0, 0);
  f3d_world_step(w, 1);
  f3d_body_get_world_position(w, far, after);
  CHECK_NEAR(after[0] - 10000.0, 1e-6, 1e-12);
  /* Not a shift at all: refused, nothing moved. */
  f3d_world_shift_origin(w, (double)nan_value(), 0, 0);
  f3d_world_get_origin(w, origin);
  CHECK(origin[0] == 10000.0);
  f3d_world_destroy(w);
}

static void test_wind_grid(void) {
  F3dWorld *w = f3d_world_create();
  f3d_real out[3];
  f3d_world_sample_wind(w, 5, 5, 5, out);
  CHECK(out[0] == 0 && out[1] == 0 && out[2] == 0);
  f3d_world_set_wind(w, 1, 0, 0);
  /* Two by one by one samples, two metres apart: 0 then 4 m/s along z,
   * plus the uniform 1 along x. */
  const f3d_real grid[6] = {0, 0, 0, 0, 0, 4};
  CHECK(f3d_world_set_wind_grid(w, 0, 0, 0, 0, 2, 1, 1, grid) == 0);
  CHECK(f3d_world_set_wind_grid(w, 0, 0, 0, 2, 0, 1, 1, grid) == 0);
  CHECK(f3d_world_set_wind_grid(w, 0, 0, 0, 2, 2, 1, 1, grid) == 1);
  f3d_world_sample_wind(w, 1, 7, -3, out);
  CHECK(out[0] == 1 && out[1] == 0 && out[2] == 2);
  /* Held at its edges. */
  f3d_world_sample_wind(w, -5, 0, 0, out);
  CHECK(out[2] == 0);
  f3d_world_sample_wind(w, 50, 0, 0, out);
  CHECK(out[2] == 4);
  f3d_world_sample_wind(w, F3D_R(0.5), 0, 0, out);
  CHECK(out[2] == 1);
  /* Trilinear across all three axes: the middle of a 2×2×2 cube is the
   * mean of its corners. */
  f3d_real cube[24];
  for (int i = 0; i < 8; i++) {
    cube[i * 3] = (f3d_real)i;
    cube[i * 3 + 1] = 0;
    cube[i * 3 + 2] = 0;
  }
  CHECK(f3d_world_set_wind_grid(w, 0, 0, 0, 1, 2, 2, 2, cube) == 1);
  f3d_world_sample_wind(w, F3D_R(0.5), F3D_R(0.5), F3D_R(0.5), out);
  CHECK(out[0] == F3D_R(1.0) + F3D_R(3.5));
  /* At a sample, the sample. */
  f3d_world_sample_wind(w, 1, 1, 0, out);
  CHECK(out[0] == F3D_R(1.0) + 3);
  /* Cleared. */
  CHECK(f3d_world_set_wind_grid(w, 0, 0, 0, 1, 1, 1, 1, NULL) == 1);
  f3d_world_sample_wind(w, F3D_R(0.5), F3D_R(0.5), F3D_R(0.5), out);
  CHECK(out[0] == 1);
  /* The grid moves with the origin, so the world's wind stays put. */
  CHECK(f3d_world_set_wind_grid(w, 0, 0, 0, 2, 2, 1, 1, grid) == 1);
  f3d_world_shift_origin(w, 1.0, 0.0, 0.0);
  f3d_world_sample_wind(w, 0, 0, 0, out);
  CHECK(out[2] == 2);
  f3d_world_destroy(w);
}

static void test_events(void) {
  F3dWorld *w = f3d_world_create();
  F3dBody bodies[4];
  uint32_t kinds[4];
  CHECK(f3d_world_read_events(w, bodies, NULL, kinds, 4) == 0);
  f3d_push_event(w, 11, F3D_EVENT_IGNITED);
  f3d_push_event(w, 12, F3D_EVENT_SLEPT);
  f3d_push_event(w, 13, F3D_EVENT_WOKE);
  /* Read a part: the oldest first, and the rest waits. */
  CHECK(f3d_world_read_events(w, bodies, NULL, kinds, 2) == 2);
  CHECK(bodies[0] == 11 && kinds[0] == F3D_EVENT_IGNITED);
  CHECK(bodies[1] == 12 && kinds[1] == F3D_EVENT_SLEPT);
  CHECK(f3d_world_read_events(w, bodies, NULL, kinds, 4) == 1);
  CHECK(bodies[0] == 13 && kinds[0] == F3D_EVENT_WOKE);
  /* Past the capacity, the newest are dropped and counted, and the ring
   * wraps without losing order. */
  for (uint32_t i = 0; i < F3D_EVENT_CAPACITY + 5u; i++) {
    f3d_push_event(w, i + 1u, F3D_EVENT_SLEPT);
  }
  CHECK(f3d_world_events_dropped(w) == 5);
  CHECK(f3d_world_read_events(w, bodies, NULL, kinds, 1) == 1);
  CHECK(bodies[0] == 1);
  f3d_push_event(w, 777, F3D_EVENT_WOKE);
  uint32_t left = 0;
  F3dBody last = 0;
  while (f3d_world_read_events(w, bodies, NULL, kinds, 1) == 1) {
    left++;
    last = bodies[0];
  }
  CHECK(left == F3D_EVENT_CAPACITY);
  CHECK(last == 777);
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
  test_substeps();
  test_read_transforms();
  test_origin();
  test_wind_grid();
  test_events();
  return finish();
}
