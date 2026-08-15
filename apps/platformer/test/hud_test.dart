/// What a player is told about their run.
///
///     flutter test test/hud_test.dart
///
/// A HUD is the one part of a game with no simulation under it to be right on
/// its behalf: a wrong number here is wrong on the screen and nowhere else. So
/// these are widget tests rather than pixel ones — what is asserted is the text
/// a player reads.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_platformer/flutter3d_platformer.dart' show RunState;
import 'package:flutter_test/flutter_test.dart';
import 'package:platformer/src/hud.dart';

Widget _hud({
  int coins = 0,
  int deaths = 0,
  int lives = 3,
  double elapsed = 0.0,
  RunState state = RunState.running,
}) =>
    MaterialApp(
      home: Hud(
        coins: coins,
        deaths: deaths,
        lives: lives,
        elapsed: elapsed,
        state: state,
        captured: true,
        levelName: 'First Steps',
      ),
    );

void main() {
  test('the clock reads as a time rather than a count of seconds', () {
    // Mutation: print the raw number. `125.4` is a duration nobody reads, and
    // a run timer is the one number a player compares between attempts.
    expect(clock(0.0), '0:00');
    expect(clock(9.9), '0:09', reason: 'a second is not counted until it is');
    expect(clock(65.0), '1:05');
    expect(clock(600.0), '10:00');
  });

  testWidgets('lives are shown when a run can be lost, and not when it cannot',
      (WidgetTester tester) async {
    // Mutation: always show them. An endless run reports "lives -1", which is
    // the package's way of saying "this does not apply" written on the screen.
    await tester.pumpWidget(_hud(lives: 2));
    expect(find.text('lives'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    await tester.pumpWidget(_hud(lives: -1));
    expect(find.text('lives'), findsNothing);
  });

  testWidgets('a finished run is named and totalled', (WidgetTester tester) async {
    await tester.pumpWidget(
      _hud(state: RunState.finished, coins: 12, deaths: 3, elapsed: 91.0),
    );

    expect(find.text('First Steps'), findsOneWidget);
    expect(find.text('1:31'), findsWidgets);
    expect(find.text('12'), findsWidgets);
  });

  testWidgets('a lost run says so, and says what to press',
      (WidgetTester tester) async {
    // Mutation: show the same banner for both endings. A player who ran out of
    // lives is told they finished the level, and the level is still there.
    await tester.pumpWidget(_hud(state: RunState.lost, lives: 0));

    expect(find.text('Out of lives'), findsOneWidget);
    expect(find.textContaining('Press R'), findsOneWidget);
    expect(find.text('First Steps'), findsNothing);
  });

  testWidgets('a run in progress has no results screen over it',
      (WidgetTester tester) async {
    await tester.pumpWidget(_hud(elapsed: 12.0));

    expect(find.text('Out of lives'), findsNothing);
    expect(find.text('First Steps'), findsNothing);
    expect(find.text('0:12'), findsOneWidget);
  });
}
