/// The engine's one colour type.
///
/// See `docs/CONTRACTS.md`: every colour in the engine is linear unless its
/// name says sRGB.
library;

import 'dart:math' as math;

/// A colour in linear light, with straight (not premultiplied) alpha.
///
/// **Linear, because light adds.** Two lamps on a wall make the sum of their
/// light, and that sum is only right in linear values; the sRGB numbers a
/// colour picker shows are a curve over them, made for the eye and the
/// display. So a light's colour, a material's albedo and a fog's tint are
/// linear here, and the curve is applied once, at the end of the frame.
///
/// [r], [g] and [b] are not clamped: above 1 is a colour brighter than
/// white, which an emissive surface or an HDR light is. [a] is coverage,
/// 0 (transparent) to 1 (opaque), and is the same in either space.
///
/// A caller holding sRGB values (a hex code, a picker) converts with
/// [LinearColor.fromSrgb]; a Flutter `Color` converts in `flutter3d`, which
/// is the package that knows Flutter.
final class LinearColor {
  /// A colour from linear components; [a] defaults to opaque.
  const LinearColor(this.r, this.g, this.b, [this.a = 1]);

  /// A colour from sRGB-encoded components in 0..1, decoded with the exact
  /// sRGB transfer function (IEC 61966-2-1), the way a caller enters a colour
  /// a person picked. [a] is copied as it is.
  factory LinearColor.fromSrgb(double r, double g, double b, [double a = 1]) =>
      LinearColor(srgbToLinear(r), srgbToLinear(g), srgbToLinear(b), a);

  /// Black, opaque.
  static const LinearColor black = LinearColor(0, 0, 0);

  /// White, opaque: 1 in every channel.
  static const LinearColor white = LinearColor(1, 1, 1);

  /// Black with no coverage, which a caller uses for "nothing here".
  static const LinearColor transparent = LinearColor(0, 0, 0, 0);

  /// Red, in linear light.
  final double r;

  /// Green, in linear light.
  final double g;

  /// Blue, in linear light.
  final double b;

  /// Coverage, 0 to 1.
  final double a;

  /// This colour encoded for display, for a caller showing it to a person
  /// (a swatch, a hex code). Each channel goes through the sRGB curve; one
  /// above 1 is encoded past 1 rather than clipped, so nothing is lost before
  /// the caller decides how to show it.
  ({double r, double g, double b, double a}) toSrgb() =>
      (r: linearToSrgb(r), g: linearToSrgb(g), b: linearToSrgb(b), a: a);

  /// This colour with its coverage replaced by [alpha], for a caller fading
  /// something in or out.
  LinearColor withAlpha(double alpha) => LinearColor(r, g, b, alpha);

  /// This colour with [r], [g] and [b] multiplied by [factor] and [a] kept,
  /// for a caller turning an intensity up or down. In linear light that is
  /// exactly "twice as much light".
  LinearColor scaled(double factor) =>
      LinearColor(r * factor, g * factor, b * factor, a);

  /// The colour a fraction [t] of the way from [from] to [to], every channel
  /// interpolated in linear light, for a caller blending between two.
  static LinearColor lerp(LinearColor from, LinearColor to, double t) =>
      LinearColor(
        from.r + (to.r - from.r) * t,
        from.g + (to.g - from.g) * t,
        from.b + (to.b - from.b) * t,
        from.a + (to.a - from.a) * t,
      );

  /// One sRGB-encoded channel decoded to linear light: the sRGB EOTF, with
  /// its linear toe below 0.04045. Negative input decodes as its mirror, so
  /// the curve is odd and a caller's out-of-gamut values survive a round
  /// trip.
  static double srgbToLinear(double encoded) {
    final magnitude = encoded.abs();
    final linear = magnitude <= 0.04045
        ? magnitude / 12.92
        : math.pow((magnitude + 0.055) / 1.055, 2.4).toDouble();
    return encoded < 0 ? -linear : linear;
  }

  /// One linear channel encoded for display: the inverse of [srgbToLinear],
  /// for a caller writing a colour out where a person reads it.
  static double linearToSrgb(double linear) {
    final magnitude = linear.abs();
    final encoded = magnitude <= 0.0031308
        ? magnitude * 12.92
        : 1.055 * math.pow(magnitude, 1 / 2.4).toDouble() - 0.055;
    return linear < 0 ? -encoded : encoded;
  }

  @override
  bool operator ==(Object other) =>
      other is LinearColor &&
      other.r == r &&
      other.g == g &&
      other.b == b &&
      other.a == a;

  @override
  int get hashCode => Object.hash(r, g, b, a);

  @override
  String toString() => 'LinearColor($r, $g, $b, $a)';
}
