/*
 * The world and its bodies — P9: an arena of bodies named by generational
 * handles, the world's air, wind and origin, the bodies' accessors and the
 * event queue. The step is in f3d_motion.c and f3d_heat.c, snapshots in
 * f3d_snapshot.c.
 */
#include "f3d_internal.h"

/* Room for this many bodies before the arena first grows. */
#define F3D_INITIAL_CAPACITY 64u

uint32_t f3d_abi_version(void) { return F3D_ABI_VERSION; }

uint32_t f3d_real_bytes(void) { return (uint32_t)sizeof(f3d_real); }

void *f3d_buffer_alloc(uint32_t bytes) { return f3d_alloc(bytes); }

void f3d_buffer_free(void *buffer) { f3d_free(buffer); }

F3dWorld *f3d_world_create(void) {
  F3dWorld *world = (F3dWorld *)f3d_alloc(sizeof(F3dWorld));
  if (world == NULL) return NULL;
  f3d_zero(world, sizeof(F3dWorld));
  world->s.gravity.y = F3D_R(-9.81);
  world->s.air_temperature = F3D_R(293.15);
  world->s.air_density = F3D_R(1.204);
  world->s.sleep_speed = F3D_R(0.05);
  world->s.sleep_time = F3D_R(0.5);
  world->s.contact_margin = F3D_R(0.02);
  world->s.substeps = 4u;
  world->s.speculative = 1u;
  world->tree.root = -1;
  world->tree.free_list = -1;
  return world;
}

void f3d_world_destroy(F3dWorld *world) {
  if (world == NULL) return;
  f3d_free(world->slots);
  f3d_free(world->grid);
  f3d_free(world->events);
  f3d_free(world->manifolds);
  f3d_free(world->next_manifolds);
  f3d_free(world->scratch);
  f3d_tree_clear(&world->tree);
  f3d_free(world->proxies);
  f3d_free(world->hulls);
  f3d_free(world->hull_vertices);
  f3d_free(world->hull_triangles);
  f3d_free(world->compounds);
  f3d_free(world->compound_parts);
  f3d_free(world->meshes);
  f3d_free(world->mesh_vertices);
  f3d_free(world->mesh_triangles);
  f3d_free(world->mesh_edges);
  f3d_clear_mesh_trees(world);
  f3d_free(world->joints);
  f3d_free(world->joined);
  f3d_free(world->bullet_at);
  f3d_free(world->bullet_turn);
  f3d_free(world->pairs);
  f3d_free(world->moved);
  f3d_free(world->swept);
  f3d_pool_destroy(world->pool);
  for (uint32_t i = 0; i < F3D_MAX_THREADS; i++) f3d_free(world->lanes[i].items);
  f3d_free(world);
}

int f3d_world_set_threads(F3dWorld *world, uint32_t threads) {
  if (threads == 0 || threads > F3D_MAX_THREADS) return 0;
  if (threads == f3d_pool_size(world->pool)) return 1;
  F3dPool *pool = threads > 1u ? f3d_pool_create(threads) : NULL;
  if (threads > 1u && pool == NULL) return 0;
  f3d_pool_destroy(world->pool);
  world->pool = pool;
  return 1;
}

uint32_t f3d_world_threads(const F3dWorld *world) { return f3d_pool_size(world->pool); }

int f3d_world_set_fast(F3dWorld *world, int fast) {
  world->s.fast = fast ? 1u : 0u;
  return 1;
}

int f3d_world_fast(const F3dWorld *world) { return world->s.fast != 0; }

void f3d_world_set_gravity(F3dWorld *world, f3d_real x, f3d_real y,
                           f3d_real z) {
  world->s.gravity.x = x;
  world->s.gravity.y = y;
  world->s.gravity.z = z;
}

void f3d_world_get_gravity(const F3dWorld *world, f3d_real *out) {
  out[0] = world->s.gravity.x;
  out[1] = world->s.gravity.y;
  out[2] = world->s.gravity.z;
}

int f3d_world_set_air(F3dWorld *world, f3d_real temperature,
                      f3d_real density) {
  if (!(f3d_finite(temperature) && temperature > F3D_R(0.0))) return 0;
  if (!(f3d_finite(density) && density > F3D_R(0.0))) return 0;
  world->s.air_temperature = temperature;
  world->s.air_density = density;
  return 1;
}

