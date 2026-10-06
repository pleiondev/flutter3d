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
#define F3D_ABI_VERSION 26u

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

/* A vehicle, numbered from one; a number is never given out again. */
typedef uint32_t F3dVehicle;

/* A multibody, numbered as a vehicle is. */
typedef uint32_t F3dMultibody;

/* The most links a multibody has, its root among them, and the most
 * degrees of freedom: a floating root's six and its joints'. */
#define F3D_MULTIBODY_MOST_LINKS 32u
#define F3D_MULTIBODY_MOST_DOFS 64u

/* The most wheels a vehicle has. */
#define F3D_VEHICLE_MOST_WHEELS 8u

/* Reals one wheel takes in f3d_vehicle_add_wheel: where its suspension is
 * fixed to the chassis xyz, in the chassis's frame; the suspension's
 * length at rest, m; the wheel's radius, m; the spring's stiffness, N/m,
 * and its damping, N s/m; and the tyre's grip, the friction coefficient
 * of the road under it. */
#define F3D_WHEEL_FLOATS 8u

/* Reals one wheel takes in f3d_vehicle_read_wheels: one while it touches,
 * nought while it hangs; the suspension's length now; the steering angle;
 * how far the wheel has turned about its axle, radians, and how fast,
 * rad/s; its centre xyz relative to the origin; the normal of what it
 * stands on xyz; the spring's force, N; the speed it slides sideways at,
 * m/s; and how far past its grip the tyre is asked to go, nought while it
 * grips and one where it is asked for twice what it holds. */
#define F3D_WHEEL_STATE_FLOATS 14u

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
  /* Several of the shapes above, each placed and turned in the body's
   * frame, that the world holds: set with f3d_body_set_compound. */
  F3D_SHAPE_COMPOUND = 8,
} F3dShapeKind;

/* Reals one part of a compound takes in f3d_world_create_compound: its
 * size a, b, c as F3dShapeKind reads it, its rounding, its place xyz and
 * its turn as a quaternion xyzw, both in the compound's frame. */
#define F3D_COMPOUND_PART_FLOATS 11u

/* The most parts one compound holds. */
#define F3D_COMPOUND_MOST_PARTS 64u

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
  /* A joint held past what f3d_joint_set_break allows it and let go: the
   * event names its two bodies, the joint is gone. */
  F3D_EVENT_JOINT_BROKEN = 7,
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

/* A compound of [count] parts, each a sphere, box, capsule, cylinder, cone
 * or hull: its kind in [kinds], its hull in [hulls] (read only for a hull,
 * and null allowed when there is none), and F3D_COMPOUND_PART_FLOATS reals
 * in [parts]. The parts are taken as one solid of even density, overlaps
 * counted twice, and moved together so its centre of mass is at the
 * origin — f3d_world_get_compound_offset says by how much. Its contacts
 * are every part's against the other shape, joined into the pair's one
 * manifold along the deepest part's normal, as a mesh's triangles are.
 * Returns the compound, numbered from one; nought for no parts, more than
 * F3D_COMPOUND_MOST_PARTS, a kind not listed, a size, a place or a turn not
 * finite, a size a shape of that kind refuses, a hull not in the world, or
 * no memory. Kept by the world for as long as it lives, in its
 * snapshots. */
F3D_API uint32_t f3d_world_create_compound(F3dWorld *world,
                                           const uint32_t *kinds,
                                           const uint32_t *hulls,
                                           const f3d_real *parts,
                                           uint32_t count);

/* What was subtracted from every part's place in [compound], into
 * out[0..2]. */
F3D_API int f3d_world_get_compound_offset(const F3dWorld *world,
                                          uint32_t compound, f3d_real *out);

/* How many parts [compound] has. */
F3D_API uint32_t f3d_world_compound_part_count(const F3dWorld *world,
                                               uint32_t compound);

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

/* Steps the world on [threads] threads, the caller one of them, from the
 * next step on: the tree's queries and the narrow phase split among them.
 * The world steps to the same bits on any number. 0 for none, more than
 * 64, or threads that would not start, leaving it as it was; in the
 * WebAssembly build, 0 for more than one. Not in a snapshot. */
F3D_API int f3d_world_set_threads(F3dWorld *world, uint32_t threads);
F3D_API uint32_t f3d_world_threads(const F3dWorld *world);

/* The fast mode, off for a new world: the contacts coloured each step so
 * that no two of a colour share a moving body, and solved a colour at a
 * time, each colour's contacts at once on every thread, the stages of a
 * step met at barriers. Solved in another order than the deterministic
 * mode's, so to other bits — but to the same bits on any number of
 * threads. In a snapshot. */
F3D_API int f3d_world_set_fast(F3dWorld *world, int fast);
F3D_API int f3d_world_fast(const F3dWorld *world);

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

/* Soft continuous collision, on by default: a contact reaches as far as
 * its two bodies can close in a step, so a body stops at a wall it would
 * cross in one. 0 turns it off. */
F3D_API int f3d_world_set_speculative(F3dWorld *world, int enabled);

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

/* --------------------------------------------------------------- vehicles */

/* A vehicle on [chassis]: wheels that hang from it on springs, each a ray
 * cast down from where its suspension is fixed, its tyre gripping the road
 * where the ray lands. (ux, uy, uz) is the chassis's up and (fx, fy, fz) its
 * forward, both in its own frame: a wheel's suspension runs along the
 * down, it steers about the up and rolls along the forward. Each step,
 * after the contacts and before the solver, every wheel that touches
 * pushes the chassis up by its spring and damper, along the road by its
 * drive and brake, and across it to hold it from sliding sideways, as much
 * as the grip times the spring's force allows together; what it stands on
 * is pushed back, when that moves. A chassis asleep stays so until it is
 * given a wheel's input. Nought for a chassis not in the world or not
 * dynamic, axes not finite, nought long or not square to each other, or no
 * memory. In a snapshot. */
