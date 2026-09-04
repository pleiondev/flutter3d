/// The climb under two thumbs.
///
///     flutter test test/touch_runner_test.dart
///
/// **A phone could jump, dash and drop through, and could not run.** Sprint is
/// bound to shift and to a shoulder button, and the touch build had neither —
/// so the run speed the longer gaps in this game are tuned for was reachable
/// on a desktop and on a pad and nowhere else.
///
/// It is a switch rather than a fourth circle, and the reason is the other
/// thumb: it is on the stick, and a sprint that has to be held costs the
/// steering for the length of the climb. That is the barrier the
/// `a11y.toggleSprint` setting exists for, arriving from the hardware.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_demo_platformer/src/touch_runner.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _runner(InputState input) => Directionality(
  textDirection: TextDirection.ltr,
  child: SizedBox(
    width: 900,
    height: 500,
    child: TouchRunner(
      state: input,
      onSprint: () => input.toggle(GameAction.sprint),
    ),
  ),
);

void main() {
  testWidgets('every verb the climb has can be reached with a thumb', (
    WidgetTester tester,
  ) async {
    // Mutation: drop any one of the three `TouchAction`s from `TouchRunner` —
    // its line here fails. Drop the `TouchToggle` and sprint does.
    final input = InputState();
    await tester.pumpWidget(_runner(input));

    final walking = await tester.startGesture(
      tester.getCenter(find.byType(TouchStick)),
      pointer: 1,
    );
    await walking.moveBy(const Offset(0, -64));
    await tester.pump();
    expect(input.moveAxis.y, closeTo(1.0, 1e-6), reason: 'no way to walk');

    const cluster = <(String, GameAction)>[
      ('jump', GameAction.jump),
      ('dash', PlatformerActions.dash),
      ('drop', PlatformerActions.dropThrough),
    ];
    for (var i = 0; i < cluster.length; i++) {
      final (label, action) = cluster[i];
      await tester.startGesture(
        tester.getCenter(find.widgetWithText(TouchButton, label)),
        pointer: 2 + i,
      );
      await tester.pump();
      expect(input.held(action), isTrue, reason: 'no way to $label');
    }

    await tester.tap(find.byType(TouchToggle), pointer: 9);
    expect(input.held(GameAction.sprint), isTrue, reason: 'no way to sprint');
  });

  testWidgets('and the sprint stays on once the finger has gone', (
    WidgetTester tester,
  ) async {
    // The difference between this control and the three beside it, and the
    // whole reason it is not one of them: a `TouchButton` would let go of the
    // sprint the moment the thumb went back to the stick.
    //
    // Mutation: replace the toggle in `TouchRunner` with a fourth
    // `TouchAction(GameAction.sprint, 'sprint')` — the second expectation
    // fails, because the release comes with the tap.
    final input = InputState();
    await tester.pumpWidget(_runner(input));

    await tester.tap(find.byType(TouchToggle));
    await tester.pumpWidget(_runner(input));
    expect(input.held(GameAction.sprint), isTrue);

    // Nothing is touching it now, and it is still on.
    await tester.pump(const Duration(seconds: 1));
    expect(input.held(GameAction.sprint), isTrue);

    await tester.tap(find.byType(TouchToggle));
    expect(input.held(GameAction.sprint), isFalse);
  });
}
