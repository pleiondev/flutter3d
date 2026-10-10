import 'package:flutter3d_foundation/flutter3d_foundation.dart' show Portable;
import 'package:vector_math/vector_math.dart';

import 'entity_types.dart';
import 'json_reader.dart';
import 'json_write_through.dart';
import 'level.dart';
import 'level_issue.dart';

/// What an instance changes in its prefab: entity path to the keys changed
/// there.
///
/// **The path is the [EntityDef.id]s of the entities walked through**, joined
/// by `/` — `k3f9a2b1` for an entity of the prefab itself, `p0st0001/k3f9a2b1`
/// for one inside the nested instance `p0st0001`. Ids, not names, so renaming
/// or reordering an entity inside a prefab does not silently retarget the
/// overrides written against it; names are for display. A level written
/// before format 3 addressed entities by name or `#<index>`, and its
/// overrides are turned into id paths when it is read.
///
/// A key is any key the entity's row may carry — `at`, `yaw` or a property —
/// and `light.intensity` reaches into a property that is itself an object,
/// one field of one component. A key that is not one of the row's own
/// ([EntityDef.reservedKeys]) is a property, so `health` and `props.health`
/// say the same thing. A null value takes the key away.
typedef PrefabOverrides = Map<String, Map<String, Object?>>;

/// A template: a tree of entities a level places as one thing, as often as
/// it likes.
///
/// **A tree because an entity of a prefab may itself be an instance** — a
/// row of type [EntityTypes.prefab] — and that instance's prefab is expanded
/// inside this one. A prefab that reaches itself that way is a cycle, which
/// [expandPrefabs] refuses by naming it.
///
/// Positions in [entities] are relative to the instance: its `at` is where
/// the prefab's origin lands, and its `yaw` turns everything about it.
///
/// **Entities only.** A brush or a light in a template is a later addition;
/// what a prefab is for first is the props and fixtures a level repeats —
/// a torch post with its light, a guard post with its patrol, a door with
/// its button — and those are entities.
final class Prefab {
  Prefab({
    List<EntityDef>? entities,
    Map<String, Object?> source = const <String, Object?>{},
  }) : entities = LevelIds.unique(
         entities ?? <EntityDef>[],
         idOf: (EntityDef e) => e.id,
         withId: (EntityDef e, String id) => e.withId(id),
         taken: <String>{},
       ),
       // ignore: prefer_initializing_formals
       _source = source;

  factory Prefab.fromJson(Map<String, Object?> json) => Prefab(
    entities: json.objects('entities').map(EntityDef.fromJson).toList(),
    source: json,
  );

  /// The document this prefab was read from. See [writeThrough].
  final Map<String, Object?> _source;

  /// The template's entities, in the order an instance expands them.
  final List<EntityDef> entities;

  Map<String, Object?> toJson() => writeThrough(_source, <WriteThroughField>[
    WriteThroughField(
      'entities',
      entities.map((EntityDef e) => e.toJson()).toList(),
    ),
  ]);
}

/// An entity read as a prefab instance: which prefab, and what it changes.
///
/// A view rather than a kind of its own, because an instance *is* an entity
/// row — it has a place, a facing and a name like any other, and everything
/// that moves, copies or deletes an entity works on it unchanged. Two keys
/// make it an instance: `prefab`, the template's id in [Level.prefabs], and
/// `overrides`, a [PrefabOverrides].
///
/// **Override precedence, nearest the level wins.** A key is decided by the
/// first of these that says it:
///
/// 1. the level's instance's [overrides];
/// 2. the overrides a nested instance carries inside its parent's template,
///    then those of the instance above that, outward to the template;
/// 3. the template's own row.
///
/// So the person editing the level has the last word over the person who
/// built the prefab, and the prefab's author over the one who built the
/// prefab inside it.
final class PrefabInstance {
  const PrefabInstance._(this.entity, this.prefab, this.overrides);

