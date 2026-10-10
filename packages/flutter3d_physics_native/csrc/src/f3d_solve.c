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

/* A body's turn since the step began, as a small rotation vector: twice the
 * vector part of q · q₀⁻¹. */
static F3dVec3 turned_since(F3dQuat q, F3dQuat q0) {
  const f3d_real x = q.w * -q0.x + q.x * q0.w + q.y * -q0.z - q.z * -q0.y;
  const f3d_real y = q.w * -q0.y - q.x * -q0.z + q.y * q0.w + q.z * -q0.x;
  const f3d_real z = q.w * -q0.z + q.x * -q0.y - q.y * -q0.x + q.z * q0.w;
  const f3d_real w = q.w * q0.w + q.x * q0.x + q.y * q0.y + q.z * q0.z;
  const f3d_real k = w < F3D_R(0.0) ? F3D_R(-2.0) : F3D_R(2.0);
  return f3d_v3(x * k, y * k, z * k);
}

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

/* What the contacts read and write of each body, packed tight: its
 * velocity and spin, and how far it has moved and turned since the step
 * began — the turn worked out once a body, not once a contact. Gathered
 * from the slots before each stage of contacts and scattered back after,
 * so the joints and the integration between stages see the slots. */
typedef struct Motion {
  F3dVec3 v, w;
  F3dVec3 moved, turned;
} Motion;

static void gather(const F3dWorld *world, const SolverBody *bodies, Motion *motion,
                   uint32_t begin, uint32_t end) {
  for (uint32_t i = begin; i < end; i++) {
    const F3dSlot *s = &world->slots[i];
    if (!s->live) continue;
    Motion *m = &motion[i];
    m->v = s->velocity;
    m->w = s->spin;
    m->moved = f3d_sub(s->position, bodies[i].start);
    m->turned = turned_since(s->orientation, bodies[i].turn);
  }
}

static void scatter(F3dWorld *world, const Motion *motion, uint32_t begin, uint32_t end) {
  for (uint32_t i = begin; i < end; i++) {
    F3dSlot *s = &world->slots[i];
    if (!moves(s)) continue;
    s->velocity = motion[i].v;
    s->spin = motion[i].w;
  }
}

static F3dVec3 relative_motion(const Motion *a, const Motion *b, F3dVec3 ra, F3dVec3 rb) {
  const F3dVec3 va = f3d_add(a->v, f3d_cross(a->w, ra));
  const F3dVec3 vb = f3d_add(b->v, f3d_cross(b->w, rb));
  return f3d_sub(va, vb);
}

/* An impulse [p] at the point: into a, out of b. A body that does not
 * move is left untouched rather than given nothing: in the fast mode a
 * fixed floor is in many contacts of one colour at once, and nothing may
 * write it. */
