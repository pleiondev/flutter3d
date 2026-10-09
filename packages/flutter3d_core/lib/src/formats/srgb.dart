/// The sRGB transfer curve, for formats whose colours are stored on the other
/// side of it from the engine's.
///
/// `SurfaceMaterial.baseColor` is authored, non-linear: the colour a paint
/// program shows, which every shader converts before multiplying. glTF's
/// `baseColorFactor` is linear, as its specification says in so many words. A
/// reader or writer of such a format converts at the boundary, and nothing
/// inside the engine has to know which format a tint came from.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// One channel, linear to sRGB-encoded — IEC 61966-2-1's piecewise curve.
double linearToSrgb(double c) => c <= 0.0031308
    ? c * 12.92
    : 1.055 * math.pow(c, 1.0 / 2.4).toDouble() - 0.055;

/// One channel, sRGB-encoded to linear.
double srgbToLinear(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

/// A colour picked on screen, as the linear RGBA a vertex colour is.
///
/// **For vertex colours, not for `baseColor`.** The two are on opposite sides
/// of the curve: a material's tint is sRGB-encoded and every shader converts
/// it, while a vertex colour is linear, as glTF's `COLOR_0` is, and goes into
/// the lighting as it stands. A green picked in a paint program and written
/// straight into a vertex comes out pale, which is what a game building its
/// scenery out of painted shapes finds first. Alpha is linear on both sides
/// and passes through.
Vector4 linearFromSrgb(double r, double g, double b, [double a = 1.0]) =>
    Vector4(srgbToLinear(r), srgbToLinear(g), srgbToLinear(b), a);
