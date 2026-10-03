// The heavy half of `FreeSurface.solveModes`, in C: the banded Cholesky
// factor of the surface's graph Laplacian (shifted by σ) and the Lanczos
// steps on its inverse, with full reorthogonalisation. What comes back, the
// tridiagonal and its basis, is finished in Dart: the tridiagonal is at most
// a few dozen across.
//
// Step for step the Dart one; held to it within a tolerance, since the
// compiler may fuse a multiply and an add where Dart rounds twice.

#include <math.h>
#include <stdint.h>
#include <string.h>

#if defined(_WIN32)
#define F3D_EXPORT __declspec(dllexport)
#else
#define F3D_EXPORT __attribute__((visibility("default")))
#endif

static double dot(const double* a, const double* b, int32_t n) {
  double s = 0.0;
  for (int32_t i = 0; i < n; i++) s += a[i] * b[i];
  return s;
}

static void remove_mean(double* a, int32_t n) {
  double mean = 0.0;
  for (int32_t i = 0; i < n; i++) mean += a[i];
  mean /= n;
  for (int32_t i = 0; i < n; i++) a[i] -= mean;
}

// x = (L + σ)⁻¹ b on the flat-free part, by the factor's two sweeps.
static void solve(const double* factor, int32_t n, int32_t band,
                  const double* b, double* x) {
  const int32_t w1 = band + 1;
  memcpy(x, b, sizeof(double) * (size_t)n);
  remove_mean(x, n);
  for (int32_t i = 0; i < n; i++) {
    double sum = x[i];
    const int32_t lo = i - band > 0 ? i - band : 0;
    for (int32_t k = lo; k < i; k++) sum -= factor[i * w1 + (i - k)] * x[k];
    x[i] = sum / factor[i * w1];
  }
  for (int32_t i = n - 1; i >= 0; i--) {
    double sum = x[i];
    const int32_t hi = i + band < n - 1 ? i + band : n - 1;
    for (int32_t k = i + 1; k <= hi; k++) {
      sum -= factor[k * w1 + (k - i)] * x[k];
    }
    x[i] = sum / factor[i * w1];
  }
  remove_mean(x, n);
}

// Lanczos on (L + σ)⁻¹ from [q0] for at most [steps] steps: [basis] (steps
// rows of n), [alpha] and [beta] (one fewer). Returns how many steps ran.
// [scratch] holds n·(band + 1) + 2·n doubles, the caller's own.
F3D_EXPORT int32_t f3d_surface_lanczos(int32_t n, const int32_t* start,
                                       const int32_t* adjacent, double cell2,
                                       int32_t band, int32_t steps,
                                       const double* q0, double* basis,
                                       double* alpha, double* beta,
                                       double* scratch) {
  const double inv = 1.0 / cell2;
  const double sigma = 1e-6 * inv;
  const int32_t w1 = band + 1;
  double* factor = scratch;
  double* w = scratch + (size_t)n * w1;
  double* previous = w + n;
  memset(factor, 0, sizeof(double) * (size_t)n * w1);
  for (int32_t i = 0; i < n; i++) {
    factor[i * w1] = (start[i + 1] - start[i]) * inv + sigma;
    for (int32_t q = start[i]; q < start[i + 1]; q++) {
      const int32_t k = adjacent[q];
      if (k < i) factor[i * w1 + (i - k)] = -inv;
    }
  }
  for (int32_t i = 0; i < n; i++) {
    const int32_t lo = i - band > 0 ? i - band : 0;
    for (int32_t j = lo; j <= i; j++) {
      double sum = factor[i * w1 + (i - j)];
      const int32_t from = lo > j - band ? lo : j - band;
      for (int32_t k = from; k < j; k++) {
        sum -= factor[i * w1 + (i - k)] * factor[j * w1 + (j - k)];
      }
      factor[i * w1 + (i - j)] =
          i == j ? sqrt(sum > 1e-300 ? sum : 1e-300) : sum / factor[j * w1];
    }
  }
  memset(previous, 0, sizeof(double) * (size_t)n);
  memcpy(basis, q0, sizeof(double) * (size_t)n);
  double b = 0.0;
  int32_t size = 0;
  for (int32_t m = 0; m < steps; m++) {
    const double* q = basis + (size_t)m * n;
    solve(factor, n, band, q, w);
    for (int32_t i = 0; i < n; i++) w[i] -= b * previous[i];
    const double a = dot(w, q, n);
    for (int32_t i = 0; i < n; i++) w[i] -= a * q[i];
    // Full reorthogonalisation, twice: Lanczos alone loses it.
    for (int32_t pass = 0; pass < 2; pass++) {
      for (int32_t v = 0; v <= m; v++) {
        const double* row = basis + (size_t)v * n;
        const double c = dot(w, row, n);
        for (int32_t i = 0; i < n; i++) w[i] -= c * row[i];
      }
      remove_mean(w, n);
    }
    alpha[m] = a;
    size = m + 1;
    b = sqrt(dot(w, w, n));
    if (b < 1e-12 * fabs(a) || m == steps - 1) break;
    beta[m] = b;
    memcpy(previous, q, sizeof(double) * (size_t)n);
    double* next = basis + (size_t)(m + 1) * n;
    for (int32_t i = 0; i < n; i++) next[i] = w[i] / b;
  }
  return size;
}
