/// Windows' XInput and Linux's joystick interface, as their plugins forward
/// them: the platform's own numbers, read into the package's pad here.
///
///     flutter test test/desktop_test.dart
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pad_input/pad_input.dart';
import 'package:pad_input/src/desktop_mapping.dart';
import 'package:pad_input/src/pad_slots.dart';

void main() {
  group('XInput', () {
    test('sticks and triggers, the y the right way up', () {
      final pad = XInputPadState()
        ..note(const <String, Object?>{'event': 'connected'})
        // The left stick pushed up and right, the right one down, the left
        // trigger half in, A and the left shoulder held.
        ..note(
          Float64List.fromList(<double>[
            16384,
            32767,
            0,
            -32768,
            128,
            0,
            (0x1000 | 0x0100).toDouble(),
          ]),
        );
      final out = PadSnapshot();
      pad.fill(out);
      expect(out.connected, isTrue);
      expect(out.axis(PadAxis.leftStickX), closeTo(0.5, 1e-3));
      // Mutation: XInput's y passed through — up would read as down.
      expect(out.axis(PadAxis.leftStickY), closeTo(-1.0, 1e-6));
      expect(out.axis(PadAxis.rightStickY), closeTo(1.0, 1e-6));
      expect(out.axis(PadAxis.triggerLeft), closeTo(128 / 255, 1e-6));
      expect(out.down(PadButton.faceSouth), isTrue);
      expect(out.down(PadButton.shoulderLeft), isTrue);
      expect(out.down(PadButton.faceEast), isFalse);
      // Half in is past the threshold; the other trigger rests.
      expect(out.down(PadButton.triggerLeft), isTrue);
      expect(out.down(PadButton.triggerRight), isFalse);
    });

    test('every button is its bit, and none is two', () {
      final bits = XInputPadState.bits.where((b) => b != 0).toList();
      expect(bits.toSet(), hasLength(bits.length));
      expect(XInputPadState.bits, hasLength(PadButton.known.length));
      for (final (i, button) in PadButton.known.indexed) {
        final bit = XInputPadState.bits[i];
        if (bit == 0) continue;
        final pad = XInputPadState()
          ..note(const <String, Object?>{'event': 'connected'})
          ..note(
            Float64List.fromList(<double>[0, 0, 0, 0, 0, 0, bit.toDouble()]),
          );
        final out = PadSnapshot();
        pad.fill(out);
        expect(PadButton.known.where(out.down), <PadButton>[
          button,
        ], reason: '$button');
      }
    });

    test('unplugged mid-corner lets go of everything', () {
      final pads = XInputPads()
        ..note(const <String, Object?>{'event': 'connected', 'slot': 2})
        ..note(Float64List.fromList(<double>[2, 0, 0, 0, 0, 0, 255, 0]));
      final out = PadSnapshot();
      pads.fill(2, out);
      expect(out.axis(PadAxis.triggerRight), 1.0);
      pads.note(const <String, Object?>{'event': 'disconnected', 'slot': 2});
      pads.fill(2, out);
      expect(out.connected, isFalse);
      expect(pads.connectedCount, 0);
    });
  });

  group('Linux joystick', () {
    Float64List events(List<(int, int, int)> it) =>
        Float64List.fromList(<double>[
          0, // slot
          for (final (type, number, value) in it) ...<double>[
            type.toDouble(),
            number.toDouble(),
            value.toDouble(),
          ],
        ]);

    test('the xpad layout read: sticks down-positive, triggers from rest', () {
      final pads = JoystickPads()
        ..note(const <String, Object?>{'event': 'connected', 'slot': 0});
      final out = PadSnapshot();
      pads.fill(0, out);
      // At rest a trigger reads −32767, which is none.
      expect(out.axis(PadAxis.triggerLeft), 0.0);
      pads.note(
        events(<(int, int, int)>[
          (2, 0, 32767), // left stick right
          (2, 1, 32767), // and down
          (2, 5, 32767), // right trigger fully in
          (2, 7, -32767), // d-pad up
          (1, 0, 1), // A
          (1, 8, 1), // guide
          (1 | 0x80, 4, 1), // the left shoulder, held when the pad opened
        ]),
      );
      pads.fill(0, out);
      expect(out.axis(PadAxis.leftStickX), 1.0);
      // Mutation: the y negated as XInput's is — Linux's is already down.
      expect(out.axis(PadAxis.leftStickY), 1.0);
      expect(out.axis(PadAxis.triggerRight), 1.0);
      expect(out.down(PadButton.triggerRight), isTrue);
      expect(out.down(PadButton.dpadUp), isTrue);
      expect(out.down(PadButton.dpadDown), isFalse);
      expect(out.down(PadButton.faceSouth), isTrue);
      expect(out.down(PadButton.guide), isTrue);
      // The kernel's initial state, flagged 0x80, counts as what it says.
      expect(out.down(PadButton.shoulderLeft), isTrue);
    });

    test('the window going away lets go of every pad', () {
      final pads = JoystickPads()
        ..note(const <String, Object?>{'event': 'connected', 'slot': 0})
        ..note(events(<(int, int, int)>[(1, 0, 1)]))
        ..note(const <String, Object?>{'event': 'relaxed'});
      final out = PadSnapshot();
      pads.fill(0, out);
      expect(out.down(PadButton.faceSouth), isFalse);
      expect(out.connected, isTrue);
    });
  });
}