void f3d_world_get_air(const F3dWorld *world, f3d_real *out) {
  out[0] = world->s.air_temperature;
  out[1] = world->s.air_density;
}


/* A change of wind wakes every body that feels it: asleep, it would hang
 * in the new wind as if the old one still blew. */
static void wake_in_wind(F3dWorld *world) {
  for (uint32_t i = 0; i < world->s.used; i++) {
    F3dSlot *s = &world->slots[i];
    if (s->live && s->surface > F3D_R(0.0) && s->shape_drag > F3D_R(0.0)) {
      f3d_wake(world, s);
    }
  }
}

void f3d_world_set_wind(F3dWorld *world, f3d_real x, f3d_real y, f3d_real z) {
  world->s.wind.x = x;
  world->s.wind.y = y;
  world->s.wind.z = z;
  wake_in_wind(world);
}

int f3d_world_set_wind_grid(F3dWorld *world, f3d_real ox, f3d_real oy,
                            f3d_real oz, f3d_real cell, uint32_t nx,
                            uint32_t ny, uint32_t nz,
                            const f3d_real *velocities) {
  if (velocities == NULL) {
    f3d_free(world->grid);
    world->grid = NULL;
    world->s.grid_n[0] = world->s.grid_n[1] = world->s.grid_n[2] = 0;
    wake_in_wind(world);
    return 1;
  }
  if (nx == 0 || ny == 0 || nz == 0) return 0;
  if (!(f3d_finite(cell) && cell > F3D_R(0.0))) return 0;
  if (!f3d_finite(ox) || !f3d_finite(oy) || !f3d_finite(oz)) return 0;
  const uint64_t count = (uint64_t)nx * ny * nz * 3u;
  if (count * sizeof(f3d_real) > (uint64_t)UINT32_MAX) return 0;
  f3d_real *grid = (f3d_real *)f3d_alloc((size_t)count * sizeof(f3d_real));
  if (grid == NULL) return 0;
  f3d_copy(grid, velocities, (size_t)count * sizeof(f3d_real));
  f3d_free(world->grid);
  world->grid = grid;
  world->s.grid_origin.x = ox;
  world->s.grid_origin.y = oy;
  world->s.grid_origin.z = oz;
  world->s.grid_cell = cell;
  world->s.grid_n[0] = nx;
  world->s.grid_n[1] = ny;
  world->s.grid_n[2] = nz;
  wake_in_wind(world);
  return 1;
}

/* Where [p] falls along one axis of [n] samples: the lower sample and the
 * share of the way to the next, held at the ends. */
static void grid_axis(f3d_real p, uint32_t n, uint32_t *at, f3d_real *t) {
  if (n == 1 || !(p > F3D_R(0.0))) {
    *at = 0;
    *t = F3D_R(0.0);
    return;
  }
  const f3d_real last = (f3d_real)(n - 1);
  if (p >= last) {
    *at = n - 2;
    *t = F3D_R(1.0);
    return;
  }
  uint32_t i = (uint32_t)p;
  if (i > n - 2) i = n - 2;
  *at = i;
  *t = p - (f3d_real)i;
}

void f3d_world_sample_wind(const F3dWorld *world, f3d_real x, f3d_real y,
                           f3d_real z, f3d_real *out) {
  out[0] = world->s.wind.x;
  out[1] = world->s.wind.y;
  out[2] = world->s.wind.z;
  const uint32_t *n = world->s.grid_n;
  if (world->grid == NULL || n[0] == 0) return;
  const f3d_real inv = F3D_R(1.0) / world->s.grid_cell;
  uint32_t i, j, k;
  f3d_real tx, ty, tz;
  grid_axis((x - world->s.grid_origin.x) * inv, n[0], &i, &tx);
  grid_axis((y - world->s.grid_origin.y) * inv, n[1], &j, &ty);
  grid_axis((z - world->s.grid_origin.z) * inv, n[2], &k, &tz);
  const uint32_t di = n[0] > 1 ? 1u : 0u;
  const uint32_t dj = n[1] > 1 ? 1u : 0u;
  const uint32_t dk = n[2] > 1 ? 1u : 0u;
  for (uint32_t c = 0; c < 3; c++) {
    f3d_real sum = F3D_R(0.0);
    for (uint32_t corner = 0; corner < 8; corner++) {
      const uint32_t ci = i + ((corner & 1u) ? di : 0u);
      const uint32_t cj = j + ((corner & 2u) ? dj : 0u);
      const uint32_t ck = k + ((corner & 4u) ? dk : 0u);
      const f3d_real w = ((corner & 1u) ? tx : F3D_R(1.0) - tx) *
                         ((corner & 2u) ? ty : F3D_R(1.0) - ty) *
                         ((corner & 4u) ? tz : F3D_R(1.0) - tz);
      const size_t at = ((size_t)ck * n[1] + cj) * n[0] + ci;
      sum += w * world->grid[at * 3u + c];
    }
    out[c] += sum;
  }
}

