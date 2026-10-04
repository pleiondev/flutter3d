/*
 * The physics core of flutter3d, in C11 — P9.
 *
 * One world owns everything it steps: bodies, the contacts between their
 * shapes and the islands those make, the solver that keeps them apart,
 * their heat and fire, the wind they move through, and joints as they
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
#define F3D_ABI_VERSION 9u

#ifdef F3D_REAL_DOUBLE
typedef double f3d_real;
#else
typedef float f3d_real;
#endif

typedef struct F3dWorld F3dWorld;

/* A body: (generation << 32) | slot. Nought is never one. */
typedef uint64_t F3dBody;

/* A joint, named as a body is. */
typedef uint64_t F3dJoint;

typedef enum F3dJointType {
  /* Holds B where it was against A, place and turn. */
  F3D_JOINT_FIXED = 0,
  /* Holds a point of each together; they turn freely about it. */
  F3D_JOINT_SPHERICAL = 1,
  /* A hinge: a point together, turning only about the axis. Limits,
   * motor and spring act on the angle. */
  F3D_JOINT_REVOLUTE = 2,
  /* A slider: no turning, moving only along the axis. Limits, motor and
   * spring act on the travel. */
  F3D_JOINT_PRISMATIC = 3,
  /* Two points held a length apart: a rod, or with its spring on, a
   * spring, or with a spring of nought hertz and a least of nought, a
   * rope. */
  F3D_JOINT_DISTANCE = 4,
} F3dJointType;

typedef enum F3dBodyType {
  /* Moved by gravity, forces, wind and contacts. */
  F3D_BODY_DYNAMIC = 0,
  /* Never moves; infinite mass. It still heats, cools and burns. */
  F3D_BODY_FIXED = 1,
} F3dBodyType;

/* What a body is shaped like: what it collides as, and its inertia, its
 * surface and its drag. */
typedef enum F3dShapeKind {
  /* No extent: does not turn, has no surface, feels no wind. */
  F3D_SHAPE_POINT = 0,
  /* a = radius. */
  F3D_SHAPE_SPHERE = 1,
  /* a, b, c = half extents along the body's x, y and z. */
  F3D_SHAPE_BOX = 2,
  /* a = radius, b = half the length of the straight part, along y. */
  F3D_SHAPE_CAPSULE = 3,
  /* a = radius, b = half its height, along y. */
  F3D_SHAPE_CYLINDER = 4,
  /* a = the base's radius, b = its height, along y, its apex up; its
   * origin at its centre of mass, a quarter of the height above the
   * base. */
  F3D_SHAPE_CONE = 5,
  /* A convex hull the world holds: set with f3d_body_set_hull. */
  F3D_SHAPE_HULL = 6,
  /* A triangle mesh the world holds, for fixed bodies: set with
   * f3d_body_set_mesh. */
  F3D_SHAPE_MESH = 7,
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
  /* W / (m K): how readily heat crosses into what it touches. */
  f3d_real conductivity;
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
  /* Two bodies came to touch, or stopped: the second is the other.
   * Touching is within five millimetres, the overlap the solver leaves a
   * resting body; a contact further out in the margin is neither. */
  F3D_EVENT_CONTACT_BEGAN = 5,
  F3D_EVENT_CONTACT_ENDED = 6,
} F3dEventKind;

/* Reals one body takes in f3d_world_read_transforms: position xyz, then the
 * orientation quaternion xyzw. */
#define F3D_TRANSFORM_FLOATS 7u

/* Reals one fire takes in f3d_world_read_fires: position xyz, then the
 * watts it gives off as hot gas. */
#define F3D_FIRE_FLOATS 4u

/* Reals one contact point takes in f3d_world_read_contacts: the normal
 * xyz, out of the second body into the first, the point xyz halfway
 * between their surfaces, and the depth, positive inside. */
#define F3D_CONTACT_FLOATS 7u

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

