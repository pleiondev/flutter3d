/*
 * The solver — P9, phase 3: soft contacts solved in substeps, as Box2D v3
 * solves them (Catto, "Solver2D", 2024).
 *
 * A step of dt is cut into substeps of h. Each substep integrates the
 * velocities, applies what each contact pushed with last time (the warm
 * start), solves the contacts with a soft bias that pushes overlap out,
 * moves the bodies, and solves them once more with no bias, so the push
 * that took the overlap out does not stay on as speed. After the last
 * substep, restitution; then the impulses are kept for the next step.
 *
 * **Soft, not stiff.** A contact is a spring of a frequency the substep
 * can carry — at most a quarter of the substep rate, and thirty hertz — and
 * heavily damped, so a pile settles instead of ringing; and the speed it
 * pushes overlap out at is held to three metres a second, so a box spawned
 * inside another comes out instead of being fired out.
 *
 * Every contact is solved in the order of its pair, and every point in its
 * manifold's order, so the same world solves to the same bits everywhere.
 */
#include "f3d_internal.h"

/* The fastest overlap is pushed out at, m/s. */
#define F3D_MAX_PUSH F3D_R(3.0)
/* Below this approach, m/s, nothing bounces: restitution on a resting
 * contact would have it chatter. */
#define F3D_RESTITUTION_THRESHOLD F3D_R(1.0)
/* The contact spring's damping ratio, heavily over critical. */
#define F3D_CONTACT_DAMPING F3D_R(10.0)

int f3d_world_set_substeps(F3dWorld *world, uint32_t substeps) {
  if (substeps == 0 || substeps > 64) return 0;
  world->s.substeps = substeps;
  return 1;
}

int f3d_body_set_friction(F3dWorld *world, F3dBody body, f3d_real friction) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL || !(f3d_finite(friction) && friction >= F3D_R(0.0))) return 0;
  s->friction = friction;
  return 1;
}

int f3d_body_set_restitution(F3dWorld *world, F3dBody body,
                             f3d_real restitution) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL || !(f3d_finite(restitution) && restitution >= F3D_R(0.0) &&
                     restitution <= F3D_R(1.0))) {
    return 0;
  }
  s->restitution = restitution;
  return 1;
}

typedef struct SolverPoint {
  /* From each centre to the point at the step's start, in the world. */
  F3dVec3 ra, rb;
  /* The same in each body's own frame, to follow the bodies as they turn. */
  F3dVec3 local_a, local_b;
  /* Separation at the step's start: minus the depth. */
  f3d_real base;
  f3d_real normal_mass;
  f3d_real tangent_mass[2];
  /* The speed they approached at before the solve, for restitution. */
  f3d_real approach;
  f3d_real most;
} SolverPoint;

typedef struct SolverContact {
  uint32_t a, b;
  uint32_t manifold;
  uint32_t count;
  F3dVec3 normal, tangent[2];
  f3d_real friction, restitution;
  SolverPoint p[F3D_MANIFOLD_POINTS];
} SolverContact;

typedef F3dSolverBody SolverBody;

static int moves(const F3dSlot *s) {
  return s->live && s->type == F3D_BODY_DYNAMIC &&
         !(s->flags & F3D_FLAG_ASLEEP);
}

/* A unit vector square to [n], fixed by n alone. */
static F3dVec3 square_to(F3dVec3 n) {
  const F3dVec3 axis = f3d_abs(n.x) < F3D_R(0.57735)
                           ? f3d_v3(F3D_R(1.0), F3D_R(0.0), F3D_R(0.0))
                           : f3d_v3(F3D_R(0.0), F3D_R(1.0), F3D_R(0.0));
  const F3dVec3 t = f3d_cross(n, axis);
  return f3d_scale(t, F3D_R(1.0) / f3d_sqrt(f3d_dot(t, t)));
}

/* 1 / (J M⁻¹ Jᵀ) along [d] at anchors ra, rb. */
static f3d_real mass_along(const SolverBody *a, const SolverBody *b,
                           F3dVec3 ra, F3dVec3 rb, F3dVec3 d) {
  const F3dVec3 ca = f3d_cross(ra, d), cb = f3d_cross(rb, d);
  const f3d_real k =
      a->inverse_mass + b->inverse_mass +
      f3d_dot(ca, f3d_sym_times(a->inverse_inertia, ca)) +
      f3d_dot(cb, f3d_sym_times(b->inverse_inertia, cb));
  return k > F3D_R(0.0) ? F3D_R(1.0) / k : F3D_R(0.0);
}

