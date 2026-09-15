/// The weight-paint gradient's own five colour stops, and the piecewise
/// blend between them — `tut-11`'s own fix, a second copy of
/// `apps/flutter3d_modeler/lib/src/weight_gradient.dart`'s own
/// [weightGradientColor] (that file's own name), restated here rather than
/// shared for the same reason `render_project.dart`'s own doc comment
/// already gives for its own "third copy" of a mesh-data switch: this
/// package may not depend on the application that owns the original, and
/// the whole function is a dozen lines.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// One stop of the weight gradient: the sRGB the design named, at [position]
/// along the 0..1 weight axis. See `weight_gradient.dart`'s own
/// [WeightGradientStop] for the fuller doc comment; this is the identical
/// shape.
final class _WeightGradientStop {
  const _WeightGradientStop(this.position, this.srgb);

  final double position;
  final Vector3 srgb;
}

Vector3 _srgbFromHex(int hex) => Vector3(
  ((hex >> 16) & 0xFF) / 255.0,
  ((hex >> 8) & 0xFF) / 255.0,
  (hex & 0xFF) / 255.0,
);

double _srgbChannelToLinear(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

Vector3 _srgbToLinear(Vector3 srgb) => Vector3(
  _srgbChannelToLinear(srgb.x),
  _srgbChannelToLinear(srgb.y),
  _srgbChannelToLinear(srgb.z),
);

/// The same five stops `weight_gradient.dart`'s own `kWeightGradientStops`
/// names, `#2A3A7A` at no influence through `#FF3B5C` at full.
final List<_WeightGradientStop> _stops = <_WeightGradientStop>[
  _WeightGradientStop(0.00, _srgbFromHex(0x2A3A7A)),
  _WeightGradientStop(0.25, _srgbFromHex(0x4AA3FF)),
  _WeightGradientStop(0.50, _srgbFromHex(0x7EE081)),
  _WeightGradientStop(0.75, _srgbFromHex(0xFFB347)),
  _WeightGradientStop(1.00, _srgbFromHex(0xFF3B5C)),
];

double _clamp01(double v) => v < 0.0 ? 0.0 : (v > 1.0 ? 1.0 : v);

/// [weight] (clamped to 0..1) as a linear RGBA colour, opaque — the same
/// piecewise sRGB blend `weight_gradient.dart`'s own `weightGradientColor`
/// runs, so a headless picture of a brush stroke reads the same hex the
/// live viewport's own legend and vertex colouring would.
Vector4 weightGradientColor(double weight) {
  final w = _clamp01(weight);
  final stops = _stops;

  Vector3 srgb;
  if (w <= stops.first.position) {
    srgb = stops.first.srgb;
  } else if (w >= stops.last.position) {
    srgb = stops.last.srgb;
  } else {
    var i = 0;
    while (i < stops.length - 2 && w > stops[i + 1].position) {
      i++;
    }
    final a = stops[i];
    final b = stops[i + 1];
    final t = (w - a.position) / (b.position - a.position);
    srgb = Vector3(
      a.srgb.x + (b.srgb.x - a.srgb.x) * t,
      a.srgb.y + (b.srgb.y - a.srgb.y) * t,
      a.srgb.z + (b.srgb.z - a.srgb.z) * t,
    );
  }

  final linear = _srgbToLinear(srgb);
  return Vector4(linear.x, linear.y, linear.z, 1.0);
}
