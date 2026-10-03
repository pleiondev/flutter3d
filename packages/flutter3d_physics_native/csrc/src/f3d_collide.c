/*
 * The collision stage — P9, phase 2: which pairs are near (a sort and
 * sweep along x, until phase 4's tree), where they touch (f3d_narrow.c),
 * what began and ended touching, and the islands that sleep and wake as
 * one.
 *
 * Every order here is fixed by slot numbers, never by where something
 * happens to sit in memory, so the same world steps to the same contacts,
 * the same events and the same sleep on every platform.
 */
#include "f3d_internal.h"

F3dPlaced f3d_placed_of(const F3dSlot *s) {
  F3dPlaced p;
  p.kind = s->shape;
  p.size = s->size;
  p.at = s->position;
  p.axes = f3d_mat_of(s->orientation);
  return p;
}

int f3d_world_set_contact_margin(F3dWorld *world, f3d_real margin) {
  if (!(f3d_finite(margin) && margin >= F3D_R(0.0))) return 0;
  world->s.contact_margin = margin;
  return 1;
}

int f3d_body_set_collision_filter(F3dWorld *world, F3dBody body,
                                  uint32_t layer, uint32_t mask) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL) return 0;
  s->layer = layer;
  s->mask = mask;
  f3d_wake(world, s);
  return 1;
}

uint32_t f3d_world_contact_count(const F3dWorld *world) {
  uint32_t points = 0;
  for (uint32_t i = 0; i < world->s.manifold_count; i++) {
    points += world->manifolds[i].count;
  }
  return points;
}

uint32_t f3d_world_read_contacts(const F3dWorld *world, f3d_real *contacts,
                                 F3dBody *pairs, uint32_t capacity) {
  uint32_t written = 0;
  for (uint32_t i = 0; i < world->s.manifold_count; i++) {
    const F3dManifold *m = &world->manifolds[i];
    for (uint32_t k = 0; k < m->count && written < capacity; k++) {
      f3d_real *c = contacts + (size_t)written * F3D_CONTACT_FLOATS;
      c[0] = m->normal.x;
      c[1] = m->normal.y;
      c[2] = m->normal.z;
      c[3] = m->points[k].point.x;
      c[4] = m->points[k].point.y;
      c[5] = m->points[k].point.z;
      c[6] = m->points[k].depth;
      if (pairs != NULL) {
        pairs[written * 2u] = m->a;
        pairs[written * 2u + 1u] = m->b;
      }
      written++;
    }
  }
  return written;
}

/* ------------------------------------------------------------- scratch */

/* [bytes] of the world's scratch, grown when it is not enough; null when
 * it cannot grow. */
void *f3d_scratch(F3dWorld *world, size_t bytes) {
  if (bytes <= world->scratch_bytes) return world->scratch;
  size_t grown = world->scratch_bytes == 0 ? 4096u : world->scratch_bytes;
  while (grown < bytes) grown *= 2u;
  void *block = f3d_realloc(world->scratch, grown);
  if (block == NULL) return NULL;
  world->scratch = block;
  world->scratch_bytes = grown;
  return block;
}

/* Room for [count] manifolds in the next step's array. */
static int reserve_next(F3dWorld *world, uint32_t count) {
  if (count <= world->next_capacity) return 1;
  uint32_t grown = world->next_capacity == 0 ? 64u : world->next_capacity;
  while (grown < count) {
    if (grown > UINT32_MAX / 2u) return 0;
    grown *= 2u;
  }
  F3dManifold *block = (F3dManifold *)f3d_realloc(
      world->next_manifolds, (size_t)grown * sizeof(F3dManifold));
  if (block == NULL) return 0;
  world->next_manifolds = block;
  world->next_capacity = grown;
  return 1;
}

/* ------------------------------------------------------------- sorting */

/* A stable merge sort of 64-bit keys carrying a 32-bit value: written out
 * here, because the WebAssembly build has no qsort, and because qsort
 * promises no order for equal keys and this needs one. */
typedef struct Keyed {
  uint64_t key;
  uint32_t value;
  uint32_t reserved;
} Keyed;

static void sort_keyed(Keyed *items, Keyed *spare, uint32_t count) {
  for (uint32_t width = 1; width < count; width *= 2u) {
    for (uint32_t lo = 0; lo < count; lo += 2u * width) {
      const uint32_t mid = lo + width < count ? lo + width : count;
      const uint32_t hi = lo + 2u * width < count ? lo + 2u * width : count;
      uint32_t i = lo, j = mid, k = lo;
      while (i < mid && j < hi) {
        spare[k++] = items[j].key < items[i].key ? items[j++] : items[i++];
      }
      while (i < mid) spare[k++] = items[i++];
      while (j < hi) spare[k++] = items[j++];
    }
    for (uint32_t k = 0; k < count; k++) items[k] = spare[k];
    if (width > UINT32_MAX / 2u) break;
  }
}

