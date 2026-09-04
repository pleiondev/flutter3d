/// The readouts, and what they refuse to draw.
///
///     flutter test test/hud_test.dart
///
/// Claims about what appears rather than about how it looks. The two that
/// matter are both absences: a purse draws what is in it rather than a fixed
/// list of kinds, and a run with no life limit draws no pips at all.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  Directionality(textDirection: TextDirection.ltr, child: child),
);

void main() {
  group('the purse readout', () {
    testWidgets('draws what is in the purse, whatever the level called it', (
      WidgetTester t,
    ) async {
      // A readout built around "coins" has to be rewritten the first time a
      // level has gems in it.
      final purse = Purse()
        ..add('coin', 3)
        ..add('gem');

      await _pump(t, PurseReadout(purse: purse));

      expect(find.text('coin 3'), findsOneWidget);
      expect(find.text('gem 1'), findsOneWidget);
    });

    testWidgets('and only the kinds asked for, in the order asked', (
      WidgetTester t,
    ) async {
      final purse = Purse()
        ..add('coin')
        ..add('gem');

      await _pump(t, PurseReadout(purse: purse, order: const <String>['gem']));

      expect(find.text('gem 1'), findsOneWidget);
      expect(find.text('coin 1'), findsNothing);
    });
  });

  group('the lives strip', () {
    testWidgets('draws nothing at all where nothing is counting', (
      WidgetTester t,
    ) async {
      // `PlatformerSimulation.lives` is negative when the run has no limit,
      // and an infinity sign or a large number is worse than no strip.
      await _pump(t, const LivesStrip(lives: -1));

      expect(find.byType(DecoratedBox), findsNothing);
    });

    testWidgets('one pip per life left', (WidgetTester t) async {
      await _pump(t, const LivesStrip(lives: 2));

      expect(find.byType(DecoratedBox), findsNWidgets(2));
    });

    testWidgets('and the spent ones stay, dim, when the start is known', (
      WidgetTester t,
    ) async {
      // A strip that shrinks tells the player how many are left; one that
      // dims tells them how many they have used, which is the thing they are
      // actually deciding about.
      await _pump(t, const LivesStrip(lives: 1, of: 3));

      expect(find.byType(DecoratedBox), findsNWidgets(3));
    });
  });
}
