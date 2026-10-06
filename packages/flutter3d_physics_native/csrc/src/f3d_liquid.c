/*
 * Liquid on the core: the three parts of flutter3d_physics's liquids that
 * are stepped through time, for a run whose fluid is on the core. Each is
 * the Dart reference's algorithm line for line — the comments there say
 * why each step is as it is — and each moves one step's state in place,
 * keeping nothing between calls: the Dart side keeps the books.
 *
 * Particles (ParticleFluid): position-based fluids (Macklin and Müller,
 * 2013), each substep
 *
 *   1. every particle out of the walls, then the density held where they
 *      stand (pre-stabilisation: what is already compressed is taken out
 *      of the positions, not the velocities);
 *   2. gravity, Akinci's cohesion and curvature on the velocities;
 *   3. a predicted position, moved in pieces of two fifths of a spacing
 *      against the walls;
 *   4. the density held there, with Macklin's artificial pressure;
 *   5. the velocity from the move, smoothed towards the neighbours' by
 *      XSPH's share.
 *
 * Densities are kernel sums over what the rest lattice sums to, which the
 * Dart side works out once and hands over, so both backends divide by the
 * same number. Only compression is corrected, never stretching: a surface
 * is held by cohesion.
 *
 * Parcels (Jet): each falls under gravity in pieces no longer than its
 * radius, pushed out of the walls it meets and losing the speed that went
 * into them; off a wall, it is drawn back while it is slower than the
 * speed surface tension holds a film of its thickness at; in the air, the
 * ripples on it grow at Weber's rate.
 *
 * Modes (FreeSurface): each the damped oscillator it is, stepped exactly,
 * damped by Stephens and Dodge's boundary layer and the bulk's 2νk², then
 * cut to a fourteenth of its wavelength. In doubles, as the reference: the
 * sine, cosine and exponential are this file's own, since the WebAssembly
 * build has no C library.
 *
 * Pipes (Pipe): the column in each is driven by the pressure across its
 * ends over its inertance and held back, implicitly, by Hagen–Poiseuille's
 * friction and the losses where it enters and leaves.
 *
 * Floats (FloatingBody): a body is lifted by the weight of the liquid it
 * displaces and slowed, implicitly, by the drag of the part of it under,
 * with White's sphere coefficient for the sphere of its frontal area. How
 * much of it is under is the Dart side's: geometry, not stepped.
 *
 * Walls are planes, and the inside and outside of a vessel turned from a
 * profile (RevolvedVessel's InsideWalls and OutsideWalls).
 */
#include "f3d_internal.h"

/* ------------------------------------------------------------ doubles */

#if defined(_MSC_VER)
#include <math.h>
static double dsqrt(double x) { return sqrt(x); }
#else
static double dsqrt(double x) { return __builtin_sqrt(x); }
#endif

static double dmax(double a, double b) { return a > b ? a : b; }
static double dabs(double x) { return x < 0.0 ? -x : x; }

/* The nearest whole number, for |x| well inside an int64's range. */
static double dround(double x) {
  return (double)(int64_t)(x < 0.0 ? x - 0.5 : x + 0.5);
}

/* eˣ: x = k ln 2 + r with |r| ≤ ln 2 / 2, Taylor's series for eʳ to the
 * thirteenth power — a few parts in 10¹⁸ — times 2ᵏ by squaring. */
static double dexp(double x) {
  if (!(x > -700.0)) return 0.0;
  if (x > 700.0) x = 700.0;
  const double ln2 = 0.69314718055994530942;
  const double k = dround(x / ln2);
  const double r = x - k * ln2;
  double sum = 1.0, term = 1.0;
  for (int i = 1; i <= 13; i++) {
    term *= r / (double)i;
    sum += term;
  }
  double scale = 1.0, two = k >= 0.0 ? 2.0 : 0.5;
  for (int64_t m = (int64_t)dabs(k); m != 0; m >>= 1) {
    if (m & 1) scale *= two;
    two *= two;
  }
  return sum * scale;
}

/* sin x and cos x: x brought within a quarter turn of a multiple of one,
 * and Taylor's series there. */
static void dsincos(double x, double *sine, double *cosine) {
  const double two_pi = 6.28318530717958647692;
  const double half_pi = 1.57079632679489661923;
  const double r = x - dround(x / two_pi) * two_pi;
  const double quarter = dround(r / half_pi);
  const double y = r - quarter * half_pi;
  const double y2 = y * y;
  double s = y, c = 1.0, ts = y, tc = 1.0;
  for (int i = 1; i <= 9; i++) {
    ts *= -y2 / (double)((2 * i) * (2 * i + 1));
    tc *= -y2 / (double)((2 * i - 1) * (2 * i));
    s += ts;
    c += tc;
  }
  switch (((int)quarter % 4 + 4) % 4) {
    case 0: *sine = s; *cosine = c; break;
    case 1: *sine = c; *cosine = -s; break;
    case 2: *sine = -s; *cosine = -c; break;
    default: *sine = -c; *cosine = s; break;
  }
}

/* ceil(x) held to [1, most]: how many pieces a move is cut into. */
static uint32_t pieces_for(f3d_real x, uint32_t most) {
  if (!(x < (f3d_real)most)) return most;
  if (!(x > F3D_R(1.0))) return 1;
  uint32_t n = (uint32_t)x;
  if ((f3d_real)n < x) n++;
  return n;
}

/* -------------------------------------------------------------- walls */

