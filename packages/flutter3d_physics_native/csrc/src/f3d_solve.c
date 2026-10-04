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

/* An impulse [p] at the point: into a, out of b. With [still], a body
 * that does not move is left untouched rather than given nothing: in the
 * fast mode a fixed floor is in many contacts of one colour at once, and
 * nothing may write it. */
static void push(F3dSlot *a, F3dSlot *b, const SolverBody *ba,
                 const SolverBody *bb, F3dVec3 ra, F3dVec3 rb, F3dVec3 p,
                 int still) {
  if (!still || ba->inverse_mass > F3D_R(0.0)) {
    a->velocity = f3d_madd(a->velocity, p, ba->inverse_mass);
    a->spin = f3d_add(a->spin,
                      f3d_sym_times(ba->inverse_inertia, f3d_cross(ra, p)));
  }
  if (!still || bb->inverse_mass > F3D_R(0.0)) {
    b->velocity = f3d_madd(b->velocity, p, -bb->inverse_mass);
    b->spin = f3d_sub(b->spin,
                      f3d_sym_times(bb->inverse_inertia, f3d_cross(rb, p)));
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
                          Softness softness, f3d_real inv_h, int use_bias, int still) {
  {
    F3dManifold *m = &world->manifolds[sc->manifold];
    F3dSlot *a = &world->slots[sc->a];
    F3dSlot *b = &world->slots[sc->b];
    const SolverBody *ba = &bodies[sc->a], *bb = &bodies[sc->b];
    const F3dVec3 turned_a = turned_since(a->orientation, ba->turn);
    const F3dVec3 turned_b = turned_since(b->orientation, bb->turn);
    const F3dVec3 n = sc->normal;
    const F3dVec3 da = f3d_sub(a->position, ba->start);
    const F3dVec3 db = f3d_sub(b->position, bb->start);
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
      const f3d_real vn = f3d_dot(relative(a, b, p->ra, p->rb), n);
      const f3d_real lambda = -p->normal_mass * mass_scale * (vn + bias) -
                              impulse_scale * mp->normal_impulse;
      const f3d_real total = f3d_max(mp->normal_impulse + lambda, F3D_R(0.0));
      const f3d_real delta = total - mp->normal_impulse;
      mp->normal_impulse = total;
      p->most = f3d_max(p->most, total);
      push(a, b, ba, bb, p->ra, p->rb, f3d_scale(n, delta), still);
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
      push(a, b, ba, bb, p->ra, p->rb, dp, still);
    }
  }
}

static void solve(F3dWorld *world, SolverContact *contacts, uint32_t count,
                  const SolverBody *bodies, Softness softness, f3d_real h,
                  int use_bias) {
  const f3d_real inv_h = F3D_R(1.0) / h;
  for (uint32_t c = 0; c < count; c++) {
    solve_contact(world, &contacts[c], bodies, softness, inv_h, use_bias, 0);
  }
}

static void warm_contact(F3dWorld *world, const SolverContact *sc, const SolverBody *bodies,
                         int still) {
  {
    const F3dManifold *m = &world->manifolds[sc->manifold];
    F3dSlot *a = &world->slots[sc->a];
    F3dSlot *b = &world->slots[sc->b];
    for (uint32_t k = 0; k < sc->count; k++) {
      const F3dContactPoint *mp = &m->points[k];
      const F3dVec3 p =
          f3d_add(f3d_scale(sc->normal, mp->normal_impulse),
                  f3d_add(f3d_scale(sc->tangent[0], mp->tangent_impulse[0]),
                          f3d_scale(sc->tangent[1], mp->tangent_impulse[1])));
      push(a, b, &bodies[sc->a], &bodies[sc->b], sc->p[k].ra, sc->p[k].rb, p, still);
    }
  }
}

static void warm_start(F3dWorld *world, const SolverContact *contacts,
                       uint32_t count, const SolverBody *bodies) {
  for (uint32_t c = 0; c < count; c++) warm_contact(world, &contacts[c], bodies, 0);
}

/* Restitution, once the substeps are done: a contact that was closing
 * faster than the threshold, and was pushed on, gets back its share of the
 * approach speed. */
static void restitute_contact(F3dWorld *world, SolverContact *sc, const SolverBody *bodies,
                              int still) {
  if (sc->restitution == F3D_R(0.0)) return;
  {
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
           f3d_scale(sc->normal, delta), still);
    }
  }
}

