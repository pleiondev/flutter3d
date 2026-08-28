import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'pointer_lock_platform_interface.dart';

/// Talks to the native side over a method channel and an event channel.
final class MethodChannelPointerLock extends PointerLockPlatform {
  @visibleForTesting
  final MethodChannel methodChannel = const MethodChannel(
    'dev.flutter3d/pointer_lock',
  );

  @visibleForTesting
  final EventChannel eventChannel = const EventChannel(
    'dev.flutter3d/pointer_lock/events',
  );

  /// Platforms with a native implementation.
  ///
  /// Deliberately a whitelist. The mobile platforms have no pointer to capture
  /// and the game falls back to touch sticks there, so the honest answer is
  /// false rather than a `MissingPluginException` at the first call.
  static const Set<TargetPlatform> _supported = <TargetPlatform>{
    TargetPlatform.macOS,
  };

  @override
  bool get isSupported => !kIsWeb && _supported.contains(defaultTargetPlatform);

  Stream<Object?>? _events;

  /// One broadcast subscription feeding both streams below.
  ///
  /// The native side multiplexes deltas and state changes onto a single channel
  /// so the hot path stays one binary message per mouse event; splitting them
  /// here keeps that off the public API.
  Stream<Object?> get _sharedEvents => _events ??= isSupported
      ? eventChannel.receiveBroadcastStream()
      // Nothing is listening on the other side where there is no
      // implementation, and subscribing anyway is a `MissingPluginException`
      // on the first listener — which every caller gets, because
      // `PointerLock` subscribes in its constructor. An empty stream is the
      // honest answer: this platform never changes capture state, which is
      // exactly what [isSupported] already says.
      : const Stream<Object?>.empty();

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
  Future<void> capture() => methodChannel.invokeMethod<void>('capture');

  @override
  Future<void> release() => methodChannel.invokeMethod<void>('release');

  @override
  Future<void> reset() => methodChannel.invokeMethod<void>('reset');
}
