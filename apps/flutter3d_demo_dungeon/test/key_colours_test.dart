/// The keys a player carries: told apart by colour where colour tells them
/// apart, and by their initial where it might not.
///
///     flutter test test/key_colours_test.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart' show ColorVision;
import 'package:flutter3d_demo_dungeon/src/fixture_looks.dart';
import 'package:flutter3d_demo_dungeon/src/hud.dart';
import 'package:flutter3d_game/flutter3d_game.dart' show ColorRoles, GameConfig;
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_game_shooter/sample.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

/// Every level's key colours, by level file.
Map<String, Set<String>> _keysByLevel() => <String, Set<String>>{
  for (final file in Directory('assets/levels').listSync().whereType<File>())
    if (file.path.endsWith('.json') && !file.path.contains('visibility'))
      file.path: <String>{
        for (final entity in Level.fromJson(
          jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
        ).ofType('key'))
          if (entity.string('color') case final String colour) colour,
      },
};

(double, double, double) _srgb(Color c) => (c.r, c.g, c.b);

void main() {
  test('every key a level has is a colour of its own, carried and lying', () {
    // Mutation: the table as it was, with only blue, red and yellow — every
    // shipped level's keys fell to the same fallback.
    final used = _keysByLevel().values.expand((Set<String> s) => s).toSet();
    expect(used, isNotEmpty);
    for (final key in used) {
      expect(keyPipColours, contains(key), reason: 'no mark for $key');
      expect(DungeonFixtures.keyColours, contains(key), reason: 'no $key key');
    }
  });

  test('no level has two keys a deficiency runs together', () {
    for (final MapEntry(key: level, value: keys) in _keysByLevel().entries) {
      final confusions = ColorVision.confusions(
        <String, (double, double, double)>{
          for (final key in keys) key: _srgb(keyPipColours[key]!),
        },
      );
      expect(confusions, isEmpty, reason: '$level: $confusions');
    }
  });

  test('every key a level has is a colour the player can change', () {
    final config = GameConfig();
    for (final key in _keysByLevel().values.expand((Set<String> s) => s)) {
      expect(dungeonColours.named('key.$key'), isNotNull, reason: key);
    }
    config.setSetting('colour.key.brass', 4);
    expect(
      dungeonColours.colourOf('key.brass', config, fallback: Colors.white),
      ColorRoles.palette[3],
    );
  });

  testWidgets('a mark is drawn in the colour it is given', (
    WidgetTester tester,
  ) async {
    // Mutation: the HUD reading its own table rather than the colours the
    // game hands it ignores whatever the player chose.
    await tester.pumpWidget(
      MaterialApp(
        home: _hud(keyColours: <String, Color>{'brass': ColorRoles.palette[3]}),
      ),
    );
    final box = tester.widget<DecoratedBox>(
      find
          .ancestor(
            of: find.byKey(const ValueKey<String>('key-pip:brass')),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect((box.decoration as BoxDecoration).color, ColorRoles.palette[3]);
  });

  testWidgets('each carried key is marked with its initial', (
    WidgetTester tester,
  ) async {
    // Brass runs into red for a deutan and into yellow for a tritan, in
    // `ColorVision.confusions`; a level with both would rest on colour
    // alone without this. Mutation: the mark without its letter.
    await tester.pumpWidget(MaterialApp(home: _hud()));
    expect(find.byKey(const ValueKey<String>('key-pip:brass')), findsOne);
    expect(find.text('B'), findsOne);
    expect(find.text('I'), findsOne);
  });
}

Hud _hud({Map<String, Color> keyColours = keyPipColours}) => Hud(
  captured: true,
  fps: 60,
  steps: 1,
  dropped: 0,
  voices: 0,
  particles: 0,
  position: Vector3.zero(),
  grounded: true,
  weapon: Weapons.pistol,
  ammo: 10,
  hitFlash: 0,
  painFlash: 0,
  health: Health(100),
  kills: 0,
  monstersLeft: 0,
  message: '',
  messageOpacity: 0,
  keys: const <String>{'brass', 'iron'},
  armour: 0,
  pouches: const <AmmoType, int>{},
  powers: const <String, double>{},
  keyColours: keyColours,
);
