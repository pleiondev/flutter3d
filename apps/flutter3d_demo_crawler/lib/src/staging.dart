/// A level, spawned, with the party standing in it ready to be stepped.
///
/// The one place this application assembles a crawl, and the one its tests
/// call: a harness that built its own would agree with any bug the game has.
/// The assembly itself is the genre package's `stageCrawl`; what is here is
/// what this game adds to it, which is carrying a party from one level to the
/// next.
library;

import 'package:flutter3d_game_crawler/flutter3d_game_crawler.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

/// Turns [level] into a crawl for [party].
///
/// [carried] are the heroes of the level before, in slot order: each new
/// hero takes up their health, keys, potions and score, and one who died
/// there is dead here too. [world] must already hold the level's brushes.
StagedCrawl stage(
  Level level,
  CollisionWorld world, {
  required List<HeroClass> party,
  List<Hero> carried = const <Hero>[],
  EntityRegistry? registry,
  void Function(Fixture fixture)? onFixture,
  GameRandom? random,
}) {
  final staged = stageCrawl(
    level,
    world,
    party: party,
    registry: registry,
    onFixture: onFixture,
    random: random,
  );
  final heroes = staged.sim.heroes;
  for (var i = 0; i < heroes.length && i < carried.length; i++) {
    final from = carried[i];
    heroes[i]
      ..keys = from.keys
      ..potions = from.potions
      ..score = from.score
      ..health.restore(from.health.save());
    if (!heroes[i].isAlive) {
      heroes[i].body.collider.kind = ColliderKind.trigger;
    }
  }
  return staged;
}