/* The velocity of a's point relative to b's. */
static F3dVec3 relative(const F3dSlot *a, const F3dSlot *b, F3dVec3 ra,
                        F3dVec3 rb) {
  const F3dVec3 va = f3d_add(a->velocity, f3d_cross(a->spin, ra));
  const F3dVec3 vb = f3d_add(b->velocity, f3d_cross(b->spin, rb));
  return f3d_sub(va, vb);
}

/* An impulse [p] at the point: into a, out of b. */
static void push(F3dSlot *a, F3dSlot *b, const SolverBody *ba,
                 const SolverBody *bb, F3dVec3 ra, F3dVec3 rb, F3dVec3 p) {
  a->velocity = f3d_madd(a->velocity, p, ba->inverse_mass);
  a->spin = f3d_add(a->spin,
                    f3d_sym_times(ba->inverse_inertia, f3d_cross(ra, p)));
  b->velocity = f3d_madd(b->velocity, p, -bb->inverse_mass);
  b->spin = f3d_sub(b->spin,
                    f3d_sym_times(bb->inverse_inertia, f3d_cross(rb, p)));
}

typedef struct Softness {
  f3d_real bias_rate, mass_scale, impulse_scale;
} Softness;

/* A spring of [hertz] and damping [zeta] as a substep of [h] carries it:
 * Catto's soft step, the spring and damper folded into the impulse. */
static Softness soft(f3d_real hertz, f3d_real zeta, f3d_real h) {
  const f3d_real omega = F3D_R(2.0) * F3D_PI * hertz;
  const f3d_real a1 = F3D_R(2.0) * zeta + h * omega;
  const f3d_real a2 = h * omega * a1;
  const f3d_real a3 = F3D_R(1.0) / (F3D_R(1.0) + a2);
  Softness s;
  s.bias_rate = omega / a1;
  s.mass_scale = a2 * a3;
  s.impulse_scale = a3;
  return s;
}

static void solve(F3dWorld *world, SolverContact *contacts, uint32_t count,
                  const SolverBody *bodies, Softness softness, f3d_real h,
                  int use_bias) {
  const f3d_real inv_h = F3D_R(1.0) / h;
  for (uint32_t c = 0; c < count; c++) {
    SolverContact *sc = &contacts[c];
    F3dManifold *m = &world->manifolds[sc->manifold];
    F3dSlot *a = &world->slots[sc->a];
    F3dSlot *b = &world->slots[sc->b];
    const SolverBody *ba = &bodies[sc->a], *bb = &bodies[sc->b];
    const F3dMat3 qa = f3d_mat_of(a->orientation);
    const F3dMat3 qb = f3d_mat_of(b->orientation);
    const F3dVec3 n = sc->normal;
    const F3dVec3 da = f3d_sub(a->position, ba->start);
    const F3dVec3 db = f3d_sub(b->position, bb->start);
    for (uint32_t k = 0; k < sc->count; k++) {
      SolverPoint *p = &sc->p[k];
      F3dContactPoint *mp = &m->points[k];
      /* Where the two points are now, against where they started. */
      const F3dVec3 ra_now =
          f3d_add(f3d_add(f3d_scale(qa.c[0], p->local_a.x),
                          f3d_scale(qa.c[1], p->local_a.y)),
                  f3d_scale(qa.c[2], p->local_a.z));
      const F3dVec3 rb_now =
          f3d_add(f3d_add(f3d_scale(qb.c[0], p->local_b.x),
                          f3d_scale(qb.c[1], p->local_b.y)),
                  f3d_scale(qb.c[2], p->local_b.z));
      const F3dVec3 moved = f3d_sub(f3d_add(da, f3d_sub(ra_now, p->ra)),
                                    f3d_add(db, f3d_sub(rb_now, p->rb)));
      const f3d_real s = p->base + f3d_dot(moved, n);
      f3d_real bias = F3D_R(0.0), mass_scale = F3D_R(1.0);
      f3d_real impulse_scale = F3D_R(0.0);
      if (s > F3D_R(0.0)) {
        /* Apart: they may close the gap this substep, and no more. */
        bias = s * inv_h;
      } else if (use_bias) {
        bias = f3d_max(softness.bias_rate * f3d_min(s + F3D_LINEAR_SLOP,
                                                    F3D_R(0.0)),
                       -F3D_MAX_PUSH);
        mass_scale = softness.mass_scale;
        impulse_scale = softness.impulse_scale;
      }
      const f3d_real vn = f3d_dot(relative(a, b, p->ra, p->rb), n);
      const f3d_real lambda = -p->normal_mass * mass_scale * (vn + bias) -
                              impulse_scale * mp->normal_impulse;
      const f3d_real total = f3d_max(mp->normal_impulse + lambda, F3D_R(0.0));
      const f3d_real delta = total - mp->normal_impulse;
      mp->normal_impulse = total;
      p->most = f3d_max(p->most, total);
      push(a, b, ba, bb, p->ra, p->rb, f3d_scale(n, delta));
    }
    /* Friction, inside Coulomb's circle of what the normal pushes with. */
    for (uint32_t k = 0; k < sc->count; k++) {
      SolverPoint *p = &sc->p[k];
      F3dContactPoint *mp = &m->points[k];
      const F3dVec3 v = relative(a, b, p->ra, p->rb);
      const f3d_real t0 = mp->tangent_impulse[0] -
                          p->tangent_mass[0] * f3d_dot(v, sc->tangent[0]);
      const f3d_real t1 = mp->tangent_impulse[1] -
                          p->tangent_mass[1] * f3d_dot(v, sc->tangent[1]);
      const f3d_real limit = sc->friction * mp->normal_impulse;
      const f3d_real length = f3d_sqrt(t0 * t0 + t1 * t1);
      const f3d_real keep =
          length > limit && length > F3D_R(0.0) ? limit / length : F3D_R(1.0);
      const f3d_real n0 = t0 * keep, n1 = t1 * keep;
      const F3dVec3 dp =
          f3d_add(f3d_scale(sc->tangent[0], n0 - mp->tangent_impulse[0]),
                  f3d_scale(sc->tangent[1], n1 - mp->tangent_impulse[1]));
      mp->tangent_impulse[0] = n0;
      mp->tangent_impulse[1] = n1;
      push(a, b, ba, bb, p->ra, p->rb, dp);
    }
  }
}