/* A convex hull of [count] points, three reals each, for bodies to be
 * shaped as: built here, and moved so its centre of mass, taken as solid,
 * is at the origin — f3d_world_get_hull_offset says by how much. Many
 * bodies can share one; a world keeps its hulls as long as it lives, and
 * they are in its snapshots. Returns the hull, numbered from one; nought
 * for fewer than four points not all in one plane, a point not finite,
 * more than 4096 points, or no memory. */
F3D_API uint32_t f3d_world_create_hull(F3dWorld *world, const f3d_real *points,
                                       uint32_t count);

/* A triangle mesh of [vertex_count] vertices, three reals each, and
 * [triangle_count] triangles, three indices each, wound counter-clockwise
 * seen from the side bodies touch: level geometry, terrain, walls. One
 * sided — a body behind a triangle passes through it — and shared vertices
 * make it whole: two triangles that share an edge by index slide a body
 * across it without a bump, where two that only meet do not. Returns the
 * mesh, numbered from one; nought for no triangles, an index past the
 * vertices, a vertex not finite, more than a million triangles, or no
 * memory. Kept by the world for as long as it lives, in its snapshots. */
F3D_API uint32_t f3d_world_create_mesh(F3dWorld *world,
                                       const f3d_real *vertices,
                                       uint32_t vertex_count,
                                       const uint32_t *indices,
                                       uint32_t triangle_count);

/* How many triangles [mesh] has, and how many of their edges it found
 * internal: shared with a neighbour across a flat or hollow fold. */
F3D_API uint32_t f3d_world_mesh_triangle_count(const F3dWorld *world,
                                               uint32_t mesh);
F3D_API uint32_t f3d_world_mesh_internal_edges(const F3dWorld *world,
                                               uint32_t mesh);

/* What was subtracted from every point of [hull], into out[0..2]. */
F3D_API int f3d_world_get_hull_offset(const F3dWorld *world, uint32_t hull,
                                      f3d_real *out);

/* How many of the points [hull] was made from are its corners. */
F3D_API uint32_t f3d_world_hull_vertex_count(const F3dWorld *world,
                                             uint32_t hull);

/* How many bodies the world holds. */
F3D_API uint32_t f3d_world_body_count(const F3dWorld *world);

/* Advances the world by [dt] seconds. Nothing happens for a dt that is not
 * finite and positive.
 *
 * First the contacts where the bodies stand, what began and ended touching,
 * and the islands that sleep and wake. Then the solver, in substeps of
 * dt / substeps, each as Box2D v3 takes it: every awake dynamic body's
 * velocity integrated, the contacts warm-started from what they pushed
 * with last, solved with a soft bias that pushes overlap out, the bodies
 * moved, and the contacts solved again with no bias; restitution after the
 * last. Then heat.
 *
 * Within a substep, a body moves as before:
 * semi-implicit Euler, as flutter3d_physics steps: the velocity gains gravity, the wind's drag and the forces added
 * since the last step, all times dt, and the spin the torques; then the
 * position gains the new velocity times dt and the orientation turns by the
 * spin, its angular momentum carried through. Every body's heat: what
 * crossed each contact, what
 * the bus brought, the fire's share, convection to the moving air and
 * radiation to it, the water on it boiling off at 373.15 K first. Forces,
 * torques and heat added through the bus are held over every substep and
 * spent by the step. */
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

/* Moves up to [capacity] events, oldest first, into [bodies], [others]
 * (the second body of an event between two, nought for the rest; may be
 * null) and [kinds], and returns how many. What is not read stays for the
 * next call. A contact's handles are as they were when it ended, so one
 * ended by a body's removal names a body no longer there. */
F3D_API uint32_t f3d_world_read_events(F3dWorld *world, F3dBody *bodies,
                                       F3dBody *others, uint32_t *kinds,
                                       uint32_t capacity);

/* How many substeps a step is solved in, one to sixty-four; default 4.
 * More holds tall stacks and fast bodies better and costs that many times
 * the solver. 0 for a count out of range. */
F3D_API int f3d_world_set_substeps(F3dWorld *world, uint32_t substeps);

/* How near two shapes must come to make a contact, m; a contact inside it
 * but not touching has a negative depth. 0 for a margin that is negative
 * or not finite. Default 0.02. */
