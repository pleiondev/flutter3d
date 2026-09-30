import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'events.dart';
import 'framing.dart';
import 'generator.dart';
import 'hero.dart';
import 'horde.dart';
import 'loot.dart';
import 'volley.dart';

/// A crawl's step, in the order it has to happen in.
///
/// One to four heroes, a maze with its doors, loot and generators, and the
/// horde that pours out of them. The order is [WorldStep]'s, and where this
/// game puts itself between the phases is written beside each call.
///
/// **Several players is the point, and the engine carries most of it.** Every
/// monster is stepped with every living hero as a focus, so the flow field
/// sends each to the hero it can reach first and the blows it lands are
/// counted against the hero they landed on. What this class adds is what a
/// hero is: health that drains, shots, hands, potions, a key spent per door,
/// and a view none of them can leave.
final class CrawlerSimulation {
  CrawlerSimulation({
    required this.heroes,
    required this.collision,
    required this.random,
    this.mechanisms,
    this.horde,
    this.levelNext,
    CrawlFraming? framing,
  }) : framing = framing ?? CrawlFraming(),
       volley = Volley(collision) {
    horde?.actors.events = events;
    // The same assertion the platformer makes, for the same reason: a save
    // that carries one generator's state while the monsters roll another's
    // restores a run nobody played.
    assert(
      horde == null || identical(horde!.actors.random, random),
      'the ActorSystem must roll the same GameRandom this simulation saves',
    );
    _feet.addAll(<Vector3>[for (final _ in heroes) Vector3.zero()]);
  }

  /// What a potion does to everything in view, before the drinker's
  /// [HeroClass.magic] multiplies it.
  static const double potionDamage = 60.0;

  /// Everybody playing, in the order of their controllers. A hero who dies
  /// stays in the list, dead: their slot, their score and their corpse are
  /// still somebody's.
  final List<Hero> heroes;

  final CollisionWorld collision;
  final MechanismWorld? mechanisms;

  /// What walks the maze, or null for an empty one.
  final Horde? horde;

  /// Randomness a save can carry. The same object as the horde's actors'.
  final GameRandom random;

  /// What the level says comes next, passed through unread.
  final String? levelNext;

  /// The view the living heroes need, and the edge they may not cross.
  final CrawlFraming framing;

  /// The heroes' shots in flight.
  final Volley volley;

  late final WorldStep _world = WorldStep(
    collision: collision,
    mechanisms: mechanisms,
  );

  /// What this step did. Drain it after [step].
  final GameEvents events = GameEvents();

  RunOutcome outcome = RunOutcome.playing;

  /// The level an exit sent the heroes to, once one has.
  String? nextLevel;

  /// Seconds played.
  double elapsed = 0.0;

  // Reused every step, so a step allocates nothing for its bookkeeping.
  final List<Hero> _living = <Hero>[];
  final List<FocusPoint> _foci = <FocusPoint>[];
  final List<Vector3> _feet = <Vector3>[];
  final List<Vector3> _livingFeet = <Vector3>[];
  final Vector3 _wish = Vector3.zero();
  final List<Collider> _touched = <Collider>[];

  void step(double dt) {
    horde?.actors.beginStep();
    if (outcome.isOver) return;
    elapsed += dt;

    // Doors, lifts, and the generators, which give birth here: a monster born
    // this step is stepped this step.
    _world.movers(dt);

    _gatherTheLiving();
    // Before the heroes move, so that the edge each of them meets is the one
    // everybody stood inside at the start of the step — whichever controller
    // happens to be read first.
    framing.frame(_livingFeet);

    // Before the broadphase catches up, as the platformer does: a monster that
    // has moved and not been reindexed is one a hero's sweep finds where it
    // was, and a crowd is mostly monsters.
    _stepMonsters(dt);

    _world.index(dt);

    for (final hero in _living) {
      if (!hero.isAlive) continue;
      // A copy, because the wish is the player's stick and the edge is this
      // step's: a game that writes the stick only when it moves would find it
      // zeroed after the first step at the edge.
      _wish.setFrom(hero.wish);
      framing.holdIn(hero.position, _wish, hero.body.velocity, dt);
      hero.body.step(dt, wishDirection: _wish);
      if (_wish.x * _wish.x + _wish.z * _wish.z > 1e-4) {
        hero.facing
          ..setValues(_wish.x, 0.0, _wish.z)
          ..normalize();
      }
    }
    _unlockDoors();
    _fight(dt);
    _shoot(dt);
    _drink();

    _world
      ..settle()
      ..publish();

    _readLoot();
    _starve(dt);
    // After everything that can kill, so a monster slain by a shot and by a
    // potion in one step is buried once.
    horde?.bury();
    _readExits();
    if (outcome.isOver) return;
    if (heroes.every((Hero hero) => !hero.isAlive)) {
      outcome = RunOutcome.lost;
    }
  }

