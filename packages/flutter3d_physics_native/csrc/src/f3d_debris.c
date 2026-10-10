/*
 * Debris on the CPU — P9, phase 10: the reference for the GPU's visual
 * bodies, and the fallback where there is none. See f3d_physics.h for what
 * they do; the WGSL in f3d_gpu.c does the same, pass for pass.
 *
 * A substep is four passes, each reading what the last one wrote and
 * nothing it writes itself, so the GPU can run every body of a pass at
 * once:
 *
 *   1. gravity, the speed limit, and each body into its cell of the grid;
 *   2. each body counts its contacts — pairs and still shapes that touch
 *      or nearly do;
 *   3. each body sums the impulses of its contacts into a new velocity,
 *      every contact computed from the old ones, and a pair always from
 *      its lower slot's side, so both bodies get the same impulse to the
 *      bit — as many times over as the settings' iterations;
 *   4. damping, and each body moved and turned.
 *
 * The impulse of a contact: it is let close by no more than its gap, and
 * pushed apart at four fifths of its depth past the slop a substep, up to
 * 3 m/s;
 * faster than 1 m/s it bounces at the restitution; friction takes the
 * slide up to μ times the push. Every body counts as its mass divided
 * among its contacts — mass splitting, which keeps a Jacobi heap from
 * blowing up.
 *
 * Pushing the overlap out apart from the velocity (a split impulse) was
 * tried and is worse here: Jacobi leaves a deep heap a little velocity
 * downwards each substep, and only a push in the velocity takes it back.
 */
#include "f3d_internal.h"

typedef struct Body {
  F3dVec3 position;
  f3d_real radius;
  F3dVec3 velocity;
  f3d_real inv_mass;
  F3dVec3 spin;
  f3d_real inv_inertia;
  F3dQuat turn;
} Body;

typedef struct Still {
  /* A plane: normal and offset. A box: centre and nought. */
  f3d_real a[4];
  /* A plane: noughts. A box: half extents and one. */
  f3d_real b[4];
} Still;

struct F3dDebris {
  Body *bodies;
  /* Pass 3's velocities and spins, applied in pass 4. */
  F3dVec3 *new_velocity;
  F3dVec3 *new_spin;
  uint32_t *contacts;
  /* The grid: each cell's first body, and each body's next in its cell;
   * NONE ends a list. */
  uint32_t *cell_head;
  uint32_t *next_in_cell;
  uint32_t cells;
  uint32_t capacity;
  uint32_t next;
  f3d_real max_radius;
  Still statics[F3D_DEBRIS_MAX_STATICS];
  uint32_t static_count;
};

#define NONE 0xFFFFFFFFu

#define SLOP F3D_R(0.0005)
#define PUSH F3D_R(0.8)
#define MAX_PUSH F3D_R(3.0)
#define BOUNCE_SPEED F3D_R(1.0)

F3dDebris *f3d_debris_create(uint32_t capacity) {
  if (capacity == 0 || capacity > (1u << 22)) return NULL;
  F3dDebris *d = (F3dDebris *)f3d_alloc(sizeof(F3dDebris));
  if (d == NULL) return NULL;
  f3d_zero(d, sizeof(F3dDebris));
  uint32_t cells = 1;
  while (cells < capacity * 2u) cells <<= 1;
  d->cells = cells;
  d->capacity = capacity;
  d->bodies = (Body *)f3d_alloc((size_t)capacity * sizeof(Body));
  d->new_velocity = (F3dVec3 *)f3d_alloc((size_t)capacity * sizeof(F3dVec3));
  d->new_spin = (F3dVec3 *)f3d_alloc((size_t)capacity * sizeof(F3dVec3));
  d->contacts = (uint32_t *)f3d_alloc((size_t)capacity * sizeof(uint32_t));
  d->cell_head = (uint32_t *)f3d_alloc((size_t)cells * sizeof(uint32_t));
  d->next_in_cell = (uint32_t *)f3d_alloc((size_t)capacity * sizeof(uint32_t));
  if (d->bodies == NULL || d->new_velocity == NULL || d->new_spin == NULL ||
      d->contacts == NULL || d->cell_head == NULL || d->next_in_cell == NULL) {
    f3d_debris_destroy(d);
    return NULL;
  }
  f3d_zero(d->bodies, (size_t)capacity * sizeof(Body));
  for (uint32_t i = 0; i < capacity; i++) d->bodies[i].turn.w = F3D_R(1.0);
  return d;
}

