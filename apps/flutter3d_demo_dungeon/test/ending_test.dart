/// How the crypt ends, and what it counts on the way.
///
///     flutter test test/ending_test.dart
///
/// **It ended with three seconds of text.** Walking out of the sanctum put
/// `You are out.` over the corridor, it faded, and the player was left standing
/// in a finished level with the crosshair up: nothing said the game was over,
/// nothing said what the crawl had cost, nobody was credited, and the only way
/// back to the start was a key nothing on screen mentioned.
///
/// Two halves here, because there are two ways to get this wrong. The screen is
/// one — the wrong words, or the credits missing. The arithmetic behind it is
/// the other, and it is the half that had never existed: what a shooter is
/// played for is what you killed and how long it took, and both were counted
/// per level and thrown away at every door.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_demo_dungeon/src/credits.dart';
import 'package:flutter3d_demo_dungeon/src/ending.dart';
import 'package:flutter3d_demo_dungeon/src/run_cubit.dart' show Crawl;
import 'package:flutter_test/flutter_test.dart';

Widget _ending({bool touch = false}) => MaterialApp(
  home: CryptEnding(kills: 47, seconds: 754.0, levels: 5, touch: touch),
);

void main() {
  group('what the crawl came to', () {
    test('is what was killed, how long it took, and how far it got', () {
      // Mutation: drop `kills += killed` from `Crawl.step` and the second
      // expectation fails; drop `seconds += dt` and the first does.
      final crawl = Crawl()
        ..step(0.5, killed: 2)
        ..step(0.5, killed: 0)
        ..step(0.5, killed: 1);
      crawl.levels = 3;

      expect(crawl.seconds, closeTo(1.5, 1e-9));
      expect(crawl.kills, 3);
      expect(crawl.levels, 3);
    });

    test('and a run started again starts the count again', () {
      // **The kill count used to be a field of the widget that nothing reset**,
      // so it counted every monster killed since the application launched — the
      // second crawl of an evening reported the first one's total. `startFresh`
      // is what calls this, on the same line that rebuilds the inventory.
      //
      // Mutation: delete the body of `Crawl.reset` — all three fail.
      final crawl = Crawl()..step(1.0, killed: 9);
      crawl.levels = 4;
      crawl.reset();

      expect(crawl.kills, 0);
      expect(crawl.seconds, 0.0);
      expect(crawl.levels, 0);
    });
  });

  group('the screen at the end', () {
    testWidgets('says the crypt is behind you, and what it cost', (
      WidgetTester tester,
    ) async {
      // Mutation: swap `clockText(seconds, ...)` for `'$seconds'` in
      // `CryptEnding` — the time reads `754.0` and the first expectation fails.
      await tester.pumpWidget(_ending());

      expect(find.textContaining('out of the crypt'), findsOneWidget);
      expect(find.text('12:34'), findsOneWidget);
      expect(find.text('47'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('levels'), findsOneWidget);
    });

    testWidgets('and names everybody it has to', (WidgetTester tester) async {
      // The credits are on the ending because that is where a game discharges
      // them, and this game's list is CC0 rather than CC BY — so the check is
      // "everyone in the list is named", not "the attribution clause is met".
      // `credits_test.dart` is what reads the asset directory.
      //
      // Mutation: delete the `CreditsSection` from `CryptEnding` — this fails.
      await tester.pumpWidget(_ending());

      for (final credit in Credits.models) {
        expect(find.textContaining(credit.author!), findsWidgets);
      }
    });

    testWidgets('and asks for something the build can actually do', (
      WidgetTester tester,
    ) async {
      // A handset has no R. This screen told every player to press one, which
      // is the same mistake the platformer's results panel made and the reason
      // `crawlAgain` is a function rather than a ternary in a build method.
      //
      // Mutation: ignore `touch` in `crawlAgain` and always return the R line —
      // the second half of this fails.
      expect(crawlAgain(touch: false), contains('R'));
      expect(crawlAgain(touch: true), isNot(contains('Press')));

      await tester.pumpWidget(_ending());
      expect(find.text(crawlAgain(touch: false)), findsOneWidget);

      await tester.pumpWidget(_ending(touch: true));
      expect(find.text(crawlAgain(touch: true)), findsOneWidget);
    });

    testWidgets('and counts one level as a level rather than levels', (
      WidgetTester tester,
    ) async {
      // A crawl resumed from disk starts its count at the level it resumed
      // into — see `Crawl.levels` — so `1` is a number this screen really does
      // show, and `1 levels` is the sort of thing nobody notices until it is
      // on a screenshot.
      //
      // Mutation: hard-code the label to `'levels'` — this fails.
      await tester.pumpWidget(
        const MaterialApp(
          home: CryptEnding(kills: 3, seconds: 61.0, levels: 1),
        ),
      );

      expect(find.text('level'), findsOneWidget);
      expect(find.text('levels'), findsNothing);
    });
  });
}