/* A real as a key that sorts as the real does: the sign bit flipped for a
 * positive number, every bit for a negative one. */
static uint32_t ordered_bits(f3d_real x) {
  const float f = (float)x;
  uint32_t bits;
  f3d_copy(&bits, &f, sizeof bits);
  return (bits & 0x80000000u) ? ~bits : bits | 0x80000000u;
}

/* -------------------------------------------------------------- bounds */

typedef struct Bounds {
  F3dVec3 lo, hi;
} Bounds;

static Bounds bounds_of(const F3dSlot *s, f3d_real margin) {
  const F3dMat3 m = f3d_mat_of(s->orientation);
  F3dVec3 reach;
  switch (s->shape) {
    case F3D_SHAPE_SPHERE:
      reach = f3d_v3(s->size.x, s->size.x, s->size.x);
      break;
    case F3D_SHAPE_CAPSULE: {
      const F3dVec3 axis = m.c[1];
      reach = f3d_v3(f3d_abs(axis.x) * s->size.y + s->size.x,
                     f3d_abs(axis.y) * s->size.y + s->size.x,
                     f3d_abs(axis.z) * s->size.y + s->size.x);
      break;
    }
    default: {
      const f3d_real h[3] = {s->size.x, s->size.y, s->size.z};
      reach = f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
      for (int k = 0; k < 3; k++) {
        reach.x += f3d_abs(m.c[k].x) * h[k];
        reach.y += f3d_abs(m.c[k].y) * h[k];
        reach.z += f3d_abs(m.c[k].z) * h[k];
      }
      break;
    }
  }
  /* Half the margin on each side: two bounds that meet are a margin
   * apart. */
  const f3d_real half = F3D_R(0.5) * margin;
  reach = f3d_add(reach, f3d_v3(half, half, half));
  Bounds b;
  b.lo = f3d_sub(s->position, reach);
  b.hi = f3d_add(s->position, reach);
  return b;
}

/* --------------------------------------------------------------- stage */

static int active(const F3dSlot *s) {
  return s->type == F3D_BODY_DYNAMIC && !(s->flags & F3D_FLAG_ASLEEP);
}

static uint64_t pair_key(uint32_t a, uint32_t b) {
  return ((uint64_t)a << 32) | b;
}

static uint64_t manifold_key(const F3dManifold *m) {
  return pair_key((uint32_t)(m->a & 0xffffffffu),
                  (uint32_t)(m->b & 0xffffffffu));
}

/* The last step's manifold for this exact pair of bodies, by a binary
 * search of the sorted array; null when there was none. */
static const F3dManifold *previous(const F3dWorld *world, F3dBody a,
                                   F3dBody b) {
  const uint64_t key = pair_key((uint32_t)(a & 0xffffffffu),
                                (uint32_t)(b & 0xffffffffu));
  uint32_t lo = 0, hi = world->s.manifold_count;
  while (lo < hi) {
    const uint32_t mid = lo + (hi - lo) / 2u;
    const uint64_t k = manifold_key(&world->manifolds[mid]);
    if (k < key) {
      lo = mid + 1u;
    } else {
      hi = mid;
    }
  }
  if (lo == world->s.manifold_count) return NULL;
  const F3dManifold *m = &world->manifolds[lo];
  return m->a == a && m->b == b ? m : NULL;
}

static uint32_t find(uint32_t *parent, uint32_t i) {
  while (parent[i] != i) {
    parent[i] = parent[parent[i]];
    i = parent[i];
  }
  return i;
}

/* Joins two islands under the lower root, so the roots do not depend on
 * the order the joins came in. */
static void join(uint32_t *parent, uint32_t a, uint32_t b) {
  const uint32_t ra = find(parent, a), rb = find(parent, b);
  if (ra < rb) {
    parent[rb] = ra;
  } else if (rb < ra) {
    parent[ra] = rb;
  }
}

static void sleep_body(F3dWorld *world, F3dSlot *s) {
  s->flags |= F3D_FLAG_ASLEEP;
  s->still = F3D_R(0.0);
  s->velocity = f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
  s->spin = f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
  f3d_push_event(world, f3d_handle_of(world, s), F3D_EVENT_SLEPT);
}

/* Islands: dynamic bodies joined by their contacts. One sleeps when every
 * body in it has been still for the sleep time, and wakes when any body in
 * it moves: a stack goes to sleep as a stack, and a crate knocked off the
 * top wakes the crate it was resting on. Fixed bodies join no island, or
 * the floor would make one island of the level. */
