import 'dart:ui' show Offset;

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'platform_default.dart';

/// Whether the pointer is currently held.
///
/// Two states rather than a bool, because the interesting event is *who*
/// released it: a game needs to tell "the player pressed Escape" from "the
/// system took focus away and the capture is gone", and the second one usually
/// means opening a pause menu.
///
/// **Closed for good**: captured or released: a yes or a no, kept as two states
/// for who released it. No member can be added without changing what the type
/// means, so it stays an enum and a `switch` over it may name every case.
enum CaptureState {
  /// The cursor is visible and free; no motion is accumulated.
  released,

  /// The cursor is hidden and held in place, and its motion arrives as
  /// deltas.
  captured,
}

/// The platform side of pointer capture.
///
/// Split out so the accumulator and the state machine above it can be tested
/// without a platform channel — which matters more than usual here, because the
/// parts that are easy to get wrong (dropping a delta, missing a release) are
/// all on the Dart side.
abstract base class PointerLockPlatform extends PlatformInterface {
  /// Registers the subclass with the platform token, so [instance] accepts
  /// it.
  PointerLockPlatform() : super(token: _token);

  static final Object _token = Object();

  /// Chosen by conditional export: a method channel outside the browser, the
  /// Pointer Lock API inside one. See `platform_default.dart` for why that is a
  /// compile-time choice rather than a plugin registration.
  static PointerLockPlatform _instance = defaultPointerLockPlatform();

  /// The implementation every `PointerLock` talks to: process-wide, set
  /// once by the platform package at registration.
  ///
  /// Setting it replaces the platform, which is how a test installs a fake;
  /// the setter throws an `AssertionError` for an implementation that was
  /// not built through the [PointerLockPlatform] constructor (one that uses
  /// `implements` rather than `extends`).
  static PointerLockPlatform get instance => _instance;

  static set instance(PointerLockPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// False where there is no pointer to capture: a phone or a tablet with no
  /// mouse connected, a touch screen in a browser, and a platform the plugin
  /// has no implementation for.
  bool get isSupported;

  /// Each change of [isSupported] after the first read, as its new value.
  ///
  /// A desktop never changes its answer and keeps the default, a stream that
  /// never fires. A phone or a tablet answers true while a mouse is
  /// connected, and its native side says so a moment after the first listen,
  /// so a game that reads [isSupported] at its first frame and listens here
  /// shows its touch controls until the mouse is known and hides them when it
  /// is.
  Stream<bool> get supportChanges => const Stream<bool>.empty();

  /// Motion reported since the last capture, in logical pixels.
  ///
  /// A stream rather than a callback so the accumulator above can be replaced
  /// without touching this layer.
  Stream<Offset> get deltas;

  /// Each change of capture state the platform reports, including releases
  /// nobody asked for: Escape, a lost focus, a switched tab.
  Stream<CaptureState> get stateChanges;

  /// Asks the platform to hide the cursor and hold it in place.
  ///
  /// The answer arrives on [stateChanges]; a refused capture reports nothing
  /// and leaves the state [CaptureState.released].
  Future<void> capture();

  /// Asks the platform to show the cursor again and stop reporting motion.
  ///
  /// The change arrives on [stateChanges] like any other.
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
