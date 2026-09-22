/// `rp-03`'s second half, wired into a real genre: a level with a named
/// monster removed restores the survivors' health onto the survivors, not
/// onto whoever now happens to sit at their old index.
///
///     flutter test test/entity_remap_test.dart
///
/// `packages/flutter3d_sim/test/entity_remap_test.dart` proves
/// `remapEntitySave` against a bare `EcsWorld`; this proves the other half —
/// that `EnemyKind.spawn` actually hands `EntityDef.name` through to
/// `ActorSystem`, so `ActorSystem.nameList()` has something real to work
/// with rather than a name a test typed in by hand.
library;

import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

/// Three named hunters, or two — a stand-in for "the level before an edit"
/// and "the level after one enemy was deleted in it".
List<EntityDef> _enemies(List<String> names) => <EntityDef>[
  for (final name in names)
    EntityDef(
      type: 'enemy',
      name: name,
      properties: <String, Object?>{
        'kind': 'hunter',
        'health': names.indexOf(name) == 0
            ? 30.0
            : names.indexOf(name) == 1
            ? 18.0
            : 90.0,
      },
    ),
];

({ActorSystem actors, CollisionWorld world}) _spawnAll(List<EntityDef> defs) {
  final world = CollisionWorld();
  final actors = ActorSystem(world: world, random: GameRandom(1));
  final mechanisms = MechanismWorld(world);
  final context = SpawnContext(
    world: world,
    actors: actors,
    mechanisms: mechanisms,
  );
  final kind = EnemyKind();
  for (final def in defs) {
    kind.spawn(def, context);
  }
  return (actors: actors, world: world);
}

void main() {
  test('removing the middle of three named enemies from the level does not '
      'misattribute the survivors\' health', () {
    final before = _spawnAll(_enemies(<String>['guard', 'archer', 'ogre']));
    final guard = before.actors.byName('guard')!;
    final archer = before.actors.byName('archer')!;
    final ogre = before.actors.byName('ogre')!;
    expect(guard.health?.current, 30.0);
    expect(archer.health?.current, 18.0);
    expect(ogre.health?.current, 90.0);

    final oldNames = before.actors.nameList();
    final saved = before.actors.entities.save();

    // The level, edited: the archer is gone.
    final after = _spawnAll(_enemies(<String>['guard', 'ogre']));
    final newGuard = after.actors.byName('guard')!;
    final newOgre = after.actors.byName('ogre')!;
    // The whole point of the test: the ogre now sits where the archer used
    // to, because it was spawned second rather than third.
    expect(newOgre.entity.index, archer.entity.index);

    final newSave = after.actors.entities.save();
    final remap = remapEntitySave(
      saved,
      oldNames: oldNames,
      newNames: after.actors.nameList(),
      newGenerations: newSave['generations']! as List<int>,
      newFree: newSave['free']! as List<int>,
    );

    expect(remap.dropped, <String>['archer']);

    after.actors.entities.restore(remap.save);

    expect(
      newGuard.health?.current,
      30.0,
      reason: 'the guard kept its own health',
    );
    expect(
      newOgre.health?.current,
      90.0,
      reason:
          'the ogre kept its own ninety, not the archer\'s eighteen — the '
          'bug the whole mechanism exists to catch, this time through the '
          'real EnemyKind rather than a hand-typed name list',
    );
  });
}