  /// [entity] as an instance, or null when it is not one.
  ///
  /// Throws [LevelFormatException] for a row of type [EntityTypes.prefab]
  /// that names no prefab or whose overrides are not a map of maps.
  static PrefabInstance? of(EntityDef entity) {
    if (entity.type != EntityTypes.prefab) return null;
    final id = entity.properties['prefab'];
    if (id is! String || id.isEmpty) {
      throw LevelFormatException(
        'a prefab instance${entity.name == null ? '' : ' "${entity.name}"'} '
        'names no "prefab"',
      );
    }
    return PrefabInstance._(entity, id, readOverrides(entity.properties));
  }

  /// The overrides [properties] carries under `overrides`, or none.
  static PrefabOverrides readOverrides(Map<String, Object?> properties) =>
      switch (properties['overrides']) {
        null => const <String, Map<String, Object?>>{},
        final Map<Object?, Object?> given => <String, Map<String, Object?>>{
          for (final MapEntry(:key, :value) in given.entries)
            '$key': switch (value) {
              final Map<Object?, Object?> keys => <String, Object?>{
                for (final MapEntry(:key, :value) in keys.entries)
                  '$key': value,
              },
              _ => throw LevelFormatException(
                'the override of "$key" must be an object of keys',
              ),
            },
        },
        _ => throw const LevelFormatException('"overrides" must be an object'),
      };

  /// An instance row of [prefab], ready for a level's entities.
  static EntityDef create(
    String prefab, {
    Vector3? at,
    double yaw = 0.0,
    String? name,
    PrefabOverrides overrides = const <String, Map<String, Object?>>{},
  }) => EntityDef(
    type: EntityTypes.prefab,
    position: at,
    yaw: yaw,
    name: name,
    properties: <String, Object?>{
      'prefab': prefab,
      if (overrides.isNotEmpty) 'overrides': overrides,
    },
  );

  /// The row this was read from.
  final EntityDef entity;

  /// The template's id in [Level.prefabs].
  final String prefab;

  /// What this instance changes, by path.
  final PrefabOverrides overrides;
}

/// The keys of a row an override may not touch: what the row *is*.
///
/// `type` and `prefab` would make the overridden thing another thing, which
/// is an edit of the template rather than of one instance; `id` is the path
/// every other override is addressed by, and `name` is what the expanded
/// entities are called by and referred to with.
const Set<String> _fixedKeys = <String>{'type', 'prefab', 'name', 'id'};

/// [row] with [keys] written into it: a dotted key reaches into a nested
/// object, and a null value removes the key.
///
/// A key that is not one of the row's own ([EntityDef.reservedKeys]) is a
/// property and is written under `props`; [row] in the shape from before
/// format 3, with its properties at the top, is read into that shape first.
///
/// Copies every map it walks through, so the row it was given is untouched.
Map<String, Object?> applyPrefabOverride(
  Map<String, Object?> row,
  Map<String, Object?> keys,
) => keys.entries.fold(EntityDef.fromJson(row).toJson(), (
  Map<String, Object?> out,
  MapEntry<String, Object?> entry,
) {
  final given = entry.key.split('.');
  final steps = EntityDef.reservedKeys.contains(given.first)
      ? given
      : <String>['props', ...given];
  final what = steps.first == 'props' && steps.length > 1 ? steps[1] : null;
  if (_fixedKeys.contains(given.first) || what == 'prefab') {
    throw LevelFormatException('an override may not change "${entry.key}"');
  }
  _write(out, steps, entry.value);
  return out;
});

void _write(Map<String, Object?> into, List<String> steps, Object? value) {
  final head = steps.first;
  if (steps.length == 1) {
    if (value == null) {
      into.remove(head);
    } else {
      into[head] = value;
    }
    return;
  }
  final inner = <String, Object?>{
    ...switch (into[head]) {
      final Map<Object?, Object?> map => <String, Object?>{
        for (final MapEntry(:key, :value) in map.entries) '$key': value,
      },
      _ => const <String, Object?>{},
    },
  };
  _write(inner, steps.sublist(1), value);
  into[head] = inner;
}

