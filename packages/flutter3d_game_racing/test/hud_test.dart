/// The two readouts, and what every racing game gets wrong writing them.
///
///     flutter test test/hud_test.dart
///
/// Claims about numbers rather than about pictures. `RacerProgress.lap` counts
/// laps *completed*, so the first lap of a race reads nought and the last one,
/// once crossed, reads one more than the race has — and both were drawn to the
/// screen by every game that reached for the field.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ring_track.dart';

RaceState _race({
  int racers = 1,
  int laps = 3,
  RaceMode mode = RaceMode.race,
}) => RaceState(
  mode: mode,
  track: ringTrack(),
  racers: racers,
  laps: laps,
  countdownSeconds: 3.0,
);

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  Directionality(textDirection: TextDirection.ltr, child: child),
);

void main() {
  group('the lap readout', () {
    testWidgets('counts from one, not from nought', (WidgetTester t) async {
      final race = _race();
      await _pump(t, LapReadout(racer: race.progress[0], race: race));

      expect(find.text('1'), findsOneWidget);
      expect(find.text(' / 3'), findsOneWidget);
    });

    testWidgets('and stops at the last rather than going one past it', (
      WidgetTester t,
    ) async {
      // Crossing the line on the final lap leaves `lap` at the lap count, and
      // the naive `lap + 1` reads "4 / 3" on the run to the flag.
      final race = _race();
      race.progress[0].lap = 3;
      await _pump(t, LapReadout(racer: race.progress[0], race: race));

      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('and draws nothing where no lap is counted', (
      WidgetTester t,
    ) async {
      final race = _race(mode: RaceMode.freeRoam);
      await _pump(t, LapReadout(racer: race.progress[0], race: race));

      expect(find.byType(Text), findsNothing);
    });
  });

  group('the position readout', () {
    testWidgets('says the place and how many are in it', (
      WidgetTester t,
    ) async {
      final race = _race(racers: 3)..phase = RacePhase.running;
      await _pump(t, PositionReadout(racer: race.progress[0], race: race));

      expect(find.text('1'), findsOneWidget);
      expect(find.text('st'), findsOneWidget);
      expect(find.text(' / 3'), findsOneWidget);
    });

    testWidgets('and draws nothing with nobody to be ahead of', (
      WidgetTester t,
    ) async {
      final race = _race()..phase = RacePhase.running;
      await _pump(t, PositionReadout(racer: race.progress[0], race: race));

      expect(find.byType(Text), findsNothing);
    });

    testWidgets('and nothing on the grid, where nobody has a place yet', (
      WidgetTester t,
    ) async {
      final race = _race(racers: 3);
      expect(race.phase, RacePhase.countdown);

      await _pump(t, PositionReadout(racer: race.progress[0], race: race));

      expect(find.byType(Text), findsNothing);
    });
  });
}
