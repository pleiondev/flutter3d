/*
 * Convex hulls — P9, phase 5: built from points, weighed, and held by the
 * world for bodies to be shaped as.
 *
 * The hull is built incrementally: a tetrahedron of four far-apart points,
 * then each further point in the order given, replacing the faces it sees
 * with a fan from it to the horizon round them. In doubles, whatever the
 * core's reals, since a hull is built once and a sliver face from rounding
 * would be there for good. The order is the caller's, so the same points
 * make the same hull everywhere.
 *
 * Its mass is the solid's, from the tetrahedra its faces make with a point
 * inside: volume, centre and the covariance of each, summed, gives the
 * inertia tensor about the centre of mass (Blow and Binstock, "How to find
 * the inertia tensor (or other mass properties) of a 3D solid body
 * represented by a triangle mesh", 2004). The hull is moved so that centre
 * is the body's origin: a body turns about its centre of mass, and every
 * other shape's is at its origin already.
 */
#include "f3d_internal.h"

#define F3D_HULL_POINTS 4096u

typedef struct HullFace {
  uint32_t a, b, c;
  double n[3];
  double d;
} HullFace;

static void sub3(const double *a, const double *b, double *o) {
  o[0] = a[0] - b[0];
  o[1] = a[1] - b[1];
  o[2] = a[2] - b[2];
}

static void cross3(const double *a, const double *b, double *o) {
  o[0] = a[1] * b[2] - a[2] * b[1];
  o[1] = a[2] * b[0] - a[0] * b[2];
  o[2] = a[0] * b[1] - a[1] * b[0];
}

