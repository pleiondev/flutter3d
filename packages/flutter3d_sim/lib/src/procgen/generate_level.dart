import '../level/level.dart';
import '../level/level_issue.dart';
import '../save/game_random.dart';
import 'exit_reachable.dart';
import 'wfc.dart';

/// What a generated level is made of: a grid of cells, each a room or
/// nothing, joined by corridors where two rooms face each other through a
/// doorway — and what stands in the rooms.
///
/// Every number has a default that builds a playable level, so
/// `LevelRules()` alone is a level; a game or an agent names what it wants
/// different. The rules travel as JSON ([toJson], [LevelRules.fromJson]),
/// which is how they cross into an isolate and in from a tool.
final class LevelRules {
  const LevelRules({
    this.columns = 4,
    this.rows = 3,
    this.cell = 16.0,
    this.room = 10.0,
    this.height = 4.0,
    this.corridor = 3.0,
    this.density = 0.7,
    this.materials = _materials,
    this.perRoom = const <({Map<String, Object?> entity, int count})>[],
    this.clutter = 0,
    this.name,
  }) : assert(room < cell, 'a room fills less than its cell, or no corridor'),
       assert(corridor < room, 'a doorway narrower than the wall it is in');

  factory LevelRules.fromJson(Map<String, Object?> json) {
    double number(String key, double fallback) =>
        (json[key] as num?)?.toDouble() ?? fallback;
    int integer(String key, int fallback) =>
        (json[key] as num?)?.toInt() ?? fallback;
    const defaults = LevelRules();
    return LevelRules(
      columns: integer('columns', defaults.columns),
      rows: integer('rows', defaults.rows),
      cell: number('cell', defaults.cell),
      room: number('room', defaults.room),
      height: number('height', defaults.height),
      corridor: number('corridor', defaults.corridor),
      density: number('density', defaults.density),
      clutter: integer('clutter', defaults.clutter),
      name: json['name'] as String?,
      materials: switch (json['materials']) {
        final Map<String, Object?> rows => rows.map(
          (String name, Object? row) =>
              MapEntry(name, (row! as Map).cast<String, Object?>()),
        ),
        _ => defaults.materials,
      },
      perRoom: <({Map<String, Object?> entity, int count})>[
        for (final row in (json['perRoom'] as List<Object?>?) ?? const [])
          (
            entity: ((row! as Map)['entity']! as Map).cast<String, Object?>(),
            count: ((row as Map)['count'] as num?)?.toInt() ?? 1,
          ),
      ],
    );
  }

  /// Cells across (x) and down (z).
  final int columns;
  final int rows;

  /// A cell's side, and a room's floor inside it; what is left between two
  /// rooms is the corridor's length.
  final double cell;
  final double room;

  /// Floor to ceiling, rooms and corridors alike.
  final double height;

  /// A corridor's width, which is its doorways' too.
  final double corridor;

  /// How likely a cell is to be a room rather than nothing, nought to one.
  final double density;

  /// The level's materials by name; `floor`, `wall` and `ceiling` are the
  /// ones the rooms are built of.
  final Map<String, Map<String, Object?>> materials;

  /// What stands in every room but the first: an entity row and how many,
  /// scattered by the seed — a game's monsters, its pickups.
  final List<({Map<String, Object?> entity, int count})> perRoom;

  /// Boxes the seed places against each room's walls.
  final int clutter;

  /// What the level is called; the seed's name when null.
  final String? name;

  static const Map<String, Map<String, Object?>> _materials =
      <String, Map<String, Object?>>{
        'floor': <String, Object?>{
          'baseColor': <num>[0.42, 0.4, 0.37, 1.0],
          'roughness': 0.9,
        },
        'wall': <String, Object?>{
          'baseColor': <num>[0.55, 0.52, 0.48, 1.0],
          'roughness': 0.85,
        },
        'ceiling': <String, Object?>{
          'baseColor': <num>[0.3, 0.29, 0.28, 1.0],
          'roughness': 0.95,
        },
      };

  Map<String, Object?> toJson() => <String, Object?>{
    'columns': columns,
    'rows': rows,
    'cell': cell,
    'room': room,
    'height': height,
    'corridor': corridor,
    'density': density,
    'clutter': clutter,
    'name': ?name,
    'materials': materials,
    'perRoom': <Object?>[
      for (final row in perRoom)
        <String, Object?>{'entity': row.entity, 'count': row.count},
    ],
  };
}

