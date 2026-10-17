/// A throttle or a brake held down with a thumb, for a player with no
/// keyboard.
///
///     flutter test test/pedal_test.dart
///
/// Moved here from the racing demo with the pedal itself.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_game_ui/touch.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

const GameAction _throttle = GameAction('throttle');

void main() {
  testWidgets('and a pedal held is the throttle held', (
    WidgetTester tester,
  ) async {
    // Mutation: `press` on the way up as well as down — the second
    // expectation fails.
    final input = InputState();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: TouchButton.pedal(
            state: input,
            action: _throttle,
            label: 'throttle',
          ),
        ),
      ),
    );

    final gesture = await tester.press(find.byType(TouchButton));
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
    //
    // Mutation: drop `onPointerCancel` — this fails.
    final input = InputState();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: TouchButton.pedal(
            state: input,
            action: _throttle,
            label: 'throttle',
          ),
        ),
      ),
    );

    final where = tester.getCenter(find.byType(TouchButton));
    final gesture = await tester.startGesture(where);
    await tester.pump();
    expect(input.value(_throttle), 1.0);

    await gesture.cancel();
    await tester.pump();

    expect(input.value(_throttle), 0.0);
  });

  testWidgets('and a pedal taken off the screen mid-press lets go', (
    WidgetTester tester,
  ) async {
    // A settings panel hiding the controls is a normal path, and no pointer-up
    // ever reaches a widget that is gone. The input outlives the pedal.
    //
    // Mutation: drop the release from `dispose` — this fails.
    final input = InputState();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: TouchButton.pedal(
            state: input,
            action: _throttle,
            label: 'throttle',
          ),
        ),
      ),
    );
    await tester.startGesture(tester.getCenter(find.byType(TouchButton)));
    await tester.pump();
    expect(input.value(_throttle), 1.0);

    await tester.pumpWidget(const SizedBox());
    expect(input.value(_throttle), 0.0, reason: 'the throttle stayed down');
  });

  testWidgets('and says what it is to a screen reader', (
    WidgetTester tester,
  ) async {
    // Mutation: drop the `Semantics` wrapper — this fails.
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: TouchButton.pedal(
            state: InputState(),
            action: _throttle,
            label: 'brake',
          ),
        ),
      ),
    );
    final node = tester.getSemantics(find.byType(TouchButton));
    expect(node, isSemantics(isButton: true));
    expect(node.label, contains('brake'));
    semantics.dispose();
  });
}
