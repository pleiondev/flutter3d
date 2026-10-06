/*
 * Joints — P9, phase 7: fixed, spherical, revolute, prismatic and distance
 * joints, with limits, motors and springs, solved in the same soft substeps
 * as the contacts, as Box2D v3 solves them.
 *
 * Each joint is a set of constraints on the relative motion of its two
 * bodies at their anchors: a point held together, turning locked about two
 * axes or three, travel locked across an axis, a length. In each substep
 * the anchors and axes are taken from where the bodies stand, the masses
 * worked out from them, and every constraint solved with the joint's soft
 * spring — at most sixty hertz, a quarter of the substep rate, damping ratio
 * two — and then again with none, as the contacts are. Springs, motors and
 * limits come first, the locks last, so a lock has the last word.
 *
 * A joint's angle needs an arctangent, which the core may not take from a
 * library; it has its own, from a series, the same bits everywhere.
 */
#include "f3d_internal.h"

#define F3D_JOINT_DAMPING F3D_R(2.0)

/* ------------------------------------------------------------- arithmetic */

/* atan(t) for |t| ≤ tan(π/8): the series t − t³/3 + t⁵/5 − …, to well past
 * the real's precision — under 2·10⁻⁸ after eight terms in f32, under
 * 10⁻¹⁵ after sixteen in f64. */
static f3d_real atan_small(f3d_real t) {
#ifdef F3D_REAL_DOUBLE
  const int terms = 18;
#else
  const int terms = 9;
#endif
  const f3d_real t2 = t * t;
  f3d_real sum = F3D_R(0.0), power = t;
  for (int k = 0; k < terms; k++) {
    const f3d_real term = power / (f3d_real)(2 * k + 1);
    sum = (k & 1) ? sum - term : sum + term;
    power *= t2;
  }
  return sum;
}

/* atan(t) for t in [0, 1]: brought under tan(π/8) by
 * atan t = π/4 + atan((t − 1)/(t + 1)). */
static f3d_real atan_unit(f3d_real t) {
  if (t <= F3D_R(0.41421356237309505)) return atan_small(t);
  return F3D_PI / F3D_R(4.0) + atan_small((t - F3D_R(1.0)) / (t + F3D_R(1.0)));
}

/* The angle of (x, y), in (−π, π]. */
f3d_real f3d_atan2(f3d_real y, f3d_real x) {
  const f3d_real ax = f3d_abs(x), ay = f3d_abs(y);
  if (ax == F3D_R(0.0) && ay == F3D_R(0.0)) return F3D_R(0.0);
  f3d_real a = ay <= ax ? atan_unit(ay / ax)
                        : F3D_PI / F3D_R(2.0) - atan_unit(ax / ay);
  if (x < F3D_R(0.0)) a = F3D_PI - a;
  return y < F3D_R(0.0) ? -a : a;
}

static F3dQuat qmul(F3dQuat a, F3dQuat b) {
  F3dQuat q;
  q.x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y;
  q.y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x;
  q.z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w;
  q.w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z;
  return q;
}

static F3dQuat qconj(F3dQuat q) {
  q.x = -q.x;
  q.y = -q.y;
  q.z = -q.z;
  return q;
}

static F3dVec3 turn(const F3dMat3 *m, F3dVec3 v) {
  return f3d_add(f3d_add(f3d_scale(m->c[0], v.x), f3d_scale(m->c[1], v.y)),
                 f3d_scale(m->c[2], v.z));
}

static F3dVec3 unturn(const F3dMat3 *m, F3dVec3 v) {
  return f3d_v3(f3d_dot(m->c[0], v), f3d_dot(m->c[1], v), f3d_dot(m->c[2], v));
}

/* A unit vector square to [n]. */
static F3dVec3 square_to(F3dVec3 n) {
  const F3dVec3 axis = f3d_abs(n.x) < F3D_R(0.57735)
                           ? f3d_v3(F3D_R(1.0), F3D_R(0.0), F3D_R(0.0))
                           : f3d_v3(F3D_R(0.0), F3D_R(1.0), F3D_R(0.0));
  const F3dVec3 t = f3d_cross(n, axis);
  return f3d_scale(t, F3D_R(1.0) / f3d_sqrt(f3d_dot(t, t)));
}

/* ------------------------------------------------------------------ arena */

static F3dJoint handle_of(uint32_t slot, uint32_t generation) {
  return ((uint64_t)generation << 32) | (uint64_t)slot;
}

static F3dJointSlot *joint_of(const F3dWorld *world, F3dJoint joint) {
  const uint32_t slot = (uint32_t)(joint & 0xffffffffu);
  const uint32_t generation = (uint32_t)(joint >> 32);
  if (generation == 0 || slot >= world->s.joint_used) return NULL;
  F3dJointSlot *j = &world->joints[slot];
  return j->live && j->generation == generation ? j : NULL;
}

static uint32_t take_joint(F3dWorld *world) {
  if (world->s.joint_free_head != 0) {
    const uint32_t slot = world->s.joint_free_head - 1u;
    world->s.joint_free_head = world->joints[slot].next_free;
    return slot;
  }
  if (world->s.joint_used == world->joint_capacity) {
    const uint32_t grown =
        world->joint_capacity == 0 ? 16u : world->joint_capacity * 2u;
    if (grown <= world->joint_capacity) return UINT32_MAX;
    F3dJointSlot *joints = (F3dJointSlot *)f3d_realloc(
        world->joints, (size_t)grown * sizeof(F3dJointSlot));
    if (joints == NULL) return UINT32_MAX;
    f3d_zero(joints + world->joint_capacity,
             (size_t)(grown - world->joint_capacity) * sizeof(F3dJointSlot));
    world->joints = joints;
    world->joint_capacity = grown;
  }
  return world->s.joint_used++;
}

