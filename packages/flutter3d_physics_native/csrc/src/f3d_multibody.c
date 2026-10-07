/*
 * Multibodies — a tree of bodies held by joints in reduced coordinates.
 *
 * The links are ordinary bodies, and the solver moves them as it moves any
 * body, contacts and all. Afterwards the multibody reads each joint's
 * coordinate off where its two links stand, puts every link back where its
 * parent and that coordinate say, and replaces the links' velocities with
 * the nearest the joints allow: the joint speeds x that minimise
 * Σ |J x − t|² weighted by each link's mass and inertia, which are the
 * solution of (Jᵀ M J) x = Jᵀ M t. Motors and limits then push on the
 * joint speeds through the same matrix, so the whole tree answers.
 *
 * So a joint never comes apart, however long the chain or heavy its end:
 * there is nothing for it to drift by. What the links did inside the step —
 * a contact pushing one of them out of the floor — is kept as far as the
 * joints allow it.
 *
 * Every order is link order, parents before children, and every number the
 * core's own, so a multibody steps to the same bits wherever the world
 * does.
 */
#include "f3d_internal.h"

enum {
  LINK_LIMIT = 1u << 0,
  LINK_MOTOR = 1u << 1,
  LINK_CONE = 1u << 2,
};

static F3dQuat qmul(F3dQuat a, F3dQuat b) {
  F3dQuat q;
  q.w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z;
  q.x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y;
  q.y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x;
  q.z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w;
  return q;
}

static F3dQuat qconj(F3dQuat q) {
  F3dQuat c = {-q.x, -q.y, -q.z, q.w};
  return c;
}

static F3dQuat qnorm(F3dQuat q) {
  const f3d_real len = f3d_sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w);
  if (!(len > F3D_R(0.0))) {
    F3dQuat one = {F3D_R(0.0), F3D_R(0.0), F3D_R(0.0), F3D_R(1.0)};
    return one;
  }
  F3dQuat n = {q.x / len, q.y / len, q.z / len, q.w / len};
  return n;
}

/* [angle] radians about the unit [axis]. */
static F3dQuat about(F3dVec3 axis, f3d_real angle) {
  f3d_real s, c;
  f3d_sin_cos(F3D_R(0.5) * angle, &s, &c);
  F3dQuat q = {axis.x * s, axis.y * s, axis.z * s, c};
  return q;
}

static F3dVec3 rotate(F3dQuat q, F3dVec3 v) {
  const F3dMat3 m = f3d_mat_of(q);
  return f3d_add(f3d_add(f3d_scale(m.c[0], v.x), f3d_scale(m.c[1], v.y)),
                 f3d_scale(m.c[2], v.z));
}

static F3dMultibodySlot *multibody_of(const F3dWorld *world,
                                      F3dMultibody multibody) {
  if (multibody == 0 || multibody > world->s.multibody_count) return NULL;
  F3dMultibodySlot *m = &world->multibodies[multibody - 1u];
  return m->live ? m : NULL;
}

/* Whether [body] is a link of a live multibody already. */
static int linked(const F3dWorld *world, F3dBody body) {
  for (uint32_t i = 0; i < world->s.multibody_count; i++) {
    const F3dMultibodySlot *m = &world->multibodies[i];
    if (!m->live) continue;
    for (uint32_t k = 0; k < m->link_count; k++) {
      if (m->links[k].body == body) return 1;
    }
  }
  return 0;
}

F3dMultibody f3d_multibody_create(F3dWorld *world, F3dBody root) {
  const F3dSlot *s = f3d_slot_of(world, root);
  if (s == NULL || linked(world, root)) return 0;
  F3dMultibodySlot *all = (F3dMultibodySlot *)f3d_realloc(
      world->multibodies,
      ((size_t)world->s.multibody_count + 1u) * sizeof(F3dMultibodySlot));
  if (all == NULL) return 0;
  world->multibodies = all;
  F3dMultibodySlot *m = &all[world->s.multibody_count];
  f3d_zero(m, sizeof *m);
  m->live = 1;
  m->link_count = 1;
  m->floating = s->type == F3D_BODY_DYNAMIC;
  m->dof_count = m->floating ? 6u : 0u;
  m->links[0].body = root;
  m->links[0].turn.w = F3D_R(1.0);
  m->links[0].reference.w = F3D_R(1.0);
  world->s.multibody_count++;
  return world->s.multibody_count;
}