F3D_API F3dVehicle f3d_vehicle_create(F3dWorld *world, F3dBody chassis,
                                      f3d_real ux, f3d_real uy, f3d_real uz,
                                      f3d_real fx, f3d_real fy, f3d_real fz);

/* Takes the vehicle out; its chassis stays. A vehicle whose chassis is
 * taken out goes with it. */
F3D_API int f3d_vehicle_destroy(F3dWorld *world, F3dVehicle vehicle);
F3D_API int f3d_vehicle_is_valid(const F3dWorld *world, F3dVehicle vehicle);

/* Adds a wheel of F3D_WHEEL_FLOATS reals; returns its index from nought,
 * or -1 for a vehicle not in the world, one with F3D_VEHICLE_MOST_WHEELS
 * already, or a value not finite, a length negative, or a radius, a
 * stiffness or a grip not positive, or a damping negative. */
F3D_API int f3d_vehicle_add_wheel(F3dWorld *world, F3dVehicle vehicle,
                                  const f3d_real *wheel);

/* What the driver asks of wheel [wheel]: its steering angle, radians about
 * the up, positive to the left of forward; the force its drive pushes
 * along the road with, N, negative backwards; and the force its brake
 * holds with, N, not negative. Held until set again. Wakes the chassis. */
F3D_API int f3d_vehicle_set_wheel(F3dWorld *world, F3dVehicle vehicle,
                                  uint32_t wheel, f3d_real steer,
                                  f3d_real drive, f3d_real brake);

/* How many wheels the vehicle has. */
F3D_API uint32_t f3d_vehicle_wheel_count(const F3dWorld *world,
                                         F3dVehicle vehicle);

/* Writes up to [capacity] wheels, F3D_WHEEL_STATE_FLOATS reals apiece, as
 * the last step left them, into [out]; returns how many. */
F3D_API uint32_t f3d_vehicle_read_wheels(const F3dWorld *world,
                                         F3dVehicle vehicle, f3d_real *out,
                                         uint32_t capacity);

/* ------------------------------------------------------------- multibodies */

/* A multibody rooted at [root]: a tree of bodies held to each other by
 * joints in reduced coordinates — each link's place is its parent's and
 * its joint's angle or travel, and nothing else — so however long the chain
 * and however heavy its end, no joint comes apart. A fixed root is a fixed
 * base: a crane, a robot arm, a chain from a ceiling; a dynamic root
 * floats, with six degrees of freedom of its own: a ragdoll, a vehicle
 * with a trailer.
 *
 * The links stay ordinary bodies: they collide, sleep together, and are in
 * snapshots. Each step the solver moves them as it moves every body,
 * contacts and all; then the multibody reads its joints' coordinates off
 * where they stand, puts every link back where those coordinates say, and
 * replaces their velocities with the nearest the joints allow — weighted
 * by every link's mass and inertia — before its motors and limits act on
 * the joints' speeds. A link does not collide with its parent.
 *
 * The root is link nought. Nought for a body not in the world, or one that
 * is a link already, or no memory. */
F3D_API F3dMultibody f3d_multibody_create(F3dWorld *world, F3dBody root);
F3D_API int f3d_multibody_destroy(F3dWorld *world, F3dMultibody multibody);
F3D_API int f3d_multibody_is_valid(const F3dWorld *world,
                                   F3dMultibody multibody);

/* Adds [body] as a link under link [parent], held by a joint of [type] —
 * fixed, revolute, prismatic or spherical — at the anchor (ax, ay, az) and
 * along the axis (ux, uy, uz), both relative to the origin and taken where
 * the bodies stand now, which is the joint's nought. Returns the link's
 * index, or -1 for a multibody or a parent not there, a body not dynamic
 * or a link already, a type it does not take, a value not finite, an axis
 * of nought for a revolute or prismatic joint, or a multibody with
 * F3D_MULTIBODY_MOST_LINKS links or F3D_MULTIBODY_MOST_DOFS degrees of
 * freedom already. */
F3D_API int f3d_multibody_add_link(F3dWorld *world, F3dMultibody multibody,
                                   uint32_t parent, F3dBody body,
                                   F3dJointType type, f3d_real ax, f3d_real ay,
                                   f3d_real az, f3d_real ux, f3d_real uy,
                                   f3d_real uz);

/* Limits on a revolute link's angle, radians, or a prismatic link's
 * travel, m; [enabled] nought takes them off. 0 for another kind of link,
 * or a lower above the upper. */
F3D_API int f3d_multibody_set_limits(F3dWorld *world, F3dMultibody multibody,
                                     uint32_t link, int enabled,
                                     f3d_real lower, f3d_real upper);

/* A motor on a revolute or prismatic link: it drives the joint's speed
 * towards [speed], rad/s or m/s, with at most [force], N m or N.
 * [enabled] nought takes it off. */
F3D_API int f3d_multibody_set_motor(F3dWorld *world, F3dMultibody multibody,
                                    uint32_t link, int enabled,
                                    f3d_real speed, f3d_real force);

/* A cone on a spherical link: its axis — the one given when it was added —
 * swings at most [swing] from where the parent holds it, in (0, π], and the
 * link twists about that axis at most [twist] either way, in [0, π].
 * [enabled] nought takes it off. 0 for another kind of link, or a value out
 * of range. */
