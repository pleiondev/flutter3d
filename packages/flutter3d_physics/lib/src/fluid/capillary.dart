import 'dart:math' as math;

import '../portable_math.dart';
import 'fluid_medium.dart';

/// Surface tension at a wall: how high liquid climbs it, and the shape of
/// the surface it leaves.
///
/// Across a curved surface the pressure jumps by σ times its curvature
/// (Young and Laplace), and under gravity the pressure in the liquid grows
/// as ρg per metre down; a surface at rest is one where the two balance at
/// every point, and where it meets the wall it meets it at the contact
/// angle. Everything here is that one balance, solved for a shape.

/// Jurin's height: how far liquid rises in a narrow tube of [radius] dipped
/// in a wide bath, under gravity [g] — or sinks, for a liquid that does not
/// wet the wall. The narrow-tube limit of [TubeMeniscus.rise].
double jurinHeight(FluidMedium medium, double radius, double g) =>
    2.0 *
    medium.surfaceTension *
    Portable.cos(medium.contactAngle) /
    (medium.density * g * radius);

/// The meniscus in a round tube of [radius]: the axisymmetric
/// Young–Laplace surface, solved exactly rather than taken for a sphere.
///
/// From the middle of the surface outwards, along its own length s, the
/// surface turns as dφ/ds = (ρg/σ)z + b − sin φ / r, where z is the height
/// above the middle and b the curvature there (twice the curvature of each
/// principal direction, which are equal on the axis). The b that makes it
/// meet the wall at the contact angle is found by halving. In a tube much
/// narrower than the capillary length that is a spherical cap; in a wide one
/// it is flat across the middle and climbs only near the wall — which is the
/// shape a liquid in a test tube actually has.
final class TubeMeniscus {
  TubeMeniscus({
    required this.medium,
    required this.radius,
    required this.g,
    this.samples = 64,
  }) {
    _solve();
  }

  final FluidMedium medium;
  final double radius;
  final double g;
  final int samples;

  /// The curvature at the middle, per metre.
  late final double apexCurvature;

  /// How far the surface stands at the wall above its middle: positive for a
  /// liquid that wets the wall, negative for one that does not.
  late final double wallRise;

  /// How far the middle of the surface stands above the level of a wide bath
  /// the tube is dipped in: the pressure under it, σb, worth ρg per metre.
  /// Jurin's height for a narrow tube, and less for a wide one, whose middle
  /// is nearly flat.
  double get rise =>
      medium.surfaceTension * apexCurvature / (medium.density * g);

  late final List<double> _r;
  late final List<double> _z;

  /// The height of the surface above its middle at distance [r] from the
  /// axis.
  double heightAt(double r) {
    final x = r.abs().clamp(0.0, radius);
    for (var i = 1; i < _r.length; i++) {
      if (_r[i] >= x) {
        final span = _r[i] - _r[i - 1];
        final t = span > 0.0 ? (x - _r[i - 1]) / span : 0.0;
        return _z[i - 1] + (_z[i] - _z[i - 1]) * t;
      }
    }
    return _z.last;
  }

  /// The mean height of the surface above its middle, weighed by area: what
  /// the meniscus takes out of a flat surface's level, so the volume stays.
  late final double meanHeight = _meanHeight();

  /// The highest the meniscus stands above its mean: at the wall when the
  /// liquid wets it, in the middle when it does not.
  late final double peak = math.max(
    heightAt(radius) - meanHeight,
    heightAt(0.0) - meanHeight,
  );

  double _meanHeight() {
    var sum = 0.0;
    var area = 0.0;
    for (var i = 1; i < _r.length; i++) {
      final r0 = _r[i - 1], r1 = _r[i];
      final ring = math.pi * (r1 * r1 - r0 * r0);
      sum += 0.5 * (_z[i - 1] + _z[i]) * ring;
      area += ring;
    }
    return area > 0.0 ? sum / area : 0.0;
  }

