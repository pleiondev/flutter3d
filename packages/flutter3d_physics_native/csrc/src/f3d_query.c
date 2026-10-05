/*
 * Queries and characters — P9, phase 9: rays, shape overlaps, shape casts,
 * and a character controller made of them.
 *
 * A ray walks the broadphase tree nearest box first and cuts what is left
 * at each hit. A ball and an unrounded box it meets in closed form, a mesh
 * triangle by triangle (Möller and Trumbore), and every other shape by
 * conservative advancement: a point on the ray is never nearer the shape
 * than its distance, so stepping that far along the ray cannot step past
 * it. A cast moves a shape the same way against what is near its path. An
 * overlap asks the narrow phase whether anything touches.
 *
 * The character is a kinematic capsule: it is moved by casting it along
 * the move and sliding what is left along what it met, as many characters
 * have been since Quake. Ground is what is flat enough to stand on; a wall
 * is slid along and not climbed; a step is climbed by lifting, moving and
 * setting down; and walking down a slope it keeps to the ground.
 */
#include "f3d_internal.h"

/* How close is touching, for rays and casts, m. */
#define F3D_QUERY_TOLERANCE F3D_R(1e-4)
/* How far a character keeps from what it meets, m. */
#define F3D_CHARACTER_SKIN F3D_R(0.01)

static int sees(const F3dWorld *world, const F3dSlot *s, uint32_t mask,
                F3dBody ignore) {
  if (!s->live || s->shape == F3D_SHAPE_POINT) return 0;
  if (!(s->layer & mask)) return 0;
  return ignore == 0 || f3d_handle_of(world, s) != ignore;
}

static F3dQuat unit(f3d_real x, f3d_real y, f3d_real z, f3d_real w) {
  const f3d_real len = f3d_sqrt(x * x + y * y + z * z + w * w);
  F3dQuat q;
  if (!(len > F3D_R(0.0)) || !f3d_finite(len)) {
    q.x = q.y = q.z = F3D_R(0.0);
    q.w = F3D_R(1.0);
    return q;
  }
  q.x = x / len;
  q.y = y / len;
  q.z = z / len;
  q.w = w / len;
  return q;
}

/* A shape a query asks about; 0 for a kind or size it does not take. */
static int query_shape(F3dShapeKind kind, f3d_real a, f3d_real b, f3d_real c,
                       f3d_real rounding, F3dVec3 at, F3dQuat q,
                       F3dPlaced *out) {
  f3d_zero(out, sizeof *out);
  if (!(f3d_finite(rounding) && rounding >= F3D_R(0.0))) return 0;
  if (!(f3d_finite(a) && f3d_finite(b) && f3d_finite(c))) return 0;
  switch (kind) {
    case F3D_SHAPE_SPHERE:
      if (!(a > F3D_R(0.0))) return 0;
      break;
    case F3D_SHAPE_BOX:
      if (!(a > F3D_R(0.0) && b > F3D_R(0.0) && c > F3D_R(0.0))) return 0;
      break;
    case F3D_SHAPE_CAPSULE:
      if (!(a > F3D_R(0.0) && b >= F3D_R(0.0))) return 0;
      break;
    case F3D_SHAPE_CYLINDER:
    case F3D_SHAPE_CONE:
      if (!(a > F3D_R(0.0) && b > F3D_R(0.0))) return 0;
      break;
    default:
      return 0;
  }
  out->kind = kind;
  out->size = f3d_v3(a, b, c);
  out->at = at;
  out->axes = f3d_mat_of(q);
  out->rounding = rounding;
  return 1;
}

/* How far a query shape reaches from its centre. */
static f3d_real reach_of(const F3dPlaced *p) {
  const F3dVec3 s = p->size;
  f3d_real r;
  switch (p->kind) {
    case F3D_SHAPE_SPHERE:
      r = s.x;
      break;
    case F3D_SHAPE_BOX:
      r = f3d_sqrt(f3d_dot(s, s));
      break;
    case F3D_SHAPE_CAPSULE:
      r = s.x + s.y;
      break;
    case F3D_SHAPE_CYLINDER:
      r = f3d_sqrt(s.x * s.x + s.y * s.y);
      break;
    default: /* A cone: its apex, or its rim. */
      r = f3d_max(F3D_R(0.75) * s.y,
                  f3d_sqrt(s.x * s.x + F3D_R(0.0625) * s.y * s.y));
      break;
  }
  return r + p->rounding;
}