F3D_API int f3d_multibody_set_cone(F3dWorld *world, F3dMultibody multibody,
                                   uint32_t link, int enabled, f3d_real swing,
                                   f3d_real twist);

/* How many links, and how many degrees of freedom. */
F3D_API uint32_t f3d_multibody_link_count(const F3dWorld *world,
                                          F3dMultibody multibody);
F3D_API uint32_t f3d_multibody_dof_count(const F3dWorld *world,
                                         F3dMultibody multibody);

/* Link [link]'s joint as the last step left it, into out[0..7]: for a
 * revolute or prismatic joint its angle or travel and its speed, the rest
 * nought; for a spherical joint its turn as a quaternion xyzw in the
 * parent's frame and its spin xyz relative to the parent, in the world;
 * nought for a fixed joint and the root. */
F3D_API int f3d_multibody_read_joint(const F3dWorld *world,
                                     F3dMultibody multibody, uint32_t link,
                                     f3d_real *out);

/* ----------------------------------------------------------------- joints */

/* A joint of [type] between [a] and [b], at the anchor (ax, ay, az) and
 * along the axis (ux, uy, uz), both relative to the origin and taken where
 * the bodies are now: what it holds them to is how they stand. The axis is
 * the hinge's or the slider's, or the one a spherical joint's cone and twist
 * are measured about; a fixed joint does not read it. Wakes both. Nought for a
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

/* Limits on a revolute joint's angle, radians, a prismatic joint's travel,
 * m, or a spherical joint's twist about its axis, radians: lower no more
 * than upper; [enabled] nought takes them off. */
F3D_API int f3d_joint_set_limits(F3dWorld *world, F3dJoint joint, int enabled,
                                 f3d_real lower, f3d_real upper);

/* A spherical joint's swing held inside a cone: B's axis no more than
 * [angle] radians, above nought and at most π, from A's — a shoulder, a
 * hip, a neck. With twist limits it is a ragdoll's joint. */
F3D_API int f3d_joint_set_cone(F3dWorld *world, F3dJoint joint, int enabled,
                               f3d_real angle);

/* A spherical joint's friction: B turning against A resisted with at most
 * [torque], N m, nought or more — what lets a ragdoll come to rest. A
 * revolute or prismatic joint has it as a motor of speed nought. */
F3D_API int f3d_joint_set_friction(F3dWorld *world, F3dJoint joint,
                                   int enabled, f3d_real torque);

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
 * spherical joint's twist about its axis, the same way; a prismatic
 * joint's travel, m; a distance joint's length, m. 0 for the others. */
F3D_API int f3d_joint_get_value(const F3dWorld *world, F3dJoint joint,
                                f3d_real *out);

/* A spherical joint's swing: the angle between B's axis and A's, radians
 * from nought to π. 0 for the others. */
F3D_API int f3d_joint_get_swing(const F3dWorld *world, F3dJoint joint,
                                f3d_real *out);

/* The force it held B with over the last substep, N, into out[0..2]. */
/* How hard the joint may hold before it lets go: [force], N, all it pushes
 * B with as f3d_joint_get_force says it, and [torque], N m, what its
 * locked turns hold B with as f3d_joint_get_torque says it. At
 * the end of a step that held past either, the joint is taken out, its
 * bodies woken, and F3D_EVENT_JOINT_BROKEN raised. Nought for either is
 * never; a new joint breaks on neither. 0 for a value negative or not
 * finite. */
F3D_API int f3d_joint_set_break(F3dWorld *world, F3dJoint joint,
                                f3d_real force, f3d_real torque);

/* The torque the joint held B's locked turns with over the last substep,
 * N m, in the world, into out[0..2]. */
F3D_API int f3d_joint_get_torque(const F3dWorld *world, F3dJoint joint,
                                 f3d_real *out);

F3D_API int f3d_joint_get_force(const F3dWorld *world, F3dJoint joint,
                                f3d_real *out);

/* ---------------------------------------------------------------- queries */

/* Reals one hit takes: the point xyz and the normal xyz there, out of what
 * was hit, both relative to the origin, then the distance along the ray or
 * the fraction of the cast. */
#define F3D_HIT_FLOATS 7u

/* What a query sees: bodies whose layer has a bit in [mask], all but
 * [ignore] (nought ignores nothing). A body with no shape is never seen. A
 * ray or cast that starts inside a shape does not see it; a cast does, at
 * nought, when it starts overlapping. */

/* The nearest body a ray meets from (ox, oy, oz) along (dx, dy, dz) within
 * [max_distance] — the direction need not be a unit — into [body] and
 * [hit]; 1 when it meets one. Meshes are seen from their front only. */
F3D_API int f3d_world_ray_cast(F3dWorld *world, f3d_real ox, f3d_real oy,
                               f3d_real oz, f3d_real dx, f3d_real dy,
                               f3d_real dz, f3d_real max_distance,
                               uint32_t mask, F3dBody ignore, F3dBody *body,
                               f3d_real *hit);

/* Every body the ray meets, nearest first, up to [capacity] of them into
 * [bodies] and [hits]; returns how many it meets. */
F3D_API uint32_t f3d_world_ray_cast_all(F3dWorld *world, f3d_real ox,
                                        f3d_real oy, f3d_real oz, f3d_real dx,
                                        f3d_real dy, f3d_real dz,
                                        f3d_real max_distance, uint32_t mask,
                                        F3dBody ignore, F3dBody *bodies,
                                        f3d_real *hits, uint32_t capacity);

/* Every body overlapping a shape of [kind] — a sphere, box, capsule,
 * cylinder or cone, a, b, c as for a body — rounded by [rounding], at
 * (px, py, pz) turned by the quaternion (qx, qy, qz, qw): up to [capacity]
 * of them, in slot order; returns how many. */
