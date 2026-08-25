/// The one thing a driver can change about the car without leaving it.
///
///     flutter test test/tyres_test.dart
///
/// The three sets and what they are worth are the racing package's, and have
/// their own file of measurements. What is here is the half a package cannot
/// hold: that this game offers the choice at all, says which set is on, and
/// says so when it refuses.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter3d_demo_racing/src/hud.dart';
import 'package:flutter3d_demo_racing/src/race_readout.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector2;

RaceReadout _readout({
  String tyres = 'road',
  bool refused = false,
  double damage = 0.0,
}) =>
    RaceReadout(
      speed: 20.0,
      lap: 0,
      laps: 3,
      position: 1,
      racers: 4,
      lapTime: 12.5,
      bestLap: null,
      record: null,
      tyres: tyres,
      tyresRefused: refused,
      damage: damage,
      wrongWay: false,
      countdown: null,
      mode: RaceMode.race,
      outline: <Vector2>[Vector2.zero(), Vector2(1.0, 1.0)],
      carsOnMap: <Vector2>[Vector2.zero()],
    );

Future<void> _show(WidgetTester tester, RaceReadout readout) => tester.pumpWidget(
      MaterialApp(home: Scaffold(body: RaceHud(readout: readout))),
    );

void main() {
  testWidgets('the screen says which tyres are on', (WidgetTester tester) async {
    await _show(tester, _readout(tyres: 'slicks'));

    expect(find.text('SLICKS'), findsOneWidget);
  });

  testWidgets('and says why it refused', (WidgetTester tester) async {
    // **Said rather than ignored.** A key that does nothing and says nothing is
    // a key a player decides is broken, and the rule it is enforcing — stop
    // first — is one they cannot guess from silence.
    await _show(tester, _readout(tyres: 'road', refused: true));

    expect(find.text('STOP FIRST'), findsOneWidget);
    expect(find.text('ROAD'), findsNothing);
  });

  testWidgets('and says nothing about damage until there is some',
      (WidgetTester tester) async {
    // A line reading NONE every lap of every clean race is a line a driver
    // stops seeing, and this one has to be noticed the once.
    await _show(tester, _readout());
    expect(find.text('DAMAGE'), findsNothing);

    await _show(tester, _readout(damage: 0.24));
    expect(find.text('DAMAGE'), findsOneWidget);
    expect(find.text('24%'), findsOneWidget);
  });

  test('and the game is the thing that offers the choice', () {
    // The same scan the ghost needs, for the same reason: the call sits in a
    // private method of a widget no test can mount, and a suite full of green
    // ticks would say nothing about a game that quietly stopped asking.
    //
    // The action itself is declared in `controls.dart` now, alongside every
    // other verb this game has — `main.dart` only reads it back.
    final game = File('lib/main.dart').readAsStringSync();
    final controls = File('lib/src/controls.dart').readAsStringSync();

    expect(game, contains('pitStop('),
        reason: 'three sets of tyres, and no way to put any of them on');
    expect(game, contains('.damage'),
        reason: 'cars get broken and the screen never says so');
    expect(controls, contains("GameAction('tyres')"),
        reason: 'the verb is not in the table, so it cannot be rebound');
    expect(game, contains('Drive.tyres'),
        reason: 'the action exists and nothing is bound to it');
  });
}
