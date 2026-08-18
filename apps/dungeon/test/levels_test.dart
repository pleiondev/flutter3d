/// The three documents this game ships, and the chain through them.
///
///     flutter test test/levels_test.dart
///
/// **There used to be one level and `next` was empty.** The machinery to move on
/// was written, tested and pointed at nothing. What this file checks is the
/// half a generator cannot: that the chain arrives somewhere, that every
/// document on it loads, and that each one can be stood up in.
///
/// Walked from the level list rather than from a list written here, so a fourth
/// document added to the chain is checked the day it is added.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dungeon/src/staging.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_shooter/flutter3d_shooter.dart';
import 'package:flutter3d_shooter/sample.dart';
import 'package:flutter_test/flutter_test.dart';

const String _first = 'assets/levels/crypt.json';

Level _read(String path) => Level.fromJson(
      jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>,
    );

/// The chain, from [_first] until something says nothing comes next.
List<({String path, Level level})> _chain() {
  final out = <({String path, Level level})>[];
  final seen = <String>{};
  String? path = _first;
  while (path != null) {
    if (!seen.add(path)) {
      fail('the chain loops: $path is reached twice');
    }
    expect(File(path).existsSync(), isTrue,
        reason: 'the chain names $path, which is not there');
    final level = _read(path);
    out.add((path: path, level: level));
    path = level.next;
  }
  return out;
}

void main() {
  test('the chain is three levels and ends', () {
    // Ending matters as much as arriving: a last level with a `next` is a game
    // that shows an error screen instead of credits.
    final chain = _chain();

    expect(chain.map((r) => r.path).toList(), <String>[
      'assets/levels/crypt.json',
      'assets/levels/vaults.json',
      'assets/levels/deep.json',
    ]);
    expect(chain.last.level.next, isNull, reason: 'the last level leads on');
  });

  test('and every document on it is valid against the shipped registry', () {
    // The validator runs against the same registry the game spawns from, so
    // the two cannot disagree about what a document may contain.
    for (final step in _chain()) {
      final issues = LevelValidator(
        registry: sampleRegistry(),
        rules: sampleRules(),
      ).validate(step.level);

      expect(issues.where((LevelIssue i) => i.isError), isEmpty,
          reason: '${step.path}:\n${issues.join('\n')}');
    }
  });

  test('and every one can be stood up in, with a way out of it', () {
    // Spawned, not merely parsed. A level whose entities refuse to spawn parses
    // perfectly and is unplayable, which is the failure the registry seam
    // exists to make loud — and it is only loud if somebody spawns.
    for (final step in _chain()) {
      final world = CollisionWorld();
      step.level.addTo(world);
      final staged = stage(
        step.level,
        world,
        input: InputState(),
        registry: sampleRegistry(),
        inventory: startingInventory(),
      );
      world.update();

      expect(staged.player.isAlive, isTrue, reason: '${step.path}: dead on arrival');
      expect(
        staged.mechanisms.all.whereType<Exit>(),
        isNotEmpty,
        reason: '${step.path} has no way out of it',
      );
      expect(staged.navIssues.where((LevelIssue i) => i.isError), isEmpty,
          reason: '${step.path}: ${staged.navIssues.join('\n')}');
    }
  });

  test('and every locked door has its key somewhere on the same level', () {
    // **The failure a chain makes possible.** Keys do not carry between levels
    // — deliberately, because a player arriving at the second level holding the
    // third level's key is a designer's promise broken by the plumbing. Which
    // means a door whose key is in the level before it is a level that cannot
    // be finished, and nothing else in this repository would notice.
    for (final step in _chain()) {
      final keys = step.level.entities
          .where((EntityDef e) => e.type == EntityTypes.key)
          .map((EntityDef e) => e.properties['color'])
          .whereType<String>()
          .toSet();
      final locks = step.level.entities
          .where((EntityDef e) => e.type == EntityTypes.door)
          .map((EntityDef e) => e.properties['key'])
          .whereType<String>()
          .toSet();

      expect(locks.difference(keys), isEmpty,
          reason: '${step.path} locks a door with a key that is not in it');
    }
  });

  test('and the fight gets harder rather than merely longer', () {
    // Not a rule the engine could enforce, and worth writing down anyway: three
    // levels that are the same fight three times is a game with one level in
    // it. Counted by kind, because that is what changes — the crypt has no
    // tanks and the deep is mostly tanks.
    int tanksIn(Level level) => level.entities
        .where((EntityDef e) =>
            e.type == ShooterEntities.monster &&
            e.properties['kind'] == 'tank')
        .length;

    final chain = _chain();
    expect(tanksIn(chain.first.level), 0,
        reason: 'the first level opens with the slowest, hardest thing');
    expect(tanksIn(chain.last.level), greaterThan(1));
  });
}
