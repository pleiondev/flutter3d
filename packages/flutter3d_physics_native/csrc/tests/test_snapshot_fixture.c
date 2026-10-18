/*
 * The committed 1.0 snapshots — the bytes a 1.x core has to keep reading.
 *
 * test/fixtures/v1/world.f32.snapshot and world.f64.snapshot are a world of
 * every subsystem (full_world.h: a car, a chain of links, joints, a hull, a
 * mesh and a compound, fire, a stream with spray and bubbles) as the 1.0
 * cores wrote it in each precision. Minted once and never again: each is
 * restored here, in the build of its own precision and in the other, and
 * stepped two seconds to the digests written below. A later core that
 * reorders a field, drops a section 1.0 wrote, or reads one differently
 * steps to other bits and fails here, whatever its own round trip says.
 *
 * A digest that fails is not to be updated: it means a 1.0 save no longer
 * restores to the world it was. Fix the reader, or the change is a major.
 *
 * Minting (done once, kept for the record): build this file with
 * -DF3D_MINT_FIXTURE in each precision and run it from the package root.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "check.h"

#ifdef F3D_MINT_FIXTURE
#include "full_world.h"
#endif

#ifdef F3D_REAL_DOUBLE
#define OWN "test/fixtures/v1/world.f64.snapshot"
#define OTHER "test/fixtures/v1/world.f32.snapshot"
#define OWN_BYTES 8u
/* The f64 snapshot restored in this build, and the f32 one, widened. */
static const uint64_t expected[2] = {0x0522b223c9d40ad0ull, 0xdd3160d6cdfc6af5ull};
#else
#define OWN "test/fixtures/v1/world.f32.snapshot"
#define OTHER "test/fixtures/v1/world.f64.snapshot"
#define OWN_BYTES 4u
/* The f32 snapshot restored in this build, and the f64 one, rounded. */
static const uint64_t expected[2] = {0x32b28acd47f72370ull, 0xae8f15c67051cdb3ull};
#endif

static uint64_t fnv(uint64_t hash, const void *data, size_t bytes) {
  const uint8_t *p = (const uint8_t *)data;
  for (size_t i = 0; i < bytes; i++) hash = (hash ^ p[i]) * 1099511628211ull;
  return hash;
}

enum { MOST = 512 };

/* Every body's transform, velocity and spin, as test_digest.c hashes a
 * world: what the world is, not how a snapshot spells it, so a later minor
 * that adds a section still lands on the same number. */
static uint64_t world_hash(const F3dWorld *w) {
  static f3d_real t[MOST * F3D_TRANSFORM_FLOATS];
  static F3dBody handles[MOST];
  const uint32_t n = f3d_world_read_transforms(w, t, handles, MOST);
  CHECK(n > 0 && n < MOST);
  uint64_t hash = fnv(1469598103934665603ull, t, (size_t)n * F3D_TRANSFORM_FLOATS * sizeof(f3d_real));
  for (uint32_t i = 0; i < n; i++) {
    f3d_real v[6];
    f3d_body_get_velocity(w, handles[i], v);
    f3d_body_get_angular_velocity(w, handles[i], v + 3);
    hash = fnv(hash, v, sizeof v);
  }
  return hash;
}

static uint8_t *read_file(const char *path, uint32_t *size) {
  FILE *f = fopen(path, "rb");
  if (f == NULL) {
    fprintf(stderr, "%s: cannot open (run from the package root)\n", path);
    return NULL;
  }
  fseek(f, 0, SEEK_END);
  const long length = ftell(f);
  fseek(f, 0, SEEK_SET);
  uint8_t *bytes = (uint8_t *)malloc(length > 0 ? (size_t)length : 1u);
  const size_t got = fread(bytes, 1, (size_t)length, f);
  fclose(f);
  *size = (uint32_t)got;
  return bytes;
}

static uint32_t u32_at(const uint8_t *p) {
  return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

#ifdef F3D_MINT_FIXTURE
static void mint(void) {
  F3dWorld *w = full_world();
  const uint32_t size = f3d_world_snapshot_size(w);
  uint8_t *bytes = (uint8_t *)malloc(size);
  CHECK(f3d_world_snapshot_write(w, bytes, size) == size);
  FILE *f = fopen(OWN, "wb");
  CHECK(f != NULL);
  if (f != NULL) {
    CHECK(fwrite(bytes, 1, size, f) == size);
    fclose(f);
  }
  printf("minted %s, %u bytes\n", OWN, size);
  free(bytes);
  f3d_world_destroy(w);
}
#endif

/* [path] restored into a fresh world and stepped two seconds: its digest. */
static uint64_t restored_and_stepped(const char *path, uint32_t real_bytes) {
  uint32_t size = 0;
  uint8_t *bytes = read_file(path, &size);
  CHECK(bytes != NULL);
  if (bytes == NULL) return 0;
  /* The header as 1.0 wrote it: the magic, major 1, the writer's reals. */
  CHECK(size > 20);
  CHECK(u32_at(bytes) == 0x53443346u);
  CHECK(u32_at(bytes + 4) >> 16 == 1u);
  CHECK(u32_at(bytes + 12) == real_bytes);
  F3dWorld *w = f3d_world_create();
  CHECK(f3d_world_restore(w, bytes, size) == 1);
  free(bytes);
  for (int step = 0; step < 120; step++) f3d_world_step(w, F3D_R(1.0 / 60.0));
  const uint64_t hash = world_hash(w);
  f3d_world_destroy(w);
  return hash;
}

int main(void) {
#ifdef F3D_MINT_FIXTURE
  mint();
#endif
  const uint64_t own = restored_and_stepped(OWN, OWN_BYTES);
  const uint64_t other = restored_and_stepped(OTHER, OWN_BYTES == 4u ? 8u : 4u);
  printf("fixture digests %016llx %016llx\n", (unsigned long long)own, (unsigned long long)other);
  CHECK(own == expected[0]);
  CHECK(other == expected[1]);
  return finish();
}
