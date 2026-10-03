// The Position Based Fluids pair loops of `lib/src/fluid/pbf_kernels.dart`,
// in C: the same five kernels over the same flat buffers, for
// `NativePbfKernels` to call through `@Native`.
//
// **Held to the Dart reference within a tolerance, not to the bit.** The
// neighbours of a particle are summed two at a time where the compiler has
// vector extensions (clang and gcc, on NEON and SSE2 alike), which adds in
// another order than Dart's one at a time; a run is the same run to about a
// part in 10¹², not exactly. Where the world must replay to the bit, the
// Dart kernels are the ones to step it with.
//
// The constants come as one array, in this order:
//   0 h, 1 h², 2 ρ₀, 3 m, 4 norm, 5 γ, 6 rest stiffness,
//   7 poly6, 8 spiky, 9 cohesion, 10 h⁶, 11 W(0.3h).

#include <math.h>
#include <stdint.h>
#include <stdlib.h>

#if defined(__clang__) || defined(__GNUC__)
#define F3D_VECTOR 1
typedef double f3d_d2 __attribute__((vector_size(16)));
#else
#define F3D_VECTOR 0
#endif

#if defined(_WIN32)
#define F3D_EXPORT __declspec(dllexport)
#else
#define F3D_EXPORT __attribute__((visibility("default")))
#endif

enum {
  K_H = 0,
  K_H2,
  K_RHO0,
  K_MASS,
  K_NORM,
  K_GAMMA,
  K_REST_STIFFNESS,
  K_POLY6,
  K_SPIKY,
  K_COHESION,
  K_H6,
  K_WQ,
};

static inline double poly6(const double* k, double r2) {
  if (r2 >= k[K_H2]) return 0.0;
  const double d = k[K_H2] - r2;
  return k[K_POLY6] * d * d * d;
}

static inline double spiky_scale(const double* k, double r) {
  if (r <= 1e-12 || r >= k[K_H]) return 0.0;
  const double hr = k[K_H] - r;
  return k[K_SPIKY] * hr * hr / r;
}

static inline double cohesion(const double* k, double r) {
  const double h = k[K_H];
  if (r >= h || r <= 0.0) return 0.0;
  const double a = (h - r) * (h - r) * (h - r) * r * r * r;
  if (2.0 * r > h) return k[K_COHESION] * a;
  return k[K_COHESION] * (2.0 * a - k[K_H6] / 64.0);
}

#if F3D_VECTOR
// The kernel weight of two squared distances at once, a lane each.
static inline f3d_d2 poly6_2(const double* k, f3d_d2 r2) {
  const f3d_d2 h2 = {k[K_H2], k[K_H2]};
  f3d_d2 d = h2 - r2;
  d = (f3d_d2){d[0] > 0.0 ? d[0] : 0.0, d[1] > 0.0 ? d[1] : 0.0};
  const f3d_d2 c = {k[K_POLY6], k[K_POLY6]};
  return c * d * d * d;
}
#endif

F3D_EXPORT int32_t f3d_pbf_version(void) { return 5; }

// Of the rows [start] and [list], those within [radius] at [x], in order,
// into [out_start] and [out] (room for as many as [list] has).
F3D_EXPORT int32_t f3d_pbf_within(const double* x, int32_t n,
                                  const int32_t* start, const int32_t* list,
                                  double radius, int32_t* out_start,
                                  int32_t* out) {
  const double reach2 = radius * radius;
  int32_t count = 0;
  out_start[0] = 0;
  for (int32_t i = 0; i < n; i++) {
    const double xi = x[3 * i], yi = x[3 * i + 1], zi = x[3 * i + 2];
    for (int32_t q = start[i]; q < start[i + 1]; q++) {
      const int32_t j = list[q];
      const double ex = x[3 * j] - xi, ey = x[3 * j + 1] - yi,
                   ez = x[3 * j + 2] - zi;
      if (ex * ex + ey * ey + ez * ez < reach2) out[count++] = j;
    }
    out_start[i + 1] = count;
  }
  return count;
}

// ----------------------------------------------------------- neighbours