F3D_API uint32_t f3d_world_overlap_shape(
    F3dWorld *world, F3dShapeKind kind, f3d_real a, f3d_real b, f3d_real c,
    f3d_real rounding, f3d_real px, f3d_real py, f3d_real pz, f3d_real qx,
    f3d_real qy, f3d_real qz, f3d_real qw, uint32_t mask, F3dBody ignore,
    F3dBody *out, uint32_t capacity);

/* The first body that shape meets moved by (tx, ty, tz) without turning,
 * into [body] and [hit] with the fraction of the move it got; 1 when it
 * meets one. */
F3D_API int f3d_world_cast_shape(F3dWorld *world, F3dShapeKind kind,
                                 f3d_real a, f3d_real b, f3d_real c,
                                 f3d_real rounding, f3d_real px, f3d_real py,
                                 f3d_real pz, f3d_real qx, f3d_real qy,
                                 f3d_real qz, f3d_real qw, f3d_real tx,
                                 f3d_real ty, f3d_real tz, uint32_t mask,
                                 F3dBody ignore, F3dBody *body, f3d_real *hit);

/* ------------------------------------------------------------- characters */

/* Bits of what f3d_world_move_character returns. */
#define F3D_CHARACTER_GROUNDED 1u
#define F3D_CHARACTER_WALL 2u
#define F3D_CHARACTER_CEILING 4u
#define F3D_CHARACTER_STEPPED 8u

/* Bits of the options f3d_world_move_character takes. */
/* It stood on ground before this move, and may climb a step: a body in the
 * air does not step up onto a ledge it brushes past. */
#define F3D_CHARACTER_MAY_STEP 1u

/* Moves an upright shape — a character: [kind] and its sizes a, b, c as
 * f3d_world_cast_shape takes them, a capsule's radius and straight half
 * height or a box's half extents — from position[0..2] by (dx, dy, dz), sliding along what it
 * meets, and writes where it ends into position. velocity[0..2] is the
 * character's, in and out: the speed into everything it met is taken out
 * of it, as the speed into a wall is gone for good. Ground is what it
 * stands on whose normal's height is at least [max_slope_cos]; steeper is
 * wall, which it slides along and does not climb. With
 * F3D_CHARACTER_MAY_STEP in [options], a move that met something tries a
 * step up to [step_height] and keeps it only if it got further along
 * (dx, dz) than sliding did — only when a wall stopped it, and not when
 * something overhead stops the lift — writing how far it was lifted into
 * [stepped_up]; it keeps to ground it is walking down within that height.
 * It starts by moving out of anything it is inside, along the deepest
 * overlap's normal, the speed into it taken out too. The ground's normal goes into ground[0..2] and its body into
 * [ground_body] (nought when in the air). Returns F3D_CHARACTER_ bits.
 * A body on a layer in [from_above] is a floor from above and nothing else:
 * met only with a normal whose height is at least [max_slope_cos], and not
 * when it starts inside one — passed through jumping up into it, walking
 * into its side, or falling on from inside it.
 * Kinematic: nothing pushes it, and it moves nothing. */
F3D_API uint32_t f3d_world_move_character(
    F3dWorld *world, F3dShapeKind kind, f3d_real a, f3d_real b, f3d_real c,
    f3d_real *position,
    f3d_real dx, f3d_real dy, f3d_real dz, f3d_real *velocity,
    f3d_real max_slope_cos, f3d_real step_height, uint32_t mask,
    uint32_t from_above, uint32_t options, F3dBody ignore, F3dBody *ground_body,
    f3d_real *ground, f3d_real *stepped_up);

/* -------------------------------------------------------------- particles */

/* Particles: sparks, spray, dust, smoke — many points that fall, drift in
 * the wind, bounce off a floor and die. Visual, not part of the game's
 * state: the GPU steps the same system in f3d_gpu.h, and this one is its
 * reference and the fallback where there is none. A fixed number of slots,
 * filled round and round: a new particle takes the next slot, the oldest
 * first; a slot whose life has run out is still and waits. */
typedef struct F3dParticles F3dParticles;

/* Reals one particle takes in f3d_particles_read: position xyz, then the
 * life it has left, s, nought or less when dead. */
#define F3D_PARTICLE_FLOATS 4u

/* How particles move: gravity, the wind they drift towards at [drag] per
 * second, and a floor at height [floor_y] they bounce off with
 * [restitution] and lose [friction] of their sliding speed on. */
typedef struct F3dParticleForces {
  f3d_real gravity[3];
  f3d_real wind[3];
  f3d_real drag;
  f3d_real floor_y;
  f3d_real restitution;
  f3d_real friction;
} F3dParticleForces;

/* [capacity] slots, all dead; null for none or no memory. */
F3D_API F3dParticles *f3d_particles_create(uint32_t capacity);
F3D_API void f3d_particles_destroy(F3dParticles *particles);
F3D_API uint32_t f3d_particles_capacity(const F3dParticles *particles);

/* [count] particles into the next slots: each its position xyz, velocity
 * xyz, and life, seven reals. Returns the slot the first went into. */
F3D_API uint32_t f3d_particles_emit(F3dParticles *particles,
                                    const f3d_real *particles_data,
                                    uint32_t count);

/* Steps every living particle by [dt]: its velocity gains gravity, drifts
 * towards the wind as v' = w + (v + g dt − w) / (1 + drag dt), its
 * position gains the velocity, and below the floor it is put back on it,
 * its fall turned back by the restitution and its slide slowed by the
 * friction; its life loses dt. */
