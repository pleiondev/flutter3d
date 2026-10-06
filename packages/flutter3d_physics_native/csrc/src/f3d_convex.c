/*
 * The general narrow phase — P9, phase 5: any two convex shapes, by their
 * support functions.
 *
 * Every shape is a core and a rounding: a ball is a point rounded by its
 * radius, a capsule a segment, and a box, cylinder, cone or hull is itself
 * rounded by whatever rounding the body has. GJK (Gilbert, Johnson and
 * Keerthi; the closest points of a simplex after Ericson's Real-Time
 * Collision Detection, §5.1) finds how far apart the cores are, and the
 * contact is the roundings less that. Where the cores themselves overlap,
 * EPA (van den Bergen) expands GJK's last simplex to the face of the
 * Minkowski difference nearest the origin, which is the way out and how
 * deep.
 *
 * One point is a pin to balance on, so the manifold comes from the two
 * shapes' features facing each other along the normal — a face, an edge or
 * a corner each: face against face clips one polygon to the other, an edge
 * against a face clips the edge, two parallel edges keep their overlap.
 * Every loop has a fixed bound and a fixed order, so the same pair answers
 * with the same bits everywhere.
 */
#include "f3d_internal.h"

#ifdef F3D_REAL_DOUBLE
#define F3D_GJK_RELATIVE F3D_R(1e-12)
#define F3D_GJK_TOUCH F3D_R(1e-20)
#define F3D_EPA_TOLERANCE F3D_R(1e-9)
#else
#define F3D_GJK_RELATIVE F3D_R(1e-6)
/* Closer than this share of the difference's size, squared, is touching:
 * a float holds the cores' distance no finer than a part in a hundred
 * thousand of how big they are, and below it GJK's simplex wobbles round
 * the origin rather than closing on it. */
#define F3D_GJK_TOUCH F3D_R(1e-10)
#define F3D_EPA_TOLERANCE F3D_R(1e-5)
#endif

/* Within five degrees of square to a face is resting on it. */
#define F3D_FACE_COS F3D_R(0.9961947)
#define F3D_FACE_SIN F3D_R(0.0871557)

static F3dVec3 local_of(const F3dPlaced *p, F3dVec3 v) {
  return f3d_v3(f3d_dot(p->axes.c[0], v), f3d_dot(p->axes.c[1], v),
                f3d_dot(p->axes.c[2], v));
}

static F3dVec3 world_of(const F3dPlaced *p, F3dVec3 l) {
  return f3d_add(p->at, f3d_add(f3d_add(f3d_scale(p->axes.c[0], l.x),
                                        f3d_scale(p->axes.c[1], l.y)),
                                f3d_scale(p->axes.c[2], l.z)));
}

static F3dVec3 hull_vertex(const F3dPlaced *p, uint32_t i) {
  return f3d_v3(p->vertices[i * 3u], p->vertices[i * 3u + 1u],
                p->vertices[i * 3u + 2u]);
}

/* How far a shape is rounded beyond its core. */
static f3d_real rounding_of(const F3dPlaced *p) {
  if (p->kind == F3D_SHAPE_SPHERE || p->kind == F3D_SHAPE_CAPSULE) {
    return p->size.x + p->rounding;
  }
  return p->rounding;
}

/* The core's furthest point along [d], both in the shape's own frame. */
static F3dVec3 core_support(const F3dPlaced *p, F3dVec3 d) {
  const F3dVec3 s = p->size;
  switch (p->kind) {
    case F3D_SHAPE_CAPSULE:
      return f3d_v3(F3D_R(0.0), d.y >= F3D_R(0.0) ? s.y : -s.y, F3D_R(0.0));
    case F3D_SHAPE_BOX:
      return f3d_v3(d.x >= F3D_R(0.0) ? s.x : -s.x,
                    d.y >= F3D_R(0.0) ? s.y : -s.y,
                    d.z >= F3D_R(0.0) ? s.z : -s.z);
    case F3D_SHAPE_CYLINDER: {
      const f3d_real flat = f3d_sqrt(d.x * d.x + d.z * d.z);
      const f3d_real k = flat > F3D_R(1e-12) ? s.x / flat : F3D_R(0.0);
      return f3d_v3(d.x * k, d.y >= F3D_R(0.0) ? s.y : -s.y, d.z * k);
    }
    case F3D_SHAPE_CONE: {
      const F3dVec3 apex = f3d_v3(F3D_R(0.0), F3D_R(0.75) * s.y, F3D_R(0.0));
      const f3d_real flat = f3d_sqrt(d.x * d.x + d.z * d.z);
      const f3d_real k = flat > F3D_R(1e-12) ? s.x / flat : F3D_R(0.0);
      const F3dVec3 rim = f3d_v3(d.x * k, F3D_R(-0.25) * s.y, d.z * k);
      return f3d_dot(apex, d) >= f3d_dot(rim, d) ? apex : rim;
    }
    case F3D_SHAPE_TRIANGLE: {
      uint32_t best = 0;
      f3d_real most = f3d_dot(hull_vertex(p, 0), d);
      for (uint32_t i = 1; i < 3u; i++) {
        const f3d_real v = f3d_dot(hull_vertex(p, i), d);
        if (v > most) {
          most = v;
          best = i;
        }
      }
      return hull_vertex(p, best);
    }
    case F3D_SHAPE_HULL: {
      if (p->hull == NULL) break;
      uint32_t best = 0;
      f3d_real most = f3d_dot(hull_vertex(p, 0), d);
      for (uint32_t i = 1; i < p->hull->vertex_count; i++) {
        const f3d_real v = f3d_dot(hull_vertex(p, i), d);
        if (v > most) {
          most = v;
          best = i;
        }
      }
      return hull_vertex(p, best);
    }
    default:
      break;
  }
  return f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
}

typedef struct Vertex {
  /* a − b, and the two points it came from. */
  F3dVec3 w, a, b;
} Vertex;

static Vertex support(const F3dPlaced *a, const F3dPlaced *b, F3dVec3 d) {
  Vertex v;
  v.a = world_of(a, core_support(a, local_of(a, d)));
  v.b = world_of(b, core_support(b, local_of(b, f3d_scale(d, F3D_R(-1.0)))));
  v.w = f3d_sub(v.a, v.b);
  return v;
}

/* ---------------------------------------------------------------- GJK */

typedef struct Simplex {
  Vertex v[4];
  f3d_real l[4];
  uint32_t n;
} Simplex;

static void keep(Simplex *s, const uint32_t *which, const f3d_real *weights,
                 uint32_t count) {
  Vertex v[4];
  for (uint32_t i = 0; i < count; i++) v[i] = s->v[which[i]];
  for (uint32_t i = 0; i < count; i++) {
    s->v[i] = v[i];
    s->l[i] = weights[i];
  }
  s->n = count;
}

/* The closest point of the triangle i, j, k to the origin, Ericson's
 * ClosestPtPointTriangle, the simplex reduced to the feature it lies on;
 * returns the point. */
