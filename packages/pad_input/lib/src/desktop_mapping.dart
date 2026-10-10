import 'dart:math' as math;
import 'dart:typed_data';

import 'pad_button.dart';
import 'pad_mirror.dart';
import 'pad_snapshot.dart';

/// How far a trigger travels before it counts as pressed: XInput's own
/// `XINPUT_GAMEPAD_TRIGGER_THRESHOLD`, thirty of 255, used on Linux too so a
/// trigger means the same on both. `PadInput` applies its own two thresholds
/// to the travel for a game; this is only the button's bit.
const double _triggerDown = 30.0 / 255.0;

/// A controller on Windows, as XInput reports it.
///
/// **What the plugin sends is XInput's own numbers**, untouched, in the
/// order `XINPUT_GAMEPAD` holds them: the sticks as −32768…32767, the
/// triggers as 0…255, and the buttons as `wButtons`' bits. Everything those
/// numbers mean is decided here, where a test can see it, as Apple's are in
/// `DarwinPadState` — including the one thing XInput shares with Apple and
/// not with this package: a stick's y is positive upwards.
///
/// XInput has no guide button to report, so [PadButton.guide] stays up.
final class XInputPadState implements PadMirror {
  /// `wButtons`' bit for each button, in [PadButton.known]'s order; nought
  /// for one XInput has not got.
  static const List<int> bits = <int>[
    0x1000, // A — the south face
    0x2000, // B — east
    0x4000, // X — west
    0x8000, // Y — north
    0x0001, // d-pad up
    0x0002, // down
    0x0004, // left
    0x0008, // right
    0x0100, // left shoulder
    0x0200, // right shoulder
    0, // left trigger: its travel, below
    0, // right trigger
    0x0040, // left stick click
    0x0080, // right stick click
    0x0010, // start
    0x0020, // back
    0, // guide: XInput keeps it
  ];

  bool _connected = false;
  final Float64List _raw = Float64List(7);

  @override
  bool get connected => _connected;

  @override
  void note(Object? event) {
    if (event is Float64List) {
      _raw.setRange(0, math.min(event.length, _raw.length), event);
      return;
    }
    if (event is! Map) return;
    switch (event['event']) {
      case 'connected':
        _connected = true;
      case 'disconnected':
        _connected = false;
        _raw.fillRange(0, _raw.length, 0.0);
      case 'relaxed':
        _raw.fillRange(0, _raw.length, 0.0);
    }
  }

  @override
  void fill(PadSnapshot out) {
    if (!_connected) {
      out.disconnect();
      return;
    }
    out
      ..clear()
      ..isConnected = true;
    double stick(double v) => (v / 32767.0).clamp(-1.0, 1.0);
    out
      ..setAxis(PadAxis.leftStickX, stick(_raw[0]))
      // Up is positive in XInput and down is positive here.
      ..setAxis(PadAxis.leftStickY, -stick(_raw[1]))
      ..setAxis(PadAxis.rightStickX, stick(_raw[2]))
      ..setAxis(PadAxis.rightStickY, -stick(_raw[3]))
      ..setAxis(PadAxis.triggerLeft, _raw[4] / 255.0)
      ..setAxis(PadAxis.triggerRight, _raw[5] / 255.0);
    final buttons = _raw[6].toInt();
    for (final (i, button) in PadButton.known.indexed) {
      final pressure = button == PadButton.triggerLeft
          ? out.axis(PadAxis.triggerLeft)
          : button == PadButton.triggerRight
          ? out.axis(PadAxis.triggerRight)
          : null;
      out.setDown(
        button,
        down: pressure != null
            ? pressure > _triggerDown
            : buttons & bits[i] != 0,
        pressure: pressure,
      );
    }
  }
}

