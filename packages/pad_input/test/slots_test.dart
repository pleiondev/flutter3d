/// More than one controller: each in the slot of the player holding it, on
/// Apple's platforms and on Android, and read by a [Gamepad] of that slot.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pad_input/pad_input.dart';
import 'package:pad_input/src/android_mapping.dart';
import 'package:pad_input/src/darwin_mapping.dart';
import 'package:pad_input/src/pad_slots.dart';

/// A Darwin sample for [slot] with the left stick's x at [leftX] and the
/// south face button at [south].
Float64List _darwin(int slot, {double leftX = 0.0, double south = 0.0}) {
  final out = Float64List(1 + DarwinPadState.sampleLength);
  out[0] = slot.toDouble();
  out[1] = leftX;
  out[1 + 6 + DarwinPadState.buttons.indexOf(PadButton.faceSouth)] = south;
  return out;
}

Float64List _motion(int device, int axis, double value) =>
    Float64List.fromList(<double>[device.toDouble(), axis.toDouble(), value]);

PadSnapshot _read(PadSlots slots, int slot) {
  final out = PadSnapshot();
  slots.fill(slot, out);
  return out;
}

/// A platform that reports two controllers: slot nought pushed left, slot
/// one pushed right.
final class _TwoPads extends GamepadPlatform {
  @override
  bool get isSupported => true;

  @override
  Stream<PadConnection> get connectionChanges =>
      const Stream<PadConnection>.empty();

  @override
  void read(PadSnapshot out) => readPad(0, out);

  @override
  void readPad(int index, PadSnapshot out) {
    if (index > 1) {
      out.disconnect();
      return;
    }
    out
      ..clear()
      ..connected = true
      ..setAxis(PadAxis.leftStickX, index == 0 ? -1.0 : 1.0);
  }
}

void main() {
  group('on Apple\'s platforms', () {
    test('two controllers are two players, each in its own slot', () {
      // Mutation: send every sample to the first slot.
      final slots = DarwinPads()
        ..note(<String, Object?>{'event': 'connected', 'slot': 0})
        ..note(<String, Object?>{'event': 'connected', 'slot': 1})
        ..note(_darwin(0, leftX: -0.8))
        ..note(_darwin(1, leftX: 0.6, south: 1.0));

      expect(slots.connectedCount, 2);
      expect(_read(slots, 0).axis(PadAxis.leftStickX), closeTo(-0.8, 1e-9));
      expect(_read(slots, 0).down(PadButton.faceSouth), isFalse);
      expect(_read(slots, 1).axis(PadAxis.leftStickX), closeTo(0.6, 1e-9));
      expect(_read(slots, 1).down(PadButton.faceSouth), isTrue);
      expect(_read(slots, 2).connected, isFalse);
    });

    test('the first unplugged leaves the second where it is', () {
      final slots = DarwinPads()
        ..note(<String, Object?>{'event': 'connected', 'slot': 0})
        ..note(<String, Object?>{'event': 'connected', 'slot': 1})
        ..note(_darwin(1, leftX: 0.5))
        ..note(<String, Object?>{'event': 'disconnected', 'slot': 0});

      expect(_read(slots, 0).connected, isFalse);
      expect(_read(slots, 1).axis(PadAxis.leftStickX), closeTo(0.5, 1e-9));
    });

    test('going to the background lets go of every controller', () {
      final slots = DarwinPads()
        ..note(<String, Object?>{'event': 'connected', 'slot': 0})
        ..note(<String, Object?>{'event': 'connected', 'slot': 1})
        ..note(_darwin(0, leftX: 1.0))
        ..note(_darwin(1, leftX: 1.0))
        ..note(<String, Object?>{'event': 'relaxed'});

      expect(_read(slots, 0).axis(PadAxis.leftStickX), 0.0);
      expect(_read(slots, 1).axis(PadAxis.leftStickX), 0.0);
      expect(slots.connectedCount, 2, reason: 'still attached');
    });
  });

  group('on Android', () {
    Map<String, Object?> connect(int device) => <String, Object?>{
      'event': 'connected',
      'device': device,
      'axes': <int>[AndroidAxis.x, AndroidAxis.y],
    };

    Map<String, Object?> key(int device, int code, {required bool down}) =>
        <String, Object?>{
          'event': 'key',
          'device': device,
          'code': code,
          'down': down,
        };

    test('each device takes the next slot, and its stick is its own', () {
      // Mutation: give every device slot nought.
      final slots = AndroidPads()
        ..note(connect(7))
        ..note(connect(12))
        ..note(_motion(7, AndroidAxis.x, -0.4))
        ..note(_motion(12, AndroidAxis.x, 0.9));

      expect(_read(slots, 0).axis(PadAxis.leftStickX), closeTo(-0.4, 1e-9));
      expect(_read(slots, 1).axis(PadAxis.leftStickX), closeTo(0.9, 1e-9));
    });

    test('a button pressed on the second pad is the second player\'s, and '
        'its d-pad is a d-pad', () {
      // Through Flutter's keyboard two pads pressing A were one A, and a
      // d-pad sending keys was a keyboard's arrows.
      //
      // Mutation: send forwarded buttons to the first slot.
      final slots = AndroidPads()
        ..note(connect(7))
        ..note(connect(12))
        ..note(key(12, 96, down: true))
        ..note(key(12, 19, down: true));

      expect(_read(slots, 0).down(PadButton.faceSouth), isFalse);
      expect(_read(slots, 1).down(PadButton.faceSouth), isTrue);
      expect(_read(slots, 1).down(PadButton.dpadUp), isTrue);

      slots.note(key(12, 96, down: false));
      expect(_read(slots, 1).down(PadButton.faceSouth), isFalse);
    });

    test('a slot a pad leaves is the next pad\'s, and the others stay', () {
      final slots = AndroidPads()
        ..note(connect(7))
        ..note(connect(12))
        ..note(<String, Object?>{'event': 'disconnected', 'device': 7})
        ..note(connect(30))
        ..note(_motion(30, AndroidAxis.x, 0.3))
        ..note(_motion(12, AndroidAxis.x, -0.2));

      expect(_read(slots, 0).axis(PadAxis.leftStickX), closeTo(0.3, 1e-9));
      expect(_read(slots, 1).axis(PadAxis.leftStickX), closeTo(-0.2, 1e-9));
    });
  });

  test('a Gamepad reads the controller in its own slot', () {
    // Mutation: read the first slot whatever the index.
    final platform = _TwoPads();
    final one = Gamepad(platform: platform);
    final two = Gamepad(platform: platform, index: 1);
    final three = Gamepad(platform: platform, index: 2);
    final out = PadSnapshot();

    one.read(out);
    expect(out.axis(PadAxis.leftStickX), -1.0);
    two.read(out);
    expect(out.axis(PadAxis.leftStickX), 1.0);
    three.read(out);
    expect(out.connected, isFalse);
  });

  test('a backend that tells no controllers apart has one, not the same one '
      'twice', () {
    // Mutation: answer every slot from read.
    final out = PadSnapshot()..connected = true;
    UnsupportedGamepad().readPad(1, out);
    expect(out.connected, isFalse);
  });
}