static F3dVec3 closest_triangle(Simplex *s, uint32_t i, uint32_t j,
                                uint32_t k) {
  const F3dVec3 a = s->v[i].w, b = s->v[j].w, c = s->v[k].w;
  const F3dVec3 ab = f3d_sub(b, a), ac = f3d_sub(c, a);
  const F3dVec3 ap = f3d_scale(a, F3D_R(-1.0));
  const f3d_real d1 = f3d_dot(ab, ap), d2 = f3d_dot(ac, ap);
  if (d1 <= F3D_R(0.0) && d2 <= F3D_R(0.0)) {
    const uint32_t w[1] = {i};
    const f3d_real l[1] = {F3D_R(1.0)};
    keep(s, w, l, 1);
    return a;
  }
  const F3dVec3 bp = f3d_scale(b, F3D_R(-1.0));
  const f3d_real d3 = f3d_dot(ab, bp), d4 = f3d_dot(ac, bp);
  if (d3 >= F3D_R(0.0) && d4 <= d3) {
    const uint32_t w[1] = {j};
    const f3d_real l[1] = {F3D_R(1.0)};
    keep(s, w, l, 1);
    return b;
  }
  const f3d_real vc = d1 * d4 - d3 * d2;
  if (vc <= F3D_R(0.0) && d1 >= F3D_R(0.0) && d3 <= F3D_R(0.0)) {
    const f3d_real t = d1 / (d1 - d3);
    const uint32_t w[2] = {i, j};
    const f3d_real l[2] = {F3D_R(1.0) - t, t};
    keep(s, w, l, 2);
    return f3d_madd(a, ab, t);
  }
  const F3dVec3 cp = f3d_scale(c, F3D_R(-1.0));
  const f3d_real d5 = f3d_dot(ab, cp), d6 = f3d_dot(ac, cp);
  if (d6 >= F3D_R(0.0) && d5 <= d6) {
    const uint32_t w[1] = {k};
    const f3d_real l[1] = {F3D_R(1.0)};
    keep(s, w, l, 1);
    return c;
  }
  const f3d_real vb = d5 * d2 - d1 * d6;
  if (vb <= F3D_R(0.0) && d2 >= F3D_R(0.0) && d6 <= F3D_R(0.0)) {
    const f3d_real t = d2 / (d2 - d6);
    const uint32_t w[2] = {i, k};
    const f3d_real l[2] = {F3D_R(1.0) - t, t};
    keep(s, w, l, 2);
    return f3d_madd(a, ac, t);
  }
  const f3d_real va = d3 * d6 - d5 * d4;
  if (va <= F3D_R(0.0) && d4 - d3 >= F3D_R(0.0) && d5 - d6 >= F3D_R(0.0)) {
    const f3d_real t = (d4 - d3) / ((d4 - d3) + (d5 - d6));
    const uint32_t w[2] = {j, k};
    const f3d_real l[2] = {F3D_R(1.0) - t, t};
    keep(s, w, l, 2);
    return f3d_madd(b, f3d_sub(c, b), t);
  }
  const f3d_real denom = F3D_R(1.0) / (va + vb + vc);
  const f3d_real v = vb * denom, w2 = vc * denom;
  const uint32_t w[3] = {i, j, k};
  const f3d_real l[3] = {F3D_R(1.0) - v - w2, v, w2};
  keep(s, w, l, 3);
  return f3d_add(a, f3d_add(f3d_scale(ab, v), f3d_scale(ac, w2)));
}

/* Whether the origin lies on the far side of face a, b, c from d. */
static int outside(F3dVec3 a, F3dVec3 b, F3dVec3 c, F3dVec3 d) {
  const F3dVec3 n = f3d_cross(f3d_sub(b, a), f3d_sub(c, a));
  const f3d_real o = -f3d_dot(n, a);
  const f3d_real other = f3d_dot(n, f3d_sub(d, a));
  /* A flat tetrahedron has no inside; every face is looked at. */
  if (f3d_abs(other) <= F3D_R(1e-12) * (F3D_R(1.0) + f3d_dot(n, n))) return 1;
  return o * other < F3D_R(0.0);
}

/* The simplex's closest point to the origin, the simplex reduced to the
 * feature it lies on; [inside] is set when a tetrahedron holds the origin. */
static F3dVec3 closest(Simplex *s, int *inside) {
  *inside = 0;
  switch (s->n) {
    case 1:
      s->l[0] = F3D_R(1.0);
      return s->v[0].w;
    case 2: {
      const F3dVec3 a = s->v[0].w, ab = f3d_sub(s->v[1].w, a);
      const f3d_real dd = f3d_dot(ab, ab);
      f3d_real t = dd > F3D_R(0.0) ? -f3d_dot(a, ab) / dd : F3D_R(0.0);
      if (t <= F3D_R(0.0)) {
        const uint32_t w[1] = {0};
        const f3d_real l[1] = {F3D_R(1.0)};
        keep(s, w, l, 1);
        return a;
      }
      if (t >= F3D_R(1.0)) {
        const uint32_t w[1] = {1};
        const f3d_real l[1] = {F3D_R(1.0)};
        keep(s, w, l, 1);
        return s->v[0].w;
      }
      s->l[0] = F3D_R(1.0) - t;
      s->l[1] = t;
      return f3d_madd(a, ab, t);
    }
    case 3:
      return closest_triangle(s, 0, 1, 2);
    default: {
      const F3dVec3 a = s->v[0].w, b = s->v[1].w, c = s->v[2].w,
                    d = s->v[3].w;
      const uint32_t faces[4][4] = {
          {0, 1, 2, 3}, {0, 2, 3, 1}, {0, 3, 1, 2}, {1, 3, 2, 0}};
      const F3dVec3 pts[4] = {a, b, c, d};
      int any = 0;
      Simplex best = *s;
      f3d_real nearest = F3D_R(1e30);
      F3dVec3 point = a;
      for (int f = 0; f < 4; f++) {
        if (!outside(pts[faces[f][0]], pts[faces[f][1]], pts[faces[f][2]],
                     pts[faces[f][3]])) {
          continue;
        }
        any = 1;
        Simplex trial = *s;
        const F3dVec3 q =
            closest_triangle(&trial, faces[f][0], faces[f][1], faces[f][2]);
        const f3d_real d2 = f3d_dot(q, q);
        if (d2 < nearest) {
          nearest = d2;
          best = trial;
          point = q;
        }
      }
      if (!any) {
        *inside = 1;
        return f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
      }
      *s = best;
      return point;
    }
  }
}

/* ---------------------------------------------------------------- EPA */

#define F3D_EPA_VERTICES 64
#define F3D_EPA_FACES 128

typedef struct Face {
  uint8_t i, j, k, live;
  F3dVec3 n;
  f3d_real d;
} Face;

typedef struct Polytope {
  Vertex v[F3D_EPA_VERTICES];
  uint32_t nv;
  Face f[F3D_EPA_FACES];
  uint32_t nf;
} Polytope;

static int add_face(Polytope *p, uint32_t i, uint32_t j, uint32_t k) {
  if (p->nf >= F3D_EPA_FACES) return 0;
  const F3dVec3 a = p->v[i].w;
  F3dVec3 n = f3d_cross(f3d_sub(p->v[j].w, a), f3d_sub(p->v[k].w, a));
  const f3d_real len = f3d_sqrt(f3d_dot(n, n));
  Face *f = &p->f[p->nf++];
  f->i = (uint8_t)i;
  f->j = (uint8_t)j;
  f->k = (uint8_t)k;
  f->live = len > F3D_R(1e-18);
  n = f->live ? f3d_scale(n, F3D_R(1.0) / len) : n;
  f->n = n;
  f->d = f3d_dot(n, a);
  return 1;
}

