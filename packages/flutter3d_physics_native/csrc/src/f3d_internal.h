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

/* Overlap the solver leaves alone, m: pushing a resting box out to the last
 * micrometre would have it lose contact, fall a substep and land again. A
 * contact this close or closer counts as touching, since this is as close
 * as the solver brings a body it holds. */
#define F3D_LINEAR_SLOP F3D_R(0.005)

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

/* R · M · Rᵀ, with R the rotation of the unit quaternion [q]: a tensor in
 * a body's own axes, in the world's. */
F3dSym3 f3d_sym_turned(F3dQuat q, F3dSym3 m);

static inline F3dSym3 f3d_sym_diag(f3d_real x, f3d_real y, f3d_real z) {
  F3dSym3 m;
  m.xx = x;
  m.yy = y;
  m.zz = z;
  m.xy = m.xz = m.yz = 0;
  return m;
}

/* The inverse of a symmetric matrix by its cofactors, or nought for one
 * that has none. */
F3dSym3 f3d_sym_inverse(F3dSym3 m);

static inline F3dVec3 f3d_sym_times(F3dSym3 m, F3dVec3 v) {
  F3dVec3 out;
  out.x = m.xx * v.x + m.xy * v.y + m.xz * v.z;
  out.y = m.xy * v.x + m.yy * v.y + m.yz * v.z;
  out.z = m.xz * v.x + m.yz * v.y + m.zz * v.z;
  return out;
}

static inline F3dVec3 f3d_v3(f3d_real x, f3d_real y, f3d_real z) {
  F3dVec3 v;
  v.x = x;
  v.y = y;
  v.z = z;
  return v;
}
static inline F3dVec3 f3d_add(F3dVec3 a, F3dVec3 b) {
  return f3d_v3(a.x + b.x, a.y + b.y, a.z + b.z);
}
static inline F3dVec3 f3d_sub(F3dVec3 a, F3dVec3 b) {
  return f3d_v3(a.x - b.x, a.y - b.y, a.z - b.z);
}
static inline F3dVec3 f3d_scale(F3dVec3 a, f3d_real k) {
  return f3d_v3(a.x * k, a.y * k, a.z * k);
}
/* a + b·k. */
static inline F3dVec3 f3d_madd(F3dVec3 a, F3dVec3 b, f3d_real k) {
  return f3d_v3(a.x + b.x * k, a.y + b.y * k, a.z + b.z * k);
}
static inline f3d_real f3d_dot(F3dVec3 a, F3dVec3 b) {
  return a.x * b.x + a.y * b.y + a.z * b.z;
}
static inline F3dVec3 f3d_cross(F3dVec3 a, F3dVec3 b) {
  return f3d_v3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z,
                a.x * b.y - a.y * b.x);
}
static inline f3d_real f3d_abs(f3d_real x) { return x < F3D_R(0.0) ? -x : x; }
static inline f3d_real f3d_clamp(f3d_real x, f3d_real lo, f3d_real hi) {
  return x < lo ? lo : (x > hi ? hi : x);
}

/* A rotation as its three columns: the body's own axes in the world's. */
typedef struct F3dMat3 {
  F3dVec3 c[3];
} F3dMat3;

F3dMat3 f3d_mat_of(F3dQuat q);

/* ------------------------------------------------------------- contacts */

/* Points a manifold holds at most: four keep a box resting on a face from
 * rocking, and more add nothing a solver uses. */
#define F3D_MANIFOLD_POINTS 4u

typedef struct F3dContactPoint {
  /* Halfway between the two surfaces, relative to the origin. */
  F3dVec3 point;
  /* Positive inside, negative a gap within the margin. */
  f3d_real depth;
  /* Which features made it, so a solver can carry its impulse to the next
   * step's point from the same features. */
  uint32_t id;
  /* What the solver pushed with, along the normal and the two tangents, per
   * substep: where the next step starts from. */
  f3d_real normal_impulse;
  f3d_real tangent_impulse[2];
} F3dContactPoint;

/* Everything two bodies' shapes touch at. Plain data: a snapshot copies it
 * whole. */
typedef struct F3dManifold {
  /* The lower slot is a, the higher b. */
  F3dBody a;
  F3dBody b;
  /* Out of b, into a: the way a moves to come apart. */
  F3dVec3 normal;
  uint32_t count;
  /* 1 while some point is within the solver's slop of touching, or past
   * it: not only within the margin. */
  uint32_t touching;
  F3dContactPoint points[F3D_MANIFOLD_POINTS];
} F3dManifold;

