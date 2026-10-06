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

/* 32-bit x86 does its arithmetic on the x87 by default, in registers
 * wider than an f32 or an f64 and rounded when they are stored, so the
 * same step lands on other bits than everywhere else (csrc/tests/
 * test_digest.c caught all seven of its scenes). SSE2 rounds every
 * operation as IEEE 754 says; without it this build refuses. */
#if (defined(__i386__) && !defined(__SSE2_MATH__)) || \
    (defined(_M_IX86) && (!defined(_M_IX86_FP) || _M_IX86_FP < 2))
#error "32-bit x86 must do its arithmetic in SSE2: build with -msse2 -mfpmath=sse (MSVC: /arch:SSE2)"
#endif

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
  /* Which of a pair's manifolds: nought, or one for the second face a
   * mesh or a compound meets it with — a box in a corner of a room, a
   * table's leg against a wall while it stands on the floor. */
  uint32_t part;
  F3dContactPoint points[F3D_MANIFOLD_POINTS];
} F3dManifold;

/* The most manifolds two bodies have: one a face. */
#define F3D_PAIR_MANIFOLDS 2u

/* A shape where it stands, as the narrow phase reads it. */
/* A shape no body has: one triangle of a mesh, as the narrow phase reads
 * it, its three corners in the world in [vertices]. */
#define F3D_SHAPE_TRIANGLE 15u

typedef struct F3dPlaced {
  uint32_t kind;
  F3dVec3 size;
  F3dVec3 at;
  F3dMat3 axes;
  /* How far the shape is rounded out. */
  f3d_real rounding;
  /* A hull's vertices and triangles, and their counts; null for the rest.
   * A triangle's three corners. */
  const struct F3dHull *hull;
  const f3d_real *vertices;
  const uint32_t *triangles;
  /* A mesh, its tree, and its edges' flags. */
  const struct F3dMesh *mesh;
  const struct F3dTree *mesh_tree;
  const uint8_t *edge_flags;
  /* A compound, its parts, and the world whose hulls they name. */
  const struct F3dCompound *compound;
  const struct F3dCompoundPart *parts;
  const struct F3dWorld *world;
} F3dPlaced;

/* Fills [out]'s normal and points for [a] against [b], within [margin],
 * and returns how many points; nought when they are further apart. The
 * normal points out of b into a. */
/* As f3d_collide, but where a mesh or a compound meets the other shape with
 * two faces at once it gives each its own manifold: up to
 * F3D_PAIR_MANIFOLDS of them in [out], their number returned. */
uint32_t f3d_collide_pair(const F3dPlaced *a, const F3dPlaced *b,
                          f3d_real margin, F3dManifold *out);

/* Of [found] points, each with the normal of the face that made it: the
 * deepest one's normal and the points that agree with it to eighteen
 * degrees into [out], and, when [second] is not null, the deepest of the
 * rest's normal and the points that agree with that into [second]. Four
 * at most each. Only a point [faces] marks may start the second — a
 * mesh's edge contacts, on seams the first face's points already hold,
 * must not — and null marks every point. */
void f3d_join_points(F3dVec3 *pts, const F3dVec3 *normals, f3d_real *depth,
                     uint32_t *ids, const uint8_t *faces, uint32_t found,
                     F3dManifold *out, F3dManifold *second);

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
  /* Swept for its time of impact after the solve: a bullet does not pass
   * through a wall however thin, at any speed. */
  F3D_FLAG_BULLET = 1u << 4,
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

/* Calls [visit] for every leaf whose box the segment from [origin] along
 * [dir] for up to *[limit] crosses, nearest box first where it can; [visit]
 * may shorten *[limit] to cut what is left. */
