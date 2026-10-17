/*
 * Hard continuous collision — P9, phase 8: bullets swept for their time of
 * impact after the solve.
 *
 * Soft collision — contacts that reach as far as a body moves in a step —
 * stops most fast bodies at what they would cross. A bullet is swept too:
 * from where the step began to where it ended, along a line and turning,
 * against every body near that line but another bullet, by conservative
 * advancement — the gap between them, over the most the bullet can close
 * it by, is a time it cannot hit before; step that far and ask again. The
 * first hit puts the bullet back there, place and turn, the solver's
 * velocity kept, and the next step's contact takes it from there. Its turn
 * is swept with it, substep by substep along the path the solver took, so
 * a blade spun through a wall in one step — five radians of it, which its
 * first and last turns would read the short way round, backwards — stops at
 * the wall as surely as a bullet shot at it. A turn of more than half a
 * revolution in one substep is past what this follows.
 */
#include "f3d_internal.h"

typedef struct Candidates {
  const F3dWorld *world;
  uint32_t self;
  uint32_t slots[256];
  uint32_t count;
} Candidates;

static int candidate(void *context, int32_t leaf) {
  Candidates *c = (Candidates *)context;
  const uint32_t other = c->world->tree.nodes[leaf].slot;
  if (other != c->self && c->count < 256u) c->slots[c->count++] = other;
  return c->count < 256u;
}

/* A bullet's path through the step: from where it began to where it
 * ended, its place along a line and its turn the shorter way round. */
typedef struct Sweep {
  F3dVec3 start, move;
  F3dQuat from, to;
  /* The most any point of it moves for its turn over the whole step: the
   * turn's fastest rate times how far its shape reaches from its centre;
   * nought for a ball, which no turn changes. */
  f3d_real spin_reach;
} Sweep;

/* The turn a fraction [t] of the way: the normalised blend of the two
 * quaternions. */
static F3dQuat turn_at(const Sweep *w, f3d_real t) {
  const f3d_real u = F3D_R(1.0) - t;
  F3dQuat q;
  q.x = w->from.x * u + w->to.x * t;
  q.y = w->from.y * u + w->to.y * t;
  q.z = w->from.z * u + w->to.z * t;
  q.w = w->from.w * u + w->to.w * t;
  const f3d_real len = f3d_sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w);
  q.x /= len;
  q.y /= len;
  q.z /= len;
  q.w /= len;
  return q;
}

/* The first time, nought to one along the sweep, that the bullet [p] comes
 * within the slop of [other]; one when it does not. The gap over the most
 * it can close per step — along the normal for its move, anywhere for its
 * turn — is a time it cannot hit before. */
static f3d_real impact(const F3dPlaced *p, const Sweep *w,
                       const F3dPlaced *other) {
  const f3d_real length = f3d_sqrt(f3d_dot(w->move, w->move));
  const f3d_real target = F3D_R(0.5) * F3D_LINEAR_SLOP;
  F3dPlaced at = *p;
  f3d_real t = F3D_R(0.0), gap = F3D_R(0.0);
  for (int iteration = 0; iteration < 64; iteration++) {
    at.at = f3d_madd(w->start, w->move, t);
    at.axes = f3d_mat_of(turn_at(w, t));
    F3dManifold m;
    f3d_zero(&m, sizeof m);
    /* Within what is left of the sweep, or it cannot reach. */
    const f3d_real reach =
        (F3D_R(1.0) - t) * (length + w->spin_reach) + F3D_LINEAR_SLOP;
    if (f3d_collide(&at, other, reach, &m) == 0) return F3D_R(1.0);
    f3d_real deepest = m.points[0].depth;
    for (uint32_t k = 1; k < m.count; k++) {
      deepest = f3d_max(deepest, m.points[k].depth);
    }
    gap = -deepest;
    /* The normal points out of the other body into the bullet. Its move
     * closes the gap only against the normal; its turn can close it from
     * anywhere. Neither closing it, it cannot hit — a bullet lying on a
     * floor and sliding over it is not held where it began. */
    const f3d_real closing =
        f3d_max(-f3d_dot(w->move, m.normal), F3D_R(0.0)) + w->spin_reach;
    if (!(closing > F3D_R(1e-12) * (length + w->spin_reach))) return F3D_R(1.0);
    /* Touching where the substep began is the contact solver's, not the
     * sweep's: a bullet resting on a floor would be held where it began by
     * the faintest downward drift. An impact that ends one substep is
     * found in it, short of its end, before the next begins touching. */
    if (gap <= F3D_LINEAR_SLOP) return iteration == 0 ? F3D_R(1.0) : t;
    t += (gap - target) / closing;
    if (t >= F3D_R(1.0)) return F3D_R(1.0);
  }
  /* Still apart after every advance: a body grazing past, turning, closes
   * on nothing; one still closing is near enough to stop at. */
  return gap <= F3D_R(4.0) * F3D_LINEAR_SLOP ? t : F3D_R(1.0);
}

