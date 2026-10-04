/*
 * The narrow phase — P9, phase 2: where two shapes touch, how deep, and
 * which way out, for every pair of sphere, box and capsule, turned however
 * they are turned.
 *
 * Every pair answers with a manifold: one normal, out of b and into a, and
 * up to four points halfway between the two surfaces, each with its depth.
 * A depth is positive inside and negative for a gap within the margin, for
 * the reason flutter3d_physics' Contact.depth gives: a resting pile that
 * only reported overlaps would fall a step, catch itself, and fall again.
 *
 * A box resting on a face needs its whole face, not a pin to balance on, so
 * box against box clips the incident face to the reference face and keeps
 * up to four points; a capsule lying along a box or another capsule keeps
 * two. Each point carries the features that made it, so the solver can
 * carry an impulse across steps.
 */
#include "f3d_internal.h"

F3dMat3 f3d_mat_of(F3dQuat q) {
  const f3d_real x = q.x, y = q.y, z = q.z, w = q.w;
  F3dMat3 m;
  m.c[0] = f3d_v3(F3D_R(1.0) - F3D_R(2.0) * (y * y + z * z),
                  F3D_R(2.0) * (x * y + z * w), F3D_R(2.0) * (x * z - y * w));
  m.c[1] = f3d_v3(F3D_R(2.0) * (x * y - z * w),
                  F3D_R(1.0) - F3D_R(2.0) * (x * x + z * z),
                  F3D_R(2.0) * (y * z + x * w));
  m.c[2] = f3d_v3(F3D_R(2.0) * (x * z + y * w), F3D_R(2.0) * (y * z - x * w),
                  F3D_R(1.0) - F3D_R(2.0) * (x * x + y * y));
  return m;
}

static f3d_real component(F3dVec3 v, int i) {
  return i == 0 ? v.x : (i == 1 ? v.y : v.z);
}

/* v in the frame of [m], from the world's. */
static F3dVec3 to_local(const F3dMat3 *m, F3dVec3 v) {
  return f3d_v3(f3d_dot(m->c[0], v), f3d_dot(m->c[1], v), f3d_dot(m->c[2], v));
}

static F3dVec3 to_world(const F3dMat3 *m, F3dVec3 v) {
  return f3d_add(f3d_add(f3d_scale(m->c[0], v.x), f3d_scale(m->c[1], v.y)),
                 f3d_scale(m->c[2], v.z));
}

static void emit(F3dManifold *out, F3dVec3 point, f3d_real depth, uint32_t id) {
  if (out->count >= F3D_MANIFOLD_POINTS) return;
  F3dContactPoint *p = &out->points[out->count++];
  p->point = point;
  p->depth = depth;
  p->id = id;
}

/* ------------------------------------------------------------- segments */

/* A capsule's axis, end to end. */
static void segment_of(const F3dPlaced *c, F3dVec3 *p0, F3dVec3 *p1) {
  const F3dVec3 half = f3d_scale(c->axes.c[1], c->size.y);
  *p0 = f3d_sub(c->at, half);
  *p1 = f3d_add(c->at, half);
}

/* How far along p0→p1 the point nearest [q] lies, nought to one. */
static f3d_real nearest_on_segment(F3dVec3 p0, F3dVec3 p1, F3dVec3 q) {
  const F3dVec3 d = f3d_sub(p1, p0);
  const f3d_real dd = f3d_dot(d, d);
  if (!(dd > F3D_R(0.0))) return F3D_R(0.0);
  return f3d_clamp(f3d_dot(f3d_sub(q, p0), d) / dd, F3D_R(0.0), F3D_R(1.0));
}

/* The nearest pair of points on p0→p1 and q0→q1, as fractions along each:
 * Ericson's closest points of two segments, in Real-Time Collision
 * Detection, §5.1.9. */
