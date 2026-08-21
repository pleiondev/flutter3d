import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'gamepad_platform_interface.dart';
import 'pad_snapshot.dart';
import 'standard_mapping.dart';

/// The gamepad a browser build gets.
GamepadPlatform defaultGamepadPlatform() => WebGamepad();

/// A gamepad read from `navigator.getGamepads()`.
///
/// **Pure Dart, no native code**, and that is not a shortcut: the browser
/// already normalises controllers to the W3C standard mapping, which is the same
/// physical vocabulary this package uses, so there is nothing for a plugin to
/// do. [StandardGamepad] holds the table and the arithmetic; this class finds the
/// pad and asks it.
///
/// ## The array freezes, it does not empty
///
/// The defect a browser backend is most likely to ship. `getGamepads()` keeps
/// returning the **last values it saw** while the page is in the background, so
/// a player who switches tabs mid-corner comes back to a car that never stopped
/// accelerating — and the game, polling happily, has no way to tell a stuck
/// array from a held trigger.
///
/// So focus is watched, and a page that is not focused reports a pad that is
/// attached and doing nothing. Not disconnected: the controller is still there,
/// the player is not, and everything downstream releases through the ordinary
/// path when the buttons stop being down.
///
/// ## And it is invisible until a button is pressed
///
/// A browser hides gamepads from a page that has never seen one used, as a
/// fingerprinting defence. There is nothing to do about it and no way to detect
/// it, which is why the acceptance checklist for this package says so: on the
/// web, press a button before expecting a pad.
final class WebGamepad extends GamepadPlatform {
  WebGamepad() {
    _listen('gamepadconnected', (web.Event _) => _announce(true));
    _listen('gamepaddisconnected', (web.Event _) => _announce(false));
    // Both, because they answer different questions: `blur` is another window
    // taking the keyboard, `visibilitychange` is this tab going behind another
    // one. A page can be hidden without ever blurring and blurred without being
    // hidden, and either is enough to stop the array from updating.
    _listen('blur', (web.Event _) => _awake = false);
    _listen('focus', (web.Event _) => _awake = true);
    _listen('visibilitychange', (web.Event _) => _awake = !web.document.hidden);
  }

  final StreamController<PadConnection> _connections =
      StreamController<PadConnection>.broadcast();

  final List<double> _axes = <double>[];
  final List<bool> _pressed = <bool>[];
  final List<double> _values = <double>[];
  final List<_Listener> _listeners = <_Listener>[];

  bool _awake = true;

  @override
  bool get isSupported => true;

  @override
  Stream<PadConnection> get connectionChanges => _connections.stream;

  @override
  void read(PadSnapshot out) {
    final pad = _current();
    if (pad == null) {
      out.disconnect();
      return;
    }
    if (!_awake) {
      // Attached and doing nothing. See the class doc: the alternative is the
      // last frame before the tab went away, repeated for as long as it stays
      // away.
      out.clear();
      out.connected = true;
      return;
    }

    // Copied into lists that live as long as this object, because `read` runs
    // once per frame for as long as the game does and the interop arrays are
    // fresh every call.
    _axes.clear();
    for (final value in pad.axes.toDart) {
      _axes.add(value.toDartDouble);
    }

    _pressed.clear();
    _values.clear();
    for (final button in pad.buttons.toDart) {
      _pressed.add(button.pressed);
      _values.add(button.value.toDouble());
    }

    StandardGamepad.apply(
      out,
      axisValues: _axes,
      pressed: _pressed,
      values: _values,
    );
  }

  @override
  Future<void> dispose() async {
    for (final listener in _listeners) {
      web.window.removeEventListener(listener.type, listener.callback);
    }
    _listeners.clear();
    await _connections.close();
  }

  /// The first pad the browser will vouch for.
  ///
  /// **Standard mapping only**, and a non-standard pad is treated as no pad.
  /// That looks harsh and is the careful answer: without the mapping the indices
  /// come from whatever the driver felt like, so index three might be a trigger,
  /// and binding it would write `pad:face.north` into the player's file for
  /// something that is not a face button. This package deliberately has no
  /// mapping database to resolve that with, and a permanent identifier that
  /// means the wrong thing is worse than a pad that does not answer.
  web.Gamepad? _current() {
    final pads = web.window.navigator.getGamepads().toDart;
    for (final pad in pads) {
      if (pad == null) continue;
      if (!pad.connected) continue;
      if (pad.mapping != 'standard') continue;
      return pad;
    }
    return null;
  }

  void _announce(bool connected) => _connections.add(
        connected ? PadConnection.connected : PadConnection.disconnected,
      );

  void _listen(String type, void Function(web.Event) handler) {
    final callback = handler.toJS;
    _listeners.add(_Listener(type, callback));
    web.window.addEventListener(type, callback);
  }
}

/// What was attached, so it can be detached. A closure converted to JavaScript
/// twice is two different functions, and the second would not remove the first.
final class _Listener {
  _Listener(this.type, this.callback);

  final String type;
  final web.EventListener callback;
}