static double dot3(const double *a, const double *b) {
  return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

static double sqrt_d(double x) {
#if defined(_MSC_VER)
  return sqrt(x);
#else
  return __builtin_sqrt(x);
#endif
}

/* The face a, b, c with its outward normal; 0 when it has no area. */
static int make_face(const double *p, uint32_t a, uint32_t b, uint32_t c,
                     HullFace *f) {
  double e1[3], e2[3], n[3];
  sub3(&p[b * 3u], &p[a * 3u], e1);
  sub3(&p[c * 3u], &p[a * 3u], e2);
  cross3(e1, e2, n);
  const double len = sqrt_d(dot3(n, n));
  f->a = a;
  f->b = b;
  f->c = c;
  if (!(len > 0.0)) {
    f->n[0] = f->n[1] = f->n[2] = 0.0;
    f->d = 0.0;
    return 0;
  }
  f->n[0] = n[0] / len;
  f->n[1] = n[1] / len;
  f->n[2] = n[2] / len;
  f->d = dot3(f->n, &p[a * 3u]);
  return 1;
}

uint32_t f3d_world_create_hull(F3dWorld *world, const f3d_real *points,
                               uint32_t count) {
  if (points == NULL || count < 4u || count > F3D_HULL_POINTS) return 0;
  for (uint32_t i = 0; i < count * 3u; i++) {
    if (!f3d_finite(points[i])) return 0;
  }
  double *p = (double *)f3d_alloc((size_t)count * 3u * sizeof(double));
  /* Room for every face a hull of [count] points can have, twice over for
   * the ones a step replaces before they are compacted. */
  const uint32_t room = 4u * count + 8u;
  HullFace *faces = (HullFace *)f3d_alloc((size_t)room * sizeof(HullFace));
  HullFace *spare = (HullFace *)f3d_alloc((size_t)room * sizeof(HullFace));
  uint32_t *edges = (uint32_t *)f3d_alloc((size_t)room * 6u * sizeof(uint32_t));
  uint32_t *remap = (uint32_t *)f3d_alloc((size_t)count * sizeof(uint32_t));
  uint32_t result = 0;
  if (p == NULL || faces == NULL || spare == NULL || edges == NULL ||
      remap == NULL) {
    goto done;
  }
  for (uint32_t i = 0; i < count * 3u; i++) p[i] = (double)points[i];
  double lo[3] = {p[0], p[1], p[2]}, hi[3] = {p[0], p[1], p[2]};
  for (uint32_t i = 1; i < count; i++) {
    for (int k = 0; k < 3; k++) {
      if (p[i * 3u + k] < lo[k]) lo[k] = p[i * 3u + k];
      if (p[i * 3u + k] > hi[k]) hi[k] = p[i * 3u + k];
    }
  }
  double span[3];
  sub3(hi, lo, span);
  const double scale = sqrt_d(dot3(span, span));
  if (!(scale > 0.0)) goto done;
  const double eps = 1e-9 * scale;
  /* Four points far apart: the lowest in x, the furthest from it, the
   * furthest from their line, the furthest from their plane. */
  uint32_t i0 = 0;
  for (uint32_t i = 1; i < count; i++) {
    if (p[i * 3u] < p[i0 * 3u]) i0 = i;
  }
  uint32_t i1 = i0;
  double best = 0.0;
  for (uint32_t i = 0; i < count; i++) {
    double d[3];
    sub3(&p[i * 3u], &p[i0 * 3u], d);
    if (dot3(d, d) > best) {
      best = dot3(d, d);
      i1 = i;
    }
  }
  if (!(best > eps * eps)) goto done;
  uint32_t i2 = i0;
  best = 0.0;
  double line[3];
  sub3(&p[i1 * 3u], &p[i0 * 3u], line);
  for (uint32_t i = 0; i < count; i++) {
    double d[3], x[3];
    sub3(&p[i * 3u], &p[i0 * 3u], d);
    cross3(line, d, x);
    if (dot3(x, x) > best) {
      best = dot3(x, x);
      i2 = i;
    }
  }
  if (!(best > eps * eps * dot3(line, line))) goto done;
  HullFace base;
  make_face(p, i0, i1, i2, &base);
  uint32_t i3 = i0;
  best = 0.0;
  for (uint32_t i = 0; i < count; i++) {
    const double d = dot3(base.n, &p[i * 3u]) - base.d;
    if ((d < 0.0 ? -d : d) > best) {
      best = d < 0.0 ? -d : d;
      i3 = i;
    }
  }
  if (!(best > eps)) goto done;
  /* The tetrahedron, its faces turned outward: away from the fourth
   * point. */
  uint32_t nf = 0;
  {
    const uint32_t t[4][4] = {
        {i0, i1, i2, i3}, {i0, i3, i1, i2}, {i0, i2, i3, i1}, {i1, i3, i2, i0}};
    for (int f = 0; f < 4; f++) {
      HullFace face;
      make_face(p, t[f][0], t[f][1], t[f][2], &face);
      if (dot3(face.n, &p[t[f][3] * 3u]) - face.d > 0.0) {
        make_face(p, t[f][1], t[f][0], t[f][2], &face);
      }
      faces[nf++] = face;
    }
  }
  for (uint32_t k = 0; k < count; k++) {
    if (k == i0 || k == i1 || k == i2 || k == i3) continue;
    const double *q = &p[k * 3u];
    /* The faces it sees, and the horizon round them: each of their edges
     * whose reverse is not also an edge of one it sees. */
    uint32_t ne = 0, kept = 0;
    for (uint32_t f = 0; f < nf; f++) {
      if (dot3(faces[f].n, q) - faces[f].d <= eps) {
        spare[kept++] = faces[f];
        continue;
      }
      const uint32_t e[3][2] = {{faces[f].a, faces[f].b},
                                {faces[f].b, faces[f].c},
                                {faces[f].c, faces[f].a}};
      for (int j = 0; j < 3; j++) {
        int shared = -1;
        for (uint32_t m = 0; m < ne; m++) {
          if (edges[m * 2u] == e[j][1] && edges[m * 2u + 1u] == e[j][0]) {
            shared = (int)m;
          }
        }
        if (shared >= 0) {
          edges[(uint32_t)shared * 2u] = edges[(ne - 1u) * 2u];
          edges[(uint32_t)shared * 2u + 1u] = edges[(ne - 1u) * 2u + 1u];
          ne--;
        } else {
          edges[ne * 2u] = e[j][0];
          edges[ne * 2u + 1u] = e[j][1];
          ne++;
        }
      }
    }
    if (kept == nf) continue; /* Inside: it sees nothing. */
    for (uint32_t m = 0; m < ne && kept < room; m++) {
      HullFace face;
      if (make_face(p, edges[m * 2u], edges[m * 2u + 1u], k, &face)) {
        spare[kept++] = face;
      }
    }
    HullFace *swap = faces;
    faces = spare;
    spare = swap;
    nf = kept;
  }
  /* The corners, numbered in the order the points came. */
  for (uint32_t i = 0; i < count; i++) remap[i] = UINT32_MAX;
  for (uint32_t f = 0; f < nf; f++) {
    remap[faces[f].a] = remap[faces[f].b] = remap[faces[f].c] = 0;
  }
  uint32_t nv = 0;
  for (uint32_t i = 0; i < count; i++) {
    if (remap[i] != UINT32_MAX) remap[i] = nv++;
  }
  /* The solid's mass, from the tetrahedra its faces make with the mean of
   * its corners. */
  double o[3] = {0.0, 0.0, 0.0};
  for (uint32_t i = 0; i < count; i++) {
    if (remap[i] == UINT32_MAX) continue;
    for (int k = 0; k < 3; k++) o[k] += p[i * 3u + k];
  }
  for (int k = 0; k < 3; k++) o[k] /= (double)nv;
  double volume = 0.0, surface = 0.0, centre[3] = {0.0, 0.0, 0.0};
  double cov[3][3] = {{0.0, 0.0, 0.0}, {0.0, 0.0, 0.0}, {0.0, 0.0, 0.0}};
  for (uint32_t f = 0; f < nf; f++) {
    double a[3], b[3], c[3], x[3], e1[3], e2[3];
    sub3(&p[faces[f].a * 3u], o, a);
    sub3(&p[faces[f].b * 3u], o, b);
    sub3(&p[faces[f].c * 3u], o, c);
    cross3(b, c, x);
    const double v = dot3(a, x) / 6.0;
    sub3(b, a, e1);
    sub3(c, a, e2);
    cross3(e1, e2, x);
    surface += 0.5 * sqrt_d(dot3(x, x));
    volume += v;
    const double s[3] = {a[0] + b[0] + c[0], a[1] + b[1] + c[1],
                         a[2] + b[2] + c[2]};
    for (int i = 0; i < 3; i++) {
      centre[i] += v * s[i] / 4.0;
      for (int j = 0; j < 3; j++) {
        cov[i][j] += v / 20.0 *
                     (a[i] * a[j] + b[i] * b[j] + c[i] * c[j] + s[i] * s[j]);
      }
    }
  }
  if (!(volume > 0.0)) goto done;
  for (int i = 0; i < 3; i++) centre[i] /= volume;
  /* The covariance about the centre of mass, then the inertia tensor of a
   * solid of unit density, then of a kilogram. */
  for (int i = 0; i < 3; i++) {
    for (int j = 0; j < 3; j++) cov[i][j] -= volume * centre[i] * centre[j];
  }
  const double trace = cov[0][0] + cov[1][1] + cov[2][2];
  F3dSym3 unit;
  unit.xx = (f3d_real)((trace - cov[0][0]) / volume);
  unit.yy = (f3d_real)((trace - cov[1][1]) / volume);
  unit.zz = (f3d_real)((trace - cov[2][2]) / volume);
  unit.xy = (f3d_real)(-cov[0][1] / volume);
  unit.xz = (f3d_real)(-cov[0][2] / volume);
  unit.yz = (f3d_real)(-cov[1][2] / volume);
  const double offset[3] = {o[0] + centre[0], o[1] + centre[1],
                            o[2] + centre[2]};
  /* Into the world's arrays, every allocation made before any is kept. */
  const uint32_t first_vertex = world->s.hull_vertex_count;
  const uint32_t first_triangle = world->s.hull_triangle_count;
  f3d_real *vertices = (f3d_real *)f3d_realloc(
      world->hull_vertices,
      ((size_t)first_vertex + nv) * 3u * sizeof(f3d_real));
  if (vertices == NULL) goto done;
  world->hull_vertices = vertices;
  uint32_t *triangles = (uint32_t *)f3d_realloc(
      world->hull_triangles,
      ((size_t)first_triangle + nf) * 3u * sizeof(uint32_t));
  if (triangles == NULL) goto done;
  world->hull_triangles = triangles;
  F3dHull *hulls = (F3dHull *)f3d_realloc(
      world->hulls, ((size_t)world->s.hull_count + 1u) * sizeof(F3dHull));
  if (hulls == NULL) goto done;
  world->hulls = hulls;
  F3dHull h;
  f3d_zero(&h, sizeof h);
  h.first_vertex = first_vertex;
  h.vertex_count = nv;
  h.first_triangle = first_triangle;
  h.triangle_count = nf;
  h.offset = f3d_v3((f3d_real)offset[0], (f3d_real)offset[1],
                    (f3d_real)offset[2]);
  h.volume = (f3d_real)volume;
  h.surface = (f3d_real)surface;
  h.unit_inertia = unit;
  int first = 1;
  for (uint32_t i = 0; i < count; i++) {
    if (remap[i] == UINT32_MAX) continue;
    const F3dVec3 v = f3d_v3((f3d_real)(p[i * 3u] - offset[0]),
                             (f3d_real)(p[i * 3u + 1u] - offset[1]),
                             (f3d_real)(p[i * 3u + 2u] - offset[2]));
    f3d_real *out = &vertices[((size_t)first_vertex + remap[i]) * 3u];
    out[0] = v.x;
    out[1] = v.y;
    out[2] = v.z;
    if (first) {
      h.lo = h.hi = v;
      first = 0;
    } else {
      h.lo = f3d_v3(f3d_min(h.lo.x, v.x), f3d_min(h.lo.y, v.y),
                    f3d_min(h.lo.z, v.z));
      h.hi = f3d_v3(f3d_max(h.hi.x, v.x), f3d_max(h.hi.y, v.y),
                    f3d_max(h.hi.z, v.z));
    }
  }
  for (uint32_t f = 0; f < nf; f++) {
    uint32_t *t = &triangles[((size_t)first_triangle + f) * 3u];
    t[0] = remap[faces[f].a];
    t[1] = remap[faces[f].b];
    t[2] = remap[faces[f].c];
  }
  f3d_copy(&hulls[world->s.hull_count], &h, sizeof h);
  world->s.hull_count++;
  world->s.hull_vertex_count += nv;
  world->s.hull_triangle_count += nf;
  result = world->s.hull_count;
done:
  f3d_free(p);
  f3d_free(faces);
  f3d_free(spare);
  f3d_free(edges);
  f3d_free(remap);
  return result;
}

int f3d_world_get_hull_offset(const F3dWorld *world, uint32_t hull,
                              f3d_real *out) {
  if (hull == 0 || hull > world->s.hull_count) return 0;
  const F3dVec3 o = world->hulls[hull - 1u].offset;
  out[0] = o.x;
  out[1] = o.y;
  out[2] = o.z;
  return 1;
}

uint32_t f3d_world_hull_vertex_count(const F3dWorld *world, uint32_t hull) {
  if (hull == 0 || hull > world->s.hull_count) return 0;
  return world->hulls[hull - 1u].vertex_count;
}
