import 'pad_button.dart';
import 'pad_snapshot.dart';

/// The browser's Standard Gamepad mapping, as a table.
///
/// A web gamepad arrives as two lists of numbers and a promise about what the
/// indices mean. The promise is the W3C's *standard mapping*, which every
/// browser applies to every controller it recognises, and this file is that
/// promise written down: seventeen buttons and four axes, in the order the
/// specification fixes them.
///
/// **Separated from the browser on purpose.** Nothing here imports
/// `dart:js_interop`, so the part that is easy to get wrong — an index off by
/// one, a trigger read as a face button, a d-pad that is buttons here and an
/// axis somewhere else — is checked by an ordinary unit test on the VM. What
/// stays behind the interop boundary is finding the pad and asking it, which is
/// four calls and no arithmetic.
///
/// ## Triggers are buttons here, not axes
///
/// The single most common way this is written wrongly. In the standard mapping a
/// trigger is **button 6 or 7 with a `value` between nought and one** — it is not
/// in the axis list at all, and a backend that looked for it there would find the
/// right stick. [PadAxis.triggerLeft] and [PadAxis.triggerRight] are filled in
/// from those two button values, because on the other side of this package a
/// trigger is an axis and a button both.
abstract final class StandardGamepad {
  /// What each button index means, or null where the specification names
  /// nothing.
  ///
  /// Index order is the specification's and cannot be rearranged: the face
  /// buttons are bottom, right, left, top — which is exactly the physical
  /// vocabulary this package uses, and the reason the two need no translation.
  static const List<PadButton?> buttons = <PadButton?>[
    PadButton.faceSouth, // 0
    PadButton.faceEast, // 1
    PadButton.faceWest, // 2
    PadButton.faceNorth, // 3
    PadButton.shoulderLeft, // 4
    PadButton.shoulderRight, // 5
    PadButton.triggerLeft, // 6, analogue
    PadButton.triggerRight, // 7, analogue
    PadButton.back, // 8, Select on older pads
    PadButton.start, // 9
    PadButton.stickLeftClick, // 10
    PadButton.stickRightClick, // 11
    PadButton.dpadUp, // 12
    PadButton.dpadDown, // 13
    PadButton.dpadLeft, // 14
    PadButton.dpadRight, // 15
    PadButton.guide, // 16, present on most pads and not on all
  ];

  /// What each axis index means. Sticks only — see the class doc on triggers.
  static const List<PadAxis?> axes = <PadAxis?>[
    PadAxis.leftStickX,
    PadAxis.leftStickY,
    PadAxis.rightStickX,
    PadAxis.rightStickY,
  ];

  static const int _triggerLeftButton = 6;
  static const int _triggerRightButton = 7;

  /// Writes a browser gamepad's two lists into [out].
  ///
  /// [pressed] and [values] are the `pressed` and `value` of each
  /// `GamepadButton`, in index order. Both, because they are not redundant: a
  /// digital button's value is its bit, and a trigger's value is its travel
  /// while its `pressed` is a threshold the browser chose. This package hands
  /// both on and lets the game decide, which is why `PadInput` ignores the
  /// browser's threshold and applies its own.
  ///
  /// Lists shorter than the table are ordinary — a pad with no middle button
  /// reports sixteen — and lists longer than it are ordinary too, because paddles
  /// and touchpads sit past the end of the standard mapping and this package
  /// deliberately names none of them.
  /// **Every named control is written on every call**, which is what makes it
  /// safe to hand the same snapshot back frame after frame. Clearing it first
  /// would look safer and prove nothing — the test that reuses a snapshot passes
  /// either way, so the clear would be a line no mutation can reach. The
  /// invariant is doing the work, and the test names it.
  static void apply(
    PadSnapshot out, {
    required List<double> axisValues,
    required List<bool> pressed,
    required List<double> values,
  }) {
    out.connected = true;

    for (var i = 0; i < buttons.length; i++) {
      final button = buttons[i];
      if (button == null) continue;
      final down = i < pressed.length && pressed[i];
      final value = i < values.length ? values[i] : (down ? 1.0 : 0.0);
      final analogue =
          i == _triggerLeftButton || i == _triggerRightButton;
      // Pressure is recorded only where it says something a bit does not.
      // Writing it for every button would put seventeen entries in a map that
      // is read once per frame, for two that are analogue.
      out.setDown(button, down: down, pressure: analogue ? value : null);
    }

    for (var i = 0; i < axes.length; i++) {
      final axis = axes[i];
      if (axis == null) continue;
      out.setAxis(axis, i < axisValues.length ? axisValues[i] : 0.0);
    }

    out
      ..setAxis(PadAxis.triggerLeft, _valueAt(values, _triggerLeftButton))
      ..setAxis(PadAxis.triggerRight, _valueAt(values, _triggerRightButton));
  }

  static double _valueAt(List<double> values, int index) =>
      index < values.length ? values[index] : 0.0;
}