/* A shape where it stands, as the narrow phase reads it. */
typedef struct F3dPlaced {
  uint32_t kind;
  F3dVec3 size;
  F3dVec3 at;
  F3dMat3 axes;
  /* How far the shape is rounded out. */
  f3d_real rounding;
  /* A hull's vertices and triangles, and their counts; null for the rest. */
  const struct F3dHull *hull;
  const f3d_real *vertices;
  const uint32_t *triangles;
} F3dPlaced;

/* Fills [out]'s normal and points for [a] against [b], within [margin],
 * and returns how many points; nought when they are further apart. The
 * normal points out of b into a. */
uint32_t f3d_collide(const F3dPlaced *a, const F3dPlaced *b, f3d_real margin,
                     F3dManifold *out);

/* ---------------------------------------------------------------- world */

/* Bits of F3dSlot.flags. */
enum {
  F3D_FLAG_ASLEEP = 1u << 0,
  F3D_FLAG_LOCKED = 1u << 1,
  F3D_FLAG_BURNING = 1u << 2,
  /* Placed, turned or reshaped by the caller since the last step: whatever
   * it slept against has to look again. */
  F3D_FLAG_MOVED = 1u << 3,
};

/* ----------------------------------------------------------------- tree */

typedef struct F3dBox {
  F3dVec3 lo, hi;
} F3dBox;

/* A node of the broadphase tree: a leaf holds one body's fat box, an
 * inner node the box round its two children. */
typedef struct F3dTreeNode {
  F3dBox box;
  /* The parent, or the next free node while free; -1 for none. */
  int32_t parent;
  /* Children; child1 is -1 for a leaf. */
  int32_t child1, child2;
  /* A leaf's is nought; -1 while free. */
  int32_t height;
  /* A leaf's body slot. */
  uint32_t slot;
} F3dTreeNode;

/* A dynamic tree of boxes, balanced by rotations, as Box2D's
 * b2DynamicTree: what finds the pairs near each other, and what queries
 * search. Derived state: not in a snapshot, built again after a restore. */
typedef struct F3dTree {
  F3dTreeNode *nodes;
  uint32_t capacity;
  int32_t root;
  int32_t free_list;
  uint32_t leaves;
} F3dTree;

/* How far past a body's box its leaf reaches, m: it moves inside that
 * before the tree has to move it. */
#define F3D_FAT_MARGIN F3D_R(0.1)

int32_t f3d_tree_insert(F3dTree *tree, F3dBox box, uint32_t slot);
void f3d_tree_remove(F3dTree *tree, int32_t leaf);
void f3d_tree_clear(F3dTree *tree);

/* Calls [visit] for every leaf whose box overlaps [box]; stops early when
 * it returns nought. */
void f3d_tree_query(const F3dTree *tree, F3dBox box,
                    int (*visit)(void *context, int32_t leaf), void *context);


static inline int f3d_box_overlap(F3dBox a, F3dBox b) {
  return a.lo.x <= b.hi.x && b.lo.x <= a.hi.x && a.lo.y <= b.hi.y &&
         b.lo.y <= a.hi.y && a.lo.z <= b.hi.z && b.lo.z <= a.hi.z;
}



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
  /* The inertia tensor in the body's own axes, and its inverse — nought
   * where the body does not turn. Diagonal for every shape but a hull. */
  F3dSym3 inertia;
  F3dSym3 inverse_inertia;
  /* The hull it is shaped as, one past its index in the world's table;
   * nought for none. */
  uint32_t hull;
  /* How far its shape is rounded out, m: the shape grown by a ball of this
   * radius. */
  f3d_real rounding;
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
  /* Coulomb's coefficient, and the share of the approach speed that comes
   * back. */
  f3d_real friction;
  f3d_real restitution;
  /* What it is, and what it meets: a pair collides when each one's layer is
   * in the other's mask. */
  uint32_t layer;
  uint32_t mask;
} F3dSlot;

typedef struct F3dEventRecord {
  F3dBody body;
  /* The other body, for an event between two; nought otherwise. */
  F3dBody other;
  uint32_t kind;
  uint32_t reserved;
} F3dEventRecord;

/* A convex hull: its vertices and triangles in the world's two arrays,
 * what one kilogram of it weighs into its inertia, and how it was moved to
 * put its centre of mass at the body's origin. Plain data. */
