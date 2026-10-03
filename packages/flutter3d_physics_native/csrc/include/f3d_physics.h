/*
 * The physics core of flutter3d, in C11 — P9.
 *
 * One world owns everything it steps: bodies, their heat and fire, the wind
 * they move through, and colliders, contacts, joints and islands as they
 * arrive. Nothing here calls back into the caller during a step; what a step
 * produces is read afterwards, in flat buffers, which is what a Dart FFI
 * call or a WebAssembly import wants.
 *
 * Numbers are f3d_real: f32 unless the core is built with F3D_REAL_DOUBLE,
 * for a simulation that wants doubles throughout and does not need the
 * browser to agree with it bit for bit. The deterministic mode is
 * bit-identical across platforms for the same inputs in the same order,
 * which is what this build's flags are for: no fused multiply-add
 * contraction, no fast math, no flush-to-zero, and no library
 * transcendentals: what the core needs of those it computes itself. The
 * square root is not one: IEEE 754 rounds it exactly, everywhere.
 *
 * Positions are relative to the world's origin, which is held in doubles.
 * A world kilometres across moves its origin to where the play is
 * (f3d_world_shift_origin), and every position near it keeps f32's full
 * precision; the renderer draws relative to the same origin.
 *
 * A body is named by a handle: its slot in the world's arena in the low 32
 * bits and the slot's generation in the high 32. A slot freed and reused
 * gets a new generation, so a handle kept past its body's destruction is
 * refused rather than answered with somebody else's body. Generations start
 * at one, so nought is never a handle.
 *
 * Units are SI: metres, kilograms, seconds, kelvin, joules, watts.
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
#define F3D_ABI_VERSION 3u

#ifdef F3D_REAL_DOUBLE
typedef double f3d_real;
#else
typedef float f3d_real;
#endif

typedef struct F3dWorld F3dWorld;

/* A body: (generation << 32) | slot. Nought is never one. */
typedef uint64_t F3dBody;

typedef enum F3dBodyType {
  /* Moved by gravity, forces, wind and contacts. */
  F3D_BODY_DYNAMIC = 0,
  /* Never moves; infinite mass. It still heats, cools and burns. */
  F3D_BODY_FIXED = 1,
} F3dBodyType;

/* What a body is shaped like, for its inertia, its surface and its drag.
 * Collision arrives with the contacts; these are the same shapes. */
typedef enum F3dShapeKind {
  /* No extent: does not turn, has no surface, feels no wind. */
  F3D_SHAPE_POINT = 0,
  /* a = radius. */
  F3D_SHAPE_SPHERE = 1,
  /* a, b, c = half extents along the body's x, y and z. */
  F3D_SHAPE_BOX = 2,
  /* a = radius, b = half the length of the straight part, along y. */
  F3D_SHAPE_CAPSULE = 3,
} F3dShapeKind;

/* What a body is made of, as heat and fire see it. */
typedef struct F3dMaterial {
  /* J / (kg K). */
  f3d_real specific_heat;
  /* Of the surface, nought to one. */
  f3d_real emissivity;
  /* K at which it catches fire and below which it goes out; nought for
   * a material that never burns. */
  f3d_real ignition_temperature;
  /* J released per kilogram burnt. */
  f3d_real heat_of_combustion;
  /* kg burnt per second per square metre of surface while alight. */
  f3d_real burn_rate;
  /* The share of the mass that can burn, nought to one. */
  f3d_real fuel_fraction;
  /* The share of the fire's heat that goes back into the body, nought to
   * one; the rest leaves as the hot gas a smoke grid takes. */
  f3d_real flame_feedback;
} F3dMaterial;

typedef enum F3dMaterialKind {
  F3D_MATERIAL_INERT = 0,
  F3D_MATERIAL_WOOD = 1,
  F3D_MATERIAL_PAPER = 2,
  F3D_MATERIAL_RUBBER = 3,
  F3D_MATERIAL_STEEL = 4,
  F3D_MATERIAL_STONE = 5,
} F3dMaterialKind;

/* What a step can say happened to a body. */
typedef enum F3dEventKind {
  F3D_EVENT_SLEPT = 0,
  F3D_EVENT_WOKE = 1,
  F3D_EVENT_IGNITED = 2,
  F3D_EVENT_EXTINGUISHED = 3,
  F3D_EVENT_BURNT_OUT = 4,
} F3dEventKind;

/* Reals one body takes in f3d_world_read_transforms: position xyz, then the
 * orientation quaternion xyzw. */
#define F3D_TRANSFORM_FLOATS 7u