static void restitute(F3dWorld *world, SolverContact *contacts,
                      uint32_t count, const SolverBody *bodies) {
  for (uint32_t c = 0; c < count; c++) restitute_contact(world, &contacts[c], bodies, 0);
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
  SolverContact *contacts;
  /* contacts[order[k]] for k from group_start[g] to group_start[g + 1] are
   * group g's; the last group, F3D_COLOURS, is the overflow. */
  const uint32_t *order;
  uint32_t group_start[F3D_COLOURS + 2u];
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
  for (uint32_t g = 0; g <= F3D_COLOURS; g++) {
    const uint32_t first = f->group_start[g], n = f->group_start[g + 1u] - first;
    if (n == 0) continue;
    uint32_t begin = 0, end = n;
    if (g < F3D_COLOURS) {
      share_of(n, w, f->workers, &begin, &end);
    } else if (w != 0) {
      end = 0;
    }
    for (uint32_t k = begin; k < end; k++) {
      SolverContact *sc = &f->contacts[f->order[first + k]];
      switch (stage) {
        case WARM: warm_contact(f->world, sc, f->bodies, 1); break;
        case SOLVE: solve_contact(f->world, sc, f->bodies, f->softness, inv_h, 1, 1); break;
        case RELAX: solve_contact(f->world, sc, f->bodies, f->softness, inv_h, 0, 1); break;
        case RESTITUTE: restitute_contact(f->world, sc, f->bodies, 1); break;
      }
    }
    f3d_barrier_wait(&f->barrier, sense);
  }
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
      if (!moves(s)) continue;
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
static int fast_solve(F3dWorld *world, const SolverBody *bodies, SolverContact *contacts,
                      uint32_t count, Softness softness, f3d_real h, uint32_t row,
                      uint8_t *room) {
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
  for (uint32_t c = 0; c < count; c++) order[fill[colour[c]]++] = c;
  f.world = world;
  f.bodies = bodies;
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
  return 1;
}

void f3d_step_solve(F3dWorld *world, f3d_real dt) {
  const uint32_t used = world->s.used;
  const uint32_t substeps = world->s.substeps;
  const f3d_real h = dt / (f3d_real)substeps;
  /* The bodies, then the contacts, in the world's scratch. */
  const size_t body_bytes = ((size_t)used * sizeof(SolverBody) + 15u) &
                            ~(size_t)15u;
  const size_t contact_bytes = ((size_t)world->s.manifold_count * sizeof(SolverContact) + 15u) &
                               ~(size_t)15u;
  /* The fast mode's colouring after them: a mask a body, two words a
   * contact. */
  const size_t fast_bytes = world->s.fast ? (size_t)used * sizeof(uint64_t) +
                                                (size_t)world->s.manifold_count * 8u
                                          : 0u;
  uint8_t *base = (uint8_t *)f3d_scratch(world, body_bytes + contact_bytes + fast_bytes);
  if (base == NULL && used > 0) return;
  SolverBody *bodies = (SolverBody *)base;
  SolverContact *contacts = (SolverContact *)(base + body_bytes);
  for (uint32_t i = 0; i < used; i++) {
    const F3dSlot *s = &world->slots[i];
    SolverBody *sb = &bodies[i];
    f3d_zero(sb, sizeof *sb);
    if (!s->live) continue;
    sb->start = s->position;
    sb->turn = s->orientation;
    sb->bullet = -1;
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
    fast_solve(world, bodies, contacts, count, softness, h, row,
               base + body_bytes + contact_bytes);
  }
  for (uint32_t step = 0; step < substeps && !world->s.fast; step++) {
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
      if (!moves(s)) continue;
      f3d_integrate_position(s, h);
      if (bodies[i].bullet >= 0) {
        const size_t at = (size_t)bodies[i].bullet * row + step + 1u;
        world->bullet_at[at] = s->position;
        world->bullet_turn[at] = s->orientation;
      }
    }
    f3d_solve_joints(world, bodies, h, 0);
    solve(world, contacts, count, bodies, softness, h, 0);
  }
  if (!world->s.fast) restitute(world, contacts, count, bodies);
  f3d_step_continuous(world, bodies);
  for (uint32_t i = 0; i < used; i++) {
    F3dSlot *s = &world->slots[i];
    if (s->live) f3d_finish_motion(world, s, dt);
  }
}