static void nearest_of_segments(F3dVec3 p0, F3dVec3 p1, F3dVec3 q0, F3dVec3 q1,
                                f3d_real *s, f3d_real *t) {
  const F3dVec3 d1 = f3d_sub(p1, p0), d2 = f3d_sub(q1, q0);
  const F3dVec3 r = f3d_sub(p0, q0);
  const f3d_real a = f3d_dot(d1, d1), e = f3d_dot(d2, d2);
  const f3d_real f = f3d_dot(d2, r);
  const f3d_real tiny = F3D_R(1e-12);
  if (a <= tiny && e <= tiny) {
    *s = *t = F3D_R(0.0);
    return;
  }
  if (a <= tiny) {
    *s = F3D_R(0.0);
    *t = f3d_clamp(f / e, F3D_R(0.0), F3D_R(1.0));
    return;
  }
  const f3d_real c = f3d_dot(d1, r);
  if (e <= tiny) {
    *t = F3D_R(0.0);
    *s = f3d_clamp(-c / a, F3D_R(0.0), F3D_R(1.0));
    return;
  }
  const f3d_real b = f3d_dot(d1, d2);
  const f3d_real denom = a * e - b * b;
  f3d_real ss = denom > tiny * a * e
                    ? f3d_clamp((b * f - c * e) / denom, F3D_R(0.0), F3D_R(1.0))
                    : F3D_R(0.0);
  f3d_real tt = (b * ss + f) / e;
  if (tt < F3D_R(0.0)) {
    tt = F3D_R(0.0);
    ss = f3d_clamp(-c / a, F3D_R(0.0), F3D_R(1.0));
  } else if (tt > F3D_R(1.0)) {
    tt = F3D_R(1.0);
    ss = f3d_clamp((b - c) / a, F3D_R(0.0), F3D_R(1.0));
  }
  *s = ss;
  *t = tt;
}

static F3dVec3 along(F3dVec3 p0, F3dVec3 p1, f3d_real t) {
  return f3d_madd(p0, f3d_sub(p1, p0), t);
}

/* ------------------------------------------------------- round shapes */

/* Two balls: the core of every pair with a round side. The normal is out
 * of b, and concentric balls part upwards, as flutter3d_physics parts
 * them. Fills the normal when [set_normal]; otherwise measures along the
 * normal already there. */
static int balls(F3dVec3 ca, f3d_real ra, F3dVec3 cb, f3d_real rb,
                 f3d_real margin, F3dManifold *out, uint32_t id) {
  const F3dVec3 d = f3d_sub(ca, cb);
  const f3d_real reach = ra + rb;
  const f3d_real within = reach + margin;
  const f3d_real d2 = f3d_dot(d, d);
  if (d2 >= within * within) return 0;
  const f3d_real distance = f3d_sqrt(d2);
  const F3dVec3 n = distance > F3D_R(1e-9) * (F3D_R(1.0) + reach)
                        ? f3d_scale(d, F3D_R(1.0) / distance)
                        : f3d_v3(F3D_R(0.0), F3D_R(1.0), F3D_R(0.0));
  out->normal = n;
  /* Halfway between a's deepest point and b's. */
  const F3dVec3 on_a = f3d_madd(ca, n, -ra);
  const F3dVec3 on_b = f3d_madd(cb, n, rb);
  emit(out, f3d_scale(f3d_add(on_a, on_b), F3D_R(0.5)), reach - distance, id);
  return 1;
}

static uint32_t sphere_sphere(const F3dPlaced *a, const F3dPlaced *b,
                              f3d_real margin, F3dManifold *out) {
  return (uint32_t)balls(a->at, a->size.x, b->at, b->size.x, margin, out, 0);
}

static uint32_t sphere_capsule(const F3dPlaced *sphere,
                               const F3dPlaced *capsule, f3d_real margin,
                               F3dManifold *out) {
  F3dVec3 p0, p1;
  segment_of(capsule, &p0, &p1);
  const F3dVec3 q = along(p0, p1, nearest_on_segment(p0, p1, sphere->at));
  return (uint32_t)balls(sphere->at, sphere->size.x, q, capsule->size.x,
                         margin, out, 0);
}

