// `TubeMeniscus._solve` in C: the curvature at the surface's middle that
// meets the wall at the contact angle, by Illinois false position over shots
// of Runge–Kutta in arc length, and the surface it gives.
//
// On the platform's own sine and cosine, many times as quick as the Dart
// one's portable ones, and so held to it within a tolerance, not to the bit:
// for a world that need not replay (`FluidWorld.nativeKernels`).

#include <math.h>
#include <stdint.h>

#if defined(_WIN32)
#define F3D_EXPORT __declspec(dllexport)
#else
#define F3D_EXPORT __attribute__((visibility("default")))
#endif

#define F3D_PI 3.14159265358979323846

static double turn(double bond, double b, double r, double z, double phi) {
  return bond * z + b - sin(phi) / (r > 1e-12 ? r : 1e-12);
}

// One shot from the axis to the wall for apex curvature [b]: the angle it
// meets the wall at. Keeps its points in [rs] and [zs] when they are given,
// [count] of them.
static double shoot(double radius, double bond, double b, int32_t samples,
                    double* rs, double* zs, int32_t capacity,
                    int32_t* count) {
  const double s0 = radius * 1e-4;
  double r = s0;
  double z = 0.5 * b * 0.5 * s0 * s0;
  double phi = 0.5 * b * s0;
  int32_t kept = 0;
  if (rs && kept < capacity) {
    rs[kept] = 0.0;
    zs[kept] = 0.0;
  }
  kept++;
  const double ds = radius / (samples * 2);
  int32_t guard = 0;
  while (r < radius && guard++ < samples * 400) {
    const double k1r = cos(phi), k1z = sin(phi);
    const double k1p = turn(bond, b, r, z, phi);
    const double k2r = cos(phi + 0.5 * ds * k1p);
    const double k2z = sin(phi + 0.5 * ds * k1p);
    const double k2p = turn(bond, b, r + 0.5 * ds * k1r, z + 0.5 * ds * k1z,
                            phi + 0.5 * ds * k1p);
    const double k3r = cos(phi + 0.5 * ds * k2p);
    const double k3z = sin(phi + 0.5 * ds * k2p);
    const double k3p = turn(bond, b, r + 0.5 * ds * k2r, z + 0.5 * ds * k2z,
                            phi + 0.5 * ds * k2p);
    const double k4r = cos(phi + ds * k3p);
    const double k4z = sin(phi + ds * k3p);
    const double k4p =
        turn(bond, b, r + ds * k3r, z + ds * k3z, phi + ds * k3p);
    const double nr = r + ds / 6 * (k1r + 2 * k2r + 2 * k3r + k4r);
    const double nz = z + ds / 6 * (k1z + 2 * k2z + 2 * k3z + k4z);
    const double np = phi + ds / 6 * (k1p + 2 * k2p + 2 * k3p + k4p);
    // A surface that turns back on itself before the wall has overshot.
    if (nr <= r || fabs(np) > F3D_PI) {
      if (count) *count = kept;
      return (np > 0.0 ? 1.0 : (np < 0.0 ? -1.0 : 0.0)) * F3D_PI;
    }
    if (nr >= radius) {
      const double t = (radius - r) / (nr - r);
      z += (nz - z) * t;
      phi += (np - phi) * t;
      r = radius;
    } else {
      r = nr;
      z = nz;
      phi = np;
    }
    if (rs) {
      if (kept < capacity) {
        rs[kept] = r;
        zs[kept] = z;
      }
      kept++;
    }
  }
  if (count) *count = kept;
  return phi;
}

// The meniscus in a tube of [radius]: its apex curvature into [apex], its
// points into [rs] and [zs] (room for [capacity]); returns how many points
// there are, which, if more than [capacity], wants a call with that room.
F3D_EXPORT int32_t f3d_meniscus(double radius, double bond,
                                double contact_angle, int32_t samples,
                                double* rs, double* zs, int32_t capacity,
                                double* apex) {
  const double target = F3D_PI / 2 - contact_angle;
  double lo = -40.0 / radius, hi = 40.0 / radius;
  double flo = shoot(radius, bond, lo, samples, 0, 0, 0, 0) - target;
  double fhi = shoot(radius, bond, hi, samples, 0, 0, 0, 0) - target;
  int32_t kept = 0;
  const double tolerance = (hi - lo) * 8.673617379884035e-19;
  for (int32_t i = 0; i < 200 && hi - lo > tolerance; i++) {
    double mid = isfinite(flo) && isfinite(fhi) && fhi != flo
                     ? lo - flo * (hi - lo) / (fhi - flo)
                     : 0.5 * (lo + hi);
    if (!(mid > lo && mid < hi)) mid = 0.5 * (lo + hi);
    const double f = shoot(radius, bond, mid, samples, 0, 0, 0, 0) - target;
    if (!isfinite(f)) {
      if (isfinite(flo) && flo > 0.0) {
        hi = mid;
      } else {
        lo = mid;
      }
      continue;
    }
    if (fabs(f) < 1e-15) {
      lo = mid;
      hi = mid;
      break;
    }
    if (f < 0.0) {
      lo = mid;
      flo = f;
      if (kept == 1) fhi *= 0.5;
      kept = 1;
    } else {
      hi = mid;
      fhi = f;
      if (kept == -1) flo *= 0.5;
      kept = -1;
    }
  }
  *apex = 0.5 * (lo + hi);
  int32_t count = 0;
  shoot(radius, bond, *apex, samples, rs, zs, capacity, &count);
  return count;
}