F3D_API void f3d_particles_step(F3dParticles *particles,
                                const F3dParticleForces *forces, f3d_real dt);

/* Every slot, F3D_PARTICLE_FLOATS reals apiece, into [out]: up to
 * [capacity]; returns how many. */
F3D_API uint32_t f3d_particles_read(const F3dParticles *particles,
                                    f3d_real *out, uint32_t capacity);

/* ----------------------------------------------------------------- debris */

/* Debris: the visual bodies — rubble, shards, crates' splinters, the
 * thousands of things a blast throws that nobody steers and nothing in the
 * game reads. Balls, each with its own size and mass, that fall, knock into
 * each other, roll and come to rest on still planes and boxes. The GPU
 * steps the same system in f3d_gpu.h and is read a frame late; this one is
 * its reference and the fallback where there is none.
 *
 * Each substep finds contacts through a hashed grid of cells as wide as
 * three of the largest radii, and solves them all at once from the same
 * velocities — Jacobi, every body splitting its mass among its contacts so
 * a heap does not blow up — then moves and turns the bodies. A fixed
 * number of slots, filled round and round; a slot of radius nought is
 * empty. */
typedef struct F3dDebris F3dDebris;

/* Reals one body takes in f3d_debris_add: position xyz, velocity xyz,
 * radius, mass. */
#define F3D_DEBRIS_INPUT_FLOATS 8u
/* Reals one body takes in f3d_debris_read: position xyz, orientation
 * xyzw, radius. */
#define F3D_DEBRIS_FLOATS 8u
/* Reals one still shape takes in f3d_debris_set_statics: a plane as its
 * normal xyz and its offset along it, then 0, 0, 0, 0; a box, unturned, as
 * its centre xyz and 0, then its half extents xyz and 1. */
#define F3D_DEBRIS_STATIC_FLOATS 8u
#define F3D_DEBRIS_MAX_STATICS 64u

typedef struct F3dDebrisSettings {
  f3d_real gravity[3];
  f3d_real friction;
  /* Applied when two close faster than 1 m/s. */
  f3d_real restitution;
  /* Per second, as v / (1 + c dt). */
  f3d_real linear_damping;
  f3d_real angular_damping;
  /* No body is let faster than this. */
  f3d_real max_speed;
  /* At least one each: substeps a step, and impulse passes a substep. */
  uint32_t substeps;
  uint32_t iterations;
} F3dDebrisSettings;

/* [capacity] empty slots; null for none or no memory. */
F3D_API F3dDebris *f3d_debris_create(uint32_t capacity);
F3D_API void f3d_debris_destroy(F3dDebris *debris);
F3D_API uint32_t f3d_debris_capacity(const F3dDebris *debris);

/* [count] bodies into the next slots, F3D_DEBRIS_INPUT_FLOATS reals apiece,
 * unturned; a radius or mass of nought or less empties the slot. Returns
 * the slot the first went into. */
F3D_API uint32_t f3d_debris_add(F3dDebris *debris, const f3d_real *data,
                                uint32_t count);

/* The still shapes, replacing the last; 0 when there are more than
 * F3D_DEBRIS_MAX_STATICS. */
F3D_API int f3d_debris_set_statics(F3dDebris *debris, const f3d_real *data,
                                   uint32_t count);

F3D_API void f3d_debris_step(F3dDebris *debris,
                             const F3dDebrisSettings *settings, f3d_real dt);

/* Every slot, F3D_DEBRIS_FLOATS reals apiece, into [out]: up to
 * [capacity]; returns how many. */
F3D_API uint32_t f3d_debris_read(const F3dDebris *debris, f3d_real *out,
                                 uint32_t capacity);

/* ------------------------------------------------------------------ cloth */

/* Cloth: points held at their distances by constraints — XPBD in small
 * steps, one pass over the constraints a substep. The constraints are
 * coloured when the cloth is made, so that no two of a colour share a
 * point, and solved colour by colour: the GPU steps the same cloth in
 * f3d_gpu.h a colour a dispatch, with nothing summed in any order, and
 * this one is its reference and the fallback where there is none. Points
 * collide with balls, a floor, and nothing else — not each other.
 * f3d_cloth_solve, further down, steps the same cloth as the Dart
 * reference does, against obstacles of every shape and itself. */
typedef struct F3dCloth F3dCloth;

/* Reals one point takes, in f3d_cloth_create and f3d_cloth_read: position
 * xyz and inverse mass, nought for a point pinned where it is. */
#define F3D_CLOTH_FLOATS 4u
#define F3D_CLOTH_MAX_BALLS 16u

typedef struct F3dClothSettings {
  f3d_real gravity[3];
  /* The air's velocity, and how fast a point drifts to it, per second. */
  f3d_real wind[3];
  f3d_real drag;
  /* Per second, as v / (1 + c dt). */
  f3d_real damping;
  f3d_real floor_y;
  /* How far from a ball or the floor a point is held. */
  f3d_real thickness;
  /* The part of a touching point's slide taken away each substep. */
  f3d_real friction;
  /* At least one. */
  uint32_t substeps;
} F3dClothSettings;

/* A cloth of [point_count] points, F3D_CLOTH_FLOATS reals apiece, held by
 * [edge_count] constraints: the pairs of points in [edges], each held at
 * the distance it starts at with its own compliance, m/N (nought: rigid).
 * Null for no points, a point out of range, an edge from a point to
 * itself, or no memory. */
F3D_API F3dCloth *f3d_cloth_create(const f3d_real *points, uint32_t point_count,
                                   const uint32_t *edges, const f3d_real *compliance,
                                   uint32_t edge_count);
