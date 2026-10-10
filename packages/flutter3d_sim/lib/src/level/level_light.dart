import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show LinearColor;
import 'package:vector_math/vector_math.dart';

import 'json_reader.dart';
import 'json_write_through.dart';
import 'legacy_light_unit.dart';
import 'level_format_exception.dart';
import 'level_ids.dart';

final Vector3 _origin = Vector3.zero();

/// What kind of light a level places.
///
/// **An open set, not an enum** (ARCHITECTURE.md §13.1): a later minor may
/// add a kind — an area light, a sky portal — and a `switch` written against
/// three values would stop compiling on it. A `switch` over these ends with
/// a wildcard.
///
/// **Its word in a document is [wireName]**, a table of the format's and
/// not a Dart identifier, so a rename here never changes what a saved level
/// says.
final class LevelLightType {
  const LevelLightType._(this.wireName);

  /// The sun: parallel rays from [LevelLight.direction], in lux.
  static const LevelLightType directional = LevelLightType._('directional');

  /// A bulb: light in every direction from [LevelLight.position], in
  /// candela.
  static const LevelLightType point = LevelLightType._('point');

  /// A bulb with a cone along [LevelLight.direction], in candela.
  static const LevelLightType spot = LevelLightType._('spot');

  /// Every type this build knows, in the order the format lists them.
  static const List<LevelLightType> values = <LevelLightType>[
    directional,
    point,
    spot,
  ];

  /// The word a level document writes for this type.
  final String wireName;

  /// The type a document's word names, or null for a word that is not one.
  static LevelLightType? fromWireName(String word) {
    for (final type in values) {
      if (type.wireName == word) return type;
    }
    return null;
  }

  @override
  String toString() => wireName;
}

/// A light placed by the level rather than by the renderer.
final class LevelLight {
  LevelLight({
    String? id,
    this.type = LevelLightType.point,
    Vector3? position,
    Vector3? direction,
    this.color = LinearColor.white,
    this.intensity = defaultIntensity,
    this.range = 0.0,
    bool? castsShadow,
    this.name,
    Map<String, Object?> source = const <String, Object?>{},
  }) : castsShadow = castsShadow ?? type == LevelLightType.directional,
       position = position?.clone() ?? Vector3.zero(),
       direction = direction?.clone() ?? Vector3(0.0, -1.0, 0.0),
       // ignore: prefer_initializing_formals
       _source = source,
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

  /// The light's colour, in linear light. Its brightness is [intensity]'s:
  /// white is `LinearColor.white`, and a colour brighter than white is a
  /// strength written in the wrong field.
  final LinearColor color;

  /// The light's strength: candela for a point or spot light, lux for a
  /// directional one — what the renderer's `LightNode.intensity` takes, with
  /// nothing in between.
  ///
  /// **Photometric since format 5.** A document of version 4 or older wrote
  /// a pre-1.0 unitless multiple, and is lifted by multiplying it by that
  /// unit (`π × 1843.2`, about 5 790.6), so every saved level draws as
  /// bright as it did.
  final double intensity;

  /// The strength of a light that does not say one, in candela or lux: one
  /// pre-1.0 unit, so a light a document left at its default keeps the
  /// brightness it had across the lift.
  static const double defaultIntensity = legacyLightUnit;

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
      color: json.linearColor('color', fallback: LinearColor.white),
      intensity: json.numberOr('intensity', defaultIntensity),
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
    WriteThroughField(
      'color',
      color.toJson(),
      whenAbsent: color != LinearColor.white,
    ),
    WriteThroughField(
      'intensity',
      intensity,
      whenAbsent: intensity != defaultIntensity,
    ),
    WriteThroughField('range', range, whenAbsent: range != 0.0),
    WriteThroughField(
      'castsShadow',
      castsShadow,
      whenAbsent: castsShadow != (type == LevelLightType.directional),
    ),
    WriteThroughField('name', name, whenAbsent: name != null),
  ]);
}