int f3d_world_set_sleep(F3dWorld *world, f3d_real speed, f3d_real time) {
  if (!(f3d_finite(speed) && speed >= F3D_R(0.0))) return 0;
  if (!(f3d_finite(time) && time >= F3D_R(0.0))) return 0;
  world->s.sleep_speed = speed;
  world->s.sleep_time = time;
  return 1;
}

void f3d_world_get_origin(const F3dWorld *world, double *out) {
  out[0] = world->s.origin[0];
  out[1] = world->s.origin[1];
  out[2] = world->s.origin[2];
}

void f3d_world_shift_origin(F3dWorld *world, double dx, double dy, double dz) {
  if (!(dx - dx == 0.0 && dy - dy == 0.0 && dz - dz == 0.0)) return;
  world->s.origin[0] += dx;
  world->s.origin[1] += dy;
  world->s.origin[2] += dz;
  /* Each position moved in doubles and rounded once, so a body far from
   * the old origin lands as near the new one as a real can say. */
  for (uint32_t i = 0; i < world->s.used; i++) {
    F3dSlot *s = &world->slots[i];
    if (!s->live) continue;
    s->position.x = (f3d_real)((double)s->position.x - dx);
    s->position.y = (f3d_real)((double)s->position.y - dy);
    s->position.z = (f3d_real)((double)s->position.z - dz);
  }
  world->s.grid_origin.x = (f3d_real)((double)world->s.grid_origin.x - dx);
  world->s.grid_origin.y = (f3d_real)((double)world->s.grid_origin.y - dy);
  world->s.grid_origin.z = (f3d_real)((double)world->s.grid_origin.z - dz);
}

uint32_t f3d_world_body_count(const F3dWorld *world) { return world->s.live; }

static F3dBody handle_of(uint32_t slot, uint32_t generation) {
  return ((uint64_t)generation << 32) | (uint64_t)slot;
}

F3dBody f3d_handle_of(const F3dWorld *world, const F3dSlot *slot) {
  return handle_of((uint32_t)(slot - world->slots), slot->generation);
}

F3dSlot *f3d_slot_of(const F3dWorld *world, F3dBody body) {
  const uint32_t slot = (uint32_t)(body & 0xffffffffu);
  const uint32_t generation = (uint32_t)(body >> 32);
  if (generation == 0 || slot >= world->s.used) return NULL;
  F3dSlot *s = &world->slots[slot];
  return s->live && s->generation == generation ? s : NULL;
}

void f3d_push_event(F3dWorld *world, F3dBody body, uint32_t kind) {
  f3d_push_pair_event(world, body, 0, kind);
}

void f3d_push_pair_event(F3dWorld *world, F3dBody body, F3dBody other,
                         uint32_t kind) {
  if (world->events == NULL) {
    world->events = (F3dEventRecord *)f3d_alloc(
        (size_t)F3D_EVENT_CAPACITY * sizeof(F3dEventRecord));
    if (world->events == NULL) {
      world->s.events_dropped++;
      return;
    }
    f3d_zero(world->events,
             (size_t)F3D_EVENT_CAPACITY * sizeof(F3dEventRecord));
  }
  if (world->s.events_count == F3D_EVENT_CAPACITY) {
    world->s.events_dropped++;
    return;
  }
  const uint32_t at =
      (world->s.events_head + world->s.events_count) % F3D_EVENT_CAPACITY;
  world->events[at].body = body;
  world->events[at].other = other;
  world->events[at].kind = kind;
  world->s.events_count++;
}

