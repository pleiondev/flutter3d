/*
 * The world's whole state in one buffer, and back — P9.
 *
 * A header, the world's plain state, the arena's slots up to its high-water
 * mark, the wind grid and the events waiting. Slots are copied whole: they
 * are zeroed when taken, so their padding is the same bytes every time, and
 * a snapshot of the same world is the same bytes. The header says which
 * build wrote it — the real's size and the layouts' — so a snapshot is
 * refused by a build that would read it wrongly, rather than misread.
 */
#include "f3d_internal.h"

#define F3D_SNAPSHOT_MAGIC 0x53443346u /* "F3DS", little-endian. */
#define F3D_SNAPSHOT_VERSION 3u

typedef struct F3dSnapshotHeader {
  uint32_t magic;
  uint32_t version;
  uint32_t real_bytes;
  uint32_t state_bytes;
  uint32_t slot_bytes;
  uint32_t event_bytes;
  uint32_t manifold_bytes;
  uint32_t reserved;
} F3dSnapshotHeader;

static uint64_t grid_reals(const F3dWorldState *s) {
  return (uint64_t)s->grid_n[0] * s->grid_n[1] * s->grid_n[2] * 3u;
}

static uint64_t size_of(const F3dWorldState *s) {
  return (uint64_t)sizeof(F3dSnapshotHeader) + sizeof(F3dWorldState) +
         (uint64_t)s->used * sizeof(F3dSlot) +
         grid_reals(s) * sizeof(f3d_real) +
         (uint64_t)s->events_count * sizeof(F3dEventRecord) +
         (uint64_t)s->manifold_count * sizeof(F3dManifold);
}

uint32_t f3d_world_snapshot_size(const F3dWorld *world) {
  const uint64_t size = size_of(&world->s);
  return size > UINT32_MAX ? 0u : (uint32_t)size;
}

uint32_t f3d_world_snapshot_write(const F3dWorld *world, uint8_t *buffer,
                                  uint32_t size) {
  const uint32_t needed = f3d_world_snapshot_size(world);
  if (needed == 0 || size < needed || buffer == NULL) return 0;
  F3dSnapshotHeader header;
  f3d_zero(&header, sizeof header);
  header.magic = F3D_SNAPSHOT_MAGIC;
  header.version = F3D_SNAPSHOT_VERSION;
  header.real_bytes = (uint32_t)sizeof(f3d_real);
  header.state_bytes = (uint32_t)sizeof(F3dWorldState);
  header.slot_bytes = (uint32_t)sizeof(F3dSlot);
  header.event_bytes = (uint32_t)sizeof(F3dEventRecord);
  header.manifold_bytes = (uint32_t)sizeof(F3dManifold);
  uint8_t *at = buffer;
  f3d_copy(at, &header, sizeof header);
  at += sizeof header;
  /* The events go out oldest first from nought, so the same queue is the
   * same bytes wherever its ring happened to start. */
  /* Copied by bytes, not assigned: an assignment need not carry the
   * padding, and the padding is part of what makes two snapshots of one
   * world the same bytes. */
  F3dWorldState state;
  f3d_copy(&state, &world->s, sizeof state);
  state.events_head = 0;
  f3d_copy(at, &state, sizeof state);
  at += sizeof state;
  if (world->s.used > 0) {
    f3d_copy(at, world->slots, (size_t)world->s.used * sizeof(F3dSlot));
    at += (size_t)world->s.used * sizeof(F3dSlot);
  }
  const uint64_t reals = grid_reals(&world->s);
  if (reals > 0) {
    f3d_copy(at, world->grid, (size_t)reals * sizeof(f3d_real));
    at += (size_t)reals * sizeof(f3d_real);
  }
  for (uint32_t i = 0; i < world->s.events_count; i++) {
    const uint32_t from = (world->s.events_head + i) % F3D_EVENT_CAPACITY;
    f3d_copy(at, &world->events[from], sizeof(F3dEventRecord));
    at += sizeof(F3dEventRecord);
  }
  /* The contacts: what the next step compares against to say what began
   * and ended, and what two sleeping bodies keep. */
  if (world->s.manifold_count > 0) {
    f3d_copy(at, world->manifolds,
             (size_t)world->s.manifold_count * sizeof(F3dManifold));
  }
  return needed;
}

