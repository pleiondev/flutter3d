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
import 'package:flutter3d_demo_platformer/src/hud.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart' show RunState;
import 'package:flutter_test/flutter_test.dart';

Widget _hud({
  int coins = 0,
  int deaths = 0,
  int lives = 3,
  double elapsed = 0.0,
  RunState state = RunState.running,
  Set<String> keys = const <String>{},
  String? message,
  double textScale = 1.0,
}) =>
    MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: MaterialApp(
      home: Hud(
        coins: coins,
        deaths: deaths,
        lives: lives,
        elapsed: elapsed,
        state: state,
        captured: true,
        levelName: 'First Steps',
        keys: keys,
        message: message,
      ),
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

  testWidgets('what the level says reaches the player', (WidgetTester tester) async {
    // **The level has been saying things since the engine had signals and
    // nobody was listening.** "You need the blue key" went into a list this
    // game never drained, so a player who walked into a locked gate was told
    // nothing and had no way to learn a key existed.
    //
    // Mutation: drop the message from the HUD, or stop draining it in
    // `main.dart`. This is the last place it can be seen.
    await tester.pumpWidget(_hud(message: 'You need the blue key.'));

    expect(find.text('You need the blue key.'), findsOneWidget);
  });

  testWidgets('and it is not shown over a finished run',
      (WidgetTester tester) async {
    // The results panel is the whole screen's business at that point, and a
    // hint about a gate under it is a hint about a game that is over.
    await tester.pumpWidget(
      _hud(state: RunState.finished, message: 'You need the blue key.'),
    );

    expect(find.text('You need the blue key.'), findsNothing);
  });

  testWidgets('keys are named, not counted', (WidgetTester tester) async {
    // A door asks "have you got a blue one", never "how many". A count in the
    // HUD is the wrong answer to the question the player is about to be asked.
    //
    // Mutation: show `keys.length`. The colour disappears and the row becomes
    // a number nobody can act on.
    await tester.pumpWidget(_hud(keys: <String>{'blue', 'green'}));

    expect(find.text('blue green'), findsOneWidget);
    expect(find.text('keys'), findsOneWidget);

    await tester.pumpWidget(_hud(keys: <String>{'blue'}));
    expect(find.text('key'), findsOneWidget);
  });

  testWidgets('and an empty ring takes no room', (WidgetTester tester) async {
    await tester.pumpWidget(_hud());
    expect(find.text('key'), findsNothing);
    expect(find.text('keys'), findsNothing);
  });

  testWidgets('a run in progress has no results screen over it',
      (WidgetTester tester) async {
    await tester.pumpWidget(_hud(elapsed: 12.0));

    expect(find.text('Out of lives'), findsNothing);
    expect(find.text('First Steps'), findsNothing);
    expect(find.text('0:12'), findsOneWidget);
  });

  group('a player who has changed how they read', () {
    // Two failures that only appear for somebody who has turned their text up or
    // turned a screen reader on — which is to say, exactly the players nobody
    // tests as.

    testWidgets('hears what each tally is, not a list of numbers', (
      WidgetTester tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_hud(coins: 12, lives: 2));

      expect(find.bySemanticsLabel('coins 12'), findsOneWidget);
      expect(find.bySemanticsLabel('lives 2'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('and does not lose the clock off the edge', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_hud(
        coins: 12,
        deaths: 3,
        lives: 2,
        elapsed: 62.0,
        keys: const <String>{'gold'},
        textScale: 2.5,
      ));

      // **Asserted on where they are, not on whether they exist.** A `Row`
      // inside a `Positioned` with no right edge is given unbounded width, so it
      // never overflows and never complains — it simply lays the last tallies
      // out past the screen, where they are still in the tree and still
      // findable. A test that only looked for them passed with the bug in.
      const screen = 800.0;
      for (final tally in <String>['12', '3', '2', '1:02', 'gold']) {
        expect(tester.getRect(find.text(tally)).right, lessThanOrEqualTo(screen),
            reason: '"$tally" is off the right-hand edge');
      }
    });
  });
}
