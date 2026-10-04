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

F3dPlaced f3d_placed_of(const F3dWorld *world, const F3dSlot *s) {
  F3dPlaced p;
  p.kind = s->shape;
  p.size = s->size;
  p.at = s->position;
  p.axes = f3d_mat_of(s->orientation);
  p.rounding = s->rounding;
  p.hull = NULL;
  p.vertices = NULL;
  p.triangles = NULL;
  p.mesh = NULL;
  p.mesh_tree = NULL;
  p.edge_flags = NULL;
  if (s->shape == F3D_SHAPE_MESH && s->hull != 0 &&
      s->hull <= world->s.mesh_count) {
    const F3dMesh *m = &world->meshes[s->hull - 1u];
    p.mesh = m;
    p.vertices = world->mesh_vertices + (size_t)m->first_vertex * 3u;
    p.triangles = world->mesh_triangles + (size_t)m->first_triangle * 3u;
    p.edge_flags = world->mesh_edges + m->first_triangle;
    p.mesh_tree = s->hull <= world->mesh_tree_count
                      ? &world->mesh_trees[s->hull - 1u]
                      : NULL;
  }
  if (s->shape == F3D_SHAPE_HULL && s->hull != 0 &&
      s->hull <= world->s.hull_count) {
    p.hull = &world->hulls[s->hull - 1u];
    p.vertices = world->hull_vertices + (size_t)p.hull->first_vertex * 3u;
    p.triangles = world->hull_triangles + (size_t)p.hull->first_triangle * 3u;
  }
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
  /* A joint joins its bodies' islands as a contact does: a chain sleeps as
   * a chain, and a pull on one end wakes the other. */
  for (uint32_t i = 0; i < world->s.joint_used; i++) {
    const F3dJointSlot *j = &world->joints[i];
    if (!j->live) continue;
    const F3dSlot *sa = f3d_slot_of(world, j->a);
    const F3dSlot *sb = f3d_slot_of(world, j->b);
    if (sa == NULL || sb == NULL) continue;
    if (sa->type == F3D_BODY_DYNAMIC && sb->type == F3D_BODY_DYNAMIC) {
      join(parent, (uint32_t)(sa - world->slots), (uint32_t)(sb - world->slots));
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

/* What a query of the tree gathers: the pairs, in the world's scratch past
 * the islands' arrays, grown as they come. */
typedef struct Gather {
  F3dWorld *world;
  size_t fixed;
  uint32_t self;
  F3dBox box;
  f3d_real dt;
  uint32_t count, capacity;
  int failed;
} Gather;

static Keyed *gathered(const Gather *g) {
  return (Keyed *)((uint8_t *)g->world->scratch + g->fixed);
}

static int add_pair(Gather *g, uint32_t a, uint32_t b) {
  if (g->count == g->capacity) {
    const uint32_t grown = g->capacity * 2u;
    if (f3d_scratch(g->world, g->fixed + (size_t)grown * sizeof(Keyed) * 2u) ==
        NULL) {
      g->failed = 1;
      return 0;
    }
    /* The spare half moves up with the capacity; nothing is in it yet. */
    g->capacity = grown;
  }
  gathered(g)[g->count].key = a < b ? pair_key(a, b) : pair_key(b, a);
  gathered(g)[g->count].value = 0;
  g->count++;
  return 1;
}

/* One leaf near the querying body: a pair, unless the other is awake too
 * and comes first — then its own query found this pair already. */
static int near_leaf(void *context, int32_t leaf) {
  Gather *g = (Gather *)context;
  const uint32_t other = g->world->tree.nodes[leaf].slot;
  if (other == g->self) return 1;
  const F3dSlot *so = &g->world->slots[other];
  const F3dSlot *ss = &g->world->slots[g->self];
  if (active(so) && other < g->self) return 1;
  if (!(ss->layer & so->mask) || !(so->layer & ss->mask)) return 1;
  if (f3d_joined(g->world, g->self, other)) return 1;
  if (!f3d_box_overlap(f3d_swept_box(g->world, so,
                                     F3D_R(0.5) * g->world->s.contact_margin,
                                     g->dt),
                       g->box)) {
    return 1;
  }
  return add_pair(g, g->self, other);
}

/* Soft CCD: how far past the margin a pair's contact reaches this step —
 * as far as the two can close in it, by their speeds and spins. The
 * contact's solver lets them close a gap and no more, so a wall a body
 * would cross in one step is a wall it stops at. Held to ten metres, past
 * which a contact would stop bodies that were only going to pass close. */
static f3d_real speculative(const F3dWorld *world, const F3dSlot *a,
                            const F3dSlot *b, f3d_real dt) {
  if (!world->s.speculative) return F3D_R(0.0);
  f3d_real reach = F3D_R(0.0);
  const F3dSlot *both[2] = {a, b};
  for (int k = 0; k < 2; k++) {
    const F3dSlot *s = both[k];
    if (s->type != F3D_BODY_DYNAMIC || (s->flags & F3D_FLAG_ASLEEP)) continue;
    reach += f3d_sqrt(f3d_dot(s->velocity, s->velocity)) * dt +
             f3d_sqrt(f3d_dot(s->spin, s->spin)) * dt * f3d_reach_of(world, s);
  }
  return f3d_min(reach, F3D_R(10.0));
}

int f3d_world_set_speculative(F3dWorld *world, int enabled) {
  world->s.speculative = enabled ? 1u : 0u;
  return 1;
}

int f3d_body_set_bullet(F3dWorld *world, F3dBody body, int bullet) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL) return 0;
  if (bullet) {
    s->flags |= F3D_FLAG_BULLET;
  } else {
    s->flags &= (uint8_t)~F3D_FLAG_BULLET;
  }
  return 1;
}

static int moved(const F3dSlot *s) {
  return s != NULL && (s->flags & F3D_FLAG_MOVED) != 0;
}

void f3d_step_collide(F3dWorld *world, f3d_real dt) {
  const uint32_t used = world->s.used;
  const f3d_real margin = world->s.contact_margin;
  /* A body placed, turned or reshaped by hand wakes what slept against it:
   * the contact they kept is no longer where they are. */
  for (uint32_t i = 0; i < world->s.manifold_count; i++) {
    const F3dManifold *m = &world->manifolds[i];
    F3dSlot *sa = f3d_slot_of(world, m->a), *sb = f3d_slot_of(world, m->b);
    if (!moved(sa) && !moved(sb)) continue;
    if (sa != NULL) f3d_wake(world, sa);
    if (sb != NULL) f3d_wake(world, sb);
  }
  f3d_update_proxies(world, dt);
  f3d_build_mesh_trees(world);
  /* The scratch: the islands' two arrays, then the pairs and their spare,
   * which grow as the queries find them. */
  const size_t fixed =
      ((size_t)used * sizeof(uint32_t) * 2u + 15u) & ~(size_t)15u;
  if (f3d_scratch(world, fixed + 64u * sizeof(Keyed) * 2u) == NULL) return;
  Gather g;
  g.world = world;
  g.fixed = fixed;
  g.count = 0;
  g.capacity = 64u;
  g.failed = 0;
  g.dt = dt;
  /* Each awake body asks the tree what is near it. Two bodies neither of
   * which can move are not asked about: they keep last step's contact. */
  for (uint32_t i = 0; i < used && !g.failed; i++) {
    const F3dSlot *s = &world->slots[i];
    if (!active(s) || world->proxies[i] == -1) continue;
    g.self = i;
    g.box = f3d_swept_box(world, s, F3D_R(0.5) * margin, dt);
    f3d_tree_query(&world->tree, g.box, near_leaf, &g);
  }
  for (uint32_t i = 0; i < world->s.manifold_count && !g.failed; i++) {
    const F3dManifold *m = &world->manifolds[i];
    const F3dSlot *sa = f3d_slot_of(world, m->a);
    const F3dSlot *sb = f3d_slot_of(world, m->b);
    if (sa == NULL || sb == NULL || active(sa) || active(sb)) continue;
    if (sa->shape == F3D_SHAPE_POINT || sb->shape == F3D_SHAPE_POINT) continue;
    add_pair(&g, (uint32_t)(m->a & 0xffffffffu), (uint32_t)(m->b & 0xffffffffu));
  }
  for (uint32_t i = 0; i < used; i++) {
    world->slots[i].flags &= (uint8_t)~F3D_FLAG_MOVED;
  }
  if (g.failed) return;
  Keyed *pairs = gathered(&g);
  sort_keyed(pairs, pairs + g.capacity, g.count);
  uint32_t pair_count = 0;
  for (uint32_t i = 0; i < g.count; i++) {
    if (pair_count == 0 || pairs[pair_count - 1].key != pairs[i].key) {
      pairs[pair_count++] = pairs[i];
    }
  }
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
    const F3dPlaced pa = f3d_placed_of(world, sa), pb = f3d_placed_of(world, sb);
    if (f3d_collide(&pa, &pb, margin + speculative(world, sa, sb, dt), m) == 0) {
      continue;
    }
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
  islands(world, (uint32_t *)world->scratch);
}
