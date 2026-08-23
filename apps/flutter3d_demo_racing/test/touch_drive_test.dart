/// A wheel and two pedals, for a player with no keyboard.
///
///     flutter test test/touch_drive_test.dart
///
/// **This game had nothing to offer a phone.** The other two have had touch
/// controls since they were written; a car has no thumb stick, so the shared
/// widget does not fit and the two things a driver holds — a steering axis and
/// a pedal held for a whole corner — had to be their own.
///
/// What is checked is what a finger means to the car, which is the same
/// arithmetic `_readDriver` performs on whatever the devices said.
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter3d_demo_racing/src/touch_drive.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';

const GameAction _left = GameAction('steerLeft');
const GameAction _right = GameAction('steerRight');
const GameAction _throttle = GameAction('throttle');

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

  testWidgets('and a pedal held is the throttle held', (WidgetTester tester) async {
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

  testWidgets('and a finger the system takes away lets go', (WidgetTester tester) async {
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

  testWidgets('and two fingers are two controls', (WidgetTester tester) async {
    // Braking while steering. A control that took the newest pointer would snap
    // the wheel to wherever the other thumb landed.
    final input = InputState();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: <Widget>[
            Positioned(
              left: 0,
              top: 0,
              child: SteeringBand(state: input, left: _left, right: _right),
            ),
            Positioned(
              left: 400,
              top: 0,
              child: Pedal(state: input, action: _throttle, label: 'throttle'),
            ),
          ],
        ),
      ),
    );

    final band = tester.getRect(find.byType(SteeringBand));
    final wheel = await tester.startGesture(
      Offset(band.right - 1, band.center.dy),
      pointer: 1,
    );
    await tester.pump();
    final pedal = await tester.startGesture(
      tester.getCenter(find.byType(Pedal)),
      pointer: 2,
    );
    await tester.pump();

    expect(_steer(input), closeTo(1.0, 0.02),
        reason: 'the second finger took the wheel');
    expect(input.value(_throttle), 1.0);

    await wheel.up();
    await pedal.up();
  });

  test('and the game shows them where there is no keyboard', () {
    final game = File('lib/main.dart').readAsStringSync();

    expect(game, contains('TouchDrive('),
        reason: 'a phone gets a car it cannot drive');
    expect(game, contains('Playing.touch'),
        reason: 'a wheel is drawn over a desktop that has a keyboard');
  });
}