F3D_API int f3d_world_set_contact_margin(F3dWorld *world, f3d_real margin);

/* Every body whose shape's box overlaps the box from (lx, ly, lz) to
 * (hx, hy, hz), relative to the origin: up to [capacity] of them, those of
 * the lowest slots, written into [out] in slot order. Returns how many
 * there are, which may be more than it wrote. Bodies with no shape are
 * never found. */
F3D_API uint32_t f3d_world_query_box(F3dWorld *world, f3d_real lx, f3d_real ly,
                                     f3d_real lz, f3d_real hx, f3d_real hy,
                                     f3d_real hz, F3dBody *out,
                                     uint32_t capacity);

/* Contact points the last step found, over every pair. */
F3D_API uint32_t f3d_world_contact_count(const F3dWorld *world);

/* Writes up to [capacity] contact points, F3D_CONTACT_FLOATS reals apiece,
 * into [contacts], and each one's two bodies into [pairs] two at a time
 * when that is not null, in order of the pair's slots; returns how many. */
F3D_API uint32_t f3d_world_read_contacts(const F3dWorld *world,
                                         f3d_real *contacts, F3dBody *pairs,
                                         uint32_t capacity);

/* Events dropped because F3D_EVENT_CAPACITY were waiting unread. */
F3D_API uint32_t f3d_world_events_dropped(const F3dWorld *world);

/* ----------------------------------------------------------------- joints */

/* A joint of [type] between [a] and [b], at the anchor (ax, ay, az) and
 * along the axis (ux, uy, uz), both relative to the origin and taken where
 * the bodies are now: what it holds them to is how they stand. The axis is
 * read by the revolute and prismatic joints only. Wakes both. Nought for a
 * body not in the world, a body joined to itself, a value not finite, a
 * revolute or prismatic joint with no axis, or a distance joint, which is
 * f3d_joint_create_distance's. Joined bodies do not collide with each
 * other unless f3d_joint_set_collide says so. */
F3D_API F3dJoint f3d_joint_create(F3dWorld *world, F3dJointType type,
                                  F3dBody a, F3dBody b, f3d_real ax,
                                  f3d_real ay, f3d_real az, f3d_real ux,
                                  f3d_real uy, f3d_real uz);

/* A distance joint from (ax, ay, az) on [a] to (bx, by, bz) on [b], held at
 * the length between them now. */
F3D_API F3dJoint f3d_joint_create_distance(F3dWorld *world, F3dBody a,
                                           F3dBody b, f3d_real ax, f3d_real ay,
                                           f3d_real az, f3d_real bx,
                                           f3d_real by, f3d_real bz);

/* Takes the joint out, waking its bodies. A body's joints go with it. */
F3D_API int f3d_joint_destroy(F3dWorld *world, F3dJoint joint);
F3D_API int f3d_joint_is_valid(const F3dWorld *world, F3dJoint joint);
F3D_API uint32_t f3d_world_joint_count(const F3dWorld *world);

/* Limits on a revolute joint's angle, radians, or a prismatic joint's
 * travel, m: lower no more than upper; [enabled] nought takes them off. */
F3D_API int f3d_joint_set_limits(F3dWorld *world, F3dJoint joint, int enabled,
                                 f3d_real lower, f3d_real upper);

/* A motor driving a revolute or prismatic joint at [speed], rad/s or m/s,
 * with at most [max_force], N m or N. */
F3D_API int f3d_joint_set_motor(F3dWorld *world, F3dJoint joint, int enabled,
                                f3d_real speed, f3d_real max_force);

/* A spring pulling a revolute joint to its starting angle, a prismatic one
 * to its starting place, or a distance joint to its length, at [hertz] and
 * damping ratio [damping]. On a distance joint the spring is what makes it
 * not a rod: at nought hertz it pulls not at all, and only the least and
 * most lengths hold. */
F3D_API int f3d_joint_set_spring(F3dWorld *world, F3dJoint joint, int enabled,
                                 f3d_real hertz, f3d_real damping);