static uint32_t capsule_capsule(const F3dPlaced *a, const F3dPlaced *b,
                                f3d_real margin, F3dManifold *out) {
  F3dVec3 a0, a1, b0, b1;
  segment_of(a, &a0, &a1);
  segment_of(b, &b0, &b1);
  f3d_real s, t;
  nearest_of_segments(a0, a1, b0, b1, &s, &t);
  const f3d_real ra = a->size.x, rb = b->size.x;
  if (!balls(along(a0, a1, s), ra, along(b0, b1, t), rb, margin, out, 0)) {
    return 0;
  }
  /* Lying along each other, one point is a pin to roll on: two, at the ends
   * of the stretch where they overlap, measured along the one normal. */
  const F3dVec3 da = f3d_sub(a1, a0), db = f3d_sub(b1, b0);
  const f3d_real la = f3d_dot(da, da), lb = f3d_dot(db, db);
  const F3dVec3 x = f3d_cross(da, db);
  if (la <= F3D_R(1e-12) || lb <= F3D_R(1e-12) ||
      f3d_dot(x, x) > F3D_R(1e-4) * la * lb) {
    return out->count;
  }
  f3d_real lo = f3d_dot(f3d_sub(b0, a0), da) / la;
  f3d_real hi = f3d_dot(f3d_sub(b1, a0), da) / la;
  if (lo > hi) {
    const f3d_real swap = lo;
    lo = hi;
    hi = swap;
  }
  lo = f3d_max(lo, F3D_R(0.0));
  hi = f3d_min(hi, F3D_R(1.0));
  if (hi - lo <= F3D_R(1e-3)) return out->count;
  const F3dVec3 n = out->normal;
  out->count = 0;
  const f3d_real ends[2] = {lo, hi};
  for (uint32_t i = 0; i < 2; i++) {
    const F3dVec3 pa = along(a0, a1, ends[i]);
    const F3dVec3 pb = along(b0, b1, nearest_on_segment(b0, b1, pa));
    const f3d_real depth = ra + rb - f3d_dot(f3d_sub(pa, pb), n);
    if (depth <= -margin) continue;
    const F3dVec3 on_a = f3d_madd(pa, n, -ra);
    emit(out, f3d_madd(on_a, n, F3D_R(0.5) * depth), depth, 1u + i);
  }
  return out->count;
}

/* --------------------------------------------------------- against a box */

/* A ball against a box: the box's nearest point, or with the centre inside
 * it, its nearest face. */
static int ball_box(F3dVec3 c, f3d_real r, const F3dPlaced *box,
                    f3d_real margin, F3dManifold *out, uint32_t id) {
  const F3dVec3 h = box->size;
  const F3dVec3 p = to_local(&box->axes, f3d_sub(c, box->at));
  const F3dVec3 q = f3d_v3(f3d_clamp(p.x, -h.x, h.x), f3d_clamp(p.y, -h.y, h.y),
                           f3d_clamp(p.z, -h.z, h.z));
  const F3dVec3 d = f3d_sub(p, q);
  const f3d_real d2 = f3d_dot(d, d);
  F3dVec3 nl, surface;
  f3d_real depth;
  if (d2 > F3D_R(1e-18)) {
    const f3d_real reach = r + margin;
    if (d2 >= reach * reach) return 0;
    const f3d_real distance = f3d_sqrt(d2);
    nl = f3d_scale(d, F3D_R(1.0) / distance);
    surface = q;
    depth = r - distance;
  } else {
    const f3d_real ox = h.x - f3d_abs(p.x), oy = h.y - f3d_abs(p.y);
    const f3d_real oz = h.z - f3d_abs(p.z);
    surface = p;
    if (ox <= oy && ox <= oz) {
      const f3d_real sign = p.x >= F3D_R(0.0) ? F3D_R(1.0) : F3D_R(-1.0);
      nl = f3d_v3(sign, F3D_R(0.0), F3D_R(0.0));
      surface.x = sign * h.x;
      depth = ox + r;
    } else if (oy <= oz) {
      const f3d_real sign = p.y >= F3D_R(0.0) ? F3D_R(1.0) : F3D_R(-1.0);
      nl = f3d_v3(F3D_R(0.0), sign, F3D_R(0.0));
      surface.y = sign * h.y;
      depth = oy + r;
    } else {
      const f3d_real sign = p.z >= F3D_R(0.0) ? F3D_R(1.0) : F3D_R(-1.0);
      nl = f3d_v3(F3D_R(0.0), F3D_R(0.0), sign);
      surface.z = sign * h.z;
      depth = oz + r;
    }
  }
  const F3dVec3 n = to_world(&box->axes, nl);
  const F3dVec3 on_box = f3d_add(box->at, to_world(&box->axes, surface));
  const F3dVec3 on_ball = f3d_madd(c, n, -r);
  out->normal = n;
  emit(out, f3d_scale(f3d_add(on_box, on_ball), F3D_R(0.5)), depth, id);
  return 1;
}

