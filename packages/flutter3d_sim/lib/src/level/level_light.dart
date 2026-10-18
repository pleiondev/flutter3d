import 'package:flutter3d_foundation/flutter3d_foundation.dart' show LightType;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show LinearColor;
import 'package:vector_math/vector_math.dart';

import 'json_reader.dart';
import 'json_write_through.dart';
import 'level_format_exception.dart';
import 'level_ids.dart';

final Vector3 _origin = Vector3.zero();

/// A light placed by the level rather than by the renderer.
final class LevelLight {
  /// A light of [type] (point by default) at [position], pointing along
  /// [direction] (down by default); both are copied. [castsShadow] null
  /// casts for a directional light only, and a null [id] is derived.
  LevelLight({
    String? id,
    this.type = LightType.point,
    Vector3? position,
    Vector3? direction,
    this.color = LinearColor.white,
    this.intensity = defaultIntensity,
    this.range = 0.0,
    bool? castsShadow,
    this.name,
    Map<String, Object?> source = const <String, Object?>{},
  }) : castsShadow = castsShadow ?? type == LightType.directional,
       position = position?.clone() ?? Vector3.zero(),
       direction = direction?.clone() ?? Vector3(0.0, -1.0, 0.0),
       // ignore: prefer_initializing_formals
       _source = source,
       id =
           id ??
           LevelIds.derive(<Object?>[
             'light',
             type.base.name,
             name,
             position?.x ?? 0.0,
             position?.y ?? 0.0,
             position?.z ?? 0.0,
           ]);

  /// Reads a light from its level row, keeping the row for [toJson].
  /// Throws a [LevelFormatException] for an unknown type or an `id` that is
  /// not text.
  factory LevelLight.fromJson(Map<String, Object?> json) {
    final word = json.textOrNull('type');
    final type = word == null
        ? LightType.point
        : LightType.byName(word) ??
              (throw LevelFormatException(
                'unknown light type "$word"; expected one of '
                '${LightType.values.map((LightType t) => t.name).join(', ')}',
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
        fallback: type == LightType.directional,
      ),
      name: json.textOrNull('name'),
      source: json,
    );
  }

  /// The document this light was read from. See [writeThrough].
  final Map<String, Object?> _source;

  /// What this light is called by the editor and by tools. See [LevelIds].
  final String id;

  /// What shape of light it is: point, spot, directional, or a plugin's
  /// kind written as the built-in shape it is lit as.
  final LightType type;

  /// Where a point or spot light stands, in metres in the level's frame.
  final Vector3 position;

  /// Which way a spot or directional light points, in the level's frame;
  /// down unless the document says otherwise.
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
  static const double defaultIntensity = 5790.583578; // π × 1843.2

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

  /// What other entities call this light, a light fixture among them;
  /// null for none.
  final String? name;

  /// This light under another [id], everything else as it is.
  LevelLight withId(String id) =>
      LevelLight.fromJson(<String, Object?>{...toJson(), 'id': id});

  /// This light as a level row, written through the row it was read from.
  Map<String, Object?> toJson() => writeThrough(_source, <WriteThroughField>[
    WriteThroughField('id', id),
    WriteThroughField(
      'type',
      // A plugin's own kind is written as the built-in shape it is lit as:
      // a level names no plugin.
      type.base.name,
      whenAbsent: type != LightType.point,
    ),
    WriteThroughField('at', position.toJson(), whenAbsent: position != _origin),
    WriteThroughField(
      'direction',
      direction.toJson(),
      whenAbsent: type != LightType.point,
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
      whenAbsent: castsShadow != (type == LightType.directional),
    ),
    WriteThroughField('name', name, whenAbsent: name != null),
  ]);
}
