// The pair loops of `pbf_kernels.c`, F3D_W neighbours at a time: included
// once for each width, with F3D_W and F3D_NAME(name) set by the includer
// (and, for the AVX2 width on x86-64, inside a target that allows it).
//
// Each loop takes the neighbours F3D_W at a time, a lane each, and the last
// few one at a time as the scalar loop does; the lanes are summed at the end
// in order. The sums so come out in another order than the scalar loop's,
// and so differ from it, and from Dart, in the last few bits.
//
// Branches become masks: a lane a kernel is nil for (past h, or at the same
// point) is computed anyway, inf or NaN as may be, and then cleared by
// and-ing its bits with the mask.

typedef double F3D_NAME(vd) __attribute__((vector_size(F3D_W * 8)));
typedef long long F3D_NAME(vi) __attribute__((vector_size(F3D_W * 8)));
#define VD F3D_NAME(vd)
#define VI F3D_NAME(vi)
// Lanes of [a] where [m] is set, nil elsewhere; [a] where set, [b] where not.
#define KEEP(m, a) ((VD)((VI)(a) & (m)))
#define PICK(m, a, b) ((VD)(((VI)(a) & (m)) | ((VI)(b) & ~(m))))

// Component [c] of the points [list] names from [q] on, a lane each.
static inline VD F3D_NAME(gather3)(const double* a, const int32_t* list,
                                   int32_t q, int c) {
  VD r;
  for (int l = 0; l < F3D_W; l++) r[l] = a[3 * list[q + l] + c];
  return r;
}

static inline VD F3D_NAME(gather1)(const double* a, const int32_t* list,
                                   int32_t q) {
  VD r;
  for (int l = 0; l < F3D_W; l++) r[l] = a[list[q + l]];
  return r;
}

static inline VD F3D_NAME(root)(VD r2) {
  VD r;
  for (int l = 0; l < F3D_W; l++) r[l] = sqrt(r2[l]);
  return r;
}

static inline double F3D_NAME(sum)(VD v) {
  double s = 0.0;
  for (int l = 0; l < F3D_W; l++) s += v[l];
  return s;
}

static inline VD F3D_NAME(poly6)(const double* k, VD r2) {
  const VD d = k[K_H2] - r2;
  return KEEP((VI)(d > 0.0), k[K_POLY6] * d * d * d);
}

static inline VD F3D_NAME(spiky)(const double* k, VD r) {
  const VD hr = k[K_H] - r;
  const VI live = (VI)(r > 1e-12) & (VI)(r < k[K_H]);
  return KEEP(live, k[K_SPIKY] * hr * hr / r);
}

static inline VD F3D_NAME(cohesion)(const double* k, VD r) {
  const double h = k[K_H];
  const VD hr = h - r;
  const VD a = hr * hr * hr * r * r * r;
  const VI live = (VI)(r < h) & (VI)(r > 0.0);
  const VI far = (VI)(2.0 * r > h);
  const VD value =
      PICK(far, k[K_COHESION] * a, k[K_COHESION] * (2.0 * a - k[K_H6] / 64.0));
  return KEEP(live, value);
}

static void F3D_NAME(densities)(const double* x, const int32_t* start,
                                const int32_t* list, int32_t n,
                                const double* k, double* density) {
  const double self = poly6(k, 0.0);
  for (int32_t i = 0; i < n; i++) {
    const double xi = x[3 * i], yi = x[3 * i + 1], zi = x[3 * i + 2];
    int32_t q = start[i];
    const int32_t end = start[i + 1];
    VD acc = {0.0};
    for (; q + F3D_W <= end; q += F3D_W) {
      const VD dx = xi - F3D_NAME(gather3)(x, list, q, 0);
      const VD dy = yi - F3D_NAME(gather3)(x, list, q, 1);
      const VD dz = zi - F3D_NAME(gather3)(x, list, q, 2);
      acc += F3D_NAME(poly6)(k, dx * dx + dy * dy + dz * dz);
    }
    double w = self + F3D_NAME(sum)(acc);
    for (; q < end; q++) {
      const int32_t j = list[q];
      const double dx = xi - x[3 * j], dy = yi - x[3 * j + 1],
                   dz = zi - x[3 * j + 2];
      w += poly6(k, dx * dx + dy * dy + dz * dz);
    }
    density[i] = k[K_RHO0] * w * k[K_NORM];
  }
}