/* The deepest point of a manifold, and its depth. */
static f3d_real deepest(const F3dManifold *m, F3dVec3 *point) {
  uint32_t best = 0;
  for (uint32_t k = 1; k < m->count; k++) {
    if (m->points[k].depth > m->points[best].depth) best = k;
  }
  if (point != NULL) *point = m->points[best].point;
  return m->points[best].depth;
}

/* ------------------------------------------------------------------- rays */

/* A ray and the nearest triangle of a mesh it meets from the front. */
typedef struct MeshRay {
  const F3dPlaced *mesh;
  F3dVec3 o, u; /* In the mesh's frame. */
  f3d_real best;
  F3dVec3 normal; /* In the mesh's frame. */
  int found;
} MeshRay;

static F3dVec3 mesh_vertex(const F3dPlaced *p, uint32_t i) {
  return f3d_v3(p->vertices[i * 3u], p->vertices[i * 3u + 1u],
                p->vertices[i * 3u + 2u]);
}

static int ray_triangle(void *context, int32_t leaf) {
  MeshRay *r = (MeshRay *)context;
  const uint32_t t = r->mesh->mesh_tree->nodes[leaf].slot;
  const uint32_t *tri = &r->mesh->triangles[t * 3u];
  const F3dVec3 a = mesh_vertex(r->mesh, tri[0]);
  const F3dVec3 e1 = f3d_sub(mesh_vertex(r->mesh, tri[1]), a);
  const F3dVec3 e2 = f3d_sub(mesh_vertex(r->mesh, tri[2]), a);
  const F3dVec3 n = f3d_cross(e1, e2);
  /* From the front only: one sided, as the mesh is to bodies. */
  if (!(f3d_dot(n, r->u) < F3D_R(0.0))) return 1;
  const F3dVec3 p = f3d_cross(r->u, e2);
  const f3d_real det = f3d_dot(e1, p);
  if (f3d_abs(det) <= F3D_R(1e-20)) return 1;
  const f3d_real inv = F3D_R(1.0) / det;
  const F3dVec3 s = f3d_sub(r->o, a);
  const f3d_real u = f3d_dot(s, p) * inv;
  if (u < F3D_R(0.0) || u > F3D_R(1.0)) return 1;
  const F3dVec3 q = f3d_cross(s, e1);
  const f3d_real v = f3d_dot(r->u, q) * inv;
  if (v < F3D_R(0.0) || u + v > F3D_R(1.0)) return 1;
  const f3d_real dist = f3d_dot(e2, q) * inv;
  if (dist < F3D_R(0.0) || dist >= r->best) return 1;
  r->best = dist;
  r->normal = f3d_scale(n, F3D_R(1.0) / f3d_sqrt(f3d_dot(n, n)));
  r->found = 1;
  return 1;
}

/* Where the ray from [o] along the unit [u] first meets the body within
 * [limit]: 1, the distance and the normal there; 0 when it misses or starts
 * inside. */