  void _gatherTheLiving() {
    _living.clear();
    _livingFeet.clear();
    for (var i = 0; i < heroes.length; i++) {
      final hero = heroes[i];
      if (!hero.isAlive) continue;
      _living.add(hero);
      final feet = _feet[i]
        ..setFrom(hero.position)
        ..y -= hero.body.halfExtents.y;
      _livingFeet.add(feet);
    }
  }

  void _stepMonsters(double dt) {
    final system = horde?.actors;
    if (system == null || _living.isEmpty) return;
    _foci.clear();
    for (final hero in _living) {
      _foci.add((at: hero.position, body: hero.body.collider));
    }
    system.step(dt, foci: _foci);
    // Indexed as [_foci] was, which is [_living].
    final dealt = system.damageToFoci;
    for (var i = 0; i < _living.length; i++) {
      if (dealt[i] > 0.0 && _living[i].hurt(dealt[i])) _died(_living[i]);
    }
  }

  /// Hand to hand: every living hero hurts whatever they are pressed against,
  /// at their class's rate. Walking into a monster is attacking it.
  void _fight(double dt) {
    for (final hero in _living) {
      if (!hero.isAlive) continue;
      final body = hero.body;
      // A hand's width past the body: two solid bodies stop a hair apart and
      // never overlap, and a hero pressed against a monster must reach it.
      _hands
        ..setFrom(body.halfExtents)
        ..x += 0.1
        ..z += 0.1;
      collision.overlap(
        CollisionBox(_hands),
        body.position,
        _touched,
        mask: CollisionLayers.actor,
        ignore: body.collider,
        includeTriggers: false,
      );
      for (final other in _touched) {
        _strike(hero, other.userData, hero.kind.melee * dt);
      }
    }
  }

  final Vector3 _hands = Vector3.zero();

  void _shoot(double dt) {
    for (final hero in _living) {
      if (!hero.isAlive) continue;
      if (hero.reload > 0.0) hero.reload -= dt;
      if (!hero.fire || hero.reload > 0.0) continue;
      volley.fire(hero);
      hero.reload += hero.kind.shotInterval;
    }
    for (final hit in volley.step(dt)) {
      _strike(hit.bolt.owner, hit.target, hit.bolt.damage);
    }
  }

  /// A potion reaches everything inside the edge of the view — monsters and
  /// generators alike — however many there are.
  void _drink() {
    for (final hero in _living) {
      if (!hero.drink) continue;
      hero.drink = false;
      if (!hero.isAlive || hero.potions <= 0) continue;
      hero.potions -= 1;
      final damage = potionDamage * hero.kind.magic;
      var struck = 0;
      final monsters = horde?.monsters.toList(growable: false);
      for (final monster in monsters ?? const <Actor>[]) {
        final at = monster.position;
        if (at == null || !monster.isAlive || !_inView(at)) continue;
        struck++;
        _strike(hero, monster, damage);
      }
      for (final mechanism in mechanisms?.all ?? const <Mechanism>[]) {
        if (mechanism is! Generator || mechanism.isDestroyed) continue;
        if (!_inView(mechanism.collider.position)) continue;
        struck++;
        _strike(hero, mechanism, damage);
      }
      events.add(PotionDrunk(hero, struck));
    }
  }

  bool _inView(Vector3 at) =>
      (at.x - framing.centre.x).abs() <= framing.reachX &&
      (at.z - framing.centre.z).abs() <= framing.reachZ;

  /// [hero] deals [amount] to [target], and is credited if it kills.
  void _strike(Hero hero, Object? target, double amount) {
    switch (target) {
      case final Actor monster when monster.isAlive:
        final at = monster.position?.clone() ?? Vector3.zero();
        final kind = horde?.kindOf(monster);
        if (!monster.applyDamage(amount, from: hero) || kind == null) return;
        hero.score += kind.score;
        events.add(MonsterSlain(hero, kind, at));
      case final Generator generator when !generator.isDestroyed:
        if (!generator.applyDamage(amount, from: hero)) return;
        hero.score += generator.score;
        events.add(GeneratorDestroyed(hero, generator));
    }
  }

