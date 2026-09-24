import 'dart:math' as math;

import '../save/game_random.dart';
import 'json_reader.dart';
import 'level.dart';

/// A piece of a level written down as the instruction that builds it.
///
/// `{"kind": "room", "seed": 7, "params": {...}}` in a document's `recipes`
/// list. **A recipe is not expanded when the document is read**: [Level]
/// keeps it as it was written, so an editor that opens and saves the level
/// writes the recipe back rather than the forty brushes it stands for. The
/// brushes appear where a level is *used* — the loader, the validator, the
/// collision world and the visibility bake all call [expandRecipes] — and they
/// are the same brushes every time, because everything a kit decides by chance
/// it decides with [GameRandom] seeded from [seed].
final class LevelRecipe {
  const LevelRecipe({
    required this.kind,
    this.seed = 0,
    this.params = const <String, Object?>{},
  });

  factory LevelRecipe.fromJson(Map<String, Object?> json) {
    final kind = json.textOrNull('kind');
    if (kind == null) {
      throw const LevelFormatException('a recipe has no "kind"');
    }
    final params = json['params'];
    return LevelRecipe(
      kind: kind,
      seed: json.integerOrNull('seed') ?? 0,
      params: switch (params) {
        null => const <String, Object?>{},
        final Map<String, Object?> map => map,
        _ => throw LevelFormatException(
          'recipe "$kind" has params that are not an object',
        ),
      },
    );
  }

  /// Which kit builds it: one of [levelKits]' keys.
  final String kind;

  /// What the kit's chances are drawn from. Same seed, same brushes.
  final int seed;

  /// The kit's own settings. See each kit for what it reads.
  final Map<String, Object?> params;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'seed': seed,
    if (params.isNotEmpty) 'params': params,
  };
}

/// A kit: reads a recipe's params and draws into a sketch.
typedef LevelKit = void Function(LevelSketch sketch, LevelRecipe recipe);

/// The kits a document's `recipes` may name.
///
/// Three, all of which take a seed, and none of which knows a genre:
///
///  * `room` — floor, ceiling and four walls with doors cut in them, and
///    [RoomKit]'s optional `clutter` placed by the seed;
///  * `corridor` — a straight passage, with the same `clutter`;
///  * `scatter` — `count` copies of an entity or a brush, placed by the seed
///    on the floor of a box, no two closer than `spacing`.
const Map<String, LevelKit> levelKits = <String, LevelKit>{
  'room': RoomKit.build,
  'corridor': CorridorKit.build,
  'scatter': ScatterKit.build,
};

/// [level] with every recipe turned into the rows it stands for.
///
/// The brushes, entities and lights a recipe draws are appended after the
/// document's own, recipe by recipe in the order they are listed, and the
/// returned level has no recipes left — expanding it again changes nothing.
/// A level with no recipes comes back as itself.
///
/// Throws [LevelFormatException] naming the recipe for a kind nobody knows or
/// params a kit cannot read. The validator turns that into an error; the
/// loader lets it through, for the same reason it refuses any broken level.
Level expandRecipes(Level level) {
  if (level.recipes.isEmpty) return level;
  final sketch = LevelSketch();
  for (final (index, recipe) in level.recipes.indexed) {
    final kit =
        levelKits[recipe.kind] ??
        (throw LevelFormatException(
          'recipe ${index + 1} is a "${recipe.kind}", and the kits are '
          '${levelKits.keys.join(', ')}',
        ));
    try {
      kit(sketch, recipe);
    } on LevelFormatException catch (e) {
      throw LevelFormatException(
        'recipe ${index + 1} (${recipe.kind}): ${e.message}',
      );
    } on TypeError catch (e) {
      // A param of the wrong JSON type reaches a cast inside a kit. Named
      // like every other refusal of a document, rather than a stack trace.
      throw LevelFormatException(
        'recipe ${index + 1} (${recipe.kind}): a param has the wrong type: $e',
      );
    }
  }
  return Level(
    name: level.name,
    brushes: <Brush>[...level.brushes, ...sketch.brushes.map(Brush.fromJson)],
    entities: <EntityDef>[
      ...level.entities,
      ...sketch.entities.map(EntityDef.fromJson),
    ],
    lights: <LevelLight>[
      ...level.lights,
      ...sketch.lights.map(LevelLight.fromJson),
    ],
    materials: level.materials,
    heightfield: level.heightfield,
    fogColor: level.fogColor,
    fogDensity: level.fogDensity,
    music: level.music,
    next: level.next,
    source: <String, Object?>{...level.toJson()}..remove('recipes'),
  );
}