F3D_API void f3d_cloth_destroy(F3dCloth *cloth);
F3D_API uint32_t f3d_cloth_point_count(const F3dCloth *cloth);

/* How many colours the constraints took. */
F3D_API uint32_t f3d_cloth_colour_count(const F3dCloth *cloth);
F3D_API uint32_t f3d_cloth_edge_count(const F3dCloth *cloth);

/* The constraints as they are solved, colour by colour: each one's pair of
 * points into [pairs], its length into [rest] and its compliance into
 * [compliance], edge-count apiece; where each colour starts into
 * [colour_start], colour-count and one. What the GPU's cloth is made
 * from, so the colouring is done in one place. */
F3D_API void f3d_cloth_edges(const F3dCloth *cloth, uint32_t *pairs, f3d_real *rest,
                             f3d_real *compliance, uint32_t *colour_start);

/* The balls, x y z radius apiece, replacing the last; 0 when more than
 * F3D_CLOTH_MAX_BALLS. */
F3D_API int f3d_cloth_set_balls(F3dCloth *cloth, const f3d_real *balls, uint32_t count);

/* Puts point [index] at [x y z], still: how a pinned point is carried. */
F3D_API void f3d_cloth_move_point(F3dCloth *cloth, uint32_t index, f3d_real x,
                                  f3d_real y, f3d_real z);

/* Each substep: gravity, damping and the wind into the velocity, the
 * points moved by it, every constraint colour by colour, the balls and the
 * floor, and the velocity from where the points went. */
F3D_API void f3d_cloth_step(F3dCloth *cloth, const F3dClothSettings *settings,
                            f3d_real dt);

/* Every point, F3D_CLOTH_FLOATS reals apiece, into [out]: up to
 * [capacity]; returns how many. */
F3D_API uint32_t f3d_cloth_read(const F3dCloth *cloth, f3d_real *out, uint32_t capacity);

/* The same cloth stepped as flutter3d_physics's stepCloth steps a
 * ClothMesh, for a run whose cloth is on the core: f3d_cloth_solve below.
 * Where f3d_cloth_step makes one pass a substep, as the GPU does, this one
 * makes as many as it is asked, each multiplier kept across them; damps a
 * fraction a substep; blows on triangles along their normals; keeps the
 * sheet's own layers apart; and pushes the points out of obstacles of
 * every shape the reference meets, with friction measured against the
 * substep's whole push. The two answers are close, not equal: the
 * constraints go colour by colour here and kind by kind there, in f32. */

/* Reals one point takes in f3d_cloth_write_state and f3d_cloth_read_state:
 * position xyz, velocity xyz, inverse mass. */
#define F3D_CLOTH_STATE_FLOATS 7u

/* What each obstacle record of f3d_cloth_set_obstacles starts with, and
 * what follows, in reals:
 *   F3D_CLOTH_BALL     x y z radius
 *   F3D_CLOTH_CAPSULE  x y z radius half_height, upright
 *   F3D_CLOTH_CONVEX   count, then count planes nx ny nz d, solid where
 *                      n · p <= d and the normals outwards: a box, a wedge
 *   F3D_CLOTH_GROUND   x y z of sample (0, 0) at height nought, cell,
 *                      columns, rows, how deep below the surface it is
 *                      solid, then columns × rows heights row by row along
 *                      +x, rows along +z, each quad split from (0, 0) to
 *                      (1, 1) */
#define F3D_CLOTH_BALL 0u
#define F3D_CLOTH_CAPSULE 1u
#define F3D_CLOTH_CONVEX 2u
#define F3D_CLOTH_GROUND 3u

typedef struct F3dClothSolveSettings {
  f3d_real gravity[3];
  /* The air's velocity, and how hard it pushes: N per m² of a triangle per
   * m/s of air through it along its normal. Nought: no wind. */
  f3d_real wind[3];
  f3d_real wind_drag;
  /* The fraction of a point's velocity taken away each substep. */
  f3d_real damping;
  /* How far outside an obstacle a point is held. */
  f3d_real thickness;
  /* Of a point's slide along an obstacle, how much each substep's push
   * may take back: Coulomb at position level. */
  f3d_real friction;
  /* How close two points not that close in the rest shape may come;
   * nought lets the layers pass through each other. */
  f3d_real self_thickness;
  /* The part of two touching points' slide taken away as they part. */
  f3d_real self_friction;
  /* At least one each, or the step does nothing. */
  uint32_t substeps;
  uint32_t iterations;
} F3dClothSolveSettings;

/* The triangles the wind blows on and a round obstacle keeps outside it,
 * three corners apiece, replacing the last; 0, and none kept, when a corner
 * is out of range or there is no memory. */
F3D_API int f3d_cloth_set_triangles(F3dCloth *cloth, const uint32_t *corners,
                                    uint32_t count);

/* The rest shape self-collision asks which points are neighbours, xyz a
 * point: two closer there than the self-thickness are left to their
 * constraints. Where the points were made, until this is called. */
F3D_API void f3d_cloth_set_rest(F3dCloth *cloth, const f3d_real *xyz);

/* Every constraint's compliance, m/N, in the order f3d_cloth_create was
 * given them. */
F3D_API void f3d_cloth_set_compliance(F3dCloth *cloth, const f3d_real *compliance);

/* Every constraint's length, in the same order: for a cloth whose rest
 * lengths are not the distances it was made at. */
F3D_API void f3d_cloth_set_lengths(F3dCloth *cloth, const f3d_real *length);

/* The obstacles, [length] reals of records laid out as above, replacing
 * the last; 0, and the last kept, for a record of no kind, cut short, or
 * a ground of fewer than two by two samples or no cell, or no memory. */