int f3d_world_restore(F3dWorld *world, const uint8_t *buffer, uint32_t size) {
  if (buffer == NULL || size < sizeof(F3dSnapshotHeader)) return 0;
  F3dSnapshotHeader header;
  f3d_copy(&header, buffer, sizeof header);
  if (header.magic != F3D_SNAPSHOT_MAGIC ||
      header.version != F3D_SNAPSHOT_VERSION ||
      header.real_bytes != sizeof(f3d_real) ||
      header.state_bytes != sizeof(F3dWorldState) ||
      header.slot_bytes != sizeof(F3dSlot) ||
      header.event_bytes != sizeof(F3dEventRecord) ||
      header.manifold_bytes != sizeof(F3dManifold)) {
    return 0;
  }
  if (size < sizeof header + sizeof(F3dWorldState)) return 0;
  F3dWorldState state;
  f3d_copy(&state, buffer + sizeof header, sizeof state);
  if (size_of(&state) != size) return 0;
  if (state.events_count > F3D_EVENT_CAPACITY || state.live > state.used ||
      state.free_head > state.used || state.events_head != 0) {
    return 0;
  }
  const uint8_t *at = buffer + sizeof header + sizeof state;
  /* Everything allocated before anything is replaced, so a restore that
   * runs out of memory leaves the world as it was. */
  F3dSlot *slots = NULL;
  const uint32_t capacity = state.used;
  if (capacity > 0) {
    slots = (F3dSlot *)f3d_alloc((size_t)capacity * sizeof(F3dSlot));
    if (slots == NULL) return 0;
  }
  const uint64_t reals = grid_reals(&state);
  f3d_real *grid = NULL;
  if (reals > 0) {
    grid = (f3d_real *)f3d_alloc((size_t)reals * sizeof(f3d_real));
    if (grid == NULL) {
      f3d_free(slots);
      return 0;
    }
  }
  F3dEventRecord *events = NULL;
  if (state.events_count > 0) {
    events = (F3dEventRecord *)f3d_alloc((size_t)F3D_EVENT_CAPACITY *
                                         sizeof(F3dEventRecord));
    if (events == NULL) {
      f3d_free(slots);
      f3d_free(grid);
      return 0;
    }
    f3d_zero(events, (size_t)F3D_EVENT_CAPACITY * sizeof(F3dEventRecord));
  }
  if (capacity > 0) {
    f3d_copy(slots, at, (size_t)capacity * sizeof(F3dSlot));
    at += (size_t)capacity * sizeof(F3dSlot);
  }
  if (reals > 0) {
    f3d_copy(grid, at, (size_t)reals * sizeof(f3d_real));
    at += (size_t)reals * sizeof(f3d_real);
  }
  F3dManifold *manifolds = NULL;
  if (state.manifold_count > 0) {
    manifolds = (F3dManifold *)f3d_alloc((size_t)state.manifold_count *
                                         sizeof(F3dManifold));
    if (manifolds == NULL) {
      f3d_free(slots);
      f3d_free(grid);
      f3d_free(events);
      return 0;
    }
  }
  if (events != NULL) {
    f3d_copy(events, at, (size_t)state.events_count * sizeof(F3dEventRecord));
    at += (size_t)state.events_count * sizeof(F3dEventRecord);
  }
  if (manifolds != NULL) {
    f3d_copy(manifolds, at,
             (size_t)state.manifold_count * sizeof(F3dManifold));
  }
  f3d_free(world->slots);
  f3d_free(world->manifolds);
  f3d_free(world->grid);
  f3d_free(world->events);
  f3d_copy(&world->s, &state, sizeof state);
  world->slots = slots;
  world->capacity = capacity;
  world->grid = grid;
  world->events = events;
  world->manifolds = manifolds;
  world->manifold_capacity = state.manifold_count;
  /* The tree is not in a snapshot: built again by the next step. */
  f3d_tree_clear(&world->tree);
  f3d_free(world->proxies);
  world->proxies = NULL;
  world->proxy_capacity = 0;
  return 1;
}