static int ray_body(const F3dWorld *world, const F3dSlot *s, F3dVec3 o,
                    F3dVec3 u, f3d_real limit, f3d_real *dist, F3dVec3 *normal) {
  const F3dPlaced p = f3d_placed_of(world, s);
  if (p.kind == F3D_SHAPE_SPHERE) {
    const f3d_real r = p.size.x + p.rounding;
    const F3dVec3 m = f3d_sub(o, p.at);
    const f3d_real b = f3d_dot(m, u);
    const f3d_real c = f3d_dot(m, m) - r * r;
    if (c <= F3D_R(0.0) || b > F3D_R(0.0)) return 0;
    /* r² less the ray's nearest distance to the centre, squared: the same
     * as b² − c, without subtracting two large numbers to get a small one —
     * which cost two millimetres at thirty metres in floats. */
    const F3dVec3 across = f3d_madd(m, u, -b);
    const f3d_real disc = r * r - f3d_dot(across, across);
    if (disc < F3D_R(0.0)) return 0;
    const f3d_real t = -b - f3d_sqrt(disc);
    if (t > limit) return 0;
    *dist = t;
    *normal = f3d_scale(f3d_sub(f3d_madd(o, u, t), p.at), F3D_R(1.0) / r);
    return 1;
  }
  if (p.kind == F3D_SHAPE_BOX && p.rounding == F3D_R(0.0)) {
    const F3dVec3 rel = f3d_sub(o, p.at);
    const f3d_real ol[3] = {f3d_dot(p.axes.c[0], rel), f3d_dot(p.axes.c[1], rel),
                            f3d_dot(p.axes.c[2], rel)};
    const f3d_real ul[3] = {f3d_dot(p.axes.c[0], u), f3d_dot(p.axes.c[1], u),
                            f3d_dot(p.axes.c[2], u)};
    const f3d_real h[3] = {p.size.x, p.size.y, p.size.z};
    f3d_real lo = F3D_R(-1e30), hi = limit;
    int axis = -1;
    f3d_real sign = F3D_R(0.0);
    for (int k = 0; k < 3; k++) {
      if (f3d_abs(ul[k]) <= F3D_R(1e-20)) {
        if (ol[k] < -h[k] || ol[k] > h[k]) return 0;
        continue;
      }
      const f3d_real inv = F3D_R(1.0) / ul[k];
      f3d_real t0 = (-h[k] - ol[k]) * inv, t1 = (h[k] - ol[k]) * inv;
      f3d_real s0 = F3D_R(-1.0);
      if (t0 > t1) {
        const f3d_real t = t0;
        t0 = t1;
        t1 = t;
        s0 = F3D_R(1.0);
      }
      if (t0 > lo) {
        lo = t0;
        axis = k;
        sign = s0;
      }
      hi = f3d_min(hi, t1);
      if (lo > hi) return 0;
    }
    /* Starting inside, or behind it. */
    if (axis < 0 || lo < F3D_R(0.0)) return 0;
    *dist = lo;
    *normal = f3d_scale(p.axes.c[axis], sign);
    return 1;
  }
  if (p.kind == F3D_SHAPE_MESH) {
    if (p.mesh == NULL || p.mesh_tree == NULL) return 0;
    MeshRay r;
    r.mesh = &p;
    const F3dVec3 rel = f3d_sub(o, p.at);
    r.o = f3d_v3(f3d_dot(p.axes.c[0], rel), f3d_dot(p.axes.c[1], rel),
                 f3d_dot(p.axes.c[2], rel));
    r.u = f3d_v3(f3d_dot(p.axes.c[0], u), f3d_dot(p.axes.c[1], u),
                 f3d_dot(p.axes.c[2], u));
    r.best = limit;
    r.found = 0;
    f3d_real cut = limit;
    f3d_tree_ray(p.mesh_tree, r.o, r.u, &cut, ray_triangle, &r);
    if (!r.found) return 0;
    *dist = r.best;
    *normal = f3d_add(f3d_add(f3d_scale(p.axes.c[0], r.normal.x),
                              f3d_scale(p.axes.c[1], r.normal.y)),
                      f3d_scale(p.axes.c[2], r.normal.z));
    return 1;
  }
  /* Conservative advancement of a point along the ray. */
  F3dPlaced probe;
  f3d_zero(&probe, sizeof probe);
  probe.kind = F3D_SHAPE_SPHERE;
  probe.axes.c[0] = f3d_v3(F3D_R(1.0), F3D_R(0.0), F3D_R(0.0));
  probe.axes.c[1] = f3d_v3(F3D_R(0.0), F3D_R(1.0), F3D_R(0.0));
  probe.axes.c[2] = f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(1.0));
  f3d_real t = F3D_R(0.0);
  for (int iteration = 0; iteration < 64; iteration++) {
    probe.at = f3d_madd(o, u, t);
    F3dManifold m;
    f3d_zero(&m, sizeof m);
    if (f3d_collide(&probe, &p, limit - t + F3D_QUERY_TOLERANCE, &m) == 0) {
      return 0;
    }
    const f3d_real gap = -deepest(&m, NULL);
    if (gap <= F3D_QUERY_TOLERANCE) {
      if (iteration == 0) return 0; /* It starts inside. */
      *dist = t;
      *normal = m.normal;
      return 1;
    }
    t += gap;
    if (t > limit) return 0;
  }
  return 0;
}

typedef struct RayWalk {
  const F3dWorld *world;
  F3dVec3 o, u;
  uint32_t mask;
  F3dBody ignore;
  /* Nearest: the best so far and the limit it cuts. */
  f3d_real *limit;
  F3dBody body;
  f3d_real distance;
  F3dVec3 normal;
  /* All: written nearest first, up to capacity; counted all. */
  F3dBody *bodies;
  f3d_real *hits;
  uint32_t capacity, count;
  int all;
} RayWalk;

static void write_hit(f3d_real *hit, F3dVec3 point, F3dVec3 normal,
                      f3d_real value) {
  hit[0] = point.x;
  hit[1] = point.y;
  hit[2] = point.z;
  hit[3] = normal.x;
  hit[4] = normal.y;
  hit[5] = normal.z;
  hit[6] = value;
}