/* Grows GJK's simplex to a tetrahedron round the origin. */
static int blow_up(const F3dPlaced *a, const F3dPlaced *b, Simplex *s) {
  const F3dVec3 axes[6] = {
      {F3D_R(1.0), F3D_R(0.0), F3D_R(0.0)}, {F3D_R(-1.0), F3D_R(0.0), F3D_R(0.0)},
      {F3D_R(0.0), F3D_R(1.0), F3D_R(0.0)}, {F3D_R(0.0), F3D_R(-1.0), F3D_R(0.0)},
      {F3D_R(0.0), F3D_R(0.0), F3D_R(1.0)}, {F3D_R(0.0), F3D_R(0.0), F3D_R(-1.0)}};
  const f3d_real tiny = F3D_R(1e-12);
  if (s->n == 1) {
    for (int k = 0; k < 6 && s->n == 1; k++) {
      const Vertex v = support(a, b, axes[k]);
      const F3dVec3 d = f3d_sub(v.w, s->v[0].w);
      if (f3d_dot(d, d) > tiny) s->v[s->n++] = v;
    }
  }
  if (s->n == 2) {
    const F3dVec3 line = f3d_sub(s->v[1].w, s->v[0].w);
    for (int k = 0; k < 6 && s->n == 2; k += 2) {
      const F3dVec3 d = f3d_cross(line, axes[k]);
      if (f3d_dot(d, d) <= tiny) continue;
      for (int sign = 0; sign < 2 && s->n == 2; sign++) {
        const Vertex v =
            support(a, b, sign ? f3d_scale(d, F3D_R(-1.0)) : d);
        const F3dVec3 off = f3d_cross(line, f3d_sub(v.w, s->v[0].w));
        if (f3d_dot(off, off) > tiny) s->v[s->n++] = v;
      }
    }
  }
  if (s->n == 3) {
    const F3dVec3 n = f3d_cross(f3d_sub(s->v[1].w, s->v[0].w),
                                f3d_sub(s->v[2].w, s->v[0].w));
    for (int sign = 0; sign < 2 && s->n == 3; sign++) {
      const Vertex v = support(a, b, sign ? f3d_scale(n, F3D_R(-1.0)) : n);
      if (f3d_abs(f3d_dot(n, f3d_sub(v.w, s->v[0].w))) > tiny) {
        s->v[s->n++] = v;
      }
    }
  }
  return s->n == 4;
}

/* EPA from a tetrahedron round the origin: the face of the Minkowski
 * difference nearest the origin, its normal and distance, and the points
 * on the two cores it came from. 0 when the polytope will not grow. */
static int expand(const F3dPlaced *a, const F3dPlaced *b, const Simplex *s,
                  F3dVec3 *normal, f3d_real *depth, F3dVec3 *pa,
                  F3dVec3 *pb) {
  static const int tetra[4][4] = {
      {0, 1, 2, 3}, {0, 3, 1, 2}, {0, 2, 3, 1}, {1, 3, 2, 0}};
  Polytope p;
  p.nv = 4;
  p.nf = 0;
  for (int i = 0; i < 4; i++) p.v[i] = s->v[i];
  for (int f = 0; f < 4; f++) {
    uint32_t i = (uint32_t)tetra[f][0], j = (uint32_t)tetra[f][1];
    const uint32_t k = (uint32_t)tetra[f][2], o = (uint32_t)tetra[f][3];
    const F3dVec3 n = f3d_cross(f3d_sub(p.v[j].w, p.v[i].w),
                                f3d_sub(p.v[k].w, p.v[i].w));
    if (f3d_dot(n, f3d_sub(p.v[o].w, p.v[i].w)) > F3D_R(0.0)) {
      const uint32_t t = i;
      i = j;
      j = t;
    }
    add_face(&p, i, j, k);
  }
  int best = -1;
  for (int iteration = 0; iteration < 64; iteration++) {
    best = -1;
    for (uint32_t f = 0; f < p.nf; f++) {
      if (!p.f[f].live) continue;
      if (best < 0 || p.f[f].d < p.f[best].d) best = (int)f;
    }
    if (best < 0) return 0;
    const Face near = p.f[best];
    const Vertex w = support(a, b, near.n);
    if (f3d_dot(w.w, near.n) - near.d <= F3D_EPA_TOLERANCE ||
        p.nv >= F3D_EPA_VERTICES) {
      break;
    }
    /* What w sees goes; the edges round what it sees, the horizon, are
     * joined to it. An edge two seen faces share appears twice, in
     * opposite directions, and is not on the horizon. */
    uint8_t edges[F3D_EPA_FACES * 3][2];
    uint32_t ne = 0;
    for (uint32_t f = 0; f < p.nf; f++) {
      Face *face = &p.f[f];
      if (!face->live) continue;
      if (f3d_dot(face->n, f3d_sub(w.w, p.v[face->i].w)) <= F3D_R(0.0)) {
        continue;
      }
      face->live = 0;
      const uint8_t e[3][2] = {
          {face->i, face->j}, {face->j, face->k}, {face->k, face->i}};
      for (int k = 0; k < 3; k++) {
        int shared = -1;
        for (uint32_t q = 0; q < ne; q++) {
          if (edges[q][0] == e[k][1] && edges[q][1] == e[k][0]) shared = (int)q;
        }
        if (shared >= 0) {
          edges[shared][0] = edges[ne - 1][0];
          edges[shared][1] = edges[ne - 1][1];
          ne--;
        } else if (ne < F3D_EPA_FACES * 3) {
          edges[ne][0] = e[k][0];
          edges[ne][1] = e[k][1];
          ne++;
        }
      }
    }
    const uint32_t nw = p.nv++;
    p.v[nw] = w;
    /* Dead faces are compacted away before the new ones go in, so the
     * table does not fill with what the polytope no longer has. */
    uint32_t live = 0;
    for (uint32_t f = 0; f < p.nf; f++) {
      if (p.f[f].live) p.f[live++] = p.f[f];
    }
    p.nf = live;
    for (uint32_t q = 0; q < ne; q++) {
      if (!add_face(&p, edges[q][0], edges[q][1], nw)) break;
    }
  }
  if (best < 0) return 0;
  const Face face = p.f[best];
  /* The origin's projection on the face, in the face's barycentrics. */
  const F3dVec3 x = f3d_scale(face.n, face.d);
  const F3dVec3 v0 = f3d_sub(p.v[face.j].w, p.v[face.i].w);
  const F3dVec3 v1 = f3d_sub(p.v[face.k].w, p.v[face.i].w);
  const F3dVec3 v2 = f3d_sub(x, p.v[face.i].w);
  const f3d_real d00 = f3d_dot(v0, v0), d01 = f3d_dot(v0, v1);
  const f3d_real d11 = f3d_dot(v1, v1), d20 = f3d_dot(v2, v0);
  const f3d_real d21 = f3d_dot(v2, v1);
  const f3d_real den = d00 * d11 - d01 * d01;
  f3d_real u = F3D_R(0.0), v = F3D_R(0.0);
  if (den > F3D_R(0.0)) {
    u = (d11 * d20 - d01 * d21) / den;
    v = (d00 * d21 - d01 * d20) / den;
  }
  const f3d_real l0 = F3D_R(1.0) - u - v;
  *pa = f3d_add(f3d_add(f3d_scale(p.v[face.i].a, l0),
                        f3d_scale(p.v[face.j].a, u)),
                f3d_scale(p.v[face.k].a, v));
  *pb = f3d_add(f3d_add(f3d_scale(p.v[face.i].b, l0),
                        f3d_scale(p.v[face.j].b, u)),
                f3d_scale(p.v[face.k].b, v));
  *normal = face.n;
  *depth = face.d;
  return 1;
}

/* ----------------------------------------------------------- features */

#define F3D_FEATURE_POINTS 16

typedef struct Feature {
  F3dVec3 p[F3D_FEATURE_POINTS];
  uint32_t n;
} Feature;

/* Puts a polygon's points in order round their middle, seen along [d]: by
 * a pseudo-angle that rises with the angle and needs no arctangent. */