static void push(Motion *a, Motion *b, const SolverBody *ba, const SolverBody *bb,
                 F3dVec3 ra, F3dVec3 rb, F3dVec3 p) {
  if (ba->inverse_mass > F3D_R(0.0)) {
    a->v = f3d_madd(a->v, p, ba->inverse_mass);
    a->w = f3d_add(a->w, f3d_sym_times(ba->inverse_inertia, f3d_cross(ra, p)));
  }
  if (bb->inverse_mass > F3D_R(0.0)) {
    b->v = f3d_madd(b->v, p, -bb->inverse_mass);
    b->w = f3d_sub(b->w, f3d_sym_times(bb->inverse_inertia, f3d_cross(rb, p)));
  }
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

static void solve_contact(F3dWorld *world, SolverContact *sc, const SolverBody *bodies,
                          Motion *motion, Softness softness, f3d_real inv_h, int use_bias) {
  {
    F3dManifold *m = &world->manifolds[sc->manifold];
    Motion *a = &motion[sc->a];
    Motion *b = &motion[sc->b];
    const SolverBody *ba = &bodies[sc->a], *bb = &bodies[sc->b];
    const F3dVec3 turned_a = a->turned;
    const F3dVec3 turned_b = b->turned;
    const F3dVec3 n = sc->normal;
    const F3dVec3 da = a->moved;
    const F3dVec3 db = b->moved;
    for (uint32_t k = 0; k < sc->count; k++) {
      SolverPoint *p = &sc->p[k];
      F3dContactPoint *mp = &m->points[k];
      /* Where the two points are now, against where they started. */
      /* How the two points have moved since the step began: each body's
       * shift, and its turn taken to first order, Δφ × r. Not the anchor
       * turned whole with the body: a rolling ball touches the floor at a
       * new point of itself each moment, and the old point carried round
       * would read a gap where it rests — a ball rolling at ten metres a
       * second sank two centimetres. */
      const F3dVec3 moved =
          f3d_sub(f3d_add(da, f3d_cross(turned_a, p->ra)),
                  f3d_add(db, f3d_cross(turned_b, p->rb)));
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
      const f3d_real vn = f3d_dot(relative_motion(a, b, p->ra, p->rb), n);
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
      const F3dVec3 v = relative_motion(a, b, p->ra, p->rb);
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

static void solve(F3dWorld *world, SolverContact *contacts, uint32_t count,
                  const SolverBody *bodies, Motion *motion, Softness softness, f3d_real h,
                  int use_bias) {
  const f3d_real inv_h = F3D_R(1.0) / h;
  gather(world, bodies, motion, 0, world->s.used);
  for (uint32_t c = 0; c < count; c++) {
    solve_contact(world, &contacts[c], bodies, motion, softness, inv_h, use_bias);
  }
  scatter(world, motion, 0, world->s.used);
}

static void warm_contact(F3dWorld *world, const SolverContact *sc, const SolverBody *bodies,
                         Motion *motion) {
  {
    const F3dManifold *m = &world->manifolds[sc->manifold];
    Motion *a = &motion[sc->a];
    Motion *b = &motion[sc->b];
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

static void warm_start(F3dWorld *world, const SolverContact *contacts,
                       uint32_t count, const SolverBody *bodies, Motion *motion) {
  gather(world, bodies, motion, 0, world->s.used);
  for (uint32_t c = 0; c < count; c++) warm_contact(world, &contacts[c], bodies, motion);
  scatter(world, motion, 0, world->s.used);
}

/* Restitution, once the substeps are done: a contact that was closing
 * faster than the threshold, and was pushed on, gets back its share of the
 * approach speed. */
static void restitute_contact(F3dWorld *world, SolverContact *sc, const SolverBody *bodies,
                              Motion *motion) {
  if (sc->restitution == F3D_R(0.0)) return;
  {
    F3dManifold *m = &world->manifolds[sc->manifold];
    Motion *a = &motion[sc->a];
    Motion *b = &motion[sc->b];
    for (uint32_t k = 0; k < sc->count; k++) {
      SolverPoint *p = &sc->p[k];
      F3dContactPoint *mp = &m->points[k];
      if (p->approach > -F3D_RESTITUTION_THRESHOLD || p->most == F3D_R(0.0)) {
        continue;
      }
      const f3d_real vn = f3d_dot(relative_motion(a, b, p->ra, p->rb), sc->normal);
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

static void restitute(F3dWorld *world, SolverContact *contacts,
                      uint32_t count, const SolverBody *bodies, Motion *motion) {
  gather(world, bodies, motion, 0, world->s.used);
  for (uint32_t c = 0; c < count; c++) restitute_contact(world, &contacts[c], bodies, motion);
  scatter(world, motion, 0, world->s.used);
}

/* ------------------------------------------------------------- wide solve */

/* The fast mode solves a colour's contacts F3D_LANES at a time: a batch of
 * contacts that share no moving body, each in a lane of a vector, every
 * lane doing what the scalar functions above do, operation for operation,
 * so a lane's bits are a contact's bits solved alone. What a scalar
 * contact decides with a branch, a lane decides with a mask; a lane with
 * fewer points, and a body that does not move, is masked out, not skipped.
 * Vectors as GCC and Clang build them; elsewhere — MSVC — the same
 * operations a lane at a time, to the same bits. */
#define F3D_LANES 4

#if (defined(__clang__) || defined(__GNUC__)) && !defined(F3D_NO_SIMD)
#ifdef F3D_REAL_DOUBLE
typedef int64_t WLaneInt;
#else
typedef int32_t WLaneInt;
#endif
typedef f3d_real WReal __attribute__((vector_size(F3D_LANES * sizeof(f3d_real))));
typedef WLaneInt WMask __attribute__((vector_size(F3D_LANES * sizeof(f3d_real))));
#define W_LANE(v, l) ((v)[l])
static inline WReal w_add(WReal a, WReal b) { return a + b; }
static inline WReal w_sub(WReal a, WReal b) { return a - b; }
static inline WReal w_mul(WReal a, WReal b) { return a * b; }
static inline WReal w_div(WReal a, WReal b) { return a / b; }
static inline WReal w_neg(WReal a) { return -a; }
static inline WReal w_splat(f3d_real x) { return (WReal){0} + x; }
static inline WMask w_gt(WReal a, WReal b) { return (WMask)(a > b); }
static inline WMask w_lt(WReal a, WReal b) { return (WMask)(a < b); }
static inline WMask w_eq(WReal a, WReal b) { return (WMask)(a == b); }
static inline WMask w_and(WMask a, WMask b) { return a & b; }
static inline WMask w_not(WMask a) { return ~a; }
static inline WReal w_sel(WMask m, WReal a, WReal b) {
  return (WReal)(((WMask)a & m) | ((WMask)b & ~m));
}
#else
typedef struct WReal {
  f3d_real l[F3D_LANES];
} WReal;
typedef struct WMask {
  int l[F3D_LANES];
} WMask;
#define W_LANE(v, i) ((v).l[i])
#define W_EACH(op)                                    \
  WReal r;                                            \
  for (int i = 0; i < F3D_LANES; i++) r.l[i] = (op);  \
  return r
#define W_TEST(op)                                    \
  WMask r;                                            \
  for (int i = 0; i < F3D_LANES; i++) r.l[i] = (op);  \
  return r
static inline WReal w_add(WReal a, WReal b) { W_EACH(a.l[i] + b.l[i]); }
static inline WReal w_sub(WReal a, WReal b) { W_EACH(a.l[i] - b.l[i]); }
static inline WReal w_mul(WReal a, WReal b) { W_EACH(a.l[i] * b.l[i]); }
static inline WReal w_div(WReal a, WReal b) { W_EACH(a.l[i] / b.l[i]); }
static inline WReal w_neg(WReal a) { W_EACH(-a.l[i]); }
static inline WReal w_splat(f3d_real x) { W_EACH(x); }
static inline WMask w_gt(WReal a, WReal b) { W_TEST(a.l[i] > b.l[i]); }
static inline WMask w_lt(WReal a, WReal b) { W_TEST(a.l[i] < b.l[i]); }
static inline WMask w_eq(WReal a, WReal b) { W_TEST(a.l[i] == b.l[i]); }
static inline WMask w_and(WMask a, WMask b) { W_TEST(a.l[i] && b.l[i]); }
static inline WMask w_not(WMask a) { W_TEST(!a.l[i]); }
static inline WReal w_sel(WMask m, WReal a, WReal b) { W_EACH(m.l[i] ? a.l[i] : b.l[i]); }
#endif

static inline WReal w_sqrt(WReal a) {
  WReal r = a;
  for (int i = 0; i < F3D_LANES; i++) W_LANE(r, i) = f3d_sqrt(W_LANE(a, i));
  return r;
}

/* f3d_max and f3d_min, a lane at a time. */
static inline WReal w_max(WReal a, WReal b) { return w_sel(w_gt(a, b), a, b); }
static inline WReal w_min(WReal a, WReal b) { return w_sel(w_lt(a, b), a, b); }

typedef struct WVec3 {
  WReal x, y, z;
} WVec3;

typedef struct WSym3 {
  WReal xx, yy, zz, xy, xz, yz;
} WSym3;

static inline WVec3 wv(WReal x, WReal y, WReal z) {
  WVec3 v;
  v.x = x;
  v.y = y;
  v.z = z;
  return v;
}
static inline WVec3 wv_add(WVec3 a, WVec3 b) {
  return wv(w_add(a.x, b.x), w_add(a.y, b.y), w_add(a.z, b.z));
}
static inline WVec3 wv_sub(WVec3 a, WVec3 b) {
  return wv(w_sub(a.x, b.x), w_sub(a.y, b.y), w_sub(a.z, b.z));
}
static inline WVec3 wv_scale(WVec3 a, WReal k) {
  return wv(w_mul(a.x, k), w_mul(a.y, k), w_mul(a.z, k));
}
static inline WVec3 wv_madd(WVec3 a, WVec3 b, WReal k) {
  return wv(w_add(a.x, w_mul(b.x, k)), w_add(a.y, w_mul(b.y, k)), w_add(a.z, w_mul(b.z, k)));
}
static inline WReal wv_dot(WVec3 a, WVec3 b) {
  return w_add(w_add(w_mul(a.x, b.x), w_mul(a.y, b.y)), w_mul(a.z, b.z));
}
static inline WVec3 wv_cross(WVec3 a, WVec3 b) {
  return wv(w_sub(w_mul(a.y, b.z), w_mul(a.z, b.y)), w_sub(w_mul(a.z, b.x), w_mul(a.x, b.z)),
            w_sub(w_mul(a.x, b.y), w_mul(a.y, b.x)));
}
static inline WVec3 wsym_times(WSym3 m, WVec3 v) {
  return wv(w_add(w_add(w_mul(m.xx, v.x), w_mul(m.xy, v.y)), w_mul(m.xz, v.z)),
            w_add(w_add(w_mul(m.xy, v.x), w_mul(m.yy, v.y)), w_mul(m.yz, v.z)),
            w_add(w_add(w_mul(m.xz, v.x), w_mul(m.yz, v.y)), w_mul(m.zz, v.z)));
}
static inline WVec3 wv_sel(WMask m, WVec3 a, WVec3 b) {
  return wv(w_sel(m, a.x, b.x), w_sel(m, a.y, b.y), w_sel(m, a.z, b.z));
}

static inline void wv_set(WVec3 *v, int l, F3dVec3 s) {
  W_LANE(v->x, l) = s.x;
  W_LANE(v->y, l) = s.y;
  W_LANE(v->z, l) = s.z;
}
static inline F3dVec3 wv_get(WVec3 v, int l) {
  return f3d_v3(W_LANE(v.x, l), W_LANE(v.y, l), W_LANE(v.z, l));
}

typedef struct WidePoint {
  WVec3 ra, rb;
  WReal base, normal_mass, tangent_mass0, tangent_mass1, approach, most;
  WReal normal_impulse, tangent_impulse0, tangent_impulse1;
  /* The lanes whose contact has this point. */
  WMask live;
} WidePoint;

typedef struct WideBatch {
  /* Each lane's contact, its bodies, and how many lanes are filled. */
  uint32_t contact[F3D_LANES];
  uint32_t a[F3D_LANES], b[F3D_LANES];
  uint32_t lanes, points;
  WVec3 normal, tangent0, tangent1;
  WReal friction, restitution;
  WReal mass_a, mass_b;
  WSym3 inertia_a, inertia_b;
  /* The lanes whose body moves, and so is pushed. */
  WMask moves_a, moves_b;
  WidePoint p[F3D_MANIFOLD_POINTS];
} WideBatch;

/* Lane [l] of [batch] made from contact [c]: its normal and tangents, its
 * points and their impulses so far, and its bodies' masses. */
static void wide_fill_lane(WideBatch *w, int l, const F3dWorld *world, const SolverBody *bodies,
                           const SolverContact *contacts, uint32_t c) {
  const SolverContact *sc = &contacts[c];
  const F3dManifold *m = &world->manifolds[sc->manifold];
  const SolverBody *ba = &bodies[sc->a], *bb = &bodies[sc->b];
  w->contact[l] = c;
  w->a[l] = sc->a;
  w->b[l] = sc->b;
  wv_set(&w->normal, l, sc->normal);
  wv_set(&w->tangent0, l, sc->tangent[0]);
  wv_set(&w->tangent1, l, sc->tangent[1]);
  W_LANE(w->friction, l) = sc->friction;
  W_LANE(w->restitution, l) = sc->restitution;
  W_LANE(w->mass_a, l) = ba->inverse_mass;
  W_LANE(w->mass_b, l) = bb->inverse_mass;
  W_LANE(w->inertia_a.xx, l) = ba->inverse_inertia.xx;
  W_LANE(w->inertia_a.yy, l) = ba->inverse_inertia.yy;
  W_LANE(w->inertia_a.zz, l) = ba->inverse_inertia.zz;
  W_LANE(w->inertia_a.xy, l) = ba->inverse_inertia.xy;
  W_LANE(w->inertia_a.xz, l) = ba->inverse_inertia.xz;
  W_LANE(w->inertia_a.yz, l) = ba->inverse_inertia.yz;
  W_LANE(w->inertia_b.xx, l) = bb->inverse_inertia.xx;
  W_LANE(w->inertia_b.yy, l) = bb->inverse_inertia.yy;
  W_LANE(w->inertia_b.zz, l) = bb->inverse_inertia.zz;
  W_LANE(w->inertia_b.xy, l) = bb->inverse_inertia.xy;
  W_LANE(w->inertia_b.xz, l) = bb->inverse_inertia.xz;
  W_LANE(w->inertia_b.yz, l) = bb->inverse_inertia.yz;
  W_LANE(w->moves_a, l) = ba->inverse_mass > F3D_R(0.0) ? -1 : 0;
  W_LANE(w->moves_b, l) = bb->inverse_mass > F3D_R(0.0) ? -1 : 0;
  if (sc->count > w->points) w->points = sc->count;
  for (uint32_t k = 0; k < F3D_MANIFOLD_POINTS; k++) {
    WidePoint *wp = &w->p[k];
    if (k >= sc->count) {
      W_LANE(wp->live, l) = 0;
      continue;
    }
    const SolverPoint *p = &sc->p[k];
    const F3dContactPoint *mp = &m->points[k];
    W_LANE(wp->live, l) = -1;
    wv_set(&wp->ra, l, p->ra);
    wv_set(&wp->rb, l, p->rb);
    W_LANE(wp->base, l) = p->base;
    W_LANE(wp->normal_mass, l) = p->normal_mass;
    W_LANE(wp->tangent_mass0, l) = p->tangent_mass[0];
    W_LANE(wp->tangent_mass1, l) = p->tangent_mass[1];
    W_LANE(wp->approach, l) = p->approach;
    W_LANE(wp->most, l) = p->most;
    W_LANE(wp->normal_impulse, l) = mp->normal_impulse;
    W_LANE(wp->tangent_impulse0, l) = mp->tangent_impulse[0];
    W_LANE(wp->tangent_impulse1, l) = mp->tangent_impulse[1];
  }
}

/* A batch of the contacts [first, first + n) of [order], n at most
 * F3D_LANES; an empty lane repeats the first lane's bodies, read and never
 * written, and has no points. */
static void wide_fill(WideBatch *w, const F3dWorld *world, const SolverBody *bodies,
                      const SolverContact *contacts, const uint32_t *order, uint32_t first,
                      uint32_t n) {
  f3d_zero(w, sizeof *w);
  w->lanes = n;
  for (uint32_t l = 0; l < F3D_LANES; l++) {
    if (l < n) {
      wide_fill_lane(w, (int)l, world, bodies, contacts, order[first + l]);
      continue;
    }
    w->contact[l] = UINT32_MAX;
    w->a[l] = w->a[0];
    w->b[l] = w->b[0];
    W_LANE(w->moves_a, l) = 0;
    W_LANE(w->moves_b, l) = 0;
    for (uint32_t k = 0; k < F3D_MANIFOLD_POINTS; k++) W_LANE(w->p[k].live, l) = 0;
  }
}

/* The batch's impulses back into its manifolds, once the step is done. */
static void wide_store(const WideBatch *w, F3dWorld *world, const SolverContact *contacts) {
  for (uint32_t l = 0; l < w->lanes; l++) {
    const SolverContact *sc = &contacts[w->contact[l]];
    F3dManifold *m = &world->manifolds[sc->manifold];
    for (uint32_t k = 0; k < sc->count; k++) {
      m->points[k].normal_impulse = W_LANE(w->p[k].normal_impulse, l);
      m->points[k].tangent_impulse[0] = W_LANE(w->p[k].tangent_impulse0, l);
      m->points[k].tangent_impulse[1] = W_LANE(w->p[k].tangent_impulse1, l);
    }
  }
}

/* The two sides' motion, a lane a contact. */
typedef struct WideMotion {
  WVec3 va, wa, vb, wb;
  WVec3 moved_a, turned_a, moved_b, turned_b;
} WideMotion;

static void wide_load(const WideBatch *w, const Motion *motion, WideMotion *m) {
  for (int l = 0; l < F3D_LANES; l++) {
    const Motion *a = &motion[w->a[l]], *b = &motion[w->b[l]];
    wv_set(&m->va, l, a->v);
    wv_set(&m->wa, l, a->w);
    wv_set(&m->moved_a, l, a->moved);
    wv_set(&m->turned_a, l, a->turned);
    wv_set(&m->vb, l, b->v);
    wv_set(&m->wb, l, b->w);
    wv_set(&m->moved_b, l, b->moved);
    wv_set(&m->turned_b, l, b->turned);
  }
}

/* Back into the motion the lanes whose bodies move: no two lanes of a
 * batch share one. */
static void wide_save(const WideBatch *w, const WideMotion *m, Motion *motion) {
  for (int l = 0; l < F3D_LANES; l++) {
    if (W_LANE(w->moves_a, l)) {
      motion[w->a[l]].v = wv_get(m->va, l);
      motion[w->a[l]].w = wv_get(m->wa, l);
    }
    if (W_LANE(w->moves_b, l)) {
      motion[w->b[l]].v = wv_get(m->vb, l);
      motion[w->b[l]].w = wv_get(m->wb, l);
    }
  }
}

static WVec3 wide_relative(const WideMotion *m, WVec3 ra, WVec3 rb) {
  const WVec3 va = wv_add(m->va, wv_cross(m->wa, ra));
  const WVec3 vb = wv_add(m->vb, wv_cross(m->wb, rb));
  return wv_sub(va, vb);
}

/* push(), for the lanes in [on]. */
static void wide_push(const WideBatch *w, WideMotion *m, WMask on, WVec3 ra, WVec3 rb, WVec3 p) {
  const WMask a = w_and(on, w->moves_a), b = w_and(on, w->moves_b);
  m->va = wv_sel(a, wv_madd(m->va, p, w->mass_a), m->va);
  m->wa = wv_sel(a, wv_add(m->wa, wsym_times(w->inertia_a, wv_cross(ra, p))), m->wa);
  m->vb = wv_sel(b, wv_madd(m->vb, p, w_neg(w->mass_b)), m->vb);
  m->wb = wv_sel(b, wv_sub(m->wb, wsym_times(w->inertia_b, wv_cross(rb, p))), m->wb);
}

/* warm_contact(), a batch at once. */
static void wide_warm(WideBatch *w, Motion *motion) {
  WideMotion m;
  wide_load(w, motion, &m);
  for (uint32_t k = 0; k < w->points; k++) {
    const WidePoint *p = &w->p[k];
    const WVec3 push =
        wv_add(wv_scale(w->normal, p->normal_impulse),
               wv_add(wv_scale(w->tangent0, p->tangent_impulse0),
                      wv_scale(w->tangent1, p->tangent_impulse1)));
    wide_push(w, &m, p->live, p->ra, p->rb, push);
  }
  wide_save(w, &m, motion);
}

/* solve_contact(), a batch at once. */
static void wide_solve(WideBatch *w, Motion *motion, Softness softness, f3d_real inv_h,
                       int use_bias) {
  WideMotion m;
  wide_load(w, motion, &m);
  const WReal zero = w_splat(F3D_R(0.0)), one = w_splat(F3D_R(1.0));
  const WReal rate = w_splat(softness.bias_rate);
  const WReal mass_scale_soft = w_splat(softness.mass_scale);
  const WReal impulse_scale_soft = w_splat(softness.impulse_scale);
  const WReal slop = w_splat(F3D_LINEAR_SLOP), most_push = w_splat(-F3D_MAX_PUSH);
  const WReal per_h = w_splat(inv_h);
  for (uint32_t k = 0; k < w->points; k++) {
    WidePoint *p = &w->p[k];
    const WVec3 moved = wv_sub(wv_add(m.moved_a, wv_cross(m.turned_a, p->ra)),
                               wv_add(m.moved_b, wv_cross(m.turned_b, p->rb)));
    const WReal s = w_add(p->base, wv_dot(moved, w->normal));
    const WMask apart = w_gt(s, zero);
    WReal bias = w_sel(apart, w_mul(s, per_h), zero);
    WReal mass_scale = one, impulse_scale = zero;
    if (use_bias) {
      const WReal soft_bias = w_max(w_mul(rate, w_min(w_add(s, slop), zero)), most_push);
      bias = w_sel(apart, bias, soft_bias);
      mass_scale = w_sel(apart, one, mass_scale_soft);
      impulse_scale = w_sel(apart, zero, impulse_scale_soft);
    }
    const WReal vn = wv_dot(wide_relative(&m, p->ra, p->rb), w->normal);
    const WReal lambda = w_sub(w_mul(w_mul(w_neg(p->normal_mass), mass_scale), w_add(vn, bias)),
                               w_mul(impulse_scale, p->normal_impulse));
    const WReal total = w_max(w_add(p->normal_impulse, lambda), zero);
    const WReal delta = w_sub(total, p->normal_impulse);
    p->normal_impulse = w_sel(p->live, total, p->normal_impulse);
    p->most = w_sel(p->live, w_max(p->most, total), p->most);
    wide_push(w, &m, p->live, p->ra, p->rb, wv_scale(w->normal, delta));
  }
  for (uint32_t k = 0; k < w->points; k++) {
    WidePoint *p = &w->p[k];
    const WVec3 v = wide_relative(&m, p->ra, p->rb);
    const WReal t0 = w_sub(p->tangent_impulse0, w_mul(p->tangent_mass0, wv_dot(v, w->tangent0)));
    const WReal t1 = w_sub(p->tangent_impulse1, w_mul(p->tangent_mass1, wv_dot(v, w->tangent1)));
    const WReal limit = w_mul(w->friction, p->normal_impulse);
    const WReal length = w_sqrt(w_add(w_mul(t0, t0), w_mul(t1, t1)));
    const WMask clamp = w_and(w_gt(length, limit), w_gt(length, zero));
    const WReal keep = w_sel(clamp, w_div(limit, length), one);
    const WReal n0 = w_mul(t0, keep), n1 = w_mul(t1, keep);
    const WVec3 push = wv_add(wv_scale(w->tangent0, w_sub(n0, p->tangent_impulse0)),
                              wv_scale(w->tangent1, w_sub(n1, p->tangent_impulse1)));
    p->tangent_impulse0 = w_sel(p->live, n0, p->tangent_impulse0);
    p->tangent_impulse1 = w_sel(p->live, n1, p->tangent_impulse1);
    wide_push(w, &m, p->live, p->ra, p->rb, push);
  }
  wide_save(w, &m, motion);
}

/* restitute_contact(), a batch at once. */
static void wide_restitute(WideBatch *w, Motion *motion) {
  WideMotion m;
  wide_load(w, motion, &m);
  const WReal zero = w_splat(F3D_R(0.0));
  const WReal threshold = w_splat(-F3D_RESTITUTION_THRESHOLD);
  const WMask bounces = w_not(w_eq(w->restitution, zero));
  for (uint32_t k = 0; k < w->points; k++) {
    WidePoint *p = &w->p[k];
    const WMask on = w_and(w_and(p->live, bounces),
                           w_and(w_not(w_gt(p->approach, threshold)), w_not(w_eq(p->most, zero))));
    const WReal vn = wv_dot(wide_relative(&m, p->ra, p->rb), w->normal);
    const WReal lambda =
        w_mul(w_neg(p->normal_mass), w_add(vn, w_mul(w->restitution, p->approach)));
    const WReal total = w_max(w_add(p->normal_impulse, lambda), zero);
    const WReal delta = w_sub(total, p->normal_impulse);
    p->normal_impulse = w_sel(on, total, p->normal_impulse);
    wide_push(w, &m, on, p->ra, p->rb, wv_scale(w->normal, delta));
  }
  wide_save(w, &m, motion);
}

/* ------------------------------------------------------------ fast mode */

/* Colours a contact may take; one that finds them all taken by its bodies
 * goes to the overflow, solved on one thread after the colours. */
#define F3D_COLOURS 64u

/* A step of the fast mode: the contacts in colour order, and what every
 * worker needs to walk the step's stages with the rest. */
typedef struct FastStep {
  F3dWorld *world;
  const SolverBody *bodies;
  Motion *motion;
  SolverContact *contacts;
  /* contacts[order[k]] for k from group_start[g] to group_start[g + 1] are
   * group g's; the last group, F3D_COLOURS, is the overflow. */
  const uint32_t *order;
  uint32_t group_start[F3D_COLOURS + 2u];
  /* Colour g's contacts in batches: batches[batch_start[g]] up to
   * batches[batch_start[g + 1]]. The overflow has none. */
  WideBatch *batches;
  uint32_t batch_start[F3D_COLOURS + 1u];
  Softness softness;
  f3d_real h;
  uint32_t substeps, used, row;
  uint32_t workers;
  F3dBarrier barrier;
} FastStep;

/* Worker [w]'s share of [n] items: [*begin, *end). */
static void share_of(uint32_t n, uint32_t w, uint32_t workers, uint32_t *begin,
                     uint32_t *end) {
  *begin = (uint32_t)((uint64_t)n * w / workers);
  *end = (uint32_t)((uint64_t)n * (w + 1u) / workers);
}

typedef enum ContactStage { WARM, SOLVE, RELAX, RESTITUTE } ContactStage;

/* Every group of contacts through one stage: a colour shared out among the
 * workers, the overflow on worker nought, a barrier after each. */
static void contact_stage(FastStep *f, uint32_t w, uint32_t *sense, ContactStage stage) {
  const f3d_real inv_h = F3D_R(1.0) / f->h;
  uint32_t mine = 0, mine_end = 0;
  share_of(f->used, w, f->workers, &mine, &mine_end);
  gather(f->world, f->bodies, f->motion, mine, mine_end);
  f3d_barrier_wait(&f->barrier, sense);
  for (uint32_t g = 0; g <= F3D_COLOURS; g++) {
    const uint32_t first = f->group_start[g], n = f->group_start[g + 1u] - first;
    if (n == 0) continue;
    if (g < F3D_COLOURS) {
      const uint32_t batch = f->batch_start[g];
      uint32_t begin = 0, end = 0;
      share_of(f->batch_start[g + 1u] - batch, w, f->workers, &begin, &end);
      for (uint32_t k = batch + begin; k < batch + end; k++) {
        WideBatch *wb = &f->batches[k];
        switch (stage) {
          case WARM: wide_warm(wb, f->motion); break;
          case SOLVE: wide_solve(wb, f->motion, f->softness, inv_h, 1); break;
          case RELAX: wide_solve(wb, f->motion, f->softness, inv_h, 0); break;
          case RESTITUTE: wide_restitute(wb, f->motion); break;
        }
      }
      f3d_barrier_wait(&f->barrier, sense);
      continue;
    }
    /* The overflow, whose contacts may share a body: on worker nought, one
     * after another. */
    const uint32_t begin = 0, end = w == 0 ? n : 0;
    for (uint32_t k = begin; k < end; k++) {
      SolverContact *sc = &f->contacts[f->order[first + k]];
      switch (stage) {
        case WARM: warm_contact(f->world, sc, f->bodies, f->motion); break;
        case SOLVE: solve_contact(f->world, sc, f->bodies, f->motion, f->softness, inv_h, 1); break;
        case RELAX: solve_contact(f->world, sc, f->bodies, f->motion, f->softness, inv_h, 0); break;
        case RESTITUTE: restitute_contact(f->world, sc, f->bodies, f->motion); break;
      }
    }
    f3d_barrier_wait(&f->barrier, sense);
  }
  scatter(f->world, f->motion, mine, mine_end);
  f3d_barrier_wait(&f->barrier, sense);
}

/* One worker's walk through the step: the same stages in the same order as
 * the deterministic mode's, each body's motion on whichever worker has it,
 * joints on worker nought, contacts a colour at a time. */
static void fast_walk(void *context, uint32_t w, uint32_t begin_unused, uint32_t end_unused) {
  (void)begin_unused;
  (void)end_unused;
  FastStep *f = (FastStep *)context;
  F3dWorld *world = f->world;
  uint32_t sense = 0, begin = 0, end = 0;
  share_of(f->used, w, f->workers, &begin, &end);
  for (uint32_t step = 0; step < f->substeps; step++) {
    for (uint32_t i = begin; i < end; i++) {
      F3dSlot *s = &world->slots[i];
      if (moves(s)) f3d_integrate_velocity(world, s, f->h);
    }
    f3d_barrier_wait(&f->barrier, &sense);
    if (w == 0) f3d_warm_joints(world, f->bodies);
    f3d_barrier_wait(&f->barrier, &sense);
    contact_stage(f, w, &sense, WARM);
    if (w == 0) f3d_solve_joints(world, f->bodies, f->h, 1);
    f3d_barrier_wait(&f->barrier, &sense);
    contact_stage(f, w, &sense, SOLVE);
    for (uint32_t i = begin; i < end; i++) {
      F3dSlot *s = &world->slots[i];
      if (!moves(s)) {
        if (f3d_carried(s)) f3d_carry(s, f->h);
        continue;
      }
      f3d_integrate_position(s, f->h);
      if (f->bodies[i].bullet >= 0) {
        const size_t at = (size_t)f->bodies[i].bullet * f->row + step + 1u;
        world->bullet_at[at] = s->position;
        world->bullet_turn[at] = s->orientation;
      }
    }
    f3d_barrier_wait(&f->barrier, &sense);
    if (w == 0) f3d_solve_joints(world, f->bodies, f->h, 0);
    f3d_barrier_wait(&f->barrier, &sense);
    contact_stage(f, w, &sense, RELAX);
  }
  contact_stage(f, w, &sense, RESTITUTE);
}

/* The lowest bit not set in [taken], or F3D_COLOURS for none. */
static uint32_t free_colour(uint64_t taken) {
  for (uint32_t k = 0; k < F3D_COLOURS; k++) {
    if (!((taken >> k) & 1u)) return k;
  }
  return F3D_COLOURS;
}

/* The fast mode's substeps and restitution, in place of the deterministic
 * mode's. Colours greedily in contact order — a contact takes the lowest
 * colour neither of its moving bodies has — so the colouring, and so the
 * bits, depend on the world alone and not on the threads. */
static int fast_solve(F3dWorld *world, const SolverBody *bodies, Motion *motion,
                      SolverContact *contacts, uint32_t count, Softness softness, f3d_real h,
                      uint32_t row, uint8_t *room) {
  const uint32_t used = world->s.used;
  uint64_t *taken = (uint64_t *)room;
  uint32_t *colour = (uint32_t *)(taken + used);
  uint32_t *order = colour + count;
  FastStep f;
  f3d_zero(&f, sizeof f);
  for (uint32_t i = 0; i < used; i++) taken[i] = 0;
  for (uint32_t c = 0; c < count; c++) {
    const uint32_t a = contacts[c].a, b = contacts[c].b;
    const int ma = bodies[a].inverse_mass > F3D_R(0.0);
    const int mb = bodies[b].inverse_mass > F3D_R(0.0);
    const uint32_t k = free_colour((ma ? taken[a] : 0u) | (mb ? taken[b] : 0u));
    if (k < F3D_COLOURS) {
      if (ma) taken[a] |= (uint64_t)1 << k;
      if (mb) taken[b] |= (uint64_t)1 << k;
    }
    colour[c] = k;
    f.group_start[k + 1u]++;
  }
  for (uint32_t g = 0; g <= F3D_COLOURS; g++) f.group_start[g + 1u] += f.group_start[g];
  uint32_t fill[F3D_COLOURS + 1u];
  for (uint32_t g = 0; g <= F3D_COLOURS; g++) fill[g] = f.group_start[g];
  /* The overflow in contact order: its contacts may share a body, and are
   * solved one after another. Within a colour, the contacts of one point
   * first, then two, and so on, so a batch's lanes mostly have as many
   * points as each other: a colour's contacts share no moving body, and
   * the order they are solved in changes nothing. */
  for (uint32_t c = 0; c < count; c++) {
    if (colour[c] == F3D_COLOURS) order[fill[F3D_COLOURS]++] = c;
  }
  for (uint32_t points = 1; points <= F3D_MANIFOLD_POINTS; points++) {
    for (uint32_t c = 0; c < count; c++) {
      const uint32_t n = contacts[c].count > 1u ? contacts[c].count : 1u;
      if (colour[c] < F3D_COLOURS && n == points) order[fill[colour[c]]++] = c;
    }
  }
  /* Each colour in batches of F3D_LANES, in that order, aligned for the
   * vectors past the order. */
  uintptr_t at = (uintptr_t)(order + count);
  at = (at + 63u) & ~(uintptr_t)63u;
  f.batches = (WideBatch *)at;
  uint32_t batches = 0;
  for (uint32_t g = 0; g < F3D_COLOURS; g++) {
    f.batch_start[g] = batches;
    for (uint32_t k = f.group_start[g]; k < f.group_start[g + 1u]; k += F3D_LANES) {
      const uint32_t n = f.group_start[g + 1u] - k < F3D_LANES ? f.group_start[g + 1u] - k
                                                               : F3D_LANES;
      wide_fill(&f.batches[batches++], world, bodies, contacts, order, k, n);
    }
  }
  f.batch_start[F3D_COLOURS] = batches;
  f.world = world;
  f.bodies = bodies;
  f.motion = motion;
  f.contacts = contacts;
  f.order = order;
  f.softness = softness;
  f.h = h;
  f.substeps = world->s.substeps;
  f.used = used;
  f.row = row;
  f.workers = f3d_pool_size(world->pool);
  f3d_barrier_init(&f.barrier, f.workers);
  f3d_pool_run(world->pool, f.workers, fast_walk, &f);
  for (uint32_t k = 0; k < batches; k++) wide_store(&f.batches[k], world, contacts);
  return 1;
}

void f3d_step_solve(F3dWorld *world, f3d_real dt) {
  const uint32_t used = world->s.used;
  const uint32_t substeps = world->s.substeps;
  const f3d_real h = dt / (f3d_real)substeps;
  /* The bodies, then the contacts, in the world's scratch. */
  const size_t body_bytes = ((size_t)used * sizeof(SolverBody) + 15u) &
                            ~(size_t)15u;
  const size_t motion_bytes = ((size_t)used * sizeof(Motion) + 15u) & ~(size_t)15u;
  const size_t contact_bytes = ((size_t)world->s.manifold_count * sizeof(SolverContact) + 15u) &
                               ~(size_t)15u;
  /* The fast mode's colouring after them: a mask a body, two words a
   * contact, and the batches. */
  const size_t fast_bytes =
      world->s.fast ? (size_t)used * sizeof(uint64_t) + (size_t)world->s.manifold_count * 8u +
                          ((size_t)world->s.manifold_count / F3D_LANES + F3D_COLOURS + 1u) *
                              sizeof(WideBatch) +
                          64u
                    : 0u;
  uint8_t *base =
      (uint8_t *)f3d_scratch(world, body_bytes + motion_bytes + contact_bytes + fast_bytes);
  if (base == NULL && used > 0) return;
  SolverBody *bodies = (SolverBody *)base;
  Motion *motion = (Motion *)(base + body_bytes);
  SolverContact *contacts = (SolverContact *)(base + body_bytes + motion_bytes);
  for (uint32_t i = 0; i < used; i++) {
    const F3dSlot *s = &world->slots[i];
    SolverBody *sb = &bodies[i];
    f3d_zero(sb, sizeof *sb);
    if (!s->live) continue;
    sb->start = s->position;
    sb->turn = s->orientation;
    sb->bullet = -1;
    if (moves(s)) {
      /* The water a body must move with it is mass the contacts and
       * joints push too: a bag of air on a rope, its own two kilograms and
       * fifty of water round it, passes its lift to what it holds rather
       * than spending it on the water. Its weight stays its own; the
       * integrator already gives it (m g + F) / (m + mₐ). */
      sb->inverse_mass =
          s->added_mass > F3D_R(0.0)
              ? F3D_R(1.0) / (F3D_R(1.0) / s->inverse_mass + s->added_mass)
              : s->inverse_mass;
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
    for (uint32_t k = 0; k < m->count; k++) {
      SolverPoint *p = &sc->p[k];
      const F3dContactPoint *mp = &m->points[k];
      p->ra = f3d_sub(mp->point, sa->position);
      p->rb = f3d_sub(mp->point, sb->position);
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
  /* The bullets' paths: where each stands before the first substep and
   * after every one, so the sweep follows a turn of more than half a
   * revolution in a step, which its two ends alone would read the short
   * way round. */
  uint32_t bullets = 0;
  for (uint32_t i = 0; i < used; i++) {
    const F3dSlot *s = &world->slots[i];
    if (moves(s) && (s->flags & F3D_FLAG_BULLET)) bodies[i].bullet = (int32_t)bullets++;
  }
  const uint32_t row = substeps + 1u;
  if (bullets * row > world->bullet_capacity) {
    F3dVec3 *at = (F3dVec3 *)f3d_realloc(world->bullet_at,
                                         (size_t)bullets * row * sizeof(F3dVec3));
    if (at != NULL) world->bullet_at = at;
    F3dQuat *turn = (F3dQuat *)f3d_realloc(
        world->bullet_turn, (size_t)bullets * row * sizeof(F3dQuat));
    if (turn != NULL) world->bullet_turn = turn;
    if (at != NULL && turn != NULL) {
      world->bullet_capacity = bullets * row;
    } else {
      for (uint32_t i = 0; i < used; i++) bodies[i].bullet = -1;
      bullets = 0;
    }
  }
  for (uint32_t i = 0; i < used && bullets > 0; i++) {
    if (bodies[i].bullet < 0) continue;
    const size_t at = (size_t)bodies[i].bullet * row;
    world->bullet_at[at] = world->slots[i].position;
    world->bullet_turn[at] = world->slots[i].orientation;
  }
  if (world->s.fast) {
    fast_solve(world, bodies, motion, contacts, count, softness, h, row,
               base + body_bytes + motion_bytes + contact_bytes);
  }
  for (uint32_t step = 0; step < substeps && !world->s.fast; step++) {
    for (uint32_t i = 0; i < used; i++) {
      F3dSlot *s = &world->slots[i];
      if (moves(s)) f3d_integrate_velocity(world, s, h);
    }
    f3d_warm_joints(world, bodies);
    warm_start(world, contacts, count, bodies, motion);
    f3d_solve_joints(world, bodies, h, 1);
    solve(world, contacts, count, bodies, motion, softness, h, 1);
    for (uint32_t i = 0; i < used; i++) {
      F3dSlot *s = &world->slots[i];
      if (!moves(s)) {
        if (f3d_carried(s)) f3d_carry(s, h);
        continue;
      }
      f3d_integrate_position(s, h);
      if (bodies[i].bullet >= 0) {
        const size_t at = (size_t)bodies[i].bullet * row + step + 1u;
        world->bullet_at[at] = s->position;
        world->bullet_turn[at] = s->orientation;
      }
    }
    f3d_solve_joints(world, bodies, h, 0);
    solve(world, contacts, count, bodies, motion, softness, h, 0);
  }
  if (!world->s.fast) restitute(world, contacts, count, bodies, motion);
  f3d_step_continuous(world, bodies);
  for (uint32_t i = 0; i < used; i++) {
    F3dSlot *s = &world->slots[i];
    if (s->live) f3d_finish_motion(world, s, dt);
  }
}