void f3d_debris_destroy(F3dDebris *d) {
  if (d == NULL) return;
  f3d_free(d->bodies);
  f3d_free(d->new_velocity);
  f3d_free(d->new_spin);
  f3d_free(d->contacts);
  f3d_free(d->cell_head);
  f3d_free(d->next_in_cell);
  f3d_free(d);
}

uint32_t f3d_debris_capacity(const F3dDebris *d) { return d->capacity; }

uint32_t f3d_debris_add(F3dDebris *d, const f3d_real *data, uint32_t count) {
  const uint32_t first = d->next;
  for (uint32_t i = 0; i < count; i++) {
    const f3d_real *in = data + (size_t)i * F3D_DEBRIS_INPUT_FLOATS;
    Body *b = &d->bodies[d->next];
    f3d_zero(b, sizeof(Body));
    b->turn.w = F3D_R(1.0);
    const f3d_real r = in[6], m = in[7];
    if (f3d_finite(r) && f3d_finite(m) && r > F3D_R(0.0) && m > F3D_R(0.0)) {
      b->position = f3d_v3(in[0], in[1], in[2]);
      b->velocity = f3d_v3(in[3], in[4], in[5]);
      b->radius = r;
      b->inv_mass = F3D_R(1.0) / m;
      /* A solid ball: I = 2/5 m r². */
      b->inv_inertia = F3D_R(2.5) / (m * r * r);
      if (r > d->max_radius) d->max_radius = r;
    }
    d->next = (d->next + 1u) % d->capacity;
  }
  return first;
}

int f3d_debris_set_statics(F3dDebris *d, const f3d_real *data, uint32_t count) {
  if (count > F3D_DEBRIS_MAX_STATICS) return 0;
  for (uint32_t i = 0; i < count; i++) {
    for (int k = 0; k < 4; k++) {
      d->statics[i].a[k] = data[i * 8u + (uint32_t)k];
      d->statics[i].b[k] = data[i * 8u + 4u + (uint32_t)k];
    }
  }
  d->static_count = count;
  return 1;
}

/* The cell a coordinate falls in: floor(x / cell), held to ±10⁹. */
static int32_t cell_coord(f3d_real x, f3d_real inv_cell) {
  const f3d_real v = f3d_clamp(x * inv_cell, F3D_R(-1e9), F3D_R(1e9));
  int32_t t = (int32_t)v;
  if ((f3d_real)t > v) t--;
  return t;
}

static uint32_t cell_hash(int32_t x, int32_t y, int32_t z, uint32_t cells) {
  return (((uint32_t)x * 73856093u) ^ ((uint32_t)y * 19349663u) ^
          ((uint32_t)z * 83492791u)) &
         (cells - 1u);
}

/* What a contact needs: the normal from the other towards this body, the
 * gap along it (less than nought when overlapping), and where it touches,
 * from each centre. */
typedef struct Touch {
  F3dVec3 normal;
  f3d_real gap;
} Touch;

static Touch touch_pair(const Body *lo, const Body *hi) {
  const F3dVec3 d = f3d_sub(lo->position, hi->position);
  const f3d_real len = f3d_sqrt(f3d_dot(d, d));
  Touch t;
  t.normal = len > F3D_R(0.0) ? f3d_scale(d, F3D_R(1.0) / len) : f3d_v3(0, 1, 0);
  t.gap = len - lo->radius - hi->radius;
  return t;
}