// MARK: - The kits

/// A room, as a recipe.
///
/// Params, all optional but `size`:
///
///  * `at` — the middle of the floor, `[x, y, z]`; y is the floor's height.
///  * `size` — the inside, `[width, height, depth]`.
///  * `doors` — `[{side, offset, width, height, sill}]`, side one of `north`
///    (−Z), `south`, `east`, `west`; offset along the wall from its middle.
///  * `materials` — `{floor, wall, ceiling}`, the names the brushes use.
///  * `roofed` — false leaves the ceiling off. `probes` — false places none.
///  * `clutter` — `{count, size, material, margin}`: boxes the seed places on
///    the floor, clear of the walls by `margin` and of every doorway's
///    approach, and not on top of each other.
abstract final class RoomKit {
  static void build(LevelSketch sketch, LevelRecipe recipe) {
    final p = recipe.params;
    final at = _vector(p, 'at', const <double>[0.0, 0.0, 0.0]);
    final size = _vector(p, 'size', null);
    final materials = _materials(p);
    final doors = _doors(p);
    sketch.room(
      at,
      size,
      height: size[1],
      base: at[1],
      floor: materials.floor,
      wall: materials.wall,
      ceiling: materials.ceiling,
      doors: doors,
      ceilinged: _flag(p, 'roofed', fallback: true),
      probe: _flag(p, 'probes', fallback: true),
    );
    _clutter(
      sketch,
      recipe,
      floor: at[1],
      x: (at[0] - size[0] / 2.0, at[0] + size[0] / 2.0),
      z: (at[2] - size[2] / 2.0, at[2] + size[2] / 2.0),
      lanes: <_Rect>[
        for (final door in doors) _lane(door, at[0], at[2], size[0], size[2]),
      ],
    );
  }
}

/// A corridor, as a recipe.
///
/// Params: `from` and `to` (`[x, y, z]`, along one axis; the lower y is the
/// floor), `width` (3), `height` (3), `doors`, `materials` and `clutter` as
/// [RoomKit] reads them. Clutter keeps to the walls and leaves the middle
/// third of the width open, since a corridor blocked across is a wall.
abstract final class CorridorKit {
  static void build(LevelSketch sketch, LevelRecipe recipe) {
    final p = recipe.params;
    final from = _vector(p, 'from', null);
    final to = _vector(p, 'to', null);
    final width = _number(p, 'width', 3.0);
    final materials = _materials(p);
    final base = math.min(from[1], to[1]);
    sketch.corridor(
      from,
      to,
      width: width,
      height: _number(p, 'height', 3.0),
      base: base,
      floor: materials.floor,
      wall: materials.wall,
      ceiling: materials.ceiling,
      doors: _doors(p),
    );
    final alongX = (from[0] - to[0]).abs() > 1e-6;
    final (lo, hi) = alongX
        ? (math.min(from[0], to[0]), math.max(from[0], to[0]))
        : (math.min(from[2], to[2]), math.max(from[2], to[2]));
    final across = alongX ? from[2] : from[0];
    final open = (across - width / 6.0, across + width / 6.0);
    _clutter(
      sketch,
      recipe,
      floor: base,
      x: alongX ? (lo, hi) : (across - width / 2.0, across + width / 2.0),
      z: alongX ? (across - width / 2.0, across + width / 2.0) : (lo, hi),
      lanes: <_Rect>[
        alongX
            ? (x0: lo, x1: hi, z0: open.$1, z1: open.$2)
            : (x0: open.$1, x1: open.$2, z0: lo, z1: hi),
      ],
    );
  }
}