/* The most any point of a shape reaching [reach] from its centre moves for
 * the blended turn from [from] to [to], the shorter way round — which it
 * makes [to] — over the blend. With β the half angle between them, the
 * normalised blend turns at most at 4 tan(β/2) = 4 sin β / (1 + cos β): the
 * turn's own angle, 2β, when it is small, a quarter more at a half turn. */
static f3d_real spin_reach_of(F3dQuat from, F3dQuat *to, f3d_real reach) {
  f3d_real cosine =
      from.x * to->x + from.y * to->y + from.z * to->z + from.w * to->w;
  if (cosine < F3D_R(0.0)) {
    to->x = -to->x;
    to->y = -to->y;
    to->z = -to->z;
    to->w = -to->w;
    cosine = -cosine;
  }
  cosine = f3d_min(cosine, F3D_R(1.0));
  const f3d_real sine = f3d_sqrt(F3D_R(1.0) - cosine * cosine);
  return F3D_R(4.0) * sine / (F3D_R(1.0) + cosine) * reach;
}

void f3d_step_continuous(F3dWorld *world, const F3dSolverBody *bodies) {
  const uint32_t row = world->s.substeps + 1u;
  for (uint32_t i = 0; i < world->s.used; i++) {
    F3dSlot *s = &world->slots[i];
    if (!s->live || bodies[i].bullet < 0 || s->shape == F3D_SHAPE_POINT ||
        world->proxies == NULL || i >= world->proxy_capacity) {
      continue;
    }
    const F3dVec3 *at = world->bullet_at + (size_t)bodies[i].bullet * row;
    const F3dQuat *turn = world->bullet_turn + (size_t)bodies[i].bullet * row;
    /* How far its shape reaches from its centre: its box's half diagonal
     * and how far that box's middle sits off the centre. */
    const F3dBox own = f3d_box_of(world, s, F3D_R(0.0));
    const F3dVec3 mid = f3d_scale(f3d_add(own.lo, own.hi), F3D_R(0.5));
    const F3dVec3 half = f3d_scale(f3d_sub(own.hi, own.lo), F3D_R(0.5));
    const F3dVec3 off = f3d_sub(mid, s->position);
    const f3d_real reach =
        f3d_sqrt(f3d_dot(half, half)) + f3d_sqrt(f3d_dot(off, off));
    const int round = s->shape == F3D_SHAPE_SPHERE;
    /* What it can reach: within its reach of every place on its path. */
    F3dBox box;
    box.lo = box.hi = at[0];
    f3d_real travelled = F3D_R(0.0);
    for (uint32_t k = 0; k < row; k++) {
      box.lo = f3d_v3(f3d_min(box.lo.x, at[k].x), f3d_min(box.lo.y, at[k].y),
                      f3d_min(box.lo.z, at[k].z));
      box.hi = f3d_v3(f3d_max(box.hi.x, at[k].x), f3d_max(box.hi.y, at[k].y),
                      f3d_max(box.hi.z, at[k].z));
      if (k > 0) {
        const F3dVec3 d = f3d_sub(at[k], at[k - 1]);
        F3dQuat to = turn[k];
        travelled += f3d_sqrt(f3d_dot(d, d)) +
                     (round ? F3D_R(0.0) : spin_reach_of(turn[k - 1], &to, reach));
      }
    }
    if (travelled <= F3D_LINEAR_SLOP) continue;
    const f3d_real r = reach + F3D_LINEAR_SLOP;
    box.lo = f3d_sub(box.lo, f3d_v3(r, r, r));
    box.hi = f3d_add(box.hi, f3d_v3(r, r, r));
    Candidates c;
    c.world = world;
    c.self = i;
    c.count = 0;
    f3d_tree_query(&world->tree, box, candidate, &c);
    const F3dPlaced p = f3d_placed_of(world, s);
    /* Substep by substep along the path: the first substep with a hit, at
     * its first hit, is where it stops. */
    for (uint32_t k = 0; k + 1u < row; k++) {
      Sweep w;
      w.start = at[k];
      w.move = f3d_sub(at[k + 1u], at[k]);
      w.from = turn[k];
      w.to = turn[k + 1u];
      const f3d_real spin = spin_reach_of(w.from, &w.to, reach);
      w.spin_reach = round ? F3D_R(0.0) : spin;
      f3d_real first = F3D_R(1.0);
      for (uint32_t q = 0; q < c.count; q++) {
        const F3dSlot *o = &world->slots[c.slots[q]];
        if (!o->live || o->shape == F3D_SHAPE_POINT) continue;
        if (o->flags & F3D_FLAG_BULLET) continue;
        if (!(s->layer & o->mask) || !(o->layer & s->mask)) continue;
        if (f3d_joined(world, i, c.slots[q])) continue;
        const F3dPlaced other = f3d_placed_of(world, o);
        const f3d_real t = impact(&p, &w, &other);
        if (t < first) first = t;
      }
      if (first < F3D_R(1.0)) {
        s->position = f3d_madd(w.start, w.move, first);
        s->orientation = turn_at(&w, first);
        break;
      }
    }
  }
}
