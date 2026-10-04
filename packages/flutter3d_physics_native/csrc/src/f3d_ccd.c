/*
 * Hard continuous collision — P9, phase 8: bullets swept for their time of
 * impact after the solve.
 *
 * Soft collision — contacts that reach as far as a body moves in a step —
 * stops most fast bodies at what they would cross. A bullet is swept too:
 * from where the step began to where it ended, along a line, against every
 * body near that line but another bullet, by conservative advancement —
 * the gap between them, over how fast the bullet closes it along the gap's
 * normal, is a time it cannot hit before; step that far and ask again. The
 * first hit puts the bullet back there, the solver's velocity kept, and the
 * next step's contact takes it from there. The bullet's turn is taken as
 * it ends the step; a bullet is small, and its turn in one step is not
 * what lets it through a wall.
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

/* The first time, nought to one along the sweep from [start] by [move],
 * that the bullet [p] comes within the slop of [other]; one when it does
 * not. */
static f3d_real impact(const F3dPlaced *p, F3dVec3 start, F3dVec3 move,
                       const F3dPlaced *other) {
  const f3d_real length = f3d_sqrt(f3d_dot(move, move));
  const f3d_real target = F3D_R(0.5) * F3D_LINEAR_SLOP;
  F3dPlaced at = *p;
  f3d_real t = F3D_R(0.0);
  for (int iteration = 0; iteration < 32; iteration++) {
    at.at = f3d_madd(start, move, t);
    F3dManifold m;
    f3d_zero(&m, sizeof m);
    /* Within what is left of the sweep, or it cannot reach. */
    const f3d_real reach = (F3D_R(1.0) - t) * length + F3D_LINEAR_SLOP;
    if (f3d_collide(&at, other, reach, &m) == 0) return F3D_R(1.0);
    f3d_real deepest = m.points[0].depth;
    for (uint32_t k = 1; k < m.count; k++) {
      deepest = f3d_max(deepest, m.points[k].depth);
    }
    /* The normal points out of the other body into the bullet: the bullet
     * closes the gap at its speed against it. Moving along it or away is no
     * impact, touching or not — a bullet lying on a floor and rolling over
     * it is not held where it began. */
    const f3d_real closing = -f3d_dot(move, m.normal);
    if (!(closing > F3D_R(1e-12) * length)) return F3D_R(1.0);
    const f3d_real gap = -deepest;
    /* Touching where the step began is the contact solver's, not the
     * sweep's: a bullet resting on a floor would be held where it began by
     * the faintest downward drift. */
    if (gap <= F3D_LINEAR_SLOP) return iteration == 0 ? F3D_R(1.0) : t;
    t += (gap - target) / closing;
    if (t >= F3D_R(1.0)) return F3D_R(1.0);
  }
  return t;
}

void f3d_step_continuous(F3dWorld *world, const F3dSolverBody *bodies) {
  for (uint32_t i = 0; i < world->s.used; i++) {
    F3dSlot *s = &world->slots[i];
    if (!s->live || !(s->flags & F3D_FLAG_BULLET) ||
        s->type != F3D_BODY_DYNAMIC || (s->flags & F3D_FLAG_ASLEEP) ||
        s->shape == F3D_SHAPE_POINT || world->proxies == NULL ||
        i >= world->proxy_capacity) {
      continue;
    }
    const F3dVec3 start = bodies[i].start;
    const F3dVec3 move = f3d_sub(s->position, start);
    if (f3d_dot(move, move) <= F3D_LINEAR_SLOP * F3D_LINEAR_SLOP) continue;
    /* What lies near the line: the bullet's box where it began, joined to
     * its box where it ended. */
    F3dBox box = f3d_box_of(world, s, F3D_LINEAR_SLOP);
    const F3dVec3 back = f3d_scale(move, F3D_R(-1.0));
    box.lo = f3d_v3(f3d_min(box.lo.x, box.lo.x + back.x),
                    f3d_min(box.lo.y, box.lo.y + back.y),
                    f3d_min(box.lo.z, box.lo.z + back.z));
    box.hi = f3d_v3(f3d_max(box.hi.x, box.hi.x + back.x),
                    f3d_max(box.hi.y, box.hi.y + back.y),
                    f3d_max(box.hi.z, box.hi.z + back.z));
    Candidates c;
    c.world = world;
    c.self = i;
    c.count = 0;
    f3d_tree_query(&world->tree, box, candidate, &c);
    const F3dPlaced p = f3d_placed_of(world, s);
    f3d_real first = F3D_R(1.0);
    for (uint32_t k = 0; k < c.count; k++) {
      const F3dSlot *o = &world->slots[c.slots[k]];
      if (!o->live || o->shape == F3D_SHAPE_POINT) continue;
      if (o->flags & F3D_FLAG_BULLET) continue;
      if (!(s->layer & o->mask) || !(o->layer & s->mask)) continue;
      if (f3d_joined(world, i, c.slots[k])) continue;
      const F3dPlaced q = f3d_placed_of(world, o);
      const f3d_real t = impact(&p, start, move, &q);
      if (t < first) first = t;
    }
    if (first < F3D_R(1.0)) s->position = f3d_madd(start, move, first);
  }
}
