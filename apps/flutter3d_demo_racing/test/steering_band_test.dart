/// The analogue wheel a thumb steers with, for a player with no keyboard.
///
///     flutter test test/steering_band_test.dart
///
/// Split out of `touch_drive_test.dart` alongside `steering_band.dart`
/// itself. What is checked is what a finger means to the car, which is the
/// same arithmetic `_readDriver` performs on whatever the devices said.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_demo_racing/src/steering_band.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';

const GameAction _left = GameAction('steerLeft');
const GameAction _right = GameAction('steerRight');

/// The steering the game would ask the car for, given what the devices said.
double _steer(InputState input) =>
    input.value(_right) - input.value(_left);

void main() {
  testWidgets('the wheel is analogue, which is the whole point of it',
      (WidgetTester tester) async {
    // A car steered by two buttons is either straight or at full lock, which is
    // undriveable at speed — the same complaint that made this game read
    // magnitudes instead of presses.
    final input = InputState();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SteeringBand(state: input, left: _left, right: _right),
        ),
      ),
    );

    final band = tester.getRect(find.byType(SteeringBand));
    // A quarter of the way right of centre.
    final gesture = await tester.startGesture(
      Offset(band.center.dx + band.width * 0.25, band.center.dy),
    );
    await tester.pump();

    expect(_steer(input), closeTo(0.5, 1e-6));

    await gesture.moveTo(Offset(band.left + 1, band.center.dy));
    await tester.pump();
    expect(_steer(input), closeTo(-1.0, 0.02),
        reason: 'the far left of the band is not full left lock');

    await gesture.up();
    await tester.pump();
    expect(_steer(input), 0.0, reason: 'the wheel stayed over after the thumb '
        'came off, which is a car that drives into the wall by itself');
  });

  testWidgets('and one side of it speaks at a time', (WidgetTester tester) async {
    // The obvious shape sets both actions. `_readDriver` subtracts them, so a
    // wheel that asks for full left *and* full right is a wheel that does
    // nothing at all — and it looks fine on screen.
    final input = InputState();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SteeringBand(state: input, left: _left, right: _right),
        ),
      ),
    );

    final band = tester.getRect(find.byType(SteeringBand));
    await tester.startGesture(Offset(band.right - 1, band.center.dy));
    await tester.pump();

    expect(input.value(_right), closeTo(1.0, 0.02));
    expect(input.value(_left), 0.0);
  });

  testWidgets('and the thumb on the wheel outranks a key held down',
      (WidgetTester tester) async {
    // **The mutation that survived the first version of this file**, and the
    // reason the idle side is set to nought rather than withdrawn: a magnitude
    // absent falls back to whatever is held, so on a machine with both a
    // keyboard and a screen a forgotten key steers against the thumb. Setting
    // both says the wheel is what the player is moving; releasing withdraws
    // both, and the keyboard has it back.
    final input = InputState()..press(_left);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SteeringBand(state: input, left: _left, right: _right),
        ),
      ),
    );

    final band = tester.getRect(find.byType(SteeringBand));
    final gesture = await tester.startGesture(
      Offset(band.right - 1, band.center.dy),
    );
    await tester.pump();

    expect(_steer(input), closeTo(1.0, 0.02),
        reason: 'a key nobody is looking at is steering against the thumb');

    await gesture.up();
    await tester.pump();

    expect(_steer(input), -1.0,
        reason: 'the wheel kept the wheel after the thumb came off it');
  });

  testWidgets('and a second thumb on the band does not take it',
      (WidgetTester tester) async {
    // One control, one pointer. A band that took the newest would jump to
    // wherever a stray finger landed on it — which is where a player's other
    // hand rests.
    final input = InputState();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SteeringBand(state: input, left: _left, right: _right),
        ),
      ),
    );

    final band = tester.getRect(find.byType(SteeringBand));
    await tester.startGesture(Offset(band.right - 1, band.center.dy),
        pointer: 1);
    await tester.pump();
    await tester.startGesture(Offset(band.left + 1, band.center.dy),
        pointer: 2);
    await tester.pump();

    expect(_steer(input), closeTo(1.0, 0.02),
        reason: 'the second finger took the wheel');
  });
}