static int ray_leaf(void *context, int32_t leaf) {
  RayWalk *r = (RayWalk *)context;
  const uint32_t slot = r->world->tree.nodes[leaf].slot;
  const F3dSlot *s = &r->world->slots[slot];
  if (!sees(r->world, s, r->mask, r->ignore)) return 1;
  f3d_real d;
  F3dVec3 n;
  if (!ray_body(r->world, s, r->o, r->u, *r->limit, &d, &n)) return 1;
  if (!r->all) {
    /* Equal distances go to the lower slot, so the tree's shape does not
     * choose. */
    const F3dBody h = f3d_handle_of(r->world, s);
    if (r->body == 0 || d < r->distance ||
        (d == r->distance && (uint32_t)h < (uint32_t)r->body)) {
      r->body = h;
      r->distance = d;
      r->normal = n;
      *r->limit = d;
    }
    return 1;
  }
  /* Kept nearest first, ties by slot: an insertion into what is written. */
  const uint32_t room = r->capacity;
  uint32_t at = r->count < room ? r->count : room;
  while (at > 0) {
    const f3d_real prev = r->hits[(at - 1u) * F3D_HIT_FLOATS + 6u];
    if (prev < d || (prev == d && (uint32_t)r->bodies[at - 1u] < slot)) break;
    at--;
  }
  if (at < room) {
    const uint32_t last = r->count < room ? r->count : room - 1u;
    for (uint32_t k = last; k > at; k--) {
      r->bodies[k] = r->bodies[k - 1u];
      for (uint32_t f = 0; f < F3D_HIT_FLOATS; f++) {
        r->hits[k * F3D_HIT_FLOATS + f] = r->hits[(k - 1u) * F3D_HIT_FLOATS + f];
      }
    }
    r->bodies[at] = f3d_handle_of(r->world, s);
    write_hit(&r->hits[at * F3D_HIT_FLOATS], f3d_madd(r->o, r->u, d), n, d);
  }
  r->count++;
  return 1;
}

static int unit_ray(f3d_real dx, f3d_real dy, f3d_real dz, F3dVec3 *u) {
  const f3d_real len = f3d_sqrt(dx * dx + dy * dy + dz * dz);
  if (!(len > F3D_R(0.0)) || !f3d_finite(len)) return 0;
  *u = f3d_v3(dx / len, dy / len, dz / len);
  return 1;
}

int f3d_world_ray_cast(F3dWorld *world, f3d_real ox, f3d_real oy, f3d_real oz,
                       f3d_real dx, f3d_real dy, f3d_real dz,
                       f3d_real max_distance, uint32_t mask, F3dBody ignore,
                       F3dBody *body, f3d_real *hit) {
  F3dVec3 u;
  if (!unit_ray(dx, dy, dz, &u) || !(max_distance > F3D_R(0.0))) return 0;
  f3d_update_proxies(world, F3D_R(0.0));
  f3d_build_mesh_trees(world);
  RayWalk r;
  f3d_zero(&r, sizeof r);
  r.world = world;
  r.o = f3d_v3(ox, oy, oz);
  r.u = u;
  r.mask = mask;
  r.ignore = ignore;
  f3d_real limit = max_distance;
  r.limit = &limit;
  f3d_tree_ray(&world->tree, r.o, r.u, &limit, ray_leaf, &r);
  if (r.body == 0) return 0;
  *body = r.body;
  write_hit(hit, f3d_madd(r.o, u, r.distance), r.normal, r.distance);
  return 1;
}

uint32_t f3d_world_ray_cast_all(F3dWorld *world, f3d_real ox, f3d_real oy,
                                f3d_real oz, f3d_real dx, f3d_real dy,
                                f3d_real dz, f3d_real max_distance,
                                uint32_t mask, F3dBody ignore, F3dBody *bodies,
                                f3d_real *hits, uint32_t capacity) {
  F3dVec3 u;
  if (!unit_ray(dx, dy, dz, &u) || !(max_distance > F3D_R(0.0))) return 0;
  f3d_update_proxies(world, F3D_R(0.0));
  f3d_build_mesh_trees(world);
  RayWalk r;
  f3d_zero(&r, sizeof r);
  r.world = world;
  r.o = f3d_v3(ox, oy, oz);
  r.u = u;
  r.mask = mask;
  r.ignore = ignore;
  f3d_real limit = max_distance;
  r.limit = &limit;
  r.all = 1;
  r.bodies = bodies;
  r.hits = hits;
  r.capacity = capacity;
  f3d_tree_ray(&world->tree, r.o, r.u, &limit, ray_leaf, &r);
  return r.count;
}