  /// Spends a key on each locked door a hero is pressed against.
  ///
  /// By touch rather than by a use key, as in the arcade: a hero with a key
  /// walks into a door and it opens. A door is a solid body, so nothing
  /// overlaps it; touching is being within a few centimetres of its box.
  void _unlockDoors() {
    final all = mechanisms?.all;
    if (all == null) return;
    for (final mechanism in all) {
      if (mechanism is! Door) continue;
      final needs = mechanism.key;
      if (needs == null || mechanism.progress > 0.0 || mechanism.goal > 0.0) {
        continue;
      }
      for (final hero in _living) {
        if (!hero.isAlive || hero.keys <= 0) continue;
        if (!_touching(hero, mechanism.collider)) continue;
        final opened = mechanism.activate(
          Activation(by: hero.body.collider, keys: <String>{needs}),
        );
        if (opened is! Activated) continue;
        hero.keys -= 1;
        events.add(DoorUnlocked(hero, mechanism));
        break;
      }
    }
  }

  static bool _touching(Hero hero, Collider door) {
    const skin = 0.05;
    final mine = hero.body.halfExtents;
    final theirs = door.shape.boundsHalfExtents;
    final apart = hero.position - door.position;
    return apart.x.abs() <= mine.x + theirs.x + skin &&
        apart.y.abs() <= mine.y + theirs.y + skin &&
        apart.z.abs() <= mine.z + theirs.z + skin;
  }

  void _readLoot() {
    final taken = mechanisms?.events.taken;
    if (taken == null) return;
    for (final mechanism in taken) {
      if (mechanism is! Loot) continue;
      final hero = mechanism.takenBy;
      if (hero != null) events.add(LootTaken(hero, mechanism));
    }
  }

  void _starve(double dt) {
    for (final hero in _living) {
      if (!hero.isAlive) continue;
      if (hero.starve(dt)) {
        _died(hero);
        continue;
      }
      if (hero.becameHungry) events.add(HeroHungry(hero));
    }
  }

  void _died(Hero hero) {
    events.add(HeroDied(hero));
    // A corpse does not block a corridor, and a monster stops treating it as
    // somebody to chase on the next step, when it is no longer a focus.
    hero.body.collider.kind = ColliderKind.trigger;
  }

  void _readExits() {
    final reached = mechanisms?.events.reached;
    if (reached == null) return;
    for (final mechanism in reached) {
      if (mechanism is! Exit) continue;
      outcome = RunOutcome.won;
      nextLevel = mechanism.next ?? levelNext;
      return;
    }
  }

  Snapshot save() => Snapshot(<String, Object?>{
    'heroes': <Map<String, Object?>>[for (final hero in heroes) hero.save()],
    'random': random.state,
    'outcome': outcome.name,
    'elapsed': elapsed,
    'bolts': volley.save(),
    if (mechanisms != null) 'mechanisms': mechanisms!.save(),
    if (horde != null) ...<String, Object?>{
      'horde': horde!.save(),
      'entities': horde!.actors.entities.save(),
      'actors': horde!.actors.save(),
    },
  });

  void restore(Snapshot from) {
    final data = from.data;
    final saved = data['heroes'];
    if (saved is List) {
      for (var i = 0; i < heroes.length && i < saved.length; i++) {
        final row = saved[i];
        if (row is Map) heroes[i].restore(row.cast<String, Object?>());
      }
    }
    for (final hero in heroes) {
      hero.body.collider.kind = hero.isAlive
          ? ColliderKind.kinematic
          : ColliderKind.trigger;
    }
    final seed = data['random'];
    if (seed is num) random.state = seed.toInt();
    outcome = data.enumOf('outcome', RunOutcome.values, RunOutcome.playing);
    final played = data['elapsed'];
    if (played is num) elapsed = played.toDouble();

    mechanisms?.restore(data['mechanisms']);
    volley.restore(data['bolts'], (int slot) {
      for (final hero in heroes) {
        if (hero.slot == slot) return hero;
      }
      return null;
    });
    final crowd = horde;
    if (crowd != null) {
      crowd.restore(
        data['horde'],
        data.object('entities'),
        generators: (String name) {
          final found = mechanisms?[name];
          return found is Generator ? found : null;
        },
      );
      crowd.actors.restore(data['actors']);
    }

    _world.afterRestore();
  }
}