int f3d_multibody_destroy(F3dWorld *world, F3dMultibody multibody) {
  F3dMultibodySlot *m = multibody_of(world, multibody);
  if (m == NULL) return 0;
  world->s.multibody_links -= m->link_count - 1u;
  m->live = 0;
  world->joined_stale = 1;
  return 1;
}

int f3d_multibody_is_valid(const F3dWorld *world, F3dMultibody multibody) {
  return multibody_of(world, multibody) != NULL;
}

int f3d_multibody_add_link(F3dWorld *world, F3dMultibody multibody,
                           uint32_t parent, F3dBody body, F3dJointType type,
                           f3d_real ax, f3d_real ay, f3d_real az, f3d_real ux,
                           f3d_real uy, f3d_real uz) {
  F3dMultibodySlot *m = multibody_of(world, multibody);
  if (m == NULL || parent >= m->link_count ||
      m->link_count >= F3D_MULTIBODY_MOST_LINKS) {
    return -1;
  }
  const F3dSlot *c = f3d_slot_of(world, body);
  const F3dSlot *p = f3d_slot_of(world, m->links[parent].body);
  if (c == NULL || p == NULL || c->type != F3D_BODY_DYNAMIC ||
      linked(world, body)) {
    return -1;
  }
  if (!(f3d_finite(ax) && f3d_finite(ay) && f3d_finite(az) &&
        f3d_finite(ux) && f3d_finite(uy) && f3d_finite(uz))) {
    return -1;
  }
  uint32_t dofs;
  switch (type) {
    case F3D_JOINT_FIXED:
      dofs = 0;
      break;
    case F3D_JOINT_REVOLUTE:
    case F3D_JOINT_PRISMATIC:
      dofs = 1;
      break;
    case F3D_JOINT_SPHERICAL:
      dofs = 3;
      break;
    default:
      return -1;
  }
  F3dVec3 axis = f3d_v3(ux, uy, uz);
  const f3d_real len = f3d_sqrt(f3d_dot(axis, axis));
  if (dofs == 1 && !(len > F3D_R(0.0))) return -1;
  if (m->dof_count + dofs > F3D_MULTIBODY_MOST_DOFS) return -1;
  axis = len > F3D_R(0.0) ? f3d_scale(axis, F3D_R(1.0) / len)
                          : f3d_v3(F3D_R(0.0), F3D_R(1.0), F3D_R(0.0));
  F3dLink *l = &m->links[m->link_count];
  f3d_zero(l, sizeof *l);
  l->body = body;
  l->parent = parent;
  l->type = (uint32_t)type;
  l->first_dof = m->dof_count;
  l->dofs = dofs;
  const F3dVec3 anchor = f3d_v3(ax, ay, az);
  const F3dQuat pinv = qconj(p->orientation);
  l->parent_anchor = rotate(pinv, f3d_sub(anchor, p->position));
  l->child_anchor = rotate(qconj(c->orientation), f3d_sub(anchor, c->position));
  l->axis = rotate(pinv, axis);
  l->reference = qnorm(qmul(pinv, c->orientation));
  l->turn.w = F3D_R(1.0);
  m->dof_count += dofs;
  m->link_count++;
  world->s.multibody_links++;
  world->joined_stale = 1;
  return (int)(m->link_count - 1u);
}

static F3dLink *joint_link(const F3dWorld *world, F3dMultibody multibody,
                           uint32_t link) {
  F3dMultibodySlot *m = multibody_of(world, multibody);
  if (m == NULL || link == 0 || link >= m->link_count) return NULL;
  F3dLink *l = &m->links[link];
  return l->type == F3D_JOINT_REVOLUTE || l->type == F3D_JOINT_PRISMATIC
             ? l
             : NULL;
}

int f3d_multibody_set_limits(F3dWorld *world, F3dMultibody multibody,
                             uint32_t link, int enabled, f3d_real lower,
                             f3d_real upper) {
  F3dLink *l = joint_link(world, multibody, link);
  if (l == NULL) return 0;
  if (enabled) {
    if (!(f3d_finite(lower) && f3d_finite(upper) && lower <= upper)) return 0;
    l->lower = lower;
    l->upper = upper;
    l->flags |= LINK_LIMIT;
  } else {
    l->flags &= ~(uint32_t)LINK_LIMIT;
  }
  return 1;
}