/* --------------------------------------------------------------- overlaps */

typedef struct Near {
  const F3dWorld *world;
  uint32_t slots[512];
  uint32_t count;
} Near;

static int near_leaf(void *context, int32_t leaf) {
  Near *n = (Near *)context;
  if (n->count < 512u) n->slots[n->count++] = n->world->tree.nodes[leaf].slot;
  return n->count < 512u;
}

/* The slots near [box], in slot order. */
static void gather(const F3dWorld *world, F3dBox box, Near *n) {
  n->world = world;
  n->count = 0;
  f3d_tree_query(&world->tree, box, near_leaf, n);
  for (uint32_t i = 1; i < n->count; i++) {
    const uint32_t v = n->slots[i];
    uint32_t j = i;
    while (j > 0 && n->slots[j - 1] > v) {
      n->slots[j] = n->slots[j - 1];
      j--;
    }
    n->slots[j] = v;
  }
}

static F3dBox around(F3dVec3 a, F3dVec3 b, f3d_real r) {
  F3dBox box;
  box.lo = f3d_v3(f3d_min(a.x, b.x) - r, f3d_min(a.y, b.y) - r,
                  f3d_min(a.z, b.z) - r);
  box.hi = f3d_v3(f3d_max(a.x, b.x) + r, f3d_max(a.y, b.y) + r,
                  f3d_max(a.z, b.z) + r);
  return box;
}

uint32_t f3d_world_overlap_shape(F3dWorld *world, F3dShapeKind kind, f3d_real a,
                                 f3d_real b, f3d_real c, f3d_real rounding,
                                 f3d_real px, f3d_real py, f3d_real pz,
                                 f3d_real qx, f3d_real qy, f3d_real qz,
                                 f3d_real qw, uint32_t mask, F3dBody ignore,
                                 F3dBody *out, uint32_t capacity) {
  F3dPlaced q;
  const F3dVec3 at = f3d_v3(px, py, pz);
  if (!query_shape(kind, a, b, c, rounding, at, unit(qx, qy, qz, qw), &q)) {
    return 0;
  }
  f3d_update_proxies(world, F3D_R(0.0));
  f3d_build_mesh_trees(world);
  Near n;
  gather(world, around(at, at, reach_of(&q)), &n);
  uint32_t count = 0;
  for (uint32_t i = 0; i < n.count; i++) {
    const F3dSlot *s = &world->slots[n.slots[i]];
    if (!sees(world, s, mask, ignore)) continue;
    const F3dPlaced p = f3d_placed_of(world, s);
    F3dManifold m;
    f3d_zero(&m, sizeof m);
    if (f3d_collide(&q, &p, F3D_R(0.0), &m) == 0) continue;
    if (deepest(&m, NULL) < F3D_R(0.0)) continue;
    if (count < capacity) out[count] = f3d_handle_of(world, s);
    count++;
  }
  return count;
}

/* ------------------------------------------------------------------ casts */

/* The first fraction of [move] at which [q] touches [other]: 1 and the
 * fraction, the normal out of [other] and the point; 0 when it does not
 * within the move. Overlapping at the start, nought. */
static int cast_against(const F3dPlaced *q, F3dVec3 move, const F3dPlaced *other,
                        f3d_real *fraction, F3dVec3 *normal, F3dVec3 *point) {
  const f3d_real length = f3d_sqrt(f3d_dot(move, move));
  F3dPlaced at = *q;
  const F3dVec3 start = q->at;
  f3d_real t = F3D_R(0.0);
  for (int iteration = 0; iteration < 64; iteration++) {
    at.at = f3d_madd(start, move, t);
    F3dManifold m;
    f3d_zero(&m, sizeof m);
    const f3d_real reach = (F3D_R(1.0) - t) * length + F3D_QUERY_TOLERANCE;
    if (f3d_collide(&at, other, reach, &m) == 0) return 0;
    F3dVec3 p;
    const f3d_real gap = -deepest(&m, &p);
    if (gap <= F3D_QUERY_TOLERANCE) {
      *fraction = t;
      *normal = m.normal;
      *point = p;
      return 1;
    }
    const f3d_real closing = -f3d_dot(move, m.normal);
    if (!(closing > F3D_R(1e-12) * length)) return 0;
    t += (gap - F3D_R(0.5) * F3D_QUERY_TOLERANCE) / closing;
    if (t > F3D_R(1.0)) return 0;
  }
  return 0;
}

