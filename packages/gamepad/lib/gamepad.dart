/// A gamepad, read once per frame.
///
/// ```dart
/// final pad = Gamepad.instance;
/// final snapshot = PadSnapshot();
///
/// // Once per frame, in the frame that uses it:
/// pad.read(snapshot);
/// if (snapshot.down(PadButton.faceSouth)) jump();
/// final throttle = snapshot.pressure(PadButton.triggerRight);
/// ```
///
/// ## Pull, not push
///
/// The API is a snapshot the caller asks for, not a stream of button events, and
/// that is deliberate. A game with a fixed simulation step asks "what is the pad
/// doing now" exactly once per frame; a stream would push edge detection — was
/// this the frame the button went down — into every caller, and every caller
/// would get it slightly differently. It is also the only honest shape for the
/// browser, where `navigator.getGamepads()` *is* a poll and a stream would be a
/// polling loop wearing a costume.
///
/// ## What this package is not
///
/// It knows nothing about games: no actions, no bindings, no vocabulary. What
/// turns `face.south` into "jump" lives in the game layer beside the keyboard's
/// equivalent, for the same reason `mouse_capture` reports deltas and lets
/// `DesktopInput` decide what they mean.
///
/// Deliberately absent: more than one pad at a time, rumble, motion sensors and
/// battery level. Each would widen every signature here for a caller that does
/// not exist.
library;

import 'src/deadzone.dart';
import 'src/gamepad_platform_interface.dart';
import 'src/pad_button.dart';
import 'src/pad_snapshot.dart';

export 'src/deadzone.dart';
export 'src/gamepad_platform_interface.dart'
    show GamepadPlatform, PadConnection, UnsupportedGamepad;
export 'src/pad_button.dart';
export 'src/pad_snapshot.dart';

/// The gamepad a player is holding.
final class Gamepad {
  Gamepad({GamepadPlatform? platform, Deadzone deadzone = const Deadzone()})
      : _platform = platform ?? GamepadPlatform.instance,
        // ignore: prefer_initializing_formals
        deadzone = deadzone;

  /// The one a game uses. Constructed lazily so a build that never touches a
  /// gamepad never touches a platform channel either.
  static final Gamepad instance = Gamepad();

  final GamepadPlatform _platform;

  /// How much of a stick's travel counts as rest.
  ///
  /// Mutable while the game runs, because it is a slider in a settings panel.
  /// Applied on the way out of [read], so no caller can forget it.
  Deadzone deadzone;

  /// Whether this build can see a gamepad at all.
  bool get isSupported => _platform.isSupported;

  Stream<PadConnection> get connectionChanges => _platform.connectionChanges;

  final List<double> _stick = <double>[0.0, 0.0];

  /// Fills [out] with what the pad is doing, dead zone already applied.
  void read(PadSnapshot out) {
    _platform.read(out);
    if (!out.connected) return;

    _stick[0] = out.axis(PadAxis.leftStickX);
    _stick[1] = out.axis(PadAxis.leftStickY);
    deadzone.applyToStick(_stick);
    out
      ..setAxis(PadAxis.leftStickX, _stick[0])
      ..setAxis(PadAxis.leftStickY, _stick[1]);

    _stick[0] = out.axis(PadAxis.rightStickX);
    _stick[1] = out.axis(PadAxis.rightStickY);
    deadzone.applyToStick(_stick);
    out
      ..setAxis(PadAxis.rightStickX, _stick[0])
      ..setAxis(PadAxis.rightStickY, _stick[1]);

    for (final pair in const <List<Object>>[
      <Object>[PadAxis.triggerLeft, PadButton.triggerLeft],
      <Object>[PadAxis.triggerRight, PadButton.triggerRight],
    ]) {
      final axis = pair[0] as PadAxis;
      final button = pair[1] as PadButton;
      final value = deadzone.applyToTrigger(out.axis(axis));
      out.setAxis(axis, value);
      // A trigger's pressure travels with it, so a caller that reads the button
      // rather than the axis still gets the real number. Whether that counts as
      // "pressed" is a threshold, and a threshold is a game's decision.
      if (value > 0.0 || out.down(button)) {
        out.setDown(button, down: out.down(button), pressure: value);
      }
    }
  }

  Future<void> dispose() => _platform.dispose();
}