int f3d_multibody_set_motor(F3dWorld *world, F3dMultibody multibody,
                            uint32_t link, int enabled, f3d_real speed,
                            f3d_real force) {
  F3dLink *l = joint_link(world, multibody, link);
  if (l == NULL) return 0;
  if (enabled) {
    if (!(f3d_finite(speed) && f3d_finite(force) && force >= F3D_R(0.0))) {
      return 0;
    }
    l->motor_speed = speed;
    l->motor_force = force;
    if (!(l->flags & LINK_MOTOR)) l->motor_q = l->q;
    l->flags |= LINK_MOTOR;
  } else {
    l->flags &= ~(uint32_t)LINK_MOTOR;
  }
  F3dSlot *s = f3d_slot_of(world, l->body);
  if (s != NULL) f3d_wake(world, s);
  return 1;
}

int f3d_multibody_set_cone(F3dWorld *world, F3dMultibody multibody,
                           uint32_t link, int enabled, f3d_real swing,
                           f3d_real twist) {
  F3dMultibodySlot *m = multibody_of(world, multibody);
  if (m == NULL || link == 0 || link >= m->link_count) return 0;
  F3dLink *l = &m->links[link];
  if (l->type != F3D_JOINT_SPHERICAL) return 0;
  if (enabled) {
    if (!(f3d_finite(swing) && f3d_finite(twist) && swing > F3D_R(0.0) &&
          swing <= F3D_PI && twist >= F3D_R(0.0) && twist <= F3D_PI)) {
      return 0;
    }
    l->swing = swing;
    l->twist = twist;
    l->flags |= LINK_CONE;
  } else {
    l->flags &= ~(uint32_t)LINK_CONE;
  }
  F3dSlot *s = f3d_slot_of(world, l->body);
  if (s != NULL) f3d_wake(world, s);
  return 1;
}

uint32_t f3d_multibody_link_count(const F3dWorld *world,
                                  F3dMultibody multibody) {
  const F3dMultibodySlot *m = multibody_of(world, multibody);
  return m == NULL ? 0u : m->link_count;
}

uint32_t f3d_multibody_dof_count(const F3dWorld *world,
                                 F3dMultibody multibody) {
  const F3dMultibodySlot *m = multibody_of(world, multibody);
  return m == NULL ? 0u : m->dof_count;
}

int f3d_multibody_read_joint(const F3dWorld *world, F3dMultibody multibody,
                             uint32_t link, f3d_real *out) {
  const F3dMultibodySlot *m = multibody_of(world, multibody);
  if (m == NULL || link >= m->link_count || out == NULL) return 0;
  const F3dLink *l = &m->links[link];
  for (int i = 0; i < 8; i++) out[i] = F3D_R(0.0);
  if (link == 0) return 1;
  switch (l->type) {
    case F3D_JOINT_REVOLUTE:
    case F3D_JOINT_PRISMATIC:
      out[0] = l->q;
      out[1] = l->qd;
      break;
    case F3D_JOINT_SPHERICAL:
      out[0] = l->turn.x;
      out[1] = l->turn.y;
      out[2] = l->turn.z;
      out[3] = l->turn.w;
      out[4] = l->spin.x;
      out[5] = l->spin.y;
      out[6] = l->spin.z;
      break;
    default:
      break;
  }
  return 1;
}

/* ------------------------------------------------------------ kinematics */

/* Where a link stands: its place and its turn. */
typedef struct Pose {
  F3dVec3 at;
  F3dQuat turn;
} Pose;

/* [a] brought within half a turn of [near]: an angle read off a turn is
 * only known to a whole turn, and a hinge that has wound round twice must
 * keep saying so, or its limits and motor would see it jump. */
static f3d_real unwrap(f3d_real a, f3d_real near) {
  const f3d_real turn = F3D_R(2.0) * F3D_PI;
  while (a - near > F3D_PI) a -= turn;
  while (a - near < -F3D_PI) a += turn;
  return a;
}