static void islands(F3dWorld *world, uint32_t *parent) {
  const uint32_t used = world->s.used;
  for (uint32_t i = 0; i < used; i++) parent[i] = i;
  for (uint32_t i = 0; i < world->s.manifold_count; i++) {
    const F3dManifold *m = &world->manifolds[i];
    const uint32_t a = (uint32_t)(m->a & 0xffffffffu);
    const uint32_t b = (uint32_t)(m->b & 0xffffffffu);
    if (world->slots[a].type == F3D_BODY_DYNAMIC &&
        world->slots[b].type == F3D_BODY_DYNAMIC) {
      join(parent, a, b);
    }
  }
  if (!(world->s.sleep_time > F3D_R(0.0))) return;
  /* Per root: bit 0, a body awake and moving; bit 1, a body asleep; bit 2,
   * a body awake. Kept in the slots' spare high bits of a second pass's
   * array: parent[] itself, once each body knows its root. */
  uint32_t *state = parent + used;
  for (uint32_t i = 0; i < used; i++) state[i] = 0;
  for (uint32_t i = 0; i < used; i++) {
    const F3dSlot *s = &world->slots[i];
    if (!s->live || s->type != F3D_BODY_DYNAMIC) continue;
    const uint32_t root = find(parent, i);
    if (s->flags & F3D_FLAG_ASLEEP) {
      state[root] |= 2u;
    } else {
      state[root] |= 4u;
      if (s->still < world->s.sleep_time) state[root] |= 1u;
    }
  }
  for (uint32_t i = 0; i < used; i++) {
    F3dSlot *s = &world->slots[i];
    if (!s->live || s->type != F3D_BODY_DYNAMIC) continue;
    const uint32_t st = state[find(parent, i)];
    if ((st & 1u) && (s->flags & F3D_FLAG_ASLEEP)) {
      f3d_wake(world, s);
    } else if (!(st & 1u) && (st & 4u) && !(s->flags & F3D_FLAG_ASLEEP)) {
      sleep_body(world, s);
    }
  }
}

