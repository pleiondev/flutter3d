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

/// One channel, linear to sRGB-encoded — IEC 61966-2-1's piecewise curve.
double linearToSrgb(double c) => c <= 0.0031308
    ? c * 12.92
    : 1.055 * math.pow(c, 1.0 / 2.4).toDouble() - 0.055;

/// One channel, sRGB-encoded to linear.
double srgbToLinear(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