static F3dJoint make(F3dWorld *world, F3dJointType type, F3dBody a, F3dBody b,
                     F3dVec3 pa, F3dVec3 pb, F3dVec3 axis) {
  F3dSlot *sa = f3d_slot_of(world, a), *sb = f3d_slot_of(world, b);
  if (sa == NULL || sb == NULL || sa == sb) return 0;
  const uint32_t slot = take_joint(world);
  if (slot == UINT32_MAX) return 0;
  F3dJointSlot *j = &world->joints[slot];
  uint32_t generation = j->generation + 1u;
  if (generation == 0) generation = 1;
  f3d_zero(j, sizeof *j);
  j->generation = generation;
  j->live = 1;
  j->type = (uint8_t)type;
  j->a = a;
  j->b = b;
  const F3dMat3 ra = f3d_mat_of(sa->orientation);
  const F3dMat3 rb = f3d_mat_of(sb->orientation);
  j->local_a = unturn(&ra, f3d_sub(pa, sa->position));
  j->local_b = unturn(&rb, f3d_sub(pb, sb->position));
  j->axis_a = unturn(&ra, axis);
  j->axis_b = unturn(&rb, axis);
  j->reference = qmul(qconj(sa->orientation), sb->orientation);
  const F3dVec3 d = f3d_sub(pb, pa);
  j->length = j->least = j->most = f3d_sqrt(f3d_dot(d, d));
  world->s.joint_live++;
  world->joined_stale = 1;
  f3d_wake(world, sa);
  f3d_wake(world, sb);
  return handle_of(slot, generation);
}

static int finite3(f3d_real x, f3d_real y, f3d_real z) {
  return f3d_finite(x) && f3d_finite(y) && f3d_finite(z);
}

F3dJoint f3d_joint_create(F3dWorld *world, F3dJointType type, F3dBody a,
                          F3dBody b, f3d_real ax, f3d_real ay, f3d_real az,
                          f3d_real ux, f3d_real uy, f3d_real uz) {
  if (type != F3D_JOINT_FIXED && type != F3D_JOINT_SPHERICAL &&
      type != F3D_JOINT_REVOLUTE && type != F3D_JOINT_PRISMATIC) {
    return 0;
  }
  if (!finite3(ax, ay, az) || !finite3(ux, uy, uz)) return 0;
  F3dVec3 axis = f3d_v3(ux, uy, uz);
  const f3d_real len = f3d_sqrt(f3d_dot(axis, axis));
  if (type == F3D_JOINT_REVOLUTE || type == F3D_JOINT_PRISMATIC) {
    if (!(len > F3D_R(1e-12))) return 0;
  }
  axis = len > F3D_R(1e-12) ? f3d_scale(axis, F3D_R(1.0) / len)
                            : f3d_v3(F3D_R(0.0), F3D_R(1.0), F3D_R(0.0));
  const F3dVec3 p = f3d_v3(ax, ay, az);
  return make(world, type, a, b, p, p, axis);
}

F3dJoint f3d_joint_create_distance(F3dWorld *world, F3dBody a, F3dBody b,
                                   f3d_real ax, f3d_real ay, f3d_real az,
                                   f3d_real bx, f3d_real by, f3d_real bz) {
  if (!finite3(ax, ay, az) || !finite3(bx, by, bz)) return 0;
  return make(world, F3D_JOINT_DISTANCE, a, b, f3d_v3(ax, ay, az),
              f3d_v3(bx, by, bz), f3d_v3(F3D_R(0.0), F3D_R(1.0), F3D_R(0.0)));
}

static void wake_both(F3dWorld *world, const F3dJointSlot *j) {
  F3dSlot *sa = f3d_slot_of(world, j->a), *sb = f3d_slot_of(world, j->b);
  if (sa != NULL) f3d_wake(world, sa);
  if (sb != NULL) f3d_wake(world, sb);
}

static void free_joint(F3dWorld *world, F3dJointSlot *j) {
  wake_both(world, j);
  j->live = 0;
  j->next_free = world->s.joint_free_head;
  world->s.joint_free_head = (uint32_t)(j - world->joints) + 1u;
  world->s.joint_live--;
  world->joined_stale = 1;
}

int f3d_joint_destroy(F3dWorld *world, F3dJoint joint) {
  F3dJointSlot *j = joint_of(world, joint);
  if (j == NULL) return 0;
  free_joint(world, j);
  return 1;
}

void f3d_unjoin(F3dWorld *world, uint32_t slot) {
  for (uint32_t i = 0; i < world->s.joint_used; i++) {
    F3dJointSlot *j = &world->joints[i];
    if (!j->live) continue;
    if ((uint32_t)(j->a & 0xffffffffu) == slot ||
        (uint32_t)(j->b & 0xffffffffu) == slot) {
      free_joint(world, j);
    }
  }
}

int f3d_joint_is_valid(const F3dWorld *world, F3dJoint joint) {
  return joint_of(world, joint) != NULL;
}

uint32_t f3d_world_joint_count(const F3dWorld *world) {
  return world->s.joint_live;
}

int f3d_joint_set_limits(F3dWorld *world, F3dJoint joint, int enabled,
                         f3d_real lower, f3d_real upper) {
  F3dJointSlot *j = joint_of(world, joint);
  if (j == NULL) return 0;
  if (j->type != F3D_JOINT_REVOLUTE && j->type != F3D_JOINT_PRISMATIC &&
      j->type != F3D_JOINT_SPHERICAL) {
    return 0;
  }
  if (enabled && !(f3d_finite(lower) && f3d_finite(upper) && lower <= upper)) {
    return 0;
  }
  if (enabled) {
    j->flags |= F3D_JOINT_LIMIT;
    j->lower = lower;
    j->upper = upper;
  } else {
    j->flags &= (uint8_t)~F3D_JOINT_LIMIT;
  }
  j->lower_impulse = j->upper_impulse = F3D_R(0.0);
  wake_both(world, j);
  return 1;
}

int f3d_joint_set_cone(F3dWorld *world, F3dJoint joint, int enabled, f3d_real angle) {
  F3dJointSlot *j = joint_of(world, joint);
  if (j == NULL || j->type != F3D_JOINT_SPHERICAL) return 0;
  if (enabled && !(f3d_finite(angle) && angle > F3D_R(0.0) && angle <= F3D_PI)) return 0;
  if (enabled) {
    j->flags |= F3D_JOINT_CONE;
    j->cone = angle;
  } else {
    j->flags &= (uint8_t)~F3D_JOINT_CONE;
  }
  j->cone_impulse = F3D_R(0.0);
  wake_both(world, j);
  return 1;
}

int f3d_joint_set_friction(F3dWorld *world, F3dJoint joint, int enabled, f3d_real torque) {
  F3dJointSlot *j = joint_of(world, joint);
  if (j == NULL || j->type != F3D_JOINT_SPHERICAL) return 0;
  if (enabled && !(f3d_finite(torque) && torque >= F3D_R(0.0))) return 0;
  if (enabled) {
    j->flags |= F3D_JOINT_FRICTION;
    j->friction = torque;
  } else {
    j->flags &= (uint8_t)~F3D_JOINT_FRICTION;
  }
  j->friction_impulse = f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
  wake_both(world, j);
  return 1;
}