void f3d_tree_ray(const F3dTree *tree, F3dVec3 origin, F3dVec3 dir,
                  f3d_real *limit,
                  int (*visit)(void *context, int32_t leaf), void *context);

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
  /* The hull or mesh it is shaped as, one past its index in the world's
   * table of them; nought for none. */
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
  /* A compound's parts' heat: the first of them in the world's lumps plus
   * one, and how many; nought while it has none of its own yet. */
  uint32_t lumps;
  uint32_t lump_count;
} F3dSlot;

/* One part of a compound as heat sees it: what a body is to heat, a part
 * at a time, so a beam can burn from one end. Plain data. */
typedef struct F3dLump {
  f3d_real temperature, heat, water, fuel, mass, heat_release;
  uint32_t burning;
  uint32_t reserved;
} F3dLump;

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

/* A triangle mesh: its vertices and triangles in the world's arrays, a
 * byte of flags a triangle — bit k set when its edge from corner k to the
 * next is internal, shared with a neighbour across a flat or hollow fold —
 * and its box. Plain data. */
typedef struct F3dMesh {
  uint32_t first_vertex, vertex_count;
  uint32_t first_triangle, triangle_count;
  F3dVec3 lo, hi;
  f3d_real surface;
} F3dMesh;

/* One part of a compound: a shape placed and turned in the compound's
 * frame, which has its centre of mass at the origin. Plain data. */
typedef struct F3dCompoundPart {
  uint32_t kind;
  /* One past the hull's index, for a hull; nought for the rest. */
  uint32_t hull;
  F3dVec3 size;
  f3d_real rounding;
  F3dVec3 at;
  F3dQuat turn;
  /* How far the part reaches from [at]: what a pair of parts is skipped
   * by when their spheres do not meet. */
  f3d_real reach;
} F3dCompoundPart;

/* A compound: its parts in the world's array, what a kilogram of it weighs
 * into its inertia, and how its parts were moved to put the centre of mass
 * at the body's origin. Plain data. */
typedef struct F3dCompound {
  uint32_t first_part, part_count;
  F3dVec3 offset;
  /* Its box in its own frame. */
  F3dVec3 lo, hi;
  f3d_real volume;
  f3d_real surface;
  F3dSym3 unit_inertia;
} F3dCompound;

/* One wheel: what it was made as, what the driver asks of it, and what the
 * last step left it. Plain data. */
typedef struct F3dWheel {
  F3dVec3 attach;
  f3d_real rest, radius, stiffness, damping, grip;
  f3d_real steer, drive, brake;
  uint32_t touching;
  f3d_real length, rotation, spin, force, lateral, skid;
  F3dVec3 centre, normal;
} F3dWheel;

/* A vehicle's slot. Plain data, zeroed when taken. */
typedef struct F3dVehicleSlot {
  uint32_t live;
  uint32_t wheel_count;
  F3dBody chassis;
  F3dVec3 up, forward;
  F3dWheel wheels[F3D_VEHICLE_MOST_WHEELS];
} F3dVehicleSlot;

/* One link of a multibody. Plain data. */
typedef struct F3dLink {
  F3dBody body;
  uint32_t parent;
  uint32_t type;
  /* Where its degrees of freedom start among the multibody's, and how
   * many: nought, one or three. */
  uint32_t first_dof, dofs;
  uint32_t flags;
  /* Where the joint holds the parent and the link, each in its own frame;
   * the axis in the parent's frame; and the link's turn relative to the
   * parent when the joint is at nought. */
  F3dVec3 parent_anchor, child_anchor, axis;
  F3dQuat reference;
  /* A revolute or prismatic joint's coordinate and speed; a spherical
   * one's turn in the parent's frame and spin relative to it. */
  f3d_real q, qd;
  F3dQuat turn;
  F3dVec3 spin;
  f3d_real lower, upper, motor_speed, motor_force;
  /* A spherical link's cone: how far its axis swings from the parent's,
   * and how far it twists about itself, radians. */
  f3d_real swing, twist;
} F3dLink;

/* One spring of a water. Plain data. */
typedef struct F3dWaterSource {
  f3d_real x, z, radius, rate;
} F3dWaterSource;