static void order(Feature *f, F3dVec3 d) {
  if (f->n < 3) return;
  F3dVec3 mid = f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
  for (uint32_t i = 0; i < f->n; i++) mid = f3d_add(mid, f->p[i]);
  mid = f3d_scale(mid, F3D_R(1.0) / (f3d_real)f->n);
  const F3dVec3 u0 = f3d_sub(f->p[0], mid);
  const F3dVec3 u = f3d_scale(u0, F3D_R(1.0) / f3d_max(f3d_sqrt(f3d_dot(u0, u0)), F3D_R(1e-12)));
  const F3dVec3 v = f3d_cross(d, u);
  f3d_real key[F3D_FEATURE_POINTS];
  for (uint32_t i = 0; i < f->n; i++) {
    const F3dVec3 r = f3d_sub(f->p[i], mid);
    const f3d_real x = f3d_dot(r, u), y = f3d_dot(r, v);
    const f3d_real s = f3d_abs(x) + f3d_abs(y);
    const f3d_real t = s > F3D_R(0.0) ? y / s : F3D_R(0.0);
    key[i] = x >= F3D_R(0.0) ? t : F3D_R(2.0) - t;
  }
  for (uint32_t i = 1; i < f->n; i++) {
    const F3dVec3 pi = f->p[i];
    const f3d_real ki = key[i];
    uint32_t j = i;
    while (j > 0 && key[j - 1] > ki) {
      f->p[j] = f->p[j - 1];
      key[j] = key[j - 1];
      j--;
    }
    f->p[j] = pi;
    key[j] = ki;
  }
}

static void push_point(Feature *f, F3dVec3 p) {
  if (f->n < F3D_FEATURE_POINTS) f->p[f->n++] = p;
}

/* A disc of eight points round the shape's axis at height y. */
static void disc(Feature *f, f3d_real r, f3d_real y) {
  const f3d_real c = F3D_R(0.70710678118654752);
  const f3d_real xs[8] = {F3D_R(1.0), c, F3D_R(0.0), -c, F3D_R(-1.0), -c, F3D_R(0.0), c};
  const f3d_real zs[8] = {F3D_R(0.0), c, F3D_R(1.0), c, F3D_R(0.0), -c, F3D_R(-1.0), -c};
  for (int k = 0; k < 8; k++) push_point(f, f3d_v3(r * xs[k], y, r * zs[k]));
}

/* The shape's feature facing along [d] (world, not unit): its face if d is
 * within five degrees of square to one, its edge if within five degrees of
 * along one, else its furthest point; on the rounded surface, in the
 * world. */
static Feature feature(const F3dPlaced *p, F3dVec3 d) {
  Feature f;
  f.n = 0;
  const f3d_real dl = f3d_sqrt(f3d_dot(d, d));
  const F3dVec3 dn = f3d_scale(d, F3D_R(1.0) / f3d_max(dl, F3D_R(1e-18)));
  const F3dVec3 l = local_of(p, dn);
  const F3dVec3 s = p->size;
  switch (p->kind) {
    case F3D_SHAPE_CAPSULE:
      if (f3d_abs(l.y) < F3D_FACE_SIN) {
        push_point(&f, f3d_v3(F3D_R(0.0), -s.y, F3D_R(0.0)));
        push_point(&f, f3d_v3(F3D_R(0.0), s.y, F3D_R(0.0)));
      }
      break;
    case F3D_SHAPE_BOX: {
      const f3d_real c[3] = {l.x, l.y, l.z};
      const f3d_real h[3] = {s.x, s.y, s.z};
      int big = 0, small = 0;
      for (int k = 1; k < 3; k++) {
        if (f3d_abs(c[k]) > f3d_abs(c[big])) big = k;
        if (f3d_abs(c[k]) < f3d_abs(c[small])) small = k;
      }
      if (f3d_abs(c[big]) > F3D_FACE_COS) {
        const int u = (big + 1) % 3, v = (big + 2) % 3;
        const f3d_real su[4] = {F3D_R(1.0), F3D_R(-1.0), F3D_R(-1.0), F3D_R(1.0)};
        const f3d_real sv[4] = {F3D_R(1.0), F3D_R(1.0), F3D_R(-1.0), F3D_R(-1.0)};
        for (int k = 0; k < 4; k++) {
          f3d_real q[3];
          q[big] = c[big] >= F3D_R(0.0) ? h[big] : -h[big];
          q[u] = su[k] * h[u];
          q[v] = sv[k] * h[v];
          push_point(&f, f3d_v3(q[0], q[1], q[2]));
        }
      } else if (f3d_abs(c[small]) < F3D_FACE_SIN) {
        for (int k = 0; k < 2; k++) {
          f3d_real q[3];
          for (int a = 0; a < 3; a++) {
            q[a] = c[a] >= F3D_R(0.0) ? h[a] : -h[a];
          }
          q[small] = k ? h[small] : -h[small];
          push_point(&f, f3d_v3(q[0], q[1], q[2]));
        }
      }
      break;
    }
    case F3D_SHAPE_CYLINDER: {
      if (f3d_abs(l.y) > F3D_FACE_COS) {
        disc(&f, s.x, l.y >= F3D_R(0.0) ? s.y : -s.y);
      } else if (f3d_abs(l.y) < F3D_FACE_SIN) {
        const f3d_real flat = f3d_sqrt(l.x * l.x + l.z * l.z);
        const f3d_real k = s.x / flat;
        push_point(&f, f3d_v3(l.x * k, -s.y, l.z * k));
        push_point(&f, f3d_v3(l.x * k, s.y, l.z * k));
      }
      break;
    }
    case F3D_SHAPE_CONE: {
      const f3d_real big = s.y, r = s.x;
      if (l.y < -F3D_FACE_COS) {
        disc(&f, r, F3D_R(-0.25) * big);
        break;
      }
      const f3d_real flat = f3d_sqrt(l.x * l.x + l.z * l.z);
      if (flat <= F3D_R(1e-12)) break;
      const f3d_real ux = l.x / flat, uz = l.z / flat;
      const f3d_real slant = f3d_sqrt(big * big + r * r);
      const f3d_real along = (big * (l.x * ux + l.z * uz) + r * l.y) / slant;
      if (along > F3D_FACE_COS) {
        push_point(&f, f3d_v3(F3D_R(0.0), F3D_R(0.75) * big, F3D_R(0.0)));
        push_point(&f, f3d_v3(r * ux, F3D_R(-0.25) * big, r * uz));
      }
      break;
    }
    case F3D_SHAPE_TRIANGLE: {
      /* Its face within five degrees of square to d; else the edge whose
       * two ends reach as far along d, within five degrees; else a
       * corner. */
      const F3dVec3 a = hull_vertex(p, 0), b = hull_vertex(p, 1);
      const F3dVec3 c = hull_vertex(p, 2);
      F3dVec3 n = f3d_cross(f3d_sub(b, a), f3d_sub(c, a));
      const f3d_real len = f3d_sqrt(f3d_dot(n, n));
      if (!(len > F3D_R(0.0))) break;
      n = f3d_scale(n, F3D_R(1.0) / len);
      if (f3d_abs(f3d_dot(n, l)) > F3D_FACE_COS) {
        push_point(&f, a);
        push_point(&f, b);
        push_point(&f, c);
        break;
      }
      const F3dVec3 corner[3] = {a, b, c};
      for (int k = 0; k < 3; k++) {
        const F3dVec3 e = f3d_sub(corner[(k + 1) % 3], corner[k]);
        const f3d_real el = f3d_sqrt(f3d_dot(e, e));
        if (!(el > F3D_R(0.0))) continue;
        const f3d_real across = f3d_abs(f3d_dot(e, l)) / el;
        const f3d_real reach = f3d_dot(corner[k], l);
        const f3d_real other = f3d_dot(corner[(k + 2) % 3], l);
        if (across < F3D_FACE_SIN && reach >= other) {
          push_point(&f, corner[k]);
          push_point(&f, corner[(k + 1) % 3]);
          break;
        }
      }
      break;
    }
    case F3D_SHAPE_HULL: {
      if (p->hull == NULL) break;
      /* The triangle facing most along d; if square enough, every
       * triangle in its plane, which is the hull's face. */
      int best = -1;
      f3d_real most = F3D_R(-2.0), best_off = F3D_R(0.0);
      F3dVec3 best_n = f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
      const uint32_t nt = p->hull->triangle_count;
      for (uint32_t t = 0; t < nt; t++) {
        const F3dVec3 a = hull_vertex(p, p->triangles[t * 3u]);
        const F3dVec3 b = hull_vertex(p, p->triangles[t * 3u + 1u]);
        const F3dVec3 c = hull_vertex(p, p->triangles[t * 3u + 2u]);
        F3dVec3 n = f3d_cross(f3d_sub(b, a), f3d_sub(c, a));
        const f3d_real len = f3d_sqrt(f3d_dot(n, n));
        if (!(len > F3D_R(0.0))) continue;
        n = f3d_scale(n, F3D_R(1.0) / len);
        const f3d_real facing = f3d_dot(n, l);
        if (facing > most) {
          most = facing;
          best = (int)t;
          best_n = n;
          best_off = f3d_dot(n, a);
        }
      }
      if (best < 0 || most <= F3D_FACE_COS) break;
      const F3dVec3 extent = f3d_sub(p->hull->hi, p->hull->lo);
      const f3d_real tol =
          F3D_R(1e-4) * (F3D_R(1.0) + f3d_sqrt(f3d_dot(extent, extent)));
      uint32_t used[F3D_FEATURE_POINTS];
      uint32_t nused = 0;
      for (uint32_t t = 0; t < nt; t++) {
        const uint32_t *tri = &p->triangles[t * 3u];
        const F3dVec3 a = hull_vertex(p, tri[0]);
        const F3dVec3 b = hull_vertex(p, tri[1]);
        const F3dVec3 c = hull_vertex(p, tri[2]);
        F3dVec3 n = f3d_cross(f3d_sub(b, a), f3d_sub(c, a));
        const f3d_real len = f3d_sqrt(f3d_dot(n, n));
        if (!(len > F3D_R(0.0))) continue;
        n = f3d_scale(n, F3D_R(1.0) / len);
        if (f3d_dot(n, best_n) < F3D_R(0.9999) ||
            f3d_abs(f3d_dot(n, a) - best_off) > tol) {
          continue;
        }
        for (int k = 0; k < 3; k++) {
          int seen = 0;
          for (uint32_t q = 0; q < nused; q++) seen |= used[q] == tri[k];
          if (!seen && nused < F3D_FEATURE_POINTS) used[nused++] = tri[k];
        }
      }
      for (uint32_t q = 0; q < nused; q++) {
        push_point(&f, hull_vertex(p, used[q]));
      }
      break;
    }
    default:
      break;
  }
  if (f.n == 0) push_point(&f, core_support(p, l));
  const f3d_real r = rounding_of(p);
  for (uint32_t i = 0; i < f.n; i++) {
    f.p[i] = f3d_madd(world_of(p, f.p[i]), dn, r);
  }
  order(&f, dn);
  return f;
}

