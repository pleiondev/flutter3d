import 'package:vector_math/vector_math.dart';

import 'json_reader.dart';
import 'json_write_through.dart';
import 'level_format_exception.dart';

/// Anything in the level that is not geometry: a spawn, a monster, a pickup, a
/// door, a trigger, a note on the wall.
///
/// One type with a property bag, rather than a class per kind. There will be
/// thirty kinds before the game is finished, the editor has to handle them all
/// the same way, and a class hierarchy buys type safety at exactly the layer
/// that reads them from JSON and therefore cannot have it anyway. The typed
/// accessors below are where the safety actually goes.
final class EntityDef {
  EntityDef({
    required this.type,
    Vector3? position,
    this.yaw = 0.0,
    this.name,
    Map<String, Object?>? properties,
    Map<String, Object?> source = const <String, Object?>{},
  }) : position = position?.clone() ?? Vector3.zero(),
       // ignore: prefer_initializing_formals
       _source = source,
       properties = Map<String, Object?>.unmodifiable(
         properties ?? const <String, Object?>{},
       );

  /// The document this entity was read from. See [writeThrough].
  final Map<String, Object?> _source;

  final String type;
  final Vector3 position;

  /// Facing, in radians about Y. Nothing in this game tilts.
  final double yaw;

  /// Referred to by other entities — the lift a button calls, the door a key
  /// opens.
  final String? name;

  final Map<String, Object?> properties;

  /// Keys the entity itself owns, which therefore never reach [properties].
  static const Set<String> reservedKeys = <String>{'type', 'at', 'yaw', 'name'};

  String? string(String key) => properties[key] as String?;

  double? number(String key) {
    final value = properties[key];
    if (value is num) return value.toDouble();
    return null;
  }

  int? integer(String key) {
    final value = properties[key];
    if (value is num) return value.toInt();
    return null;
  }

  bool flag(String key, {bool orElse = false}) =>
      properties[key] as bool? ?? orElse;

  Vector3? vector(String key) {
    final value = properties[key];
    if (value is! List || value.length < 3) return null;
    return Vector3(
      (value[0] as num).toDouble(),
      (value[1] as num).toDouble(),
      (value[2] as num).toDouble(),
    );
  }

  factory EntityDef.fromJson(Map<String, Object?> json) {
    final type = json['type'];
    if (type is! String || type.isEmpty) {
      throw const LevelFormatException('an entity has no "type"');
    }
    // Everything not reserved is a property, so the format grows by writing
    // new keys rather than by changing the reader.
    final properties = <String, Object?>{
      for (final entry in json.entries)
        if (!reservedKeys.contains(entry.key)) entry.key: entry.value,
    };
    return EntityDef(
      type: type,
      position: json.vector3('at', fallback: Vector3.zero()),
      yaw: json.numberOr('yaw', 0.0),
      name: json.textOrNull('name'),
      properties: properties,
      source: json,
    );
  }

  Map<String, Object?> toJson() => writeThrough(_source, <WriteThroughField>[
    WriteThroughField('type', type),
    WriteThroughField('at', position.toJson()),
    WriteThroughField('yaw', yaw, whenAbsent: yaw != 0.0),
    WriteThroughField('name', name, whenAbsent: name != null),
    for (final entry in properties.entries)
      WriteThroughField(entry.key, entry.value),
  ]);
}