/// Copies of one thing, spread by the seed.
///
/// Params:
///
///  * `at`, `size` — the box to fill, centre and extent; things stand on its
///    floor, `at.y - size.y / 2`.
///  * `count` — how many. Fewer come out when the box cannot hold that many at
///    `spacing` (default 1) apart; the seed decides which fit, every time.
///  * `entity` — a row to copy, `type` and all; `at` is filled in, a `name`
///    gets ` 1`, ` 2`… appended so every copy has its own, and `turn: true`
///    gives each a yaw of its own.
///  * or `brush` — `{size, material, …}`, placed with its base on the floor.
abstract final class ScatterKit {
  static void build(LevelSketch sketch, LevelRecipe recipe) {
    final p = recipe.params;
    final at = _vector(p, 'at', null);
    final size = _vector(p, 'size', null);
    final count = (p['count'] as num? ?? 1).toInt();
    final spacing = _number(p, 'spacing', 1.0);
    final entity = p['entity'] as Map<String, Object?>?;
    final brush = p['brush'] as Map<String, Object?>?;
    if ((entity == null) == (brush == null)) {
      throw const LevelFormatException(
        'a scatter copies exactly one of "entity" or "brush"',
      );
    }
    final random = GameRandom(recipe.seed);
    final floor = at[1] - size[1] / 2.0;
    final footprint = brush == null
        ? const <double>[0.0, 0.0, 0.0]
        : _vector(brush, 'size', null);
    final points = _spread(
      random,
      count: count,
      spacing: spacing,
      x: (
        at[0] - size[0] / 2.0 + footprint[0] / 2.0,
        at[0] + size[0] / 2.0 - footprint[0] / 2.0,
      ),
      z: (
        at[2] - size[2] / 2.0 + footprint[2] / 2.0,
        at[2] + size[2] / 2.0 - footprint[2] / 2.0,
      ),
      footprint: (footprint[0], footprint[2]),
    );
    for (final (index, (x, z)) in points.indexed) {
      if (entity != null) {
        final name = entity['name'];
        final turn = entity['turn'] == true;
        sketch.entities.add(<String, Object?>{
          for (final entry in entity.entries)
            if (entry.key != 'turn') entry.key: entry.value,
          'at': roundedVector(<num>[x, floor, z]),
          if (name is String) 'name': '$name ${index + 1}',
          if (turn) 'yaw': roundDecimal(random.nextDouble() * 2.0 * math.pi, 4),
        });
      } else {
        sketch.brushes.add(<String, Object?>{
          for (final entry in brush!.entries) entry.key: entry.value,
          'at': roundedVector(<num>[x, floor + footprint[1] / 2.0, z]),
          'size': roundedVector(footprint),
          'material': brush['material'] as String? ?? 'stone',
        });
      }
    }
  }
}

// MARK: - What the kits share

typedef _Rect = ({double x0, double x1, double z0, double z1});

bool _overlaps(_Rect a, _Rect b) =>
    a.x0 < b.x1 && a.x1 > b.x0 && a.z0 < b.z1 && a.z1 > b.z0;

/// Where a doorway's approach runs: the opening, carried two metres into the
/// room so nothing the seed places stands in front of it.
_Rect _lane(RoomDoor door, double cx, double cz, double w, double d) {
  const reach = 2.0;
  final half = door.width / 2.0;
  return switch (door.side) {
    'north' => (
      x0: cx + door.offset - half,
      x1: cx + door.offset + half,
      z0: cz - d / 2.0,
      z1: cz - d / 2.0 + reach,
    ),
    'south' => (
      x0: cx + door.offset - half,
      x1: cx + door.offset + half,
      z0: cz + d / 2.0 - reach,
      z1: cz + d / 2.0,
    ),
    'east' => (
      x0: cx + w / 2.0 - reach,
      x1: cx + w / 2.0,
      z0: cz + door.offset - half,
      z1: cz + door.offset + half,
    ),
    _ => (
      x0: cx - w / 2.0,
      x1: cx - w / 2.0 + reach,
      z0: cz + door.offset - half,
      z1: cz + door.offset + half,
    ),
  };
}

