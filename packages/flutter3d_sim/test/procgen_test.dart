/// N11: levels made from a seed and some rules — wave function collapse
/// over rooms, joined by corridors, held to an exit a body can walk to.
///
///     dart test test/procgen_test.dart
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const List<WfcTile> _pipes = <WfcTile>[
  WfcTile('cross', sockets: <String>['pipe', 'pipe', 'pipe', 'pipe']),
  WfcTile('across', sockets: <String>['none', 'pipe', 'none', 'pipe']),
  WfcTile('down', sockets: <String>['pipe', 'none', 'pipe', 'none']),
  WfcTile(
    'blank',
    sockets: <String>['none', 'none', 'none', 'none'],
    weight: 2,
  ),
];

List<String> _errors(Level level) =>
    LevelValidator(
          registry: EntityRegistry(<EntityKind>[
            const PlayerSpawnKind(),
            const ExitKind(),
            // A room kit puts a probe in every room it builds.
            const ReflectionProbeKind(),
          ]),
          rules: const <LevelRule>[
            ExactlyOne(EntityTypes.playerSpawn),
            AtLeastOne(EntityTypes.exit),
            ExitReachable(),
          ],
        )
        .validate(level)
        .where((LevelIssue issue) => issue.isError)
        .map((LevelIssue issue) => issue.message)
        .toList();