/* A water's slot: its grid, where its reals start in the world's array of
 * them, and its springs. Plain data, zeroed when taken.
 *
 * Its reals, in order: the ground at each cell's centre, nx × nz; the
 * depth at each, nx × nz; the velocity across each x face, (nx + 1) × nz;
 * across each z face, nx × (nz + 1); and the volume bodies fill in each
 * column, nx × nz. */
typedef struct F3dWaterSlot {
  uint32_t live;
  uint32_t nx, nz;
  uint32_t first;
  f3d_real cell;
  F3dVec3 origin;
  f3d_real roughness;
  uint32_t open_edges;
  f3d_real lost;
  uint32_t source_count;
  F3dWaterSource sources[F3D_WATER_MOST_SOURCES];
} F3dWaterSlot;

/* A drop of spray in flight. Plain data. */
typedef struct F3dSpray {
  F3dVec3 at, velocity;
  f3d_real volume;
  uint32_t water;
} F3dSpray;

/* A multibody's slot. Plain data, zeroed when taken. */
typedef struct F3dMultibodySlot {
  uint32_t live;
  uint32_t link_count;
  uint32_t dof_count;
  /* One for a dynamic root, with six degrees of freedom first. */
  uint32_t floating;
  F3dLink links[F3D_MULTIBODY_MOST_LINKS];
} F3dMultibodySlot;

/* Bits of F3dJointSlot.flags. */
enum {
  F3D_JOINT_LIMIT = 1u << 0,
  F3D_JOINT_MOTOR = 1u << 1,
  F3D_JOINT_SPRING = 1u << 2,
  F3D_JOINT_COLLIDE = 1u << 3,
  /* A spherical joint's swing held inside a cone. */
  F3D_JOINT_CONE = 1u << 4,
  F3D_JOINT_FRICTION = 1u << 5,
};

/* One joint's arena slot. Plain data, zeroed when taken: a snapshot copies
 * it whole, warm-start impulses and all. */
typedef struct F3dJointSlot {
  uint32_t generation;
  uint32_t next_free;
  uint8_t live;
  uint8_t type;
  uint8_t flags;
  uint8_t reserved;
  F3dBody a, b;
  /* Where it holds each body, in that body's frame. */
  F3dVec3 local_a, local_b;
  /* Its axis in A's frame, and the same axis in B's. */
  F3dVec3 axis_a, axis_b;
  /* B's turn relative to A's when it was made: what "no angle" is. */
  F3dQuat reference;
  f3d_real lower, upper;
  f3d_real motor_speed, motor_force;
  f3d_real spring_hertz, spring_damping;
  /* A distance joint's rest, least and most length. */
  f3d_real length, least, most;
  /* What it pushed with, per substep: its locked directions, solved as
   * one block — up to three of the point and three of the turn — then the
   * limits, the motor, the spring. */
  f3d_real impulse[6];
  f3d_real lower_impulse, upper_impulse, motor_impulse, spring_impulse;
  /* The linear impulse it put on B over the last substep, in the world. */
  F3dVec3 pushed;
  /* A spherical joint's cone: the most B's axis may swing from A's, and
   * what holding it pushed with. */
  f3d_real cone;
  f3d_real cone_impulse;
  /* A spherical joint's friction: the most torque it resists turning
   * with, N m, and what it pushed with about the world's axes. */
  f3d_real friction;
  F3dVec3 friction_impulse;
  /* What it lets go past, N and N m; nought for never. */
  f3d_real break_force, break_torque;
  /* The angular impulse its locked turns put on B over the last substep,
   * in the world. */
  F3dVec3 turned;
} F3dJointSlot;

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
  /* 1 while contacts reach as far as a body moves in a step. */
  uint32_t speculative;
  /* Manifolds the last step found, in order of their pair. */
  uint32_t manifold_count;
  /* How many substeps a step is solved in. */
  uint32_t substeps;
  /* The hulls, and the vertices and triangles they hold. */
  uint32_t hull_count;
  uint32_t hull_vertex_count;
  uint32_t hull_triangle_count;
  /* The meshes, and the vertices and triangles they hold. */
  uint32_t mesh_count;
  uint32_t mesh_vertex_count;
  uint32_t mesh_triangle_count;
  /* The joints' arena, as the bodies'. */
  uint32_t joint_used;
  uint32_t joint_live;
  uint32_t joint_free_head;
  /* The last substep's length, s: what a joint's impulse is divided by to
   * say its force. */
  f3d_real last_substep;
  /* 1 in the fast mode: contacts solved a colour at a time, in parallel. */
  uint32_t fast;
  /* The compounds, and the parts they hold. */
  uint32_t compound_count;
  uint32_t compound_part_count;
  /* Vehicles ever made. */
  uint32_t vehicle_count;
  /* Multibodies ever made, and how many links all the live ones have
   * beside their roots: what the collision filter counts. */
  uint32_t multibody_count;
  uint32_t multibody_links;
  /* Compounds' parts' heat, every live compound's in slot order. */
  uint32_t lump_count;
  /* Waters ever made, the reals all the live ones hold, and the spray in
   * flight. */
  uint32_t water_count;
  uint32_t water_reals;
  uint32_t spray_count;
} F3dWorldState;

