import 'package:vector_math/vector_math.dart';

import 'json_reader.dart';
import 'json_write_through.dart';

final Vector3 _origin = Vector3.zero();
final Vector3 _white = Vector3(1.0, 1.0, 1.0);

enum LevelLightType { directional, point, spot }

/// A light placed by the level rather than by the renderer.
final class LevelLight {
  LevelLight({
    this.type = LevelLightType.point,
    Vector3? position,
    Vector3? direction,
    Vector3? color,
    this.intensity = 1.0,
    this.range = 0.0,
    this.castsShadow = false,
    this.name,
    Map<String, Object?> source = const <String, Object?>{},
  })  : position = position?.clone() ?? Vector3.zero(),
        direction = direction?.clone() ?? Vector3(0.0, -1.0, 0.0),
        // ignore: prefer_initializing_formals
        _source = source,
        color = color?.clone() ?? Vector3(1.0, 1.0, 1.0);

  /// The document this light was read from. See [writeThrough].
  final Map<String, Object?> _source;

  final LevelLightType type;
  final Vector3 position;
  final Vector3 direction;
  final Vector3 color;
  final double intensity;
  final double range;

  /// Whether this light is a candidate for a shadow map.
  ///
  /// A request, not a promise: shadows cost six passes per light, so the
  /// renderer grants it to the nearest couple and ignores the rest.
  final bool castsShadow;

  final String? name;

  factory LevelLight.fromJson(Map<String, Object?> json) => LevelLight(
        type: json.enumValue(
          'type',
          LevelLightType.values,
          LevelLightType.point,
          describedAs: 'light type',
        ),
        position: json.vector3('at', fallback: Vector3.zero()),
        direction: json.vector3(
          'direction',
          fallback: Vector3(0.0, -1.0, 0.0),
        ),
        color: json.vector3('color', fallback: Vector3(1.0, 1.0, 1.0)),
        intensity: json.numberOr('intensity', 1.0),
        range: json.numberOr('range', 0.0),
        castsShadow: json.flagOr('castsShadow'),
        name: json.textOrNull('name'),
        source: json,
      );

  Map<String, Object?> toJson() => writeThrough(_source, <WriteThroughField>[
        WriteThroughField('type', type.name, whenAbsent: type != LevelLightType.point),
        WriteThroughField('at', position.toJson(), whenAbsent: position != _origin),
        WriteThroughField('direction', direction.toJson(),
            whenAbsent: type != LevelLightType.point),
        WriteThroughField('color', color.toJson(), whenAbsent: color != _white),
        WriteThroughField('intensity', intensity, whenAbsent: intensity != 1.0),
        WriteThroughField('range', range, whenAbsent: range != 0.0),
        WriteThroughField('castsShadow', castsShadow, whenAbsent: castsShadow),
        WriteThroughField('name', name, whenAbsent: name != null),
      ]);
}