/// Why [generateLevel] could not, or the level it made and the seed that
/// made it — which is not always the seed asked for: see [generateLevel].
typedef Generated = ({Level? level, int seed, String says});

/// The tiles: a room with a doorway on any of its four sides, sixteen of
/// them, and nothing at all. A doorway meets a doorway and a wall a wall, so
/// a solved grid is one where every doorway leads somewhere.
List<WfcTile> _tiles(double density) => <WfcTile>[
  for (var exits = 0; exits < 16; exits++)
    WfcTile(
      'room$exits',
      sockets: <String>[
        for (var side = 0; side < 4; side++)
          exits & (1 << side) != 0 ? 'door' : 'wall',
      ],
      // Rooms with more ways out a little likelier, so a level is a place
      // with choices in it rather than a string of beads.
      weight: density * (1 + (exits.bitLength)) / 16.0,
    ),
  WfcTile(
    'none',
    sockets: const <String>['wall', 'wall', 'wall', 'wall'],
    weight: 1.0 - density,
  ),
];

/// A level from [rules] and [seed]: rooms laid out by wave function
/// collapse, joined by corridors through the doorways it chose, the player
/// in one room and the exit in the room farthest from it, the rest
/// scattered with what [rules] says stands in a room — and, before it is
/// handed back, refused unless the exit can be walked to ([ExitReachable]).
///
/// **The same seed, the same level**, bit for bit: everything chance
/// decides comes from [GameRandom], and the rooms are recipes that build
/// their brushes from seeds of their own. A grid that fails — a
/// contradiction, or rooms too few to be a level — is tried again with the
/// next seed, up to [attempts], and the answer says which seed made it, so
/// that seed alone makes it again.
Generated generateLevel(
  LevelRules rules, {
  required int seed,
  int attempts = 32,
}) {
  for (var attempt = 0; attempt < attempts; attempt++) {
    final tried = seed + attempt;
    final level = _attempt(rules, tried);
    if (level == null) continue;
    final issues = <LevelIssue>[];
    const ExitReachable().check(level, issues);
    if (issues.any((LevelIssue issue) => issue.isError)) continue;
    return (
      level: level,
      seed: tried,
      says: attempt == 0
          ? 'generated from seed $tried'
          : 'generated from seed $tried; ${attempt == 1 ? 'seed $seed' : 'seeds $seed to ${tried - 1}'} made no level',
    );
  }
  return (
    level: null,
    seed: seed,
    says:
        'no level from seeds $seed to ${seed + attempts - 1}: the grid is '
        'too small or too empty to hold two joined rooms — more cells or a '
        'higher density',
  );
}