/* ------------------------------------------------------------------- pool */

/* The most threads a world steps on. */
#define F3D_MAX_THREADS 64u

typedef struct F3dPool F3dPool;

/* A pass's share of [begin, end), run by worker [worker]. */
typedef void (*F3dTask)(void *context, uint32_t worker, uint32_t begin, uint32_t end);

/* [threads] workers, the caller one of them: null for fewer than two, more
 * than F3D_MAX_THREADS, no memory, threads that would not start, or the
 * WebAssembly build. */
F3dPool *f3d_pool_create(uint32_t threads);
void f3d_pool_destroy(F3dPool *pool);

/* How many workers [pool] has; one for none. */
uint32_t f3d_pool_size(const F3dPool *pool);

/* Runs [task] over [count] items, split evenly among the workers, and
 * returns once every share is done; on the caller alone when [pool] is
 * null. */
void f3d_pool_run(F3dPool *pool, uint32_t count, F3dTask task, void *context);

/* A barrier the workers of one pass meet at, spinning: the stages of a
 * step that must each finish before the next begins, inside one pass. */
typedef struct F3dBarrier {
  volatile uint32_t arrived;
  volatile uint32_t sense;
  uint32_t workers;
} F3dBarrier;

void f3d_barrier_init(F3dBarrier *barrier, uint32_t workers);

/* Waits until all the barrier's workers have come; [sense] is the caller's
 * own, nought to begin with, and flips each time. */
void f3d_barrier_wait(F3dBarrier *barrier, uint32_t *sense);

/* What one worker gathers in a pass, kept between steps so it need not
 * grow again. */