/* The nearest of what [q] moved by [move] meets. A body on a layer in
 * [from_above] is met only from above — with a normal whose height is at
 * least [from_above_cos] — and passed through every other way: a platform
 * jumped up through and landed on. */
static int cast_world(F3dWorld *world, const F3dPlaced *q, F3dVec3 move,
                      uint32_t mask, uint32_t from_above, f3d_real from_above_cos,
                      F3dBody ignore, F3dBody *body, f3d_real *fraction,
                      F3dVec3 *normal, F3dVec3 *point) {
  Near n;
  gather(world, around(q->at, f3d_add(q->at, move), reach_of(q) + F3D_QUERY_TOLERANCE),
         &n);
  int found = 0;
  for (uint32_t i = 0; i < n.count; i++) {
    const F3dSlot *s = &world->slots[n.slots[i]];
    if (!sees(world, s, mask, ignore)) continue;
    const F3dPlaced p = f3d_placed_of(world, s);
    f3d_real t;
    F3dVec3 nn, pp;
    if (!cast_against(q, move, &p, &t, &nn, &pp)) continue;
    /* Met from above or not at all; and not one it starts inside, which a
     * body rising through it or standing in it passes out of. */
    if ((s->layer & from_above) && (nn.y < from_above_cos || t <= F3D_R(0.0))) {
      continue;
    }
    if (found && t >= *fraction) continue;
    found = 1;
    *body = f3d_handle_of(world, s);
    *fraction = t;
    *normal = nn;
    *point = pp;
  }
  return found;
}

int f3d_world_cast_shape(F3dWorld *world, F3dShapeKind kind, f3d_real a,
                         f3d_real b, f3d_real c, f3d_real rounding, f3d_real px,
                         f3d_real py, f3d_real pz, f3d_real qx, f3d_real qy,
                         f3d_real qz, f3d_real qw, f3d_real tx, f3d_real ty,
                         f3d_real tz, uint32_t mask, F3dBody ignore,
                         F3dBody *body, f3d_real *hit) {
  F3dPlaced q;
  if (!query_shape(kind, a, b, c, rounding, f3d_v3(px, py, pz),
                   unit(qx, qy, qz, qw), &q)) {
    return 0;
  }
  if (!(f3d_finite(tx) && f3d_finite(ty) && f3d_finite(tz))) return 0;
  f3d_update_proxies(world, F3D_R(0.0));
  f3d_build_mesh_trees(world);
  f3d_real t;
  F3dVec3 n, p;
  if (!cast_world(world, &q, f3d_v3(tx, ty, tz), mask, 0u, F3D_R(0.0), ignore,
                  body, &t, &n, &p)) {
    return 0;
  }
  write_hit(hit, p, n, t);
  return 1;
}

/* ------------------------------------------------------------- characters */

typedef struct Character {
  F3dWorld *world;
  F3dPlaced shape;
  uint32_t mask;
  uint32_t from_above;
  f3d_real from_above_cos;
  F3dBody ignore;
} Character;

/* Moves the character by as much of [move] as it can, and its skin off
 * what it met along that surface's normal; 1 and the hit when it met
 * something. Off along the normal, not back along the move: a move that
 * only grazed a surface — sliding over the edge of a step — backed off
 * along itself is no further from it, starts the next cast touching it
 * and goes nowhere. */
static int advance(Character *c, F3dVec3 move, F3dVec3 *normal, F3dBody *body,
                   f3d_real *travelled) {
  *travelled = F3D_R(1.0);
  const f3d_real length = f3d_sqrt(f3d_dot(move, move));
  if (!(length > F3D_R(1e-9))) return 0;
  f3d_real t;
  F3dVec3 p;
  if (!cast_world(c->world, &c->shape, move, c->mask, c->from_above,
                  c->from_above_cos, c->ignore, body, &t, normal, &p)) {
    c->shape.at = f3d_add(c->shape.at, move);
    return 0;
  }
  *travelled = f3d_max(t, F3D_R(0.0));
  c->shape.at = f3d_madd(f3d_madd(c->shape.at, move, *travelled), *normal,
                         F3D_CHARACTER_SKIN);
  return 1;
}