static void F3D_NAME(normals)(const double* x, const int32_t* start,
                              const int32_t* list, int32_t n,
                              const double* k, const double* density,
                              double* normal) {
  const double hm = k[K_H] * k[K_MASS];
  for (int32_t i = 0; i < n; i++) {
    const double xi = x[3 * i], yi = x[3 * i + 1], zi = x[3 * i + 2];
    int32_t q = start[i];
    const int32_t end = start[i + 1];
    VD ax = {0.0}, ay = {0.0}, az = {0.0};
    for (; q + F3D_W <= end; q += F3D_W) {
      const VD dx = xi - F3D_NAME(gather3)(x, list, q, 0);
      const VD dy = yi - F3D_NAME(gather3)(x, list, q, 1);
      const VD dz = zi - F3D_NAME(gather3)(x, list, q, 2);
      const VD r = F3D_NAME(root)(dx * dx + dy * dy + dz * dz);
      const VD f = F3D_NAME(spiky)(k, r) * hm /
                   F3D_NAME(gather1)(density, list, q);
      ax += dx * f;
      ay += dy * f;
      az += dz * f;
    }
    double nx = F3D_NAME(sum)(ax), ny = F3D_NAME(sum)(ay),
           nz = F3D_NAME(sum)(az);
    for (; q < end; q++) {
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

static void F3D_NAME(forces)(const double* x, const int32_t* start,
                             const int32_t* list, int32_t n, const double* k,
                             const double* density, const double* normal,
                             const double* before, const double* after,
                             double* v, double dt) {
  const double rho0 = k[K_RHO0];
  const double gm = k[K_GAMMA] * k[K_MASS];
  for (int32_t i = 0; i < n; i++) {
    const double xi = x[3 * i], yi = x[3 * i + 1], zi = x[3 * i + 2];
    const double di = density[i];
    const double nxi = normal[3 * i], nyi = normal[3 * i + 1],
                 nzi = normal[3 * i + 2];
    int32_t q = start[i];
    const int32_t end = start[i + 1];
    VD sx = {0.0}, sy = {0.0}, sz = {0.0};
    for (; q + F3D_W <= end; q += F3D_W) {
      const VD dx = xi - F3D_NAME(gather3)(x, list, q, 0);
      const VD dy = yi - F3D_NAME(gather3)(x, list, q, 1);
      const VD dz = zi - F3D_NAME(gather3)(x, list, q, 2);
      const VD r = F3D_NAME(root)(dx * dx + dy * dy + dz * dz);
      const VI apart = (VI)(r >= 1e-12);
      const VD kk = 2.0 * rho0 / (di + F3D_NAME(gather1)(density, list, q));
      const VD c = -kk * gm * F3D_NAME(cohesion)(k, r) / r;
      const VD t = -kk * k[K_GAMMA];
      sx += KEEP(apart,
                 dx * c + (nxi - F3D_NAME(gather3)(normal, list, q, 0)) * t);
      sy += KEEP(apart,
                 dy * c + (nyi - F3D_NAME(gather3)(normal, list, q, 1)) * t);
      sz += KEEP(apart,
                 dz * c + (nzi - F3D_NAME(gather3)(normal, list, q, 2)) * t);
    }
    double ax = before[3 * i] + F3D_NAME(sum)(sx);
    double ay = before[3 * i + 1] + F3D_NAME(sum)(sy);
    double az = before[3 * i + 2] + F3D_NAME(sum)(sz);
    for (; q < end; q++) {
      const int32_t j = list[q];
      const double dx = xi - x[3 * j], dy = yi - x[3 * j + 1],
                   dz = zi - x[3 * j + 2];
      const double r = sqrt(dx * dx + dy * dy + dz * dz);
      if (r < 1e-12) continue;
      const double kk = 2.0 * rho0 / (di + density[j]);
      const double c = -kk * gm * cohesion(k, r) / r;
      const double t = -kk * k[K_GAMMA];
      ax += dx * c + (nxi - normal[3 * j]) * t;
      ay += dy * c + (nyi - normal[3 * j + 1]) * t;
      az += dz * c + (nzi - normal[3 * j + 2]) * t;
    }
    ax += after[3 * i];
    ay += after[3 * i + 1];
    az += after[3 * i + 2];
    v[3 * i] += ax * dt;
    v[3 * i + 1] += ay * dt;
    v[3 * i + 2] += az * dt;
  }
}

static void F3D_NAME(lambdas)(const double* p, const int32_t* start,
                              const int32_t* list, int32_t n,
                              const double* k, double* lambda) {
  const double norm = k[K_NORM];
  const double self = poly6(k, 0.0);
  for (int32_t i = 0; i < n; i++) {
    const double xi = p[3 * i], yi = p[3 * i + 1], zi = p[3 * i + 2];
    int32_t q = start[i];
    const int32_t end = start[i + 1];
    VD vw = {0.0}, vs = {0.0}, vx = {0.0}, vy = {0.0}, vz = {0.0};
    for (; q + F3D_W <= end; q += F3D_W) {
      const VD dx = xi - F3D_NAME(gather3)(p, list, q, 0);
      const VD dy = yi - F3D_NAME(gather3)(p, list, q, 1);
      const VD dz = zi - F3D_NAME(gather3)(p, list, q, 2);
      const VD r2 = dx * dx + dy * dy + dz * dz;
      vw += F3D_NAME(poly6)(k, r2);
      const VD f = F3D_NAME(spiky)(k, F3D_NAME(root)(r2)) * norm;
      vs += r2 * f * f;
      vx += dx * f;
      vy += dy * f;
      vz += dz * f;
    }
    double w = self + F3D_NAME(sum)(vw), sum2 = F3D_NAME(sum)(vs);
    double gx = F3D_NAME(sum)(vx), gy = F3D_NAME(sum)(vy),
           gz = F3D_NAME(sum)(vz);
    for (; q < end; q++) {
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

static void F3D_NAME(deltas)(const double* p, const int32_t* start,
                             const int32_t* list, int32_t n, const double* k,
                             const double* lambda, double* delta) {
  const double norm = k[K_NORM];
  const double corr_scale = -0.02 / k[K_REST_STIFFNESS];
  for (int32_t i = 0; i < n; i++) {
    const double xi = p[3 * i], yi = p[3 * i + 1], zi = p[3 * i + 2];
    const double li = lambda[i];
    int32_t q = start[i];
    const int32_t end = start[i + 1];
    VD vx = {0.0}, vy = {0.0}, vz = {0.0};
    for (; q + F3D_W <= end; q += F3D_W) {
      const VD dx = xi - F3D_NAME(gather3)(p, list, q, 0);
      const VD dy = yi - F3D_NAME(gather3)(p, list, q, 1);
      const VD dz = zi - F3D_NAME(gather3)(p, list, q, 2);
      const VD r2 = dx * dx + dy * dy + dz * dz;
      const VD ratio = F3D_NAME(poly6)(k, r2) / k[K_WQ];
      const VD corr = ratio * ratio * ratio * ratio * corr_scale;
      const VD f = F3D_NAME(spiky)(k, F3D_NAME(root)(r2)) *
                   (li + F3D_NAME(gather1)(lambda, list, q) + corr) * norm;
      vx += dx * f;
      vy += dy * f;
      vz += dz * f;
    }
    double sx = F3D_NAME(sum)(vx), sy = F3D_NAME(sum)(vy),
           sz = F3D_NAME(sum)(vz);
    for (; q < end; q++) {
      const int32_t j = list[q];
      const double dx = xi - p[3 * j], dy = yi - p[3 * j + 1],
                   dz = zi - p[3 * j + 2];
      const double r2 = dx * dx + dy * dy + dz * dz;
      const double ratio = poly6(k, r2) / k[K_WQ];
      const double corr =
          -0.02 * ratio * ratio * ratio * ratio / k[K_REST_STIFFNESS];
      const double f =
          spiky_scale(k, sqrt(r2)) * (li + lambda[j] + corr) * norm;
      sx += dx * f;
      sy += dy * f;
      sz += dz * f;
    }
    delta[3 * i] = sx;
    delta[3 * i + 1] = sy;
    delta[3 * i + 2] = sz;
  }
}

static void F3D_NAME(viscosity)(const double* p, const double* v,
                                const int32_t* start, const int32_t* list,
                                int32_t n, const double* k, double share,
                                double* smoothed) {
  const double scale = k[K_NORM] * share;
  for (int32_t i = 0; i < n; i++) {
    const double xi = p[3 * i], yi = p[3 * i + 1], zi = p[3 * i + 2];
    const double vxi = v[3 * i], vyi = v[3 * i + 1], vzi = v[3 * i + 2];
    int32_t q = start[i];
    const int32_t end = start[i + 1];
    VD ax = {0.0}, ay = {0.0}, az = {0.0};
    for (; q + F3D_W <= end; q += F3D_W) {
      const VD dx = xi - F3D_NAME(gather3)(p, list, q, 0);
      const VD dy = yi - F3D_NAME(gather3)(p, list, q, 1);
      const VD dz = zi - F3D_NAME(gather3)(p, list, q, 2);
      const VD w = F3D_NAME(poly6)(k, dx * dx + dy * dy + dz * dz) * scale;
      ax += (F3D_NAME(gather3)(v, list, q, 0) - vxi) * w;
      ay += (F3D_NAME(gather3)(v, list, q, 1) - vyi) * w;
      az += (F3D_NAME(gather3)(v, list, q, 2) - vzi) * w;
    }
    double sx = vxi + F3D_NAME(sum)(ax), sy = vyi + F3D_NAME(sum)(ay),
           sz = vzi + F3D_NAME(sum)(az);
    for (; q < end; q++) {
      const int32_t j = list[q];
      const double dx = xi - p[3 * j], dy = yi - p[3 * j + 1],
                   dz = zi - p[3 * j + 2];
      const double w = poly6(k, dx * dx + dy * dy + dz * dz) * scale;
      sx += (v[3 * j] - vxi) * w;
      sy += (v[3 * j + 1] - vyi) * w;
      sz += (v[3 * j + 2] - vzi) * w;
    }
    smoothed[3 * i] = sx;
    smoothed[3 * i + 1] = sy;
    smoothed[3 * i + 2] = sz;
  }
}

#undef VD
#undef VI
#undef KEEP
#undef PICK
