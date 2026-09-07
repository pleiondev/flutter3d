/// What a player is told about the match they are playing.
///
///     flutter test test/hud_test.dart
///
/// **A HUD is the one part of a game with no simulation under it to be right on
/// its behalf**: a wrong number here is wrong on the screen and nowhere else.
/// The platformer's version of this file says the same thing, and it is worth
/// saying twice — every other test in this application can lean on the
/// simulation package being tested, and this one cannot lean on anything. So
/// these are widget tests rather than pixel ones, and what is asserted is the
/// text a player reads.
///
/// This screen was a single line of text until selection arrived, and the line
/// could not say the one thing only the screen knows: how many workers the
/// player has picked out. A click that gathered six and a click that gathered
/// none looked identical.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_demo_strategy/src/hud.dart';
import 'package:flutter3d_demo_strategy/src/hud_readout.dart';
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _hud({
  int side = 0,
  double stock = 0.0,
  List<double> delivered = const <double>[0.0, 0.0],
  double goal = 400.0,
  int selected = 0,
  Standing standing = const Standing.running(),
  String? under,
  double textScale = 1.0,
}) => MediaQuery(
  data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
  child: MaterialApp(
    home: Scaffold(
      body: StrategyHud(
        readout: StrategyReadout(
          side: side,
          stock: stock,
          deliveredBySide: delivered,
          goal: goal,
          selected: selected,
          standing: standing,
          under: under,
        ),
      ),
    ),
  ),
);

void main() {
  group('what the numbers say before anybody draws them', () {
    test('a quantity is rounded, because a sack is filled in fractions', () {
      // Mutation: print the double. A worker fills at eight a second, so the
      // tally would flicker through three decimals and could not be compared
      // to the one the player saw a moment ago.
      expect(amountText(0.0), '0');
      expect(amountText(137.4), '137');
      expect(amountText(137.6), '138');
    });

    test('progress is what has been brought home against the line', () {
      expect(progressText(137.0, 400.0), '137 / 400');
    });

    test('and a map with no line shows no line', () {
      // A map without a goal is playable — it ends when the ground runs out —
      // and its goal is infinity. Mutation: print it, and the corner of the
      // screen reads "137 / Infinity", which looks like a crash.
      expect(progressText(137.0, double.infinity), '137');
    });

    test('a match in play says so rather than naming a winner', () {
      expect(standingText(const Standing.running(), side: 0), 'in play');
    });

    test('and a finished one names the side that won, from your side', () {
      // Mutation: ignore `side`. Watching side one would say "you win" when
      // side nought won, which is the readout lying to the only person reading
      // it. How many sides a match has is read out of the document, so the
      // other ones are numbered rather than called "the bot".
      expect(standingText(const Standing.wonBy(0), side: 0), 'you win');
      expect(standingText(const Standing.wonBy(1), side: 0), 'side 1 wins');
      expect(standingText(const Standing.wonBy(1), side: 1), 'you win');
      expect(standingText(const Standing.drawn(), side: 0), 'drawn');
    });

    test('every side is tallied, and yours is called yours', () {
      final tallies = tallyBySide(
        const StrategyReadout(
          side: 1,
          stock: 0.0,
          deliveredBySide: <double>[10.0, 20.0, 30.0],
          goal: 400.0,
          selected: 0,
          standing: Standing.running(),
        ),
      );

      expect(tallies.map((it) => it.label), <String>['side 0', 'you', 'side 2']);
      expect(tallies.map((it) => it.amount), <String>['10', '20', '30']);
    });
  });

  testWidgets('the squad the player gathered is counted on the screen', (
    WidgetTester tester,
  ) async {
    // **The one number on this screen that no simulation knows.** Nothing in
    // the match can be asked how many workers somebody has a rectangle round,
    // so if this row is wrong nothing else is in a position to disagree.
    await tester.pumpWidget(_hud(selected: 6));

    expect(find.text('selected'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);

    await tester.pumpWidget(_hud());
    expect(find.text('0'), findsWidgets);
  });

  testWidgets('the purse and the total are not the same number', (
    WidgetTester tester,
  ) async {
    // Mutation: show the stockpile under both labels. A player who had just
    // spent forty on a worker would be told they were losing, because the purse
    // is what is *left* and only the total settles the match.
    await tester.pumpWidget(
      _hud(stock: 15.0, delivered: <double>[137.0, 90.0]),
    );

    expect(find.text('stock'), findsOneWidget);
    expect(find.text('15'), findsOneWidget);
    expect(find.text('delivered'), findsOneWidget);
    expect(find.text('137 / 400'), findsOneWidget);
  });

  testWidgets('the other side is on the screen too, by number', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_hud(delivered: <double>[137.0, 90.0]));

    expect(find.text('side 1'), findsOneWidget);
    expect(find.text('90'), findsOneWidget);
    // Your own total is the `delivered` row against the line; a second one
    // labelled "you" beside it would be the same number twice.
    expect(find.text('you'), findsNothing);
  });

  testWidgets('what the cursor is over is named, and only when there is one', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_hud(under: 'their worker'));
    expect(find.text('under'), findsOneWidget);
    expect(find.text('their worker'), findsOneWidget);

    // Mutation: show the row with an empty value. A label with nothing under it
    // sits in the row for the whole match, taking the width of a tally to say
    // that the pointer is over grass.
    await tester.pumpWidget(_hud());
    expect(find.text('under'), findsNothing);
  });

  testWidgets('a finished match says so across the middle', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_hud(standing: const Standing.wonBy(1)));
    expect(find.text('side 1 wins'), findsOneWidget);

    // Mutation: draw the banner whether or not the match is over. "in play"
    // across the middle of every frame is a banner a player stops seeing, and
    // this one has to be noticed the once.
    await tester.pumpWidget(_hud());
    expect(find.text('in play'), findsNothing);
  });

  testWidgets('the controls are written where a player can find them', (
    WidgetTester tester,
  ) async {
    // **The primary drag stopped moving the view when it started selecting**,
    // so a player who knew this demo yesterday would find the map nailed down
    // with nothing to explain it.
    await tester.pumpWidget(_hud());

    expect(find.textContaining('drag to select'), findsOneWidget);
    expect(find.textContaining('right-drag'), findsOneWidget);
  });

  group('a player who has changed how they read', () {
    testWidgets('hears what each tally is, not a row of numbers', (
      WidgetTester tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _hud(stock: 15.0, selected: 6, delivered: <double>[137.0, 90.0]),
      );

      expect(find.bySemanticsLabel('stock 15'), findsOneWidget);
      expect(find.bySemanticsLabel('selected 6'), findsOneWidget);
      expect(find.bySemanticsLabel('delivered 137 / 400'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('and does not lose a tally off the right-hand edge', (
      WidgetTester tester,
    ) async {
      // **Asserted on where they are, not on whether they exist.** A `Row`
      // inside a `Positioned` with no right edge is given unbounded width, so
      // it never overflows and never complains — it lays the last tallies out
      // past the screen, where they are still in the tree and still findable. A
      // test that only looked for them would pass with the bug in.
      await tester.pumpWidget(
        _hud(
          stock: 15.0,
          selected: 6,
          delivered: <double>[137.0, 90.0],
          under: 'their worker',
          textScale: 2.5,
        ),
      );

      const double screen = 800.0;
      for (final String tally in <String>[
        '15',
        '137 / 400',
        '6',
        '90',
        'their worker',
      ]) {
        expect(
          tester.getRect(find.text(tally)).right,
          lessThanOrEqualTo(screen),
          reason: '"$tally" is off the right-hand edge',
        );
      }
    });
  });
}
