/// `ls-x-02`'s own visor widget, driven with no window and no `WidgetSurface`
/// — the same "moves with its anchor node" mechanism is already proven in
/// `flutter3d_bridge`'s own test; this proves the widget tree itself reads
/// [ValueListenable] rather than a value fixed at construction, which is
/// what lets a `WidgetSurface`'s own fixed `child` still show a changing
/// reading (`WidgetSurfacePipeline`'s own doc comment gives the reason it
/// has to be built this way at all).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter3d_demo_racing/src/hud.dart';
import 'package:flutter3d_demo_racing/src/race_readout.dart';
import 'package:flutter3d_demo_racing/src/stereo_hud_panel.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector2;

RaceReadout _readout({double speed = 24.0}) => RaceReadout(
  speed: speed,
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
  mode: RaceMode.race,
  outline: <Vector2>[Vector2(0.0, 0.0), Vector2(10.0, 0.0), Vector2(0.0, 10.0)],
  carsOnMap: <Vector2>[Vector2(1.0, 1.0)],
);

void main() {
  testWidgets('shows nothing before a race exists to read', (tester) async {
    final reading = ValueNotifier<RaceReadout?>(null);
    addTearDown(reading.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StereoHud(reading: reading, issueOf: () => null),
        ),
      ),
    );

    expect(find.byType(RaceHud), findsNothing);
  });

  testWidgets('draws the same RaceHud a flat screen would, once a readout '
      'arrives', (tester) async {
    final reading = ValueNotifier<RaceReadout?>(null);
    addTearDown(reading.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StereoHud(reading: reading, issueOf: () => null),
        ),
      ),
    );
    expect(find.byType(RaceHud), findsNothing);

    reading.value = _readout();
    await tester.pump();

    expect(find.byType(RaceHud), findsOneWidget);
  });

  testWidgets('redraws when the reading changes, the same widget tree both '
      'times', (tester) async {
    final reading = ValueNotifier<RaceReadout?>(_readout(speed: 10.0));
    addTearDown(reading.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StereoHud(reading: reading, issueOf: () => null),
        ),
      ),
    );
    final first = tester.widget<RaceHud>(find.byType(RaceHud));
    expect(first.readout.speed, 10.0);

    reading.value = _readout(speed: 30.0);
    await tester.pump();

    final second = tester.widget<RaceHud>(find.byType(RaceHud));
    expect(second.readout.speed, 30.0);
  });

  testWidgets('reads the issue message fresh from issueOf, not once', (
    tester,
  ) async {
    final reading = ValueNotifier<RaceReadout?>(_readout());
    String? issue;
    addTearDown(reading.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StereoHud(reading: reading, issueOf: () => issue),
        ),
      ),
    );
    expect(tester.widget<RaceHud>(find.byType(RaceHud)).issue, isNull);

    issue = 'the pad went quiet';
    reading.value = _readout(speed: 11.0);
    await tester.pump();

    expect(
      tester.widget<RaceHud>(find.byType(RaceHud)).issue,
      'the pad went quiet',
    );
  });
}