/// The path segment [entity] is addressed by in its prefab: its id.
String prefabSegment(EntityDef entity) => entity.id;

/// The segment a level from before format 3 addressed [entity], number
/// [index] in its prefab, by: its name, or `#<index>`.
String _legacySegment(EntityDef entity, int index) => entity.name ?? '#$index';

/// [overrides], written against prefab [id] by name or `#<index>` before
/// format 3, as id paths: each segment is looked up in the prefab it walks
/// through. A segment that names nothing is kept as it was, so
/// [prefabIssues] still reports it.
PrefabOverrides legacyOverridesToIds(
  PrefabOverrides overrides,
  String id,
  Map<String, Prefab> prefabs,
) {
  String? resolve(String prefab, List<String> segments, List<String> stack) {
    final template = prefabs[prefab];
    if (template == null || stack.contains(prefab)) return null;
    final hit = template.entities.indexed
        .where(
          ((int, EntityDef) it) =>
              _legacySegment(it.$2, it.$1) == segments.first ||
              it.$2.id == segments.first,
        )
        .firstOrNull;
    if (hit == null) return null;
    final entity = hit.$2;
    if (segments.length == 1) return entity.id;
    final nested = entity.properties['prefab'];
    if (entity.type != EntityTypes.prefab || nested is! String) return null;
    final rest = resolve(nested, segments.sublist(1), <String>[
      ...stack,
      prefab,
    ]);
    return rest == null ? null : '${entity.id}/$rest';
  }

  return <String, Map<String, Object?>>{
    for (final MapEntry(:key, :value) in overrides.entries)
      resolve(id, key.split('/'), const <String>[]) ?? key: value,
  };
}

/// The first chain of prefabs that reaches itself, as ids from the one it
/// starts at back to that one again, or null when there is none.
List<String>? prefabCycle(Map<String, Prefab> prefabs) {
  final done = <String>{};
  List<String>? walk(String id, List<String> stack) {
    if (stack.contains(id)) {
      return <String>[...stack.sublist(stack.indexOf(id)), id];
    }
    if (done.contains(id)) return null;
    final prefab = prefabs[id];
    if (prefab == null) return null;
    final deeper = <String>[...stack, id];
    for (final entity in prefab.entities) {
      if (entity.type != EntityTypes.prefab) continue;
      final next = entity.properties['prefab'];
      if (next is! String) continue;
      final found = walk(next, deeper);
      if (found != null) return found;
    }
    done.add(id);
    return null;
  }

  for (final id in prefabs.keys) {
    final found = walk(id, const <String>[]);
    if (found != null) return found;
  }
  return null;
}

/// The overrides a nested instance at [segment] receives from [outer]: the
/// ones whose path goes through it, with the segment taken off.
PrefabOverrides _through(
  PrefabOverrides outer,
  String segment,
) => <String, Map<String, Object?>>{
  for (final MapEntry(:key, :value) in outer.entries)
    if (key.startsWith('$segment/')) key.substring(segment.length + 1): value,
};

/// [inner] and [outer] as one set, [outer]'s key winning where both say one.
PrefabOverrides mergePrefabOverrides(
  PrefabOverrides inner,
  PrefabOverrides outer,
) => <String, Map<String, Object?>>{
  ...inner,
  for (final MapEntry(:key, :value) in outer.entries)
    // [outer]'s keys after every one of [inner]'s, rather than in the place
    // an equal key of [inner] held: they are applied in order, and a whole
    // `glow` of [inner] written after [outer]'s `glow.tint` would undo it.
    key: <String, Object?>{
      for (final MapEntry(key: k, value: v) in (inner[key] ?? const {}).entries)
        if (!value.containsKey(k)) k: v,
      ...value,
    },
};