int f3d_joint_set_motor(F3dWorld *world, F3dJoint joint, int enabled,
                        f3d_real speed, f3d_real max_force) {
  F3dJointSlot *j = joint_of(world, joint);
  if (j == NULL) return 0;
  if (j->type != F3D_JOINT_REVOLUTE && j->type != F3D_JOINT_PRISMATIC) return 0;
  if (enabled && !(f3d_finite(speed) && f3d_finite(max_force) &&
                   max_force >= F3D_R(0.0))) {
    return 0;
  }
  if (enabled) {
    j->flags |= F3D_JOINT_MOTOR;
    j->motor_speed = speed;
    j->motor_force = max_force;
  } else {
    j->flags &= (uint8_t)~F3D_JOINT_MOTOR;
    j->motor_impulse = F3D_R(0.0);
  }
  wake_both(world, j);
  return 1;
}

int f3d_joint_set_spring(F3dWorld *world, F3dJoint joint, int enabled,
                         f3d_real hertz, f3d_real damping) {
  F3dJointSlot *j = joint_of(world, joint);
  if (j == NULL) return 0;
  if (j->type == F3D_JOINT_FIXED || j->type == F3D_JOINT_SPHERICAL) return 0;
  if (enabled && !(f3d_finite(hertz) && hertz >= F3D_R(0.0) &&
                   f3d_finite(damping) && damping >= F3D_R(0.0))) {
    return 0;
  }
  if (enabled) {
    j->flags |= F3D_JOINT_SPRING;
    j->spring_hertz = hertz;
    j->spring_damping = damping;
  } else {
    j->flags &= (uint8_t)~F3D_JOINT_SPRING;
    j->spring_impulse = F3D_R(0.0);
  }
  /* A distance joint changing between rod and spring starts its impulses
   * afresh: each holds what the other would not. */
  if (j->type == F3D_JOINT_DISTANCE) {
    j->impulse[0] = F3D_R(0.0);
    j->lower_impulse = j->upper_impulse = F3D_R(0.0);
  }
  wake_both(world, j);
  return 1;
}

int f3d_joint_set_length(F3dWorld *world, F3dJoint joint, f3d_real length,
                         f3d_real least, f3d_real most) {
  F3dJointSlot *j = joint_of(world, joint);
  if (j == NULL || j->type != F3D_JOINT_DISTANCE) return 0;
  if (!(f3d_finite(length) && f3d_finite(least) && f3d_finite(most))) return 0;
  if (!(least >= F3D_R(0.0) && least <= length && length <= most)) return 0;
  j->length = length;
  j->least = least;
  j->most = most;
  wake_both(world, j);
  return 1;
}

int f3d_joint_set_collide(F3dWorld *world, F3dJoint joint, int collide) {
  F3dJointSlot *j = joint_of(world, joint);
  if (j == NULL) return 0;
  if (collide) {
    j->flags |= F3D_JOINT_COLLIDE;
  } else {
    j->flags &= (uint8_t)~F3D_JOINT_COLLIDE;
  }
  world->joined_stale = 1;
  wake_both(world, j);
  return 1;
}

int f3d_joint_set_break(F3dWorld *world, F3dJoint joint, f3d_real force,
                        f3d_real torque) {
  F3dJointSlot *j = joint_of(world, joint);
  if (j == NULL) return 0;
  if (!(f3d_finite(force) && force >= F3D_R(0.0)) ||
      !(f3d_finite(torque) && torque >= F3D_R(0.0))) {
    return 0;
  }
  j->break_force = force;
  j->break_torque = torque;
  return 1;
}

int f3d_joint_get_torque(const F3dWorld *world, F3dJoint joint,
                         f3d_real *out) {
  const F3dJointSlot *j = joint_of(world, joint);
  if (j == NULL) return 0;
  const f3d_real h = world->s.last_substep;
  const f3d_real k = h > F3D_R(0.0) ? F3D_R(1.0) / h : F3D_R(0.0);
  out[0] = j->turned.x * k;
  out[1] = j->turned.y * k;
  out[2] = j->turned.z * k;
  return 1;
}

void f3d_break_joints(F3dWorld *world) {
  const f3d_real h = world->s.last_substep;
  if (!(h > F3D_R(0.0))) return;
  /* In slot order, so the events come out the same on every platform.
   * Compared as impulses: the limit times the substep, squared, against
   * what was pushed, squared — no root, no division. */
  for (uint32_t i = 0; i < world->s.joint_used; i++) {
    F3dJointSlot *j = &world->joints[i];
    if (!j->live) continue;
    const f3d_real most_push = j->break_force * h;
    const f3d_real most_turn = j->break_torque * h;
    const int pushed_past = j->break_force > F3D_R(0.0) &&
                            f3d_dot(j->pushed, j->pushed) > most_push * most_push;
    const int turned_past = j->break_torque > F3D_R(0.0) &&
                            f3d_dot(j->turned, j->turned) > most_turn * most_turn;
    if (!pushed_past && !turned_past) continue;
    const F3dBody a = j->a, b = j->b;
    wake_both(world, j);
    free_joint(world, j);
    f3d_push_pair_event(world, a, b, F3D_EVENT_JOINT_BROKEN);
  }
}

int f3d_joint_get_force(const F3dWorld *world, F3dJoint joint, f3d_real *out) {
  const F3dJointSlot *j = joint_of(world, joint);
  if (j == NULL) return 0;
  const f3d_real h = world->s.last_substep;
  const f3d_real k = h > F3D_R(0.0) ? F3D_R(1.0) / h : F3D_R(0.0);
  out[0] = j->pushed.x * k;
  out[1] = j->pushed.y * k;
  out[2] = j->pushed.z * k;
  return 1;
}

/* ------------------------------------------------------------ the filter */

static void sort_keys(uint64_t *a, uint64_t *spare, uint32_t n) {
  for (uint32_t width = 1; width < n; width *= 2u) {
    for (uint32_t lo = 0; lo < n; lo += 2u * width) {
      const uint32_t mid = lo + width < n ? lo + width : n;
      const uint32_t hi = lo + 2u * width < n ? lo + 2u * width : n;
      uint32_t i = lo, k = mid, o = lo;
      while (i < mid && k < hi) spare[o++] = a[k] < a[i] ? a[k++] : a[i++];
      while (i < mid) spare[o++] = a[i++];
      while (k < hi) spare[o++] = a[k++];
    }
    for (uint32_t o = 0; o < n; o++) a[o] = spare[o];
    if (width > UINT32_MAX / 2u) break;
  }
}