/* Keeps the part of [in] inside the convex polygon [ref], seen along n:
 * Sutherland–Hodgman against each of its edges, or for a segment, each end
 * cut back to the edge it crosses. */
static uint32_t clip_to(const F3dVec3 *in, uint32_t count, const Feature *ref,
                        F3dVec3 n, F3dVec3 *out) {
  enum { ROOM = 2 * F3D_FEATURE_POINTS + 8 };
  F3dVec3 a[ROOM], b[ROOM];
  uint32_t m = count < ROOM ? count : ROOM;
  for (uint32_t i = 0; i < m; i++) a[i] = in[i];
  F3dVec3 mid = f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
  for (uint32_t i = 0; i < ref->n; i++) mid = f3d_add(mid, ref->p[i]);
  mid = f3d_scale(mid, F3D_R(1.0) / (f3d_real)ref->n);
  for (uint32_t e = 0; e < ref->n && m > 0; e++) {
    const F3dVec3 r0 = ref->p[e], r1 = ref->p[(e + 1) % ref->n];
    F3dVec3 inward = f3d_cross(n, f3d_sub(r1, r0));
    if (f3d_dot(inward, f3d_sub(mid, r0)) < F3D_R(0.0)) {
      inward = f3d_scale(inward, F3D_R(-1.0));
    }
    if (m == 2) {
      const f3d_real dp = f3d_dot(inward, f3d_sub(a[0], r0));
      const f3d_real dq = f3d_dot(inward, f3d_sub(a[1], r0));
      if (dp < F3D_R(0.0) && dq < F3D_R(0.0)) {
        m = 0;
        break;
      }
      const F3dVec3 p = a[0], q = a[1];
      if (dp < F3D_R(0.0)) a[0] = f3d_madd(p, f3d_sub(q, p), dp / (dp - dq));
      if (dq < F3D_R(0.0)) a[1] = f3d_madd(p, f3d_sub(q, p), dp / (dp - dq));
      continue;
    }
    uint32_t w = 0;
    for (uint32_t i = 0; i < m; i++) {
      const F3dVec3 p = a[i], q = a[(i + 1) % m];
      const f3d_real dp = f3d_dot(inward, f3d_sub(p, r0));
      const f3d_real dq = f3d_dot(inward, f3d_sub(q, r0));
      if (dp >= F3D_R(0.0) && w < ROOM) b[w++] = p;
      if (((dp > F3D_R(0.0) && dq < F3D_R(0.0)) ||
           (dp < F3D_R(0.0) && dq > F3D_R(0.0))) &&
          w < ROOM) {
        b[w++] = f3d_madd(p, f3d_sub(q, p), dp / (dp - dq));
      }
    }
    m = w;
    for (uint32_t i = 0; i < m; i++) a[i] = b[i];
  }
  for (uint32_t i = 0; i < m; i++) out[i] = a[i];
  return m;
}

/* Of many points, the four that hold the face: the deepest, the furthest
 * from it, and the widest either side of the line between them. */
static void four(F3dVec3 *p, f3d_real *depth, uint32_t *ids, uint32_t *count,
                 F3dVec3 n) {
  if (*count <= F3D_MANIFOLD_POINTS) return;
  uint32_t pick[4] = {0, 0, 0, 0};
  for (uint32_t i = 1; i < *count; i++) {
    if (depth[i] > depth[pick[0]]) pick[0] = i;
  }
  f3d_real far = F3D_R(-1.0);
  for (uint32_t i = 0; i < *count; i++) {
    const F3dVec3 d = f3d_sub(p[i], p[pick[0]]);
    if (f3d_dot(d, d) > far) {
      far = f3d_dot(d, d);
      pick[1] = i;
    }
  }
  const F3dVec3 line = f3d_sub(p[pick[1]], p[pick[0]]);
  f3d_real most = F3D_R(0.0), least = F3D_R(0.0);
  pick[2] = pick[0];
  pick[3] = pick[1];
  for (uint32_t i = 0; i < *count; i++) {
    const f3d_real area =
        f3d_dot(f3d_cross(line, f3d_sub(p[i], p[pick[0]])), n);
    if (area > most) {
      most = area;
      pick[2] = i;
    }
    if (area < least) {
      least = area;
      pick[3] = i;
    }
  }
  F3dVec3 kp[4];
  f3d_real kd[4];
  uint32_t ki[4];
  uint32_t nk = 0;
  for (uint32_t k = 0; k < 4; k++) {
    int seen = 0;
    for (uint32_t j = 0; j < k; j++) seen |= pick[j] == pick[k];
    if (seen) continue;
    kp[nk] = p[pick[k]];
    kd[nk] = depth[pick[k]];
    ki[nk] = ids[pick[k]];
    nk++;
  }
  for (uint32_t k = 0; k < nk; k++) {
    p[k] = kp[k];
    depth[k] = kd[k];
    ids[k] = ki[k];
  }
  *count = nk;
}

