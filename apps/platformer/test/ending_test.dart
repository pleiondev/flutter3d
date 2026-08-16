/// How the game opens and how it ends.
///
///     flutter test test/ending_test.dart
///
/// **It did neither.** The application opened straight into the tutorial with a
/// `Click to play` banner over it — no name, no keys, and nowhere to put the
/// attribution its models' licence requires — and finishing the last level put
/// up the same panel as finishing the first one, whose entire message was
/// "Press escape to let the mouse go". Four hundred metres of climbing, and the
/// reward was a note about the mouse pointer.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter3d_platformer/flutter3d_platformer.dart' show RunState;
import 'package:flutter_test/flutter_test.dart';
import 'package:platformer/src/credits.dart';
import 'package:platformer/src/hud.dart';
import 'package:platformer/src/title_card.dart';

Widget _hud({required bool finale}) => MaterialApp(
      home: Hud(
        coins: 12,
        deaths: 4,
        lives: 3,
        elapsed: 610.0,
        state: RunState.finished,
        captured: true,
        levelName: 'Ascent',
        finale: finale,
      ),
    );

Map<String, Object?> _level(String name) => jsonDecode(
      File('assets/levels/$name').readAsStringSync(),
    ) as Map<String, Object?>;

void main() {
  test('the shipped levels say which one is the last', () {
    // **What `finale` reads, checked against the content rather than assumed.**
    // The flag is `nextLevel == null`, so a third level chained after Ascent
    // would move the ending — and this is the test that would say so instead of
    // the credits quietly appearing halfway through the game.
    expect(_level('first_steps.json')['next'], isNotNull,
        reason: 'the tutorial is not the end of the game');
    expect(_level('ascent.json')['next'], isNull,
        reason: 'Ascent is the last level, and the ending belongs to it');
  });

  group('the ending', () {
    testWidgets('says the game is over and who made it', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_hud(finale: true));

      expect(find.textContaining('reached the summit'), findsOneWidget);
      // The credits are here because the licence puts them here, and this is
      // the acceptance the plan asked for in as many words: the author's name
      // and a link to the licence.
      for (final credit in Credits.owed) {
        expect(find.textContaining(credit.author!), findsWidgets);
        expect(find.text(credit.licenceUrl!), findsWidgets);
      }
      expect(find.textContaining('Press R'), findsOneWidget);
    });

    testWidgets('and finishing a level that is not the last does not', (
      WidgetTester tester,
    ) async {
      // Otherwise the credits roll after the tutorial, four hundred metres
      // early.
      await tester.pumpWidget(_hud(finale: false));

      expect(find.textContaining('reached the summit'), findsNothing);
      expect(find.text('Ascent'), findsOneWidget);
    });
  });

  group('the title card', () {
    testWidgets('names the game, the keys and the authors', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: TitleCard(prompt: 'Click to take the mouse.')),
      );

      expect(find.text('Ascent'), findsOneWidget);
      // The two moves the level was rebuilt to ask for. A player who is not
      // told about the dash finds a nine-metre gap and no way over it.
      expect(find.textContaining('dash'), findsOneWidget);
      expect(find.textContaining('jump'), findsWidgets);
      for (final credit in Credits.owed) {
        expect(find.textContaining(credit.author!), findsWidgets);
      }
      expect(find.text('Click to take the mouse.'), findsOneWidget);
    });

    testWidgets('and says when there is a run waiting behind it', (
      WidgetTester tester,
    ) async {
      // The game writes a checkpoint silently, so the only way a player learns
      // their progress was kept is by being told.
      await tester.pumpWidget(
        const MaterialApp(
          home: TitleCard(prompt: 'Click.', resuming: true),
        ),
      );

      expect(find.textContaining('checkpoint'), findsOneWidget);
    });

    testWidgets('and does not promise one that is not there', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: TitleCard(prompt: 'Click.')),
      );

      expect(find.textContaining('checkpoint'), findsNothing);
    });
  });
}