typedef struct Wall {
  uint32_t kind;
  /* A plane. */
  F3dVec3 normal;
  f3d_real offset;
  /* A vessel: where it stands, its turn column by column, its glass, and
   * its profile. */
  F3dVec3 at;
  f3d_real m[9];
  f3d_real thickness;
  f3d_real floor;
  f3d_real top;
  f3d_real widest;
  f3d_real floor_radius;
  const f3d_real *profile;
  uint32_t points;
} Wall;

#define VESSEL_HEAD 19u

/* The records' walls, or 0 for a record of no kind or cut short, or no
 * memory. [*walls] is null when there are none. */
static int read_walls(const f3d_real *records, uint32_t length, Wall **walls,
                      uint32_t *count) {
  *walls = NULL;
  *count = 0;
  uint32_t n = 0;
  for (uint32_t at = 0; at < length;) {
    const f3d_real kind = records[at];
    if (kind == (f3d_real)F3D_LIQUID_PLANE) {
      if (length - at < 5u) return 0;
      at += 5u;
    } else if (kind == (f3d_real)F3D_LIQUID_INSIDE || kind == (f3d_real)F3D_LIQUID_OUTSIDE) {
      if (length - at < VESSEL_HEAD) return 0;
      const f3d_real points = records[at + VESSEL_HEAD - 1u];
      if (!(points >= F3D_R(2.0)) || !(points <= F3D_R(1e6))) return 0;
      const uint32_t p = (uint32_t)points;
      if ((f3d_real)p != points || (length - at - VESSEL_HEAD) / 2u < p) return 0;
      at += VESSEL_HEAD + 2u * p;
    } else {
      return 0;
    }
    n++;
  }
  if (n == 0) return 1;
  Wall *out = (Wall *)f3d_alloc((size_t)n * sizeof(Wall));
  if (out == NULL) return 0;
  f3d_zero(out, (size_t)n * sizeof(Wall));
  uint32_t k = 0;
  for (uint32_t at = 0; at < length; k++) {
    const f3d_real *r = records + at;
    Wall *w = &out[k];
    if (r[0] == (f3d_real)F3D_LIQUID_PLANE) {
      w->kind = F3D_LIQUID_PLANE;
      w->normal = f3d_v3(r[1], r[2], r[3]);
      w->offset = r[4];
      at += 5u;
      continue;
    }
    w->kind = r[0] == (f3d_real)F3D_LIQUID_INSIDE ? F3D_LIQUID_INSIDE : F3D_LIQUID_OUTSIDE;
    w->at = f3d_v3(r[1], r[2], r[3]);
    for (int i = 0; i < 9; i++) w->m[i] = r[4 + i];
    w->thickness = r[13];
    w->floor = r[14];
    w->top = r[15];
    w->widest = r[16];
    w->floor_radius = r[17];
    w->points = (uint32_t)r[18];
    w->profile = r + VESSEL_HEAD;
    at += VESSEL_HEAD + 2u * w->points;
  }
  *walls = out;
  *count = n;
  return 1;
}

/* [v] turned by the vessel's turn: its frame into the world. */
static F3dVec3 turned(const Wall *w, F3dVec3 v) {
  const f3d_real *m = w->m;
  return f3d_v3(m[0] * v.x + m[3] * v.y + m[6] * v.z, m[1] * v.x + m[4] * v.y + m[7] * v.z,
                m[2] * v.x + m[5] * v.y + m[8] * v.z);
}

/* [p] in the vessel's frame, or 0 when it is further than [margin] beyond
 * the inside, sideways or along the axis. */
static int near_vessel(const Wall *w, F3dVec3 p, f3d_real margin, F3dVec3 *q) {
  const f3d_real *m = w->m;
  const f3d_real dx = p.x - w->at.x, dy = p.y - w->at.y, dz = p.z - w->at.z;
  const f3d_real y = m[3] * dx + m[4] * dy + m[5] * dz;
  if (y < w->floor - margin || y > w->top + margin) return 0;
  const f3d_real x = m[0] * dx + m[1] * dy + m[2] * dz;
  const f3d_real z = m[6] * dx + m[7] * dy + m[8] * dz;
  const f3d_real reach = w->widest + margin;
  if (x * x + z * z > reach * reach) return 0;
  *q = f3d_v3(x, y, z);
  return 1;
}

/* How far [q] (vessel frame) is from the profile across it — negative
 * inside — and the wall's outward normal there; 0 above the mouth. */
static int wall_distance(const Wall *w, F3dVec3 q, f3d_real *distance, F3dVec3 *normal) {
  if (q.y > w->top) return 0;
  const f3d_real r = f3d_sqrt(q.x * q.x + q.z * q.z);
  const F3dVec3 out = r > F3D_R(1e-12) ? f3d_v3(q.x / r, 0, q.z / r) : f3d_v3(1, 0, 0);
  f3d_real best = F3D_R(1e30);
  f3d_real nx = 0, ny = -1, sign = 1;
  const f3d_real *pr = w->profile;
  for (uint32_t i = 0; i + 1u < w->points; i++) {
    const f3d_real ax = pr[2u * i], ay = pr[2u * i + 1u];
    const f3d_real dx = pr[2u * i + 2u] - ax, dy = pr[2u * i + 3u] - ay;
    const f3d_real length2 = dx * dx + dy * dy;
    if (length2 < F3D_R(1e-24)) continue;
    const f3d_real t = f3d_clamp(((r - ax) * dx + (q.y - ay) * dy) / length2, 0, 1);
    const f3d_real ox = r - (ax + dx * t), oy = q.y - (ay + dy * t);
    const f3d_real d = f3d_sqrt(ox * ox + oy * oy);
    if (d < best) {
      best = d;
      /* Outward is to the right of the way the profile runs. */
      const f3d_real l = f3d_sqrt(length2);
      const f3d_real rx = dy / l, ry = -dx / l;
      sign = ox * rx + oy * ry >= 0 ? F3D_R(1.0) : F3D_R(-1.0);
      nx = rx;
      ny = ry;
    }
  }
  *distance = sign * best;
  *normal = f3d_v3(out.x * nx, ny, out.z * nx);
  return 1;
}