static int64_t pack_cell(int64_t x, int64_t y, int64_t z) {
  const int64_t span = (int64_t)1 << 17, half = (int64_t)1 << 16;
#define F3D_WRAP(v) ((((v) + half) % span + span) % span)
  return (F3D_WRAP(x) * span + F3D_WRAP(y)) * span + F3D_WRAP(z);
#undef F3D_WRAP
}

typedef struct {
  int64_t key;
  int64_t index;
} f3d_cell_entry;

static int compare_entries(const void* a, const void* b) {
  const f3d_cell_entry* p = (const f3d_cell_entry*)a;
  const f3d_cell_entry* q = (const f3d_cell_entry*)b;
  if (p->key != q->key) return p->key < q->key ? -1 : 1;
  return p->index < q->index ? -1 : (p->index > q->index ? 1 : 0);
}

// The neighbours of each particle within h, as compressed rows, the same
// order as the Dart kernel's: cells by x, y, z from −1 to 1, within a cell
// by index. Writes at most [capacity] into [list] and returns how many there
// are: called again with room for that when it is more. [scratch] holds
// 5·n int64s, the caller's own: nothing here is shared between calls, so
// two isolates may step two fluids at once.
//
// **Read in the cells' order, not the particles'.** Of the 27 cells' worth
// of candidates around a particle only one in six or seven is within h,
// and each was read through its index from wherever it lay in [x]: nearly
// every read missed the cache, and the search cost twice all the loops
// over pairs together. The positions are copied out in the sorted order,
// so a cell's candidates are read one after the other.
F3D_EXPORT int32_t f3d_pbf_neighbours(const double* x, int32_t n,
                                      double radius, int32_t* start,
                                      int32_t* list, int32_t capacity,
                                      int64_t* scratch) {
  const double h = radius;
  const double reach2 = h * h;
  // Two words an entry in the scratch's first 2·n, the positions in sorted
  // order in its last 3·n.
  f3d_cell_entry* entries = (f3d_cell_entry*)scratch;
  double* sorted = (double*)(scratch + 2 * n);
  for (int32_t i = 0; i < n; i++) {
    entries[i].key = pack_cell((int64_t)floor(x[3 * i] / h),
                               (int64_t)floor(x[3 * i + 1] / h),
                               (int64_t)floor(x[3 * i + 2] / h));
    entries[i].index = i;
  }
  qsort(entries, (size_t)n, sizeof(f3d_cell_entry), compare_entries);
  for (int32_t q = 0; q < n; q++) {
    const int64_t j = entries[q].index;
    sorted[3 * q] = x[3 * j];
    sorted[3 * q + 1] = x[3 * j + 1];
    sorted[3 * q + 2] = x[3 * j + 2];
  }
  int32_t count = 0;
  start[0] = 0;
  for (int32_t i = 0; i < n; i++) {
    const double xi = x[3 * i], yi = x[3 * i + 1], zi = x[3 * i + 2];
    const int64_t cx = (int64_t)floor(xi / h), cy = (int64_t)floor(yi / h),
                  cz = (int64_t)floor(zi / h);
    for (int64_t dx = -1; dx <= 1; dx++) {
      for (int64_t dy = -1; dy <= 1; dy++) {
        // The three cells from z − 1 to z + 1 are three keys in a row, z
        // being the key's last part: one search finds the first, and the
        // rest follow it in the sorted entries, in the order three searches
        // gave. Where z wraps round they are not in a row, and each is
        // searched for.
        const int64_t first = pack_cell(cx + dx, cy + dy, cz - 1);
        const int64_t last = pack_cell(cx + dx, cy + dy, cz + 1);
        const int32_t runs = last == first + 2 ? 1 : 3;
        for (int32_t run = 0; run < runs; run++) {
          const int64_t from =
              runs == 1 ? first : pack_cell(cx + dx, cy + dy, cz - 1 + run);
          const int64_t to = runs == 1 ? last : from;
          int32_t lo = 0, hi = n;
          while (lo < hi) {
            const int32_t mid = (lo + hi) >> 1;
            if (entries[mid].key < from) {
              lo = mid + 1;
            } else {
              hi = mid;
            }
          }
          for (int32_t q = lo; q < n && entries[q].key <= to; q++) {
            const double ex = sorted[3 * q] - xi, ey = sorted[3 * q + 1] - yi,
                         ez = sorted[3 * q + 2] - zi;
            if (ex * ex + ey * ey + ez * ez >= reach2) continue;
            const int32_t j = (int32_t)entries[q].index;
            if (j == i) continue;
            if (count < capacity) list[count] = j;
            count++;
          }
        }
      }
    }
    start[i + 1] = count;
  }
  return count;
}

