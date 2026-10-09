import 'package:vector_math/vector_math.dart';

import 'json_reader.dart';
import 'json_write_through.dart';
import 'level_format_exception.dart';
import 'level_ids.dart';

final Vector3 _origin = Vector3.zero();
final Vector3 _white = Vector3(1.0, 1.0, 1.0);

enum LevelLightType {
  directional,
  point,
  spot;

  /// The word a level document writes for this type.
  ///
  /// **A table, not [name]**: the Dart identifier is free to be renamed, and
  /// a rename must not change what every saved level says. The words are the
  /// format's and stay as they are.
  String get wireName => _wireNames[this]!;

  /// The type a document's word names, or null for a word that is not one.
  static LevelLightType? fromWireName(String word) => _byWireName[word];

  static const Map<LevelLightType, String> _wireNames =
      <LevelLightType, String>{
        LevelLightType.directional: 'directional',
        LevelLightType.point: 'point',
        LevelLightType.spot: 'spot',
      };

  static const Map<String, LevelLightType> _byWireName =
      <String, LevelLightType>{
        'directional': LevelLightType.directional,
        'point': LevelLightType.point,
        'spot': LevelLightType.spot,
      };
}

/// A light placed by the level rather than by the renderer.
final class LevelLight {
  LevelLight({
    String? id,
    this.type = LevelLightType.point,
    Vector3? position,
    Vector3? direction,
    Vector3? color,
    this.intensity = 1.0,
    this.range = 0.0,
    bool? castsShadow,
    this.name,
    Map<String, Object?> source = const <String, Object?>{},
  }) : castsShadow = castsShadow ?? type == LevelLightType.directional,
       position = position?.clone() ?? Vector3.zero(),
       direction = direction?.clone() ?? Vector3(0.0, -1.0, 0.0),
       // ignore: prefer_initializing_formals
       _source = source,
       color = color?.clone() ?? Vector3(1.0, 1.0, 1.0),
       id =
           id ??
           LevelIds.derive(<Object?>[
             'light',
             type.wireName,
             name,
             position?.x ?? 0.0,
             position?.y ?? 0.0,
             position?.z ?? 0.0,
           ]);

  /// The document this light was read from. See [writeThrough].
  final Map<String, Object?> _source;

  /// What this light is called by the editor and by tools. See [LevelIds].
  final String id;

  /// This light under another [id], everything else as it is.
  LevelLight withId(String id) =>
      LevelLight.fromJson(<String, Object?>{...toJson(), 'id': id});

  final LevelLightType type;
  final Vector3 position;
  final Vector3 direction;
  final Vector3 color;

  /// The light's strength as the level file stores it: a pre-1.0 unitless
  /// multiple that `Photometric.legacyUnit` turns into candela for a point
  /// or spot light and lux for a directional one.
  final double intensity;

  /// How far a point or spot light reaches, in metres; zero is unbounded.
  final double range;

  /// Whether this light is a candidate for a shadow map.
  ///
  /// A request, not a promise: shadows cost six passes per light, so the
  /// renderer grants it to the nearest couple and ignores the rest.
  ///
  /// **Absent, it depends on the type: true for a directional light, false
  /// for the others.** That is what a level has always drawn. The renderer
  /// used to cast the sun whatever this said and read the flag only for point
  /// and spot lights, so a level that never named it got a sun shadow and no
  /// torch shadows. The renderer reads it for the sun as well now, and this
  /// default keeps every existing level's picture.
  final bool castsShadow;

  final String? name;

  factory LevelLight.fromJson(Map<String, Object?> json) {
    final word = json.textOrNull('type');
    final type = word == null
        ? LevelLightType.point
        : LevelLightType.fromWireName(word) ??
              (throw LevelFormatException(
                'unknown light type "$word"; expected one of '
                '${LevelLightType.values.map((LevelLightType t) => t.wireName).join(', ')}',
              ));
    final id = json['id'];
    if (id != null && (id is! String || id.isEmpty)) {
      throw LevelFormatException('a light\'s "id" must be text, not $id');
    }
    return LevelLight(
      id: id as String?,
      type: type,
      position: json.vector3('at', fallback: Vector3.zero()),
      direction: json.vector3('direction', fallback: Vector3(0.0, -1.0, 0.0)),
      color: json.vector3('color', fallback: Vector3(1.0, 1.0, 1.0)),
      intensity: json.numberOr('intensity', 1.0),
      range: json.numberOr('range', 0.0),
      castsShadow: json.flagOr(
        'castsShadow',
        fallback: type == LevelLightType.directional,
      ),
      name: json.textOrNull('name'),
      source: json,
    );
  }

  Map<String, Object?> toJson() => writeThrough(_source, <WriteThroughField>[
    WriteThroughField('id', id),
    WriteThroughField(
      'type',
      type.wireName,
      whenAbsent: type != LevelLightType.point,
    ),
    WriteThroughField('at', position.toJson(), whenAbsent: position != _origin),
    WriteThroughField(
      'direction',
      direction.toJson(),
      whenAbsent: type != LevelLightType.point,
    ),
    WriteThroughField('color', color.toJson(), whenAbsent: color != _white),
    WriteThroughField('intensity', intensity, whenAbsent: intensity != 1.0),
    WriteThroughField('range', range, whenAbsent: range != 0.0),
    WriteThroughField(
      'castsShadow',
      castsShadow,
      whenAbsent: castsShadow != (type == LevelLightType.directional),
    ),
    WriteThroughField('name', name, whenAbsent: name != null),
  ]);
}