/* Where a ball of [radius] at [p] is into [w]: the way out and how far,
 * or 0 when it is clear. */
static int touch(const Wall *w, F3dVec3 p, f3d_real radius, F3dVec3 *normal, f3d_real *depth) {
  if (w->kind == F3D_LIQUID_PLANE) {
    const f3d_real d = f3d_dot(w->normal, p) - w->offset - radius;
    if (!(d < F3D_R(0.0))) return 0;
    *normal = w->normal;
    *depth = -d;
    return 1;
  }
  F3dVec3 q;
  const f3d_real t = w->thickness;
  if (!near_vessel(w, p, t + radius, &q)) return 0;
  const f3d_real fr = w->floor_radius;
  f3d_real distance;
  F3dVec3 n;
  if (w->kind == F3D_LIQUID_INSIDE) {
    /* Under the inside's floor and beyond its edge is the outside's. */
    if (q.y < w->floor && q.x * q.x + q.z * q.z >= fr * fr) return 0;
    if (!wall_distance(w, q, &distance, &n)) return 0;
    const f3d_real glass = t > F3D_R(0.0) ? F3D_R(0.5) * t : radius;
    if (distance <= -radius || distance >= glass) return 0;
    *normal = turned(w, f3d_scale(n, F3D_R(-1.0)));
    *depth = distance + radius;
    return 1;
  }
  /* Below the inside's floor the glass is its foot: out sideways. */
  if (q.y < w->floor) {
    const f3d_real r = f3d_sqrt(q.x * q.x + q.z * q.z);
    const f3d_real clear = fr + t + radius;
    if (r >= clear || r < fr) return 0;
    const F3dVec3 out = r > F3D_R(1e-12) ? f3d_v3(q.x / r, 0, q.z / r) : f3d_v3(1, 0, 0);
    *normal = turned(w, out);
    *depth = clear - r;
    return 1;
  }
  /* The rim's top is glass too, up to its thickness above the mouth. */
  const F3dVec3 at = q.y > w->top && q.y <= w->top + t ? f3d_v3(q.x, w->top, q.z) : q;
  if (!wall_distance(w, at, &distance, &n)) return 0;
  const f3d_real clear = t + radius;
  if (distance < F3D_R(0.5) * t || distance >= clear) return 0;
  *normal = turned(w, n);
  *depth = clear - distance;
  return 1;
}

/* [p] pushed out of every wall in turn. */
static F3dVec3 collide(const Wall *walls, uint32_t count, F3dVec3 p, f3d_real radius) {
  for (uint32_t k = 0; k < count; k++) {
    F3dVec3 n;
    f3d_real depth;
    if (touch(&walls[k], p, radius, &n, &depth)) p = f3d_madd(p, n, depth);
  }
  return p;
}

/* ---------------------------------------------------------- particles */

typedef struct Kernels {
  f3d_real h;
  f3d_real h2;
  f3d_real poly6;
  f3d_real spiky;
  f3d_real cohesion;
  f3d_real sixth;
} Kernels;

static Kernels kernels(f3d_real spacing) {
  Kernels k;
  const double h = 2.0 * (double)spacing;
  const double h3 = h * h * h;
  const double pi = 3.14159265358979323846;
  k.h = (f3d_real)h;
  k.h2 = (f3d_real)(h * h);
  k.poly6 = (f3d_real)(315.0 / (64.0 * pi * h3 * h3 * h3));
  k.spiky = (f3d_real)(-45.0 / (pi * h3 * h3));
  k.cohesion = (f3d_real)(32.0 / (pi * h3 * h3 * h3));
  k.sixth = (f3d_real)(h3 * h3 / 64.0);
  return k;
}

static f3d_real poly6(const Kernels *k, f3d_real r2) {
  if (r2 >= k->h2) return 0;
  const f3d_real d = k->h2 - r2;
  return k->poly6 * d * d * d;
}

static F3dVec3 spiky(const Kernels *k, F3dVec3 d) {
  const f3d_real r = f3d_sqrt(f3d_dot(d, d));
  if (r <= F3D_R(1e-12) || r >= k->h) return f3d_v3(0, 0, 0);
  const f3d_real f = k->spiky * (k->h - r) * (k->h - r);
  return f3d_scale(d, f / r);
}

/* Akinci's cohesion spline. */
static f3d_real cohesion(const Kernels *k, f3d_real r) {
  if (r >= k->h || r <= F3D_R(0.0)) return 0;
  const f3d_real a = (k->h - r) * (k->h - r) * (k->h - r) * r * r * r;
  if (F3D_R(2.0) * r > k->h) return k->cohesion * a;
  return k->cohesion * (F3D_R(2.0) * a - k->sixth);
}

/* Each point's neighbours within the kernel, itself left out: [list] from
 * [start][i] to [start][i + 1]. */
typedef struct Near {
  uint32_t *start;
  uint32_t *list;
} Near;

static void near_free(Near *near) {
  f3d_free(near->start);
  f3d_free(near->list);
  near->start = NULL;
  near->list = NULL;
}