typedef struct F3dLane {
  void *items;
  size_t capacity;
  uint32_t count;
  int failed;
} F3dLane;

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
  /* The meshes likewise, with a byte of edge flags a triangle; and a tree
   * of each mesh's triangles, built from them, not in a snapshot. */
  F3dMesh *meshes;
  f3d_real *mesh_vertices;
  uint32_t *mesh_triangles;
  uint8_t *mesh_edges;
  F3dTree *mesh_trees;
  uint32_t mesh_tree_count;
  /* The compounds and their parts. In a snapshot. */
  F3dCompound *compounds;
  F3dCompoundPart *compound_parts;
  /* The vehicles, vehicle_count of them. In a snapshot. */
  F3dVehicleSlot *vehicles;
  /* The multibodies, multibody_count of them. In a snapshot. */
  F3dMultibodySlot *multibodies;
  /* The lumps, lump_count of them. In a snapshot. */
  F3dLump *lumps;
  /* The waters, their reals and their spray. In a snapshot. */
  F3dWaterSlot *waters;
  f3d_real *water_data;
  F3dSpray *spray;
  /* The joints, and the pairs of slots joined by a joint that keeps them
   * from colliding, sorted: built from the joints when they change, not in
   * a snapshot. */
  F3dJointSlot *joints;
  uint32_t joint_capacity;
  uint64_t *joined;
  uint32_t joined_count;
  int joined_stale;
  /* The threads the world steps on, null for the caller alone, and what
   * each gathers. Not in a snapshot: a restored world steps on one. */
  F3dPool *pool;
  F3dLane lanes[F3D_MAX_THREADS];
  /* The broadphase, and each slot's leaf in it (-1 for none), as long as
   * the arena. Neither is in a snapshot. */
  F3dTree tree;
  int32_t *proxies;
  uint32_t proxy_capacity;
  /* Every two slots whose leaves overlap, as pair keys in order: what the
   * pairs are found among, kept from step to step and changed only where
   * a leaf moved. The slots whose leaves moved since, and whether the
   * pairs are to be trusted at all — not after a restore, nor when the
   * moved list could not grow. Neither is in a snapshot. */
  uint64_t *pairs;
  uint32_t pair_count, pair_capacity;
  uint32_t *moved;
  uint32_t moved_count, moved_capacity;
  int pairs_ready;
  /* Each slot's box swept through the step, worked out once a step. */
  F3dBox *swept;
  uint32_t swept_capacity;
  /* Where each bullet stood after each substep of the last step: its
   * path, for the sweep. Rows of substeps + 1 poses. Not in a snapshot. */
  F3dVec3 *bullet_at;
  F3dQuat *bullet_turn;
  uint32_t bullet_capacity;
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
void f3d_update_proxies(F3dWorld *world, f3d_real dt);

/* A body's box grown by [margin], and for an awake body with speculative
 * contacts on, joined to where it will be after [dt] at its velocity: what
 * it can touch this step. */
F3dBox f3d_swept_box(const F3dWorld *world, const F3dSlot *slot,
                     f3d_real margin, f3d_real dt);

/* How far a body reaches from its centre: the half diagonal of its box. */
f3d_real f3d_reach_of(const F3dWorld *world, const F3dSlot *slot);

/* A shape's placement, from its slot. */
F3dPlaced f3d_placed_of(const F3dWorld *world, const F3dSlot *slot);

/* The general narrow phase, for any two shapes: GJK between their cores,
 * EPA where the cores overlap, and the manifold from their faces. */
/* A convex shape against a mesh: the triangles near it from the mesh's
 * tree, each against it, merged into one manifold whose normal points out
 * of the mesh into the shape. */
uint32_t f3d_collide_mesh(const F3dPlaced *mesh, const F3dPlaced *body,
                          f3d_real margin, F3dManifold *out,
                          F3dManifold *second);

/* Builds each mesh's tree that is missing: after a restore, or for a mesh
 * just made. */
void f3d_build_mesh_trees(F3dWorld *world);
void f3d_clear_mesh_trees(F3dWorld *world);

/* The nearest pair of points on p0→p1 and q0→q1, as fractions along each:
 * Ericson's closest points of two segments. */
void f3d_nearest_of_segments(F3dVec3 p0, F3dVec3 p1, F3dVec3 q0, F3dVec3 q1,
                             f3d_real *s, f3d_real *t);

uint32_t f3d_collide_convex(const F3dPlaced *a, const F3dPlaced *b,
                            f3d_real margin, F3dManifold *out);

/* Of many points of one face, the four that hold it best: the deepest, the
 * furthest from it, and the widest either side of the line between. */
void f3d_keep_four(F3dVec3 *p, f3d_real *depth, uint32_t *ids,
                   uint32_t *count, F3dVec3 n);

/* Part [i] of a placed compound, where it stands. */
F3dPlaced f3d_placed_part(const F3dPlaced *compound, uint32_t i);