/* What one slide met: its F3D_CHARACTER_ bits and the ground it stood on. */
typedef struct Slid {
  uint32_t flags;
  F3dBody ground_body;
  F3dVec3 ground;
} Slid;

/* Casts and slides [move], up to four times — a corner is two walls and a
 * floor — taking out of [velocity] the speed into everything it meets, as
 * the speed into a wall is gone for good. A face too steep to stand on is
 * met as an upright wall, so sliding along it does not climb it. */
static Slid slide(Character *c, F3dVec3 move, F3dVec3 *velocity,
                  f3d_real max_slope_cos) {
  Slid out = {0u, 0, {F3D_R(0.0), F3D_R(0.0), F3D_R(0.0)}};
  F3dVec3 left = move;
  for (int i = 0; i < 4 && f3d_dot(left, left) > F3D_R(1e-14); i++) {
    F3dVec3 n;
    F3dBody hit;
    f3d_real travelled;
    if (!advance(c, left, &n, &hit, &travelled)) break;
    /* What is left of the move, not of where the skin put it. */
    left = f3d_scale(left, F3D_R(1.0) - travelled);
    if (n.y >= max_slope_cos) {
      out.flags |= F3D_CHARACTER_GROUNDED;
      out.ground_body = hit;
      out.ground = n;
    } else if (n.y <= -max_slope_cos) {
      out.flags |= F3D_CHARACTER_CEILING;
    } else {
      out.flags |= F3D_CHARACTER_WALL;
      const f3d_real flat = f3d_sqrt(n.x * n.x + n.z * n.z);
      if (flat > F3D_R(1e-9)) {
        n = f3d_v3(n.x / flat, F3D_R(0.0), n.z / flat);
      }
    }
    const f3d_real into = f3d_dot(left, n);
    if (into < F3D_R(0.0)) left = f3d_madd(left, n, -into);
    const f3d_real speed = f3d_dot(*velocity, n);
    if (speed < F3D_R(0.0)) *velocity = f3d_madd(*velocity, n, -speed);
  }
  return out;
}

/* Out of whatever the character starts inside — something moved into it,
 * a door, a lift's side, another character: up to four times the deepest
 * overlap, along its normal by its depth and the skin, the speed into it
 * taken out of [velocity]. Not out of a body on a from-above layer, which
 * it passes through. */
static void push_out(Character *c, F3dVec3 *velocity) {
  for (int k = 0; k < 4; k++) {
    Near n;
    gather(c->world, around(c->shape.at, c->shape.at, reach_of(&c->shape)), &n);
    f3d_real worst = F3D_R(0.0);
    F3dVec3 away = f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
    for (uint32_t i = 0; i < n.count; i++) {
      const F3dSlot *s = &c->world->slots[n.slots[i]];
      if (!sees(c->world, s, c->mask, c->ignore)) continue;
      if (s->layer & c->from_above) continue;
      const F3dPlaced p = f3d_placed_of(c->world, s);
      F3dManifold m;
      f3d_zero(&m, sizeof m);
      if (f3d_collide(&c->shape, &p, F3D_R(0.0), &m) == 0) continue;
      const f3d_real depth = deepest(&m, NULL);
      if (depth > worst) {
        worst = depth;
        away = m.normal;
      }
    }
    if (!(worst > F3D_QUERY_TOLERANCE)) return;
    c->shape.at = f3d_madd(c->shape.at, away, worst + F3D_CHARACTER_SKIN);
    const f3d_real speed = f3d_dot(*velocity, away);
    if (speed < F3D_R(0.0)) *velocity = f3d_madd(*velocity, away, -speed);
  }
}

/* How far [at] got from [from] along the level direction (dx, dz). */
static f3d_real progress(F3dVec3 from, F3dVec3 at, f3d_real dx, f3d_real dz) {
  return (at.x - from.x) * dx + (at.z - from.z) * dz;
}

