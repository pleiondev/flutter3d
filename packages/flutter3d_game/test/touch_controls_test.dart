/// The controls a game grows when there is no keyboard.
///
///     flutter test test/touch_controls_test.dart
///
/// `InputState`'s own doc has promised since before either other device existed
/// that "the touch build and the desktop build run the same game code", and
/// `setStickAxis` has said "for a stick or a d-pad" for just as long. Nothing
/// collected on that until now, so this is the file that checks the promise was
/// worth making — a finger produces the same movement axis a thumb stick does,
/// and the simulation is not told which it was.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';

const GameAction _dash = GameAction('dash');

Widget _wrap(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: Align(alignment: Alignment.topLeft, child: child),
    );

void main() {
  group('a thumb stick', () {
    testWidgets('pushed forward walks forward', (WidgetTester tester) async {
      // Screen coordinates grow downwards and forward is positive, so a finger
      // moved *up* has to come out positive. Getting this backwards is the
      // oldest bug in the file and invisible without a device.
      final input = InputState();
      await tester.pumpWidget(_wrap(TouchStick(state: input, radius: 50)));

      final centre = tester.getCenter(find.byType(TouchStick));
      final gesture = await tester.startGesture(centre);
      await gesture.moveBy(const Offset(0, -50));
      await tester.pump();

      expect(input.moveAxis.y, closeTo(1.0, 1e-6));
      expect(input.moveAxis.x, closeTo(0.0, 1e-6));
    });

    testWidgets('and half over asks for half', (WidgetTester tester) async {
      final input = InputState();
      await tester.pumpWidget(_wrap(TouchStick(state: input, radius: 50)));

      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(TouchStick)));
      await gesture.moveBy(const Offset(25, 0));
      await tester.pump();

      expect(input.moveAxis.x, closeTo(0.5, 1e-6));
    });

    testWidgets('and a finger dragged off the edge still asks for one', (
      WidgetTester tester,
    ) async {
      // **Not a test of this widget's clamp**, and finding that out was worth
      // the mutation that found it: deleting the clamp inside `TouchStick`
      // changes nothing here, because `InputState` bounds the movement axis
      // itself. What this checks is that the two agree — a stick reporting 1.6
      // must not become a player moving at 1.6. The widget's own clamp is about
      // where the knob is drawn, which no test here can see.
      final input = InputState();
      await tester.pumpWidget(_wrap(TouchStick(state: input, radius: 50)));

      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(TouchStick)));
      await gesture.moveBy(const Offset(80, -80));
      await tester.pump();

      expect(input.moveAxis.length, closeTo(1.0, 1e-6));
    });

    testWidgets('and letting go stops dead', (WidgetTester tester) async {
      final input = InputState();
      await tester.pumpWidget(_wrap(TouchStick(state: input, radius: 50)));

      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(TouchStick)));
      await gesture.moveBy(const Offset(0, -50));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(input.moveAxis.y, 0.0);
    });

    testWidgets('and a pointer the system takes away is a release', (
      WidgetTester tester,
    ) async {
      // A notification shade pulled down mid-run cancels the pointer rather than
      // lifting it. Without this the player comes back walking into a wall.
      final input = InputState();
      await tester.pumpWidget(_wrap(TouchStick(state: input, radius: 50)));

      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(TouchStick)));
      await gesture.moveBy(const Offset(0, -50));
      await tester.pump();
      await gesture.cancel();
      await tester.pump();

      expect(input.moveAxis.y, 0.0);
    });

    testWidgets('and a second finger elsewhere does not move it', (
      WidgetTester tester,
    ) async {
      // **The whole of multi-touch, and it is not optional.** A player walking
      // and jumping holds two fingers down; a stick that took the newest pointer
      // would snap to wherever the other thumb landed.
      final input = InputState();
      await tester.pumpWidget(_wrap(TouchStick(state: input, radius: 50)));

      final centre = tester.getCenter(find.byType(TouchStick));
      final walking = await tester.startGesture(centre, pointer: 1);
      await walking.moveBy(const Offset(0, -50));
      await tester.pump();

      final other = await tester.startGesture(centre, pointer: 2);
      await other.moveBy(const Offset(50, 0));
      await tester.pump();

      expect(input.moveAxis.y, closeTo(1.0, 1e-6),
          reason: 'the second finger stole the stick');
    });
  });

  group('a button', () {
    testWidgets('holds its action down while a finger is on it', (
      WidgetTester tester,
    ) async {
      final input = InputState();
      await tester.pumpWidget(_wrap(
        TouchButton(state: input, action: _dash, label: 'dash', radius: 30),
      ));

      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(TouchButton)));
      await tester.pump();
      expect(input.pressed(_dash), isTrue);
      expect(input.held(_dash), isTrue);

      await gesture.up();
      await tester.pump();
      expect(input.held(_dash), isFalse);
      expect(input.released(_dash), isTrue);
    });

    testWidgets('and says what it does', (WidgetTester tester) async {
      final input = InputState();
      await tester.pumpWidget(_wrap(
        TouchButton(state: input, action: _dash, label: 'dash', radius: 30),
      ));

      expect(find.text('dash'), findsOneWidget);
    });
  });

  group('the two together', () {
    testWidgets('walk and jump at the same time', (WidgetTester tester) async {
      // The reason both controls track their own pointer, checked end to end
      // through the widget a game actually mounts.
      final input = InputState();
      await tester.pumpWidget(_wrap(
        SizedBox(
          width: 800,
          height: 600,
          child: TouchControls(
            state: input,
            buttons: const <TouchAction>[
              TouchAction(GameAction.jump, 'jump'),
              TouchAction(_dash, 'dash'),
            ],
          ),
        ),
      ));

      final walking = await tester.startGesture(
        tester.getCenter(find.byType(TouchStick)),
        pointer: 1,
      );
      await walking.moveBy(const Offset(0, -64));
      await tester.pump();

      await tester.startGesture(
        tester.getCenter(find.widgetWithText(TouchButton, 'jump')),
        pointer: 2,
      );
      await tester.pump();

      expect(input.moveAxis.y, closeTo(1.0, 1e-6));
      expect(input.held(GameAction.jump), isTrue);
      expect(input.held(_dash), isFalse);
    });
  });
}