/// Boxes the seed places on a floor between [x] and [z], clear of [lanes].
void _clutter(
  LevelSketch sketch,
  LevelRecipe recipe, {
  required double floor,
  required (double, double) x,
  required (double, double) z,
  required List<_Rect> lanes,
}) {
  final clutter = recipe.params['clutter'];
  if (clutter == null) return;
  final spec = clutter as Map<String, Object?>;
  final size = _vector(spec, 'size', const <double>[1.0, 1.0, 1.0]);
  final margin = _number(spec, 'margin', 1.0);
  final points = _spread(
    GameRandom(recipe.seed),
    count: (spec['count'] as num? ?? 1).toInt(),
    spacing: math.max(size[0], size[2]) * 1.5,
    x: (x.$1 + margin + size[0] / 2.0, x.$2 - margin - size[0] / 2.0),
    z: (z.$1 + margin + size[2] / 2.0, z.$2 - margin - size[2] / 2.0),
    footprint: (size[0], size[2]),
    avoid: lanes,
  );
  for (final (px, pz) in points) {
    sketch.box(
      <num>[px, floor + size[1] / 2.0, pz],
      size,
      spec['material'] as String? ?? 'stone',
    );
  }
}

/// Up to [count] points between [x] and [z], at least [spacing] apart, whose
/// [footprint] touches nothing in [avoid] — drawn from [random] by rejection,
/// with a bounded number of tries so a box too small for the count gives back
/// fewer rather than hanging.
List<(double, double)> _spread(
  GameRandom random, {
  required int count,
  required double spacing,
  required (double, double) x,
  required (double, double) z,
  required (double, double) footprint,
  List<_Rect> avoid = const <_Rect>[],
}) {
  final out = <(double, double)>[];
  if (count <= 0 || x.$2 < x.$1 || z.$2 < z.$1) return out;
  for (var tries = 0; tries < count * 32 && out.length < count; tries++) {
    final px = x.$1 + random.nextDouble() * (x.$2 - x.$1);
    final pz = z.$1 + random.nextDouble() * (z.$2 - z.$1);
    final box = (
      x0: px - footprint.$1 / 2.0,
      x1: px + footprint.$1 / 2.0,
      z0: pz - footprint.$2 / 2.0,
      z1: pz + footprint.$2 / 2.0,
    );
    if (avoid.any((_Rect lane) => _overlaps(box, lane))) continue;
    final crowded = out.any(
      ((double, double) q) =>
          (q.$1 - px) * (q.$1 - px) + (q.$2 - pz) * (q.$2 - pz) <
          spacing * spacing,
    );
    if (!crowded) out.add((px, pz));
  }
  return out;
}

List<double> _vector(
  Map<String, Object?> params,
  String key,
  List<double>? fallback,
) {
  final value = params[key];
  if (value == null) {
    return fallback ??
        (throw LevelFormatException('"$key" is required, as [x, y, z]'));
  }
  if (value is! List || value.length != 3 || value.any((v) => v is! num)) {
    throw LevelFormatException('"$key" is $value, not [x, y, z]');
  }
  return <double>[for (final v in value) (v as num).toDouble()];
}

double _number(Map<String, Object?> params, String key, double fallback) =>
    switch (params[key]) {
      null => fallback,
      final num value => value.toDouble(),
      final other => throw LevelFormatException(
        '"$key" is $other, not a number',
      ),
    };

bool _flag(Map<String, Object?> params, String key, {required bool fallback}) =>
    switch (params[key]) {
      null => fallback,
      final bool value => value,
      final other => throw LevelFormatException(
        '"$key" is $other, not true or false',
      ),
    };

({String floor, String wall, String ceiling}) _materials(
  Map<String, Object?> params,
) {
  final named =
      (params['materials'] as Map<String, Object?>?) ??
      const <String, Object?>{};
  return (
    floor: named['floor'] as String? ?? 'floor',
    wall: named['wall'] as String? ?? 'wall',
    ceiling: named['ceiling'] as String? ?? 'ceiling',
  );
}

List<RoomDoor> _doors(Map<String, Object?> params) => <RoomDoor>[
  for (final door in (params['doors'] as List<Object?>?) ?? const <Object?>[])
    switch (door) {
      final Map<String, Object?> d => RoomDoor(
        d['side'] as String? ??
            (throw const LevelFormatException('a door has no "side"')),
        _number(d, 'offset', 0.0),
        _number(d, 'width', 2.0),
        _number(d, 'height', 3.0),
        sill: (d['sill'] as num?)?.toDouble(),
      ),
      _ => throw LevelFormatException('a door is $door, not an object'),
    },
];