void f3d_keep_four(F3dVec3 *p, f3d_real *depth, uint32_t *ids,
                   uint32_t *count, F3dVec3 n) {
  four(p, depth, ids, count, n);
}

static void emit(F3dManifold *out, F3dVec3 point, f3d_real depth, uint32_t id) {
  if (out->count >= F3D_MANIFOLD_POINTS) return;
  F3dContactPoint *c = &out->points[out->count++];
  c->point = point;
  c->depth = depth;
  c->id = id;
}

/* A face's own plane: its normal by Newell's method, turned to face along
 * [toward], and its offset. Depth is measured from this, not from the
 * face's lowest corner along the contact normal: a floor twenty metres
 * across under a normal a tenth of a degree off would put its far corner
 * five centimetres low. */
static F3dVec3 face_normal(const Feature *f, F3dVec3 toward, f3d_real *offset) {
  F3dVec3 n = f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
  F3dVec3 mid = n;
  for (uint32_t i = 0; i < f->n; i++) {
    const F3dVec3 p = f->p[i], q = f->p[(i + 1) % f->n];
    n.x += (p.y - q.y) * (p.z + q.z);
    n.y += (p.z - q.z) * (p.x + q.x);
    n.z += (p.x - q.x) * (p.y + q.y);
    mid = f3d_add(mid, p);
  }
  const f3d_real len = f3d_sqrt(f3d_dot(n, n));
  n = len > F3D_R(0.0) ? f3d_scale(n, F3D_R(1.0) / len) : toward;
  if (f3d_dot(n, toward) < F3D_R(0.0)) n = f3d_scale(n, F3D_R(-1.0));
  mid = f3d_scale(mid, F3D_R(1.0) / (f3d_real)f->n);
  *offset = f3d_dot(n, mid);
  return n;
}

/* The manifold from the two features facing along n (out of b into a).
 * Returns how many points it found; nought leaves the single point to the
 * caller. */
static uint32_t from_features(const F3dPlaced *a, const F3dPlaced *b,
                              F3dVec3 n, f3d_real margin, F3dManifold *out) {
  const Feature fa = feature(a, f3d_scale(n, F3D_R(-1.0)));
  const Feature fb = feature(b, n);
  F3dVec3 pts[2 * F3D_FEATURE_POINTS + 8];
  f3d_real depth[2 * F3D_FEATURE_POINTS + 8];
  uint32_t count = 0;
  if (fa.n >= 3 && fb.n >= 2) {
    /* b's face or edge clipped to a's face; deep as far as b reaches past
     * a's plane. a's face looks towards b, against n. */
    f3d_real plane;
    const F3dVec3 nf = face_normal(&fa, f3d_scale(n, F3D_R(-1.0)), &plane);
    count = clip_to(fb.p, fb.n, &fa, n, pts);
    uint32_t kept = 0;
    for (uint32_t i = 0; i < count; i++) {
      const f3d_real d = plane - f3d_dot(nf, pts[i]);
      if (d <= -margin) continue;
      pts[kept] = f3d_madd(pts[i], n, F3D_R(-0.5) * d);
      depth[kept++] = d;
    }
    count = kept;
  } else if (fb.n >= 3 && fa.n == 2) {
    f3d_real plane;
    const F3dVec3 nf = face_normal(&fb, n, &plane);
    count = clip_to(fa.p, fa.n, &fb, n, pts);
    uint32_t kept = 0;
    for (uint32_t i = 0; i < count; i++) {
      const f3d_real d = plane - f3d_dot(nf, pts[i]);
      if (d <= -margin) continue;
      pts[kept] = f3d_madd(pts[i], n, F3D_R(0.5) * d);
      depth[kept++] = d;
    }
    count = kept;
  } else if (fa.n == 2 && fb.n == 2) {
    /* Two edges lying along each other keep their overlap. */
    const F3dVec3 da = f3d_sub(fa.p[1], fa.p[0]), db = f3d_sub(fb.p[1], fb.p[0]);
    const f3d_real la = f3d_dot(da, da), lb = f3d_dot(db, db);
    const F3dVec3 x = f3d_cross(da, db);
    if (la > F3D_R(1e-12) && lb > F3D_R(1e-12) &&
        f3d_dot(x, x) <= F3D_R(1e-4) * la * lb) {
      f3d_real lo = f3d_dot(f3d_sub(fb.p[0], fa.p[0]), da) / la;
      f3d_real hi = f3d_dot(f3d_sub(fb.p[1], fa.p[0]), da) / la;
      if (lo > hi) {
        const f3d_real t = lo;
        lo = hi;
        hi = t;
      }
      lo = f3d_max(lo, F3D_R(0.0));
      hi = f3d_min(hi, F3D_R(1.0));
      if (hi - lo > F3D_R(1e-3)) {
        const f3d_real ends[2] = {lo, hi};
        for (int k = 0; k < 2; k++) {
          const F3dVec3 pa = f3d_madd(fa.p[0], da, ends[k]);
          const f3d_real t = f3d_clamp(
              f3d_dot(f3d_sub(pa, fb.p[0]), db) / lb, F3D_R(0.0), F3D_R(1.0));
          const F3dVec3 pb = f3d_madd(fb.p[0], db, t);
          const f3d_real d = f3d_dot(n, f3d_sub(pb, pa));
          if (d <= -margin) continue;
          pts[count] = f3d_scale(f3d_add(pa, pb), F3D_R(0.5));
          depth[count++] = d;
        }
      }
    }
  }
  uint32_t ids[2 * F3D_FEATURE_POINTS + 8];
  for (uint32_t i = 0; i < count; i++) ids[i] = 0x200u + i;
  four(pts, depth, ids, &count, n);
  for (uint32_t i = 0; i < count; i++) emit(out, pts[i], depth[i], ids[i]);
  return count;
}

