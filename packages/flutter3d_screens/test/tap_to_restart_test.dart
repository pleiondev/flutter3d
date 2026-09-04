/// A finished run can be started again by a player holding a phone.
///
///     flutter test test/tap_to_restart_test.dart
///
/// The crypt and the platformer each had two ways back into a finished run,
/// the R key and a gamepad's Start, and a touch build has neither: its
/// on-screen layer carries the verbs the level needs, and a level that is over
/// has none of them. This is the third way, and the two things it has to get
/// right are that the whole screen is the target and that the tap does not
/// also reach the drag-look layer underneath, which would turn the camera of a
/// body that is dead.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_screens/flutter3d_screens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a tap anywhere restarts', (WidgetTester tester) async {
    // Mutation: drop `Positioned.fill` for a bottom-aligned box and a tap in
    // the middle of the screen — where a thumb lands after a death — reaches
    // nothing.
    var restarts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: <Widget>[TapToRestart(onRestart: () => restarts++)],
        ),
      ),
    );

    await tester.tapAt(const Offset(100.0, 120.0));
    expect(restarts, 1);
    await tester.tapAt(tester.getCenter(find.byType(TapToRestart)));
    expect(restarts, 2);
  });

  testWidgets('and nothing below it hears the tap', (
    WidgetTester tester,
  ) async {
    // Mutation: set `behavior` to `deferToChild` and the layer stops covering
    // the screen it is over, so the drag-look listener under it takes the
    // press as the beginning of a look.
    var below = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: <Widget>[
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) => below++,
              ),
            ),
            TapToRestart(onRestart: () {}),
          ],
        ),
      ),
    );

    await tester.tapAt(const Offset(200.0, 200.0));
    expect(below, 0);
  });

  testWidgets('and says what the tap is for', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: <Widget>[
            TapToRestart(onRestart: () {}, label: 'Tap to climb it again'),
          ],
        ),
      ),
    );

    expect(find.text('Tap to climb it again'), findsOneWidget);
  });
}