typedef struct F3dHull {
  uint32_t first_vertex, vertex_count;
  uint32_t first_triangle, triangle_count;
  /* Subtracted from every point it was made from. */
  F3dVec3 offset;
  /* Its box in its own frame. */
  F3dVec3 lo, hi;
  f3d_real volume;
  f3d_real surface;
  /* The inertia tensor of a kilogram of it, about its centre. */
  F3dSym3 unit_inertia;
} F3dHull;

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
  /* How near counts as a contact. */
  f3d_real contact_margin;
  /* Manifolds the last step found, in order of their pair. */
  uint32_t manifold_count;
  /* How many substeps a step is solved in. */
  uint32_t substeps;
  /* The hulls, and the vertices and triangles they hold. */
  uint32_t hull_count;
  uint32_t hull_vertex_count;
  uint32_t hull_triangle_count;
} F3dWorldState;

struct F3dWorld {
  F3dWorldState s;
  F3dSlot *slots;
  uint32_t capacity;
  /* Three reals a sample. */
  f3d_real *grid;
  /* A ring of F3D_EVENT_CAPACITY, allocated with the first event. */
  F3dEventRecord *events;
  /* The last step's manifolds, manifold_count of them, and room for the
   * next step's beside them. */
  F3dManifold *manifolds;
  F3dManifold *next_manifolds;
  uint32_t manifold_capacity;
  uint32_t next_capacity;
  /* The hulls: headers, vertices three reals each, triangles three indices
   * into their hull's vertices each. In a snapshot. */
  F3dHull *hulls;
  f3d_real *hull_vertices;
  uint32_t *hull_triangles;
  /* The broadphase, and each slot's leaf in it (-1 for none), as long as
   * the arena. Neither is in a snapshot. */
  F3dTree tree;
  int32_t *proxies;
  uint32_t proxy_capacity;
  /* Scratch the collision stage grows and keeps, so a step allocates only
   * when the world grows. None of it outlives a step. */
  void *scratch;
  size_t scratch_bytes;
};

/* The slot [body] names in [world], or null for a stale or foreign one. */
F3dSlot *f3d_slot_of(const F3dWorld *world, F3dBody body);

F3dBody f3d_handle_of(const F3dWorld *world, const F3dSlot *slot);

/* Brings a body's inertia, surface and drag up to date with its shape and
 * mass. */
void f3d_refresh_mass(const F3dWorld *world, F3dSlot *slot);

void f3d_push_event(F3dWorld *world, F3dBody body, uint32_t kind);
void f3d_push_pair_event(F3dWorld *world, F3dBody body, F3dBody other,
                         uint32_t kind);

/* Wakes a body, raising its event when it slept. */
void f3d_wake(F3dWorld *world, F3dSlot *slot);

/* A body's box, as tight as its shape, grown by [margin] on every side. */
F3dBox f3d_box_of(const F3dWorld *world, const F3dSlot *slot, f3d_real margin);

/* Brings every body's leaf up to date: made for a body that has a shape,
 * moved for one that left its fat box, taken out for one that is gone or
 * has none. */
void f3d_update_proxies(F3dWorld *world);

/* A shape's placement, from its slot. */
F3dPlaced f3d_placed_of(const F3dWorld *world, const F3dSlot *slot);

/* The general narrow phase, for any two shapes: GJK between their cores,
 * EPA where the cores overlap, and the manifold from their faces. */
uint32_t f3d_collide_convex(const F3dPlaced *a, const F3dPlaced *b,
                            f3d_real margin, F3dManifold *out);

/* Whether anything can turn the body: a shape with inertia, dynamic, not
 * locked. */
int f3d_turns(const F3dSlot *slot);

/* One substep of [h] seconds of a dynamic body's velocity — gravity, the
 * bus's forces and torques, the wind's drag, damping — and of its position
 * and orientation; and the end of a step for any body — the bus spent and
 * the sleep clock run. */
void f3d_integrate_velocity(const F3dWorld *world, F3dSlot *slot, f3d_real h);
void f3d_integrate_position(F3dSlot *slot, f3d_real h);
void f3d_finish_motion(const F3dWorld *world, F3dSlot *slot, f3d_real dt);

/* [bytes] of the world's scratch, kept between steps and grown when it is
 * not enough; null when it cannot grow. One stage's at a time. */
void *f3d_scratch(F3dWorld *world, size_t bytes);

/* The step's stages: contacts where the bodies stand, the solver's
 * substeps, heat. */
void f3d_step_collide(F3dWorld *world);
void f3d_step_solve(F3dWorld *world, f3d_real dt);
void f3d_step_heat(F3dWorld *world, f3d_real dt);

#endif /* F3D_INTERNAL_H_ */