static uint32_t sphere_box(const F3dPlaced *sphere, const F3dPlaced *box,
                           f3d_real margin, F3dManifold *out) {
  return (uint32_t)ball_box(sphere->at, sphere->size.x, box, margin, out, 0);
}

/* The box's furthest reach along [n]. */
static f3d_real box_support(const F3dPlaced *box, F3dVec3 n) {
  return f3d_dot(n, box->at) +
         f3d_abs(f3d_dot(n, box->axes.c[0])) * box->size.x +
         f3d_abs(f3d_dot(n, box->axes.c[1])) * box->size.y +
         f3d_abs(f3d_dot(n, box->axes.c[2])) * box->size.z;
}

/* Squared distance from [p] to the box, in the box's own frame. */
static f3d_real box_gap2(const F3dPlaced *box, F3dVec3 p) {
  const F3dVec3 l = to_local(&box->axes, f3d_sub(p, box->at));
  const F3dVec3 h = box->size;
  const f3d_real dx = f3d_abs(l.x) - h.x, dy = f3d_abs(l.y) - h.y;
  const f3d_real dz = f3d_abs(l.z) - h.z;
  const f3d_real ex = f3d_max(dx, F3D_R(0.0)), ey = f3d_max(dy, F3D_R(0.0));
  const f3d_real ez = f3d_max(dz, F3D_R(0.0));
  return ex * ex + ey * ey + ez * ez;
}

static uint32_t capsule_box(const F3dPlaced *capsule, const F3dPlaced *box,
                            f3d_real margin, F3dManifold *out) {
  F3dVec3 p0, p1;
  segment_of(capsule, &p0, &p1);
  const f3d_real r = capsule->size.x;
  /* The axis's nearest point to the box: the distance to a box is convex
   * along a line, so a golden-section search finds its least to a part in
   * ten million in thirty-two narrowings, and only adds and multiplies. */
  f3d_real lo = F3D_R(0.0), hi = F3D_R(1.0);
  const f3d_real golden = F3D_R(0.6180339887498949);
  f3d_real m1 = hi - golden * (hi - lo), m2 = lo + golden * (hi - lo);
  f3d_real f1 = box_gap2(box, along(p0, p1, m1));
  f3d_real f2 = box_gap2(box, along(p0, p1, m2));
  for (int i = 0; i < 32; i++) {
    if (f1 <= f2) {
      hi = m2;
      m2 = m1;
      f2 = f1;
      m1 = hi - golden * (hi - lo);
      f1 = box_gap2(box, along(p0, p1, m1));
    } else {
      lo = m1;
      m1 = m2;
      f1 = f2;
      m2 = lo + golden * (hi - lo);
      f2 = box_gap2(box, along(p0, p1, m2));
    }
  }
  /* The deepest of the two ends and that nearest point gives the normal. */
  const f3d_real candidates[3] = {F3D_R(0.0), F3D_R(1.0),
                                  F3D_R(0.5) * (lo + hi)};
  F3dManifold best;
  f3d_zero(&best, sizeof best);
  int found = 0;
  for (uint32_t i = 0; i < 3; i++) {
    F3dManifold trial;
    f3d_zero(&trial, sizeof trial);
    if (!ball_box(along(p0, p1, candidates[i]), r, box, margin, &trial, i)) {
      continue;
    }
    if (!found || trial.points[0].depth > best.points[0].depth) {
      best = trial;
      found = 1;
    }
  }
  if (!found) return 0;
  out->normal = best.normal;
  emit(out, best.points[0].point, best.points[0].depth, best.points[0].id);
  /* Lying on a face, the ends rest on it too: each end that stands over
   * the face is measured along the face's normal, so a capsule on a floor
   * has two points and does not roll about the one. */
  const F3dVec3 n = best.normal;
  int face = -1;
  for (int k = 0; k < 3; k++) {
    if (f3d_abs(f3d_dot(n, box->axes.c[k])) > F3D_R(0.999)) face = k;
  }
  if (face < 0) return out->count;
  const f3d_real top = box_support(box, n);
  for (uint32_t i = 0; i < 2; i++) {
    if (best.points[0].id == i) continue;
    const F3dVec3 c = i == 0 ? p0 : p1;
    const F3dVec3 l = to_local(&box->axes, f3d_sub(c, box->at));
    int over = 1;
    for (int k = 0; k < 3; k++) {
      if (k != face && f3d_abs(component(l, k)) > component(box->size, k)) {
        over = 0;
      }
    }
    if (!over) continue;
    const f3d_real depth = top - (f3d_dot(n, c) - r);
    if (depth <= -margin) continue;
    const F3dVec3 on_capsule = f3d_madd(c, n, -r);
    emit(out, f3d_madd(on_capsule, n, F3D_R(0.5) * depth), depth, i);
  }
  return out->count;
}