Level? _attempt(LevelRules rules, int seed) {
  final random = GameRandom(seed);
  final tiles = _tiles(rules.density.clamp(0.05, 0.95));
  final grid = collapse(
    width: rules.columns,
    height: rules.rows,
    tiles: tiles,
    random: random,
    edge: 'wall',
  );
  if (grid == null) return null;

  final count = rules.columns * rules.rows;
  int exits(int cell) => grid[cell] < 16 ? grid[cell] : -1;
  int? across(int cell, int side) {
    final x = cell % rules.columns;
    final z = cell ~/ rules.columns;
    return switch (side) {
      0 when z > 0 => cell - rules.columns,
      1 when x < rules.columns - 1 => cell + 1,
      2 when z < rules.rows - 1 => cell + rules.columns,
      3 when x > 0 => cell - 1,
      _ => null,
    };
  }

  // The rooms one can walk between, as the largest group; the first room of
  // it by index is where the player starts.
  final seen = List<int>.filled(count, -1);
  var best = <int>[];
  for (var start = 0; start < count; start++) {
    if (exits(start) < 0 || seen[start] >= 0) continue;
    final group = <int>[start];
    seen[start] = 0;
    for (var i = 0; i < group.length; i++) {
      final cell = group[i];
      for (var side = 0; side < 4; side++) {
        final next = across(cell, side);
        if (next == null || exits(cell) & (1 << side) == 0) continue;
        if (seen[next] >= 0) continue;
        seen[next] = seen[cell] + 1;
        group.add(next);
      }
    }
    if (group.length > best.length) best = group;
  }
  if (best.length < 2) return null;
  final start = best.first;
  // Breadth first from the start, so the last room reached is the farthest;
  // the depths were counted from each group's own first room, which for the
  // best group is [start].
  final exitRoom = best.reduce((int a, int b) => seen[b] > seen[a] ? b : a);

  final inLevel = best.toSet();
  List<num> centre(int cell) => <num>[
    (cell % rules.columns + 0.5) * rules.cell,
    0.0,
    (cell ~/ rules.columns + 0.5) * rules.cell,
  ];
  const sides = <String>['north', 'east', 'south', 'west'];
  final materials = <String, Object?>{
    'floor': 'floor',
    'wall': 'wall',
    'ceiling': 'ceiling',
  };

  final recipes = <Map<String, Object?>>[];
  final lights = <Map<String, Object?>>[];
  final entities = <Map<String, Object?>>[];
  for (final cell in best) {
    final at = centre(cell);
    recipes.add(<String, Object?>{
      'kind': 'room',
      'seed': seed * 1000 + cell,
      'params': <String, Object?>{
        'at': at,
        'size': <num>[rules.room, rules.height, rules.room],
        'materials': materials,
        'doors': <Object?>[
          for (var side = 0; side < 4; side++)
            if (exits(cell) & (1 << side) != 0)
              <String, Object?>{
                'side': sides[side],
                'offset': 0.0,
                'width': rules.corridor,
                'height': rules.height - 0.6,
              },
        ],
        if (rules.clutter > 0)
          'clutter': <String, Object?>{
            'count': rules.clutter,
            'size': <num>[0.8, 0.8, 0.8],
            'material': 'wall',
          },
      },
    });
    lights.add(<String, Object?>{
      'type': 'point',
      'at': <num>[at[0], rules.height - 0.6, at[2]],
      'color': <num>[1.0, 0.85, 0.65],
      'intensity': 6.0,
      'range': rules.room * 1.2,
    });
    // A corridor east and south of each room that has one, so each is
    // built once.
    for (final side in <int>[1, 2]) {
      final next = across(cell, side);
      if (next == null || !inLevel.contains(next)) continue;
      if (exits(cell) & (1 << side) == 0) continue;
      final half = rules.room / 2.0;
      final there = centre(next);
      final (from, to) = side == 1
          ? (
              <num>[at[0] + half, 0.0, at[2]],
              <num>[there[0] - half, 0.0, at[2]],
            )
          : (
              <num>[at[0], 0.0, at[2] + half],
              <num>[at[0], 0.0, there[2] - half],
            );
      recipes.add(<String, Object?>{
        'kind': 'corridor',
        'seed': seed * 1000 + count + cell * 2 + side,
        'params': <String, Object?>{
          'from': from,
          'to': to,
          'width': rules.corridor,
          'height': rules.height,
          'materials': materials,
          // Open at both ends, onto the doorways it joins.
          'doors': <Object?>[
            for (final end
                in side == 1
                    ? const <String>['west', 'east']
                    : const <String>['north', 'south'])
              <String, Object?>{
                'side': end,
                'offset': 0.0,
                'width': rules.corridor,
                'height': rules.height - 0.6,
              },
          ],
        },
      });
    }
    if (cell == start) {
      entities.add(<String, Object?>{'type': 'player_spawn', 'at': at});
    } else {
      for (final (index, row) in rules.perRoom.indexed) {
        recipes.add(<String, Object?>{
          'kind': 'scatter',
          'seed': seed * 1000 + 3 * count + cell * 16 + index,
          'params': <String, Object?>{
            'at': <num>[at[0], rules.height / 2.0, at[2]],
            'size': <num>[rules.room - 3.0, rules.height, rules.room - 3.0],
            'count': row.count,
            'spacing': 1.5,
            'entity': row.entity,
          },
        });
      }
    }
    if (cell == exitRoom) {
      entities.add(<String, Object?>{
        'type': 'exit',
        'at': <num>[at[0], 0.0, at[2] + rules.room / 4.0],
      });
    }
  }

  return Level.fromJson(<String, Object?>{
    'version': 1,
    'name': rules.name ?? 'Generated $seed',
    'generatedBy': 'generateLevel, seed $seed',
    'materials': rules.materials,
    'lights': lights,
    'entities': entities,
    'recipes': recipes,
  });
}