static void warm_start(F3dWorld *world, const SolverContact *contacts,
                       uint32_t count, const SolverBody *bodies) {
  for (uint32_t c = 0; c < count; c++) {
    const SolverContact *sc = &contacts[c];
    const F3dManifold *m = &world->manifolds[sc->manifold];
    F3dSlot *a = &world->slots[sc->a];
    F3dSlot *b = &world->slots[sc->b];
    for (uint32_t k = 0; k < sc->count; k++) {
      const F3dContactPoint *mp = &m->points[k];
      const F3dVec3 p =
          f3d_add(f3d_scale(sc->normal, mp->normal_impulse),
                  f3d_add(f3d_scale(sc->tangent[0], mp->tangent_impulse[0]),
                          f3d_scale(sc->tangent[1], mp->tangent_impulse[1])));
      push(a, b, &bodies[sc->a], &bodies[sc->b], sc->p[k].ra, sc->p[k].rb, p);
    }
  }
}

/* Restitution, once the substeps are done: a contact that was closing
 * faster than the threshold, and was pushed on, gets back its share of the
 * approach speed. */
static void restitute(F3dWorld *world, SolverContact *contacts,
                      uint32_t count, const SolverBody *bodies) {
  for (uint32_t c = 0; c < count; c++) {
    SolverContact *sc = &contacts[c];
    if (sc->restitution == F3D_R(0.0)) continue;
    F3dManifold *m = &world->manifolds[sc->manifold];
    F3dSlot *a = &world->slots[sc->a];
    F3dSlot *b = &world->slots[sc->b];
    for (uint32_t k = 0; k < sc->count; k++) {
      SolverPoint *p = &sc->p[k];
      F3dContactPoint *mp = &m->points[k];
      if (p->approach > -F3D_RESTITUTION_THRESHOLD || p->most == F3D_R(0.0)) {
        continue;
      }
      const f3d_real vn = f3d_dot(relative(a, b, p->ra, p->rb), sc->normal);
      const f3d_real lambda =
          -p->normal_mass * (vn + sc->restitution * p->approach);
      const f3d_real total = f3d_max(mp->normal_impulse + lambda, F3D_R(0.0));
      const f3d_real delta = total - mp->normal_impulse;
      mp->normal_impulse = total;
      push(a, b, &bodies[sc->a], &bodies[sc->b], p->ra, p->rb,
           f3d_scale(sc->normal, delta));
    }
  }
}

