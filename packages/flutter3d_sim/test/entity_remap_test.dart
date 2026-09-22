/// `rp-03`'s second half: a save restored into a level that removed or
/// reordered an entity lands on the right survivor, by name, and names what
/// it could not place — proven against a real [EcsWorld], not a hand-typed
/// map standing in for one.
///
///     dart test test/entity_remap_test.dart
library;

import 'package:flutter3d_sim/src/ecs/ecs_world.dart';
import 'package:flutter3d_sim/src/ecs/entity_remap.dart';
import 'package:test/test.dart';

final class _Health {
  _Health(this.value);
  double value;
}

EcsWorld _world() => EcsWorld()
  ..register<_Health>(
    'health',
    encode: (_Health h) => h.value,
    decode: (Object? data) => _Health((data! as num).toDouble()),
  );

void main() {
  test('removing the middle of three named monsters does not misattribute the '
      'other two', () {
    // The old level: three monsters, spawned in document order, each given
    // a name the way `rp-03`'s write-up says a game's own spawn code would
    // — this file stands in for that code with a plain map, since nothing
    // shipped calls `remapEntitySave` yet.
    final oldWorld = _world();
    final guard = oldWorld.spawn();
    final archer = oldWorld.spawn();
    final ogre = oldWorld.spawn();
    oldWorld.set(guard, _Health(30.0));
    oldWorld.set(archer, _Health(18.0));
    oldWorld.set(ogre, _Health(90.0));
    final oldNames = <String?>['guard', 'archer', 'ogre'];

    final saved = oldWorld.save();

    // The edited level: the archer removed, so the ogre — spawned after it
    // — gets the archer's old index in the new world.
    final newWorld = _world();
    final newGuard = newWorld.spawn();
    final newOgre = newWorld.spawn();
    expect(
      newOgre.index,
      archer.index,
      reason:
          'the whole point of the '
          'test: the ogre now sits where the archer used to',
    );
    final newNames = <String?>['guard', 'ogre'];

    final remap = remapEntitySave(
      saved,
      oldNames: oldNames,
      newNames: newNames,
      newGenerations: newWorld.save()['generations']! as List<int>,
      newFree: newWorld.save()['free']! as List<int>,
    );

    expect(remap.dropped, <String>['archer']);

    newWorld.restore(remap.save);

    expect(
      newWorld.get<_Health>(newGuard)?.value,
      30.0,
      reason: 'the guard kept its own health',
    );
    expect(
      newWorld.get<_Health>(newOgre)?.value,
      90.0,
      reason:
          'the ogre kept its own ninety, not the archer\'s eighteen — '
          'the bug this whole mechanism exists to catch',
    );
  });

  test('an entity nobody named is dropped and reported, not misattributed', () {
    final oldWorld = _world();
    final named = oldWorld.spawn();
    final anonymous = oldWorld.spawn();
    oldWorld.set(named, _Health(50.0));
    oldWorld.set(anonymous, _Health(999.0));

    final saved = oldWorld.save();

    final newWorld = _world();
    final newNamed = newWorld.spawn();

    final remap = remapEntitySave(
      saved,
      oldNames: <String?>['named', null],
      newNames: <String?>['named'],
      newGenerations: newWorld.save()['generations']! as List<int>,
      newFree: newWorld.save()['free']! as List<int>,
    );

    expect(remap.dropped.single, contains('no name recorded'));
    newWorld.restore(remap.save);
    expect(newWorld.get<_Health>(newNamed)?.value, 50.0);
  });

  test('reordering with nothing removed loses nothing and drops nothing', () {
    final oldWorld = _world();
    final a = oldWorld.spawn();
    final b = oldWorld.spawn();
    oldWorld.set(a, _Health(10.0));
    oldWorld.set(b, _Health(20.0));

    final saved = oldWorld.save();

    // The edited level lists them the other way around.
    final newWorld = _world();
    final newB = newWorld.spawn();
    final newA = newWorld.spawn();

    final remap = remapEntitySave(
      saved,
      oldNames: <String?>['a', 'b'],
      newNames: <String?>['b', 'a'],
      newGenerations: newWorld.save()['generations']! as List<int>,
      newFree: newWorld.save()['free']! as List<int>,
    );

    expect(remap.dropped, isEmpty);
    newWorld.restore(remap.save);
    expect(newWorld.get<_Health>(newA)?.value, 10.0);
    expect(newWorld.get<_Health>(newB)?.value, 20.0);
  });

  test('a name the new level does not have at all is dropped and named', () {
    final oldWorld = _world();
    final gone = oldWorld.spawn();
    oldWorld.set(gone, _Health(5.0));

    final remap = remapEntitySave(
      oldWorld.save(),
      oldNames: <String?>['gone'],
      newNames: <String?>[],
      newGenerations: <int>[],
      newFree: <int>[],
    );

    expect(remap.dropped, <String>['gone']);
    expect(remap.save['components'], isEmpty);
  });
}