void f3d_joined_ready(F3dWorld *world) {
  if ((world->s.joint_live == 0 && world->s.multibody_links == 0) ||
      !world->joined_stale) {
    return;
  }
  f3d_free(world->joined);
  world->joined = NULL;
  world->joined_count = 0;
  const uint32_t n = world->s.joint_used + world->s.multibody_links;
  uint64_t *keys = (uint64_t *)f3d_alloc((size_t)n * 2u * sizeof(uint64_t) + 8u);
  if (keys == NULL) return;
  uint32_t count = 0;
  /* A multibody's links and their parents, as a joint's two bodies. */
  for (uint32_t m = 0; m < world->s.multibody_count; m++) {
    const F3dMultibodySlot *mb = &world->multibodies[m];
    if (!mb->live) continue;
    for (uint32_t k = 1; k < mb->link_count && count < n; k++) {
      const uint32_t sa = (uint32_t)(mb->links[k].body & 0xffffffffu);
      const uint32_t sb =
          (uint32_t)(mb->links[mb->links[k].parent].body & 0xffffffffu);
      keys[count++] = sa < sb ? ((uint64_t)sa << 32) | sb
                              : ((uint64_t)sb << 32) | sa;
    }
  }
  for (uint32_t i = 0; i < world->s.joint_used; i++) {
    const F3dJointSlot *j = &world->joints[i];
    if (!j->live || (j->flags & F3D_JOINT_COLLIDE)) continue;
    const uint32_t sa = (uint32_t)(j->a & 0xffffffffu);
    const uint32_t sb = (uint32_t)(j->b & 0xffffffffu);
    keys[count++] = sa < sb ? ((uint64_t)sa << 32) | sb
                            : ((uint64_t)sb << 32) | sa;
  }
  sort_keys(keys, keys + n, count);
  world->joined = keys;
  world->joined_count = count;
  world->joined_stale = 0;
}

int f3d_joined(F3dWorld *world, uint32_t a, uint32_t b) {
  if (world->s.joint_live == 0 && world->s.multibody_links == 0) return 0;
  f3d_joined_ready(world);
  if (world->joined_stale) return 0;
  const uint64_t key =
      a < b ? ((uint64_t)a << 32) | b : ((uint64_t)b << 32) | a;
  uint32_t lo = 0, hi = world->joined_count;
  while (lo < hi) {
    const uint32_t mid = lo + (hi - lo) / 2u;
    if (world->joined[mid] < key) {
      lo = mid + 1u;
    } else {
      hi = mid;
    }
  }
  return lo < world->joined_count && world->joined[lo] == key;
}

/* ----------------------------------------------------------------- solver */

typedef struct Soft {
  f3d_real bias_rate, mass_scale, impulse_scale;
} Soft;

static Soft soft(f3d_real hertz, f3d_real zeta, f3d_real h) {
  Soft s;
  if (!(hertz > F3D_R(0.0))) {
    s.bias_rate = F3D_R(0.0);
    s.mass_scale = F3D_R(0.0);
    s.impulse_scale = F3D_R(1.0);
    return s;
  }
  const f3d_real omega = F3D_R(2.0) * F3D_PI * hertz;
  const f3d_real a1 = F3D_R(2.0) * zeta + h * omega;
  const f3d_real a2 = h * omega * a1;
  const f3d_real a3 = F3D_R(1.0) / (F3D_R(1.0) + a2);
  s.bias_rate = omega / a1;
  s.mass_scale = a2 * a3;
  s.impulse_scale = a3;
  return s;
}

/* Where a joint's two bodies stand this substep, as its constraints read
 * them. */
typedef struct Frame {
  F3dSlot *a, *b;
  const F3dSolverBody *ba, *bb;
  F3dMat3 ra, rb;
  F3dVec3 la, lb; /* Anchors from each centre, in the world. */
  F3dVec3 d;      /* B's anchor less A's. */
  F3dVec3 axis;   /* The joint's axis, from A. */
} Frame;

static int frame_of(F3dWorld *world, const F3dJointSlot *j,
                    const F3dSolverBody *bodies, Frame *f) {
  f->a = f3d_slot_of(world, j->a);
  f->b = f3d_slot_of(world, j->b);
  if (f->a == NULL || f->b == NULL) return 0;
  f->ba = &bodies[f->a - world->slots];
  f->bb = &bodies[f->b - world->slots];
  if (f->ba->inverse_mass == F3D_R(0.0) && f->bb->inverse_mass == F3D_R(0.0) &&
      !f3d_turns(f->a) && !f3d_turns(f->b)) {
    return 0;
  }
  f->ra = f3d_mat_of(f->a->orientation);
  f->rb = f3d_mat_of(f->b->orientation);
  f->la = turn(&f->ra, j->local_a);
  f->lb = turn(&f->rb, j->local_b);
  f->d = f3d_sub(f3d_add(f->b->position, f->lb), f3d_add(f->a->position, f->la));
  f->axis = turn(&f->ra, j->axis_a);
  return 1;
}

static F3dVec3 velocity_at(const F3dSlot *s, F3dVec3 r) {
  return f3d_add(s->velocity, f3d_cross(s->spin, r));
}

/* A linear impulse [p] on B at rb, and its opposite on A at ra. */
static void push(Frame *f, F3dVec3 ra, F3dVec3 rb, F3dVec3 p) {
  f->a->velocity = f3d_madd(f->a->velocity, p, -f->ba->inverse_mass);
  f->a->spin = f3d_sub(f->a->spin,
                       f3d_sym_times(f->ba->inverse_inertia, f3d_cross(ra, p)));
  f->b->velocity = f3d_madd(f->b->velocity, p, f->bb->inverse_mass);
  f->b->spin = f3d_add(f->b->spin,
                       f3d_sym_times(f->bb->inverse_inertia, f3d_cross(rb, p)));
}

/* An angular impulse [l] on B, and its opposite on A. */
static void twist(Frame *f, F3dVec3 l) {
  f->a->spin = f3d_sub(f->a->spin, f3d_sym_times(f->ba->inverse_inertia, l));
  f->b->spin = f3d_add(f->b->spin, f3d_sym_times(f->bb->inverse_inertia, l));
}