static Touch touch_still(const Body *b, const Still *s) {
  Touch t;
  if (s->b[3] == F3D_R(0.0)) {
    t.normal = f3d_v3(s->a[0], s->a[1], s->a[2]);
    t.gap = f3d_dot(b->position, t.normal) - s->a[3] - b->radius;
    return t;
  }
  const f3d_real c[3] = {s->a[0], s->a[1], s->a[2]};
  const f3d_real p[3] = {b->position.x, b->position.y, b->position.z};
  f3d_real q[3];
  for (int k = 0; k < 3; k++) q[k] = f3d_clamp(p[k], c[k] - s->b[k], c[k] + s->b[k]);
  const F3dVec3 d = f3d_v3(p[0] - q[0], p[1] - q[1], p[2] - q[2]);
  const f3d_real len = f3d_sqrt(f3d_dot(d, d));
  if (len > F3D_R(0.0)) {
    t.normal = f3d_scale(d, F3D_R(1.0) / len);
    t.gap = len - b->radius;
    return t;
  }
  /* The centre inside: out through the nearest face. */
  int axis = 0;
  f3d_real best = s->b[0] - f3d_abs(p[0] - c[0]);
  for (int k = 1; k < 3; k++) {
    const f3d_real depth = s->b[k] - f3d_abs(p[k] - c[k]);
    if (depth < best) {
      best = depth;
      axis = k;
    }
  }
  f3d_real n[3] = {0, 0, 0};
  n[axis] = p[axis] < c[axis] ? F3D_R(-1.0) : F3D_R(1.0);
  t.normal = f3d_v3(n[0], n[1], n[2]);
  t.gap = -best - b->radius;
  return t;
}

/* The velocity of a body's surface where it touches along [n], -n r from
 * its centre. */
static F3dVec3 surface_velocity(const Body *b, F3dVec3 n, f3d_real r) {
  return f3d_add(b->velocity, f3d_cross(b->spin, f3d_scale(n, -r)));
}

/* Whether a contact counts: its gap within [reach]. By where the bodies
 * are, not how fast they go, so a substep's contacts stay the same through
 * all its impulse passes, as their counts do. */
static int active(Touch t, f3d_real reach) { return t.gap <= reach; }

/* How far a pair's contact reaches: a quarter of their radii together;
 * a still shape's, the body's radius. Closer than three of the largest
 * radii from centre to centre, so the grid's neighbours hold every pair. */
static f3d_real pair_reach(const Body *lo, const Body *hi) {
  return F3D_R(0.25) * (lo->radius + hi->radius);
}

/* The impulse on [lo] of its contact with [hi] (null for a still shape,
 * whose surface does not move), each counting [n_lo] and [n_hi] contacts:
 * nought when the contact is not active or holds without one. */
static F3dVec3 impulse(const Body *lo, uint32_t n_lo, const Body *hi,
                       uint32_t n_hi, Touch t, const F3dDebrisSettings *s,
                       f3d_real h) {
  if (!active(t, hi != NULL ? pair_reach(lo, hi) : lo->radius)) return f3d_v3(0, 0, 0);
  F3dVec3 rel = surface_velocity(lo, t.normal, lo->radius);
  if (hi != NULL) {
    rel = f3d_sub(rel, surface_velocity(hi, f3d_scale(t.normal, F3D_R(-1.0)), hi->radius));
  }
  const f3d_real vn = f3d_dot(rel, t.normal);
  f3d_real target = t.gap > F3D_R(0.0)
                        ? -t.gap / h
                        : f3d_min(f3d_max(-t.gap - SLOP, F3D_R(0.0)) * PUSH / h, MAX_PUSH);
  if (vn < -BOUNCE_SPEED && t.gap <= SLOP) target = f3d_max(target, -s->restitution * vn);
  const f3d_real dvn = target - vn;
  if (!(dvn > F3D_R(0.0))) return f3d_v3(0, 0, 0);
  const f3d_real w_lo = lo->inv_mass * (f3d_real)n_lo;
  const f3d_real w_hi = hi != NULL ? hi->inv_mass * (f3d_real)n_hi : F3D_R(0.0);
  const f3d_real pn = dvn / (w_lo + w_hi);
  F3dVec3 p = f3d_scale(t.normal, pn);
  const F3dVec3 vt = f3d_madd(rel, t.normal, -vn);
  const f3d_real slide = f3d_sqrt(f3d_dot(vt, vt));
  if (slide > F3D_R(0.0)) {
    f3d_real k = (lo->inv_mass + lo->radius * lo->radius * lo->inv_inertia) * (f3d_real)n_lo;
    if (hi != NULL) {
      k += (hi->inv_mass + hi->radius * hi->radius * hi->inv_inertia) * (f3d_real)n_hi;
    }
    const f3d_real pt = f3d_min(slide / k, s->friction * pn);
    p = f3d_madd(p, vt, -pt / slide);
  }
  return p;
}

