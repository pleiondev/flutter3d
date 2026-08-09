import 'dart:ui' show Offset;

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'mouse_capture_method_channel.dart';

/// Whether the pointer is currently held.
///
/// Two states rather than a bool, because the interesting event is *who*
/// released it: a game needs to tell "the player pressed Escape" from "the
/// system took focus away and the capture is gone", and the second one usually
/// means opening a pause menu.
enum CaptureState {
  released,
  captured,
}

/// The platform side of pointer capture.
///
/// Split out so the accumulator and the state machine above it can be tested
/// without a platform channel — which matters more than usual here, because the
/// parts that are easy to get wrong (dropping a delta, missing a release) are
/// all on the Dart side.
abstract base class MouseCapturePlatform extends PlatformInterface {
  MouseCapturePlatform() : super(token: _token);

  static final Object _token = Object();

  static MouseCapturePlatform _instance = MethodChannelMouseCapture();

  static MouseCapturePlatform get instance => _instance;

  static set instance(MouseCapturePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// False where there is no pointer to capture — the mobile platforms — and
  /// where the plugin has no implementation yet.
  bool get isSupported;

  /// Motion reported since the last capture, in logical pixels.
  ///
  /// A stream rather than a callback so the accumulator above can be replaced
  /// without touching this layer.
  Stream<Offset> get deltas;

  Stream<CaptureState> get stateChanges;

  Future<void> capture();

  Future<void> release();

  /// Puts the platform back to an uncaptured state regardless of what it thinks
  /// it is doing.
  ///
  /// Exists for exactly one situation: a hot restart while the pointer was
  /// captured. The Dart side has been replaced and remembers nothing, but the
  /// native side kept running and still has the cursor hidden. Without this the
  /// developer is left with no cursor and no way to ask for it back.
  Future<void> reset();
}
