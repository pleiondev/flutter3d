/// Generators, the horde they pour out, and the ways heroes answer it.
///
///     flutter test test/combat_test.dart
library;

import 'package:flutter3d_game_crawler/flutter3d_game_crawler.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// Something that stands still and takes a while to die: a target.
const MonsterKind _post = MonsterKind(
  name: 'post',
  health: 1000.0,
  speed: 0.0,
  bite: 0.001,
);

/// Stands still and dies to anything.
const MonsterKind _straw = MonsterKind(
  name: 'straw',
  health: 5.0,
  speed: 0.0,
  bite: 0.001,
);

const List<MonsterKind> _kinds = <MonsterKind>[
  MonsterKind.grunt,
  MonsterKind.ghost,
  _post,
  _straw,
];

/// A crawl on eighty metres of floor, with whatever the test adds to it.
final class _Crawl {
  _Crawl({int seed = 3}) : world = CollisionWorld() {
    world
      ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(80.0, 1.0, 80.0))
      ..update();
    mechanisms = MechanismWorld(world);
    horde = Horde(
      ActorSystem(world: world, random: GameRandom(seed)),
      kinds: _kinds,
    );
  }

  final CollisionWorld world;
  late final MechanismWorld mechanisms;
  late final Horde horde;
  final List<Hero> heroes = <Hero>[];
  late final CrawlerSimulation sim = CrawlerSimulation(
    heroes: heroes,
    collision: world,
    random: horde.actors.random,
    mechanisms: mechanisms,
    horde: horde,
  );

  final List<GameEvent> heard = <GameEvent>[];

  Hero hero(HeroClass kind, double x, {double z = 0.0}) {
    final made = Hero(
      world: world,
      kind: kind,
      slot: heroes.length,
      at: Vector3(x, 0.9, z),
    );
    heroes.add(made);
    return made;
  }

  Generator generator(
    double x,
    double z, {
    MonsterKind kind = MonsterKind.grunt,
    int cap = 4,
    double period = 0.5,
    String name = 'generator',
  }) => mechanisms.add(
    Generator(
      name: name,
      collider: world.add(
        Collider(
          shape: CollisionBox(Vector3(0.5, 0.5, 0.5)),
          position: Vector3(x, 0.5, z),
        ),
      ),
      kind: kind,
      horde: horde,
      cap: cap,
      period: period,
    ),
  );

  void run(double seconds) {
    for (var i = 0; i < (seconds / _dt).round(); i++) {
      sim.step(_dt);
      heard.addAll(sim.events.drain());
    }
  }
}