void f3d_step_solve(F3dWorld *world, f3d_real dt) {
  const uint32_t used = world->s.used;
  const uint32_t substeps = world->s.substeps;
  const f3d_real h = dt / (f3d_real)substeps;
  /* The bodies, then the contacts, in the world's scratch. */
  const size_t body_bytes = ((size_t)used * sizeof(SolverBody) + 15u) &
                            ~(size_t)15u;
  uint8_t *base = (uint8_t *)f3d_scratch(
      world, body_bytes + (size_t)world->s.manifold_count *
                              sizeof(SolverContact));
  if (base == NULL && used > 0) return;
  SolverBody *bodies = (SolverBody *)base;
  SolverContact *contacts = (SolverContact *)(base + body_bytes);
  for (uint32_t i = 0; i < used; i++) {
    const F3dSlot *s = &world->slots[i];
    SolverBody *sb = &bodies[i];
    f3d_zero(sb, sizeof *sb);
    if (!s->live) continue;
    sb->start = s->position;
    if (moves(s)) {
      sb->inverse_mass = s->inverse_mass;
      sb->inverse_inertia = f3d_sym_turned(s->orientation, s->inverse_inertia);
    }
  }
  /* Each manifold the solver can act on — one of its bodies awake and
   * dynamic — made ready: anchors, masses, and the approach speed. */
  uint32_t count = 0;
  for (uint32_t i = 0; i < world->s.manifold_count; i++) {
    F3dManifold *m = &world->manifolds[i];
    const uint32_t a = (uint32_t)(m->a & 0xffffffffu);
    const uint32_t b = (uint32_t)(m->b & 0xffffffffu);
    const F3dSlot *sa = &world->slots[a], *sb = &world->slots[b];
    if (!moves(sa) && !moves(sb)) continue;
    SolverContact *sc = &contacts[count++];
    sc->a = a;
    sc->b = b;
    sc->manifold = i;
    sc->count = m->count;
    sc->normal = m->normal;
    sc->tangent[0] = square_to(m->normal);
    sc->tangent[1] = f3d_cross(m->normal, sc->tangent[0]);
    /* Friction the geometric mean, so either surface can make it slippery;
     * restitution the larger, so either can make it bounce. */
    sc->friction = f3d_sqrt(sa->friction * sb->friction);
    sc->restitution = f3d_max(sa->restitution, sb->restitution);
    const F3dMat3 qa = f3d_mat_of(sa->orientation);
    const F3dMat3 qb = f3d_mat_of(sb->orientation);
    for (uint32_t k = 0; k < m->count; k++) {
      SolverPoint *p = &sc->p[k];
      const F3dContactPoint *mp = &m->points[k];
      p->ra = f3d_sub(mp->point, sa->position);
      p->rb = f3d_sub(mp->point, sb->position);
      p->local_a = f3d_v3(f3d_dot(qa.c[0], p->ra), f3d_dot(qa.c[1], p->ra),
                          f3d_dot(qa.c[2], p->ra));
      p->local_b = f3d_v3(f3d_dot(qb.c[0], p->rb), f3d_dot(qb.c[1], p->rb),
                          f3d_dot(qb.c[2], p->rb));
      p->base = -mp->depth;
      p->normal_mass =
          mass_along(&bodies[a], &bodies[b], p->ra, p->rb, m->normal);
      p->tangent_mass[0] =
          mass_along(&bodies[a], &bodies[b], p->ra, p->rb, sc->tangent[0]);
      p->tangent_mass[1] =
          mass_along(&bodies[a], &bodies[b], p->ra, p->rb, sc->tangent[1]);
      p->approach = f3d_dot(relative(sa, sb, p->ra, p->rb), m->normal);
      p->most = F3D_R(0.0);
    }
  }
  /* A quarter of the substep rate, and no more than thirty hertz. */
  const f3d_real hertz = f3d_min(F3D_R(30.0), F3D_R(0.25) / h);
  const Softness softness = soft(hertz, F3D_CONTACT_DAMPING, h);
  for (uint32_t step = 0; step < substeps; step++) {
    for (uint32_t i = 0; i < used; i++) {
      F3dSlot *s = &world->slots[i];
      if (moves(s)) f3d_integrate_velocity(world, s, h);
    }
    f3d_warm_joints(world, bodies);
    warm_start(world, contacts, count, bodies);
    f3d_solve_joints(world, bodies, h, 1);
    solve(world, contacts, count, bodies, softness, h, 1);
    for (uint32_t i = 0; i < used; i++) {
      F3dSlot *s = &world->slots[i];
      if (moves(s)) f3d_integrate_position(s, h);
    }
    f3d_solve_joints(world, bodies, h, 0);
    solve(world, contacts, count, bodies, softness, h, 0);
  }
  restitute(world, contacts, count, bodies);
  for (uint32_t i = 0; i < used; i++) {
    F3dSlot *s = &world->slots[i];
    if (s->live) f3d_finish_motion(world, s, dt);
  }
}