/* Reals one fire takes in f3d_world_read_fires: position xyz, then the
 * watts it gives off as hot gas. */
#define F3D_FIRE_FLOATS 4u

/* Events held unread before the newest are dropped and counted. */
#define F3D_EVENT_CAPACITY 65536u

/* F3D_ABI_VERSION, so a binding can refuse a library it was not written
 * against. */
F3D_API uint32_t f3d_abi_version(void);

/* sizeof(f3d_real): 4, or 8 in a build with F3D_REAL_DOUBLE. */
F3D_API uint32_t f3d_real_bytes(void);

/* [bytes] of the core's own memory, 16-byte aligned, or null. For a caller
 * with no allocator of its own to hand the core a buffer from — the
 * WebAssembly module's JavaScript side, which has no malloc to call. */
F3D_API void *f3d_buffer_alloc(uint32_t bytes);

/* Gives back what f3d_buffer_alloc handed out. Null is allowed. */
F3D_API void f3d_buffer_free(void *buffer);

/* ------------------------------------------------------------------ world */

/* A world with gravity (0, -9.81, 0), still air at 293.15 K and 1.204 kg/m³,
 * its origin at nought; or null when out of memory. */
F3D_API F3dWorld *f3d_world_create(void);

/* Frees the world and everything in it. Null is allowed. */
F3D_API void f3d_world_destroy(F3dWorld *world);

F3D_API void f3d_world_set_gravity(F3dWorld *world, f3d_real x, f3d_real y,
                                   f3d_real z);

/* Writes the world's gravity into out[0..2]. */
F3D_API void f3d_world_get_gravity(const F3dWorld *world, f3d_real *out);

/* The air's temperature, K, and density, kg/m³. 0 and nothing changed for
 * a value that is not finite and positive. */
F3D_API int f3d_world_set_air(F3dWorld *world, f3d_real temperature,
                              f3d_real density);

/* Writes the air's temperature and density into out[0..1]. */
F3D_API void f3d_world_get_air(const F3dWorld *world, f3d_real *out);

/* The wind everywhere, m/s, added to the grid's where there is one. */
F3D_API void f3d_world_set_wind(F3dWorld *world, f3d_real x, f3d_real y,
                                f3d_real z);

/* A wind field: [nx] × [ny] × [nz] samples of velocity, three reals each,
 * x fastest, the first at (ox, oy, oz) relative to the origin and [cell]
 * metres apart, read trilinearly and held at its edge beyond it. Copied.
 * 0 and the old field kept when out of memory or for a size or spacing
 * that is not positive; [velocities] null clears the field. */
F3D_API int f3d_world_set_wind_grid(F3dWorld *world, f3d_real ox, f3d_real oy,
                                    f3d_real oz, f3d_real cell, uint32_t nx,
                                    uint32_t ny, uint32_t nz,
                                    const f3d_real *velocities);

/* The wind at (x, y, z) relative to the origin, into out[0..2]. */
F3D_API void f3d_world_sample_wind(const F3dWorld *world, f3d_real x,
                                   f3d_real y, f3d_real z, f3d_real *out);

/* How long, s, a body must stay slower than [speed], m/s and rad/s, to
 * fall asleep. 0 for a value that is negative or not finite; a [time] of
 * nought turns sleep off. Defaults: 0.05 and 0.5. */
F3D_API int f3d_world_set_sleep(F3dWorld *world, f3d_real speed,
                                f3d_real time);

/* Writes the world's origin, in doubles, into out[0..2]. */
F3D_API void f3d_world_get_origin(const F3dWorld *world, double *out);

/* Moves the origin by (dx, dy, dz) and every body, and the wind grid, the
 * other way, so nothing moves in the world. Positions near the new origin
 * get back the precision their distance from the old one cost. */
F3D_API void f3d_world_shift_origin(F3dWorld *world, double dx, double dy,
                                    double dz);

/* How many bodies the world holds. */
F3D_API uint32_t f3d_world_body_count(const F3dWorld *world);

/* Advances the world by [dt] seconds. Nothing happens for a dt that is not
 * finite and positive.
 *
 * For each awake dynamic body, semi-implicit Euler, as flutter3d_physics
 * steps: the velocity gains gravity, the wind's drag and the forces added
 * since the last step, all times dt, and the spin the torques; then the
 * position gains the new velocity times dt and the orientation turns by the
 * spin, its angular momentum carried through. Then every body's heat: what
 * the bus brought, the fire's share, convection to the moving air and
 * radiation to it, the water on it boiling off at 373.15 K first. Forces,
 * torques and heat added through the bus are spent by the step. */
F3D_API void f3d_world_step(F3dWorld *world, f3d_real dt);