uint32_t f3d_collide_convex(const F3dPlaced *a, const F3dPlaced *b,
                            f3d_real margin, F3dManifold *out) {
  out->count = 0;
  const f3d_real ra = rounding_of(a), rb = rounding_of(b);
  /* GJK on the cores. */
  Simplex s;
  F3dVec3 start = f3d_sub(a->at, b->at);
  if (f3d_dot(start, start) <= F3D_R(1e-18)) {
    start = f3d_v3(F3D_R(1.0), F3D_R(0.0), F3D_R(0.0));
  }
  s.v[0] = support(a, b, start);
  s.l[0] = F3D_R(1.0);
  s.n = 1;
  F3dVec3 v = s.v[0].w;
  f3d_real size = f3d_dot(v, v);
  int overlap = 0;
  for (int iteration = 0; iteration < 64; iteration++) {
    const f3d_real vv = f3d_dot(v, v);
    /* Touching, by the difference's own scale: van den Bergen's test. */
    if (vv <= F3D_GJK_TOUCH * size) {
      overlap = 1;
      break;
    }
    const Vertex w = support(a, b, f3d_scale(v, F3D_R(-1.0)));
    size = f3d_max(size, f3d_dot(w.w, w.w));
    if (vv - f3d_dot(v, w.w) <= F3D_GJK_RELATIVE * vv) break;
    int repeated = 0;
    for (uint32_t i = 0; i < s.n; i++) {
      const F3dVec3 d = f3d_sub(w.w, s.v[i].w);
      repeated |= f3d_dot(d, d) <= F3D_R(1e-18);
    }
    if (repeated) break;
    Simplex next = s;
    next.v[next.n++] = w;
    int inside = 0;
    const F3dVec3 nv = closest(&next, &inside);
    if (inside) {
      s = next;
      overlap = 1;
      break;
    }
    /* No nearer: what there is, is the answer. */
    if (f3d_dot(nv, nv) >= vv) break;
    s = next;
    v = nv;
  }
  F3dVec3 n, pa, pb;
  f3d_real depth;
  if (!overlap) {
    pa = f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
    pb = pa;
    for (uint32_t i = 0; i < s.n; i++) {
      pa = f3d_madd(pa, s.v[i].a, s.l[i]);
      pb = f3d_madd(pb, s.v[i].b, s.l[i]);
    }
    const F3dVec3 d = f3d_sub(pa, pb);
    const f3d_real distance = f3d_sqrt(f3d_dot(d, d));
    depth = ra + rb - distance;
    if (depth <= -margin) return 0;
    if (!(distance > F3D_R(0.0))) return 0;
    n = f3d_scale(d, F3D_R(1.0) / distance);
  } else {
    F3dVec3 face;
    f3d_real into;
    if (!blow_up(a, b, &s) || !expand(a, b, &s, &face, &into, &pa, &pb)) {
      return 0;
    }
    /* Moving a by −face·into takes the origin out of the difference: a
     * goes out along −face. */
    n = f3d_scale(face, F3D_R(-1.0));
    depth = into + ra + rb;
  }
  out->normal = n;
  if (from_features(a, b, n, margin, out) > 0) return out->count;
  const F3dVec3 on_a = f3d_madd(pa, n, -ra);
  const F3dVec3 on_b = f3d_madd(pb, n, rb);
  emit(out, f3d_scale(f3d_add(on_a, on_b), F3D_R(0.5)), depth, 0x100u);
  return out->count;
}

/* -------------------------------------------------------------- meshes */

/* The point of triangle a, b, c nearest [p]: Ericson's
 * ClosestPtPointTriangle. */
static F3dVec3 nearest_on_triangle(F3dVec3 p, F3dVec3 a, F3dVec3 b, F3dVec3 c) {
  const F3dVec3 ab = f3d_sub(b, a), ac = f3d_sub(c, a), ap = f3d_sub(p, a);
  const f3d_real d1 = f3d_dot(ab, ap), d2 = f3d_dot(ac, ap);
  if (d1 <= F3D_R(0.0) && d2 <= F3D_R(0.0)) return a;
  const F3dVec3 bp = f3d_sub(p, b);
  const f3d_real d3 = f3d_dot(ab, bp), d4 = f3d_dot(ac, bp);
  if (d3 >= F3D_R(0.0) && d4 <= d3) return b;
  const f3d_real vc = d1 * d4 - d3 * d2;
  if (vc <= F3D_R(0.0) && d1 >= F3D_R(0.0) && d3 <= F3D_R(0.0)) {
    return f3d_madd(a, ab, d1 / (d1 - d3));
  }
  const F3dVec3 cp = f3d_sub(p, c);
  const f3d_real d5 = f3d_dot(ab, cp), d6 = f3d_dot(ac, cp);
  if (d6 >= F3D_R(0.0) && d5 <= d6) return c;
  const f3d_real vb = d5 * d2 - d1 * d6;
  if (vb <= F3D_R(0.0) && d2 >= F3D_R(0.0) && d6 <= F3D_R(0.0)) {
    return f3d_madd(a, ac, d2 / (d2 - d6));
  }
  const f3d_real va = d3 * d6 - d5 * d4;
  if (va <= F3D_R(0.0) && d4 - d3 >= F3D_R(0.0) && d5 - d6 >= F3D_R(0.0)) {
    return f3d_madd(b, f3d_sub(c, b), (d4 - d3) / ((d4 - d3) + (d5 - d6)));
  }
  const f3d_real denom = F3D_R(1.0) / (va + vb + vc);
  return f3d_add(a, f3d_add(f3d_scale(ab, vb * denom), f3d_scale(ac, vc * denom)));
}

#define F3D_ROUND_CANDIDATES 8

/* A ball or a capsule against one triangle: its axis's ends, and the
 * points of its axis nearest each edge, each against the triangle as a
 * ball — so a capsule lying on a triangle rests on both ends. The deepest
 * gives the normal; the rest that agree with it are kept. */
static uint32_t round_triangle(const F3dPlaced *body, F3dVec3 a, F3dVec3 b,
                               F3dVec3 c, F3dVec3 face, f3d_real margin,
                               F3dManifold *out) {
  F3dVec3 p0 = body->at, p1 = body->at;
  if (body->kind == F3D_SHAPE_CAPSULE) {
    const F3dVec3 half = f3d_scale(body->axes.c[1], body->size.y);
    p0 = f3d_sub(body->at, half);
    p1 = f3d_add(body->at, half);
  }
  const f3d_real r = rounding_of(body);
  F3dVec3 on[F3D_ROUND_CANDIDATES];
  uint32_t n_on = 0;
  on[n_on++] = p0;
  if (body->kind == F3D_SHAPE_CAPSULE) {
    on[n_on++] = p1;
    const F3dVec3 corner[3] = {a, b, c};
    for (int k = 0; k < 3; k++) {
      f3d_real s, t;
      f3d_nearest_of_segments(p0, p1, corner[k], corner[(k + 1) % 3], &s, &t);
      on[n_on++] = f3d_madd(p0, f3d_sub(p1, p0), s);
    }
    /* Through the triangle's plane, the crossing too. */
    const f3d_real d0 = f3d_dot(face, f3d_sub(p0, a));
    const f3d_real d1 = f3d_dot(face, f3d_sub(p1, a));
    if ((d0 < F3D_R(0.0)) != (d1 < F3D_R(0.0))) {
      on[n_on++] = f3d_madd(p0, f3d_sub(p1, p0), d0 / (d0 - d1));
    }
  }
  F3dVec3 pts[F3D_ROUND_CANDIDATES], normals[F3D_ROUND_CANDIDATES];
  f3d_real depth[F3D_ROUND_CANDIDATES];
  uint32_t found = 0;
  for (uint32_t i = 0; i < n_on; i++) {
    const F3dVec3 q = on[i];
    const F3dVec3 near = nearest_on_triangle(q, a, b, c);
    const F3dVec3 d = f3d_sub(q, near);
    const f3d_real dist = f3d_sqrt(f3d_dot(d, d));
    /* On or behind the plane: out along the face, as deep as it is in. */
    const f3d_real above = f3d_dot(face, f3d_sub(q, a));
    F3dVec3 nn;
    f3d_real dd;
    if (dist <= F3D_R(1e-9) || above < F3D_R(0.0)) {
      nn = face;
      dd = r - above;
    } else {
      nn = f3d_scale(d, F3D_R(1.0) / dist);
      dd = r - dist;
    }
    if (dd <= -margin) continue;
    int same = 0;
    for (uint32_t k = 0; k < found; k++) {
      const F3dVec3 e = f3d_sub(pts[k], q);
      same |= f3d_dot(e, e) <= F3D_R(1e-12);
    }
    if (same) continue;
    pts[found] = q;
    normals[found] = nn;
    depth[found] = dd;
    found++;
  }
  if (found == 0) return 0;
  uint32_t best = 0;
  for (uint32_t i = 1; i < found; i++) {
    if (depth[i] > depth[best]) best = i;
  }
  out->normal = normals[best];
  for (uint32_t i = 0; i < found; i++) {
    if (f3d_dot(normals[i], normals[best]) < F3D_R(0.95)) continue;
    const F3dVec3 surface = f3d_madd(pts[i], normals[i], -r);
    emit(out, f3d_madd(surface, normals[i], F3D_R(0.5) * depth[i]), depth[i], i);
  }
  return out->count;
}