/* 1 / (J M⁻¹ Jᵀ) of a linear direction n at levers ra, rb. */
static f3d_real linear_mass(const Frame *f, F3dVec3 ra, F3dVec3 rb, F3dVec3 n) {
  const F3dVec3 ca = f3d_cross(ra, n), cb = f3d_cross(rb, n);
  const f3d_real k = f->ba->inverse_mass + f->bb->inverse_mass +
                     f3d_dot(ca, f3d_sym_times(f->ba->inverse_inertia, ca)) +
                     f3d_dot(cb, f3d_sym_times(f->bb->inverse_inertia, cb));
  return k > F3D_R(0.0) ? F3D_R(1.0) / k : F3D_R(0.0);
}

static f3d_real angular_mass(const Frame *f, F3dVec3 n) {
  const f3d_real k = f3d_dot(n, f3d_sym_times(f->ba->inverse_inertia, n)) +
                     f3d_dot(n, f3d_sym_times(f->bb->inverse_inertia, n));
  return k > F3D_R(0.0) ? F3D_R(1.0) / k : F3D_R(0.0);
}

/* B's turn from where it started against A, in A's frame, as a small
 * rotation vector: twice the error quaternion's vector part. */
static F3dVec3 turn_error(const F3dJointSlot *j, const Frame *f) {
  F3dQuat e = qmul(qmul(qconj(f->a->orientation), f->b->orientation),
                   qconj(j->reference));
  if (e.w < F3D_R(0.0)) {
    e.x = -e.x;
    e.y = -e.y;
    e.z = -e.z;
    e.w = -e.w;
  }
  return f3d_v3(F3D_R(2.0) * e.x, F3D_R(2.0) * e.y, F3D_R(2.0) * e.z);
}

static f3d_real hinge_angle(const F3dJointSlot *j, const Frame *f) {
  F3dQuat e = qmul(qmul(qconj(f->a->orientation), f->b->orientation),
                   qconj(j->reference));
  if (e.w < F3D_R(0.0)) {
    e.x = -e.x;
    e.y = -e.y;
    e.z = -e.z;
    e.w = -e.w;
  }
  const f3d_real along = e.x * j->axis_a.x + e.y * j->axis_a.y + e.z * j->axis_a.z;
  return F3D_R(2.0) * f3d_atan2(along, e.w);
}

/* One row of a joint's locked block: what it asks of each body's velocity
 * and spin, and how far it is from being met. */
typedef struct Row {
  F3dVec3 lin_a, ang_a, lin_b, ang_b;
  f3d_real c;
} Row;

static Row point_row(const Frame *f, F3dVec3 n, f3d_real c, F3dVec3 ra) {
  Row r;
  r.lin_a = f3d_scale(n, F3D_R(-1.0));
  r.ang_a = f3d_scale(f3d_cross(ra, n), F3D_R(-1.0));
  r.lin_b = n;
  r.ang_b = f3d_cross(f->lb, n);
  r.c = c;
  return r;
}

static Row turn_row(F3dVec3 n, f3d_real c) {
  Row r;
  r.lin_a = r.lin_b = f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
  r.ang_a = f3d_scale(n, F3D_R(-1.0));
  r.ang_b = n;
  r.c = c;
  return r;
}

/* The rows a joint locks: its point, its turns, its slide across the
 * axis. Returns how many. */
static int rows_of(const F3dJointSlot *j, const Frame *f, Row *rows) {
  const F3dVec3 e[3] = {f3d_v3(F3D_R(1.0), F3D_R(0.0), F3D_R(0.0)),
                        f3d_v3(F3D_R(0.0), F3D_R(1.0), F3D_R(0.0)),
                        f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(1.0))};
  const f3d_real dd[3] = {f->d.x, f->d.y, f->d.z};
  int n = 0;
  switch (j->type) {
    case F3D_JOINT_FIXED: {
      const F3dVec3 err = turn(&f->ra, turn_error(j, f));
      const f3d_real ee[3] = {err.x, err.y, err.z};
      for (int k = 0; k < 3; k++) rows[n++] = point_row(f, e[k], dd[k], f->la);
      for (int k = 0; k < 3; k++) rows[n++] = turn_row(e[k], ee[k]);
      break;
    }
    case F3D_JOINT_SPHERICAL:
      for (int k = 0; k < 3; k++) rows[n++] = point_row(f, e[k], dd[k], f->la);
      break;
    case F3D_JOINT_REVOLUTE: {
      /* B's axis kept on A's: its cross with A's, a small turn about the
       * two directions square to the axis, is the error. */
      const F3dVec3 a1 = f->axis, a2 = turn(&f->rb, j->axis_b);
      const F3dVec3 t0 = square_to(a1), t1 = f3d_cross(a1, t0);
      const F3dVec3 err = f3d_cross(a1, a2);
      for (int k = 0; k < 3; k++) rows[n++] = point_row(f, e[k], dd[k], f->la);
      rows[n++] = turn_row(t0, f3d_dot(err, t0));
      rows[n++] = turn_row(t1, f3d_dot(err, t1));
      break;
    }
    case F3D_JOINT_PRISMATIC: {
      /* No turning, and B's anchor kept on A's axis: A's lever reaches to
       * where B's anchor is along it. */
      const F3dVec3 a = f->axis, t0 = square_to(a), t1 = f3d_cross(a, t0);
      const F3dVec3 err = turn(&f->ra, turn_error(j, f));
      const f3d_real ee[3] = {err.x, err.y, err.z};
      const F3dVec3 ra = f3d_add(f->la, f->d);
      rows[n++] = point_row(f, t0, f3d_dot(f->d, t0), ra);
      rows[n++] = point_row(f, t1, f3d_dot(f->d, t1), ra);
      for (int k = 0; k < 3; k++) rows[n++] = turn_row(e[k], ee[k]);
      break;
    }
    default:
      break;
  }
  return n;
}

static f3d_real row_rate(const Frame *f, const Row *r) {
  return f3d_dot(r->lin_a, f->a->velocity) + f3d_dot(r->ang_a, f->a->spin) +
         f3d_dot(r->lin_b, f->b->velocity) + f3d_dot(r->ang_b, f->b->spin);
}

