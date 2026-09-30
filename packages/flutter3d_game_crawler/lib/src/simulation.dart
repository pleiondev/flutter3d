import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'events.dart';
import 'framing.dart';
import 'hero.dart';
import 'loot.dart';

/// A crawl's step, in the order it has to happen in.
///
/// One to four heroes, a maze with its doors and loot, and whatever walks in
/// it. The order is [WorldStep]'s, and where this game puts itself between
/// the phases is written beside each call.
///
/// **Several players is the point, and the engine carries most of it.** Every
/// monster is stepped with every living hero as a focus, so the flow field
/// sends each to the hero it can reach first and the blows it lands are
/// counted against the hero they landed on. What this class adds is what a
/// hero is: health that drains, a key spent per door, and a view none of them
/// can leave.
final class CrawlerSimulation {
  CrawlerSimulation({
    required this.heroes,
    required this.collision,
    required this.random,
    this.mechanisms,
    this.actors,
    this.levelNext,
    CrawlFraming? framing,
  }) : framing = framing ?? CrawlFraming() {
    actors?.events = events;
    // The same assertion the platformer makes, for the same reason: a save
    // that carries one generator's state while the monsters roll another's
    // restores a run nobody played.
    assert(
      actors == null || identical(actors!.random, random),
      'the ActorSystem must roll the same GameRandom this simulation saves',
    );
    _feet.addAll(<Vector3>[for (final _ in heroes) Vector3.zero()]);
  }

  /// Everybody playing, in the order of their controllers. A hero who dies
  /// stays in the list, dead: their slot, their score and their corpse are
  /// still somebody's.
  final List<Hero> heroes;

  final CollisionWorld collision;
  final MechanismWorld? mechanisms;

  /// What walks the maze, or null for an empty one.
  final ActorSystem? actors;

  /// Randomness a save can carry. The same object as [actors]'s.
  final GameRandom random;

  /// What the level says comes next, passed through unread.
  final String? levelNext;

  /// The view the living heroes need, and the edge they may not cross.
  final CrawlFraming framing;

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

  void step(double dt) {
    actors?.beginStep();
    if (outcome.isOver) return;
    elapsed += dt;

    _world.movers(dt);

    _gatherTheLiving();
    // Before the heroes move, so that the edge each of them meets is the one
    // everybody stood inside at the start of the step — whichever controller
    // happens to be read first.
    framing.frame(_livingFeet);

    // Before the broadphase catches up, as the platformer does: a monster that
    // has moved and not been reindexed is one a hero's sweep finds where it
    // was, and a crowd is mostly monsters.
    _stepActors(dt);

    _world.index(dt);

    for (final hero in _living) {
      if (!hero.isAlive) continue;
      // A copy, because the wish is the player's stick and the edge is this
      // step's: a game that writes the stick only when it moves would find it
      // zeroed after the first step at the edge.
      _wish.setFrom(hero.wish);
      framing.holdIn(hero.position, _wish, hero.body.velocity, dt);
      hero.body.step(dt, wishDirection: _wish);
    }
    _unlockDoors();

    _world
      ..settle()
      ..publish();

    _readLoot();
    _starve(dt);
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

  void _stepActors(double dt) {
    final system = actors;
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
    if (mechanisms != null) 'mechanisms': mechanisms!.save(),
    if (actors != null) 'entities': actors!.entities.save(),
    if (actors != null) 'actors': actors!.save(),
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
    final entities = data.object('entities');
    if (actors != null && entities != null) actors!.entities.restore(entities);
    actors?.restore(data['actors']);
    actors?.syncCorpses();

    _world.afterRestore();
  }
}