/// The entities [instance] stands for, placed in the level.
///
/// [deep] false stops at the first level — a nested instance comes out as
/// an instance, carrying the overrides that reached it — which is what
/// unpacking one instance does; true expands all the way down, which is
/// what a level is played with.
///
/// Names are the instance's name and the entity's joined by `/` — two
/// copies of one prefab must not give two things one name — and an
/// instance without a name hands its entities' names through unchanged.
/// **A reference inside a property is not rewritten**: a button in a prefab
/// that calls a lift by name calls the level's entity of that name.
///
/// Throws [LevelFormatException] for a prefab the level does not have or a
/// chain of prefabs that reaches itself.
List<EntityDef> expandPrefabInstance(
  PrefabInstance instance,
  Map<String, Prefab> prefabs, {
  bool deep = true,
}) => _expand(
  instance.prefab,
  instance.overrides,
  prefabs,
  const <String>[],
  deep: deep,
).map((EntityDef e) => _placed(e, instance.entity)).toList();

List<EntityDef> _expand(
  String id,
  PrefabOverrides overrides,
  Map<String, Prefab> prefabs,
  List<String> stack, {
  required bool deep,
}) {
  if (stack.contains(id)) {
    throw LevelFormatException(
      'prefab "$id" contains itself: ${<String>[...stack, id].join(' → ')}',
    );
  }
  final prefab =
      prefabs[id] ??
      (throw LevelFormatException(
        'prefab "$id" is not one the level has'
        '${prefabs.isEmpty ? '' : ' (${prefabs.keys.join(', ')})'}',
      ));
  final out = <EntityDef>[];
  for (final template in prefab.entities) {
    final segment = prefabSegment(template);
    final own = overrides[segment];
    final row = own == null
        ? template
        : EntityDef.fromJson(applyPrefabOverride(template.toJson(), own));
    final nested = PrefabInstance.of(row);
    if (nested == null) {
      out.add(row);
      continue;
    }
    final reaching = mergePrefabOverrides(
      nested.overrides,
      _through(overrides, segment),
    );
    // Walked even when not kept, so a cycle or a missing prefab below is
    // refused here rather than at the next load.
    final below = _expand(nested.prefab, reaching, prefabs, <String>[
      ...stack,
      id,
    ], deep: true);
    if (deep) {
      out.addAll(below.map((EntityDef e) => _placed(e, row)));
      continue;
    }
    out.add(
      EntityDef(
        type: row.type,
        id: row.id,
        position: row.position,
        yaw: row.yaw,
        name: row.name,
        properties: <String, Object?>{
          for (final MapEntry(:key, :value) in row.properties.entries)
            if (key != 'overrides') key: value,
          if (reaching.isNotEmpty) 'overrides': reaching,
        },
        components: row.components,
      ),
    );
  }
  return out;
}

/// [entity], whose place is relative to [parent], put where [parent] puts it.
///
/// Its id becomes the path from [parent] — `<instance id>/<entity id>` — so
/// two copies of one prefab expand into entities with ids of their own, and
/// the id of an expanded entity is the path an override of it is written to.
EntityDef _placed(EntityDef entity, EntityDef parent) {
  // Turned by `Portable`'s sine and cosine, not `Matrix3.rotationY`, which
  // asks libm: a yawed instance expanded to other bits in a browser than in
  // the VM, from step 0, under the same `SimulationVersion`.
  final (:sin, :cos) = Portable.sinCos(parent.yaw);
  final local = entity.position;
  final turned = Vector3(
    cos * local.x + sin * local.z,
    local.y,
    cos * local.z - sin * local.x,
  );
  final name = switch ((parent.name, entity.name)) {
    (final String outer, final String inner) => '$outer/$inner',
    (_, final inner) => inner,
  };
  return EntityDef.fromJson(
    <String, Object?>{
      ...entity.toJson(),
      'id': '${parent.id}/${entity.id}',
      'at': (parent.position + turned).toJson(),
      'yaw': parent.yaw + entity.yaw,
      'name': ?name,
    }..removeWhere((String key, Object? value) => key == 'yaw' && value == 0.0),
  );
}

