/// A level, spawned, with its heroes standing in it ready to be stepped.
///
/// **In the package rather than in an application**, unlike the platformer's,
/// because a crawl's tests need a level turned into a crawl as much as its
/// application does, and "a harness that is not the game is a harness that
/// agrees with any bug the game has". The application's own staging calls
/// this and adds what needs a device.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'hero.dart';
import 'hero_class.dart';
import 'horde.dart';
import 'kinds.dart';
import 'monster_kind.dart';
import 'simulation.dart';

/// A crawl assembled from a level.
final class StagedCrawl {
  const StagedCrawl({
    required this.registry,
    required this.mechanisms,
    required this.horde,
    required this.sim,
  });

  /// The one registry that spawned the document.
  final EntityRegistry registry;
  final MechanismWorld mechanisms;
  final Horde horde;
  final CrawlerSimulation sim;
}

/// Turns [level] into a crawl for [party], one hero per class, in slot order.
///
/// [world] must already hold the level's brushes: an application gets them
/// from its level loader, a test from `level.addTo(world)`.
///
/// A hero stands on the `player_spawn` whose `slot` is theirs; a slot the
/// level has no spawn for stands beside the first one, a metre and a half
/// along for each slot, so a level written for one player still seats four.
StagedCrawl stageCrawl(
  Level level,
  CollisionWorld world, {
  required List<HeroClass> party,
  List<MonsterKind> kinds = MonsterKind.all,
  EntityRegistry? registry,
  GameRandom? random,
  void Function(Fixture fixture)? onFixture,
}) {
  final registered = registry ?? crawlerRegistry(kinds: kinds);
  // One generator for the monsters and the save, as every genre's staging
  // insists: two are two sequences, of which a save records one.
  final dice = random ?? GameRandom(1);
  final actors = ActorSystem(world: world, random: dice)
    ..navigation = Navigation.bake(level);
  final horde = Horde(actors, kinds: kinds);
  for (final type in <String>[
    CrawlerEntities.generator,
    CrawlerEntities.monster,
  ]) {
    final kind = registered[type];
    if (kind is GeneratorKind) kind.horde = horde;
    if (kind is MonsterEntityKind) kind.horde = horde;
  }
  final mechanisms = MechanismWorld(world);

  level.spawnInto(
    SpawnContext(
      world: world,
      actors: actors,
      mechanisms: mechanisms,
      onFixture: onFixture,
    ),
    registry: registered,
  );

  final spawns = level.ofType(EntityTypes.playerSpawn).toList();
  final first = spawns.isEmpty ? Vector3.zero() : spawns.first.position;
  final heroes = <Hero>[
    for (var slot = 0; slot < party.length; slot++)
      Hero(
        world: world,
        kind: party[slot],
        slot: slot,
        at: _startOf(spawns, slot, first) + Vector3(0.0, 0.9, 0.0),
      ),
  ];

  return StagedCrawl(
    registry: registered,
    mechanisms: mechanisms,
    horde: horde,
    sim: CrawlerSimulation(
      heroes: heroes,
      collision: world,
      random: dice,
      mechanisms: mechanisms,
      horde: horde,
      levelNext: level.next,
    ),
  );
}

Vector3 _startOf(List<EntityDef> spawns, int slot, Vector3 first) {
  for (final spawn in spawns) {
    if ((spawn.integer('slot') ?? 0) == slot) return spawn.position;
  }
  return first + Vector3(1.5 * slot, 0.0, 0.0);
}
