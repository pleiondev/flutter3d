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
 * no C library — supplies them once, in f3d_memory_wasm.c, and nothing else
 * in the core knows which build it is in.
 */
void *f3d_alloc(size_t bytes);
void *f3d_realloc(void *block, size_t bytes);
void f3d_free(void *block);
void f3d_zero(void *block, size_t bytes);
void f3d_copy(void *to, const void *from, size_t bytes);

/* ----------------------------------------------------------------- math */

/* A literal as an f3d_real, so one expression reads the same in either
 * build. */
#define F3D_R(x) ((f3d_real)(x))

#define F3D_PI F3D_R(3.14159265358979323846)

/* Stefan–Boltzmann, W / (m² K⁴). */
#define F3D_STEFAN_BOLTZMANN F3D_R(5.670374419e-8)

/* Water: J / (kg K), J / kg to boil it, and K at which it boils. */
#define F3D_WATER_HEAT F3D_R(4186.0)
#define F3D_WATER_LATENT F3D_R(2.257e6)
#define F3D_WATER_BOILS F3D_R(373.15)

/* Whether [x] is neither infinite nor NaN, without <math.h>: the
 * WebAssembly build has none, and isfinite may be a library call. */
static inline int f3d_finite(f3d_real x) { return x - x == F3D_R(0.0); }

/* The square root, which IEEE 754 rounds exactly: an instruction on every
 * target, never a library call — f32.sqrt in WebAssembly, sqrtss on x86,
 * fsqrt on ARM. */
#if defined(_MSC_VER)
#include <math.h>
#ifdef F3D_REAL_DOUBLE
static inline f3d_real f3d_sqrt(f3d_real x) { return sqrt(x); }
#else
static inline f3d_real f3d_sqrt(f3d_real x) { return sqrtf(x); }
#endif
#else
#ifdef F3D_REAL_DOUBLE
static inline f3d_real f3d_sqrt(f3d_real x) { return __builtin_sqrt(x); }
#else
static inline f3d_real f3d_sqrt(f3d_real x) { return __builtin_sqrtf(x); }
#endif
#endif

static inline f3d_real f3d_min(f3d_real a, f3d_real b) { return a < b ? a : b; }
static inline f3d_real f3d_max(f3d_real a, f3d_real b) { return a > b ? a : b; }

typedef struct F3dVec3 {
  f3d_real x, y, z;
} F3dVec3;

typedef struct F3dQuat {
  f3d_real x, y, z, w;
} F3dQuat;

/* A symmetric 3×3 matrix: the six numbers that are not mirrors. */
typedef struct F3dSym3 {
  f3d_real xx, yy, zz, xy, xz, yz;
} F3dSym3;

/* R · diag(d) · Rᵀ, with R the rotation of the unit quaternion [q]. */
F3dSym3 f3d_sym_turned(F3dQuat q, F3dVec3 d);

static inline F3dVec3 f3d_sym_times(F3dSym3 m, F3dVec3 v) {
  F3dVec3 out;
  out.x = m.xx * v.x + m.xy * v.y + m.xz * v.z;
  out.y = m.xy * v.x + m.yy * v.y + m.yz * v.z;
  out.z = m.xz * v.x + m.yz * v.y + m.zz * v.z;
  return out;
}

/* ---------------------------------------------------------------- world */

/* Bits of F3dSlot.flags. */
enum {
  F3D_FLAG_ASLEEP = 1u << 0,
  F3D_FLAG_LOCKED = 1u << 1,
  F3D_FLAG_BURNING = 1u << 2,
};

/* One arena slot. A free slot keeps its generation, so the next body it
 * holds gets a new one, and links to the next free slot.
 *
 * Plain data, zeroed when taken, so a snapshot copies it whole and its
 * padding is the same bytes every time. */
typedef struct F3dSlot {
  uint32_t generation;
  /* Next free slot plus one, or nought; meaningful while free. */
  uint32_t next_free;
  uint8_t live;
  uint8_t type;
  uint8_t shape;
  uint8_t flags;
  F3dVec3 position;
  F3dQuat orientation;
  F3dVec3 velocity;
  F3dVec3 spin;
  F3dVec3 force;
  F3dVec3 torque;
  /* The shape's size, as F3dShapeKind reads it. */
  F3dVec3 size;
  f3d_real mass;
  f3d_real inverse_mass;
  /* Principal moments in the body's axes, and their inverses — nought
   * where the body does not turn. */
  F3dVec3 inertia;
  F3dVec3 inverse_inertia;
  f3d_real linear_damping;
  f3d_real angular_damping;
  /* As set; nought takes the shape's. */
  f3d_real drag;
  /* m², and the coefficient the step uses. */
  f3d_real surface;
  f3d_real shape_drag;
  /* Seconds spent below the sleep speed. */
  f3d_real still;
  F3dMaterial material;
  f3d_real temperature;
  f3d_real heat;
  f3d_real water;
  f3d_real fuel;
  /* W given off as gas over the last step. */
  f3d_real heat_release;
} F3dSlot;

typedef struct F3dEventRecord {
  F3dBody body;
  uint32_t kind;
  uint32_t reserved;
} F3dEventRecord;

/* Everything in a world that is not behind a pointer: what a snapshot
 * copies in one piece. */
typedef struct F3dWorldState {
  double origin[3];
  F3dVec3 gravity;
  F3dVec3 wind;
  f3d_real air_temperature;
  f3d_real air_density;
  f3d_real sleep_speed;
  f3d_real sleep_time;
  /* Slots ever used: the arena's high-water mark. */
  uint32_t used;
  uint32_t live;
  /* First free slot plus one, or nought. */
  uint32_t free_head;
  /* The wind grid, or none while its counts are nought. */
  F3dVec3 grid_origin;
  f3d_real grid_cell;
  uint32_t grid_n[3];
  /* Events waiting, from the oldest at events_head. */
  uint32_t events_head;
  uint32_t events_count;
  uint32_t events_dropped;
} F3dWorldState;

struct F3dWorld {
  F3dWorldState s;
  F3dSlot *slots;
  uint32_t capacity;
  /* Three reals a sample. */
  f3d_real *grid;
  /* A ring of F3D_EVENT_CAPACITY, allocated with the first event. */
  F3dEventRecord *events;
};

/* The slot [body] names in [world], or null for a stale or foreign one. */
F3dSlot *f3d_slot_of(const F3dWorld *world, F3dBody body);

F3dBody f3d_handle_of(const F3dWorld *world, const F3dSlot *slot);

/* Brings a body's inertia, surface and drag up to date with its shape and
 * mass. */
void f3d_refresh_mass(F3dSlot *slot);

void f3d_push_event(F3dWorld *world, F3dBody body, uint32_t kind);

/* The step's halves: motion, then heat. */
void f3d_step_motion(F3dWorld *world, f3d_real dt);
void f3d_step_heat(F3dWorld *world, f3d_real dt);

#endif /* F3D_INTERNAL_H_ */
