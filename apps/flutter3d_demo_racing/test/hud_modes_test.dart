/// The HUD says a different thing in each of the three race modes.
///
///     flutter test test/hud_modes_test.dart
///
/// The shipped game stages `RaceMode.race` and offers no way to pick another,
/// so two of the three branches in `RaceHud` had never been built by anything:
/// a time trial has laps and no field to be a position within, and free roam
/// has neither. They are part of `flutter3d_game_racing`'s published surface,
/// which means the first person to select one is somebody else's player, and
/// the panel they get should not be the first time it was laid out.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_demo_racing/src/hud.dart';
import 'package:flutter3d_demo_racing/src/race_readout.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector2;

RaceReadout _readout(RaceMode mode) => RaceReadout(
  speed: 24.0,
  lap: 1,
  laps: 3,
  position: 2,
  racers: 4,
  lapTime: 41.5,
  bestLap: 40.25,
  record: 39.0,
  tyres: 'slicks',
  damage: 0.0,
  wrongWay: false,
  countdown: null,
  mode: mode,
  outline: <Vector2>[Vector2(0.0, 0.0), Vector2(10.0, 0.0), Vector2(0.0, 10.0)],
  carsOnMap: <Vector2>[Vector2(1.0, 1.0)],
);

Future<void> _pump(WidgetTester tester, RaceMode mode) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(body: RaceHud(readout: _readout(mode))),
  ),
);

void main() {
  group('raceNotice', () {
    test('says a car was put back on the road', () {
      // **`respawnedThisStep` was set by the simulation and read by nothing.**
      // Its own doc says it is there "for a sound or a caption" and there was
      // neither, so the most violent thing the simulation does to a driver —
      // picking the car up and setting it down elsewhere — arrived with no
      // sound, no flash and no line of text, and read as a glitch.
      //
      // Mutation: ignore `justRespawned` and this comes back null, which is
      // the silence.
      expect(
        raceNotice(betweenCircuits: null, justRespawned: true),
        'Back on the track',
      );
      expect(raceNotice(betweenCircuits: null), isNull);
    });

    test('and the end of the season says how to race it again', () {
      // **It used to say "Season complete" and stop.** The last race keeps
      // running underneath for ever — nothing calls `moveOn` after the final
      // circuit — and the key handler had no restart in it at all, so winning
      // the season ended the game whether the driver wanted it to or not.
      //
      // Mutation: ignore `touch` and a handset is told to press a key it does
      // not have, which is the one thing worse than being told nothing.
      expect(
        seasonCompleteNotice(touch: false),
        'Season complete — press R to race it again',
      );
      expect(seasonCompleteNotice(touch: true), contains('tap'));
      expect(seasonCompleteNotice(touch: true), isNot(contains('R')));
    });

    test('and the end of a race wins the line', () {
      // One line, two claims on it. A car put back on the road half a second
      // before the flag is not what the driver is waiting to be told.
      expect(
        raceNotice(betweenCircuits: 'Harbour next', justRespawned: true),
        'Harbour next',
      );
    });
  });

  testWidgets('a race counts laps and a position in the field', (
    WidgetTester tester,
  ) async {
    // Mutation: change `readout.mode == RaceMode.race` to `!= RaceMode.race`
    // in hud.dart and POS disappears from a race and appears in a time trial —
    // the first expectation here fails, and so does the one below it.
    await _pump(tester, RaceMode.race);
    expect(find.text('LAP'), findsOneWidget);
    expect(find.text('POS'), findsOneWidget);
    expect(find.text('TIME'), findsOneWidget);
    expect(find.text('RECORD'), findsOneWidget);
  });

  testWidgets('a time trial counts laps and has nobody to be second to', (
    WidgetTester tester,
  ) async {
    await _pump(tester, RaceMode.timeTrial);
    expect(find.text('LAP'), findsOneWidget);
    // One car on the circuit: a position out of one is a line that only ever
    // reads 1/1, which is the line saying nothing.
    expect(find.text('POS'), findsNothing);
    expect(find.text('BEST'), findsOneWidget);
  });

  testWidgets('free roam counts nothing and still drives', (
    WidgetTester tester,
  ) async {
    // Mutation: drop the `readout.mode != RaceMode.freeRoam` guard in hud.dart
    // and free roam grows a LAP counter out of three for a mode with no laps.
    await _pump(tester, RaceMode.freeRoam);
    expect(find.text('LAP'), findsNothing);
    expect(find.text('POS'), findsNothing);
    expect(find.text('TIME'), findsNothing);
    expect(find.text('RECORD'), findsNothing);
    // What is left is the car itself: tyres, the speedometer and the map.
    expect(find.text('TYRES'), findsOneWidget);
  });
}