void main() {
  group('a generator', () {
    test('pours until its cap is alive, then waits', () {
      final crawl = _Crawl();
      crawl.hero(HeroClass.warrior, -30.0);
      final generator = crawl.generator(20.0, 20.0, cap: 4);

      crawl.run(10.0);

      expect(crawl.horde.countFrom(generator), 4);
    });

    test('makes another as soon as one of its own dies', () {
      final crawl = _Crawl();
      crawl.hero(HeroClass.warrior, -30.0);
      final generator = crawl.generator(20.0, 20.0, cap: 3);
      crawl.run(5.0);
      final victim = crawl.horde.monsters.first;
      crawl.horde.actors.hurt(victim, double.infinity);

      crawl.run(_dt);
      expect(
        crawl.horde.countFrom(generator),
        2,
        reason: 'the dead are buried',
      );
      crawl.run(_dt);
      expect(crawl.horde.countFrom(generator), 3, reason: 'and replaced');
    });

    test('is broken by shots, scores, and makes nothing more', () {
      final crawl = _Crawl();
      final elf = crawl.hero(HeroClass.elf, 12.0)
        ..facing.setValues(1.0, 0.0, 0.0)
        ..fire = true;
      final generator = crawl.generator(20.0, 0.0, kind: _post, cap: 0);

      crawl.run(4.0);

      expect(generator.isDestroyed, isTrue);
      expect(crawl.heard.whereType<GeneratorDestroyed>(), hasLength(1));
      expect(elf.score, generator.score);
      crawl.run(3.0);
      expect(crawl.horde.count, 0);
    });
  });

  group('shots', () {
    test('leave on the class\'s beat, in the way the hero last walked', () {
      final crawl = _Crawl();
      final elf = crawl.hero(HeroClass.elf, 0.0)..fire = true;
      elf.wish.setValues(0.0, 0.0, 1.0);

      crawl.run(_dt);
      elf.wish.setZero();
      crawl.run(1.0 - _dt);

      final fired = crawl.sim.volley.bolts;
      expect(fired, hasLength((1.0 / HeroClass.elf.shotInterval).ceil()));
      expect(fired.every((Bolt b) => b.direction.z > 0.99), isTrue);
    });

    test('kill what they reach and credit whoever fired', () {
      final crawl = _Crawl();
      final valkyrie = crawl.hero(HeroClass.valkyrie, 0.0)
        ..facing.setValues(1.0, 0.0, 0.0)
        ..fire = true;
      crawl.horde.spawn(_straw, Vector3(6.0, 0.8, 0.0));

      crawl.run(1.0);

      final slain = crawl.heard.whereType<MonsterSlain>().toList();
      expect(slain, hasLength(1));
      expect(identical(slain.single.hero, valkyrie), isTrue);
      expect(valkyrie.score, _straw.score);
      expect(crawl.horde.count, 0);
    });

    test('pass through another hero and stop at a wall', () {
      final crawl = _Crawl();
      crawl.world.addBox(Vector3(10.0, 1.5, 0.0), Vector3(0.4, 3.0, 4.0));
      crawl.hero(HeroClass.elf, 0.0)
        ..facing.setValues(1.0, 0.0, 0.0)
        ..fire = true;
      final friend = crawl.hero(HeroClass.warrior, 4.0);
      final beyond = crawl.horde.spawn(_post, Vector3(14.0, 0.8, 0.0));

      crawl.run(2.0);

      expect(friend.health.current, closeTo(Hero.startingHealth - 2.0, 1e-6));
      expect(beyond.health!.current, _post.health);
    });
  });

  test('hand to hand, the warrior outlasts the wizard', () {
    double dealt(HeroClass kind) {
      final crawl = _Crawl();
      crawl.hero(kind, 0.0);
      final target = crawl.horde.spawn(_post, Vector3(0.75, 0.8, 0.0));
      crawl.run(1.0);
      return _post.health - target.health!.current;
    }

    expect(dealt(HeroClass.warrior), greaterThan(dealt(HeroClass.wizard)));
    expect(
      dealt(HeroClass.warrior),
      closeTo(HeroClass.warrior.melee, HeroClass.warrior.melee * 0.1),
    );
  });

  group('a potion', () {
    test('reaches everything in view and nothing beyond it', () {
      final crawl = _Crawl();
      final wizard = crawl.hero(HeroClass.wizard, 0.0)
        ..potions = 1
        ..drink = true;
      for (var i = 0; i < 5; i++) {
        crawl.horde.spawn(_straw, Vector3(-4.0 + 2.0 * i, 0.8, 5.0));
      }
      final far = crawl.horde.spawn(_straw, Vector3(0.0, 0.8, 38.0));

      crawl.run(_dt);

      expect(crawl.horde.monsters, <Actor>[far]);
      expect(wizard.potions, 0);
      expect(wizard.drink, isFalse, reason: 'a press, not a hold');
      final drunk = crawl.heard.whereType<PotionDrunk>().single;
      expect(drunk.struck, 5);
    });

    test('does nothing for a hero who has none', () {
      final crawl = _Crawl();
      crawl.hero(HeroClass.wizard, 0.0).drink = true;
      crawl.horde.spawn(_straw, Vector3(2.0, 0.8, 0.0));

      crawl.run(_dt);

      expect(crawl.heard.whereType<PotionDrunk>(), isEmpty);
    });
  });

  test('a ghost strikes once and is gone', () {
    final crawl = _Crawl();
    final wizard = crawl.hero(HeroClass.wizard, 0.0);
    crawl.horde.spawn(MonsterKind.ghost, Vector3(4.0, 0.8, 0.0));

    crawl.run(3.0);

    expect(crawl.horde.count, 0);
    expect(
      wizard.health.current,
      closeTo(Hero.startingHealth - 3.0 - MonsterKind.ghost.touch, 0.01),
    );
    expect(wizard.score, 0, reason: 'nobody killed it');
  });

  group('a save with the horde in it', () {
    /// Two heroes fighting their way towards two generators, the elf firing.
    _Crawl staged() {
      final crawl = _Crawl(seed: 11);
      crawl.hero(HeroClass.elf, 0.0).fire = true;
      crawl.hero(HeroClass.warrior, -2.0, z: 2.0);
      crawl
        ..generator(8.0, 3.0, cap: 5, period: 0.3, name: 'north')
        ..generator(-6.0, -7.0, kind: MonsterKind.ghost, cap: 3, name: 'south');
      crawl.mechanisms.add(
        Food(
          name: 'food',
          collider: crawl.world.add(
            Collider(
              shape: CollisionBox(Vector3(0.3, 0.3, 0.3)),
              position: Vector3(3.0, 0.5, 1.0),
            ),
          ),
        ),
      );
      return crawl;
    }

    void drive(_Crawl crawl, int from, int to) {
      for (var i = from; i < to; i++) {
        crawl.heroes[0].wish.setValues(i < 100 ? 1.0 : 0.2, 0.0, 0.3);
        crawl.heroes[1].wish.setValues(0.5, 0.0, i < 80 ? -1.0 : 0.4);
        crawl.heroes[1].drink = i == 150;
        crawl.sim.step(_dt);
      }
    }

    test('loaded into a fresh world continues as the crawl did', () {
      final straight = staged()..heroes[1].potions = 1;
      drive(straight, 0, 300);

      final first = staged()..heroes[1].potions = 1;
      drive(first, 0, 120);
      expect(first.horde.count, greaterThan(3), reason: 'births to restore');
      final saved = first.sim.save();
      final second = staged();
      second.sim.restore(saved);
      drive(second, 120, 300);

      expect(second.sim.save().data, straight.sim.save().data);
    });

    test('rolled back in the same world continues as the crawl did', () {
      final straight = staged()..heroes[1].potions = 1;
      drive(straight, 0, 300);

      final crawl = staged()..heroes[1].potions = 1;
      drive(crawl, 0, 120);
      final saved = crawl.sim.save();
      // Past the save: more born, some slain, a potion drunk, food eaten.
      drive(crawl, 120, 260);
      crawl.sim.restore(saved);
      drive(crawl, 120, 300);

      expect(crawl.sim.save().data, straight.sim.save().data);
    });
  });
}