/* A spherical joint's turn [q], in the parent's frame, as a swing of the
 * axis [a] and a twist about it: q = swing · twist. The angles are the
 * swing's, in [0, π], and the twist's, in (−π, π]. */
static void split(F3dQuat q, F3dVec3 a, F3dQuat *swing, F3dQuat *twist,
                  f3d_real *swung, f3d_real *twisted) {
  if (q.w < F3D_R(0.0)) {
    q.x = -q.x;
    q.y = -q.y;
    q.z = -q.z;
    q.w = -q.w;
  }
  const f3d_real along = q.x * a.x + q.y * a.y + q.z * a.z;
  F3dQuat t = {a.x * along, a.y * along, a.z * along, q.w};
  t = qnorm(t);
  *twist = t;
  *swing = qnorm(qmul(q, qconj(t)));
  const f3d_real sv = f3d_sqrt(swing->x * swing->x + swing->y * swing->y +
                               swing->z * swing->z);
  *swung = F3D_R(2.0) * f3d_atan2(sv, f3d_abs(swing->w));
  *twisted = F3D_R(2.0) * f3d_atan2(t.x * a.x + t.y * a.y + t.z * a.z, t.w);
}

/* A spherical link's turn brought back inside its cone. */
static void hold_cone(F3dLink *l) {
  F3dQuat swing, twist;
  f3d_real swung, twisted;
  split(l->turn, l->axis, &swing, &twist, &swung, &twisted);
  int changed = 0;
  if (swung > l->swing) {
    const F3dVec3 v = f3d_v3(swing.x, swing.y, swing.z);
    const f3d_real len = f3d_sqrt(f3d_dot(v, v));
    if (len > F3D_R(0.0)) {
      swing = about(f3d_scale(v, (swing.w < F3D_R(0.0) ? F3D_R(-1.0) : F3D_R(1.0)) / len),
                    l->swing);
      changed = 1;
    }
  }
  if (f3d_abs(twisted) > l->twist) {
    twist = about(l->axis, twisted < F3D_R(0.0) ? -l->twist : l->twist);
    changed = 1;
  }
  if (changed) l->turn = qnorm(qmul(swing, twist));
}

/* Link [l]'s joint read off where it and its parent stand. */
static void read_joint(F3dLink *l, Pose parent, Pose child) {
  /* The joint's own turn, in the parent's frame. */
  const F3dQuat rel =
      qnorm(qmul(qmul(qconj(parent.turn), child.turn), qconj(l->reference)));
  switch (l->type) {
    case F3D_JOINT_REVOLUTE: {
      /* The twist about the axis: twice the angle of (axis · v, w). */
      const f3d_real along = rel.x * l->axis.x + rel.y * l->axis.y +
                             rel.z * l->axis.z;
      const f3d_real angle = F3D_R(2.0) * f3d_atan2(along, rel.w);
      l->q = unwrap(angle, l->q);
      break;
    }
    case F3D_JOINT_PRISMATIC: {
      const F3dVec3 a = f3d_add(parent.at, rotate(parent.turn, l->parent_anchor));
      const F3dVec3 b = f3d_add(child.at, rotate(child.turn, l->child_anchor));
      l->q = f3d_dot(rotate(parent.turn, l->axis), f3d_sub(b, a));
      break;
    }
    case F3D_JOINT_SPHERICAL:
      l->turn = rel;
      break;
    default:
      break;
  }
}

/* Where link [l] stands, from where its parent does and its joint. */
static Pose place(const F3dLink *l, Pose parent) {
  F3dQuat joint = {F3D_R(0.0), F3D_R(0.0), F3D_R(0.0), F3D_R(1.0)};
  F3dVec3 slide = f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
  switch (l->type) {
    case F3D_JOINT_REVOLUTE:
      joint = about(l->axis, l->q);
      break;
    case F3D_JOINT_PRISMATIC:
      slide = f3d_scale(l->axis, l->q);
      break;
    case F3D_JOINT_SPHERICAL:
      joint = l->turn;
      break;
    default:
      break;
  }
  Pose p;
  p.turn = qnorm(qmul(parent.turn, qmul(joint, l->reference)));
  const F3dVec3 anchor = f3d_add(
      parent.at, rotate(parent.turn, f3d_add(l->parent_anchor, slide)));
  p.at = f3d_sub(anchor, rotate(p.turn, l->child_anchor));
  return p;
}

