import 'dart:typed_data';

import 'pad_button.dart';
import 'pad_mirror.dart';
import 'pad_snapshot.dart';

/// A gamepad on macOS and iOS, as `GameController` reports it.
///
/// **The easiest of the three platforms, and it is worth saying why.**
/// `GCExtendedGamepad` is already the shape this package chose: face buttons by
/// position, a d-pad of four buttons, two shoulders, two analogue triggers, two
/// clickable sticks, and menu/options/home. Apple normalised the hardware years
/// ago, so there is no per-device guessing of the kind Android needs and no
/// mapping table to consult. The native side sends the values in a fixed order
/// and this reads them back.
///
/// ## The one trap, and it is a sign
///
/// **`GameController` reports a stick's y as positive upwards.** Android and the
/// browser report it positive downwards, and so does this package — see
/// [PadAxis]. So the two stick y values are negated here, in the open, once.
///
/// It is exactly the kind of difference that is invisible in a code review and
/// obvious in a room with a controller: the character walks backwards. The
/// alternative — flipping it in Swift — would have put it where no test could
/// see it and where the next platform would have to remember to do the same.
final class DarwinPadState implements PadMirror {
  /// How many doubles a sample carries: the axes, then a value per button.
  static int get sampleLength => _axisCount + PadButton.known.length;

  static const int _axisCount = 6;

  /// The axes, in the order the native side writes them.
  ///
  /// The two stick y entries are the ones negated on the way in.
  static const List<PadAxis> axes = <PadAxis>[
    PadAxis.leftStickX,
    PadAxis.leftStickY,
    PadAxis.rightStickX,
    PadAxis.rightStickY,
    PadAxis.triggerLeft,
    PadAxis.triggerRight,
  ];

  /// The buttons follow, in [PadButton.known]'s own order.
  ///
  /// Not a coincidence and not fragile: that list is the same seventeen controls
  /// `GCExtendedGamepad` has, in the same order, because both are the physical
  /// layout of a controller. The Swift side writes them by name against this
  /// list, and `test/darwin_test.dart` checks the length agrees.
  static List<PadButton> get buttons => PadButton.known;

  bool _connected = false;
  final Float64List _values = Float64List(_axisCount + 32);
  int _length = 0;

  @override
  bool get connected => _connected;

  @override
  void note(Object? event) {
    if (event is Float64List) {
      _length = event.length < _values.length ? event.length : _values.length;
      _values.setRange(0, _length, event);
      return;
    }
    if (event is! Map) return;
    switch (event['event']) {
      case 'connected':
        _connected = true;
      case 'disconnected':
        _connected = false;
        _clear();
      case 'relaxed':
        // The application went to the background, or another window took the
        // keyboard. The controller is still attached and the player is not.
        _clear();
    }
  }

  @override
  void fill(PadSnapshot out) {
    if (!_connected) {
      out.disconnect();
      return;
    }
    out.clear();
    out.connected = true;

    for (var i = 0; i < axes.length; i++) {
      final axis = axes[i];
      final value = _at(i);
      // Up is positive on Apple's platforms and down is positive here. See the
      // class doc: this is the whole of the difference.
      final sign = axis == PadAxis.leftStickY || axis == PadAxis.rightStickY
          ? -1.0
          : 1.0;
      out.setAxis(axis, value * sign);
    }

    final names = buttons;
    for (var i = 0; i < names.length; i++) {
      final button = names[i];
      // **Every button carries a bit and only a bit**, including the triggers.
      // Their travel is already in the axis list above, and sending it twice is
      // what the first draft did — a test caught the duplication by disagreeing
      // with itself about which copy mattered.
      //
      // So the bit is `GCControllerButtonInput.isPressed`, which is Apple's own
      // threshold rather than one invented here, and the travel a game plays by
      // comes off the axis. `PadInput` applies the real threshold, with two of
      // them so a trigger resting against one cannot chatter.
      final down = _at(_axisCount + i) > 0.0;
      final pressure = button == PadButton.triggerLeft
          ? out.axis(PadAxis.triggerLeft)
          : button == PadButton.triggerRight
              ? out.axis(PadAxis.triggerRight)
              : null;
      out.setDown(button, down: down, pressure: pressure);
    }
  }

  double _at(int index) => index < _length ? _values[index] : 0.0;

  void _clear() {
    _values.fillRange(0, _values.length, 0.0);
    _length = 0;
  }
}