static int32_t cell_of(f3d_real x, f3d_real inv) {
  const f3d_real v = f3d_clamp(x * inv, F3D_R(-1e9), F3D_R(1e9));
  int32_t t = (int32_t)v;
  if ((f3d_real)t > v) t--;
  return t;
}

static uint32_t bucket(int32_t x, int32_t y, int32_t z, uint32_t mask) {
  return (((uint32_t)x * 73856093u) ^ ((uint32_t)y * 19349663u) ^ ((uint32_t)z * 83492791u)) &
         mask;
}

#define NONE 0xFFFFFFFFu

/* [near] for [p]: a hashed grid of cells as wide as the kernel, each
 * point met in the 27 cells round its own. 0 for no memory. */
static int find_near(const F3dVec3 *p, uint32_t n, f3d_real h, Near *near) {
  near->start = NULL;
  near->list = NULL;
  uint32_t buckets = 1;
  while (buckets < 2u * n && buckets < (1u << 30)) buckets <<= 1;
  uint32_t *head = (uint32_t *)f3d_alloc((size_t)buckets * sizeof(uint32_t));
  uint32_t *next = (uint32_t *)f3d_alloc((size_t)n * sizeof(uint32_t));
  int32_t *cell = (int32_t *)f3d_alloc((size_t)n * 3u * sizeof(int32_t));
  near->start = (uint32_t *)f3d_alloc(((size_t)n + 1u) * sizeof(uint32_t));
  int ok = head != NULL && next != NULL && cell != NULL && near->start != NULL;
  if (ok) {
    const f3d_real inv = F3D_R(1.0) / h;
    const f3d_real h2 = h * h;
    for (uint32_t b = 0; b < buckets; b++) head[b] = NONE;
    for (uint32_t i = 0; i < n; i++) {
      int32_t *c = &cell[3u * i];
      c[0] = cell_of(p[i].x, inv);
      c[1] = cell_of(p[i].y, inv);
      c[2] = cell_of(p[i].z, inv);
      const uint32_t b = bucket(c[0], c[1], c[2], buckets - 1u);
      next[i] = head[b];
      head[b] = i;
    }
    /* Twice: counting, then writing. */
    for (int pass = 0; pass < 2 && ok; pass++) {
      uint32_t total = 0;
      for (uint32_t i = 0; i < n; i++) {
        if (pass == 0) near->start[i] = total;
        const int32_t *c = &cell[3u * i];
        for (int32_t x = c[0] - 1; x <= c[0] + 1; x++) {
          for (int32_t y = c[1] - 1; y <= c[1] + 1; y++) {
            for (int32_t z = c[2] - 1; z <= c[2] + 1; z++) {
              for (uint32_t j = head[bucket(x, y, z, buckets - 1u)]; j != NONE; j = next[j]) {
                const int32_t *cj = &cell[3u * j];
                if (j == i || cj[0] != x || cj[1] != y || cj[2] != z) continue;
                const F3dVec3 d = f3d_sub(p[j], p[i]);
                if (!(f3d_dot(d, d) < h2)) continue;
                if (pass == 1) near->list[total] = j;
                total++;
              }
            }
          }
        }
      }
      if (pass == 0) {
        near->start[n] = total;
        near->list = (uint32_t *)f3d_alloc((size_t)(total > 0 ? total : 1u) * sizeof(uint32_t));
        ok = near->list != NULL;
      }
    }
  }
  f3d_free(head);
  f3d_free(next);
  f3d_free(cell);
  if (!ok) near_free(near);
  return ok;
}

typedef struct Solve {
  const F3dLiquidParticleSettings *s;
  Kernels k;
  const Wall *walls;
  uint32_t wall_count;
  uint32_t n;
  F3dVec3 *x;
  F3dVec3 *v;
  F3dVec3 *p;
  F3dVec3 *delta;
  F3dVec3 *normal;
  f3d_real *lambda;
  f3d_real *density;
} Solve;

/* pᵢ − pⱼ, or, where the two stand on the same point, a hair of it in a
 * direction set by the pair alone — opposite for j and i. */
static F3dVec3 between(const Solve *solve, const F3dVec3 *p, uint32_t i, uint32_t j) {
  const F3dVec3 d = f3d_sub(p[i], p[j]);
  if (f3d_dot(d, d) > F3D_R(1e-24) * solve->k.h2) return d;
  const double low = (double)(i < j ? i : j);
  const double high = (double)(i < j ? j : i);
  /* A point on the sphere from the pair's indices, by the golden angle. */
  const double u = low * 0.6180339887498949 + high * 0.4142135623730951;
  const double t = u - (double)(int64_t)u;
  const double z = 1.0 - 2.0 * t;
  const double ring = dsqrt(dmax(1.0 - z * z, 0.0));
  double sine, cosine;
  dsincos(2.399963229728653 * (low + 7.0 * high), &sine, &cosine);
  const double away = 1e-6 * (double)solve->k.h * (i < j ? 1.0 : -1.0);
  return f3d_v3((f3d_real)(ring * cosine * away), (f3d_real)(ring * sine * away),
                (f3d_real)(z * away));
}

/* Moves [p] until none is compressed past the rest density, for the
 * settings' passes at most, or fewer once none is compressed by more than
 * [until]; [near] is each one's neighbours where [p] stood at the start,
 * kept for the caller. 0 for no memory. */
