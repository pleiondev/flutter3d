import '../save/state_digest.dart';
import 'entity_types.dart';
import 'level.dart';

/// What changed between two versions of one level, split by who has to act
/// on it.
///
/// **The split is the whole point.** An editor saves a level while the game
/// is running it, and the game has two ways to take the change. What only the
/// picture reads — a light, a material, the fog, the music — can be patched
/// into the running scene as it is, and nothing the simulation computed is
/// disturbed. What the simulation reads — brushes it collides with, entities
/// it spawned, the ground — cannot: patched in place, the run would carry on
/// from a state no run of the new level could have reached, and a replay of
/// it would disagree with the run it recorded. That half goes through a
/// timeline branch instead (`RunTimeline.swapLevel`).
///
/// **Conservative on purpose.** A brush whose only change is its material
/// looks presentational, and usually is — but a brush's surface falls back to
/// its material, and a surface is what footsteps and friction read. A
/// classifier that is sometimes too careful costs a replay; one that is
/// sometimes too bold costs a run that cannot be reproduced. So anything
/// under [simulation] is judged by the whole part, not by a guess at which of
/// its fields the game reads.
final class LevelDiff {
  const LevelDiff({
    this.lights = const <int>[],
    this.lightCountChanged = false,
    this.materials = const <String>[],
    this.fog = false,
    this.music = false,
    this.simulation = const <String>[],
  });

  /// Lights changed in place, by index in the level's list.
  final List<int> lights;

  /// Lights were added or removed, so indices past the shorter list mean
  /// nothing; a presenter rebuilds the lights rather than patching them.
  final bool lightCountChanged;

  /// Materials added, removed or changed, by name.
  final List<String> materials;

  /// The fog's colour or density changed.
  final bool fog;

  /// The music changed.
  final bool music;

  /// Which parts the simulation reads changed: `brushes`, `entities`,
  /// `heightfield`, `recipes`, `next`. Empty when the change can be patched
  /// into a running scene without touching the run.
  final List<String> simulation;

  /// Whether nothing changed at all.
  bool get isEmpty =>
      lights.isEmpty &&
      !lightCountChanged &&
      materials.isEmpty &&
      !fog &&
      !music &&
      simulation.isEmpty;

  /// Whether the change can be patched in without a timeline branch.
  bool get isPresentationOnly => simulation.isEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'lights': lights,
    'lightCountChanged': lightCountChanged,
    'materials': materials,
    'fog': fog,
    'music': music,
    'simulation': simulation,
  };
}

/// Compares [before] and [after], part by part, through their documents.
///
/// Through `toJson` rather than field by field: the document is what a level
/// *is* to the editor that wrote it, and a field added to a part later is
/// compared the day it is added, with nothing here to remember.
///
/// **Ids are left out of the comparison.** An id is what a tool calls a
/// thing, not what the thing is, and a level that only had its ids given —
/// a version 2 file written again as version 3 by a tool that hands out
/// fresh ids, where this build derives them — is the same level: no
/// collider, spawn or light moved. So a row is compared without its `id`,
/// and a prefab instance's overrides, which version 3 addresses by id path,
/// are compared by the place each path reaches in its template
/// (`#<index>/#<index>`). The rest of the format rewrite (properties moved
/// under `props`, overrides by name) is already the same document once read.
LevelDiff diffLevel(Level before, Level after) {
  String digest(Object? json) => contentDigestHex(<String, Object?>{'v': json});
  bool differs(Object? a, Object? b) => digest(a) != digest(b);

  final oldLights = before.lights;
  final newLights = after.lights;
  final shared = oldLights.length < newLights.length
      ? oldLights.length
      : newLights.length;

  List<Object?> entities(Level level) => <Object?>[
    for (final e in level.entities) _entityWithoutIds(e, level.prefabs),
  ];
  Map<String, Object?> prefabs(Level level) => <String, Object?>{
    for (final MapEntry(:key, :value) in level.prefabs.entries)
      key: <Object?>[
        for (final e in value.entities) _entityWithoutIds(e, level.prefabs),
      ],
  };

  final names = <String>{...before.materials.keys, ...after.materials.keys};
  return LevelDiff(
    lights: <int>[
      for (var i = 0; i < shared; i++)
        if (differs(
          _withoutId(oldLights[i].toJson()),
          _withoutId(newLights[i].toJson()),
        ))
          i,
    ],
    lightCountChanged: oldLights.length != newLights.length,
    materials: <String>[
      for (final name in names)
        if (differs(
          before.materials[name]?.toJson(),
          after.materials[name]?.toJson(),
        ))
          name,
    ],
    fog:
        before.fogColor != after.fogColor ||
        before.fogDensity != after.fogDensity,
    music: before.music != after.music,
    simulation: <String>[
      if (differs(
        <Object?>[for (final b in before.brushes) _withoutId(b.toJson())],
        <Object?>[for (final b in after.brushes) _withoutId(b.toJson())],
      ))
        'brushes',
      if (differs(entities(before), entities(after))) 'entities',
      if (differs(before.heightfield?.toJson(), after.heightfield?.toJson()))
        'heightfield',
      if (differs(
        <Object?>[for (final r in before.recipes) r.toJson()],
        <Object?>[for (final r in after.recipes) r.toJson()],
      ))
        'recipes',
      // A template's edit is an edit of every instance's entities.
      if (differs(prefabs(before), prefabs(after))) 'prefabs',
      if (before.next != after.next) 'next',
      if (differs(before.world, after.world)) 'world',
    ],
  );
}

/// [row] without its `id`.
Map<String, Object?> _withoutId(Map<String, Object?> row) => <String, Object?>{
  for (final MapEntry(:key, :value) in row.entries)
    if (key != 'id') key: value,
};

/// [entity]'s document without its id, and, for a prefab instance, with its
/// overrides keyed by the place each id path reaches in [prefabs] rather
/// than by the ids on the way.
Map<String, Object?> _entityWithoutIds(
  EntityDef entity,
  Map<String, Prefab> prefabs,
) {
  final row = _withoutId(entity.toJson());
  final template = entity.properties['prefab'];
  final overrides = entity.properties['overrides'];
  if (entity.type != EntityTypes.prefab ||
      template is! String ||
      overrides is! Map<Object?, Object?>) {
    return row;
  }
  return <String, Object?>{
    ...row,
    'props': <String, Object?>{
      ...entity.properties,
      'overrides': <String, Object?>{
        for (final MapEntry(:key, :value) in overrides.entries)
          _placeOf('$key'.split('/'), template, prefabs, const <String>[]) ??
                  '$key':
              value,
      },
    },
  };
}

/// The id path [segments], walked from prefab [prefab], as the index of each
/// entity it passes in its template: `#2/#0`. Null when a segment names
/// nothing, so the path is compared as it was written.
String? _placeOf(
  List<String> segments,
  String prefab,
  Map<String, Prefab> prefabs,
  List<String> stack,
) {
  final template = prefabs[prefab];
  if (template == null || stack.contains(prefab)) return null;
  final hit = template.entities.indexed
      .where(((int, EntityDef) it) => it.$2.id == segments.first)
      .firstOrNull;
  if (hit == null) return null;
  final (index, entity) = hit;
  if (segments.length == 1) return '#$index';
  final nested = entity.properties['prefab'];
  if (nested is! String) return null;
  final rest = _placeOf(segments.sublist(1), nested, prefabs, <String>[
    ...stack,
    prefab,
  ]);
  return rest == null ? null : '#$index/$rest';
}
