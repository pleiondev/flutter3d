/*
 * What the core's files share and the API does not show.
 */
#ifndef F3D_INTERNAL_H_
#define F3D_INTERNAL_H_

#include <stddef.h>
#include <stdint.h>

#include "f3d_physics.h"

/* --------------------------------------------------------------- memory
 *
 * Every allocation goes through these, so the WebAssembly build — which has
 * no C library — supplies them once, in f3d_wasm.c, and nothing else in the
 * core knows which build it is in.
 */
void *f3d_alloc(size_t bytes);
void *f3d_realloc(void *block, size_t bytes);
void f3d_free(void *block);
void f3d_zero(void *block, size_t bytes);

/* ----------------------------------------------------------------- math */

/* Whether [x] is neither infinite nor NaN, without <math.h>: the
 * WebAssembly build has none, and isfinite may be a library call. */
static inline int f3d_finite(float x) { return x - x == 0.0f; }

/* ---------------------------------------------------------------- world */

typedef struct F3dVec3 {
  float x, y, z;
} F3dVec3;

typedef struct F3dQuat {
  float x, y, z, w;
} F3dQuat;

/* One arena slot. A free slot keeps its generation, so the next body it
 * holds gets a new one, and links to the next free slot. */
typedef struct F3dSlot {
  uint32_t generation;
  /* Next free slot plus one, or nought; meaningful while free. */
  uint32_t next_free;
  uint8_t live;
  uint8_t type;
  F3dVec3 position;
  F3dQuat orientation;
  F3dVec3 velocity;
  float inverse_mass;
} F3dSlot;

struct F3dWorld {
  F3dSlot *slots;
  uint32_t capacity;
  /* Slots ever used: the arena's high-water mark. */
  uint32_t used;
  uint32_t live;
  /* First free slot plus one, or nought. */
  uint32_t free_head;
  F3dVec3 gravity;
};

/* The slot [body] names in [world], or null for a stale or foreign one. */
F3dSlot *f3d_slot_of(const F3dWorld *world, F3dBody body);

#endif /* F3D_INTERNAL_H_ */