/* Jᵀλ: the rows' impulses on both bodies. */
static void apply_rows(Frame *f, const Row *rows, int n, const f3d_real *l) {
  F3dVec3 la = f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0)), aa = la, lb = la, ab = la;
  for (int k = 0; k < n; k++) {
    la = f3d_madd(la, rows[k].lin_a, l[k]);
    aa = f3d_madd(aa, rows[k].ang_a, l[k]);
    lb = f3d_madd(lb, rows[k].lin_b, l[k]);
    ab = f3d_madd(ab, rows[k].ang_b, l[k]);
  }
  f->a->velocity = f3d_madd(f->a->velocity, la, f->ba->inverse_mass);
  f->a->spin = f3d_add(f->a->spin, f3d_sym_times(f->ba->inverse_inertia, aa));
  f->b->velocity = f3d_madd(f->b->velocity, lb, f->bb->inverse_mass);
  f->b->spin = f3d_add(f->b->spin, f3d_sym_times(f->bb->inverse_inertia, ab));
}

/* Solves the symmetric positive system k x = r of n ≤ 6 by Cholesky's
 * factoring, in place; 0 when k is not positive — two bodies neither of
 * which can move along some row. */
static int cholesky(f3d_real k[6][6], int n, const f3d_real *r, f3d_real *x) {
  for (int i = 0; i < n; i++) {
    for (int c = 0; c <= i; c++) {
      f3d_real sum = k[i][c];
      for (int m = 0; m < c; m++) sum -= k[i][m] * k[c][m];
      if (i == c) {
        if (!(sum > F3D_R(1e-20))) return 0;
        k[i][i] = f3d_sqrt(sum);
      } else {
        k[i][c] = sum / k[c][c];
      }
    }
  }
  f3d_real y[6];
  for (int i = 0; i < n; i++) {
    f3d_real sum = r[i];
    for (int m = 0; m < i; m++) sum -= k[i][m] * y[m];
    y[i] = sum / k[i][i];
  }
  for (int i = n - 1; i >= 0; i--) {
    f3d_real sum = y[i];
    for (int m = i + 1; m < n; m++) sum -= k[m][i] * x[m];
    x[i] = sum / k[i][i];
  }
  return 1;
}

/* Every locked direction of the joint at once: the coupled block, so a
 * heavy lever on a light ball is held as firmly as a light one — solved
 * one direction after another, the point would spin the ball to stop it
 * and the lock would take the spin back, a substep at a time. */
static void solve_block(F3dJointSlot *j, Frame *f, Soft s, int use_bias) {
  Row rows[6];
  const int n = rows_of(j, f, rows);
  if (n == 0) return;
  f3d_real k[6][6], rhs[6], x[6];
  for (int r = 0; r < n; r++) {
    for (int c = 0; c <= r; c++) {
      const Row *p = &rows[r], *q = &rows[c];
      const f3d_real v =
          f->ba->inverse_mass * f3d_dot(p->lin_a, q->lin_a) +
          f3d_dot(p->ang_a, f3d_sym_times(f->ba->inverse_inertia, q->ang_a)) +
          f->bb->inverse_mass * f3d_dot(p->lin_b, q->lin_b) +
          f3d_dot(p->ang_b, f3d_sym_times(f->bb->inverse_inertia, q->ang_b));
      k[r][c] = k[c][r] = v;
    }
  }
  f3d_real ms = F3D_R(1.0), is = F3D_R(0.0), rate = F3D_R(0.0);
  if (use_bias) {
    ms = s.mass_scale;
    is = s.impulse_scale;
    rate = s.bias_rate;
  }
  for (int r = 0; r < n; r++) rhs[r] = row_rate(f, &rows[r]) + rate * rows[r].c;
  if (!cholesky(k, n, rhs, x)) return;
  f3d_real l[6];
  for (int r = 0; r < n; r++) {
    l[r] = -ms * x[r] - is * j->impulse[r];
    j->impulse[r] += l[r];
  }
  apply_rows(f, rows, n, l);
}

/* One free direction of a joint — a hinge's angle, a slider's travel, a
 * rod's length — as a value, its rate, its mass, and how to push along
 * it. */
typedef struct Axis {
  f3d_real value, rate, mass;
  int angular;
  F3dVec3 n, ra, rb;
} Axis;

static void push_axis(Frame *f, const Axis *x, f3d_real impulse) {
  if (x->angular) {
    twist(f, f3d_scale(x->n, impulse));
  } else {
    push(f, x->ra, x->rb, f3d_scale(x->n, impulse));
  }
}

static f3d_real rate_of(const Frame *f, const Axis *x) {
  if (x->angular) return f3d_dot(f3d_sub(f->b->spin, f->a->spin), x->n);
  return f3d_dot(f3d_sub(velocity_at(f->b, x->rb), velocity_at(f->a, x->ra)),
                 x->n);
}

/* The spring, the motor and the limits along a free direction. */
static void solve_axis(F3dJointSlot *j, Frame *f, Axis *x, f3d_real target,
                       f3d_real h, Soft s, int use_bias) {
  if (j->flags & F3D_JOINT_SPRING) {
    const Soft sp = soft(j->spring_hertz, j->spring_damping, h);
    const f3d_real c = x->value - target;
    const f3d_real lambda =
        -x->mass * sp.mass_scale * (rate_of(f, x) + sp.bias_rate * c) -
        sp.impulse_scale * j->spring_impulse;
    j->spring_impulse += lambda;
    push_axis(f, x, lambda);
  }
  if (j->flags & F3D_JOINT_MOTOR) {
    const f3d_real most = j->motor_force * h;
    const f3d_real lambda = -x->mass * (rate_of(f, x) - j->motor_speed);
    const f3d_real total =
        f3d_clamp(j->motor_impulse + lambda, -most, most);
    const f3d_real delta = total - j->motor_impulse;
    j->motor_impulse = total;
    push_axis(f, x, delta);
  }
  if (j->flags & F3D_JOINT_LIMIT) {
    const f3d_real inv_h = F3D_R(1.0) / h;
    /* Lower: value − lower stays above nought; upper: upper − value. Apart,
     * they may close this substep and no more; past, the soft spring takes
     * them back. */
    for (int side = 0; side < 2; side++) {
      const f3d_real sign = side ? F3D_R(-1.0) : F3D_R(1.0);
      const f3d_real c = side ? j->upper - x->value : x->value - j->lower;
      f3d_real *acc = side ? &j->upper_impulse : &j->lower_impulse;
      f3d_real bias = F3D_R(0.0), ms = F3D_R(1.0), is = F3D_R(0.0);
      if (c > F3D_R(0.0)) {
        bias = c * inv_h;
      } else if (use_bias) {
        bias = s.bias_rate * c;
        ms = s.mass_scale;
        is = s.impulse_scale;
      }
      const f3d_real cdot = sign * rate_of(f, x);
      const f3d_real lambda = -x->mass * ms * (cdot + bias) - is * *acc;
      const f3d_real total = f3d_max(*acc + lambda, F3D_R(0.0));
      const f3d_real delta = total - *acc;
      *acc = total;
      push_axis(f, x, sign * delta);
    }
  }
}