static int hold_density(Solve *solve, F3dVec3 *p, int artificial, f3d_real until, Near *near) {
  const uint32_t n = solve->n;
  const Kernels *k = &solve->k;
  const f3d_real norm = F3D_R(1.0) / solve->s->lattice_sum;
  if (!find_near(p, n, k->h, near)) return 0;
  const f3d_real dq = F3D_R(0.3) * k->h;
  const f3d_real wq = poly6(k, dq * dq);
  const f3d_real radius = F3D_R(0.5) * solve->s->spacing;
  const f3d_real soft = F3D_R(1e-6) * norm * norm / k->h2;
  for (uint32_t it = 0; it < solve->s->iterations; it++) {
    f3d_real worst = 0;
    for (uint32_t i = 0; i < n; i++) {
      f3d_real w = poly6(k, 0);
      f3d_real sum2 = 0;
      F3dVec3 gi = f3d_v3(0, 0, 0);
      for (uint32_t e = near->start[i]; e < near->start[i + 1u]; e++) {
        const F3dVec3 d = between(solve, p, i, near->list[e]);
        w += poly6(k, f3d_dot(d, d));
        const F3dVec3 g = f3d_scale(spiky(k, d), norm);
        sum2 += f3d_dot(g, g);
        gi = f3d_add(gi, g);
      }
      sum2 += f3d_dot(gi, gi);
      const f3d_real c = f3d_max(w * norm - F3D_R(1.0), 0);
      worst = f3d_max(worst, c);
      solve->lambda[i] = -c / (sum2 + soft);
    }
    if (worst <= until) break;
    for (uint32_t i = 0; i < n; i++) {
      F3dVec3 delta = f3d_v3(0, 0, 0);
      for (uint32_t e = near->start[i]; e < near->start[i + 1u]; e++) {
        const uint32_t j = near->list[e];
        const F3dVec3 d = between(solve, p, i, j);
        f3d_real corr = 0;
        if (artificial) {
          const f3d_real ratio = poly6(k, f3d_dot(d, d)) / wq;
          corr = F3D_R(-0.02) * ratio * ratio * ratio * ratio / solve->s->rest_stiffness;
        }
        delta = f3d_madd(delta, spiky(k, d), (solve->lambda[i] + solve->lambda[j] + corr) * norm);
      }
      solve->delta[i] = delta;
    }
    for (uint32_t i = 0; i < n; i++) {
      p[i] = collide(solve->walls, solve->wall_count, f3d_add(p[i], solve->delta[i]), radius);
    }
  }
  return 1;
}

static int substep(Solve *solve) {
  const F3dLiquidParticleSettings *s = solve->s;
  const Kernels *k = &solve->k;
  const uint32_t n = solve->n;
  const f3d_real dt = s->dt;
  const f3d_real radius = F3D_R(0.5) * s->spacing;
  F3dVec3 *x = solve->x;
  F3dVec3 *v = solve->v;
  F3dVec3 *p = solve->p;
  /* 1. Out of the walls, and pre-stabilised. */
  for (uint32_t i = 0; i < n; i++) x[i] = collide(solve->walls, solve->wall_count, x[i], radius);
  Near near;
  if (!hold_density(solve, x, 0, F3D_R(1e-3), &near)) return 0;
  near_free(&near);
  /* 2. Gravity, cohesion and curvature, on the velocities. */
  if (!find_near(x, n, k->h, &near)) return 0;
  const f3d_real rho0 = s->density;
  const f3d_real m = s->density * s->spacing * s->spacing * s->spacing;
  const f3d_real gamma = s->cohesion;
  const f3d_real norm = F3D_R(1.0) / s->lattice_sum;
  for (uint32_t i = 0; i < n; i++) {
    f3d_real w = poly6(k, 0);
    for (uint32_t e = near.start[i]; e < near.start[i + 1u]; e++) {
      const F3dVec3 d = f3d_sub(x[i], x[near.list[e]]);
      w += poly6(k, f3d_dot(d, d));
    }
    solve->density[i] = rho0 * w * norm;
  }
  for (uint32_t i = 0; i < n; i++) {
    F3dVec3 nn = f3d_v3(0, 0, 0);
    for (uint32_t e = near.start[i]; e < near.start[i + 1u]; e++) {
      const uint32_t j = near.list[e];
      nn = f3d_madd(nn, spiky(k, f3d_sub(x[i], x[j])), k->h * m / solve->density[j]);
    }
    solve->normal[i] = nn;
  }
  const F3dVec3 g = f3d_v3(s->gravity[0], s->gravity[1], s->gravity[2]);
  for (uint32_t i = 0; i < n; i++) {
    F3dVec3 a = g;
    for (uint32_t e = near.start[i]; e < near.start[i + 1u]; e++) {
      const uint32_t j = near.list[e];
      const F3dVec3 d = f3d_sub(x[i], x[j]);
      const f3d_real r = f3d_sqrt(f3d_dot(d, d));
      if (r < F3D_R(1e-12)) continue;
      const f3d_real kk = F3D_R(2.0) * rho0 / (solve->density[i] + solve->density[j]);
      a = f3d_madd(a, d, -kk * gamma * m * cohesion(k, r) / r);
      a = f3d_madd(a, f3d_sub(solve->normal[i], solve->normal[j]), -kk * gamma);
    }
    v[i] = f3d_madd(v[i], a, dt);
  }
  near_free(&near);
  /* 3. Predicted, in pieces of two fifths of a spacing against the walls. */
  for (uint32_t i = 0; i < n; i++) {
    const uint32_t pieces =
        solve->wall_count == 0
            ? 1u
            : pieces_for(f3d_sqrt(f3d_dot(v[i], v[i])) * dt / (F3D_R(0.4) * s->spacing), 64u);
    F3dVec3 q = x[i];
    for (uint32_t piece = 0; piece < pieces; piece++) {
      q = f3d_madd(q, v[i], dt / (f3d_real)pieces);
      if (pieces > 1u) q = collide(solve->walls, solve->wall_count, q, radius);
    }
    p[i] = q;
  }
  /* 4. The density held where they went. */
  if (!hold_density(solve, p, 1, 0, &near)) return 0;
  /* 5. The velocity from the move, and XSPH's viscosity. */
  for (uint32_t i = 0; i < n; i++) {
    v[i] = f3d_scale(f3d_sub(p[i], x[i]), F3D_R(1.0) / dt);
  }
  const f3d_real share = f3d_min(
      F3D_R(0.5), s->kinematic_viscosity * dt / (s->spacing * s->spacing) * F3D_R(50.0) +
                      F3D_R(0.01));
  for (uint32_t i = 0; i < n; i++) {
    F3dVec3 smooth = v[i];
    for (uint32_t e = near.start[i]; e < near.start[i + 1u]; e++) {
      const uint32_t j = near.list[e];
      const F3dVec3 d = f3d_sub(p[i], p[j]);
      smooth = f3d_madd(smooth, f3d_sub(v[j], v[i]), share * poly6(k, f3d_dot(d, d)) * norm);
    }
    solve->delta[i] = smooth;
  }
  near_free(&near);
  for (uint32_t i = 0; i < n; i++) {
    v[i] = solve->delta[i];
    x[i] = p[i];
  }
  return 1;
}

