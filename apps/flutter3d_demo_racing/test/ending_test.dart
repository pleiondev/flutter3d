/// How the season opens and how it ends.
///
///     flutter test test/ending_test.dart
///
/// **It did neither.** The application opened straight onto a grid with the
/// lights already counting, and the only place it named the person whose car it
/// ships was inside the settings panel — behind a gear, past the volume
/// sliders — while the licence on that car asks for attribution wherever the
/// work appears. And winning the fifth circuit put one line of text across a
/// race that went on driving underneath it for ever: no laps, no best lap, no
/// list of what had been won, and no credits.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_demo_racing/src/circuits.dart';
import 'package:flutter3d_demo_racing/src/credits.dart';
import 'package:flutter3d_demo_racing/src/ending.dart';
import 'package:flutter3d_demo_racing/src/race_cubit.dart';
import 'package:flutter3d_demo_racing/src/race_readout.dart';
import 'package:flutter3d_demo_racing/src/title_card.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _ending({bool touch = false}) => MaterialApp(
  home: SeasonEnding(circuits: 5, laps: 15, bestLap: 83.456, touch: touch),
);

void main() {
  group('the title card', () {
    testWidgets('names the game, the controls and the author of the car', (
      WidgetTester tester,
    ) async {
      // **The acceptance the licence writes for us.** The car is CC BY 4.0,
      // whose text makes naming the author a condition, and until now the only
      // screen that did was one most players never open. `Credits.owed` is the
      // subset the clause applies to, and this asks for the author and the
      // licence URL by name.
      //
      // Mutation: delete the `CreditsSection` from `TitleCard` — this fails,
      // and the game goes back into breach.
      await tester.pumpWidget(
        const MaterialApp(home: TitleCard(prompt: 'Press any key.')),
      );

      expect(find.text('Ring'), findsOneWidget);
      expect(find.textContaining('throttle'), findsWidgets);
      for (final credit in Credits.owed) {
        expect(find.textContaining(credit.author!), findsWidgets);
        expect(find.text(credit.licenceUrl!), findsWidgets);
      }
      expect(find.text('Press any key.'), findsOneWidget);
    });

    testWidgets('and describes the controls this build actually has', (
      WidgetTester tester,
    ) async {
      // The platformer's card said "click to dash" in a browser for months,
      // because a `const` list of keys written beside the keys drifts the first
      // time either changes. A handset has no keys at all, so the touch build's
      // lines describe the band and the pedals — and the pit button, which is
      // the control this game's own HUD tells a driver to press.
      //
      // Mutation: return the keyboard list from `TitleCard._controls`
      // regardless of `touch` — both halves of this fail.
      await tester.pumpWidget(
        const MaterialApp(home: TitleCard(prompt: 'Touch.', touch: true)),
      );

      expect(find.textContaining('W and S'), findsNothing);
      expect(find.textContaining('pedals'), findsOneWidget);
      expect(find.textContaining('Pit stops'), findsOneWidget);
    });
  });

  group('what a season came to', () {
    test('adds up the circuits and the laps, and keeps the quickest', () {
      // Mutation: drop the `<` comparison in `SeasonTally.won` and always take
      // the newer lap — the season's best becomes the slow last circuit's and
      // the third expectation fails.
      final season = SeasonTally()
        ..won(laps: 3, bestLap: 91.0)
        ..won(laps: 3, bestLap: 84.5)
        ..won(laps: 5, bestLap: 120.0);

      expect(season.circuits, 3);
      expect(season.laps, 11);
      expect(season.bestLap, closeTo(84.5, 1e-9));
    });

    test('and a circuit nobody drove a clean lap of still counts', () {
      // A null best lap is a real race: crash out on the first lap of five and
      // the flag still falls. Counting the circuit and ignoring the missing
      // time is the only answer that is true of both.
      //
      // Mutation: make `SeasonTally.won` return early on a null `bestLap` —
      // the first two expectations fail.
      final season = SeasonTally()
        ..won(laps: 3, bestLap: 90.0)
        ..won(laps: 3);

      expect(season.circuits, 2);
      expect(season.laps, 6);
      expect(season.bestLap, closeTo(90.0, 1e-9));
    });

    test('and racing the season again is a season, not a longer one', () {
      // `startOver` is what R and the tap layer reach. Without the reset the
      // second run of an evening reports ten circuits and thirty laps.
      //
      // Mutation: drop `season.reset()` from `RaceProgress.startOver` — both
      // expectations fail.
      final progress = RaceProgress()..finish(laps: 3, bestLap: 90.0);
      progress.startOver();

      expect(progress.season.circuits, 0);
      expect(progress.season.bestLap, isNull);
    });

    test('and the fifth circuit is the one that ends it', () {
      // What the ending is gated on, checked against the season rather than
      // assumed: `finish` returns null only for the last circuit, and the
      // screen reads that as "the season is over".
      //
      // Mutation: make `Season.after` return the first circuit rather than null
      // at the end — the last expectation fails and the game never ends.
      final progress = RaceProgress();
      final reached = <String>[];
      for (var i = 0; i < Season.circuits.length; i++) {
        reached.add(progress.current.name);
        final next = progress.finish(laps: 3);
        if (next != null) progress.moveOn(next);
      }

      expect(reached, Season.circuits.map((Circuit c) => c.name).toList());
      expect(progress.season.circuits, Season.circuits.length);
      expect(progress.finish(), isNull);
    });
  });

  group('the screen at the end', () {
    testWidgets('says the season is won, and what the driving came to', (
      WidgetTester tester,
    ) async {
      // Mutation: swap `formatLapTime(bestLap!)` for `'$bestLap'` in
      // `SeasonEnding` — the lap reads `83.456` and this fails.
      await tester.pumpWidget(_ending());

      expect(find.textContaining('season is yours'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('15'), findsOneWidget);
      expect(find.text(formatLapTime(83.456)), findsOneWidget);
    });

    testWidgets('and names the author the licence asks for', (
      WidgetTester tester,
    ) async {
      // The other screen the CC BY clause reaches. A player who never opens the
      // settings and never sits through the title card still finishes the game.
      //
      // Mutation: delete the `CreditsSection` from `SeasonEnding` — this fails.
      await tester.pumpWidget(_ending());

      for (final credit in Credits.owed) {
        expect(find.textContaining(credit.author!), findsWidgets);
      }
    });

    testWidgets('and asks for something the build can actually do', (
      WidgetTester tester,
    ) async {
      // A handset has no R. `seasonCompleteNotice` is where the wording and the
      // control it names are decided together, and the screen reads it rather
      // than writing its own copy of the sentence.
      //
      // Mutation: hard-code `touch: false` where `SeasonEnding` calls
      // `seasonCompleteNotice` — the second half fails.
      await tester.pumpWidget(_ending());
      expect(find.text(seasonCompleteNotice(touch: false)), findsOneWidget);

      await tester.pumpWidget(_ending(touch: true));
      expect(find.text(seasonCompleteNotice(touch: true)), findsOneWidget);
    });

    testWidgets('and reads as nothing rather than as a zero with no lap', (
      WidgetTester tester,
    ) async {
      // The same `--:--.---` the HUD's own best-lap line shows before there is
      // one. A season with no clean lap in it is a season somebody had a very
      // bad evening in, and `0:00.000` would read as a world record.
      //
      // **The first attempt at this could not fail**, and that is worth
      // recording: the mutation tried was `formatLapTime(bestLap ?? 0.0)`, and
      // `clockText` answers a nought with the dashes too — so the ternary the
      // widget used to carry was dead code and the check was testing nothing.
      // The ternary is gone and the null goes through.
      //
      // Mutation: add `none: '0:00.000'` to `formatLapTime` — this fails.
      await tester.pumpWidget(
        const MaterialApp(
          home: SeasonEnding(circuits: 5, laps: 15, bestLap: null),
        ),
      );

      expect(find.text('--:--.---'), findsOneWidget);
    });
  });
}
