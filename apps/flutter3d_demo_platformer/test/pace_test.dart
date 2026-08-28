/// What the player is told when the machine cannot keep up.
///
///     flutter test test/pace_test.dart
///
/// **The other half of `flutter3d_game/test/pace_test.dart`**, which keeps the
/// mechanism — `Pace` counting the simulated time a slow machine never ran. The
/// sentence on the screen is this game's, so it is tested here.
///
/// It used to be tested there, by dev-depending on this application from inside
/// the engine and importing its `lib/src`. That is a cycle
/// (`flutter3d_game` → `platformer` → `flutter3d_game`), it reaches into
/// another package's private half, and it sat two lines under a pubspec comment
/// explaining that the dependency runs the other way round.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_demo_platformer/src/hud.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart'
    show RunState;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('what the player is told', () {
    Widget hud({bool behind = false, double lost = 0.0, RunState? state}) =>
        MaterialApp(
          home: Hud(
            coins: 0,
            deaths: 0,
            lives: 3,
            elapsed: 61.0,
            state: state ?? RunState.running,
            captured: true,
            levelName: 'Ascent',
            behind: behind,
            lost: lost,
          ),
        );

    testWidgets('a slow machine is named as the slow thing', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(hud(behind: true));

      expect(find.textContaining('running slowly'), findsOneWidget);
    });

    testWidgets('and nothing is said when it is keeping up', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(hud());

      expect(find.textContaining('running slowly'), findsNothing);
    });

    testWidgets('a finished run owns up to the time it lost', (
      WidgetTester tester,
    ) async {
      // The clock counts simulated seconds, so a run that dropped four of them
      // took four seconds longer than it says.
      await tester.pumpWidget(hud(lost: 4.2, state: RunState.finished));

      expect(find.textContaining('lost 4s'), findsOneWidget);
    });

    testWidgets('and says nothing about a fraction of a second', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(hud(lost: 0.2, state: RunState.finished));

      expect(find.textContaining('lost'), findsNothing);
    });
  });
}
