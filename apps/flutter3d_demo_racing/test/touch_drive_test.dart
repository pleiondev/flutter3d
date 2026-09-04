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
import 'package:flutter3d_demo_racing/src/touch_drive.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';

const GameAction _left = GameAction('steerLeft');
const GameAction _right = GameAction('steerRight');
const GameAction _throttle = GameAction('throttle');
const GameAction _brake = GameAction('brake');
const GameAction _tyres = GameAction('tyres');

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

  testWidgets('and the pit stop is a control rather than an instruction', (
    WidgetTester tester,
  ) async {
    // **The HUD told a driver to stop and change, and a phone had no way to.**
    // The tyre line reads `STOP FIRST` when a change is refused at speed, which
    // is an instruction — and `Drive.tyres` was bound to a key, to a pad button
    // and to nothing a finger could reach. Read on the step through `pressed`,
    // so a tap is enough and a hold is not required.
    //
    // Mutation: drop the `pitStop` block from `TouchDrive` — this fails.
    final input = InputState();
    await tester.pumpWidget(
      Directionality(
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
            pitStop: _tyres,
          ),
        ),
      ),
    );

    final pit = await tester.startGesture(
      tester.getCenter(find.widgetWithText(TouchButton, 'pit')),
      pointer: 1,
    );
    await tester.pump();
    expect(input.pressed(_tyres), isTrue, reason: 'no way to call a pit stop');
    await pit.up();
  });

  testWidgets('and it is nowhere a corner can reach', (
    WidgetTester tester,
  ) async {
    // A pedal-sized target beside the throttle is a pit stop entered at two
    // hundred. It is the one control here that is never wanted mid-corner, so
    // it is the one that takes a deliberate reach — the far side of the screen
    // from everything that is held.
    //
    // Mutation: move the pit button into the pedal `Row` in `TouchDrive` — this
    // fails.
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 900,
          height: 500,
          child: TouchDrive(
            state: InputState(),
            steerLeft: _left,
            steerRight: _right,
            throttle: _throttle,
            brake: _brake,
            pitStop: _tyres,
          ),
        ),
      ),
    );

    final pit = tester.getRect(find.widgetWithText(TouchButton, 'pit'));
    for (final held in tester.widgetList<Pedal>(find.byType(Pedal))) {
      final rect = tester.getRect(find.byWidget(held));
      expect(
        pit.bottom,
        lessThan(rect.top),
        reason: 'the pit button is among the pedals',
      );
    }
    expect(
      pit.top,
      lessThan(tester.getRect(find.byType(SteeringBand)).top),
      reason: 'the pit button is level with the wheel',
    );
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