void f3d_step_collide(F3dWorld *world) {
  const uint32_t used = world->s.used;
  const f3d_real margin = world->s.contact_margin;
  /* The scratch, laid out once: bounds per slot, the sweep's order and its
   * spare, the pairs and their spare, and the islands' two arrays. The
   * pairs are bounded by what the sweep finds, so they go last and grow. */
  const size_t bounds_bytes = (size_t)used * sizeof(Bounds);
  const size_t order_bytes = (size_t)used * sizeof(Keyed) * 2u;
  const size_t island_bytes = (size_t)used * sizeof(uint32_t) * 2u;
  size_t fixed = bounds_bytes + order_bytes + island_bytes;
  fixed = (fixed + 15u) & ~(size_t)15u;
  uint8_t *base = (uint8_t *)f3d_scratch(world, fixed + 64u * sizeof(Keyed) * 2u);
  if (base == NULL) return;
  Bounds *bounds = (Bounds *)base;
  Keyed *order = (Keyed *)(base + bounds_bytes);
  Keyed *order_spare = order + used;
  uint32_t candidates = 0;
  for (uint32_t i = 0; i < used; i++) {
    const F3dSlot *s = &world->slots[i];
    if (!s->live || s->shape == F3D_SHAPE_POINT) continue;
    bounds[i] = bounds_of(s, margin);
    order[candidates].key =
        ((uint64_t)ordered_bits(bounds[i].lo.x) << 32) | i;
    order[candidates].value = i;
    candidates++;
  }
  sort_keyed(order, order_spare, candidates);
  /* The sweep: each body against those whose bounds start before its own
   * end along x. */
  uint32_t pair_count = 0, pair_capacity = 64u;
  for (uint32_t i = 0; i < candidates; i++) {
    const uint32_t a = order[i].value;
    const F3dSlot *sa = &world->slots[a];
    for (uint32_t j = i + 1u; j < candidates; j++) {
      const uint32_t b = order[j].value;
      if (bounds[b].lo.x > bounds[a].hi.x) break;
      if (bounds[b].lo.y > bounds[a].hi.y || bounds[a].lo.y > bounds[b].hi.y ||
          bounds[b].lo.z > bounds[a].hi.z || bounds[a].lo.z > bounds[b].hi.z) {
        continue;
      }
      const F3dSlot *sb = &world->slots[b];
      if (sa->type == F3D_BODY_FIXED && sb->type == F3D_BODY_FIXED) continue;
      if (!(sa->layer & sb->mask) || !(sb->layer & sa->mask)) continue;
      if (pair_count == pair_capacity) {
        pair_capacity *= 2u;
        base = (uint8_t *)f3d_scratch(world,
                                  fixed + (size_t)pair_capacity * sizeof(Keyed) * 2u);
        if (base == NULL) return;
        bounds = (Bounds *)base;
        order = (Keyed *)(base + bounds_bytes);
      }
      Keyed *pairs = (Keyed *)(base + fixed);
      pairs[pair_count].key = a < b ? pair_key(a, b) : pair_key(b, a);
      pairs[pair_count].value = 0;
      pair_count++;
    }
  }
  Keyed *pairs = (Keyed *)(base + fixed);
  sort_keyed(pairs, pairs + pair_capacity, pair_count);
  if (!reserve_next(world, pair_count)) return;
  /* The narrow phase, pair by pair in key order. Two bodies that are both
   * asleep or fixed keep last step's manifold: nothing between them has
   * moved, and dropping it would end a contact nobody broke. */
  uint32_t found = 0;
  for (uint32_t i = 0; i < pair_count; i++) {
    const uint32_t a = (uint32_t)(pairs[i].key >> 32);
    const uint32_t b = (uint32_t)(pairs[i].key & 0xffffffffu);
    const F3dSlot *sa = &world->slots[a];
    const F3dSlot *sb = &world->slots[b];
    const F3dBody ha = f3d_handle_of(world, sa), hb = f3d_handle_of(world, sb);
    F3dManifold *m = &world->next_manifolds[found];
    if (!active(sa) && !active(sb)) {
      const F3dManifold *kept = previous(world, ha, hb);
      if (kept != NULL) {
        /* By bytes: the padding is part of what a snapshot compares. */
        f3d_copy(m, kept, sizeof *m);
        found++;
      }
      continue;
    }
    f3d_zero(m, sizeof *m);
    const F3dPlaced pa = f3d_placed_of(sa), pb = f3d_placed_of(sb);
    if (f3d_collide(&pa, &pb, margin, m) == 0) continue;
    m->a = ha;
    m->b = hb;
    /* Warm start: a point made by the same features as one last step
     * starts from what that one pushed with. */
    const F3dManifold *old = previous(world, ha, hb);
    if (old != NULL) {
      for (uint32_t k = 0; k < m->count; k++) {
        for (uint32_t o = 0; o < old->count; o++) {
          if (old->points[o].id != m->points[k].id) continue;
          m->points[k].normal_impulse = old->points[o].normal_impulse;
          m->points[k].tangent_impulse[0] = old->points[o].tangent_impulse[0];
          m->points[k].tangent_impulse[1] = old->points[o].tangent_impulse[1];
          break;
        }
      }
    }
    found++;
  }
  /* What began and ended touching: the two sorted arrays side by side. */
  uint32_t i = 0, j = 0;
  const uint32_t before = world->s.manifold_count;
  while (i < before || j < found) {
    const F3dManifold *old = i < before ? &world->manifolds[i] : NULL;
    const F3dManifold *now = j < found ? &world->next_manifolds[j] : NULL;
    const uint64_t ko = old ? manifold_key(old) : UINT64_MAX;
    const uint64_t kn = now ? manifold_key(now) : UINT64_MAX;
    if (old && now && ko == kn && old->a == now->a && old->b == now->b) {
      if (old->touching && !now->touching) {
        f3d_push_pair_event(world, now->a, now->b, F3D_EVENT_CONTACT_ENDED);
      } else if (!old->touching && now->touching) {
        f3d_push_pair_event(world, now->a, now->b, F3D_EVENT_CONTACT_BEGAN);
      }
      i++;
      j++;
    } else if (now == NULL || (old && ko <= kn)) {
      if (old->touching) {
        f3d_push_pair_event(world, old->a, old->b, F3D_EVENT_CONTACT_ENDED);
      }
      i++;
    } else {
      if (now->touching) {
        f3d_push_pair_event(world, now->a, now->b, F3D_EVENT_CONTACT_BEGAN);
      }
      j++;
    }
  }
  /* The new manifolds become the world's, and the old array is the next
   * step's room. */
  F3dManifold *swap = world->manifolds;
  const uint32_t swap_capacity = world->manifold_capacity;
  world->manifolds = world->next_manifolds;
  world->manifold_capacity = world->next_capacity;
  world->next_manifolds = swap;
  world->next_capacity = swap_capacity;
  world->s.manifold_count = found;
  /* A body woken by a contact is woken here, after the contacts are set:
   * an awake, moving body touching a sleeping one wakes its whole island. */
  islands(world, (uint32_t *)(base + bounds_bytes + order_bytes));
}
