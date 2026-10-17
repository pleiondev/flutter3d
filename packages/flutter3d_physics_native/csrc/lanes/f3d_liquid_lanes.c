// The liquid's pair loops of `lib/src/liquid_kernels.dart`, in C, a few
// neighbours at a time: the native CPU executor of `KernelLiquid`, the
// workload's own host code beside the kernels the hardware layer places.
//
// **Held to the CPU kernel within a tolerance, not to the bit.** The kernels
// run in f32, rounded after every operation, the same bytes on every
// machine; this runs in doubles and sums several neighbours at a time where
// the compiler has vector extensions (clang and gcc), in another order.
// So it is refused where a run must replay to the bit
// (`SimulationProfile.deterministic`), and held to the kernel within the
// tolerance `KernelLiquid.nativeTolerance` states.
//
// **Built apart from the core**, with -O3 and without the core's
// deterministic flags, by the package's hook, which builds nothing and
// says so where there is no C compiler: the liquid then runs its kernels.
//
// **How many at a time is the running processor's, chosen when first
// asked**, not the building machine's: two lanes everywhere (SSE2 and NEON
// are in every x86-64 and arm64); on x86-64 also four, built for AVX2, and
// eight, built for AVX-512F, each taken only where the processor says it
// has them. Four is the default where AVX2 is (see [f3d_default_lanes]).
//
// The constants come as one array, in this order:
//   0 h, 1 h², 2 ρ₀, 3 m, 4 norm, 5 γ, 6 rest stiffness,
//   7 poly6, 8 spiky, 9 cohesion, 10 h⁶, 11 W(0.3h).

#include <math.h>
#include <stdint.h>
#include <stdlib.h>

#if defined(__clang__) || defined(__GNUC__)
#define F3D_VECTOR 1
#else
#define F3D_VECTOR 0
#endif

#if F3D_VECTOR && (defined(__x86_64__) || defined(_M_X64))
#define F3D_X86 1
#else
#define F3D_X86 0
#endif

// The lanes arm64 takes unless a test sets others: what measured fastest.
#ifndef F3D_ARM_LANES
#define F3D_ARM_LANES 2
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

F3D_EXPORT int32_t f3d_lanes_version(void) { return 7; }

// Memory the caller's buffers are copied into, and given back.
F3D_EXPORT void* f3d_lanes_alloc(int64_t bytes) {
  return malloc(bytes > 0 ? (size_t)bytes : 1);
}

F3D_EXPORT void f3d_lanes_free(void* block) { free(block); }

static void scalar_densities(const double* x, const int32_t* start,
                                  const int32_t* list, int32_t n,
                                  const double* k, double* density) {
  const double self = poly6(k, 0.0);
  for (int32_t i = 0; i < n; i++) {
    const double xi = x[3 * i], yi = x[3 * i + 1], zi = x[3 * i + 2];
    int32_t q = start[i];
    const int32_t end = start[i + 1];
    double w = self;
    for (; q < end; q++) {
      const int32_t j = list[q];
      const double dx = xi - x[3 * j], dy = yi - x[3 * j + 1],
                   dz = zi - x[3 * j + 2];
      w += poly6(k, dx * dx + dy * dy + dz * dz);
    }
    density[i] = k[K_RHO0] * w * k[K_NORM];
  }
}

