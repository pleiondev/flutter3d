/// The pad in the game's own words, and the platform's pad behind them.
///
///     flutter test test/pad_device_test.dart
///
/// The game's input names no type of `pad_input`, which is on its own 0.x
/// line: a change there is mended in `PadDevice.platform`, never in a game.
/// What has to hold is that the translation loses nothing: every axis, every
/// button by its id, and a pad that went away.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pad_input/pad_input.dart';

/// A platform whose every slot holds what the test says.
final class _Platform extends GamepadPlatform {
  final PadSnapshot state = PadSnapshot()..isConnected = true;

  @override
  bool get isSupported => true;

  @override
  Stream<PadConnection> get connectionChanges =>
      const Stream<PadConnection>.empty();

  @override
  void read(PadSnapshot out) => out.copyFrom(state);

  @override
  void readPad(PadReadContext context) {
    final out = context.out;
    out.copyFrom(state);
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  late _Platform platform;

  setUp(() {
    platform = _Platform();
    GamepadPlatform.instance = platform;
  });

  test('the platform pad is read in the game\'s words, all of it', () {
    // Mutation: leave an axis out of the platform pad's table, or read a
    // button by anything but its id, and the reading says less than the pad.
    platform.state
      ..setAxis(PadAxis.leftStickX, 0.5)
      ..setAxis(PadAxis.rightStickY, -1.0)
      ..setAxis(PadAxis.triggerRight, 1.0)
      ..setDown(PadButton.start, down: true)
      ..setDown(const PadButton('paddle.1'), down: true);
    final device = PadDevice.platform(slot: 1)
      ..setDeadZones(PadDeadZones(stick: 0.0, trigger: 0.0));
    final reading = PadReading();

    device.read(reading);

    expect(reading.isConnected, isTrue);
    expect(reading.axis(GamePadAxis.leftStickX), 0.5);
    expect(reading.axis(GamePadAxis.rightStickY), -1.0);
    expect(reading.axis(GamePadAxis.triggerRight), 1.0);
    expect(reading.down(GamePadButton.start), isTrue);
    expect(
      reading.held,
      contains(const GamePadButton('paddle.1')),
      reason: 'a button the game names no constant for is still a button',
    );
  });

  test('a pad that went away reads as no pad, with nothing held', () {
    platform.state.setDown(PadButton.faceSouth, down: true);
    final device = PadDevice.platform(slot: 1);
    final reading = PadReading();
    device.read(reading);
    expect(reading.down(GamePadButton.faceSouth), isTrue);

    platform.state.disconnect();
    device.read(reading);

    expect(reading.isConnected, isFalse);
    expect(reading.held, isEmpty);
  });

  test('a button is its id, whichever constant names it', () {
    expect(const GamePadButton('start'), GamePadButton.start);
    expect(
      GamePadButton.known.map((GamePadButton b) => b.id),
      PadButton.known.map((PadButton b) => b.id),
      reason: 'the game names every button the device does, by the same id',
    );
  });

  test('a reading copies another and forgets on disconnect', () {
    final source = PadReading()
      ..isConnected = true
      ..setAxis(GamePadAxis.triggerLeft, 0.25)
      ..setDown(GamePadButton.back, down: true);
    final copy = PadReading()..copyFrom(source);

    expect(copy.axis(GamePadAxis.triggerLeft), 0.25);
    expect(copy.down(GamePadButton.back), isTrue);

    copy.disconnect();
    expect(copy.isConnected, isFalse);
    expect(copy.axis(GamePadAxis.triggerLeft), 0.0);
    expect(copy.held, isEmpty);
  });
}