uint32_t f3d_world_read_events(F3dWorld *world, F3dBody *bodies,
                               F3dBody *others, uint32_t *kinds,
                               uint32_t capacity) {
  uint32_t read = 0;
  while (read < capacity && world->s.events_count > 0) {
    const F3dEventRecord *e = &world->events[world->s.events_head];
    bodies[read] = e->body;
    if (others != NULL) others[read] = e->other;
    kinds[read] = e->kind;
    world->s.events_head = (world->s.events_head + 1u) % F3D_EVENT_CAPACITY;
    world->s.events_count--;
    read++;
  }
  return read;
}

uint32_t f3d_world_events_dropped(const F3dWorld *world) {
  return world->s.events_dropped;
}

/* A free slot's index, growing the arena when none is free; or UINT32_MAX
 * when it cannot grow. */
static uint32_t take_slot(F3dWorld *world) {
  if (world->s.free_head != 0) {
    const uint32_t slot = world->s.free_head - 1;
    world->s.free_head = world->slots[slot].next_free;
    return slot;
  }
  if (world->s.used == world->capacity) {
    const uint32_t grown = world->capacity == 0 ? F3D_INITIAL_CAPACITY
                                                : world->capacity * 2u;
    if (grown <= world->capacity) return UINT32_MAX;
    F3dSlot *slots =
        (F3dSlot *)f3d_realloc(world->slots, (size_t)grown * sizeof(F3dSlot));
    if (slots == NULL) return UINT32_MAX;
    f3d_zero(slots + world->capacity,
             (size_t)(grown - world->capacity) * sizeof(F3dSlot));
    world->slots = slots;
    world->capacity = grown;
  }
  return world->s.used++;
}

F3dBody f3d_body_create(F3dWorld *world, F3dBodyType type, f3d_real px,
                        f3d_real py, f3d_real pz, f3d_real mass) {
  if (type != F3D_BODY_DYNAMIC && type != F3D_BODY_FIXED) return 0;
  if (!f3d_finite(px) || !f3d_finite(py) || !f3d_finite(pz)) return 0;
  if (type == F3D_BODY_DYNAMIC && !(f3d_finite(mass) && mass > F3D_R(0.0))) {
    return 0;
  }
  if (!(f3d_finite(mass) && mass >= F3D_R(0.0))) mass = F3D_R(0.0);
  const uint32_t slot = take_slot(world);
  if (slot == UINT32_MAX) return 0;
  F3dSlot *s = &world->slots[slot];
  uint32_t generation = s->generation + 1u;
  if (generation == 0) generation = 1; /* Wrapped: nought is never a handle. */
  f3d_zero(s, sizeof(F3dSlot));
  s->generation = generation;
  s->live = 1;
  s->type = (uint8_t)type;
  s->shape = F3D_SHAPE_POINT;
  s->position.x = px;
  s->position.y = py;
  s->position.z = pz;
  s->orientation.w = F3D_R(1.0);
  s->mass = mass;
  f3d_material_preset(F3D_MATERIAL_INERT, &s->material);
  s->temperature = world->s.air_temperature;
  s->friction = F3D_R(0.6);
  s->layer = 1u;
  s->mask = UINT32_MAX;
  f3d_refresh_mass(world, s);
  world->s.live++;
  return handle_of(slot, generation);
}

int f3d_body_destroy(F3dWorld *world, F3dBody body) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL) return 0;
  f3d_unjoin(world, (uint32_t)(s - world->slots));
  s->live = 0;
  s->next_free = world->s.free_head;
  world->s.free_head = (uint32_t)(s - world->slots) + 1u;
  world->s.live--;
  return 1;
}

int f3d_body_is_valid(const F3dWorld *world, F3dBody body) {
  return f3d_slot_of(world, body) != NULL;
}

static int finite3(f3d_real x, f3d_real y, f3d_real z) {
  return f3d_finite(x) && f3d_finite(y) && f3d_finite(z);
}

static void set3(F3dVec3 *v, f3d_real x, f3d_real y, f3d_real z) {
  v->x = x;
  v->y = y;
  v->z = z;
}