int f3d_liquid_particles(f3d_real *state, uint32_t count, const f3d_real *walls,
                         uint32_t length, const F3dLiquidParticleSettings *settings) {
  if (count == 0 || settings->substeps == 0) return 1;
  if (!(settings->spacing > F3D_R(0.0)) || !(settings->lattice_sum > F3D_R(0.0)) ||
      !(settings->dt > F3D_R(0.0)) || count > (1u << 24)) {
    return 0;
  }
  Solve solve;
  f3d_zero(&solve, sizeof solve);
  solve.s = settings;
  solve.k = kernels(settings->spacing);
  solve.n = count;
  Wall *read = NULL;
  if (!read_walls(walls, length, &read, &solve.wall_count)) return 0;
  solve.walls = read;
  const size_t vec = (size_t)count * sizeof(F3dVec3);
  const size_t real = (size_t)count * sizeof(f3d_real);
  solve.x = (F3dVec3 *)f3d_alloc(vec);
  solve.v = (F3dVec3 *)f3d_alloc(vec);
  solve.p = (F3dVec3 *)f3d_alloc(vec);
  solve.delta = (F3dVec3 *)f3d_alloc(vec);
  solve.normal = (F3dVec3 *)f3d_alloc(vec);
  solve.lambda = (f3d_real *)f3d_alloc(real);
  solve.density = (f3d_real *)f3d_alloc(real);
  int ok = solve.x != NULL && solve.v != NULL && solve.p != NULL && solve.delta != NULL &&
           solve.normal != NULL && solve.lambda != NULL && solve.density != NULL;
  if (ok) {
    for (uint32_t i = 0; i < count; i++) {
      const f3d_real *in = state + (size_t)i * F3D_LIQUID_PARTICLE_FLOATS;
      solve.x[i] = f3d_v3(in[0], in[1], in[2]);
      solve.v[i] = f3d_v3(in[3], in[4], in[5]);
    }
    for (uint32_t sub = 0; sub < settings->substeps && ok; sub++) ok = substep(&solve);
  }
  if (ok) {
    for (uint32_t i = 0; i < count; i++) {
      f3d_real *out = state + (size_t)i * F3D_LIQUID_PARTICLE_FLOATS;
      out[0] = solve.x[i].x;
      out[1] = solve.x[i].y;
      out[2] = solve.x[i].z;
      out[3] = solve.v[i].x;
      out[4] = solve.v[i].y;
      out[5] = solve.v[i].z;
    }
  }
  f3d_free(solve.x);
  f3d_free(solve.v);
  f3d_free(solve.p);
  f3d_free(solve.delta);
  f3d_free(solve.normal);
  f3d_free(solve.lambda);
  f3d_free(solve.density);
  f3d_free(read);
  return ok;
}

/* ------------------------------------------------------------ parcels */