/* Writes every body's transform, F3D_TRANSFORM_FLOATS reals apiece, into
 * [transforms], and its handle into [handles] when that is not null, in the
 * world's slot order. At most [capacity] bodies; returns how many were
 * written. */
F3D_API uint32_t f3d_world_read_transforms(const F3dWorld *world,
                                           f3d_real *transforms,
                                           F3dBody *handles,
                                           uint32_t capacity);

/* Every burning body, F3D_FIRE_FLOATS reals apiece, as
 * f3d_world_read_transforms does: what a smoke grid takes its sources
 * from. */
F3D_API uint32_t f3d_world_read_fires(const F3dWorld *world, f3d_real *fires,
                                      F3dBody *handles, uint32_t capacity);

/* Moves up to [capacity] events, oldest first, into [bodies] and [kinds],
 * and returns how many. What is not read stays for the next call. */
F3D_API uint32_t f3d_world_read_events(F3dWorld *world, F3dBody *bodies,
                                       uint32_t *kinds, uint32_t capacity);

/* Events dropped because F3D_EVENT_CAPACITY were waiting unread. */
F3D_API uint32_t f3d_world_events_dropped(const F3dWorld *world);

/* -------------------------------------------------------------- snapshots */

/* Bytes f3d_world_snapshot_write needs for the world as it is. */
F3D_API uint32_t f3d_world_snapshot_size(const F3dWorld *world);

/* Writes the world's whole state into [buffer] and returns the bytes
 * written, or nought when [size] is too small. A world restored from it
 * steps to the same bits the original does. */
F3D_API uint32_t f3d_world_snapshot_write(const F3dWorld *world,
                                          uint8_t *buffer, uint32_t size);

/* Puts the world back as [buffer] says. 1, or 0 and the world unchanged for
 * a buffer that is not a snapshot from this build of the core. Handles kept
 * from before name what they named when the snapshot was taken. */
F3D_API int f3d_world_restore(F3dWorld *world, const uint8_t *buffer,
                              uint32_t size);

/* ----------------------------------------------------------------- bodies */

/* A body of [type] at (px, py, pz) with [mass] kilograms, at rest,
 * unrotated, a point of inert material at the air's temperature. Nought
 * when the world cannot grow, or when a dynamic body is given a mass that
 * is not finite and positive. A fixed body's mass is its thermal mass
 * only, and may be nought. */
F3D_API F3dBody f3d_body_create(F3dWorld *world, F3dBodyType type, f3d_real px,
                                f3d_real py, f3d_real pz, f3d_real mass);

/* Takes [body] out of the world. 1 when it was there, 0 for a stale or
 * foreign handle. */
F3D_API int f3d_body_destroy(F3dWorld *world, F3dBody body);

/* 1 while [body] names a body in [world]. */
F3D_API int f3d_body_is_valid(const F3dWorld *world, F3dBody body);

/* Every accessor below: 1 and the value written, or 0 for a handle that is
 * not valid or a value that is not finite. Setting a body's motion wakes
 * it. */
F3D_API int f3d_body_set_velocity(F3dWorld *world, F3dBody body, f3d_real x,
                                  f3d_real y, f3d_real z);
F3D_API int f3d_body_get_velocity(const F3dWorld *world, F3dBody body,
                                  f3d_real *out);
F3D_API int f3d_body_set_position(F3dWorld *world, F3dBody body, f3d_real x,
                                  f3d_real y, f3d_real z);
F3D_API int f3d_body_get_position(const F3dWorld *world, F3dBody body,
                                  f3d_real *out);

/* The position in the world's own coordinates, origin added, in doubles. */
F3D_API int f3d_body_get_world_position(const F3dWorld *world, F3dBody body,
                                        double *out);

/* Radians per second about the world's axes. Nothing turns a body that
 * cannot: a point, a fixed body, or one whose rotation is locked. */
F3D_API int f3d_body_set_angular_velocity(F3dWorld *world, F3dBody body,
                                          f3d_real x, f3d_real y, f3d_real z);
F3D_API int f3d_body_get_angular_velocity(const F3dWorld *world, F3dBody body,
                                          f3d_real *out);

/* A quaternion xyzw, normalised on the way in; a zero one is the
 * identity. */
F3D_API int f3d_body_set_orientation(F3dWorld *world, F3dBody body, f3d_real x,
                                     f3d_real y, f3d_real z, f3d_real w);
F3D_API int f3d_body_get_orientation(const F3dWorld *world, F3dBody body,
                                     f3d_real *out);

