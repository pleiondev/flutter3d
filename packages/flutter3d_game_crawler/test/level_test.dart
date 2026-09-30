/// A crawl from a level document: validated, staged, and played through.
///
///     flutter test test/level_test.dart
library;

import 'package:flutter3d_game_crawler/flutter3d_game_crawler.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

Map<String, Object?> _box(List<double> at, List<double> size) =>
    <String, Object?>{'at': at, 'size': size, 'material': 'stone'};

/// Two halls either side of a wall at x = 0, a locked door in its middle.
/// The heroes start in the west with food and the key; the east has a
/// generator, a grunt and the way out.
Map<String, Object?> _document({
  List<Map<String, Object?>> extra = const <Map<String, Object?>>[],
}) => <String, Object?>{
  'version': 1,
  'name': 'two halls',
  'next': 'three halls',
  'materials': <String, Object?>{
    'stone': <String, Object?>{
      'baseColor': <double>[0.5, 0.5, 0.5, 1.0],
    },
  },
  'brushes': <Object?>[
    _box(<double>[0.0, -0.5, 0.0], <double>[30.0, 1.0, 30.0]),
    _box(<double>[0.0, 1.5, -8.0], <double>[0.4, 3.0, 14.0]),
    _box(<double>[0.0, 1.5, 8.0], <double>[0.4, 3.0, 14.0]),
  ],
  'lights': <Object?>[
    <String, Object?>{
      'at': <double>[0.0, 6.0, 0.0],
      'intensity': 20.0,
      'range': 30.0,
    },
  ],
  'entities': <Object?>[
    <String, Object?>{
      'type': 'player_spawn',
      'at': <double>[-10.0, 0.0, 0.0],
      'slot': 0,
    },
    <String, Object?>{
      'type': 'player_spawn',
      'at': <double>[-10.0, 0.0, 3.0],
      'slot': 1,
    },
    <String, Object?>{
      'type': 'key',
      'at': <double>[-6.0, 0.3, 0.0],
      'color': 'gold',
    },
    <String, Object?>{
      'type': 'food',
      'at': <double>[-10.0, 0.3, -4.0],
      'amount': 50,
    },
    <String, Object?>{
      'type': 'door',
      'name': 'the door',
      'at': <double>[0.0, 1.5, 0.0],
      'size': <double>[0.4, 3.0, 2.0],
      'travel': <double>[0.0, 3.2, 0.0],
      'wait': 0,
      'key': 'gold',
    },
    <String, Object?>{
      'type': 'generator',
      'at': <double>[12.0, 0.0, 10.0],
      'kind': 'grunt',
      'cap': 2,
    },
    <String, Object?>{
      'type': 'monster',
      'at': <double>[10.0, 0.0, -10.0],
      'kind': 'grunt',
    },
    <String, Object?>{
      'type': 'exit',
      'at': <double>[8.0, 1.0, 0.0],
      'size': <double>[1.0, 2.0, 1.0],
    },
    ...extra,
  ],
};

Level _level({List<Map<String, Object?>> extra = const []}) =>
    Level.fromJson(_document(extra: extra));

List<LevelIssue> _issues(Level level) => LevelValidator(
  registry: crawlerRegistry(),
  rules: crawlerRules(),
).validate(level);

StagedCrawl _stage(Level level, List<HeroClass> party) {
  final world = CollisionWorld();
  level.addTo(world);
  world.update();
  return stageCrawl(level, world, party: party, random: GameRandom(4));
}

/// Walks [hero] at [to] on the ground, for [seconds] or until within a third
/// of a metre.
void _walk(CrawlerSimulation sim, Hero hero, Vector3 to, double seconds) {
  for (var i = 0; i < (seconds / _dt).round(); i++) {
    final gap = to - hero.position
      ..y = 0.0;
    if (gap.length < 0.3) {
      hero.wish.setZero();
      return;
    }
    hero.wish.setFrom(gap..normalize());
    sim.step(_dt);
  }
  hero.wish.setZero();
}

void main() {
  group('the document', () {
    test('as written has nothing wrong with it', () {
      final errors = _issues(_level())
          .where((LevelIssue i) => i.severity == LevelIssueSeverity.error)
          .toList();

      expect(errors, isEmpty);
    });

    test('a monster of a kind nobody knows is an error that names them', () {
      final issues = _issues(
        _level(
          extra: <Map<String, Object?>>[
            <String, Object?>{
              'type': 'generator',
              'at': <double>[5.0, 0.0, 5.0],
              'kind': 'dragon',
            },
          ],
        ),
      );

      final error = issues.singleWhere(
        (LevelIssue i) => i.severity == LevelIssueSeverity.error,
      );
      expect(error.message, contains('"dragon"'));
      expect(error.message, contains('"grunt"'));
    });
  });

  group('staged', () {
    test(
      'seats each hero on their own spawn, and a fifth beside the first',
      () {
        final crawl = _stage(_level(), <HeroClass>[
          HeroClass.warrior,
          HeroClass.elf,
          HeroClass.wizard,
        ]);
        final at = crawl.sim.heroes
            .map((Hero h) => h.position.clone())
            .toList();

        expect(at[0].x, -10.0);
        expect(at[1].z, 3.0);
        expect(at[2].x, closeTo(-7.0, 1e-9), reason: 'no slot 2 spawn');
        expect(crawl.horde.count, 1, reason: 'the placed grunt');
        expect(crawl.sim.levelNext, 'three halls');
      },
    );

    test('is played through: the key, the door, the way out', () {
      final crawl = _stage(_level(), <HeroClass>[HeroClass.elf]);
      final elf = crawl.sim.heroes.single;

      _walk(crawl.sim, elf, Vector3(-6.0, 0.0, 0.0), 3.0);
      expect(elf.keys, 1);
      _walk(crawl.sim, elf, Vector3(1.0, 0.0, 0.0), 4.0);
      final door = crawl.mechanisms['the door']! as Door;
      expect(elf.keys, 0, reason: 'spent on the door');
      expect(door.goal, 1.0);
      // Through, once it has risen.
      for (var i = 0; i < 90; i++) {
        crawl.sim.step(_dt);
      }
      _walk(crawl.sim, elf, Vector3(8.0, 0.0, 0.0), 4.0);

      expect(crawl.sim.outcome, RunOutcome.won);
      expect(crawl.sim.nextLevel, 'three halls');
    });

    test('unnamed food, once eaten, stays eaten after a load', () {
      final first = _stage(_level(), <HeroClass>[HeroClass.valkyrie]);
      _walk(first.sim, first.sim.heroes.single, Vector3(-10.0, 0.0, -4.0), 3.0);
      final ate = first.sim.heroes.single.health.current;
      final saved = first.sim.save();

      final second = _stage(_level(), <HeroClass>[HeroClass.valkyrie])
        ..sim.restore(saved);
      final food = second.mechanisms.all.whereType<Food>().single;

      expect(food.isTaken, isTrue);
      expect(second.sim.heroes.single.health.current, ate);
    });
  });
}