/* A spherical joint's swing: the angle from A's axis to B's, and the
 * direction to turn B about to open it — nought when the two are as good
 * as one, and no direction is the way out. */
static f3d_real swing_of(const F3dJointSlot *j, const Frame *f, F3dVec3 *n) {
  const F3dVec3 a1 = f->axis, a2 = turn(&f->rb, j->axis_b);
  const F3dVec3 c = f3d_cross(a1, a2);
  const f3d_real s = f3d_sqrt(f3d_dot(c, c));
  *n = s > F3D_R(1e-9) ? f3d_scale(c, F3D_R(1.0) / s) : f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
  return f3d_atan2(s, f3d_dot(a1, a2));
}

/* How a spherical joint's twist answers B's turn against A: about the
 * axes' sum over one and their cosine. Its swing does not change it, but
 * swung far the twist turns faster than the turn about A's axis — on a
 * shoulder swung a radian and a half, by nearly half again — and a limit
 * pushing about A's axis alone would push on the swing instead. */
static F3dVec3 twist_axis(const F3dJointSlot *j, const Frame *f) {
  const F3dVec3 a1 = f->axis, a2 = turn(&f->rb, j->axis_b);
  const f3d_real c = f3d_max(F3D_R(1.0) + f3d_dot(a1, a2), F3D_R(1e-3));
  return f3d_scale(f3d_add(a1, a2), F3D_R(1.0) / c);
}

/* The cone: the swing held at most j->cone, as a limit is — apart, it may
 * close this substep and no more; past, the soft spring takes it back. */
static void solve_cone(F3dJointSlot *j, Frame *f, f3d_real h, Soft s, int use_bias) {
  if (!(j->flags & F3D_JOINT_CONE)) return;
  F3dVec3 n;
  const f3d_real swing = swing_of(j, f, &n);
  if (n.x == F3D_R(0.0) && n.y == F3D_R(0.0) && n.z == F3D_R(0.0)) return;
  const f3d_real c = j->cone - swing;
  f3d_real bias = F3D_R(0.0), ms = F3D_R(1.0), is = F3D_R(0.0);
  if (c > F3D_R(0.0)) {
    bias = c / h;
  } else if (use_bias) {
    bias = s.bias_rate * c;
    ms = s.mass_scale;
    is = s.impulse_scale;
  }
  const f3d_real cdot = -f3d_dot(f3d_sub(f->b->spin, f->a->spin), n);
  const f3d_real lambda = -angular_mass(f, n) * ms * (cdot + bias) - is * j->cone_impulse;
  const f3d_real total = f3d_max(j->cone_impulse + lambda, F3D_R(0.0));
  const f3d_real delta = total - j->cone_impulse;
  j->cone_impulse = total;
  twist(f, f3d_scale(n, -delta));
}

/* Friction: B's turn against A's resisted about each of the world's axes
 * with at most the joint's torque over the substep. */
static void solve_friction(F3dJointSlot *j, Frame *f, f3d_real h) {
  if (!(j->flags & F3D_JOINT_FRICTION)) return;
  const f3d_real most = j->friction * h;
  f3d_real *held[3] = {&j->friction_impulse.x, &j->friction_impulse.y, &j->friction_impulse.z};
  for (int k = 0; k < 3; k++) {
    const F3dVec3 n = f3d_v3(k == 0 ? F3D_R(1.0) : F3D_R(0.0), k == 1 ? F3D_R(1.0) : F3D_R(0.0),
                             k == 2 ? F3D_R(1.0) : F3D_R(0.0));
    const f3d_real turning = f3d_dot(f3d_sub(f->b->spin, f->a->spin), n);
    const f3d_real lambda = -angular_mass(f, n) * turning;
    const f3d_real total = f3d_clamp(*held[k] + lambda, -most, most);
    const f3d_real delta = total - *held[k];
    *held[k] = total;
    twist(f, f3d_scale(n, delta));
  }
}

static Soft joint_softness(f3d_real h) {
  return soft(f3d_min(F3D_R(60.0), F3D_R(0.25) / h), F3D_JOINT_DAMPING, h);
}

void f3d_solve_joints(F3dWorld *world, const F3dSolverBody *bodies, f3d_real h,
                      int use_bias) {
  if (world->s.joint_live == 0) return;
  world->s.last_substep = h;
  const Soft s = joint_softness(h);
  for (uint32_t i = 0; i < world->s.joint_used; i++) {
    F3dJointSlot *j = &world->joints[i];
    if (!j->live) continue;
    Frame f;
    if (!frame_of(world, j, bodies, &f)) continue;
    Axis x;
    switch (j->type) {
      case F3D_JOINT_FIXED:
        solve_block(j, &f, s, use_bias);
        break;
      case F3D_JOINT_SPHERICAL:
        /* Its friction, its twist about the axis, limited as a hinge's
         * angle is, then its swing inside the cone, then its point. */
        solve_friction(j, &f, h);
        if (j->flags & F3D_JOINT_LIMIT) {
          x.angular = 1;
          x.n = twist_axis(j, &f);
          x.value = hinge_angle(j, &f);
          x.mass = angular_mass(&f, x.n);
          solve_axis(j, &f, &x, F3D_R(0.0), h, s, use_bias);
        }
        solve_cone(j, &f, h, s, use_bias);
        solve_block(j, &f, s, use_bias);
        break;
      case F3D_JOINT_REVOLUTE:
        x.angular = 1;
        x.n = f.axis;
        x.value = hinge_angle(j, &f);
        x.mass = angular_mass(&f, f.axis);
        solve_axis(j, &f, &x, F3D_R(0.0), h, s, use_bias);
        solve_block(j, &f, s, use_bias);
        break;
      case F3D_JOINT_PRISMATIC:
        x.angular = 0;
        x.n = f.axis;
        x.ra = f3d_add(f.la, f.d);
        x.rb = f.lb;
        x.value = f3d_dot(f.d, f.axis);
        x.mass = linear_mass(&f, x.ra, x.rb, f.axis);
        solve_axis(j, &f, &x, F3D_R(0.0), h, s, use_bias);
        solve_block(j, &f, s, use_bias);
        break;
      case F3D_JOINT_DISTANCE: {
        const f3d_real len = f3d_sqrt(f3d_dot(f.d, f.d));
        x.angular = 0;
        x.n = len > F3D_R(1e-9) ? f3d_scale(f.d, F3D_R(1.0) / len)
                                : f3d_v3(F3D_R(0.0), F3D_R(1.0), F3D_R(0.0));
        x.ra = f.la;
        x.rb = f.lb;
        x.value = len;
        x.mass = linear_mass(&f, x.ra, x.rb, x.n);
        if (j->flags & F3D_JOINT_SPRING) {
          /* A spring between the least and most lengths, which hold hard:
           * the limits, read as lengths. */
          const uint8_t keep = j->flags;
          const f3d_real lower = j->lower, upper = j->upper;
          j->lower = j->least;
          j->upper = j->most;
          j->flags |= F3D_JOINT_LIMIT;
          if (!(j->spring_hertz > F3D_R(0.0))) j->flags &= (uint8_t)~F3D_JOINT_SPRING;
          solve_axis(j, &f, &x, j->length, h, s, use_bias);
          j->flags = keep;
          j->lower = lower;
          j->upper = upper;
        } else {
          /* A rod. */
          f3d_real bias = F3D_R(0.0), ms = F3D_R(1.0), is = F3D_R(0.0);
          if (use_bias) {
            bias = s.bias_rate * (len - j->length);
            ms = s.mass_scale;
            is = s.impulse_scale;
          }
          const f3d_real lambda =
              -x.mass * ms * (rate_of(&f, &x) + bias) - is * j->impulse[0];
          j->impulse[0] += lambda;
          push_axis(&f, &x, lambda);
        }
        break;
      }
      default:
        break;
    }
  }
}