/* Gathers the triangles a query finds. */
#define F3D_MESH_NEAR 512

typedef struct NearTriangles {
  uint32_t t[F3D_MESH_NEAR];
  uint32_t n;
  const F3dTree *tree;
} NearTriangles;

static int near_triangle(void *context, int32_t leaf) {
  NearTriangles *g = (NearTriangles *)context;
  if (g->n < F3D_MESH_NEAR) g->t[g->n++] = g->tree->nodes[leaf].slot;
  return g->n < F3D_MESH_NEAR;
}

uint32_t f3d_collide_mesh(const F3dPlaced *mesh, const F3dPlaced *body,
                          f3d_real margin, F3dManifold *out) {
  out->count = 0;
  if (mesh->mesh == NULL || mesh->mesh_tree == NULL) return 0;
  const f3d_real r = rounding_of(body);
  /* The body's box in the mesh's frame, by its support along each of the
   * mesh's axes. */
  F3dBox box;
  f3d_real lo[3], hi[3];
  for (int k = 0; k < 3; k++) {
    const F3dVec3 axis = mesh->axes.c[k];
    const F3dVec3 up = world_of(body, core_support(body, local_of(body, axis)));
    const F3dVec3 down = world_of(
        body, core_support(body, local_of(body, f3d_scale(axis, F3D_R(-1.0)))));
    hi[k] = f3d_dot(axis, f3d_sub(up, mesh->at)) + r + margin;
    lo[k] = f3d_dot(axis, f3d_sub(down, mesh->at)) - r - margin;
  }
  box.lo = f3d_v3(lo[0], lo[1], lo[2]);
  box.hi = f3d_v3(hi[0], hi[1], hi[2]);
  NearTriangles near;
  near.n = 0;
  near.tree = mesh->mesh_tree;
  f3d_tree_query(mesh->mesh_tree, box, near_triangle, &near);
  /* In index order, whatever order the tree gave them: the answer must not
   * depend on the tree's shape. */
  for (uint32_t i = 1; i < near.n; i++) {
    const uint32_t v = near.t[i];
    uint32_t j = i;
    while (j > 0 && near.t[j - 1] > v) {
      near.t[j] = near.t[j - 1];
      j--;
    }
    near.t[j] = v;
  }
  enum { ROOM = 64 };
  F3dVec3 pts[ROOM], normals[ROOM];
  f3d_real depth[ROOM];
  uint32_t ids[ROOM];
  uint32_t found = 0;
  for (uint32_t q = 0; q < near.n; q++) {
    const uint32_t t = near.t[q];
    const uint32_t *tri = &mesh->triangles[t * 3u];
    f3d_real corners[9];
    F3dVec3 v[3];
    for (int k = 0; k < 3; k++) {
      v[k] = world_of(mesh, hull_vertex(mesh, tri[k]));
      corners[k * 3] = v[k].x;
      corners[k * 3 + 1] = v[k].y;
      corners[k * 3 + 2] = v[k].z;
    }
    F3dVec3 face = f3d_cross(f3d_sub(v[1], v[0]), f3d_sub(v[2], v[0]));
    const f3d_real len = f3d_sqrt(f3d_dot(face, face));
    if (!(len > F3D_R(0.0))) continue;
    face = f3d_scale(face, F3D_R(1.0) / len);
    /* One sided: a body whose centre is behind the triangle does not see
     * it. */
    if (f3d_dot(face, f3d_sub(body->at, v[0])) < F3D_R(0.0)) continue;
    F3dManifold tm;
    f3d_zero(&tm, sizeof tm);
    uint32_t n;
    if (body->kind == F3D_SHAPE_SPHERE || body->kind == F3D_SHAPE_CAPSULE) {
      n = round_triangle(body, v[0], v[1], v[2], face, margin, &tm);
    } else {
      F3dPlaced p;
      f3d_zero(&p, sizeof p);
      p.kind = F3D_SHAPE_TRIANGLE;
      p.axes.c[0] = f3d_v3(F3D_R(1.0), F3D_R(0.0), F3D_R(0.0));
      p.axes.c[1] = f3d_v3(F3D_R(0.0), F3D_R(1.0), F3D_R(0.0));
      p.axes.c[2] = f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(1.0));
      p.vertices = corners;
      n = f3d_collide_convex(body, &p, margin, &tm);
    }
    if (n == 0) continue;
    /* An edge or corner contact on an internal edge is the face's: the
     * body is on the same surface across the seam, and the edge's normal
     * would trip it. A contact whose normal is not the face's is taken back
     * to the face only when every edge it lies on is internal. */
    if (f3d_dot(tm.normal, face) < F3D_R(0.9999) && tm.count == 1) {
      const F3dVec3 x = tm.points[0].point;
      const F3dVec3 e0 = f3d_sub(v[1], v[0]), e1 = f3d_sub(v[2], v[0]);
      const F3dVec3 e2 = f3d_sub(x, v[0]);
      const f3d_real d00 = f3d_dot(e0, e0), d01 = f3d_dot(e0, e1);
      const f3d_real d11 = f3d_dot(e1, e1), d20 = f3d_dot(e2, e0);
      const f3d_real d21 = f3d_dot(e2, e1);
      const f3d_real den = d00 * d11 - d01 * d01;
      const f3d_real wb = den > F3D_R(0.0) ? (d11 * d20 - d01 * d21) / den : F3D_R(0.0);
      const f3d_real wc = den > F3D_R(0.0) ? (d00 * d21 - d01 * d20) / den : F3D_R(0.0);
      const f3d_real wa = F3D_R(1.0) - wb - wc;
      const f3d_real tol = F3D_R(1e-3);
      const uint8_t flags = mesh->edge_flags[t];
      /* Edge k runs from corner k to the next; it is the one opposite the
       * corner whose weight is nought. */
      int internal = 1;
      if (wc <= tol && !(flags & 1u)) internal = 0;
      if (wa <= tol && !(flags & 2u)) internal = 0;
      if (wb <= tol && !(flags & 4u)) internal = 0;
      if (internal) {
        const F3dVec3 s = world_of(
            body, core_support(body, local_of(body, f3d_scale(face, F3D_R(-1.0)))));
        const f3d_real d = f3d_dot(face, v[0]) - f3d_dot(face, s) + r;
        if (d <= -margin) continue;
        tm.normal = face;
        const F3dVec3 deepest = f3d_madd(s, face, -r);
        tm.points[0].point = f3d_madd(deepest, face, F3D_R(0.5) * d);
        tm.points[0].depth = d;
      }
    }
    for (uint32_t k = 0; k < tm.count && found < ROOM; k++) {
      pts[found] = tm.points[k].point;
      normals[found] = tm.normal;
      depth[found] = tm.points[k].depth;
      ids[found] = (t << 4) | (tm.points[k].id & 15u);
      found++;
    }
  }
  if (found == 0) return 0;
  /* One manifold: the deepest point's normal, and every point whose
   * triangle agrees with it to eighteen degrees. */
  uint32_t best = 0;
  for (uint32_t i = 1; i < found; i++) {
    if (depth[i] > depth[best]) best = i;
  }
  const F3dVec3 n = normals[best];
  uint32_t kept = 0;
  for (uint32_t i = 0; i < found; i++) {
    if (f3d_dot(normals[i], n) < F3D_R(0.95)) continue;
    pts[kept] = pts[i];
    depth[kept] = depth[i];
    ids[kept] = ids[i];
    kept++;
  }
  four(pts, depth, ids, &kept, n);
  out->normal = n;
  for (uint32_t i = 0; i < kept; i++) emit(out, pts[i], depth[i], ids[i]);
  return out->count;
}
