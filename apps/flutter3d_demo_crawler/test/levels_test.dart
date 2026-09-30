/// The levels this game ships: valid, chained, and finishable.
///
///     flutter test test/levels_test.dart
///
/// Through the game's own `stage`, on the documents the game loads. What is
/// asserted about the first level is that it can be *played through*: a hero
/// walking the navigation field to the key, into the locked door and out, with
/// the grunts it meets on the way fought where they stand.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_demo_crawler/src/level_open.dart';
import 'package:flutter3d_demo_crawler/src/staging.dart';
import 'package:flutter3d_game_crawler/flutter3d_game_crawler.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

Level _read(String name) => Level.fromJson(
  jsonDecode(File(levelAsset(name)).readAsStringSync()) as Map<String, Object?>,
);

StagedCrawl _stage(
  Level level,
  List<HeroClass> party, {
  List<Hero> carried = const <Hero>[],
}) {
  final world = CollisionWorld();
  level.addTo(world);
  world.update();
  return stage(level, world, party: party, carried: carried);
}

/// Walks [hero] to [to] along the level's navigation, fighting as it goes,
/// for up to [seconds]. Answers whether it arrived.
bool _walk(
  StagedCrawl crawl,
  Level level,
  Hero hero,
  Vector3 to, {
  double seconds = 20.0,
}) {
  final field = Navigation.bake(level).fieldFor(radius: 0.35, height: 1.8)
    ..rebuild(to);
  final way = Vector3.zero();
  hero.fire = true;
  for (var i = 0; i < (seconds / _dt).round(); i++) {
    final gap = to - hero.position
      ..y = 0.0;
    if (gap.length < 0.6 || crawl.sim.outcome.isOver) {
      hero.wish.setZero();
      return true;
    }
    if (!field.descend(hero.position, way)) way.setFrom(gap..normalize());
    hero.wish.setFrom(way);
    crawl.sim.step(_dt);
  }
  hero.wish.setZero();
  return false;
}

Vector3 _entity(Level level, String type) =>
    level.ofType(type).single.position.clone();

void main() {
  const names = <String>['gatehouse', 'kennels', 'ossuary'];

  for (final name in names) {
    test('$name has nothing wrong with it', () {
      final issues = LevelValidator(
        registry: crawlerRegistry(),
        rules: crawlerRules(),
      ).validate(_read(name));

      expect(issues, isEmpty);
    });
  }

  test('each level leads to the next and the last to none', () {
    expect(
      <String?>[for (final n in names) _read(n).next],
      <String?>['kennels', 'ossuary', null],
    );
    expect(levelAsset(firstLevel), 'assets/levels/gatehouse.json');
  });

  test('the gatehouse is played through: key, door, way out', () {
    final level = _read('gatehouse');
    final crawl = _stage(level, <HeroClass>[HeroClass.warrior]);
    final warrior = crawl.sim.heroes.single;

    expect(
      _walk(crawl, level, warrior, _entity(level, 'key')),
      isTrue,
      reason: 'the key',
    );
    expect(warrior.keys, 1);

    final door = level.ofType('door').single.position;
    expect(
      _walk(crawl, level, warrior, Vector3(door.x - 1.2, 0.0, door.z)),
      isTrue,
      reason: 'up to the door',
    );
    // Pressed against it, then give it time to sink.
    warrior.wish.setValues(1.0, 0.0, 0.0);
    for (var i = 0; i < 90; i++) {
      crawl.sim.step(_dt);
    }
    expect(warrior.keys, 0, reason: 'spent on the door');

    expect(_walk(crawl, level, warrior, _entity(level, 'exit')), isTrue);
    expect(crawl.sim.outcome, RunOutcome.won);
    expect(crawl.sim.nextLevel, 'kennels');
    expect(warrior.isAlive, isTrue);
  });

  test('a party carries what it has into the next level', () {
    final first = _stage(_read('gatehouse'), <HeroClass>[
      HeroClass.elf,
      HeroClass.wizard,
    ]);
    final elf = first.sim.heroes[0]
      ..keys = 2
      ..potions = 1
      ..score = 340;
    elf.health.damage(100.0);
    first.sim.heroes[1].health.damage(Hero.maximumHealth);

    final next = _stage(_read('kennels'), <HeroClass>[
      HeroClass.elf,
      HeroClass.wizard,
    ], carried: first.sim.heroes);

    final carried = next.sim.heroes[0];
    expect(carried.keys, 2);
    expect(carried.potions, 1);
    expect(carried.score, 340);
    expect(carried.health.current, Hero.startingHealth - 100.0);
    expect(next.sim.heroes[1].isAlive, isFalse, reason: 'fallen stays fallen');
  });
}