F3D_EXPORT void f3d_pbf_densities(const double* x, const int32_t* start,
                                  const int32_t* list, int32_t n,
                                  const double* k, double* density) {
  const double self = poly6(k, 0.0);
  for (int32_t i = 0; i < n; i++) {
    const double xi = x[3 * i], yi = x[3 * i + 1], zi = x[3 * i + 2];
    int32_t q = start[i];
    const int32_t end = start[i + 1];
    double w = self;
#if F3D_VECTOR
    f3d_d2 acc = {0.0, 0.0};
    for (; q + 2 <= end; q += 2) {
      const int32_t a = list[q], b = list[q + 1];
      const f3d_d2 dx = {xi - x[3 * a], xi - x[3 * b]};
      const f3d_d2 dy = {yi - x[3 * a + 1], yi - x[3 * b + 1]};
      const f3d_d2 dz = {zi - x[3 * a + 2], zi - x[3 * b + 2]};
      acc += poly6_2(k, dx * dx + dy * dy + dz * dz);
    }
    w += acc[0] + acc[1];
#endif
    for (; q < end; q++) {
      const int32_t j = list[q];
      const double dx = xi - x[3 * j], dy = yi - x[3 * j + 1],
                   dz = zi - x[3 * j + 2];
      w += poly6(k, dx * dx + dy * dy + dz * dz);
    }
    density[i] = k[K_RHO0] * w * k[K_NORM];
  }
}

F3D_EXPORT void f3d_pbf_normals(const double* x, const int32_t* start,
                                const int32_t* list, int32_t n,
                                const double* k, const double* density,
                                double* normal) {
  for (int32_t i = 0; i < n; i++) {
    const double xi = x[3 * i], yi = x[3 * i + 1], zi = x[3 * i + 2];
    double nx = 0.0, ny = 0.0, nz = 0.0;
    for (int32_t q = start[i]; q < start[i + 1]; q++) {
      const int32_t j = list[q];
      const double dx = xi - x[3 * j], dy = yi - x[3 * j + 1],
                   dz = zi - x[3 * j + 2];
      const double f = spiky_scale(k, sqrt(dx * dx + dy * dy + dz * dz)) *
                       k[K_H] * k[K_MASS] / density[j];
      nx += dx * f;
      ny += dy * f;
      nz += dz * f;
    }
    normal[3 * i] = nx;
    normal[3 * i + 1] = ny;
    normal[3 * i + 2] = nz;
  }
}

F3D_EXPORT void f3d_pbf_forces(const double* x, const int32_t* start,
                               const int32_t* list, int32_t n,
                               const double* k, const double* density,
                               const double* normal, const double* before,
                               const double* after, double* v, double dt) {
  const double rho0 = k[K_RHO0];
  for (int32_t i = 0; i < n; i++) {
    const double xi = x[3 * i], yi = x[3 * i + 1], zi = x[3 * i + 2];
    double ax = before[3 * i], ay = before[3 * i + 1], az = before[3 * i + 2];
    for (int32_t q = start[i]; q < start[i + 1]; q++) {
      const int32_t j = list[q];
      const double dx = xi - x[3 * j], dy = yi - x[3 * j + 1],
                   dz = zi - x[3 * j + 2];
      const double r = sqrt(dx * dx + dy * dy + dz * dz);
      if (r < 1e-12) continue;
      const double kk = 2.0 * rho0 / (density[i] + density[j]);
      const double c = -kk * k[K_GAMMA] * k[K_MASS] * cohesion(k, r) / r;
      const double t = -kk * k[K_GAMMA];
      ax += dx * c + (normal[3 * i] - normal[3 * j]) * t;
      ay += dy * c + (normal[3 * i + 1] - normal[3 * j + 1]) * t;
      az += dz * c + (normal[3 * i + 2] - normal[3 * j + 2]) * t;
    }
    ax += after[3 * i];
    ay += after[3 * i + 1];
    az += after[3 * i + 2];
    v[3 * i] += ax * dt;
    v[3 * i + 1] += ay * dt;
    v[3 * i + 2] += az * dt;
  }
}