void f3d_debris_step(F3dDebris *d, const F3dDebrisSettings *s, f3d_real dt) {
  if (!(f3d_finite(dt) && dt > F3D_R(0.0))) return;
  const uint32_t substeps = s->substeps > 0 ? s->substeps : 1u;
  const uint32_t iterations = s->iterations > 0 ? s->iterations : 1u;
  const f3d_real h = dt / (f3d_real)substeps;
  const F3dVec3 g = f3d_v3(s->gravity[0], s->gravity[1], s->gravity[2]);
  const f3d_real cell = d->max_radius * F3D_R(3.0);
  if (!(cell > F3D_R(0.0))) return;
  const f3d_real inv_cell = F3D_R(1.0) / cell;
  const f3d_real keep_v = F3D_R(1.0) / (F3D_R(1.0) + s->linear_damping * h);
  const f3d_real keep_w = F3D_R(1.0) / (F3D_R(1.0) + s->angular_damping * h);
  for (uint32_t sub = 0; sub < substeps; sub++) {
    /* 1. Gravity, the speed limit, the grid. */
    for (uint32_t c = 0; c < d->cells; c++) d->cell_head[c] = NONE;
    for (uint32_t i = 0; i < d->capacity; i++) {
      Body *b = &d->bodies[i];
      if (!(b->radius > F3D_R(0.0))) continue;
      b->velocity = f3d_madd(b->velocity, g, h);
      const f3d_real speed2 = f3d_dot(b->velocity, b->velocity);
      if (speed2 > s->max_speed * s->max_speed) {
        b->velocity = f3d_scale(b->velocity, s->max_speed / f3d_sqrt(speed2));
      }
      const uint32_t c = cell_hash(cell_coord(b->position.x, inv_cell),
                                   cell_coord(b->position.y, inv_cell),
                                   cell_coord(b->position.z, inv_cell), d->cells);
      d->next_in_cell[i] = d->cell_head[c];
      d->cell_head[c] = i;
    }
    /* 2 and 3: each body's contacts, counted, then their impulses, as many
     * times as the settings say. */
    for (uint32_t pass = 0; pass <= iterations; pass++) {
      const int counting = pass == 0;
      /* An impulse pass after the first starts from the last one's. */
      if (pass > 1) {
        for (uint32_t i = 0; i < d->capacity; i++) {
          d->bodies[i].velocity = d->new_velocity[i];
          d->bodies[i].spin = d->new_spin[i];
        }
      }
      for (uint32_t i = 0; i < d->capacity; i++) {
        const Body *b = &d->bodies[i];
        if (!(b->radius > F3D_R(0.0))) continue;
        uint32_t count = 0;
        F3dVec3 dv = b->velocity, dw = b->spin;
        const int32_t cx = cell_coord(b->position.x, inv_cell);
        const int32_t cy = cell_coord(b->position.y, inv_cell);
        const int32_t cz = cell_coord(b->position.z, inv_cell);
        for (int32_t x = cx - 1; x <= cx + 1; x++) {
          for (int32_t y = cy - 1; y <= cy + 1; y++) {
            for (int32_t z = cz - 1; z <= cz + 1; z++) {
              for (uint32_t j = d->cell_head[cell_hash(x, y, z, d->cells)]; j != NONE;
                   j = d->next_in_cell[j]) {
                if (j == i) continue;
                const Body *o = &d->bodies[j];
                /* Another cell sharing this one's hash: met there. */
                if (cell_coord(o->position.x, inv_cell) != x ||
                    cell_coord(o->position.y, inv_cell) != y ||
                    cell_coord(o->position.z, inv_cell) != z) {
                  continue;
                }
                const Body *lo = i < j ? b : o;
                const Body *hi = i < j ? o : b;
                const Touch t = touch_pair(lo, hi);
                if (counting) {
                  if (active(t, pair_reach(lo, hi))) count++;
                  continue;
                }
                const uint32_t n_lo = d->contacts[i < j ? i : j];
                const uint32_t n_hi = d->contacts[i < j ? j : i];
                const F3dVec3 p = impulse(lo, n_lo, hi, n_hi, t, s, h);
                /* On this body, from where it touches. */
                const f3d_real sign = i < j ? F3D_R(1.0) : F3D_R(-1.0);
                const F3dVec3 n_out = f3d_scale(t.normal, sign);
                const F3dVec3 mine = f3d_scale(p, sign);
                dv = f3d_madd(dv, mine, b->inv_mass);
                dw = f3d_madd(dw, f3d_cross(f3d_scale(n_out, -b->radius), mine),
                              b->inv_inertia);
              }
            }
          }
        }
        for (uint32_t k = 0; k < d->static_count; k++) {
          const Touch t = touch_still(b, &d->statics[k]);
          if (counting) {
            if (active(t, b->radius)) count++;
            continue;
          }
          const F3dVec3 p = impulse(b, d->contacts[i], NULL, 0, t, s, h);
          dv = f3d_madd(dv, p, b->inv_mass);
          dw = f3d_madd(dw, f3d_cross(f3d_scale(t.normal, -b->radius), p), b->inv_inertia);
        }
        if (counting) {
          d->contacts[i] = count;
        } else {
          d->new_velocity[i] = dv;
          d->new_spin[i] = dw;
        }
      }
    }
    /* 4. Damping, and every body moved and turned. */
    for (uint32_t i = 0; i < d->capacity; i++) {
      Body *b = &d->bodies[i];
      if (!(b->radius > F3D_R(0.0))) continue;
      b->velocity = f3d_scale(d->new_velocity[i], keep_v);
      b->spin = f3d_scale(d->new_spin[i], keep_w);
      b->position = f3d_madd(b->position, b->velocity, h);
      const F3dVec3 w = b->spin;
      const F3dQuat q = b->turn;
      const f3d_real k = F3D_R(0.5) * h;
      F3dQuat r;
      r.x = q.x + k * (w.x * q.w + w.y * q.z - w.z * q.y);
      r.y = q.y + k * (w.y * q.w + w.z * q.x - w.x * q.z);
      r.z = q.z + k * (w.z * q.w + w.x * q.y - w.y * q.x);
      r.w = q.w - k * (w.x * q.x + w.y * q.y + w.z * q.z);
      const f3d_real len = f3d_sqrt(r.x * r.x + r.y * r.y + r.z * r.z + r.w * r.w);
      b->turn.x = r.x / len;
      b->turn.y = r.y / len;
      b->turn.z = r.z / len;
      b->turn.w = r.w / len;
    }
  }
}

uint32_t f3d_debris_read(const F3dDebris *d, f3d_real *out, uint32_t capacity) {
  const uint32_t n = capacity < d->capacity ? capacity : d->capacity;
  for (uint32_t i = 0; i < n; i++) {
    const Body *b = &d->bodies[i];
    f3d_real *o = out + (size_t)i * F3D_DEBRIS_FLOATS;
    o[0] = b->position.x;
    o[1] = b->position.y;
    o[2] = b->position.z;
    o[3] = b->turn.x;
    o[4] = b->turn.y;
    o[5] = b->turn.z;
    o[6] = b->turn.w;
    o[7] = b->radius;
  }
  return n;
}