static void get3(const F3dVec3 *v, f3d_real *out) {
  out[0] = v->x;
  out[1] = v->y;
  out[2] = v->z;
}

void f3d_wake(F3dWorld *world, F3dSlot *s) {
  s->still = F3D_R(0.0);
  if (!(s->flags & F3D_FLAG_ASLEEP)) return;
  s->flags &= (uint8_t)~F3D_FLAG_ASLEEP;
  f3d_push_event(world, f3d_handle_of(world, s), F3D_EVENT_WOKE);
}


int f3d_body_set_velocity(F3dWorld *world, F3dBody body, f3d_real x,
                          f3d_real y, f3d_real z) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL || !finite3(x, y, z)) return 0;
  set3(&s->velocity, x, y, z);
  f3d_wake(world, s);
  return 1;
}

int f3d_body_get_velocity(const F3dWorld *world, F3dBody body, f3d_real *out) {
  const F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL) return 0;
  get3(&s->velocity, out);
  return 1;
}

int f3d_body_set_position(F3dWorld *world, F3dBody body, f3d_real x,
                          f3d_real y, f3d_real z) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL || !finite3(x, y, z)) return 0;
  set3(&s->position, x, y, z);
  s->flags |= F3D_FLAG_MOVED;
  f3d_wake(world, s);
  return 1;
}

int f3d_body_get_position(const F3dWorld *world, F3dBody body, f3d_real *out) {
  const F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL) return 0;
  get3(&s->position, out);
  return 1;
}

int f3d_body_get_world_position(const F3dWorld *world, F3dBody body,
                                double *out) {
  const F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL) return 0;
  out[0] = world->s.origin[0] + (double)s->position.x;
  out[1] = world->s.origin[1] + (double)s->position.y;
  out[2] = world->s.origin[2] + (double)s->position.z;
  return 1;
}

int f3d_body_set_angular_velocity(F3dWorld *world, F3dBody body, f3d_real x,
                                  f3d_real y, f3d_real z) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL || !finite3(x, y, z)) return 0;
  if (!f3d_turns(s)) return 1;
  set3(&s->spin, x, y, z);
  f3d_wake(world, s);
  return 1;
}

int f3d_body_get_angular_velocity(const F3dWorld *world, F3dBody body,
                                  f3d_real *out) {
  const F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL) return 0;
  get3(&s->spin, out);
  return 1;
}

int f3d_body_set_orientation(F3dWorld *world, F3dBody body, f3d_real x,
                             f3d_real y, f3d_real z, f3d_real w) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL || !finite3(x, y, z) || !f3d_finite(w)) return 0;
  const f3d_real length = f3d_sqrt(x * x + y * y + z * z + w * w);
  if (!(length > F3D_R(0.0)) || !f3d_finite(length)) {
    s->orientation.x = s->orientation.y = s->orientation.z = F3D_R(0.0);
    s->orientation.w = F3D_R(1.0);
  } else {
    s->orientation.x = x / length;
    s->orientation.y = y / length;
    s->orientation.z = z / length;
    s->orientation.w = w / length;
  }
  s->flags |= F3D_FLAG_MOVED;
  f3d_wake(world, s);
  return 1;
}

int f3d_body_get_orientation(const F3dWorld *world, F3dBody body,
                             f3d_real *out) {
  const F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL) return 0;
  out[0] = s->orientation.x;
  out[1] = s->orientation.y;
  out[2] = s->orientation.z;
  out[3] = s->orientation.w;
  return 1;
}

int f3d_body_set_shape(F3dWorld *world, F3dBody body, F3dShapeKind kind,
                       f3d_real a, f3d_real b, f3d_real c) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL) return 0;