/* Two shapes, one of them or both compounds: every pair of parts whose
 * spheres meet, joined into one manifold as a mesh's triangles are. */
uint32_t f3d_collide_compound(const F3dPlaced *a, const F3dPlaced *b,
                              f3d_real margin, F3dManifold *out,
                              F3dManifold *second);

/* A shape's volume, m³, inertia about its centre for [mass], and surface,
 * m², as a body of it would have them. For a compound's parts. */
f3d_real f3d_shape_volume(const F3dWorld *world, uint32_t kind, F3dVec3 size,
                          f3d_real rounding, uint32_t hull);
F3dSym3 f3d_shape_inertia(const F3dWorld *world, uint32_t kind, F3dVec3 size,
                          f3d_real rounding, uint32_t hull, f3d_real mass);
f3d_real f3d_shape_surface(const F3dWorld *world, uint32_t kind, F3dVec3 size,
                           f3d_real rounding, uint32_t hull);

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

/* The angle of (x, y), in (−π, π], from a series: the core's own, the same
 * bits everywhere. */
f3d_real f3d_atan2(f3d_real y, f3d_real x);

/* Whether a joint joins the slots [a] and [b] and keeps them from
 * colliding. */
int f3d_joined(F3dWorld *world, uint32_t a, uint32_t b);

/* Builds the joined pairs' table if it is out of date, so that f3d_joined
 * only reads after this: what threads asking at once need. */
void f3d_joined_ready(F3dWorld *world);

/* Takes out every joint on the body in [slot]: called as it goes. */
void f3d_unjoin(F3dWorld *world, uint32_t slot);

/* What the solver holds of each body for a step: where it started, and how
 * hard it is to move — nothing, for a body the solver may not move. */
typedef struct F3dSolverBody {
  F3dVec3 start;
  F3dQuat turn;
  /* A bullet's row in the world's record of where it stood at each
   * substep; -1 for any other body. */
  int32_t bullet;
  f3d_real inverse_mass;
  F3dSym3 inverse_inertia;
} F3dSolverBody;

/* The joints' part of the solver, in each substep: warm-started, then
 * solved with the soft bias or without it. Their anchors and masses are
 * worked out from where the bodies are each time. */
void f3d_warm_joints(F3dWorld *world, const F3dSolverBody *bodies);

/* Every vehicle's wheels, after the contacts and before the solver: their
 * rays cast, and their springs and tyres put on the bus. */
void f3d_step_vehicles(F3dWorld *world, f3d_real dt);

/* The core's own sine and cosine: the same bits everywhere. */
void f3d_sin_cos(f3d_real x, f3d_real *sine, f3d_real *cosine);

/* Every water, before the solver: the bodies in it held up and dragged,
 * the water moved, and its spray flown. */
void f3d_step_water(F3dWorld *world, f3d_real dt);

/* Every multibody, after the solver: its joints read off where its links
 * stand, its links put back where the joints say, and their velocities
 * the nearest the joints allow, its motors and limits then acting. */
void f3d_step_multibodies(F3dWorld *world, f3d_real dt);

/* Takes out every joint that held past its break, at the end of a step. */
void f3d_break_joints(F3dWorld *world);
void f3d_solve_joints(F3dWorld *world, const F3dSolverBody *bodies,
                      f3d_real h, int use_bias);


/* The step's stages: contacts where the bodies stand, the solver's
 * substeps, heat. */
void f3d_step_collide(F3dWorld *world, f3d_real dt);

/* Hard CCD, after the solve: each bullet swept from where the step began to
 * where it ended, and put back at its first time of impact. */
void f3d_step_continuous(F3dWorld *world, const F3dSolverBody *bodies);
void f3d_step_solve(F3dWorld *world, f3d_real dt);
void f3d_step_heat(F3dWorld *world, f3d_real dt);

#endif /* F3D_INTERNAL_H_ */