/* ------------------------------------------------------------ the speeds */

#define MOST_DOFS F3D_MULTIBODY_MOST_DOFS

/* What one degree of freedom moving at one unit does to a link: its
 * velocity and its spin. */
typedef struct Column {
  F3dVec3 lin, ang;
} Column;

/* Whether link [j] is link [k] or one it hangs from. */
static int carries(const F3dMultibodySlot *m, uint32_t j, uint32_t k) {
  while (k != j && k != 0) k = m->links[k].parent;
  return k == j;
}

/* Every degree of freedom that moves link [k], into [dofs] and their
 * columns into [cols]; returns how many. */
static uint32_t columns(const F3dMultibodySlot *m, const Pose *placed,
                        uint32_t k, uint32_t *dofs, Column *cols) {
  uint32_t n = 0;
  const F3dVec3 at = placed[k].at;
  const F3dVec3 e[3] = {f3d_v3(F3D_R(1.0), F3D_R(0.0), F3D_R(0.0)),
                        f3d_v3(F3D_R(0.0), F3D_R(1.0), F3D_R(0.0)),
                        f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(1.0))};
  if (m->floating) {
    const F3dVec3 arm = f3d_sub(at, placed[0].at);
    for (uint32_t i = 0; i < 3; i++) {
      dofs[n] = i;
      cols[n].lin = e[i];
      cols[n].ang = f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
      n++;
    }
    for (uint32_t i = 0; i < 3; i++) {
      dofs[n] = 3u + i;
      cols[n].ang = e[i];
      cols[n].lin = f3d_cross(e[i], arm);
      n++;
    }
  }
  for (uint32_t j = 1; j < m->link_count; j++) {
    const F3dLink *l = &m->links[j];
    if (l->dofs == 0 || !carries(m, j, k)) continue;
    const Pose parent = placed[l->parent];
    const F3dVec3 o = f3d_add(parent.at, rotate(parent.turn, l->parent_anchor));
    const F3dVec3 arm = f3d_sub(at, o);
    if (l->type == F3D_JOINT_PRISMATIC) {
      dofs[n] = l->first_dof;
      cols[n].lin = rotate(parent.turn, l->axis);
      cols[n].ang = f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
      n++;
    } else if (l->type == F3D_JOINT_REVOLUTE) {
      const F3dVec3 a = rotate(parent.turn, l->axis);
      dofs[n] = l->first_dof;
      cols[n].ang = a;
      cols[n].lin = f3d_cross(a, arm);
      n++;
    } else {
      for (uint32_t i = 0; i < 3; i++) {
        const F3dVec3 a = rotate(parent.turn, e[i]);
        dofs[n] = l->first_dof + i;
        cols[n].ang = a;
        cols[n].lin = f3d_cross(a, arm);
        n++;
      }
    }
  }
  return n;
}

/* A = L Lᵀ in place, the lower half; 0 when it is not positive. */
static int cholesky(f3d_real *a, uint32_t n) {
  for (uint32_t j = 0; j < n; j++) {
    f3d_real d = a[j * n + j];
    for (uint32_t k = 0; k < j; k++) d -= a[j * n + k] * a[j * n + k];
    if (!(d > F3D_R(0.0))) return 0;
    const f3d_real root = f3d_sqrt(d);
    a[j * n + j] = root;
    for (uint32_t i = j + 1; i < n; i++) {
      f3d_real s = a[i * n + j];
      for (uint32_t k = 0; k < j; k++) s -= a[i * n + k] * a[j * n + k];
      a[i * n + j] = s / root;
    }
  }
  return 1;
}

/* Solves L Lᵀ x = b in place. */
static void solve(const f3d_real *l, uint32_t n, f3d_real *x) {
  for (uint32_t i = 0; i < n; i++) {
    f3d_real s = x[i];
    for (uint32_t k = 0; k < i; k++) s -= l[i * n + k] * x[k];
    x[i] = s / l[i * n + i];
  }
  for (uint32_t i = n; i-- > 0;) {
    f3d_real s = x[i];
    for (uint32_t k = i + 1; k < n; k++) s -= l[k * n + i] * x[k];
    x[i] = s / l[i * n + i];
  }
}

