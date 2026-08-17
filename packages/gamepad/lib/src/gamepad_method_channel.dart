import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'android_mapping.dart';
import 'gamepad_platform_interface.dart';
import 'pad_snapshot.dart';

/// A gamepad behind a platform channel.
///
/// Android for now. The channel carries **raw events**, not a normalised pad:
/// the native side reports which device appeared and which axes it says it has,
/// then forwards each `MotionEvent` untouched, and [AndroidPadState] does every
/// piece of arithmetic and every choice. That is deliberate and it is the whole
/// reason this backend could be written at all without a controller in hand —
/// the traps are all in the choosing (which axis is a trigger, whether the d-pad
/// is a hat) and the choosing is in Dart, where a test can reach it.
///
/// ## Pushed into a mirror, read out synchronously
///
/// Android has **no way to ask** a gamepad what it is doing: input arrives as
/// events aimed at the focused view. So the events fill a mirror and [read]
/// copies it. [GamepadPlatform.read] stays synchronous, which is what a caller
/// reading inside a frame needs, and the value is as fresh as the last event
/// delivered — which is what a poll would have given anyway.
///
/// A method channel would not do: an `invokeMethod` is a future, and a
/// simulation cannot take a value that is stale by an unknown amount.
final class MethodChannelGamepad extends GamepadPlatform {
  @visibleForTesting
  final EventChannel eventChannel =
      const EventChannel('dev.flutter3d/gamepad/events');

  /// Platforms with a native implementation.
  ///
  /// A **whitelist**, never try-and-see: subscribing where nothing is listening
  /// is a `MissingPluginException` for the first listener, and this class
  /// subscribes in its constructor. macOS and iOS join this set when their
  /// `GameController` side is written, and not before.
  static const Set<TargetPlatform> _supported = <TargetPlatform>{
    TargetPlatform.android,
  };

  @override
  bool get isSupported => !kIsWeb && _supported.contains(defaultTargetPlatform);

  final AndroidPadState _state = AndroidPadState();
  final StreamController<PadConnection> _connections =
      StreamController<PadConnection>.broadcast();

  StreamSubscription<Object?>? _subscription;
  bool _listening = false;

  @override
  Stream<PadConnection> get connectionChanges {
    _ensureListening();
    return _connections.stream;
  }

  @override
  void read(PadSnapshot out) {
    _ensureListening();
    _state.fill(out);
  }

  @override
  Future<void> dispose() async {
    if (_listening) HardwareKeyboard.instance.removeHandler(_onKey);
    _listening = false;
    await _subscription?.cancel();
    _subscription = null;
    await _connections.close();
  }

  /// Attaches on first use, and **not in the constructor**.
  ///
  /// Two reasons, and the second one bit. `isSupported` promises to answer
  /// without opening a channel, and an object that opened one merely by existing
  /// would break that for anybody who only asked. And this object is built during
  /// static initialisation — possibly before `runApp` — where there is no
  /// `HardwareKeyboard` to add a handler to and no messenger to talk over.
  ///
  /// It also makes the package testable at all: **a `flutter test` on the desktop
  /// reports itself as Android**, which is `flutter_test`'s own default, so a
  /// constructor that subscribed would hand every unrelated test a
  /// `MissingPluginException` from a plugin that is not there.
  void _ensureListening() {
    if (_listening || !isSupported) return;
    _listening = true;
    _subscription = eventChannel.receiveBroadcastStream().listen(_onEvent);
    // Buttons arrive through Flutter's own keyboard on Android, already mapped
    // to `gameButtonA` and its neighbours — see [AndroidPadState]. Handled here
    // rather than natively so there is one source of truth for one event.
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  /// Handles one event from the native side.
  ///
  /// The payload's **type** says what it is, which is `mouse_capture`'s trick
  /// and for its reason: a motion sample is the hot path and deserves one typed
  /// list rather than a map with a discriminator in it.
  ///
  /// * [Float64List] — a motion sample, `[deviceId, axis, value, …]`.
  /// * [Map] — a device appeared or went away, or the application lost focus.
  @visibleForTesting
  void handleEvent(Object? event) => _onEvent(event);

  void _onEvent(Object? event) {
    if (event is Float64List) {
      _state.noteMotion(event);
      return;
    }
    if (event is! Map) return;
    switch (event['event']) {
      case 'connected':
        final id = event['device'];
        if (id is! int) return;
        final axes = event['axes'];
        _state.connect(
          deviceId: id,
          axes: axes is List ? axes.whereType<int>() : const <int>[],
        );
        _connections.add(PadConnection.connected);
      case 'disconnected':
        // Zeroed by the state itself before anybody is told, so a controller
        // whose battery dies mid-corner cannot leave the throttle where it was.
        _state.disconnect();
        _connections.add(PadConnection.disconnected);
      case 'relaxed':
        // The application went to the background. The pad is still attached and
        // the player is not: everything downstream releases through the ordinary
        // path once the buttons stop being down.
        _state.relax();
    }
  }

  bool _onKey(KeyEvent event) {
    _state.noteKey(event);
    // **Always false, even for a button that was ours.** Returning true marks
    // the event handled and stops it reaching the rest of the application —
    // which is how a player on a television would lose the ability to leave a
    // menu with the same button they entered it with. This is a listener, not a
    // claim.
    return false;
  }
}
