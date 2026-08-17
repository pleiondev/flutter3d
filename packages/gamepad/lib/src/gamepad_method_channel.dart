import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'android_mapping.dart';
import 'darwin_mapping.dart';
import 'gamepad_platform_interface.dart';
import 'pad_mirror.dart';
import 'pad_snapshot.dart';

/// A gamepad behind a platform channel.
///
/// Android, macOS and iOS. The channel carries **what the platform said**, not a
/// normalised pad: the native side forwards values and this side chooses what
/// they mean, in a [PadMirror] per platform. That is deliberate and it is the
/// whole reason these backends could be written without a controller in hand —
/// every trap is in the choosing, and the choosing is in Dart where a test can
/// reach it. Android's traps are which axis a trigger is on and whether the
/// d-pad is a hat; Apple's is a single sign, because `GameController` reports a
/// stick's y positive upwards and everything else here reports it downwards.
///
/// One class rather than three because the channel is the same channel: a
/// stream of platform messages, a mirror to put them in, and a synchronous read
/// out of it. What differs is which mirror.
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
  /// is a `MissingPluginException` for the first listener. Windows and Linux
  /// join this set when somebody writes XInput and evdev, and not before.
  static const Set<TargetPlatform> _supported = <TargetPlatform>{
    TargetPlatform.android,
    TargetPlatform.macOS,
    TargetPlatform.iOS,
  };

  /// Where a gamepad's buttons come from as well as the channel.
  ///
  /// Android alone: it delivers them as `KeyEvent`s and Flutter's embedding maps
  /// them to `gameButtonA` and its neighbours before the framework sees them, so
  /// catching them natively would be a second source of truth for one event.
  /// `GameController` has no such path and reports everything through the
  /// plugin.
  static const Set<TargetPlatform> _buttonsThroughKeyboard =
      <TargetPlatform>{TargetPlatform.android};

  @override
  bool get isSupported => !kIsWeb && _supported.contains(defaultTargetPlatform);

  /// The mirror for this platform, built once and only where it is used.
  late final PadMirror _state = defaultTargetPlatform == TargetPlatform.android
      ? _android
      : DarwinPadState();

  /// Android's mirror, named as well as held: its buttons arrive off the
  /// channel, through the keyboard, and that needs the concrete type.
  final AndroidPadState _android = AndroidPadState();
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
    if (_listening && _buttonsThroughKeyboard.contains(defaultTargetPlatform)) {
      HardwareKeyboard.instance.removeHandler(_onKey);
    }
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
    if (_buttonsThroughKeyboard.contains(defaultTargetPlatform)) {
      HardwareKeyboard.instance.addHandler(_onKey);
    }
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
    // **Asked of the mirror rather than parsed here.** The mirror is the one
    // that knows whether a pad is attached, so reading it on either side of the
    // message is how a connection change is noticed — and nothing has to
    // understand a platform's messages twice to find out.
    //
    // It also means the zeroing happens first and the news second, which is what
    // stops a controller whose battery dies mid-corner from leaving the throttle
    // where it was.
    final was = _state.connected;
    _state.note(event);
    if (_state.connected == was) return;
    _connections.add(
      _state.connected ? PadConnection.connected : PadConnection.disconnected,
    );
  }

  bool _onKey(KeyEvent event) {
    _android.noteKey(event);
    // **Always false, even for a button that was ours.** Returning true marks
    // the event handled and stops it reaching the rest of the application —
    // which is how a player on a television would lose the ability to leave a
    // menu with the same button they entered it with. This is a listener, not a
    // claim.
    return false;
  }
}
