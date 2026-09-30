/// Heroes, what they carry, and the view they share.
///
///     flutter test test/crawler_test.dart
library;

import 'package:flutter3d_game_crawler/flutter3d_game_crawler.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// Eighty metres of open floor, its top at y = 0.
CollisionWorld _floor() {
  final world = CollisionWorld()
    ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(80.0, 1.0, 80.0));
  world.update();
  return world;
}

Hero _hero(CollisionWorld world, HeroClass kind, int slot, double x) =>
    Hero(world: world, kind: kind, slot: slot, at: Vector3(x, 0.9, 0.0));

CrawlerSimulation _crawl(
  CollisionWorld world,
  List<Hero> heroes, {
  MechanismWorld? mechanisms,
  Horde? horde,
}) => CrawlerSimulation(
  heroes: heroes,
  collision: world,
  random: horde?.actors.random ?? GameRandom(1),
  mechanisms: mechanisms,
  horde: horde,
);

Horde _horde(CollisionWorld world, {int seed = 5}) => Horde(
  ActorSystem(world: world, random: GameRandom(seed)),
  kinds: const <MonsterKind>[_biter],
);

void _run(CrawlerSimulation sim, double seconds) {
  for (var i = 0; i < (seconds / _dt).round(); i++) {
    sim.step(_dt);
  }
}

List<GameEvent> _drain(CrawlerSimulation sim) => sim.events.drain();

Collider _trigger(CollisionWorld world, double x, double z) => world.add(
  Collider(
    shape: CollisionBox(Vector3(0.3, 0.3, 0.3)),
    position: Vector3(x, 0.5, z),
  ),
);

/// Quick and tough enough to keep biting for the length of a test.
const MonsterKind _biter = MonsterKind(
  name: 'biter',
  health: 5000.0,
  speed: 6.0,
  bite: 60.0,
);

