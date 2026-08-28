/// A car asked for how hard, not for whether.
///
///     flutter test test/driving_test.dart
///
/// **Everything a controller needs was already written and this game read none
/// of it.** `VehicleInput` has held a throttle, a brake and a steering angle as
/// `double` since the genre package existed, `PadRoutes.driving` was written for
/// a racing game that never asked for it, and the one place a player's intent
/// became a number said `held ? 1.0 : 0.0` — so a trigger a third down and a
/// stick a third over arrived as everything or nothing.
///
/// What is checked here is the arithmetic between a device and a car. The
/// device package draws the line: below the platform channel needs a controller
/// in hand, above it is this.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter3d_app/flutter3d_app.dart'; // GamepadPlatform, from pad_input
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';

/// A gamepad that does whatever the test says.
final class _FakePad extends GamepadPlatform {
  final PadSnapshot state = PadSnapshot()..connected = true;
  final StreamController<PadConnection> _connections =
      StreamController<PadConnection>.broadcast();

  @override
  bool get isSupported => true;

  @override
  Stream<PadConnection> get connectionChanges => _connections.stream;

  @override
  void read(PadSnapshot out) => out.copyFrom(state);

  @override
  Future<void> dispose() async => _connections.close();
}

/// No dead zone, so a test can name the number it expects. The dead zone has
/// its own tests in the device package.
Gamepad _bare(_FakePad fake) =>
    Gamepad(platform: fake, deadzone: const Deadzone(stick: 0.0, trigger: 0.0));

const GameAction _throttle = GameAction('throttle');
const GameAction _brake = GameAction('brake');
const GameAction _left = GameAction('steerLeft');
const GameAction _right = GameAction('steerRight');

/// This game's pad table, in the shape `main.dart` builds it.
Bindings _padTable() => Bindings(<InputSource, GameAction>{})
  ..bind(InputSource.pad(PadButton.triggerRight.id), _throttle)
  ..bind(InputSource.pad(PadButton.triggerLeft.id), _brake);

/// What `_readDriver` does with whatever the devices said.
({double throttle, double brake, double steer}) _asDriven(InputState input) => (
  throttle: input.value(_throttle),
  brake: input.value(_brake),
  steer: input.value(_right) - input.value(_left),
);

void main() {
  test('a trigger a third down is a third of the throttle', () {
    // The bug this replaces: `held ? 1.0 : 0.0`, which is a car with an on/off
    // pedal being driven by a control that measures its own travel.
    final fake = _FakePad()..state.setAxis(PadAxis.triggerRight, 0.33);
    final input = InputState();

    PadInput(
      state: input,
      pad: _bare(fake),
      bindings: _padTable(),
      routes: PadRoutes.driving(steerLeft: _left, steerRight: _right),
    ).tick(1 / 60);

    expect(_asDriven(input).throttle, closeTo(0.33, 1e-6));
  });

  test('and the stick half over asks for half the lock', () {
    final fake = _FakePad()..state.setAxis(PadAxis.leftStickX, -0.5);
    final input = InputState();

    PadInput(
      state: input,
      pad: _bare(fake),
      bindings: _padTable(),
      routes: PadRoutes.driving(steerLeft: _left, steerRight: _right),
    ).tick(1 / 60);

    // Negative is left, and left is a negative steering angle at the car.
    expect(_asDriven(input).steer, closeTo(-0.5, 1e-6));
  });

  test('and a key is still all of it', () {
    // The other half of `value`, and the reason the game can read one number
    // for both devices: a key has no travel, so a press is a press.
    final input = InputState()..press(_throttle);

    expect(_asDriven(input).throttle, 1.0);
  });

  test('and a pad unplugged mid-corner does not leave the wheel over', () {
    // A pad that goes away has to withdraw what it said. What this catches is
    // a car left steering into a wall by a controller that is no longer in the
    // room — and, worse, a keyboard that cannot take the wheel back.
    final fake = _FakePad()..state.setAxis(PadAxis.leftStickX, 1.0);
    final input = InputState();
    final pad = PadInput(
      state: input,
      pad: _bare(fake),
      bindings: _padTable(),
      routes: PadRoutes.driving(steerLeft: _left, steerRight: _right),
    )..tick(1 / 60);
    expect(_asDriven(input).steer, closeTo(1.0, 1e-6));

    fake.state
      ..connected = false
      ..setAxis(PadAxis.leftStickX, 0.0);
    pad.tick(1 / 60);

    expect(_asDriven(input).steer, 0.0);
  });

  test('and the game reads how hard rather than whether', () {
    // A scan, for the reason `ghost_test.dart` gives at length: the read is a
    // private method of a widget no test can mount, and this exact line was
    // digital for as long as the game existed.
    final game = File('lib/main.dart').readAsStringSync();

    expect(game, contains(r'_input.value(Drive.throttle)'));
    expect(
      game,
      contains(r'_input.value(Drive.right) - _input.value(Drive.left)'),
    );
    expect(
      game,
      isNot(contains(r'_input.held(Drive.throttle)')),
      reason: 'the throttle is a switch again',
    );
    expect(
      game,
      contains('PadRoutes.driving('),
      reason: 'the stick is not routed, so nothing steers from a pad',
    );
    expect(
      game,
      contains('_pad.tick('),
      reason: 'the pad is built and never polled',
    );
  });
}
