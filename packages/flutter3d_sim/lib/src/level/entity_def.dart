import 'package:vector_math/vector_math.dart';

import 'json_reader.dart';
import 'json_write_through.dart';
import 'level_format_exception.dart';
import 'level_ids.dart';

/// Anything in the level that is not geometry: a spawn, a monster, a pickup, a
/// door, a trigger, a note on the wall.
///
/// One type with a property bag, rather than a class per kind. There will be
/// thirty kinds before the game is finished, the editor has to handle them all
/// the same way, and a class hierarchy buys type safety at exactly the layer
/// that reads them from JSON and therefore cannot have it anyway. The typed
/// accessors below are where the safety actually goes.
///
/// ## The row in a document
///
/// ```json
/// {"id": "k3f9a2b1", "type": "torch", "at": [1, 0, 2], "name": "east",
///  "props": {"radius": 3}, "components": {"glow_plugin": {"tint": [1, 0.5, 0]}}}
/// ```
///
/// **Since level format 3 the top level of a row is the engine's**, every
/// key of it listed in [reservedKeys], and what a game says about an entity
/// goes under `props`; what a plugin says goes under `components.<its
/// namespace>`. That keeps a later release free to add a top-level key — a
/// layer, a rotation — without colliding with a property somebody already
/// called that. A row without `props` is the older shape, where every key
/// that is not reserved is a property, and it still reads; it is written
/// back in the new shape.
final class EntityDef {
  /// An entity of [type] at [position] (the origin when null, copied
  /// otherwise), facing [yaw] radians. A null [id] is derived from the
  /// type, name, position and yaw.
  EntityDef({
    required this.type,
    String? id,
    Vector3? position,
    this.yaw = 0.0,
    this.name,
    Map<String, Object?>? properties,
    Map<String, Map<String, Object?>>? components,
    this.physicalMaterial,
    Map<String, Object?> source = const <String, Object?>{},
  }) : position = position?.clone() ?? Vector3.zero(),
       // ignore: prefer_initializing_formals
       _source = source,
       properties = Map<String, Object?>.unmodifiable(
         properties ?? const <String, Object?>{},
       ),
       components = Map<String, Map<String, Object?>>.unmodifiable(
         components ?? const <String, Map<String, Object?>>{},
       ),
       id =
           id ??
           LevelIds.derive(<Object?>[
             'entity',
             type,
             name,
             position?.x ?? 0.0,
             position?.y ?? 0.0,
             position?.z ?? 0.0,
             yaw,
           ]);

  /// Reads a row in either shape: with `props` (format 3), or with its
  /// properties at the top (before it).
  factory EntityDef.fromJson(Map<String, Object?> json) {
    final type = json['type'];
    if (type is! String || type.isEmpty) {
      throw const LevelFormatException('an entity has no "type"');
    }
    final id = json['id'];
    if (id != null && (id is! String || id.isEmpty)) {
      throw LevelFormatException('an entity\'s "id" must be text, not $id');
    }
    // `physicalMaterial` was reserved by format 5, long after `props`, so a
    // row naming it is in the newer shape whatever else it says.
    final shaped =
        json.containsKey('props') ||
        json.containsKey('components') ||
        json.containsKey('physicalMaterial');
    // The older shape: everything not reserved is a property, so the format
    // grew by writing new keys. Moved under `props` on the way in, so the
    // row is written back in the shape this build writes.
    final row = shaped
        ? json
        : <String, Object?>{
            for (final entry in json.entries)
              if (_legacyReserved.contains(entry.key)) entry.key: entry.value,
            if (json.keys.any((String key) => !_legacyReserved.contains(key)))
              'props': <String, Object?>{
                for (final entry in json.entries)
                  if (!_legacyReserved.contains(entry.key))
                    entry.key: entry.value,
              },
          };
    return EntityDef(
      type: type,
      id: id as String?,
      position: row.vector3('at', fallback: Vector3.zero()),
      yaw: row.numberOr('yaw', 0.0),
      name: row.textOrNull('name'),
      properties: switch (row['props']) {
        null => null,
        final Map<Object?, Object?> props => <String, Object?>{
          for (final MapEntry(:key, :value) in props.entries) '$key': value,
        },
        final other => throw LevelFormatException(
          'an entity\'s "props" must be an object, not $other',
        ),
      },
      components: row.objectMap('components'),
      physicalMaterial: switch (row['physicalMaterial']) {
        null => null,
        final String id when id.isNotEmpty => id,
        final other => throw LevelFormatException(
          'an entity\'s "physicalMaterial" must be a material\'s id, not '
          '$other',
        ),
      },
      source: row,
    );
  }