void f3d_warm_joints(F3dWorld *world, const F3dSolverBody *bodies) {
  for (uint32_t i = 0; i < world->s.joint_used; i++) {
    F3dJointSlot *j = &world->joints[i];
    if (!j->live) continue;
    Frame f;
    if (!frame_of(world, j, bodies, &f)) continue;
    const f3d_real axial =
        j->spring_impulse + j->motor_impulse + j->lower_impulse - j->upper_impulse;
    /* The block's impulses along its rows as they stand now, then the free
     * direction's. What B was pushed with, linearly, is kept to report. */
    Row rows[6];
    const int n = rows_of(j, &f, rows);
    apply_rows(&f, rows, n, j->impulse);
    F3dVec3 pushed = f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
    F3dVec3 turned = pushed;
    for (int k = 0; k < n; k++) {
      pushed = f3d_madd(pushed, rows[k].lin_b, j->impulse[k]);
      /* A turn row moves nothing along: its turn on B is its torque. */
      if (f3d_dot(rows[k].lin_b, rows[k].lin_b) == F3D_R(0.0)) {
        turned = f3d_madd(turned, rows[k].ang_b, j->impulse[k]);
      }
    }
    j->turned = turned;
    switch (j->type) {
      case F3D_JOINT_REVOLUTE:
        twist(&f, f3d_scale(f.axis, axial));
        break;
      case F3D_JOINT_SPHERICAL: {
        twist(&f, f3d_scale(twist_axis(j, &f), axial));
        F3dVec3 n;
        swing_of(j, &f, &n);
        twist(&f, f3d_scale(n, -j->cone_impulse));
        twist(&f, j->friction_impulse);
        break;
      }
      case F3D_JOINT_PRISMATIC: {
        const F3dVec3 p = f3d_scale(f.axis, axial);
        push(&f, f3d_add(f.la, f.d), f.lb, p);
        pushed = f3d_add(pushed, p);
        break;
      }
      case F3D_JOINT_DISTANCE: {
        const f3d_real len = f3d_sqrt(f3d_dot(f.d, f.d));
        const F3dVec3 nn = len > F3D_R(1e-9) ? f3d_scale(f.d, F3D_R(1.0) / len)
                                             : f3d_v3(F3D_R(0.0), F3D_R(1.0), F3D_R(0.0));
        /* The rod's own impulse only while it is a rod: made a spring or a
         * rope, what it held as a rod would hold on for ever. */
        const f3d_real rod = (j->flags & F3D_JOINT_SPRING) ? F3D_R(0.0) : j->impulse[0];
        pushed = f3d_scale(nn, rod + axial);
        push(&f, f.la, f.lb, pushed);
        break;
      }
      default:
        break;
    }
    j->pushed = pushed;
  }
}

int f3d_joint_get_value(const F3dWorld *world, F3dJoint joint, f3d_real *out) {
  const F3dJointSlot *j = joint_of(world, joint);
  if (j == NULL) return 0;
  Frame f;
  f.a = f3d_slot_of(world, j->a);
  f.b = f3d_slot_of(world, j->b);
  *out = F3D_R(0.0);
  if (f.a == NULL || f.b == NULL) return 1;
  f.ra = f3d_mat_of(f.a->orientation);
  f.rb = f3d_mat_of(f.b->orientation);
  f.la = turn(&f.ra, j->local_a);
  f.lb = turn(&f.rb, j->local_b);
  f.d = f3d_sub(f3d_add(f.b->position, f.lb), f3d_add(f.a->position, f.la));
  f.axis = turn(&f.ra, j->axis_a);
  switch (j->type) {
    case F3D_JOINT_REVOLUTE:
    case F3D_JOINT_SPHERICAL:
      *out = hinge_angle(j, &f);
      break;
    case F3D_JOINT_PRISMATIC:
      *out = f3d_dot(f.d, f.axis);
      break;
    case F3D_JOINT_DISTANCE:
      *out = f3d_sqrt(f3d_dot(f.d, f.d));
      break;
    default:
      break;
  }
  return 1;
}

int f3d_joint_get_swing(const F3dWorld *world, F3dJoint joint, f3d_real *out) {
  const F3dJointSlot *j = joint_of(world, joint);
  if (j == NULL) return 0;
  *out = F3D_R(0.0);
  Frame f;
  f.a = f3d_slot_of(world, j->a);
  f.b = f3d_slot_of(world, j->b);
  if (f.a == NULL || f.b == NULL || j->type != F3D_JOINT_SPHERICAL) return 1;
  f.ra = f3d_mat_of(f.a->orientation);
  f.rb = f3d_mat_of(f.b->orientation);
  f.axis = turn(&f.ra, j->axis_a);
  F3dVec3 n;
  *out = swing_of(j, &f, &n);
  return 1;
}
