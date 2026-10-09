/// Levels made from a seed when they are reached.
///
///     dart test test/seeded_levels_test.dart
///
/// A seeded level is named where an asset would be and read back from its
/// name; the same seed makes the same level; each names the next; and the
/// rules are asked for by depth, counted from the run's first seed.
library;

import 'dart:convert';

import 'package:flutter3d_game_kit/seeded_levels.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

LevelRules _named(int depth) =>
    LevelRules(columns: 2, rows: 2, name: 'Down ${depth + 1}');

void main() {
  const levels = SeededLevels(rulesFor: _named);

  test('a seed is named where an asset would be, and read back', () {
    expect(levels.first(7), 'generated:7');
    expect(levels.seedOf(levels.first(7)), 7);
    // Mutation: read every name as a seed, and an asset of the game's own
    // whose name happens to end in digits opens as a generated level.
    expect(levels.seedOf('levels/crypt2.json'), isNull);
    expect(levels.seedOf('generated:deep'), isNull);
  });

  test('a game picks its own prefix', () {
    const own = SeededLevels(rulesFor: _named, prefix: 'seed/');
    expect(own.first(3), 'seed/3');
    expect(own.seedOf('seed/3'), 3);
    // Mutation: compare against the default prefix rather than this one.
    expect(own.seedOf('generated:3'), isNull);
  });

  test('the same seed makes the same level, which names the next', () async {
    final a = await levels.level(4, first: 4);
    final b = await levels.level(4, first: 4);
    expect(jsonEncode(a.toJson()), jsonEncode(b.toJson()));
    final next = levels.seedOf(a.next!);
    // Mutation: name the same seed again as the next, and the run walks
    // into the level it just left.
    expect(next, isNotNull);
    expect(next, greaterThan(4));
  });

  test('the rules are asked for by depth from the first seed', () async {
    final top = await levels.level(10, first: 10);
    final third = await levels.level(12, first: 10);
    // Mutation: ask for the rules by seed rather than depth, and the first
    // level is named "Down 11".
    expect(top.name, 'Down 1');
    expect(third.name, 'Down 3');
  });
}