/* A distance joint's rest [length] and the [least] and [most] its spring
 * may stretch it to. */
F3D_API int f3d_joint_set_length(F3dWorld *world, F3dJoint joint,
                                 f3d_real length, f3d_real least,
                                 f3d_real most);

/* Whether the joined bodies collide with each other. */
F3D_API int f3d_joint_set_collide(F3dWorld *world, F3dJoint joint,
                                  int collide);

/* A revolute joint's angle from where it started, radians in (−π, π]; a
 * prismatic joint's travel, m; a distance joint's length, m. 0 for the
 * others. */
F3D_API int f3d_joint_get_value(const F3dWorld *world, F3dJoint joint,
                                f3d_real *out);

/* The force it held B with over the last substep, N, into out[0..2]. */
F3D_API int f3d_joint_get_force(const F3dWorld *world, F3dJoint joint,
                                f3d_real *out);

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

/* The moments of inertia about the body's own axes, kg m², into
 * out[0..2]: the whole tensor for every shape but a hull, which also has
 * products of inertia. */
F3D_API int f3d_body_get_inertia(const F3dWorld *world, F3dBody body,
                                 f3d_real *out);

/* The whole inertia tensor in the body's axes: xx, yy, zz, xy, xz, yz. */
F3D_API int f3d_body_get_inertia_tensor(const F3dWorld *world, F3dBody body,
                                        f3d_real *out);

/* Rounds the body's shape out by [radius]: the shape grown by a ball, so a
 * box gets rounded edges and corners and rolls off them as a real crate
 * does. Its inertia, surface and drag are the shape it rounds out to. 0
 * for a radius negative or not finite, or for a point. */
F3D_API int f3d_body_set_rounding(F3dWorld *world, F3dBody body,
                                  f3d_real radius);

/* Shapes the body as [hull], one f3d_world_create_hull returned. 0 for a
 * hull the world does not hold. */
F3D_API int f3d_body_set_hull(F3dWorld *world, F3dBody body, uint32_t hull);

/* Shapes a fixed body as [mesh]. 0 for a mesh the world does not hold, or
 * a body that is not fixed: an open mesh has no inside to weigh. */
F3D_API int f3d_body_set_mesh(F3dWorld *world, F3dBody body, uint32_t mesh);

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

/* Coulomb's coefficient, nought up; default 0.6. A pair slides on the
 * geometric mean of its two, so either can make it slippery. */
F3D_API int f3d_body_set_friction(F3dWorld *world, F3dBody body,
                                  f3d_real friction);

/* The share of the approach speed that comes back, nought to one; default
 * nought. A pair bounces with the larger of its two, and nothing bounces
 * that met slower than a metre a second. */
F3D_API int f3d_body_set_restitution(F3dWorld *world, F3dBody body,
                                     f3d_real restitution);

/* What the body is, [layer], and what it meets, [mask]: two bodies collide
 * when each one's layer has a bit in the other's mask. Defaults 1 and every
 * bit. */
F3D_API int f3d_body_set_collision_filter(F3dWorld *world, F3dBody body,
                                          uint32_t layer, uint32_t mask);

/* 1 while the body sleeps. Bodies sleep and wake by islands: those joined
 * by their contacts sleep when all of them have been still for the sleep
 * time, and wake together when any of them moves. */
F3D_API int f3d_body_is_asleep(const F3dWorld *world, F3dBody body);

/* Wakes the body, and starts its sleep clock again. */
F3D_API int f3d_body_wake(F3dWorld *world, F3dBody body);

/* ------------------------------------------------------- heat and fire */

/* A material's typical values into [out]. 0 for a kind there is none of. */
F3D_API int f3d_material_preset(F3dMaterialKind kind, F3dMaterial *out);

/* What the body is made of. Its fuel is its mass times the material's
 * fuel fraction, counted from now. 0 for a value out of its range. A fixed
 * body of no thermal mass — no mass and no water — is a reservoir: it gives
 * and takes heat through its contacts and keeps its temperature. */
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
