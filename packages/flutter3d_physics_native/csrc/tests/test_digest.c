/*
 * The core's digests — P9, phase 13: what it steps a world of every shape,
 * the same world in the fast mode on three threads, a ragdoll down a
 * flight of stairs, a heap of debris, a sheet of cloth over a ball, water
 * in a tank and a spray of particles to, as one hash of their every real
 * apiece, held against the hashes written below. They were taken on one
 * machine; any other — another operating system, compiler or processor —
 * that steps the core to other bits fails here. `tool/digest_platforms.sh`
 * runs this file on Linux, Android and iOS; CI on Windows too.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "check.h"
#include "ragdoll.h"
#include "scene.h"

#ifdef F3D_REAL_DOUBLE
static const uint64_t expected[7] = {0x1fb772f206ab8078ull, 0xd6c42b47ec0c4233ull, 0x133d63714f6d0c92ull,
                                     0xdea75fe91bac5613ull, 0xc98ced65f832abbeull, 0x4c8f3b90f328112cull,
                                     0xd1be7e081d0955e8ull};
#else
static const uint64_t expected[7] = {0x3ff514dab6b2c971ull, 0x6b72b563c215f443ull, 0x9fb0722eaf94140aull,
                                     0xbd9efabeee7e9ee4ull, 0x0a0952b9452611cfull, 0x840abe40761b9b85ull,
                                     0x3d3a82b755727489ull};
#endif

static const char *const names[7] = {"world", "fast", "ragdoll", "debris", "cloth", "fluid", "particles"};

static uint64_t fnv(uint64_t hash, const void *data, size_t bytes) {
  const uint8_t *p = (const uint8_t *)data;
  for (size_t i = 0; i < bytes; i++) hash = (hash ^ p[i]) * 1099511628211ull;
  return hash;
}

enum { MOST = 512, MOST_REALS = 32768 };

/* Every body's transform, velocity and spin. */
static uint64_t world_hash(const F3dWorld *w) {
  static f3d_real t[MOST * F3D_TRANSFORM_FLOATS];
  static F3dBody handles[MOST];
  const uint32_t n = f3d_world_read_transforms(w, t, handles, MOST);
  uint64_t hash = fnv(1469598103934665603ull, t, (size_t)n * F3D_TRANSFORM_FLOATS * sizeof(f3d_real));
  for (uint32_t i = 0; i < n; i++) {
    f3d_real v[6];
    f3d_body_get_velocity(w, handles[i], v);
    f3d_body_get_angular_velocity(w, handles[i], v + 3);
    hash = fnv(hash, v, sizeof v);
  }
  return hash;
}

static uint64_t stepped_world(int fast) {
  F3dWorld *w = scene();
  if (fast) {
    f3d_world_set_fast(w, 1);
    CHECK(f3d_world_set_threads(w, 3));
  }
  for (int step = 0; step < 240; step++) f3d_world_step(w, F3D_R(1.0 / 60.0));
  const uint64_t hash = world_hash(w);
  f3d_world_destroy(w);
  return hash;
}

static uint64_t stepped_ragdoll(void) {
  F3dWorld *w = stairs_world();
  Ragdoll r;
  make(w, &r, 0, 2, 0);
  push_off(w, &r);
  for (int step = 0; step < 300; step++) f3d_world_step(w, F3D_R(1.0 / 60.0));
  const uint64_t hash = world_hash(w);
  f3d_world_destroy(w);
  return hash;
}