F3D_API int f3d_cloth_set_obstacles(F3dCloth *cloth, const f3d_real *records,
                                    uint32_t length);

/* Every point's position, velocity and inverse mass, F3D_CLOTH_STATE_FLOATS
 * reals apiece, from [state], or into it. */
F3D_API void f3d_cloth_write_state(F3dCloth *cloth, const f3d_real *state);
F3D_API void f3d_cloth_read_state(const F3dCloth *cloth, f3d_real *state);

/* Each substep: damping, gravity and the wind into a predicted position;
 * then [iterations] times the constraints colour by colour, the layers
 * apart and the points out of the obstacles; friction against what the
 * obstacles pushed; and the velocity from where the points went. Pinned
 * points, of inverse mass nought, are not moved. */
F3D_API void f3d_cloth_solve(F3dCloth *cloth, const F3dClothSolveSettings *settings,
                             f3d_real dt);

/* ------------------------------------------------------------------ fluid */

/* Fluid: water as particles, position-based (PBF) — each held near the
 * density at rest of a cubic lattice of [spacing], with a kernel twice the
 * spacing wide, inside a tank. The GPU steps the same fluid in f3d_gpu.h;
 * this one is its reference and the fallback where there is none. Only
 * ever pushed apart, never pulled together: no clumping, and no surface
 * tension either. */
typedef struct F3dFluid F3dFluid;

/* Reals one particle takes in f3d_fluid_add: position xyz, velocity xyz. */
#define F3D_FLUID_INPUT_FLOATS 6u
/* Reals one particle takes in f3d_fluid_read: position xyz, and its
 * density over the density at rest. */
#define F3D_FLUID_FLOATS 4u

typedef struct F3dFluidSettings {
  f3d_real gravity[3];
  /* The tank's corners: no particle centre comes nearer its walls than
   * half the spacing. */
  f3d_real tank_min[3];
  f3d_real tank_max[3];
  /* XSPH: how far a particle's velocity goes to its neighbours' a substep. */
  f3d_real viscosity;
  /* Softens the density constraint; larger is softer and steadier. */
  f3d_real relaxation;
  /* At least one each: substeps a step, density passes a substep. */
  uint32_t substeps;
  uint32_t iterations;
} F3dFluidSettings;

/* Room for [capacity] particles [spacing] apart at rest; null for none, a
 * spacing not above nought, or no memory. */
F3D_API F3dFluid *f3d_fluid_create(uint32_t capacity, f3d_real spacing);
F3D_API void f3d_fluid_destroy(F3dFluid *fluid);
F3D_API uint32_t f3d_fluid_capacity(const F3dFluid *fluid);

/* The density at rest, in particles of mass one per cubic metre. */
F3D_API f3d_real f3d_fluid_rest_density(const F3dFluid *fluid);

/* [count] particles, F3D_FLUID_INPUT_FLOATS reals apiece, into the next
 * slots, round and round once full. Returns the slot the first went in. */
F3D_API uint32_t f3d_fluid_add(F3dFluid *fluid, const f3d_real *data, uint32_t count);

F3D_API void f3d_fluid_step(F3dFluid *fluid, const F3dFluidSettings *settings, f3d_real dt);

/* Every particle added, F3D_FLUID_FLOATS reals apiece, into [out]: up to
 * [capacity]; returns how many. */
F3D_API uint32_t f3d_fluid_read(const F3dFluid *fluid, f3d_real *out, uint32_t capacity);

/* ----------------------------------------------------------------- liquid */

/* The parts of flutter3d_physics's liquids that are stepped through time,
 * for a run whose fluid is on the core: what its FluidSolver does. The
 * Dart side keeps the books — how much liquid is where, what is dissolved
 * in it, which vessel caught what — and hands these the state of one step,
 * moved in place. Nothing is kept between calls.
 *
 *   f3d_liquid_particles  spilt liquid as position-based fluid particles:
 *                         cohesion and curvature, the density held from
 *                         where each step starts and where it ends, XSPH's
 *                         viscosity, against the walls in pieces;
 *   f3d_liquid_parcels    a stream's parcels in the air: falling, running
 *                         along and clinging to walls, their ripples grown;
 *   f3d_liquid_modes      a free surface's modes, each a damped oscillator
 *                         stepped exactly, held under Stokes' limit;
 *   f3d_liquid_pipes      the column of liquid in a pipe between vessels,
 *                         driven by the pressure across it;
 *   f3d_liquid_floats     bodies floating in it, lifted and dragged.
 *
 * Close to the Dart reference, not equal to it: f32 here, and neighbours
 * summed in another order. */

/* What each wall record starts with, and what follows, in reals:
 *   F3D_LIQUID_PLANE    nx ny nz offset: clear where n · p >= offset
 *   F3D_LIQUID_INSIDE   the inside of a vessel turned from a profile about
 *   F3D_LIQUID_OUTSIDE  its y axis, or its outside: x y z of the vessel, its
 *                       turn as nine reals column by column, the glass's
 *                       thickness, the profile's floor, top, widest radius
 *                       and radius at the floor, count, then count points
 *                       radius height from the middle of the floor up the
 *                       side to the mouth */
#define F3D_LIQUID_PLANE 0u
#define F3D_LIQUID_INSIDE 1u
#define F3D_LIQUID_OUTSIDE 2u

/* Reals one particle takes: position xyz, velocity xyz. */
#define F3D_LIQUID_PARTICLE_FLOATS 6u