/* One push of [impulse] on degree of freedom [d], through the whole tree:
 * x moves by A⁻¹ e_d times it. Returns A⁻¹'s diagonal there, the inverse of
 * the mass that degree of freedom moves. */
static f3d_real response(const f3d_real *l, uint32_t n, uint32_t d,
                         f3d_real *u) {
  for (uint32_t i = 0; i < n; i++) u[i] = F3D_R(0.0);
  u[d] = F3D_R(1.0);
  solve(l, n, u);
  return u[d];
}

static void step_one(F3dWorld *world, F3dMultibodySlot *m, f3d_real dt) {
  const uint32_t n = m->link_count;
  F3dSlot *slots[F3D_MULTIBODY_MOST_LINKS];
  int awake = 0;
  for (uint32_t k = 0; k < n; k++) {
    slots[k] = f3d_slot_of(world, m->links[k].body);
    if (slots[k] == NULL) {
      /* A link taken out of the world takes the multibody with it. */
      world->s.multibody_links -= n - 1u;
      m->live = 0;
      world->joined_stale = 1;
      return;
    }
    if (!(slots[k]->flags & F3D_FLAG_ASLEEP)) awake = 1;
  }
  if (!awake || n < 2) return;
  /* One tree, one sleep: what the solver woke, it wakes all of. */
  for (uint32_t k = 0; k < n; k++) {
    if (slots[k]->flags & F3D_FLAG_ASLEEP) f3d_wake(world, slots[k]);
  }
  /* The joints read off where the solver left the links, and the links put
   * back where the joints say, from the root out. */
  Pose solved[F3D_MULTIBODY_MOST_LINKS], placed[F3D_MULTIBODY_MOST_LINKS];
  for (uint32_t k = 0; k < n; k++) {
    solved[k].at = slots[k]->position;
    solved[k].turn = slots[k]->orientation;
  }
  placed[0] = solved[0];
  for (uint32_t k = 1; k < n; k++) {
    F3dLink *l = &m->links[k];
    read_joint(l, solved[l->parent], solved[k]);
    if ((l->flags & LINK_LIMIT) && l->dofs == 1) {
      l->q = f3d_clamp(l->q, l->lower, l->upper);
    }
    if (l->flags & LINK_CONE) hold_cone(l);
    placed[k] = place(l, placed[l->parent]);
    slots[k]->position = placed[k].at;
    slots[k]->orientation = placed[k].turn;
  }
  /* The joint speeds nearest the links' velocities, weighted by their mass
   * and inertia: (Jᵀ M J) x = Jᵀ M t. */
  const uint32_t dn = m->dof_count;
  if (dn == 0) {
    /* Nothing moves but the root: every link moves as it does. */
    for (uint32_t k = 1; k < n; k++) {
      slots[k]->spin = slots[0]->spin;
      slots[k]->velocity = f3d_add(
          slots[0]->velocity,
          f3d_cross(slots[0]->spin, f3d_sub(placed[k].at, placed[0].at)));
    }
    return;
  }
  f3d_real a[MOST_DOFS * MOST_DOFS];
  f3d_real x[MOST_DOFS], u[MOST_DOFS];
  for (uint32_t i = 0; i < dn * dn; i++) a[i] = F3D_R(0.0);
  for (uint32_t i = 0; i < dn; i++) x[i] = F3D_R(0.0);
  uint32_t dofs[MOST_DOFS];
  Column cols[MOST_DOFS];
  for (uint32_t k = m->floating ? 0u : 1u; k < n; k++) {
    const F3dSlot *s = slots[k];
    const F3dSym3 inertia = f3d_sym_turned(s->orientation, s->inertia);
    const uint32_t c = columns(m, placed, k, dofs, cols);
    for (uint32_t i = 0; i < c; i++) {
      const F3dVec3 ia = f3d_sym_times(inertia, cols[i].ang);
      x[dofs[i]] += s->mass * f3d_dot(cols[i].lin, s->velocity) +
                    f3d_dot(ia, s->spin);
      for (uint32_t j = 0; j < c; j++) {
        a[dofs[j] * dn + dofs[i]] += s->mass * f3d_dot(cols[i].lin, cols[j].lin) +
                                     f3d_dot(ia, cols[j].ang);
      }
    }
  }
  /* A degree of freedom that moves nothing with mass — a spherical joint
   * on a point — is held still rather than left to divide by nought. */
  for (uint32_t i = 0; i < dn; i++) {
    a[i * dn + i] += F3D_R(1e-6) * (F3D_R(1.0) + a[i * dn + i]);
  }
  if (!cholesky(a, dn)) return;
  solve(a, dn, x);
  /* Motors and limits, each a push on its own degree of freedom that the
   * whole tree answers, and so each moving the others' speeds: solved
   * together, a pass over them all repeated until they agree (projected
   * Gauss–Seidel), each push accumulated over the passes and held to what
   * its motor can give in a step, or to pushing only away from its limit.
   * One pass alone left a chain's motors undoing each other, and a neck of
   * four links held still by its motors sagged to its limits. */
  {
    enum { PASSES = 16 };
    /* Each constraint's degree of freedom, its response column and its
     * inverse inertia, its target and bounds, and what it has pushed. */
    uint32_t cd[2u * F3D_MULTIBODY_MOST_LINKS];
    f3d_real cinv[2u * F3D_MULTIBODY_MOST_LINKS];
    f3d_real cwant[2u * F3D_MULTIBODY_MOST_LINKS];
    f3d_real clo[2u * F3D_MULTIBODY_MOST_LINKS], chi[2u * F3D_MULTIBODY_MOST_LINKS];
    f3d_real cdone[2u * F3D_MULTIBODY_MOST_LINKS];
    uint32_t clink[2u * F3D_MULTIBODY_MOST_LINKS];
    int csign[2u * F3D_MULTIBODY_MOST_LINKS];
    f3d_real cu[2u * F3D_MULTIBODY_MOST_LINKS][MOST_DOFS];
    uint32_t cn = 0;
    for (uint32_t k = 1; k < n; k++) {
      const F3dLink *l = &m->links[k];
      if (l->dofs != 1) continue;
      const uint32_t d = l->first_dof;
      if (l->flags & LINK_MOTOR) {
        const f3d_real inv = response(a, dn, d, cu[cn]);
        if (inv > F3D_R(0.0)) {
          cd[cn] = d;
          cinv[cn] = inv;
          /* A servo: the motor's speed, and what brings the joint back to
           * where the motor means it to be — the step's free fall under
           * the solver would otherwise sag a held arm a little each step. */
          cwant[cn] = l->motor_speed + (l->motor_q - l->q) / dt;
          clink[cn] = k;
          chi[cn] = l->motor_force * dt;
          clo[cn] = -chi[cn];
          csign[cn] = 0;
          cdone[cn] = F3D_R(0.0);
          cn++;
        }
      }
      if (l->flags & LINK_LIMIT) {
        /* The speed that would carry it just to each limit this step: at
         * least the lower's, at most the upper's. */
        for (int side = -1; side <= 1; side += 2) {
          const f3d_real inv = response(a, dn, d, cu[cn]);
          if (!(inv > F3D_R(0.0))) continue;
          cd[cn] = d;
          cinv[cn] = inv;
          clink[cn] = k;
          cwant[cn] = ((side < 0 ? l->lower : l->upper) - l->q) / dt;
          csign[cn] = side;
          cdone[cn] = F3D_R(0.0);
          cn++;
        }
      }
    }
    for (int pass = 0; pass < PASSES; pass++) {
      for (uint32_t c = 0; c < cn; c++) {
        const uint32_t d = cd[c];
        f3d_real want = (cwant[c] - x[d]) / cinv[c];
        f3d_real done;
        if (csign[c] == 0) {
          done = f3d_clamp(cdone[c] + want, clo[c], chi[c]);
        } else if (csign[c] < 0) {
          /* Lower: may only push up, and only while it would pass it. */
          done = f3d_max(cdone[c] + want, F3D_R(0.0));
        } else {
          done = f3d_min(cdone[c] + want, F3D_R(0.0));
        }
        want = done - cdone[c];
        cdone[c] = done;
        for (uint32_t i = 0; i < dn; i++) x[i] += cu[c][i] * want;
      }
    }
    /* Each motor's mark carried on at its speed — or, where it could not
     * hold the joint, brought to where the joint goes, so a motor too weak
     * for its load does not wind up a debt it pays back with a lurch. */
    for (uint32_t c = 0; c < cn; c++) {
      if (csign[c] != 0) continue;
      F3dLink *l = &m->links[clink[c]];
      const int held = f3d_abs(cdone[c]) < chi[c];
      l->motor_q = held ? l->motor_q + l->motor_speed * dt : l->q + x[cd[c]] * dt;
      if (l->flags & LINK_LIMIT) l->motor_q = f3d_clamp(l->motor_q, l->lower, l->upper);
    }
  }
  /* Cones: a spherical link's spin relative to its parent, in the
   * parent's frame, is its three joint speeds; what of it would carry the
   * axis further out than the swing allows, or twist it past the twist, is
   * pushed back through the whole tree as a limit is. */
  for (uint32_t k = 1; k < n; k++) {
    const F3dLink *l = &m->links[k];
    if (!(l->flags & LINK_CONE)) continue;
    const uint32_t d = l->first_dof;
    F3dQuat swing, twist;
    f3d_real swung, twisted;
    split(l->turn, l->axis, &swing, &twist, &swung, &twisted);
    const F3dVec3 out = rotate(l->turn, l->axis);
    const F3dVec3 bend = f3d_cross(l->axis, out);
    const f3d_real bent = f3d_sqrt(f3d_dot(bend, bend));
    F3dVec3 dirs[3];
    f3d_real limits[3], now[3];
    uint32_t count = 0;
    if (bent > F3D_R(1e-6)) {
      dirs[count] = f3d_scale(bend, F3D_R(1.0) / bent);
      limits[count] = l->swing;
      now[count++] = swung;
    }
    dirs[count] = out;
    limits[count] = l->twist;
    now[count++] = twisted;
    dirs[count] = f3d_scale(out, F3D_R(-1.0));
    limits[count] = l->twist;
    now[count++] = -twisted;
    for (uint32_t c = 0; c < count; c++) {
      const F3dVec3 j = dirs[c];
      const f3d_real rate = j.x * x[d] + j.y * x[d + 1u] + j.z * x[d + 2u];
      const f3d_real want = (limits[c] - now[c]) / dt;
      if (rate <= want) continue;
      for (uint32_t i = 0; i < dn; i++) u[i] = F3D_R(0.0);
      u[d] = j.x;
      u[d + 1u] = j.y;
      u[d + 2u] = j.z;
      solve(a, dn, u);
      const f3d_real inv = j.x * u[d] + j.y * u[d + 1u] + j.z * u[d + 2u];
      if (!(inv > F3D_R(0.0))) continue;
      const f3d_real push = (want - rate) / inv;
      for (uint32_t i = 0; i < dn; i++) x[i] += u[i] * push;
    }
  }
  /* The joints' speeds kept, and every link moving as they say. */
  for (uint32_t k = 1; k < n; k++) {
    F3dLink *l = &m->links[k];
    if (l->dofs == 1) l->qd = x[l->first_dof];
    if (l->type == F3D_JOINT_SPHERICAL) {
      const Pose parent = placed[l->parent];
      l->spin = f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
      const F3dVec3 e[3] = {f3d_v3(F3D_R(1.0), F3D_R(0.0), F3D_R(0.0)),
                            f3d_v3(F3D_R(0.0), F3D_R(1.0), F3D_R(0.0)),
                            f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(1.0))};
      for (uint32_t i = 0; i < 3; i++) {
        l->spin = f3d_madd(l->spin, rotate(parent.turn, e[i]), x[l->first_dof + i]);
      }
    }
  }
  for (uint32_t k = m->floating ? 0u : 1u; k < n; k++) {
    const uint32_t c = columns(m, placed, k, dofs, cols);
    F3dVec3 v = f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0)), w = v;
    for (uint32_t i = 0; i < c; i++) {
      v = f3d_madd(v, cols[i].lin, x[dofs[i]]);
      w = f3d_madd(w, cols[i].ang, x[dofs[i]]);
    }
    slots[k]->velocity = v;
    slots[k]->spin = w;
  }
}

void f3d_step_multibodies(F3dWorld *world, f3d_real dt) {
  for (uint32_t i = 0; i < world->s.multibody_count; i++) {
    F3dMultibodySlot *m = &world->multibodies[i];
    if (m->live) step_one(world, m, dt);
  }
}
