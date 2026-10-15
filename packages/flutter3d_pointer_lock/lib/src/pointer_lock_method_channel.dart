import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'pointer_lock_platform_interface.dart';

/// Talks to the native side over a method channel and an event channel.
final class MethodChannelPointerLock extends PointerLockPlatform {
  @visibleForTesting
  final MethodChannel methodChannel = const MethodChannel(
    'dev.flutter3d/flutter3d_pointer_lock',
  );

  @visibleForTesting
  final EventChannel eventChannel = const EventChannel(
    'dev.flutter3d/flutter3d_pointer_lock/events',
  );

  /// Desktops, where a pointer is always there to capture.
  static const Set<TargetPlatform> _desktops = <TargetPlatform>{
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  };

  /// Phones and tablets, where a pointer is there only while a mouse is.
  ///
  /// Android captures through `View.requestPointerCapture` (API 26 on), and
  /// iPadOS through `prefersPointerLocked` with the motion read from
  /// `GCMouse`. Both answer "unsupported" until the native side has said a
  /// mouse is connected, which arrives as a `bool` on the event channel when
  /// the stream is first listened to and again whenever a mouse comes or
  /// goes. A phone with no mouse keeps answering false, so a game still shows
  /// its touch controls there.
  static const Set<TargetPlatform> _mobiles = <TargetPlatform>{
    TargetPlatform.android,
    TargetPlatform.iOS,
  };

  /// Whether this platform has a native side at all. Deliberately a
  /// whitelist: a platform without one answers false rather than raising a
  /// `MissingPluginException` at the first call.
  bool get _hasNativeSide =>
      !kIsWeb &&
      (_desktops.contains(defaultTargetPlatform) ||
          _mobiles.contains(defaultTargetPlatform));

  /// The last answer a mobile native side gave about its mouse.
  bool _mouseConnected = false;

  @override
  bool get isSupported {
    if (kIsWeb) return false;
    if (_desktops.contains(defaultTargetPlatform)) return true;
    return _mobiles.contains(defaultTargetPlatform) && _mouseConnected;
  }

  final StreamController<bool> _supportChanges =
      StreamController<bool>.broadcast();

  @override
  Stream<bool> get supportChanges {
    // Reading the shared stream is what subscribes the mouse listener below,
    // so a caller that asks for this first still hears the first answer.
    _sharedEvents;
    return _supportChanges.stream;
  }

  Stream<Object?>? _events;

  /// One broadcast subscription feeding the streams below.
  ///
  /// The native side multiplexes deltas, state changes and, on a phone or a
  /// tablet, whether a mouse is connected onto a single channel so the hot
  /// path stays one binary message per mouse event; splitting them here keeps
  /// that off the public API.
  Stream<Object?> get _sharedEvents => _events ??= _openEvents();

  Stream<Object?> _openEvents() {
    if (!_hasNativeSide) {
      // Nothing is listening on the other side where there is no
      // implementation, and subscribing anyway is a `MissingPluginException`
      // on the first listener — which every caller gets, because
      // `PointerLock` subscribes in its constructor. An empty stream is the
      // honest answer: this platform never changes capture state, which is
      // exactly what [isSupported] already says.
      return const Stream<Object?>.empty();
    }
    final events = eventChannel.receiveBroadcastStream();
    if (_mobiles.contains(defaultTargetPlatform)) {
      // Held for the life of the channel rather than tied to a listener of
      // [supportChanges]: [isSupported] has to follow the mouse whether or
      // not anybody is watching it change.
      events.where((Object? event) => event is bool).listen((Object? event) {
        final connected = event! as bool;
        if (connected == _mouseConnected) return;
        _mouseConnected = connected;
        _supportChanges.add(connected);
      });
    }
    return events;
  }

  @override
  Stream<Offset> get deltas => _sharedEvents
      .where((Object? event) => event is Float64List)
      .map((Object? event) {
        final values = event! as Float64List;
        return Offset(values[0], values[1]);
      });

  @override
  Stream<CaptureState> get stateChanges =>
      _sharedEvents.where((Object? event) => event is int).map((Object? event) {
        return event == 1 ? CaptureState.captured : CaptureState.released;
      });

  @override
  Future<void> capture() => _call('capture');

  @override
  Future<void> release() => _call('release');

  @override
  Future<void> reset() => _call('reset');

  /// Calls [method] on the native side, and answers nothing where that side
  /// does not have it.
  ///
  /// **A missing method is a no-op, never a throw.** A native side that has
  /// no handler for [method] — an embedding that did not register the
  /// plugin, or a side that predates a method a later minor adds — answers
  /// with a `MissingPluginException`, and the engine pins this package at
  /// `^0.5.0`, so a game cannot choose the minor its players get. The
  /// capture state then stays where it was, which [stateChanges] already
  /// reports, and the game keeps its own cursor.
  Future<void> _call(String method) async {
    try {
      await methodChannel.invokeMethod<void>(method);
    } on MissingPluginException {
      return;
    }
  }
}
