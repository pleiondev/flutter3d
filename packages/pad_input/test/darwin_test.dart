/// The Apple backend, without an Apple controller.
///
///     flutter test test/darwin_test.dart
///
/// The easiest of the three platforms to write and the easiest to get subtly
/// wrong. `GCExtendedGamepad` is already the shape this package chose — face
/// buttons by position, four d-pad buttons, two analogue triggers — so there is
/// no per-device guessing of the kind Android needs. What is left is an order
/// and a sign, and the sign is the interesting one: **`GameController` reports a
/// stick's y positive upwards**, where Android, the browser and this package all
/// report it downwards.
///
/// That is a difference no code review catches and a room with a controller
/// catches in one second, because the character walks backwards. So it is done
/// in Dart, once, with a test on it.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pad_input/pad_input.dart';
import 'package:pad_input/src/darwin_mapping.dart';

/// A sample in the shape the Swift side sends it: six axes, then a value per
/// button in `PadButton.known`'s order.
Float64List sample({
  double leftX = 0.0,
  double leftY = 0.0,
  double rightX = 0.0,
  double rightY = 0.0,
  double leftTrigger = 0.0,
  double rightTrigger = 0.0,
  Map<PadButton, double> buttons = const <PadButton, double>{},
}) {
  final out = Float64List(DarwinPadState.sampleLength);
  out[0] = leftX;
  out[1] = leftY;
  out[2] = rightX;
  out[3] = rightY;
  out[4] = leftTrigger;
  out[5] = rightTrigger;
  buttons.forEach((PadButton button, double value) {
    out[6 + DarwinPadState.buttons.indexOf(button)] = value;
  });
  return out;
}

DarwinPadState connected() =>
    DarwinPadState()..note(<String, Object?>{'event': 'connected'});

void main() {
  group('a stick', () {
    test('pushed up walks forward, not backwards', () {
      // **The whole reason this file exists.** `GameController` says a stick
      // pushed up is +1 on its y axis; this package says down is positive, as
      // Android and the browser do. One negation, in the open, once.
      final state = connected()..note(sample(leftY: 1.0));

      final out = PadSnapshot();
      state.fill(out);

      expect(out.axis(PadAxis.leftStickY), closeTo(-1.0, 1e-9),
          reason: 'a stick pushed up must read negative here, because that is '
              'what the other two platforms report and what PadInput flips');
    });

    test('and x is left alone, because x already agrees', () {
      final state = connected()..note(sample(leftX: 0.5, rightX: -0.25));

      final out = PadSnapshot();
      state.fill(out);

      expect(out.axis(PadAxis.leftStickX), closeTo(0.5, 1e-9));
      expect(out.axis(PadAxis.rightStickX), closeTo(-0.25, 1e-9));
    });

    test('and the right stick is flipped too, not just the left', () {
      // Easy to fix one and forget the other, and the symptom is a camera that
      // looks the wrong way only vertically.
      final state = connected()..note(sample(rightY: 1.0));

      final out = PadSnapshot();
      state.fill(out);

      expect(out.axis(PadAxis.rightStickY), closeTo(-1.0, 1e-9));
    });
  });

  group('the fixed order', () {
    test('puts each button where the native side wrote it', () {
      final state = connected()
        ..note(sample(buttons: <PadButton, double>{
          PadButton.faceSouth: 1.0,
          PadButton.dpadLeft: 1.0,
          PadButton.guide: 1.0,
        }));

      final out = PadSnapshot();
      state.fill(out);

      expect(out.down(PadButton.faceSouth), isTrue);
      expect(out.down(PadButton.dpadLeft), isTrue);
      expect(out.down(PadButton.guide), isTrue);
      expect(out.down(PadButton.faceEast), isFalse);
      expect(out.down(PadButton.dpadRight), isFalse);
    });

    test('and a trigger keeps its travel', () {
      // Racing needs the proportion. The Swift side sends the value for these
      // two and the framework's own bit for everything else.
      final state = connected()..note(sample(rightTrigger: 0.42));

      final out = PadSnapshot();
      state.fill(out);

      expect(out.axis(PadAxis.triggerRight), closeTo(0.42, 1e-9));
      // The travel reaches the button too, so a caller that does not care which
      // controls are analogue never has to find out — and it reaches it from the
      // axis rather than from a second copy on the wire.
      expect(out.pressure(PadButton.triggerRight), closeTo(0.42, 1e-9));
      expect(out.down(PadButton.triggerRight), isFalse,
          reason: "the framework's own bit said no, and it is the only bit");
    });

    test('and a sample shorter than the table is not an error', () {
      // A pad with no home button, an older Swift side, a truncated message:
      // reading past the end would be a crash on the frame it arrived.
      final state = connected()..note(Float64List.fromList(<double>[0.0, 0.5]));

      final out = PadSnapshot();
      state.fill(out);

      expect(out.axis(PadAxis.leftStickY), closeTo(-0.5, 1e-9));
      expect(out.down(PadButton.guide), isFalse);
    });

    test('and the two sides agree about how many controls there are', () {
      // The Swift file writes seventeen values by name against this list. If the
      // list grows and the Swift does not, every button past the new one moves.
      expect(DarwinPadState.buttons.length, 17);
      expect(DarwinPadState.sampleLength, 6 + 17);
    });
  });

  group('losing the player, and losing the pad', () {
    test('going to the background lets go without disconnecting', () {
      final state = connected()
        ..note(sample(leftY: 1.0, buttons: <PadButton, double>{
          PadButton.faceSouth: 1.0,
        }))
        ..note(<String, Object?>{'event': 'relaxed'});

      final out = PadSnapshot();
      state.fill(out);

      expect(out.connected, isTrue);
      expect(out.axis(PadAxis.leftStickY), 0.0);
      expect(out.down(PadButton.faceSouth), isFalse);
    });

    test('and unplugging leaves nothing held', () {
      final state = connected()
        ..note(sample(rightTrigger: 1.0))
        ..note(<String, Object?>{'event': 'disconnected'});

      final out = PadSnapshot();
      state.fill(out);

      expect(state.connected, isFalse);
      expect(out.connected, isFalse);
      expect(out.axis(PadAxis.triggerRight), 0.0);
    });

    test('and a message it does not understand changes nothing', () {
      final state = connected()
        ..note(<String, Object?>{'event': 'rumble'})
        ..note('nonsense');

      expect(state.connected, isTrue);
    });
  });
}