  void _solve() {
    final target = math.pi / 2 - medium.contactAngle;
    final bond = medium.density * g / medium.surfaceTension;
    var lo = -40.0 / radius;
    var hi = 40.0 / radius;
    for (var i = 0; i < 60; i++) {
      final mid = 0.5 * (lo + hi);
      if (_shoot(mid, bond).angle < target) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    apexCurvature = 0.5 * (lo + hi);
    final path = _shoot(apexCurvature, bond, keep: true);
    _r = path.r;
    _z = path.z;
    wallRise = _z.last;
  }

  /// The surface from the axis to the wall for an apex curvature [b]: the
  /// angle it reaches the wall at, and its points.
  ({double angle, List<double> r, List<double> z}) _shoot(
    double b,
    double bond, {
    bool keep = false,
  }) {
    // Near the axis sin φ / r → b/2, so start a hair off it on the cap.
    final s0 = radius * 1e-4;
    var r = s0;
    var z = 0.5 * b * 0.5 * s0 * s0;
    var phi = 0.5 * b * s0;
    final rs = <double>[0.0];
    final zs = <double>[0.0];
    double turn(double r, double z, double phi) =>
        bond * z + b - Portable.sin(phi) / math.max(r, 1e-12);
    final ds = radius / (samples * 8);
    var guard = 0;
    while (r < radius && guard++ < samples * 400) {
      // Runge–Kutta in arc length.
      final k1r = Portable.cos(phi), k1z = Portable.sin(phi);
      final k1p = turn(r, z, phi);
      final k2r = Portable.cos(phi + 0.5 * ds * k1p);
      final k2z = Portable.sin(phi + 0.5 * ds * k1p);
      final k2p = turn(
        r + 0.5 * ds * k1r,
        z + 0.5 * ds * k1z,
        phi + 0.5 * ds * k1p,
      );
      final k3r = Portable.cos(phi + 0.5 * ds * k2p);
      final k3z = Portable.sin(phi + 0.5 * ds * k2p);
      final k3p = turn(
        r + 0.5 * ds * k2r,
        z + 0.5 * ds * k2z,
        phi + 0.5 * ds * k2p,
      );
      final k4r = Portable.cos(phi + ds * k3p);
      final k4z = Portable.sin(phi + ds * k3p);
      final k4p = turn(r + ds * k3r, z + ds * k3z, phi + ds * k3p);
      final nr = r + ds / 6 * (k1r + 2 * k2r + 2 * k3r + k4r);
      final nz = z + ds / 6 * (k1z + 2 * k2z + 2 * k3z + k4z);
      final np = phi + ds / 6 * (k1p + 2 * k2p + 2 * k3p + k4p);
      // A surface that turns back on itself before the wall has overshot.
      if (nr <= r || np.abs() > math.pi) {
        return (angle: np.sign * math.pi, r: rs, z: zs);
      }
      if (nr >= radius) {
        final t = (radius - r) / (nr - r);
        z += (nz - z) * t;
        phi += (np - phi) * t;
        r = radius;
      } else {
        r = nr;
        z = nz;
        phi = np;
      }
      if (keep) {
        rs.add(r);
        zs.add(z);
      }
    }
    return (angle: phi, r: rs, z: zs);
  }
}

/// The height of the surface at distance [distance] from a flat wall in a
/// wide vessel, above the level far from it: the planar Young–Laplace
/// solution. The surface climbs the wall to l·√(2(1 − sin θ)), l the
/// capillary length, and falls away from it within a few l; for a liquid
/// that does not wet the wall the same shape is turned down.
double wallMeniscus(FluidMedium medium, double distance, double g) {
  final l = medium.capillaryLength(g);
  final theta = medium.contactAngle;
  final h0 = l * math.sqrt(2.0 * (1.0 - Portable.sin(theta)));
  if (h0 <= 0.0) return 0.0;
  // x(z) = l[acosh(2l/z) − √(4 − z²/l²)], measured from where z = h0.
  double x(double z) {
    final a = 2.0 * l / z;
    final acosh = Portable.log(a + math.sqrt(a * a - 1.0));
    return l * (acosh - math.sqrt(math.max(4.0 - z * z / (l * l), 0.0)));
  }

  final x0 = x(h0);
  final d = math.max(distance, 0.0);
  var lo = 1e-12 * l;
  var hi = h0;
  for (var i = 0; i < 60; i++) {
    final mid = 0.5 * (lo + hi);
    if (x(mid) - x0 > d) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  final z = 0.5 * (lo + hi);
  return theta > math.pi / 2 ? -z : z;
}