/* The body's shape, as F3dShapeKind says what a, b and c are. Its inertia
 * follows from its mass, its surface and drag from its size. 0 for a size
 * that is not finite and positive where the kind reads it. */
F3D_API int f3d_body_set_shape(F3dWorld *world, F3dBody body,
                               F3dShapeKind kind, f3d_real a, f3d_real b,
                               f3d_real c);

/* The principal moments of inertia, kg m², in the body's axes, into
 * out[0..2]. */
F3D_API int f3d_body_get_inertia(const F3dWorld *world, F3dBody body,
                                 f3d_real *out);

/* Kilograms: less, once it has burnt. */
F3D_API int f3d_body_get_mass(const F3dWorld *world, F3dBody body,
                              f3d_real *out);

/* 1 keeps the body from turning, whatever its shape. */
F3D_API int f3d_body_lock_rotation(F3dWorld *world, F3dBody body, int locked);

/* Per second, the share of velocity and of spin taken away, each as
 * 1 / (1 + dt · damping). Nought, the default, keeps them. */
F3D_API int f3d_body_set_damping(F3dWorld *world, F3dBody body,
                                 f3d_real linear, f3d_real angular);

/* The drag coefficient against the wind; nought, the default, takes the
 * shape's own: 0.47 a sphere, 1.05 a box, 0.6 a capsule. */
F3D_API int f3d_body_set_drag(F3dWorld *world, F3dBody body,
                              f3d_real coefficient);

/* An impulse, N s, through the centre, or at (px, py, pz) relative to the
 * origin, which spins the body as well. */
F3D_API int f3d_body_apply_impulse(F3dWorld *world, F3dBody body, f3d_real x,
                                   f3d_real y, f3d_real z);
F3D_API int f3d_body_apply_impulse_at(F3dWorld *world, F3dBody body,
                                      f3d_real x, f3d_real y, f3d_real z,
                                      f3d_real px, f3d_real py, f3d_real pz);

/* The bus: a force, N, or a torque, N m, about the world's axes, held over
 * the next step and spent by it; added up when added twice. */
F3D_API int f3d_body_add_force(F3dWorld *world, F3dBody body, f3d_real x,
                               f3d_real y, f3d_real z);
F3D_API int f3d_body_add_torque(F3dWorld *world, F3dBody body, f3d_real x,
                                f3d_real y, f3d_real z);

/* 1 while the body sleeps. */
F3D_API int f3d_body_is_asleep(const F3dWorld *world, F3dBody body);

/* Wakes the body, and starts its sleep clock again. */
F3D_API int f3d_body_wake(F3dWorld *world, F3dBody body);

/* ------------------------------------------------------- heat and fire */

/* A material's typical values into [out]. 0 for a kind there is none of. */
F3D_API int f3d_material_preset(F3dMaterialKind kind, F3dMaterial *out);

/* What the body is made of. Its fuel is its mass times the material's
 * fuel fraction, counted from now. 0 for a value out of its range. */
F3D_API int f3d_body_set_material(F3dWorld *world, F3dBody body,
                                  const F3dMaterial *material);

/* Kelvin. Set, it does not light a fire or put one out until the step
 * says so. */
F3D_API int f3d_body_set_temperature(F3dWorld *world, F3dBody body,
                                     f3d_real kelvin);
F3D_API int f3d_body_get_temperature(const F3dWorld *world, F3dBody body,
                                     f3d_real *out);

/* The bus: joules into the body over the next step, or out of it for a
 * negative amount. */
F3D_API int f3d_body_add_heat(F3dWorld *world, F3dBody body, f3d_real joules);

/* The bus: kilograms of water onto the body, at the air's temperature and
 * mixed with the body's heat at once, or off it for a negative amount.
 * Water holds the body at its boiling point until it has boiled away,
 * which is how it puts a fire out. Its heat is counted, not its weight. */
F3D_API int f3d_body_add_water(F3dWorld *world, F3dBody body, f3d_real kg);
F3D_API int f3d_body_get_water(const F3dWorld *world, F3dBody body,
                               f3d_real *out);

/* Kilograms that can still burn. */
F3D_API int f3d_body_get_fuel(const F3dWorld *world, F3dBody body,
                              f3d_real *out);

/* 1 while the body burns, into *out. */
F3D_API int f3d_body_is_burning(const F3dWorld *world, F3dBody body, int *out);

/* Watts the fire gave off as hot gas over the last step. */
F3D_API int f3d_body_get_heat_release(const F3dWorld *world, F3dBody body,
                                      f3d_real *out);

#ifdef __cplusplus
}
#endif

#endif /* F3D_PHYSICS_H_ */
