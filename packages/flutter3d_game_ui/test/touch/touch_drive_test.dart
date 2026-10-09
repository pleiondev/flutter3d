/// A wheel and pedals together, for a player with no keyboard.
///
///     flutter test test/touch_drive_test.dart
///
/// **The racing demo had nothing to offer a phone.** A vehicle has no thumb
/// stick, so the shared `TouchControls` does not fit, and the two things a
/// driver holds — a steering axis and a pedal held for a whole corner — had
/// to be their own.
///
/// The wheel on its own is `steering_band_test.dart` and a pedal on its own is
/// `pedal_test.dart`. What is here is what only shows up with both on screen
/// together, and where the corner button goes.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_game_ui/touch.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

const GameAction _left = GameAction('steerLeft');
const GameAction _right = GameAction('steerRight');
const GameAction _throttle = GameAction('throttle');
const GameAction _brake = GameAction('brake');
const GameAction _tireSet = GameAction('tyres');

/// The steering a game would ask the vehicle for, given what the devices said.
double _steer(InputState input) => input.value(_right) - input.value(_left);

Widget _drive(InputState input, {GameAction? handbrake}) => Directionality(
  textDirection: TextDirection.ltr,
  child: SizedBox(
    width: 900,
    height: 500,
    child: TouchDrive(
      state: input,
      steerLeft: _left,
      steerRight: _right,
      throttle: _throttle,
      brake: _brake,
      handbrake: handbrake,
      corner: const TouchAction(_tireSet, 'pit'),
    ),
  ),
);

void main() {
  testWidgets('two fingers are two controls', (WidgetTester tester) async {
    // Braking while steering. A control that took the newest pointer would snap
    // the wheel to wherever the other thumb landed.
    //
    // Mutation: stretch the band across the screen (`Positioned.fill`) and
    // paint it last in the `Stack` — it takes the pedal's finger and the
    // throttle expectation fails.
    final input = InputState();
    await tester.pumpWidget(_drive(input));

    final band = tester.getRect(find.byType(SteeringBand));
    final wheel = await tester.startGesture(
      Offset(band.right - 1, band.center.dy),
      pointer: 1,
    );
    await tester.pump();
    final pedal = await tester.startGesture(
      tester.getCenter(find.widgetWithText(TouchButton, 'throttle')),
      pointer: 2,
    );
    await tester.pump();

    expect(
      _steer(input),
      closeTo(1.0, 0.02),
      reason: 'the second finger took the wheel',
    );
    expect(input.value(_throttle), 1.0);

    await wheel.up();
    await pedal.up();
  });

  testWidgets('the corner button is a control, pressed with a tap', (
    WidgetTester tester,
  ) async {
    // The racing demo's HUD tells a driver to stop and change tyres, and a
    // phone had nothing bound to the second half of that sentence.
    //
    // Mutation: drop the `corner` block from `TouchDrive` — this fails.
    final input = InputState();
    await tester.pumpWidget(_drive(input));

    final pit = await tester.startGesture(
      tester.getCenter(find.widgetWithText(TouchButton, 'pit')),
      pointer: 1,
    );
    await tester.pump();
    expect(input.pressed(_tireSet), isTrue, reason: 'no way to press it');
    await pit.up();
  });

  testWidgets('and it is nowhere a corner can reach', (
    WidgetTester tester,
  ) async {
    // A pedal-sized target beside the throttle is a button pressed at full
    // speed. It is the one control never wanted mid-corner, so it takes a
    // deliberate reach — the far side of the screen from everything held.
    //
    // Mutation: move the corner button into the pedal `Row` in `TouchDrive` —
    // this fails.
    await tester.pumpWidget(_drive(InputState(), handbrake: _brake));

    final pit = tester.getRect(find.widgetWithText(TouchButton, 'pit'));
    final pedals = find.byWidgetPredicate(
      (Widget it) => it is TouchButton && it.pedal != null,
    );
    for (final held in tester.widgetList<TouchButton>(pedals)) {
      final rect = tester.getRect(find.byWidget(held));
      expect(
        pit.bottom,
        lessThan(rect.top),
        reason: 'the corner button is among the pedals',
      );
    }
    expect(
      pit.top,
      lessThan(tester.getRect(find.byType(SteeringBand)).top),
      reason: 'the corner button is level with the wheel',
    );
  });

  testWidgets('the throttle is the pedal nearest the thumb', (
    WidgetTester tester,
  ) async {
    // Held the longest, so it is where the right thumb rests.
    //
    // Mutation: swap the brake and the throttle in the `Row` — this fails.
    await tester.pumpWidget(_drive(InputState(), handbrake: _brake));

    final right = <String, double>{
      for (final label in <String>['handbrake', 'brake', 'throttle'])
        label: tester.getRect(find.widgetWithText(TouchButton, label)).right,
    };
    expect(right['throttle'], greaterThan(right['brake']!));
    expect(right['brake'], greaterThan(right['handbrake']!));
  });
}