void main() {
  group('collapse', () {
    test('every neighbour agrees, and the outside is what was asked', () {
      final grid = collapse(
        width: 9,
        height: 7,
        tiles: _pipes,
        random: GameRandom(4),
        edge: 'none',
      )!;
      for (var cell = 0; cell < grid.length; cell++) {
        final x = cell % 9;
        final z = cell ~/ 9;
        final here = _pipes[grid[cell]].sockets;
        // Mutation: propagating one step and no further leaves a pipe
        // facing a blank two cells away.
        if (x < 8) expect(here[1], _pipes[grid[cell + 1]].sockets[3]);
        if (z < 6) expect(here[2], _pipes[grid[cell + 9]].sockets[0]);
        if (x == 0) expect(here[3], 'none');
        if (z == 0) expect(here[0], 'none');
      }
    });

    test('the same seed is the same grid, and another seed another', () {
      List<int>? of(int seed) => collapse(
        width: 9,
        height: 7,
        tiles: _pipes,
        random: GameRandom(seed),
      );
      expect(of(11), of(11));
      expect(of(11), isNot(of(12)));
    });

    test('a cell can be decided first, and a grid nothing fits is null', () {
      final grid = collapse(
        width: 3,
        height: 3,
        tiles: _pipes,
        random: GameRandom(1),
        fixed: const <int, int>{4: 0},
      )!;
      expect(grid[4], 0);
      // These pipes have no ends, so with the outside closed a cross
      // anywhere must run out of the grid, and nothing is allowed to.
      // Mutation: the edge applied after the fixed cells are settled.
      expect(
        collapse(
          width: 3,
          height: 3,
          tiles: _pipes,
          random: GameRandom(1),
          edge: 'none',
          fixed: const <int, int>{4: 0},
        ),
        isNull,
      );
    });
  });

  group('generateLevel', () {
    test('a level that validates, its exit a walk from its start', () {
      final made = generateLevel(const LevelRules(), seed: 7);
      expect(made.level, isNotNull, reason: made.says);
      expect(_errors(made.level!), isEmpty);
      // Rooms and corridors as recipes, which build their brushes from
      // seeds of their own.
      expect(
        made.level!.recipes.map((LevelRecipe r) => r.kind).toSet(),
        containsAll(<String>['room', 'corridor']),
      );
    });

    test('the same seed is the same level, and the seed it says makes it', () {
      final a = generateLevel(const LevelRules(), seed: 21);
      final b = generateLevel(const LevelRules(), seed: 21);
      expect(a.level!.digestHex, b.level!.digestHex);
      final again = generateLevel(const LevelRules(), seed: a.seed);
      expect(again.level!.digestHex, a.level!.digestHex);
      expect(again.seed, a.seed);
      expect(
        generateLevel(const LevelRules(), seed: 22).level!.digestHex,
        isNot(a.level!.digestHex),
      );
    });

    test('what stands in a room stands in every room but the first', () {
      final made = generateLevel(
        const LevelRules(
          perRoom: <({Map<String, Object?> entity, int count})>[
            (entity: <String, Object?>{'type': 'crate'}, count: 2),
          ],
        ),
        seed: 3,
      );
      final level = expandRecipes(made.level!);
      final rooms = made.level!.recipes
          .where((LevelRecipe r) => r.kind == 'room')
          .length;
      expect(level.ofType('crate').length, 2 * (rooms - 1));
    });

    test('off the thread, the same level as on it', () async {
      // The isolate's copy comes back as a document; read again, it is the
      // level the same seed makes here.
      final there = await generateLevelOffThread(const LevelRules(), seed: 9);
      final here = generateLevel(const LevelRules(), seed: 9);
      expect(there.level!.digestHex, here.level!.digestHex);
      expect(there.seed, here.seed);
    });

    test('rules too small for a level say so rather than loop', () {
      final made = generateLevel(
        const LevelRules(columns: 1, rows: 1),
        seed: 1,
        attempts: 4,
      );
      expect(made.level, isNull);
      expect(made.says, contains('seeds 1 to 4'));
    });

    test('rules cross as JSON unchanged', () {
      const rules = LevelRules(columns: 5, rows: 2, density: 0.5, clutter: 2);
      expect(LevelRules.fromJson(rules.toJson()).toJson(), rules.toJson());
    });
  });

  group('ExitReachable', () {
    Level two({required bool open}) => Level(
      name: 'two rooms',
      brushes: <Brush>[
        Brush(center: Vector3(0.0, -0.5, 0.0), size: Vector3(20.0, 1.0, 6.0)),
        Brush(
          center: Vector3(0.0, 1.5, open ? -2.5 : 0.0),
          size: Vector3(0.5, 3.0, open ? 1.0 : 6.0),
        ),
      ],
      entities: <EntityDef>[
        EntityDef(
          type: EntityTypes.playerSpawn,
          position: Vector3(-6.0, 0.0, 0.0),
        ),
        EntityDef(type: EntityTypes.exit, position: Vector3(6.0, 0.0, 0.0)),
      ],
    );

    test('a wall right across is refused, a gap in it is not', () {
      // Mutation: asking the mesh for a route and not whether it arrived.
      final closed = <LevelIssue>[];
      const ExitReachable().check(two(open: false), closed);
      expect(closed.single.message, contains('cannot be finished'));
      final open = <LevelIssue>[];
      const ExitReachable().check(two(open: true), open);
      expect(open, isEmpty);
    });
  });

  group('erosion', () {
    /// A cone: one steep peak in the middle of a flat field.
    Heightfield cone() {
      const n = 33;
      final heights = Float32List(n * n);
      for (var z = 0; z < n; z++) {
        for (var x = 0; x < n; x++) {
          final r = math.sqrt(math.pow(x - 16, 2) + math.pow(z - 16, 2));
          heights[z * n + x] = math.max(0.0, 12.0 - r * 1.5);
        }
      }
      return Heightfield(columns: n, rows: n, cellSize: 1.0, heights: heights);
    }

    double total(Heightfield f) => f.copyOfSamples().fold(0.0, (a, b) => a + b);
    double steepest(Heightfield f) {
      var most = 0.0;
      for (var z = 0; z < f.rows; z++) {
        for (var x = 0; x + 1 < f.columns; x++) {
          most = math.max(most, (f.sample(x, z) - f.sample(x + 1, z)).abs());
        }
      }
      return most;
    }

    test('scree slides until no step is steeper than the talus, and none of '
        'the hill is lost', () {
      final before = cone();
      final after = erodeThermally(before, talus: 0.8, passes: 200);
      // Mutation: moving the excess away and giving it to nobody.
      expect(total(after), closeTo(total(before), 1e-2));
      expect(steepest(before), greaterThan(1.4));
      expect(steepest(after), lessThan(0.95));
    });

    test(
      'rain cuts the slopes and sets the silt down, the same every time',
      () {
        final before = cone();
        final once = erodeHydraulically(before, seed: 5, droplets: 2000);
        final again = erodeHydraulically(before, seed: 5, droplets: 2000);
        expect(once.copyOfSamples(), again.copyOfSamples());
        expect(
          erodeHydraulically(before, seed: 6, droplets: 2000).copyOfSamples(),
          isNot(once.copyOfSamples()),
        );
        // The ground moved, and is all still there. Mutation: a drop that
        // runs off the field taking its load with it.
        expect(total(once), closeTo(total(before), total(before) * 1e-4));
        expect(once.sample(16, 16), lessThan(before.sample(16, 16)));
        expect(once.copyOfSamples(), isNot(before.copyOfSamples()));
      },
    );
  });
}