  /// The document this entity was read from. See [writeThrough].
  final Map<String, Object?> _source;

  /// What this entity is called by everything that has to find it again —
  /// a prefab override, the editor's selection. See [LevelIds]; given when
  /// the entity is made, derived from what it is otherwise.
  final String id;

  /// The kind of thing it is, as `EntityKinds` knows it: `torch`,
  /// `playerSpawn`, a game's own word. Never empty.
  final String type;

  /// Where it stands, in metres in the level's frame.
  final Vector3 position;

  /// Facing, in radians about Y. Nothing in this game tilts.
  final double yaw;

  /// Referred to by other entities — the lift a button calls, the door a key
  /// opens. For people and for references between entities; a tool that has
  /// to find this entity again uses [id].
  final String? name;

  /// What the game says about this entity: the row's `props`.
  final Map<String, Object?> properties;

  /// What plugins say about this entity, by the plugin's namespace: the
  /// row's `components`. A level that holds any names their namespaces in
  /// its envelope's `requires`, so a reader without the plugin refuses the
  /// level rather than dropping them.
  final Map<String, Map<String, Object?>> components;

  /// The substance this entity's body is made of: the id of a material in
  /// the engine's `MaterialCatalog` (`f3d.oak`, `<pluginId>.basalt`), or
  /// null for the material its kind gives it. The row's `physicalMaterial`;
  /// a level naming one no installed plugin declares is refused
  /// (`Level.requireMaterials`).
  final String? physicalMaterial;

  /// The top-level keys of a row, which belong to the format and never reach
  /// [properties].
  ///
  /// `type`, `id`, `at`, `yaw`, `name`, `props`, `components` and
  /// `physicalMaterial` are read today; `layer`, `rotation`, `scale`, `tags`, `parent` and `enabled` are
  /// held back for later minors, so no game can have used them for a
  /// property of its own by then.
  static const Set<String> reservedKeys = <String>{
    'type',
    'id',
    'at',
    'yaw',
    'name',
    'props',
    'components',
    'physicalMaterial',
    'layer',
    'rotation',
    'scale',
    'tags',
    'parent',
    'enabled',
  };

  /// The keys a row had before format 3, the only ones that were never
  /// properties. Everything else at the top of such a row is one.
  static const Set<String> _legacyReserved = <String>{
    'type',
    'id',
    'at',
    'yaw',
    'name',
  };

  /// The text property [key], or null when it is absent. A value that is
  /// not text throws a [TypeError].
  String? string(String key) => properties[key] as String?;

  /// The number property [key] as a double, or null when it is absent or
  /// not a number.
  double? number(String key) {
    final value = properties[key];
    if (value is num) return value.toDouble();
    return null;
  }

  /// The number property [key] truncated to an int, or null when it is
  /// absent or not a number.
  int? integer(String key) {
    final value = properties[key];
    if (value is num) return value.toInt();
    return null;
  }

  /// The bool property [key], or [orElse] when it is absent. A value that
  /// is not a bool throws a [TypeError].
  bool flag(String key, {bool orElse = false}) =>
      properties[key] as bool? ?? orElse;

  /// The property [key] as a vector from its first three numbers, or null
  /// when it is not a list of at least three.
  Vector3? vector(String key) {
    final value = properties[key];
    if (value is! List || value.length < 3) return null;
    return Vector3(
      (value[0] as num).toDouble(),
      (value[1] as num).toDouble(),
      (value[2] as num).toDouble(),
    );
  }

  /// This entity under another [id], everything else as it is.
  EntityDef withId(String id) =>
      EntityDef.fromJson(<String, Object?>{...toJson(), 'id': id});

  /// This entity as a level row in the format-3 shape, written through the
  /// row it was read from so unknown keys survive.
  Map<String, Object?> toJson() => writeThrough(_source, <WriteThroughField>[
    WriteThroughField('id', id),
    WriteThroughField('type', type),
    WriteThroughField(
      'at',
      position.toJson(),
      whenAbsent: position != Vector3.zero(),
    ),
    WriteThroughField('yaw', yaw, whenAbsent: yaw != 0.0),
    WriteThroughField('name', name, whenAbsent: name != null),
    WriteThroughField('props', <String, Object?>{
      for (final entry in properties.entries) entry.key: entry.value,
    }, whenAbsent: properties.isNotEmpty),
    WriteThroughField('components', <String, Object?>{
      for (final entry in components.entries) entry.key: entry.value,
    }, whenAbsent: components.isNotEmpty),
    WriteThroughField(
      'physicalMaterial',
      physicalMaterial,
      whenAbsent: physicalMaterial != null,
    ),
  ]);
}
