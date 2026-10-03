/*
 * The world and its bodies — P9, phase 0: an arena of bodies named by
 * generational handles, gravity, and a semi-implicit Euler step.
 */
#include "f3d_internal.h"

/* Room for this many bodies before the arena first grows. */
#define F3D_INITIAL_CAPACITY 64u

uint32_t f3d_abi_version(void) { return F3D_ABI_VERSION; }

void *f3d_buffer_alloc(uint32_t bytes) { return f3d_alloc(bytes); }

void f3d_buffer_free(void *buffer) { f3d_free(buffer); }

F3dWorld *f3d_world_create(void) {
  F3dWorld *world = (F3dWorld *)f3d_alloc(sizeof(F3dWorld));
  if (world == NULL) return NULL;
  f3d_zero(world, sizeof(F3dWorld));
  world->gravity.y = -9.81f;
  return world;
}

void f3d_world_destroy(F3dWorld *world) {
  if (world == NULL) return;
  f3d_free(world->slots);
  f3d_free(world);
}

void f3d_world_set_gravity(F3dWorld *world, float x, float y, float z) {
  world->gravity.x = x;
  world->gravity.y = y;
  world->gravity.z = z;
}

void f3d_world_get_gravity(const F3dWorld *world, float *out) {
  out[0] = world->gravity.x;
  out[1] = world->gravity.y;
  out[2] = world->gravity.z;
}

uint32_t f3d_world_body_count(const F3dWorld *world) { return world->live; }

static F3dBody handle_of(uint32_t slot, uint32_t generation) {
  return ((uint64_t)generation << 32) | (uint64_t)slot;
}

F3dSlot *f3d_slot_of(const F3dWorld *world, F3dBody body) {
  const uint32_t slot = (uint32_t)(body & 0xffffffffu);
  const uint32_t generation = (uint32_t)(body >> 32);
  if (generation == 0 || slot >= world->used) return NULL;
  F3dSlot *s = &world->slots[slot];
  return s->live && s->generation == generation ? s : NULL;
}

/* A free slot's index, growing the arena when none is free; or UINT32_MAX
 * when it cannot grow. */
static uint32_t take_slot(F3dWorld *world) {
  if (world->free_head != 0) {
    const uint32_t slot = world->free_head - 1;
    world->free_head = world->slots[slot].next_free;
    return slot;
  }
  if (world->used == world->capacity) {
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
  return world->used++;
}

F3dBody f3d_body_create(F3dWorld *world, F3dBodyType type, float px, float py,
                        float pz, float mass) {
  if (type != F3D_BODY_DYNAMIC && type != F3D_BODY_FIXED) return 0;
  if (!f3d_finite(px) || !f3d_finite(py) || !f3d_finite(pz)) return 0;
  if (type == F3D_BODY_DYNAMIC && !(f3d_finite(mass) && mass > 0.0f)) {
    return 0;
  }
  const uint32_t slot = take_slot(world);
  if (slot == UINT32_MAX) return 0;
  F3dSlot *s = &world->slots[slot];
  uint32_t generation = s->generation + 1u;
  if (generation == 0) generation = 1; /* Wrapped: nought is never a handle. */
  f3d_zero(s, sizeof(F3dSlot));
  s->generation = generation;
  s->live = 1;
  s->type = (uint8_t)type;
  s->position.x = px;
  s->position.y = py;
  s->position.z = pz;
  s->orientation.w = 1.0f;
  s->inverse_mass = type == F3D_BODY_DYNAMIC ? 1.0f / mass : 0.0f;
  world->live++;
  return handle_of(slot, generation);
}

int f3d_body_destroy(F3dWorld *world, F3dBody body) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL) return 0;
  s->live = 0;
  s->next_free = world->free_head;
  world->free_head = (uint32_t)(s - world->slots) + 1u;
  world->live--;
  return 1;
}

int f3d_body_is_valid(const F3dWorld *world, F3dBody body) {
  return f3d_slot_of(world, body) != NULL;
}

int f3d_body_set_velocity(F3dWorld *world, F3dBody body, float x, float y,
                          float z) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL) return 0;
  s->velocity.x = x;
  s->velocity.y = y;
  s->velocity.z = z;
  return 1;
}

int f3d_body_get_velocity(const F3dWorld *world, F3dBody body, float *out) {
  const F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL) return 0;
  out[0] = s->velocity.x;
  out[1] = s->velocity.y;
  out[2] = s->velocity.z;
  return 1;
}

int f3d_body_set_position(F3dWorld *world, F3dBody body, float x, float y,
                          float z) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL) return 0;
  s->position.x = x;
  s->position.y = y;
  s->position.z = z;
  return 1;
}

int f3d_body_get_position(const F3dWorld *world, F3dBody body, float *out) {
  const F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL) return 0;
  out[0] = s->position.x;
  out[1] = s->position.y;
  out[2] = s->position.z;
  return 1;
}

void f3d_world_step(F3dWorld *world, float dt) {
  if (!(f3d_finite(dt) && dt > 0.0f)) return;
  const F3dVec3 g = world->gravity;
  for (uint32_t i = 0; i < world->used; i++) {
    F3dSlot *s = &world->slots[i];
    if (!s->live || s->type != F3D_BODY_DYNAMIC) continue;
    /* Velocity first, then position with the new velocity: semi-implicit
     * Euler, the order flutter3d_physics steps in. */
    s->velocity.x += g.x * dt;
    s->velocity.y += g.y * dt;
    s->velocity.z += g.z * dt;
    s->position.x += s->velocity.x * dt;
    s->position.y += s->velocity.y * dt;
    s->position.z += s->velocity.z * dt;
  }
}

uint32_t f3d_world_read_transforms(const F3dWorld *world, float *transforms,
                                   F3dBody *handles, uint32_t capacity) {
  uint32_t written = 0;
  for (uint32_t i = 0; i < world->used && written < capacity; i++) {
    const F3dSlot *s = &world->slots[i];
    if (!s->live) continue;
    float *t = transforms + (size_t)written * F3D_TRANSFORM_FLOATS;
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