/* ----------------------------------------------------------- box and box */

typedef struct ClipPoint {
  F3dVec3 p;
  uint32_t id;
} ClipPoint;

/* Keeps the part of [in] on the inner side of the plane dot(n, x) ≤ d,
 * Sutherland–Hodgman; a point made on the plane is named after the plane
 * and the edge it cut. */
static uint32_t clip(const ClipPoint *in, uint32_t count, F3dVec3 n, f3d_real d,
                     uint32_t plane, ClipPoint *out) {
  uint32_t written = 0;
  for (uint32_t i = 0; i < count; i++) {
    const ClipPoint a = in[i];
    const ClipPoint b = in[(i + 1) % count];
    const f3d_real da = f3d_dot(n, a.p) - d;
    const f3d_real db = f3d_dot(n, b.p) - d;
    if (da <= F3D_R(0.0) && written < 8u) out[written++] = a;
    /* A cut only where the edge truly crosses: an end on the plane is kept
     * as it is, and cutting there too would add it twice and grow a convex
     * quadrilateral past the eight points four cuts can make. */
    if (((da < F3D_R(0.0) && db > F3D_R(0.0)) ||
         (da > F3D_R(0.0) && db < F3D_R(0.0))) &&
        written < 8u) {
      const f3d_real t = da / (da - db);
      ClipPoint cut;
      cut.p = along(a.p, b.p, t);
      cut.id = 16u + plane * 4u + (a.id & 3u);
      out[written++] = cut;
    }
  }
  return written;
}

/* Of up to eight points, the four that hold the face: the deepest, the one
 * furthest from it, and the two that span the most area either side of the
 * line between them. */
static void reduce(ClipPoint *points, f3d_real *depths, uint32_t *count,
                   F3dVec3 n) {
  if (*count <= F3D_MANIFOLD_POINTS) return;
  uint32_t pick[4];
  pick[0] = 0;
  for (uint32_t i = 1; i < *count; i++) {
    if (depths[i] > depths[pick[0]]) pick[0] = i;
  }
  f3d_real best = F3D_R(-1.0);
  pick[1] = pick[0];
  for (uint32_t i = 0; i < *count; i++) {
    const F3dVec3 d = f3d_sub(points[i].p, points[pick[0]].p);
    if (f3d_dot(d, d) > best) {
      best = f3d_dot(d, d);
      pick[1] = i;
    }
  }
  const F3dVec3 line = f3d_sub(points[pick[1]].p, points[pick[0]].p);
  f3d_real most = F3D_R(0.0), least = F3D_R(0.0);
  pick[2] = pick[0];
  pick[3] = pick[1];
  for (uint32_t i = 0; i < *count; i++) {
    const f3d_real area = f3d_dot(
        f3d_cross(line, f3d_sub(points[i].p, points[pick[0]].p)), n);
    if (area > most) {
      most = area;
      pick[2] = i;
    }
    if (area < least) {
      least = area;
      pick[3] = i;
    }
  }
  ClipPoint kept[4];
  f3d_real kept_depths[4];
  uint32_t n_kept = 0;
  for (uint32_t k = 0; k < 4; k++) {
    int seen = 0;
    for (uint32_t j = 0; j < k; j++) seen |= pick[j] == pick[k];
    if (seen) continue;
    kept[n_kept] = points[pick[k]];
    kept_depths[n_kept] = depths[pick[k]];
    n_kept++;
  }
  for (uint32_t k = 0; k < n_kept; k++) {
    points[k] = kept[k];
    depths[k] = kept_depths[k];
  }
  *count = n_kept;
}