/// A controller on Linux, through the kernel's joystick interface —
/// `/dev/input/jsN` — as the `xpad` driver lays an Xbox-style pad out on it.
///
/// **The plugin forwards the kernel's events as they come**: for each, its
/// type (one a button, two an axis), its number and its value. Which number
/// is which control is the driver's layout, written down here once: axes
/// nought and one the left stick, two the left trigger, three and four the
/// right stick, five the right trigger, six and seven the d-pad as a hat;
/// buttons A, B, X, Y, the shoulders, back, start, guide and the two stick
/// clicks, in that order. A stick's y is positive downwards on Linux, as it
/// is here; a trigger rests at −32767 and is fully in at 32767.
final class JoystickPadState implements PadMirror {
  static const int _button = 1;
  static const int _axis = 2;

  /// The `xpad` button number each of [PadButton.known] is, or −1 for one
  /// that is not a button on this interface (the d-pad, the triggers).
  static const List<int> buttonNumbers = <int>[
    0, 1, 2, 3, // A B X Y
    -1, -1, -1, -1, // the d-pad: axes six and seven
    4, 5, // shoulders
    -1, -1, // triggers: axes two and five
    9, 10, // stick clicks
    7, 6, 8, // start, back, guide
  ];

  bool _connected = false;
  final Float64List _axes = Float64List(8);
  final List<bool> _buttons = List<bool>.filled(16, false);

  @override
  bool get connected => _connected;

  @override
  void note(Object? event) {
    if (event is Float64List) {
      for (var i = 0; i + 2 < event.length; i += 3) {
        final (type, number, value) = (
          event[i].toInt() & 0x7f,
          event[i + 1].toInt(),
          event[i + 2],
        );
        if (type == _axis && number >= 0 && number < _axes.length) {
          _axes[number] = value;
        } else if (type == _button && number >= 0 && number < _buttons.length) {
          _buttons[number] = value != 0.0;
        }
      }
      return;
    }
    if (event is! Map) return;
    switch (event['event']) {
      case 'connected':
        _connected = true;
        _rest();
      case 'disconnected':
        _connected = false;
        _rest();
      case 'relaxed':
        _rest();
    }
  }

  /// Everything let go, the triggers out.
  void _rest() {
    _axes.fillRange(0, _axes.length, 0.0);
    _axes[2] = -32767.0;
    _axes[5] = -32767.0;
    _buttons.fillRange(0, _buttons.length, false);
  }

  @override
  void fill(PadSnapshot out) {
    if (!_connected) {
      out.disconnect();
      return;
    }
    out
      ..clear()
      ..isConnected = true;
    double stick(double v) => (v / 32767.0).clamp(-1.0, 1.0);
    double trigger(double v) => ((v + 32767.0) / 65534.0).clamp(0.0, 1.0);
    out
      ..setAxis(PadAxis.leftStickX, stick(_axes[0]))
      ..setAxis(PadAxis.leftStickY, stick(_axes[1]))
      ..setAxis(PadAxis.triggerLeft, trigger(_axes[2]))
      ..setAxis(PadAxis.rightStickX, stick(_axes[3]))
      ..setAxis(PadAxis.rightStickY, stick(_axes[4]))
      ..setAxis(PadAxis.triggerRight, trigger(_axes[5]));
    for (final (i, button) in PadButton.known.indexed) {
      final down = switch (button) {
        PadButton.dpadUp => _axes[7] < 0.0,
        PadButton.dpadDown => _axes[7] > 0.0,
        PadButton.dpadLeft => _axes[6] < 0.0,
        PadButton.dpadRight => _axes[6] > 0.0,
        PadButton.triggerLeft => out.axis(PadAxis.triggerLeft) > _triggerDown,
        PadButton.triggerRight => out.axis(PadAxis.triggerRight) > _triggerDown,
        _ => buttonNumbers[i] >= 0 && _buttons[buttonNumbers[i]],
      };
      final pressure = button == PadButton.triggerLeft
          ? out.axis(PadAxis.triggerLeft)
          : button == PadButton.triggerRight
          ? out.axis(PadAxis.triggerRight)
          : null;
      out.setDown(button, down: down, pressure: pressure);
    }
  }
}