void main() {
  group('health', () {
    test('drains a point a second, through no armour', () {
      final world = _floor();
      final warrior = _hero(world, HeroClass.warrior, 0, 0.0);
      final sim = _crawl(world, <Hero>[warrior]);

      _run(sim, 10.0);

      expect(warrior.health.current, closeTo(Hero.startingHealth - 10.0, 1e-6));
    });

    test('says a hero needs food once as it falls low, not every step', () {
      final world = _floor();
      final elf = _hero(world, HeroClass.elf, 0, 0.0);
      elf.health.damage(Hero.startingHealth - Hero.hungryBelow - 1.0);
      final sim = _crawl(world, <Hero>[elf]);

      final hungry = <GameEvent>[];
      for (var i = 0; i < 5 * 60; i++) {
        sim.step(_dt);
        hungry.addAll(_drain(sim).whereType<HeroHungry>());
      }

      expect(hungry, hasLength(1));
    });

    test('runs out, and the last hero to die loses the run', () {
      final world = _floor();
      final wizard = _hero(world, HeroClass.wizard, 0, 0.0);
      wizard.health.damage(Hero.startingHealth - 2.0);
      final sim = _crawl(world, <Hero>[wizard]);

      _run(sim, 3.0);

      expect(wizard.isAlive, isFalse);
      expect(sim.outcome, RunOutcome.lost);
    });

    test('one hero dying is not the end while another lives', () {
      final world = _floor();
      final doomed = _hero(world, HeroClass.wizard, 0, -3.0)
        ..health.damage(Hero.startingHealth - 1.0);
      final sim = _crawl(world, <Hero>[
        doomed,
        _hero(world, HeroClass.warrior, 1, 3.0),
      ]);

      final died = <GameEvent>[];
      for (var i = 0; i < 3 * 60; i++) {
        sim.step(_dt);
        died.addAll(_drain(sim).whereType<HeroDied>());
      }

      expect(died, hasLength(1));
      expect(sim.outcome, RunOutcome.playing);
    });
  });

  group('loot', () {
    late CollisionWorld world;
    late MechanismWorld mechanisms;
    late Hero valkyrie;
    late CrawlerSimulation sim;

    setUp(() {
      world = _floor();
      mechanisms = MechanismWorld(world);
      valkyrie = _hero(world, HeroClass.valkyrie, 0, 0.0);
      sim = _crawl(world, <Hero>[valkyrie], mechanisms: mechanisms);
    });

    void walkEast(double seconds) {
      valkyrie.wish.setValues(1.0, 0.0, 0.0);
      _run(sim, seconds);
    }

    test('food, a key, a potion and treasure are each taken once', () {
      mechanisms
        ..add(Food(name: 'food', collider: _trigger(world, 1.5, 0.0)))
        ..add(DoorKey(name: 'key', collider: _trigger(world, 2.5, 0.0)))
        ..add(Potion(name: 'potion', collider: _trigger(world, 3.5, 0.0)))
        ..add(Treasure(name: 'gold', collider: _trigger(world, 4.5, 0.0)));

      final taken = <LootTaken>[];
      valkyrie.wish.setValues(1.0, 0.0, 0.0);
      for (var i = 0; i < 2 * 60; i++) {
        sim.step(_dt);
        taken.addAll(_drain(sim).whereType<LootTaken>());
      }

      expect(taken.map((LootTaken e) => e.loot.name), <String>[
        'food',
        'key',
        'potion',
        'gold',
      ]);
      expect(taken.every((LootTaken e) => identical(e.hero, valkyrie)), isTrue);
      expect(valkyrie.keys, 1);
      expect(valkyrie.potions, 1);
      expect(valkyrie.score, 100);
      expect(
        valkyrie.health.current,
        closeTo(Hero.startingHealth + 100.0 - 2.0, 0.05),
        reason: 'food carries a hero past where they began, less the drain',
      );
    });

    test('a hero who has died takes nothing', () {
      final food = mechanisms.add(
        Food(name: 'food', collider: _trigger(world, 1.5, 0.0)),
      );
      valkyrie.health.damage(Hero.maximumHealth);

      walkEast(1.0);

      expect(food.isTaken, isFalse);
    });
  });

  group('a locked door', () {
    late CollisionWorld world;
    late MechanismWorld mechanisms;
    late Door door;
    late Hero warrior;
    late CrawlerSimulation sim;

    setUp(() {
      world = _floor();
      mechanisms = MechanismWorld(world);
      final slab = world.add(
        Collider(
          shape: CollisionBox(Vector3(0.2, 1.5, 2.0)),
          position: Vector3(2.0, 1.5, 0.0),
          kind: ColliderKind.kinematic,
        ),
      );
      door = mechanisms.add(
        Door(
          name: 'door',
          collider: slab,
          travel: Vector3(0.0, 3.2, 0.0),
          wait: 0.0,
          key: 'key',
        ),
      );
      world.update();
      warrior = _hero(world, HeroClass.warrior, 0, 0.0);
      sim = _crawl(world, <Hero>[warrior], mechanisms: mechanisms);
    });

    test('stays shut for a hero with no key', () {
      warrior.wish.setValues(1.0, 0.0, 0.0);
      _run(sim, 2.0);

      expect(door.progress, 0.0);
      expect(warrior.position.x, lessThan(1.8));
    });

    test('opens for good when a hero with a key walks into it, and the key '
        'is spent', () {
      warrior.keys = 2;
      warrior.wish.setValues(1.0, 0.0, 0.0);

      final unlocked = <DoorUnlocked>[];
      for (var i = 0; i < 4 * 60; i++) {
        sim.step(_dt);
        unlocked.addAll(_drain(sim).whereType<DoorUnlocked>());
      }

      expect(unlocked, hasLength(1));
      expect(warrior.keys, 1);
      expect(door.progress, 1.0, reason: 'a door that waits for nothing');
      expect(
        warrior.position.x,
        greaterThan(4.0),
        reason: 'and is walked through',
      );
    });
  });

  group('the shared view', () {
    test('rises as the heroes spread, within its limits', () {
      final framing = CrawlFraming();

      framing.frame(<Vector3>[Vector3(0.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0)]);
      expect(framing.height, framing.tuning.minHeight);

      framing.frame(<Vector3>[
        Vector3(-12.0, 0.0, 0.0),
        Vector3(12.0, 0.0, 0.0),
      ]);
      expect(framing.height, greaterThan(framing.tuning.minHeight));
      expect(framing.height, lessThan(framing.tuning.maxHeight));

      framing.frame(<Vector3>[
        Vector3(-90.0, 0.0, 0.0),
        Vector3(90.0, 0.0, 0.0),
      ]);
      expect(framing.height, framing.tuning.maxHeight);
    });

    test('keeps both heroes in the picture it asks for', () {
      final framing = CrawlFraming();
      final a = Vector3(-10.0, 0.0, 4.0);
      final b = Vector3(9.0, 0.0, -6.0);
      framing.frame(<Vector3>[a, b]);
      final eye = Vector3.zero();
      final target = Vector3.zero();
      framing.view(eye, target);

      final forward = (target - eye)..normalize();
      final right = forward.cross(Vector3(0.0, 1.0, 0.0))..normalize();
      final up = right.cross(forward);
      final tanV = Portable.tan(framing.tuning.fieldOfView / 2.0);
      final tanH = tanV * framing.tuning.aspect;
      for (final hero in <Vector3>[a, b]) {
        final to = hero - eye;
        final depth = to.dot(forward);
        expect((to.dot(right) / depth).abs(), lessThan(tanH));
        expect((to.dot(up) / depth).abs(), lessThan(tanV));
      }
    });

    test('stops a hero walking away from the others at its edge', () {
      final world = _floor();
      final runner = _hero(world, HeroClass.elf, 0, -28.0);
      final stayer = _hero(world, HeroClass.warrior, 1, -30.0);
      final sim = _crawl(world, <Hero>[runner, stayer]);

      runner.wish.setValues(1.0, 0.0, 0.0);
      _run(sim, 12.0);

      final apart = runner.position.x - stayer.position.x;
      expect(apart, closeTo(2.0 * sim.framing.reachX, 0.2));
      expect(
        runner.position.x - sim.framing.centre.x,
        lessThan(sim.framing.reachX + 0.2),
      );
    });

    test('but lets a hero alone go anywhere', () {
      final world = _floor();
      final elf = _hero(world, HeroClass.elf, 0, -30.0);
      final sim = _crawl(world, <Hero>[elf]);

      elf.wish.setValues(1.0, 0.0, 0.0);
      _run(sim, 8.0);

      expect(elf.position.x, greaterThan(10.0));
    });

    test('the camera cuts to the framing and then eases after it', () {
      final framing = CrawlFraming()..frame(<Vector3>[Vector3.zero()]);
      final camera = CrawlCamera()..follow(framing, _dt);
      final eye = Vector3.zero();
      framing.view(eye, Vector3.zero());
      expect(camera.eye, eye);

      framing.frame(<Vector3>[Vector3(10.0, 0.0, 0.0)]);
      camera.follow(framing, _dt);
      expect(camera.eye.x, greaterThan(0.0));
      expect(camera.eye.x, lessThan(10.0));
    });
  });

  group('monsters', () {
    ({CrawlerSimulation sim, List<Hero> heroes, Actor monster}) staged(
      HeroClass near,
    ) {
      final world = _floor();
      final horde = _horde(world);
      final heroes = <Hero>[
        _hero(world, near, 0, 0.0),
        _hero(world, HeroClass.wizard, 1, 20.0),
      ];
      final monster = horde.spawn(_biter, Vector3(3.0, 0.8, 0.0));
      return (
        sim: _crawl(world, heroes, horde: horde),
        heroes: heroes,
        monster: monster,
      );
    }

    test('go for the nearer hero, and what they deal goes through armour', () {
      final warrior = staged(HeroClass.warrior);
      final wizard = staged(HeroClass.wizard);
      _run(warrior.sim, 2.0);
      _run(wizard.sim, 2.0);

      final warriorLost =
          Hero.startingHealth - 2.0 - warrior.heroes[0].health.current;
      final wizardLost =
          Hero.startingHealth - 2.0 - wizard.heroes[0].health.current;
      expect(warriorLost, greaterThan(0.0));
      expect(
        warriorLost / wizardLost,
        closeTo(HeroClass.warrior.damageTaken, 0.01),
      );
      expect(
        warrior.heroes[1].health.current,
        closeTo(Hero.startingHealth - 2.0, 1e-6),
        reason: 'the far hero was never touched',
      );
    });

    test('turn to the other hero when the near one dies', () {
      final crawl = staged(HeroClass.wizard);
      crawl.heroes[0].health.damage(Hero.startingHealth - 5.0);

      _run(crawl.sim, 4.0);

      expect(crawl.heroes[0].isAlive, isFalse);
      expect(crawl.monster.position!.x, greaterThan(8.0));
    });
  });

  test('an exit reached by any hero wins the run for all of them', () {
    final world = _floor();
    final mechanisms = MechanismWorld(world);
    mechanisms.add(
      Exit(name: 'exit', collider: _trigger(world, 3.0, 0.0), next: 'two'),
    );
    final heroes = <Hero>[
      _hero(world, HeroClass.elf, 0, 0.0),
      _hero(world, HeroClass.warrior, 1, -4.0),
    ];
    final sim = _crawl(world, heroes, mechanisms: mechanisms);

    heroes[0].wish.setValues(1.0, 0.0, 0.0);
    _run(sim, 2.0);

    expect(sim.outcome, RunOutcome.won);
    expect(sim.nextLevel, 'two');
  });

  test('a save taken mid-crawl continues as the crawl did', () {
    ({CrawlerSimulation sim, List<Hero> heroes}) build() {
      final world = _floor();
      final mechanisms = MechanismWorld(world)
        ..add(Food(name: 'food', collider: _trigger(world, 2.0, 0.0)))
        ..add(DoorKey(name: 'key', collider: _trigger(world, -2.0, 1.0)));
      final horde = _horde(world, seed: 9);
      final heroes = <Hero>[
        _hero(world, HeroClass.valkyrie, 0, 0.0),
        _hero(world, HeroClass.elf, 1, -3.0),
      ];
      horde.spawn(_biter, Vector3(6.0, 0.8, 4.0));
      return (
        sim: _crawl(world, heroes, mechanisms: mechanisms, horde: horde),
        heroes: heroes,
      );
    }

    void drive(
      ({CrawlerSimulation sim, List<Hero> heroes}) crawl,
      int from,
      int to,
    ) {
      for (var i = from; i < to; i++) {
        crawl.heroes[0].wish.setValues(i < 90 ? 1.0 : -0.5, 0.0, 0.3);
        crawl.heroes[1].wish.setValues(0.4, 0.0, i < 60 ? 0.2 : -1.0);
        crawl.sim.step(_dt);
      }
    }

    final straight = build();
    drive(straight, 0, 240);

    final first = build();
    drive(first, 0, 120);
    final saved = first.sim.save();
    final second = build();
    second.sim.restore(saved);
    drive(second, 120, 240);

    expect(second.sim.save().data, straight.sim.save().data);
  });
}