int f3d_liquid_parcels(f3d_real *parcels, uint32_t count, const f3d_real *walls,
                       uint32_t length, const F3dLiquidStreamSettings *settings) {
  Wall *read = NULL;
  uint32_t wall_count = 0;
  if (!read_walls(walls, length, &read, &wall_count)) return 0;
  const f3d_real dt = settings->dt;
  const F3dVec3 g = f3d_v3(settings->gravity[0], settings->gravity[1], settings->gravity[2]);
  for (uint32_t i = 0; i < count; i++) {
    f3d_real *r = parcels + (size_t)i * F3D_LIQUID_PARCEL_FLOATS;
    F3dVec3 position = f3d_v3(r[0], r[1], r[2]);
    F3dVec3 velocity = f3d_madd(f3d_v3(r[3], r[4], r[5]), g, dt);
    const F3dVec3 previous = position;
    const f3d_real volume = r[9], emitted_in = r[10];
    const f3d_real rho = r[14], sigma = r[15], mu = r[16];
    int on_wall = r[13] != F3D_R(0.0);
    r[11] += dt;
    const f3d_real speed = f3d_sqrt(f3d_dot(velocity, velocity));
    const f3d_real section = volume / (f3d_max(speed, F3D_R(1e-6)) * emitted_in);
    const f3d_real radius = f3d_sqrt(section / F3D_PI);
    int touched = 0;
    /* In pieces no longer than its own radius, held by the walls after
     * each. */
    const uint32_t pieces = pieces_for(speed * dt / radius, 16u);
    for (uint32_t k = 0; k < pieces; k++) {
      position = f3d_madd(position, velocity, dt / (f3d_real)pieces);
      for (uint32_t w = 0; w < wall_count; w++) {
        F3dVec3 n;
        f3d_real depth;
        if (!touch(&read[w], position, radius, &n, &depth)) continue;
        position = f3d_madd(position, n, depth);
        const f3d_real into = f3d_dot(velocity, n);
        if (into < F3D_R(0.0)) velocity = f3d_madd(velocity, n, -into);
        on_wall = 1;
        touched = 1;
      }
    }
    /* Off the wall this step: held while surface tension outweighs its
     * inertia. */
    if (on_wall && !touched) {
      const f3d_real contact = F3D_R(0.1) * radius;
      const f3d_real reach = F3D_R(2.0) * radius;
      int held = 0;
      for (uint32_t w = 0; w < wall_count && !held; w++) {
        F3dVec3 n;
        f3d_real depth;
        held = touch(&read[w], position, radius + contact, &n, &depth);
      }
      const f3d_real cling =
          f3d_sqrt(settings->cling / f3d_max(F3D_R(2.0) * radius, F3D_R(1e-9)));
      if (!held && f3d_sqrt(f3d_dot(velocity, velocity)) < cling) {
        for (uint32_t w = 0; w < wall_count; w++) {
          F3dVec3 n;
          f3d_real depth;
          if (!touch(&read[w], position, radius + reach, &n, &depth)) continue;
          position = f3d_madd(position, n, depth - reach);
          const f3d_real away = f3d_dot(velocity, n);
          if (away > F3D_R(0.0)) velocity = f3d_madd(velocity, n, -away);
          held = 1;
          break;
        }
      }
      on_wall = held;
    }
    /* Weber's growth of the ripples on it, at its own diameter. */
    if (!on_wall) {
      const f3d_real d = F3D_R(2.0) * radius;
      const f3d_real tau = f3d_sqrt(rho * d * d * d / sigma) + F3D_R(3.0) * mu * d / sigma;
      r[12] += dt / tau;
    }
    r[0] = position.x;
    r[1] = position.y;
    r[2] = position.z;
    r[3] = velocity.x;
    r[4] = velocity.y;
    r[5] = velocity.z;
    r[6] = previous.x;
    r[7] = previous.y;
    r[8] = previous.z;
    r[13] = on_wall ? F3D_R(1.0) : F3D_R(0.0);
  }
  f3d_free(read);
  return 1;
}

/* -------------------------------------------------------------- modes */

static double dtanh(double x) {
  if (x > 20.0) return 1.0;
  const double e = dexp(-2.0 * x);
  return (1.0 - e) / (1.0 + e);
}

/* Stephens and Dodge's damping ratio for the first mode of a round vessel
 * of [radius], liquid [depth] deep. */
static double stephens(double nu, double g, double radius, double depth) {
  const double r = dmax(radius, 1e-6);
  const double ratio = 1.84 * depth / r;
  const double sinh = 0.5 * (dexp(ratio) - dexp(-ratio));
  const double cosh = 0.5 * (dexp(ratio) + dexp(-ratio));
  const double shallow =
      ratio > 30.0 ? 0.0 : 0.318 / dmax(sinh, 1e-9) * (1.0 + (1.0 - depth / r) / cosh);
  return 0.83 * dsqrt(nu / dsqrt(g * r * r * r)) * (1.0 + shallow);
}

typedef struct Waves {
  double g;
  double tension;
  double depth;
} Waves;

static double omega(const Waves *w, double k) {
  return dsqrt(dmax((w->g * k + w->tension * k * k * k) * dtanh(k * w->depth), 0.0));
}

void f3d_liquid_modes(f3d_real *modes, uint32_t count, const F3dLiquidWaveSettings *settings) {
  if (count == 0) return;
  const double dt = (double)settings->dt;
  const double nu = (double)settings->kinematic_viscosity;
  Waves waves;
  waves.g = (double)settings->g;
  waves.tension = (double)settings->tension;
  waves.depth = dmax((double)settings->depth, 1e-6);
  const double pi = 3.14159265358979323846;
  const double w1 = omega(&waves, dsqrt((double)modes[0]));
  const double radius = dsqrt((double)settings->area / pi);
  const double boundary = stephens(nu, waves.g, radius, waves.depth) * w1;
  for (uint32_t i = 0; i < count; i++) {
    f3d_real *m = modes + (size_t)i * F3D_LIQUID_MODE_FLOATS;
    const double k = dsqrt((double)m[0]);
    const double w = omega(&waves, k);
    const double decay = boundary * dsqrt(w / dmax(w1, 1e-9)) + 2.0 * nu * k * k;
    const double wd = dsqrt(dmax(w * w - decay * decay, 1e-12));
    double s, c;
    dsincos(wd * dt, &s, &c);
    const double e = dexp(-decay * dt);
    const double a = (double)m[2];
    const double v = (double)m[3];
    const double b = (v + decay * a) / wd;
    double amplitude = e * (a * c + b * s);
    double rate = e * (v * c - (decay * b + a * wd) * s);
    /* No higher than a fourteenth of its wavelength: Stokes' limit. */
    const double peak = dabs(amplitude) * (double)m[1];
    const double most = 2.0 * pi / (14.0 * dmax(k, 1e-9));
    if (peak > most) {
      amplitude *= most / peak;
      rate *= most / peak;
    }
    m[2] = (f3d_real)amplitude;
    m[3] = (f3d_real)rate;
    m[4] = (f3d_real)(w * w);
    m[5] = (f3d_real)decay;
  }
}

