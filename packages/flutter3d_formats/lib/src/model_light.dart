import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// The shape a light's falloff takes — `KHR_lights_punctual`'s own three,
/// and no others, since the extension defines exactly these three and a
/// fourth is not a thing a decoded document can honestly claim to hold.
enum ModelLightType { directional, point, spot }

/// A punctual light, decoded from `KHR_lights_punctual` or held for a
/// writer to encode into it — `fmt-28`'s own row.
///
/// **Values, not watts.** `intensity` is exactly the number the extension
/// carries — lux for [ModelLightType.directional], candela for
/// [ModelLightType.point]/[ModelLightType.spot] — and this class does no
/// unit conversion of its own; a caller feeding it to a renderer with a
/// different convention does that conversion at the seam, not here.
final class ModelLight {
  ModelLight({
    required this.type,
    Vector3? color,
    this.intensity = 1.0,
    this.range,
    this.innerConeAngle = 0.0,
    double? outerConeAngle,
    this.name,
  }) : color = color ?? Vector3(1.0, 1.0, 1.0),
       outerConeAngle = outerConeAngle ?? math.pi / 4;

  final ModelLightType type;

  /// Linear RGB, the same convention every other colour in this package
  /// (`SurfaceMaterial.baseColor` excepted, which is non-linear as authored)
  /// already uses for a light or a material factor.
  final Vector3 color;

  /// Lux for [ModelLightType.directional], candela otherwise. The
  /// specification's own default when a file omits the key.
  final double intensity;

  /// Distance at which a point or spot light stops contributing, or null
  /// for unbounded — the specification's own default when the key is
  /// absent, kept as `null` rather than folded into a number so a writer
  /// can tell "the file said no limit" from "the file said a very large
  /// number" and omit the key again rather than inventing one.
  final double? range;

  /// Spot-only: the angle, in radians, inside which a spot is at full
  /// intensity. Meaningless for the other two [type]s and kept anyway,
  /// since [ModelLightType.point]/[ModelLightType.directional] never read
  /// it and a writer only emits it for a spot.
  final double innerConeAngle;

  /// Spot-only: the angle, in radians, past which a spot contributes
  /// nothing. Defaults to the specification's own quarter turn over four —
  /// 45 degrees.
  final double outerConeAngle;

  final String? name;

  @override
  String toString() =>
      'ModelLight(${name ?? type.name}, ${type.name}, '
      'intensity: $intensity)';
}