F3D_EXPORT void f3d_pbf_lambdas(const double* p, const int32_t* start,
                                const int32_t* list, int32_t n,
                                const double* k, double* lambda) {
  const double norm = k[K_NORM];
  const double self = poly6(k, 0.0);
  for (int32_t i = 0; i < n; i++) {
    const double xi = p[3 * i], yi = p[3 * i + 1], zi = p[3 * i + 2];
    double w = self, sum2 = 0.0, gx = 0.0, gy = 0.0, gz = 0.0;
    for (int32_t q = start[i]; q < start[i + 1]; q++) {
      const int32_t j = list[q];
      const double dx = xi - p[3 * j], dy = yi - p[3 * j + 1],
                   dz = zi - p[3 * j + 2];
      const double r2 = dx * dx + dy * dy + dz * dz;
      w += poly6(k, r2);
      const double f = spiky_scale(k, sqrt(r2)) * norm;
      sum2 += r2 * f * f;
      gx += dx * f;
      gy += dy * f;
      gz += dz * f;
    }
    sum2 += gx * gx + gy * gy + gz * gz;
    double c = w * norm - 1.0;
    if (c < 0.0) c = 0.0;
    lambda[i] = -c / (sum2 + 1e-6 * norm * norm / (k[K_H] * k[K_H]));
  }
}

F3D_EXPORT void f3d_pbf_deltas(const double* p, const int32_t* start,
                               const int32_t* list, int32_t n,
                               const double* k, const double* lambda,
                               double* delta) {
  const double norm = k[K_NORM];
  for (int32_t i = 0; i < n; i++) {
    const double xi = p[3 * i], yi = p[3 * i + 1], zi = p[3 * i + 2];
    double sx = 0.0, sy = 0.0, sz = 0.0;
    for (int32_t q = start[i]; q < start[i + 1]; q++) {
      const int32_t j = list[q];
      const double dx = xi - p[3 * j], dy = yi - p[3 * j + 1],
                   dz = zi - p[3 * j + 2];
      const double r2 = dx * dx + dy * dy + dz * dz;
      const double ratio = poly6(k, r2) / k[K_WQ];
      const double corr =
          -0.02 * ratio * ratio * ratio * ratio / k[K_REST_STIFFNESS];
      const double f =
          spiky_scale(k, sqrt(r2)) * (lambda[i] + lambda[j] + corr) * norm;
      sx += dx * f;
      sy += dy * f;
      sz += dz * f;
    }
    delta[3 * i] = sx;
    delta[3 * i + 1] = sy;
    delta[3 * i + 2] = sz;
  }
}

F3D_EXPORT void f3d_pbf_viscosity(const double* p, const double* v,
                                  const int32_t* start, const int32_t* list,
                                  int32_t n, const double* k, double share,
                                  double* smoothed) {
  const double norm = k[K_NORM];
  for (int32_t i = 0; i < n; i++) {
    const double xi = p[3 * i], yi = p[3 * i + 1], zi = p[3 * i + 2];
    const double vx = v[3 * i], vy = v[3 * i + 1], vz = v[3 * i + 2];
    double sx = vx, sy = vy, sz = vz;
    for (int32_t q = start[i]; q < start[i + 1]; q++) {
      const int32_t j = list[q];
      const double dx = xi - p[3 * j], dy = yi - p[3 * j + 1],
                   dz = zi - p[3 * j + 2];
      const double w = poly6(k, dx * dx + dy * dy + dz * dz) * norm * share;
      sx += (v[3 * j] - vx) * w;
      sy += (v[3 * j + 1] - vy) * w;
      sz += (v[3 * j + 2] - vz) * w;
    }
    smoothed[3 * i] = sx;
    smoothed[3 * i + 1] = sy;
    smoothed[3 * i + 2] = sz;
  }
}
