/*
 * The physics core of flutter3d, in C11 — P9.
 *
 * One world owns everything it steps: bodies now, and colliders, contacts,
 * joints and islands as they arrive. Nothing here calls back into the
 * caller during a step; what a step produces is read afterwards, in flat
 * buffers, which is what a Dart FFI call or a WebAssembly import wants.
 *
 * Numbers are f32 throughout. The deterministic mode is bit-identical
 * across platforms for the same inputs in the same order, which is what
 * this build's flags are for: no fused multiply-add contraction, no fast
 * math, no flush-to-zero, and no library transcendentals: what the core
 * needs of those it computes itself.
 *
 * A body is named by a handle: its slot in the world's arena in the low 32
 * bits and the slot's generation in the high 32. A slot freed and reused
 * gets a new generation, so a handle kept past its body's destruction is
 * refused rather than answered with somebody else's body. Generations start
 * at one, so nought is never a handle.
 */
#ifndef F3D_PHYSICS_H_
#define F3D_PHYSICS_H_

#include <stdint.h>

#if defined(_WIN32)
#define F3D_API __declspec(dllexport)
#else
#define F3D_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* Bumped whenever a function's meaning or signature changes. */
#define F3D_ABI_VERSION 2u

typedef struct F3dWorld F3dWorld;

/* A body: (generation << 32) | slot. Nought is never one. */
typedef uint64_t F3dBody;

typedef enum F3dBodyType {
  /* Moved by gravity, forces and contacts. */
  F3D_BODY_DYNAMIC = 0,
  /* Never moves; infinite mass. */
  F3D_BODY_FIXED = 1,
} F3dBodyType;

/* Floats one body takes in f3d_world_read_transforms: position xyz, then the
 * orientation quaternion xyzw. */
#define F3D_TRANSFORM_FLOATS 7u

/* F3D_ABI_VERSION, so a binding can refuse a library it was not written
 * against. */
F3D_API uint32_t f3d_abi_version(void);

/* [bytes] of the core's own memory, 16-byte aligned, or null. For a caller
 * with no allocator of its own to hand the core a buffer from — the
 * WebAssembly module's JavaScript side, which has no malloc to call. */
F3D_API void *f3d_buffer_alloc(uint32_t bytes);

/* Gives back what f3d_buffer_alloc handed out. Null is allowed. */
F3D_API void f3d_buffer_free(void *buffer);

/* A world with gravity (0, -9.81, 0), or null when out of memory. */
F3D_API F3dWorld *f3d_world_create(void);

/* Frees the world and everything in it. Null is allowed. */
F3D_API void f3d_world_destroy(F3dWorld *world);

F3D_API void f3d_world_set_gravity(F3dWorld *world, float x, float y, float z);

/* Writes the world's gravity into out[0..2]. */
F3D_API void f3d_world_get_gravity(const F3dWorld *world, float *out);

/* How many bodies the world holds. */
F3D_API uint32_t f3d_world_body_count(const F3dWorld *world);

/* A body of [type] at (px, py, pz) with [mass] kilograms, at rest and
 * unrotated. Nought when the world cannot grow, or when a dynamic body is
 * given a mass that is not finite and positive. A fixed body's mass is
 * ignored. */
F3D_API F3dBody f3d_body_create(F3dWorld *world, F3dBodyType type, float px,
                                float py, float pz, float mass);

/* Takes [body] out of the world. 1 when it was there, 0 for a stale or
 * foreign handle. */
F3D_API int f3d_body_destroy(F3dWorld *world, F3dBody body);

/* 1 while [body] names a body in [world]. */
F3D_API int f3d_body_is_valid(const F3dWorld *world, F3dBody body);

/* 1 and the value written, or 0 for a handle that is not valid. */
F3D_API int f3d_body_set_velocity(F3dWorld *world, F3dBody body, float x,
                                  float y, float z);
F3D_API int f3d_body_get_velocity(const F3dWorld *world, F3dBody body,
                                  float *out);
F3D_API int f3d_body_set_position(F3dWorld *world, F3dBody body, float x,
                                  float y, float z);
F3D_API int f3d_body_get_position(const F3dWorld *world, F3dBody body,
                                  float *out);

/* Advances the world by [dt] seconds. Nothing happens for a dt that is not
 * finite and positive.
 *
 * Semi-implicit Euler, as flutter3d_physics steps: a dynamic body's
 * velocity gains gravity * dt, then its position gains velocity * dt. */
F3D_API void f3d_world_step(F3dWorld *world, float dt);

/* Writes every body's transform, F3D_TRANSFORM_FLOATS floats apiece, into
 * [transforms], and its handle into [handles] when that is not null, in the
 * world's slot order. At most [capacity] bodies; returns how many were
 * written. */
F3D_API uint32_t f3d_world_read_transforms(const F3dWorld *world,
                                           float *transforms,
                                           F3dBody *handles,
                                           uint32_t capacity);

#ifdef __cplusplus
}
#endif

#endif /* F3D_PHYSICS_H_ */