/* Six hundred balls of three sizes dropped in a heap into a box. */
static uint64_t stepped_debris(void) {
  F3dDebris *d = f3d_debris_create(600);
  static f3d_real in[600 * F3D_DEBRIS_INPUT_FLOATS];
  for (int i = 0; i < 600; i++) {
    f3d_real *b = in + i * F3D_DEBRIS_INPUT_FLOATS;
    b[0] = F3D_R(-0.9) + F3D_R(0.2) * (f3d_real)(i % 10);
    b[1] = F3D_R(0.3) + F3D_R(0.2) * (f3d_real)(i / 100);
    b[2] = F3D_R(-0.9) + F3D_R(0.2) * (f3d_real)((i / 10) % 10);
    b[3] = F3D_R(0.1) * (f3d_real)(i % 3 - 1);
    b[4] = 0;
    b[5] = F3D_R(0.1) * (f3d_real)(i % 5 - 2);
    b[6] = F3D_R(0.04) + F3D_R(0.02) * (f3d_real)(i % 3);
    b[7] = F3D_R(0.1) + F3D_R(0.05) * (f3d_real)(i % 3);
  }
  f3d_debris_add(d, in, 600);
  /* A floor and a box's four walls. */
  const f3d_real statics[5 * F3D_DEBRIS_STATIC_FLOATS] = {
      0, 1, 0, 0, 0, 0, 0, 0,  //
      F3D_R(1.2), 1, 0, 0, F3D_R(0.1), 1, F3D_R(1.3), 1,
      F3D_R(-1.2), 1, 0, 0, F3D_R(0.1), 1, F3D_R(1.3), 1,
      0, 1, F3D_R(1.2), 0, F3D_R(1.3), 1, F3D_R(0.1), 1,
      0, 1, F3D_R(-1.2), 0, F3D_R(1.3), 1, F3D_R(0.1), 1,
  };
  CHECK(f3d_debris_set_statics(d, statics, 5));
  F3dDebrisSettings s;
  memset(&s, 0, sizeof s);
  s.gravity[1] = F3D_R(-9.81);
  s.friction = F3D_R(0.5);
  s.restitution = F3D_R(0.3);
  s.linear_damping = F3D_R(0.05);
  s.angular_damping = F3D_R(0.1);
  s.max_speed = 20;
  s.substeps = 4;
  s.iterations = 2;
  for (int step = 0; step < 120; step++) f3d_debris_step(d, &s, F3D_R(1.0 / 60.0));
  static f3d_real out[600 * F3D_DEBRIS_FLOATS];
  const uint32_t n = f3d_debris_read(d, out, 600);
  f3d_debris_destroy(d);
  return fnv(1469598103934665603ull, out, (size_t)n * F3D_DEBRIS_FLOATS * sizeof(f3d_real));
}

/* A sheet of twenty by twenty points, its edges and shears held, dropped
 * over a ball in a wind. */
static uint64_t stepped_cloth(void) {
  enum { SIDE = 20, POINTS = SIDE * SIDE };
  static f3d_real points[POINTS * F3D_CLOTH_FLOATS];
  static uint32_t edges[POINTS * 4 * 2];
  static f3d_real compliance[POINTS * 4];
  for (int j = 0; j < SIDE; j++) {
    for (int i = 0; i < SIDE; i++) {
      f3d_real *p = points + (j * SIDE + i) * F3D_CLOTH_FLOATS;
      p[0] = F3D_R(0.05) * (f3d_real)(i - SIDE / 2);
      p[1] = F3D_R(1.0);
      p[2] = F3D_R(0.05) * (f3d_real)(j - SIDE / 2);
      p[3] = 1;
    }
  }
  uint32_t e = 0;
  for (int j = 0; j < SIDE; j++) {
    for (int i = 0; i < SIDE; i++) {
      const uint32_t a = (uint32_t)(j * SIDE + i);
      const int right = i + 1 < SIDE, down = j + 1 < SIDE;
      const uint32_t to[4] = {a + 1, a + SIDE, a + SIDE + 1, a + SIDE - 1};
      const int ok[4] = {right, down, right && down, i > 0 && down};
      for (int k = 0; k < 4; k++) {
        if (!ok[k]) continue;
        edges[2 * e] = a;
        edges[2 * e + 1] = to[k];
        compliance[e] = k < 2 ? 0 : F3D_R(1e-4);
        e++;
      }
    }
  }
  F3dCloth *c = f3d_cloth_create(points, POINTS, edges, compliance, e);
  CHECK(c != NULL);
  const f3d_real ball[4] = {0, F3D_R(0.5), 0, F3D_R(0.25)};
  CHECK(f3d_cloth_set_balls(c, ball, 1));
  F3dClothSettings s;
  memset(&s, 0, sizeof s);
  s.gravity[1] = F3D_R(-9.81);
  s.wind[0] = 2;
  s.drag = F3D_R(0.2);
  s.damping = F3D_R(0.1);
  s.thickness = F3D_R(0.01);
  s.friction = F3D_R(0.3);
  s.substeps = 8;
  for (int step = 0; step < 120; step++) f3d_cloth_step(c, &s, F3D_R(1.0 / 60.0));
  f3d_cloth_read(c, points, POINTS);
  f3d_cloth_destroy(c);
  return fnv(1469598103934665603ull, points, sizeof points);
}

