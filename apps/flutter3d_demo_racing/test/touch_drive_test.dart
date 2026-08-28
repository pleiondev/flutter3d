/// A wheel and two pedals together, for a player with no keyboard.
///
///     flutter test test/touch_drive_test.dart
///
/// **This game had nothing to offer a phone.** The other two have had touch
/// controls since they were written; a car has no thumb stick, so the shared
/// widget does not fit and the two things a driver holds — a steering axis and
/// a pedal held for a whole corner — had to be their own.
///
/// The wheel on its own is `steering_band_test.dart` and a pedal on its own is
/// `pedal_test.dart`. What is left here is what only shows up with both on
/// screen together, and that this widget is actually the one the game draws.
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter3d_demo_racing/src/pedal.dart';
import 'package:flutter3d_demo_racing/src/steering_band.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';

const GameAction _left = GameAction('steerLeft');
const GameAction _right = GameAction('steerRight');
const GameAction _throttle = GameAction('throttle');

/// The steering the game would ask the car for, given what the devices said.
double _steer(InputState input) => input.value(_right) - input.value(_left);

void main() {
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

    expect(
      _steer(input),
      closeTo(1.0, 0.02),
      reason: 'the second finger took the wheel',
    );
    expect(input.value(_throttle), 1.0);

    await wheel.up();
    await pedal.up();
  });

  test('and the game shows them where there is no keyboard', () {
    final game = File('lib/main.dart').readAsStringSync();

    expect(
      game,
      contains('TouchDrive('),
      reason: 'a phone gets a car it cannot drive',
    );
    expect(
      game,
      contains('Playing.touch'),
      reason: 'a wheel is drawn over a desktop that has a keyboard',
    );
  });
}
