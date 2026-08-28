/// A throttle or a brake held down with a thumb, for a player with no
/// keyboard.
///
///     flutter test test/pedal_test.dart
///
/// Split out of `touch_drive_test.dart` alongside `pedal.dart` itself.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_demo_racing/src/pedal.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';

const GameAction _throttle = GameAction('throttle');

void main() {
  testWidgets('and a pedal held is the throttle held', (
    WidgetTester tester,
  ) async {
    final input = InputState();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: Pedal(state: input, action: _throttle, label: 'throttle'),
        ),
      ),
    );

    final gesture = await tester.press(find.byType(Pedal));
    await tester.pump();
    expect(input.value(_throttle), 1.0);

    await gesture.up();
    await tester.pump();
    expect(input.value(_throttle), 0.0);
  });

  testWidgets('and a finger the system takes away lets go', (
    WidgetTester tester,
  ) async {
    // A notification pulled down mid-corner. The pointer never comes up, and a
    // control that only listens for an up leaves the car at full throttle for
    // as long as the player is looking at something else.
    final input = InputState();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: Pedal(state: input, action: _throttle, label: 'throttle'),
        ),
      ),
    );

    final where = tester.getCenter(find.byType(Pedal));
    final gesture = await tester.startGesture(where);
    await tester.pump();
    expect(input.value(_throttle), 1.0);

    await gesture.cancel();
    await tester.pump();

    expect(input.value(_throttle), 0.0);
  });
}