/// [level] with every prefab instance replaced by the entities it stands
/// for, all the way down, and no prefabs left to expand.
///
/// **What everything that uses a level reads**, as [expandRecipes] is — and
/// [expandRecipes] calls this first, so the loader, the validator, the
/// collision world and the bakes all see the expanded entities without
/// asking. The document keeps its instances: an editor that opens and saves
/// it writes instances back, and a change to a template reaches every one of
/// them the next time the level is expanded.
///
/// The very [level] when it has no instance, so a level without prefabs is
/// the same object and the same document it always was.
Level expandPrefabs(Level level) {
  if (!level.entities.any((EntityDef e) => e.type == EntityTypes.prefab)) {
    return level;
  }
  final cycle = prefabCycle(level.prefabs);
  if (cycle != null) {
    throw LevelFormatException(
      'prefabs contain themselves: ${cycle.join(' → ')}',
    );
  }
  final entities = <EntityDef>[
    for (final entity in level.entities)
      if (PrefabInstance.of(entity) case final PrefabInstance instance)
        ...expandPrefabInstance(instance, level.prefabs)
      else
        entity,
  ];
  return Level(
    name: level.name,
    brushes: level.brushes,
    entities: entities,
    lights: level.lights,
    materials: level.materials,
    heightfield: level.heightfield,
    fogColor: level.fogColor,
    fogDensity: level.fogDensity,
    world: level.world,
    music: level.music,
    next: level.next,
    recipes: level.recipes,
    behaviors: level.behaviors,
    renderSettings: level.renderSettings,
    source: <String, Object?>{...level.toJson()}..remove('prefabs'),
  );
}

/// What is worth saying about [level]'s prefabs that does not stop it
/// loading: overrides addressed to nothing, and prefabs nothing places.
///
/// An override outlives the entity it was written for when the template
/// loses or renames that entity; it then changes nothing, silently, and this
/// is where it is said. A cycle or a missing prefab is an error that
/// [expandPrefabs] throws, and is not repeated here.
List<LevelIssue> prefabIssues(Level level) {
  final issues = <LevelIssue>[];
  final used = <String>{};
  void look(
    String id,
    PrefabOverrides overrides,
    String where,
    List<String> stack,
  ) {
    final prefab = level.prefabs[id];
    if (prefab == null || stack.contains(id)) return;
    used.add(id);
    final segments = <String>{
      for (final entity in prefab.entities) prefabSegment(entity),
    };
    for (final path in overrides.keys) {
      if (!segments.contains(path.split('/').first)) {
        issues.add(
          LevelIssue(
            LevelIssueSeverity.warning,
            'the override of "$path" names nothing in prefab "$id", so it '
            'changes nothing',
            where: where,
          ),
        );
      }
    }
    for (final entity in prefab.entities) {
      final nested = _instanceOrNull(entity);
      if (nested == null) continue;
      final segment = prefabSegment(entity);
      look(
        nested.prefab,
        mergePrefabOverrides(nested.overrides, _through(overrides, segment)),
        '$where › ${entity.name ?? segment}',
        <String>[...stack, id],
      );
    }
  }

  for (final (index, entity) in level.entities.indexed) {
    final instance = _instanceOrNull(entity);
    if (instance == null) continue;
    look(
      instance.prefab,
      instance.overrides,
      'entities[$index] prefab "${instance.prefab}"',
      const <String>[],
    );
  }
  for (final id in level.prefabs.keys) {
    if (!used.contains(id)) {
      issues.add(
        LevelIssue(
          LevelIssueSeverity.warning,
          'prefab "$id" is placed nowhere in the level',
        ),
      );
    }
  }
  return issues;
}

PrefabInstance? _instanceOrNull(EntityDef entity) {
  try {
    return PrefabInstance.of(entity);
  } on LevelFormatException {
    return null;
  }
}