static uint32_t box_box(const F3dPlaced *a, const F3dPlaced *b,
                        f3d_real margin, F3dManifold *out) {
  const F3dVec3 d = f3d_sub(a->at, b->at);
  const f3d_real ha[3] = {a->size.x, a->size.y, a->size.z};
  const f3d_real hb[3] = {b->size.x, b->size.y, b->size.z};
  /* The fifteen axes that can part two boxes: three faces of each and the
   * nine crossings of their edges. The way out is the one they overlap
   * least along. */
  f3d_real best_face = F3D_R(1e30), best_edge = F3D_R(1e30);
  int face_axis = -1, edge_axis = -1;
  F3dVec3 face_n = f3d_v3(0, 0, 0), edge_n = f3d_v3(0, 0, 0);
  for (int k = 0; k < 15; k++) {
    F3dVec3 axis;
    if (k < 3) {
      axis = a->axes.c[k];
    } else if (k < 6) {
      axis = b->axes.c[k - 3];
    } else {
      axis = f3d_cross(a->axes.c[(k - 6) / 3], b->axes.c[(k - 6) % 3]);
      const f3d_real l2 = f3d_dot(axis, axis);
      /* Parallel edges cross to nothing: the face axes already cover
       * them. */
      if (l2 < F3D_R(1e-6)) continue;
      axis = f3d_scale(axis, F3D_R(1.0) / f3d_sqrt(l2));
    }
    f3d_real ra = F3D_R(0.0), rb = F3D_R(0.0);
    for (int i = 0; i < 3; i++) {
      ra += ha[i] * f3d_abs(f3d_dot(a->axes.c[i], axis));
      rb += hb[i] * f3d_abs(f3d_dot(b->axes.c[i], axis));
    }
    const f3d_real along_d = f3d_dot(d, axis);
    const f3d_real overlap = ra + rb - f3d_abs(along_d);
    if (overlap <= -margin) return 0;
    if (along_d < F3D_R(0.0)) axis = f3d_scale(axis, F3D_R(-1.0));
    if (k < 6) {
      /* a's faces first, and b's only when clearly better: two faces
       * nearly as good would otherwise trade places step to step, and a
       * resting box would rock between them. */
      const f3d_real better = k < 3 ? overlap : overlap + F3D_R(1e-4);
      if (better < best_face) {
        best_face = better;
        face_axis = k;
        face_n = axis;
      }
    } else if (overlap < best_edge) {
      best_edge = overlap;
      edge_axis = k;
      edge_n = axis;
    }
  }
  if (face_axis >= 3) best_face -= F3D_R(1e-4);
  /* An edge only when it is clearly the shorter way out: a face holds a
   * resting box, an edge only touches. */
  if (edge_axis >= 0 && best_edge < F3D_R(0.95) * best_face - F3D_R(1e-3)) {
    const int i = (edge_axis - 6) / 3, j = (edge_axis - 6) % 3;
    const F3dVec3 n = edge_n; /* Out of b, into a. */
    F3dVec3 ca = a->at, cb = b->at;
    for (int k = 0; k < 3; k++) {
      if (k != i) {
        const f3d_real s = f3d_dot(a->axes.c[k], n) > F3D_R(0.0) ? F3D_R(-1.0)
                                                                : F3D_R(1.0);
        ca = f3d_madd(ca, a->axes.c[k], s * ha[k]);
      }
      if (k != j) {
        const f3d_real s = f3d_dot(b->axes.c[k], n) > F3D_R(0.0) ? F3D_R(1.0)
                                                                : F3D_R(-1.0);
        cb = f3d_madd(cb, b->axes.c[k], s * hb[k]);
      }
    }
    const F3dVec3 a0 = f3d_madd(ca, a->axes.c[i], -ha[i]);
    const F3dVec3 a1 = f3d_madd(ca, a->axes.c[i], ha[i]);
    const F3dVec3 b0 = f3d_madd(cb, b->axes.c[j], -hb[j]);
    const F3dVec3 b1 = f3d_madd(cb, b->axes.c[j], hb[j]);
    f3d_real s, t;
    nearest_of_segments(a0, a1, b0, b1, &s, &t);
    const F3dVec3 pa = along(a0, a1, s), pb = along(b0, b1, t);
    out->normal = n;
    emit(out, f3d_scale(f3d_add(pa, pb), F3D_R(0.5)), best_edge,
         0x100u + (uint32_t)(edge_axis - 6));
    return out->count;
  }
  /* A face: the reference box's face along the axis, the incident box's
   * face turned most against it, clipped to the reference face's sides. */
  const int ref_is_a = face_axis < 3;
  const F3dPlaced *ref = ref_is_a ? a : b;
  const F3dPlaced *inc = ref_is_a ? b : a;
  const int rk = ref_is_a ? face_axis : face_axis - 3;
  /* Out of the reference face, towards the other box. face_n is out of b
   * into a. */
  const F3dVec3 nr = ref_is_a ? f3d_scale(face_n, F3D_R(-1.0)) : face_n;
  const f3d_real hr[3] = {ref->size.x, ref->size.y, ref->size.z};
  const f3d_real hi[3] = {inc->size.x, inc->size.y, inc->size.z};
  int ik = 0;
  f3d_real most = F3D_R(-1.0);
  for (int k = 0; k < 3; k++) {
    const f3d_real c = f3d_abs(f3d_dot(inc->axes.c[k], nr));
    if (c > most) {
      most = c;
      ik = k;
    }
  }
  const f3d_real side =
      f3d_dot(inc->axes.c[ik], nr) > F3D_R(0.0) ? F3D_R(-1.0) : F3D_R(1.0);
  const F3dVec3 inc_center = f3d_madd(inc->at, inc->axes.c[ik], side * hi[ik]);
  const int iu = (ik + 1) % 3, iv = (ik + 2) % 3;
  ClipPoint poly[8], scratch[8];
  const f3d_real su[4] = {F3D_R(1.0), F3D_R(-1.0), F3D_R(-1.0), F3D_R(1.0)};
  const f3d_real sv[4] = {F3D_R(1.0), F3D_R(1.0), F3D_R(-1.0), F3D_R(-1.0)};
  for (uint32_t v = 0; v < 4; v++) {
    poly[v].p = f3d_madd(f3d_madd(inc_center, inc->axes.c[iu], su[v] * hi[iu]),
                         inc->axes.c[iv], sv[v] * hi[iv]);
    poly[v].id = v;
  }
  uint32_t count = 4;
  const int ru = (rk + 1) % 3, rv = (rk + 2) % 3;
  const F3dVec3 u = ref->axes.c[ru], v = ref->axes.c[rv];
  const f3d_real du = f3d_dot(u, ref->at), dv = f3d_dot(v, ref->at);
  count = clip(poly, count, u, du + hr[ru], 0, scratch);
  count = clip(scratch, count, f3d_scale(u, F3D_R(-1.0)), -du + hr[ru], 1, poly);
  count = clip(poly, count, v, dv + hr[rv], 2, scratch);
  count = clip(scratch, count, f3d_scale(v, F3D_R(-1.0)), -dv + hr[rv], 3, poly);
  const f3d_real face_d = f3d_dot(nr, ref->at) + hr[rk];
  ClipPoint kept[8];
  f3d_real depths[8];
  uint32_t n_kept = 0;
  for (uint32_t i = 0; i < count; i++) {
    const f3d_real depth = face_d - f3d_dot(nr, poly[i].p);
    if (depth <= -margin) continue;
    kept[n_kept] = poly[i];
    depths[n_kept] = depth;
    n_kept++;
  }
  if (n_kept == 0) return 0;
  reduce(kept, depths, &n_kept, nr);
  out->normal = face_n;
  const uint32_t base = ((ref_is_a ? 0u : 1u) << 12) | ((uint32_t)rk << 8) |
                        ((uint32_t)ik << 6);
  for (uint32_t i = 0; i < n_kept; i++) {
    emit(out, f3d_madd(kept[i].p, nr, F3D_R(0.5) * depths[i]), depths[i],
         base | kept[i].id);
  }
  return out->count;
}