#define POSITIVE(v) (f3d_finite(v) && (v) > F3D_R(0.0))
  switch (kind) {
    case F3D_SHAPE_POINT:
      set3(&s->size, F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
      break;
    case F3D_SHAPE_SPHERE:
      if (!POSITIVE(a)) return 0;
      set3(&s->size, a, F3D_R(0.0), F3D_R(0.0));
      break;
    case F3D_SHAPE_BOX:
      if (!POSITIVE(a) || !POSITIVE(b) || !POSITIVE(c)) return 0;
      set3(&s->size, a, b, c);
      break;
    case F3D_SHAPE_CAPSULE:
      /* A capsule with no straight part is a sphere, and allowed. */
      if (!POSITIVE(a) || !(f3d_finite(b) && b >= F3D_R(0.0))) return 0;
      set3(&s->size, a, b, F3D_R(0.0));
      break;
    case F3D_SHAPE_CYLINDER:
    case F3D_SHAPE_CONE:
      if (!POSITIVE(a) || !POSITIVE(b)) return 0;
      set3(&s->size, a, b, F3D_R(0.0));
      break;
    default:
      return 0;
  }
#undef POSITIVE
  s->shape = (uint8_t)kind;
  s->hull = 0;
  if (kind == F3D_SHAPE_POINT) s->rounding = F3D_R(0.0);
  f3d_refresh_mass(world, s);
  if (!f3d_turns(s)) set3(&s->spin, F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
  s->flags |= F3D_FLAG_MOVED;
  f3d_wake(world, s);
  return 1;
}

int f3d_body_get_inertia(const F3dWorld *world, F3dBody body, f3d_real *out) {
  const F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL) return 0;
  out[0] = s->inertia.xx;
  out[1] = s->inertia.yy;
  out[2] = s->inertia.zz;
  return 1;
}

int f3d_body_get_inertia_tensor(const F3dWorld *world, F3dBody body,
                                f3d_real *out) {
  const F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL) return 0;
  out[0] = s->inertia.xx;
  out[1] = s->inertia.yy;
  out[2] = s->inertia.zz;
  out[3] = s->inertia.xy;
  out[4] = s->inertia.xz;
  out[5] = s->inertia.yz;
  return 1;
}

int f3d_body_set_rounding(F3dWorld *world, F3dBody body, f3d_real radius) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL || !(f3d_finite(radius) && radius >= F3D_R(0.0))) return 0;
  if (s->shape == F3D_SHAPE_POINT && radius > F3D_R(0.0)) return 0;
  s->rounding = radius;
  f3d_refresh_mass(world, s);
  s->flags |= F3D_FLAG_MOVED;
  f3d_wake(world, s);
  return 1;
}

int f3d_body_set_hull(F3dWorld *world, F3dBody body, uint32_t hull) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL || hull == 0 || hull > world->s.hull_count) return 0;
  s->shape = F3D_SHAPE_HULL;
  s->hull = hull;
  set3(&s->size, F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
  f3d_refresh_mass(world, s);
  s->flags |= F3D_FLAG_MOVED;
  f3d_wake(world, s);
  return 1;
}

int f3d_body_get_mass(const F3dWorld *world, F3dBody body, f3d_real *out) {
  const F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL) return 0;
  *out = s->mass;
  return 1;
}

int f3d_body_lock_rotation(F3dWorld *world, F3dBody body, int locked) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL) return 0;
  if (locked) {
    s->flags |= F3D_FLAG_LOCKED;
  } else {
    s->flags &= (uint8_t)~F3D_FLAG_LOCKED;
  }
  f3d_refresh_mass(world, s);
  if (!f3d_turns(s)) set3(&s->spin, F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
  return 1;
}

int f3d_body_set_damping(F3dWorld *world, F3dBody body, f3d_real linear,
                         f3d_real angular) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL) return 0;
  if (!(f3d_finite(linear) && linear >= F3D_R(0.0))) return 0;
  if (!(f3d_finite(angular) && angular >= F3D_R(0.0))) return 0;
  s->linear_damping = linear;
  s->angular_damping = angular;
  return 1;
}

int f3d_body_set_drag(F3dWorld *world, F3dBody body, f3d_real coefficient) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL || !(f3d_finite(coefficient) && coefficient >= F3D_R(0.0))) {
    return 0;
  }
  s->drag = coefficient;
  f3d_refresh_mass(world, s);
  return 1;
}

/* The change of spin an angular impulse [l] makes: I⁻¹ in world axes
 * times it. */
static void spin_by(F3dSlot *s, F3dVec3 l) {
  const F3dVec3 w =
      f3d_sym_times(f3d_sym_turned(s->orientation, s->inverse_inertia), l);
  s->spin.x += w.x;
  s->spin.y += w.y;
  s->spin.z += w.z;
}

