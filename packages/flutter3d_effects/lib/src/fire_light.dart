/// The light a fire gives: how many lumens a watt radiated at a temperature
/// is worth to the eye, and what colour it is.
library;

import 'dart:math' as math;

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:vector_math/vector_math.dart';

/// How a [FireView] lights the scene with its fires.
final class FireLights {
  const FireLights._(this.cluster, {this.most = 0});

  /// Fires within [radius] m of each other lit as one light, at the middle
  /// of their light, as bright as all of them: a village burning lights its
  /// walls as many fires, not as one at its centre. At most [most] lights;
  /// past that the nearest clusters join.
  const FireLights.clusters({double radius = 4.0, int most = 8})
    : this._(radius, most: most);

  /// One light for each fire, at most [most]; past that, as [clusters].
  const FireLights.perFire({int most = 8}) : this._(0.0, most: most);

  /// No light: the game lights its fires itself, or they are seen by day.
  static const FireLights none = FireLights._(-1.0);

  /// The distance within which fires are one light, in metres; nought for
  /// each its own, below nought for none.
  final double cluster;

  /// The most lights.
  final int most;
}

/// Planck's radiation of a blackbody seen by the eye and by the CIE 1931
/// observer, by temperature: what a flame's soot, nearly a blackbody, looks
/// like.
abstract final class Blackbody {
  /// Lumens a watt radiated at [kelvin] is worth: 683 lm/W times the share
  /// of Planck's spectrum the photopic eye sees, ∫V(λ)B(λ,T)dλ / ∫B dλ —
  /// about 16 at a tungsten filament's 2856 K, a thousandth of that near
  /// 1300 K, and a nineteen-thousandth at 1100 K, where a hot stone has only
  /// just begun to glow.
  static double efficacy(double kelvin) => _of(kelvin).efficacy;

  /// Its colour in linear sRGB, the brightest channel one.
  static Vector3 color(double kelvin) => _of(kelvin).color.clone();

  static final Map<int, ({double efficacy, Vector3 color})> _seen =
      <int, ({double efficacy, Vector3 color})>{};

  /// Planck's spectrum against the CIE 1931 colour matching functions,
  /// 360 to 830 nm a nanometre at a time, by kelvin.
  static ({double efficacy, Vector3 color}) _of(double kelvin) =>
      _seen.putIfAbsent(kelvin.round().clamp(1, 1000000), () {
        final t = kelvin.round().clamp(1, 1000000).toDouble();
        var x = 0.0, y = 0.0, z = 0.0;
        for (var nm = 360; nm <= 830; nm++) {
          final b = _planck(nm * 1e-9, t) * 1e-9;
          x += _x(nm.toDouble()) * b;
          y += _y(nm.toDouble()) * b;
          z += _z(nm.toDouble()) * b;
        }
        // All of it, σT⁴/π a steradian, against what the eye takes.
        final radiance = stefanBoltzmann * t * t * t * t / math.pi;
        final r = 3.2406 * x - 1.5372 * y - 0.4986 * z;
        final g = -0.9689 * x + 1.8758 * y + 0.0415 * z;
        final bl = 0.0557 * x - 0.2040 * y + 1.0570 * z;
        final most = math.max(r, math.max(g, bl));
        return (
          efficacy: radiance > 0 ? 683.0 * y / radiance : 0.0,
          color: most > 0
              ? Vector3(
                  math.max(r, 0.0) / most,
                  math.max(g, 0.0) / most,
                  math.max(bl, 0.0) / most,
                )
              : Vector3.zero(),
        );
      });

  static const double _h = 6.62607015e-34, _c = 2.99792458e8;

  /// W / (m² sr m) at wavelength [l], m.
  static double _planck(double l, double t) {
    final e = _h * _c / (l * boltzmannConstant * t);
    if (e > 700) return 0.0;
    return 2 * _h * _c * _c / (l * l * l * l * l) / (math.exp(e) - 1.0);
  }

  /// The CIE 1931 colour matching functions as Wyman, Sloan and Shirley fit
  /// them with piecewise Gaussians ("Simple analytic approximations to the
  /// CIE XYZ color matching functions", JCGT 2(2), 2013); ȳ is the photopic
  /// eye's V(λ).
  static double _g(double l, double mu, double below, double above) {
    final s = l < mu ? below : above;
    final d = (l - mu) / s;
    return math.exp(-0.5 * d * d);
  }

  static double _x(double l) =>
      1.056 * _g(l, 599.8, 37.9, 31.0) +
      0.362 * _g(l, 442.0, 16.0, 26.7) -
      0.065 * _g(l, 501.1, 20.4, 26.2);

  static double _y(double l) =>
      0.821 * _g(l, 568.8, 46.9, 40.5) + 0.286 * _g(l, 530.9, 16.3, 31.1);

  static double _z(double l) =>
      1.217 * _g(l, 437.0, 11.8, 36.0) + 0.681 * _g(l, 459.0, 26.0, 13.8);
}