/* -------------------------------------------------------------- pipes */

void f3d_liquid_pipes(f3d_real *pipes, uint32_t count, f3d_real dt_real) {
  const double pi = 3.14159265358979323846;
  const double dt = (double)dt_real;
  for (uint32_t i = 0; i < count; i++) {
    f3d_real *r = pipes + (size_t)i * F3D_LIQUID_PIPE_FLOATS;
    double q = (double)r[0];
    double drive = (double)r[1];
    const double head0 = (double)r[2], head1 = (double)r[3];
    const double radius = (double)r[6], length = (double)r[7];
    const double rho = (double)r[8], mu = (double)r[9], loss = (double)r[10];
    const double a = pi * radius * radius;
    /* Air cannot be pushed through. */
    if (head0 <= 0.0 && q > 0.0) q = 0.0;
    if (head1 <= 0.0 && q < 0.0) q = 0.0;
    const double inertance = rho * (length / a + dmax(head0, 0.0) / dmax((double)r[4], a) +
                                    dmax(head1, 0.0) / dmax((double)r[5], a));
    const double viscous = 8.0 * mu * length / (pi * (radius * radius * radius * radius));
    const double quadratic = loss * rho * dabs(q) / (2.0 * a * a);
    if (head0 <= 0.0 && drive > 0.0) drive = 0.0;
    if (head1 <= 0.0 && drive < 0.0) drive = 0.0;
    /* Friction taken implicitly: stable at any step. */
    r[0] = (f3d_real)((q + dt * drive / inertance) / (1.0 + dt * (viscous + quadratic) / inertance));
  }
}

/* ------------------------------------------------------------- floats */

/* White's drag coefficient of a sphere at Reynolds number [re]. */
static double sphere_drag(double re) {
  if (re <= 0.0) return 0.0;
  return 24.0 / re + 6.0 / (1.0 + dsqrt(re)) + 0.4;
}

int f3d_liquid_floats(f3d_real *bodies, uint32_t body_count, const f3d_real *pushes,
                      uint32_t count, const F3dLiquidFloatSettings *settings) {
  for (uint32_t i = 0; i < count; i++) {
    const f3d_real *r = pushes + (size_t)i * F3D_LIQUID_PUSH_FLOATS;
    if (!(r[0] >= F3D_R(0.0)) || !(r[0] < (f3d_real)body_count) ||
        (f3d_real)(uint32_t)r[0] != r[0] || !(r[1] >= F3D_R(0.0)) ||
        !(r[1] <= (f3d_real)F3D_LIQUID_OTHER) || (f3d_real)(uint32_t)r[1] != r[1]) {
      return 0;
    }
  }
  const double pi = 3.14159265358979323846;
  const double dt = (double)settings->dt;
  const double g[3] = {(double)settings->gravity[0], (double)settings->gravity[1],
                       (double)settings->gravity[2]};
  for (uint32_t i = 0; i < count; i++) {
    const f3d_real *r = pushes + (size_t)i * F3D_LIQUID_PUSH_FLOATS;
    f3d_real *b = bodies + (size_t)(uint32_t)r[0] * F3D_LIQUID_BODY_FLOATS;
    const uint32_t kind = (uint32_t)r[1];
    const double sa = (double)r[2], sb = (double)r[3], sc = (double)r[4];
    const double under = (double)r[5], rho = (double)r[6], mu = (double)r[7];
    const double inverse_mass = (double)b[3];
    /* Archimedes, as an impulse. */
    double v[3];
    for (int k = 0; k < 3; k++) v[k] = (double)b[k] - g[k] * rho * under * dt * inverse_mass;
    const double speed = dsqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    if (speed > 1e-9) {
      const double dx = v[0] / speed, dy = v[1] / speed, dz = v[2] / speed;
      double area = 0.0, whole = 1.0;
      switch (kind) {
        case F3D_LIQUID_SPHERE:
          area = pi * sa * sa;
          whole = 4.0 / 3.0 * pi * sa * sa * sa;
          break;
        case F3D_LIQUID_BOX:
          area = 4.0 * (sb * sc * dabs(dx) + sa * sc * dabs(dy) + sa * sb * dabs(dz));
          whole = 8.0 * sa * sb * sc;
          break;
        case F3D_LIQUID_CAPSULE:
          area = pi * sa * sa + 4.0 * sa * sb * dsqrt(dmax(1.0 - dy * dy, 0.0));
          whole = pi * sa * sa * (2.0 * sb + 4.0 / 3.0 * sa);
          break;
        default:
          break;
      }
      const double share = whole > 0.0 ? dmax(0.0, under / whole < 1.0 ? under / whole : 1.0) : 0.0;
      const double diameter = dsqrt(4.0 * area / pi);
      const double re = rho * speed * diameter / mu;
      const double k = 0.5 * rho * sphere_drag(re) * area * share * speed * inverse_mass;
      /* Gravity taken into the implicit solve and back out: the body's own
       * step adds it after. */
      for (int c = 0; c < 3; c++) v[c] = (v[c] + g[c] * dt) / (1.0 + k * dt) - g[c] * dt;
    }
    for (int c = 0; c < 3; c++) b[c] = (f3d_real)v[c];
  }
  return 1;
}