int f3d_body_apply_impulse(F3dWorld *world, F3dBody body, f3d_real x,
                           f3d_real y, f3d_real z) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL || !finite3(x, y, z)) return 0;
  if (s->inverse_mass == F3D_R(0.0)) return 1;
  s->velocity.x += x * s->inverse_mass;
  s->velocity.y += y * s->inverse_mass;
  s->velocity.z += z * s->inverse_mass;
  f3d_wake(world, s);
  return 1;
}

int f3d_body_apply_impulse_at(F3dWorld *world, F3dBody body, f3d_real x,
                              f3d_real y, f3d_real z, f3d_real px, f3d_real py,
                              f3d_real pz) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL || !finite3(x, y, z) || !finite3(px, py, pz)) return 0;
  if (s->inverse_mass == F3D_R(0.0)) return 1;
  s->velocity.x += x * s->inverse_mass;
  s->velocity.y += y * s->inverse_mass;
  s->velocity.z += z * s->inverse_mass;
  if (f3d_turns(s)) {
    const f3d_real rx = px - s->position.x;
    const f3d_real ry = py - s->position.y;
    const f3d_real rz = pz - s->position.z;
    F3dVec3 l;
    l.x = ry * z - rz * y;
    l.y = rz * x - rx * z;
    l.z = rx * y - ry * x;
    spin_by(s, l);
  }
  f3d_wake(world, s);
  return 1;
}

int f3d_body_add_force(F3dWorld *world, F3dBody body, f3d_real x, f3d_real y,
                       f3d_real z) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL || !finite3(x, y, z)) return 0;
  s->force.x += x;
  s->force.y += y;
  s->force.z += z;
  if (s->inverse_mass != F3D_R(0.0)) f3d_wake(world, s);
  return 1;
}

int f3d_body_add_torque(F3dWorld *world, F3dBody body, f3d_real x, f3d_real y,
                        f3d_real z) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL || !finite3(x, y, z)) return 0;
  s->torque.x += x;
  s->torque.y += y;
  s->torque.z += z;
  if (f3d_turns(s)) f3d_wake(world, s);
  return 1;
}

int f3d_body_is_asleep(const F3dWorld *world, F3dBody body) {
  const F3dSlot *s = f3d_slot_of(world, body);
  return s != NULL && (s->flags & F3D_FLAG_ASLEEP) != 0;
}

int f3d_body_wake(F3dWorld *world, F3dBody body) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL) return 0;
  f3d_wake(world, s);
  return 1;
}

uint32_t f3d_world_read_transforms(const F3dWorld *world, f3d_real *transforms,
                                   F3dBody *handles, uint32_t capacity) {
  uint32_t written = 0;
  for (uint32_t i = 0; i < world->s.used && written < capacity; i++) {
    const F3dSlot *s = &world->slots[i];
    if (!s->live) continue;
    f3d_real *t = transforms + (size_t)written * F3D_TRANSFORM_FLOATS;
    t[0] = s->position.x;
    t[1] = s->position.y;
    t[2] = s->position.z;
    t[3] = s->orientation.x;
    t[4] = s->orientation.y;
    t[5] = s->orientation.z;
    t[6] = s->orientation.w;
    if (handles != NULL) handles[written] = handle_of(i, s->generation);
    written++;
  }
  return written;
}

uint32_t f3d_world_read_fires(const F3dWorld *world, f3d_real *fires,
                              F3dBody *handles, uint32_t capacity) {
  uint32_t written = 0;
  for (uint32_t i = 0; i < world->s.used && written < capacity; i++) {
    const F3dSlot *s = &world->slots[i];
    if (!s->live || !(s->flags & F3D_FLAG_BURNING)) continue;
    f3d_real *f = fires + (size_t)written * F3D_FIRE_FLOATS;
    f[0] = s->position.x;
    f[1] = s->position.y;
    f[2] = s->position.z;
    f[3] = s->heat_release;
    if (handles != NULL) handles[written] = handle_of(i, s->generation);
    written++;
  }
  return written;
}

void f3d_world_step(F3dWorld *world, f3d_real dt) {
  if (!(f3d_finite(dt) && dt > F3D_R(0.0))) return;
  f3d_step_collide(world, dt);
  f3d_step_solve(world, dt);
  f3d_break_joints(world);
  f3d_step_heat(world, dt);
}