uint32_t f3d_world_move_character(F3dWorld *world, F3dShapeKind kind,
                                  f3d_real a, f3d_real b, f3d_real c3,
                                  f3d_real *position,
                                  f3d_real dx, f3d_real dy, f3d_real dz,
                                  f3d_real *velocity, f3d_real max_slope_cos,
                                  f3d_real step_height, uint32_t mask,
                                  uint32_t from_above, uint32_t options,
                                  F3dBody ignore, F3dBody *ground_body,
                                  f3d_real *ground, f3d_real *stepped_up) {
  *ground_body = 0;
  *stepped_up = F3D_R(0.0);
  ground[0] = ground[1] = ground[2] = F3D_R(0.0);
  if (!(f3d_finite(dx) && f3d_finite(dy) && f3d_finite(dz))) return 0;
  if (!f3d_finite(step_height) || !f3d_finite(max_slope_cos)) return 0;
  f3d_update_proxies(world, F3D_R(0.0));
  f3d_build_mesh_trees(world);
  Character c;
  c.world = world;
  c.mask = mask;
  c.from_above = from_above;
  c.from_above_cos = max_slope_cos;
  c.ignore = ignore;
  const F3dQuat upright = {F3D_R(0.0), F3D_R(0.0), F3D_R(0.0), F3D_R(1.0)};
  if (!query_shape(kind, a, b, c3, F3D_R(0.0),
                   f3d_v3(position[0], position[1], position[2]), upright,
                   &c.shape)) {
    return 0;
  }
  F3dVec3 pushed = f3d_v3(velocity[0], velocity[1], velocity[2]);
  push_out(&c, &pushed);
  const F3dVec3 start = c.shape.at;
  const F3dVec3 v0 = pushed;

  /* The plain move: slide along whatever is in the way. */
  F3dVec3 v = v0;
  Slid plain = slide(&c, f3d_v3(dx, dy, dz), &v, max_slope_cos);
  uint32_t flags = plain.flags;
  *ground_body = plain.ground_body;
  F3dVec3 g = plain.ground;

  /* Stopped by a wall while standing: it might be a step. Up by the step's
   * height — given up if something overhead stops it there, there being no
   * room to climb into — across, down onto ground; and taken only if it got
   * further along the way asked than sliding did, which tells a stair from
   * a wall. */
  const int level = dx * dx + dz * dz > F3D_R(1e-14);
  if ((options & F3D_CHARACTER_MAY_STEP) && (plain.flags & F3D_CHARACTER_WALL) &&
      level && step_height > F3D_R(0.0)) {
    const F3dVec3 plain_at = c.shape.at;
    const F3dVec3 plain_v = v;
    c.shape.at = start;
    F3dVec3 n;
    F3dBody hit;
    f3d_real travelled;
    int kept = 0;
    if (!advance(&c, f3d_v3(F3D_R(0.0), step_height, F3D_R(0.0)), &n, &hit,
                 &travelled)) {
      F3dVec3 sv = v0;
      slide(&c, f3d_v3(dx, F3D_R(0.0), dz), &sv, max_slope_cos);
      const int landed = advance(
          &c,
          f3d_v3(F3D_R(0.0), -step_height - F3D_CHARACTER_SKIN, F3D_R(0.0)),
          &n, &hit, &travelled);
      if (landed && n.y >= max_slope_cos &&
          progress(start, c.shape.at, dx, dz) >
              progress(start, plain_at, dx, dz) + F3D_R(1e-6)) {
        kept = 1;
        flags = (flags & ~F3D_CHARACTER_WALL) | F3D_CHARACTER_STEPPED |
                F3D_CHARACTER_GROUNDED;
        *ground_body = hit;
        g = n;
        *stepped_up = f3d_max(c.shape.at.y - start.y, F3D_R(0.0));
        sv.y = F3D_R(0.0);
        v = sv;
      }
    }
    if (!kept) {
      c.shape.at = plain_at;
      v = plain_v;
    }
  }

  /* Keeping to the ground: not moving up and not on ground, it looks down
   * as far as a step, or its skin twice over, and settles on ground there —
   * walking down a slope or off a kerb, not floating off it. */
  if (!(flags & F3D_CHARACTER_GROUNDED) && dy <= F3D_R(0.0)) {
    const F3dVec3 before = c.shape.at;
    const f3d_real reach =
        f3d_max(step_height, F3D_R(2.0) * F3D_CHARACTER_SKIN);
    F3dVec3 n;
    F3dBody hit;
    f3d_real travelled;
    if (advance(&c, f3d_v3(F3D_R(0.0), -reach, F3D_R(0.0)), &n, &hit,
                &travelled) &&
        n.y >= max_slope_cos) {
      flags |= F3D_CHARACTER_GROUNDED;
      *ground_body = hit;
      g = n;
    } else {
      c.shape.at = before;
    }
  }
  ground[0] = g.x;
  ground[1] = g.y;
  ground[2] = g.z;
  velocity[0] = v.x;
  velocity[1] = v.y;
  velocity[2] = v.z;
  position[0] = c.shape.at.x;
  position[1] = c.shape.at.y;
  position[2] = c.shape.at.z;
  return flags;
}