typedef struct F3dLiquidParticleSettings {
  f3d_real gravity[3];
  /* The spacing at rest; the kernel reaches twice that. */
  f3d_real spacing;
  /* kg / m³, and m² / s. */
  f3d_real density;
  f3d_real kinematic_viscosity;
  /* Akinci's cohesion coefficient; the density kernel summed over the rest
   * lattice; and Σ|∇C|² over it, for the artificial pressure. */
  f3d_real cohesion;
  f3d_real lattice_sum;
  f3d_real rest_stiffness;
  /* Seconds a substep, and how many. */
  f3d_real dt;
  uint32_t substeps;
  /* Density passes a substep. */
  uint32_t iterations;
} F3dLiquidParticleSettings;

/* Moves [count] particles, F3D_LIQUID_PARTICLE_FLOATS reals apiece, on by
 * the settings' substeps against the walls, [length] reals of records laid
 * out as above. 1, or 0 and nothing moved for a record of no kind or cut
 * short, or no memory. */
F3D_API int f3d_liquid_particles(f3d_real *state, uint32_t count, const f3d_real *walls,
                                 uint32_t length, const F3dLiquidParticleSettings *settings);

/* Reals one parcel takes: position xyz, velocity xyz, the position it
 * started the step at xyz (written), volume, the step it left the lip in,
 * age, growth, on a wall (1) or not (0), and its liquid's density, surface
 * tension and viscosity. */
#define F3D_LIQUID_PARCEL_FLOATS 17u

typedef struct F3dLiquidStreamSettings {
  f3d_real gravity[3];
  f3d_real dt;
  /* σ(1 + cos θ) / ρ of the stream's liquid: a parcel off a wall is held
   * to it while slower than the root of this over its thickness. */
  f3d_real cling;
} F3dLiquidStreamSettings;

/* Flies [count] parcels, F3D_LIQUID_PARCEL_FLOATS reals apiece, on by one
 * step against the walls; 1, or 0 and nothing moved as for particles. */
F3D_API int f3d_liquid_parcels(f3d_real *parcels, uint32_t count, const f3d_real *walls,
                               uint32_t length, const F3dLiquidStreamSettings *settings);

/* Reals one mode takes: k², the most it stands anywhere per unit
 * amplitude, amplitude, rate, and (written) ω² and the decay rate it rang
 * at. */
#define F3D_LIQUID_MODE_FLOATS 6u

typedef struct F3dLiquidWaveSettings {
  f3d_real dt;
  /* The gravity felt, m/s², and the liquid's mean depth. */
  f3d_real g;
  f3d_real depth;
  f3d_real kinematic_viscosity;
  /* σ / ρ. */
  f3d_real tension;
  /* The surface's area, for the round vessel it damps as. */
  f3d_real area;
} F3dLiquidWaveSettings;

/* Rings [count] modes, F3D_LIQUID_MODE_FLOATS reals apiece, the lowest
 * first, on by the settings' step. */
F3D_API void f3d_liquid_modes(f3d_real *modes, uint32_t count,
                              const F3dLiquidWaveSettings *settings);

/* Reals one pipe takes: the flow from its first vessel to its second
 * (moved), the pressure at its first end less at its second, how deep each
 * end is under its surface, each vessel's surface area, its bore and
 * length, the liquid's density and viscosity, and the loss where it enters
 * and leaves in velocity heads. */
#define F3D_LIQUID_PIPE_FLOATS 11u

/* Drives [count] pipes on by [dt]: each column accelerated by the pressure
 * across it over its inertance, held back implicitly by Hagen–Poiseuille's
 * friction and its end losses; nothing through an end above its surface. */
F3D_API void f3d_liquid_pipes(f3d_real *pipes, uint32_t count, f3d_real dt);

/* Reals one floating body takes: velocity xyz (moved), inverse mass; and
 * one push: which body, its shape (F3D_LIQUID_SPHERE: radius; _BOX: half
 * extents; _CAPSULE: radius, half height, upright; _OTHER: none), three
 * sizes, the volume of it under the surface, and the liquid's density and
 * viscosity. */
#define F3D_LIQUID_BODY_FLOATS 4u
#define F3D_LIQUID_PUSH_FLOATS 8u
#define F3D_LIQUID_SPHERE 0u
#define F3D_LIQUID_BOX 1u
#define F3D_LIQUID_CAPSULE 2u
#define F3D_LIQUID_OTHER 3u

typedef struct F3dLiquidFloatSettings {
  f3d_real gravity[3];
  f3d_real dt;
} F3dLiquidFloatSettings;

/* Applies [count] pushes in order to [bodies]: each lifts its body by the
 * weight of the liquid it displaces, then slows it by the drag of the part
 * under, implicitly, with White's sphere coefficient. 1, or 0 and nothing
 * moved for a body out of range or a shape of no kind. */
F3D_API int f3d_liquid_floats(f3d_real *bodies, uint32_t body_count, const f3d_real *pushes,
                              uint32_t count, const F3dLiquidFloatSettings *settings);

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

/* Shapes the body as [compound], one f3d_world_create_compound returned:
 * its mass spread through the parts, its inertia theirs about the centre
 * of mass. A body's rounding rounds every part further. 0 for a compound
 * the world does not hold. */
F3D_API int f3d_body_set_compound(F3dWorld *world, F3dBody body,
                                  uint32_t compound);

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

/* Hard continuous collision for [body]: after the solve it is swept from
 * where the step began to where it ended against every body but another
 * bullet, and put back at its first time of impact, its velocity kept. For
 * what is small and fast — a bullet, a puck — and what soft collision might
 * still let through, and what spins fast enough to turn through a wall in
 * one step. Its turn is swept with it. */
F3D_API int f3d_body_set_bullet(F3dWorld *world, F3dBody body, int bullet);

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