/* ---------------------------------------------------------------- pairs */

/* The same pair with a and b swapped: the normal turns round. */
static uint32_t flipped(uint32_t count, F3dManifold *out) {
  out->normal = f3d_scale(out->normal, F3D_R(-1.0));
  return count;
}

/* Whether the pair has a closed form here: balls, unrounded boxes and
 * capsules. Anything else goes to the general narrow phase. */
static int classic(const F3dPlaced *p) {
  return p->kind == F3D_SHAPE_SPHERE || p->kind == F3D_SHAPE_CAPSULE ||
         (p->kind == F3D_SHAPE_BOX && p->rounding == F3D_R(0.0));
}

uint32_t f3d_collide(const F3dPlaced *pa, const F3dPlaced *pb, f3d_real margin,
                     F3dManifold *out) {
  out->count = 0;
  out->touching = 0;
  uint32_t count = 0;
  if (pa->kind == F3D_SHAPE_POINT || pb->kind == F3D_SHAPE_POINT) return 0;
  if (!classic(pa) || !classic(pb)) {
    count = f3d_collide_convex(pa, pb, margin, out);
    out->count = count;
    for (uint32_t i = 0; i < count; i++) {
      if (out->points[i].depth >= -F3D_LINEAR_SLOP) out->touching = 1;
    }
    return count;
  }
  /* A ball's or a capsule's rounding is more radius. */
  F3dPlaced ra = *pa, rb = *pb;
  if (ra.kind != F3D_SHAPE_BOX) ra.size.x += ra.rounding;
  if (rb.kind != F3D_SHAPE_BOX) rb.size.x += rb.rounding;
  const F3dPlaced *a = &ra, *b = &rb;
  switch (a->kind * 4u + b->kind) {
    case F3D_SHAPE_SPHERE * 4u + F3D_SHAPE_SPHERE:
      count = sphere_sphere(a, b, margin, out);
      break;
    case F3D_SHAPE_SPHERE * 4u + F3D_SHAPE_BOX:
      count = sphere_box(a, b, margin, out);
      break;
    case F3D_SHAPE_BOX * 4u + F3D_SHAPE_SPHERE:
      count = flipped(sphere_box(b, a, margin, out), out);
      break;
    case F3D_SHAPE_SPHERE * 4u + F3D_SHAPE_CAPSULE:
      count = sphere_capsule(a, b, margin, out);
      break;
    case F3D_SHAPE_CAPSULE * 4u + F3D_SHAPE_SPHERE:
      count = flipped(sphere_capsule(b, a, margin, out), out);
      break;
    case F3D_SHAPE_BOX * 4u + F3D_SHAPE_BOX:
      count = box_box(a, b, margin, out);
      break;
    case F3D_SHAPE_CAPSULE * 4u + F3D_SHAPE_BOX:
      count = capsule_box(a, b, margin, out);
      break;
    case F3D_SHAPE_BOX * 4u + F3D_SHAPE_CAPSULE:
      count = flipped(capsule_box(b, a, margin, out), out);
      break;
    case F3D_SHAPE_CAPSULE * 4u + F3D_SHAPE_CAPSULE:
      count = capsule_capsule(a, b, margin, out);
      break;
    default:
      return 0; /* A point touches nothing. */
  }
  out->count = count;
  for (uint32_t i = 0; i < count; i++) {
    if (out->points[i].depth >= -F3D_LINEAR_SLOP) out->touching = 1;
  }
  return count;
}