/* A block of water let go at one end of a tank. */
static uint64_t stepped_fluid(void) {
  const f3d_real spacing = F3D_R(0.05);
  F3dFluid *f = f3d_fluid_create(800, spacing);
  static f3d_real in[800 * F3D_FLUID_INPUT_FLOATS];
  memset(in, 0, sizeof in);
  for (int i = 0; i < 800; i++) {
    in[i * F3D_FLUID_INPUT_FLOATS] = F3D_R(-0.45) + spacing * (f3d_real)(i % 8);
    in[i * F3D_FLUID_INPUT_FLOATS + 1] = F3D_R(0.025) + spacing * (f3d_real)(i / 80);
    in[i * F3D_FLUID_INPUT_FLOATS + 2] = F3D_R(-0.225) + spacing * (f3d_real)((i / 8) % 10);
  }
  f3d_fluid_add(f, in, 800);
  F3dFluidSettings s;
  memset(&s, 0, sizeof s);
  s.gravity[1] = F3D_R(-9.81);
  s.tank_min[0] = F3D_R(-0.5);
  s.tank_min[2] = F3D_R(-0.25);
  s.tank_max[0] = F3D_R(0.5);
  s.tank_max[1] = F3D_R(10.0);
  s.tank_max[2] = F3D_R(0.25);
  s.viscosity = F3D_R(0.01);
  s.relaxation = F3D_R(10.0);
  s.substeps = 2;
  s.iterations = 4;
  for (int step = 0; step < 120; step++) f3d_fluid_step(f, &s, F3D_R(1.0 / 60.0));
  static f3d_real out[800 * F3D_FLUID_FLOATS];
  const uint32_t n = f3d_fluid_read(f, out, 800);
  f3d_fluid_destroy(f);
  return fnv(1469598103934665603ull, out, (size_t)n * F3D_FLUID_FLOATS * sizeof(f3d_real));
}

/* Sparks thrown up in a fan, falling in a wind and bouncing on a floor. */
static uint64_t stepped_particles(void) {
  F3dParticles *p = f3d_particles_create(400);
  static f3d_real in[400 * 7];
  for (int i = 0; i < 400; i++) {
    f3d_real *q = in + i * 7;
    q[0] = 0;
    q[1] = F3D_R(0.5);
    q[2] = 0;
    q[3] = F3D_R(0.02) * (f3d_real)(i % 40 - 20);
    q[4] = 3 + F3D_R(0.01) * (f3d_real)(i % 17);
    q[5] = F3D_R(0.02) * (f3d_real)(i / 10 - 20);
    q[6] = 1 + F3D_R(0.005) * (f3d_real)i;
  }
  f3d_particles_emit(p, in, 400);
  const F3dParticleForces forces = {{0, F3D_R(-9.81), 0}, {1, 0, F3D_R(0.5)}, F3D_R(0.3), 0, F3D_R(0.4), F3D_R(0.2)};
  for (int step = 0; step < 150; step++) f3d_particles_step(p, &forces, F3D_R(1.0 / 60.0));
  static f3d_real out[400 * F3D_PARTICLE_FLOATS];
  const uint32_t n = f3d_particles_read(p, out, 400);
  f3d_particles_destroy(p);
  return fnv(1469598103934665603ull, out, (size_t)n * F3D_PARTICLE_FLOATS * sizeof(f3d_real));
}

int main(void) {
  const uint64_t got[7] = {stepped_world(0),  stepped_world(1), stepped_ragdoll(), stepped_debris(),
                           stepped_cloth(),   stepped_fluid(),  stepped_particles()};
  for (int k = 0; k < 7; k++) {
    printf("digest %s %016llx\n", names[k], (unsigned long long)got[k]);
    CHECK(got[k] == expected[k]);
  }
  return finish();
}