static void scalar_normals(const double* x, const int32_t* start,
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

static void scalar_forces(const double* x, const int32_t* start,
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

static void scalar_lambdas(const double* p, const int32_t* start,
                           const int32_t* list, int32_t n, const double* k,
                           double* lambda, double* crowd) {
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
    crowd[i] = c;
    lambda[i] = -c / (sum2 + 1e-6 * norm * norm / (k[K_H] * k[K_H]));
  }
}

static void scalar_deltas(const double* p, const int32_t* start,
                          const int32_t* list, int32_t n, const double* k,
                          const double* lambda, int32_t artificial,
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
          artificial
              ? -0.02 * ratio * ratio * ratio * ratio / k[K_REST_STIFFNESS]
              : 0.0;
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

static void scalar_viscosity(const double* p, const double* v,
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

// ------------------------------------------------------------ the widths

#if F3D_VECTOR
#define F3D_W 2
#define F3D_NAME(name) name##_w2
#include "f3d_liquid_lanes_w.h"
#undef F3D_W
#undef F3D_NAME

#if F3D_X86
#if defined(__clang__)
#pragma clang attribute push(__attribute__((target("avx2"))), apply_to = function)
#else
#pragma GCC push_options
#pragma GCC target("avx2")
#endif
#define F3D_W 4
#define F3D_NAME(name) name##_w4
#include "f3d_liquid_lanes_w.h"
#undef F3D_W
#undef F3D_NAME
#if defined(__clang__)
#pragma clang attribute pop
#else
#pragma GCC pop_options
#endif

#if defined(__clang__)
#pragma clang attribute push(__attribute__((target("avx512f"))), apply_to = function)
#else
#pragma GCC push_options
#pragma GCC target("avx512f")
#endif
#define F3D_W 8
#define F3D_NAME(name) name##_w8
#include "f3d_liquid_lanes_w.h"
#undef F3D_W
#undef F3D_NAME
#if defined(__clang__)
#pragma clang attribute pop
#else
#pragma GCC pop_options
#endif
#else
// Off x86-64 the wider widths are built for the baseline: four lanes are
// two NEON registers an operation, eight are four. Built so that a test
// can hold them to the Dart kernels on any machine; which one runs by
// default is [f3d_lanes_width]'s choice.
#define F3D_W 4
#define F3D_NAME(name) name##_w4
#include "f3d_liquid_lanes_w.h"
#undef F3D_W
#undef F3D_NAME
#define F3D_W 8
#define F3D_NAME(name) name##_w8
#include "f3d_liquid_lanes_w.h"
#undef F3D_W
#undef F3D_NAME
#endif
#endif

// The widest the running processor can take: 1 without vector extensions.
static int32_t f3d_widest(void) {
#if !F3D_VECTOR
  return 1;
#elif F3D_X86
  __builtin_cpu_init();
  if (__builtin_cpu_supports("avx512f")) return 8;
  if (__builtin_cpu_supports("avx2")) return 4;
  return 2;
#else
  return 8;
#endif
}

// The lanes in use: 0 until first asked. Written once with the same value
// by whichever isolate asks first, or set by a test.
static int32_t f3d_lanes = 0;

// **Four on x86-64 where there is AVX2, not the widest there is.** On a
// CI runner with AVX-512F, eight lanes were as fast as four built with gcc
// and slower built with clang (0.67 and 0.77 ms against 0.70 and 0.65): the
// loops wait on gathering each neighbour's numbers, not on arithmetic.
// Four against two was 1.5 times as fast.
static int32_t f3d_default_lanes(void) {
#if F3D_X86
  return f3d_widest() >= 4 ? 4 : 2;
#elif F3D_VECTOR
  return F3D_ARM_LANES;
#else
  return 1;
#endif
}

// How many neighbours each pair loop takes at a time: 1, 2, 4 or 8.
F3D_EXPORT int32_t f3d_lanes_width(void) {
  if (f3d_lanes == 0) f3d_lanes = f3d_default_lanes();
  return f3d_lanes;
}

// Sets the lanes to [lanes] where the processor has them, and returns the
// lanes now in use: for a test to hold each width to the Dart kernels.
// 0 goes back to the running processor's default.
F3D_EXPORT int32_t f3d_lanes_set_width(int32_t lanes) {
  if (lanes == 0) {
    f3d_lanes = f3d_default_lanes();
  } else if ((lanes == 1 || lanes == 2 || lanes == 4 || lanes == 8) &&
             lanes <= f3d_widest()) {
    f3d_lanes = lanes;
  }
  return f3d_lanes_width();
}

#if F3D_VECTOR
#define F3D_DISPATCH(name, ...)              \
  switch (f3d_lanes_width()) {                 \
    case 8:                                  \
      name##_w8(__VA_ARGS__);                \
      return;                                \
    case 4:                                  \
      name##_w4(__VA_ARGS__);                \
      return;                                \
    case 2:                                  \
      name##_w2(__VA_ARGS__);                \
      return;                                \
    default:                                 \
      scalar_##name(__VA_ARGS__);            \
      return;                                \
  }
#else
#define F3D_DISPATCH(name, ...) scalar_##name(__VA_ARGS__);
#endif

F3D_EXPORT void f3d_lanes_densities(const double* x, const int32_t* start,
                                  const int32_t* list, int32_t n,
                                  const double* k, double* density) {
  F3D_DISPATCH(densities, x, start, list, n, k, density)
}

F3D_EXPORT void f3d_lanes_normals(const double* x, const int32_t* start,
                                const int32_t* list, int32_t n,
                                const double* k, const double* density,
                                double* normal) {
  F3D_DISPATCH(normals, x, start, list, n, k, density, normal)
}

F3D_EXPORT void f3d_lanes_forces(const double* x, const int32_t* start,
                               const int32_t* list, int32_t n,
                               const double* k, const double* density,
                               const double* normal, const double* before,
                               const double* after, double* v, double dt) {
  F3D_DISPATCH(forces, x, start, list, n, k, density, normal, before, after,
               v, dt)
}

F3D_EXPORT void f3d_lanes_lambdas(const double* p, const int32_t* start,
                                  const int32_t* list, int32_t n,
                                  const double* k, double* lambda,
                                  double* crowd) {
  F3D_DISPATCH(lambdas, p, start, list, n, k, lambda, crowd)
}

F3D_EXPORT void f3d_lanes_deltas(const double* p, const int32_t* start,
                                 const int32_t* list, int32_t n,
                                 const double* k, const double* lambda,
                                 int32_t artificial, double* delta) {
  F3D_DISPATCH(deltas, p, start, list, n, k, lambda, artificial, delta)
}

F3D_EXPORT void f3d_lanes_viscosity(const double* p, const double* v,
                                  const int32_t* start, const int32_t* list,
                                  int32_t n, const double* k, double share,
                                  double* smoothed) {
  F3D_DISPATCH(viscosity, p, v, start, list, n, k, share, smoothed)
}
