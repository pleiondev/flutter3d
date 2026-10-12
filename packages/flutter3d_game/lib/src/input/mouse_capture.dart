/// The captured mouse, in the game layer's own words.
///
/// **Why the game has its own type for it.** The capture itself is
/// `flutter3d_pointer_lock`, a package on its own version line below 1.0 that may
/// change its API in any minor. `DesktopInput` named its `PointerLock` in its
/// constructor, so such a change would have reached every game that passed
/// one. [MouseCapture.platform] is now where the input reaches the plugin;
/// no public signature of this package names it.
library;

import 'dart:ui' show Offset;

import 'package:flutter3d_pointer_lock/flutter3d_pointer_lock.dart';

/// Taking the pointer, so the mouse reports motion instead of moving a
/// cursor, and giving it back.
///
/// **An `abstract base class` a test or a host extends**: a capture a test
/// tells to change its mind, or one a remote viewer drives.
/// [MouseCapture.platform] is the platform's own.
abstract base class MouseCapture {
  /// A capture a subclass describes.
  const MouseCapture();

  /// The platform's pointer capture: one for the whole process, as the
  /// platform has one pointer.
  factory MouseCapture.platform() => _PlatformCapture(PointerLock.instance);

  /// Whether the platform can take the pointer at all.
  bool get isSupported => true;

  /// Whether the pointer is taken now.
  bool get isCaptured;

  /// Each change of [isCaptured]: true when the pointer is taken, false when
  /// it is given back, by the player or by the system taking focus away.
  Stream<bool> get changes;

  /// The motion since the last call, in logical pixels, and forgets it.
  Offset drainDelta();

  /// Asks for the pointer. A browser grants it only after a user gesture.
  Future<void> capture();

  /// Gives the pointer back.
  Future<void> release();
}

/// The platform's capture, through `flutter3d_pointer_lock`.
final class _PlatformCapture extends MouseCapture {
  _PlatformCapture(this._lock);

  final PointerLock _lock;

  @override
  bool get isSupported => _lock.isSupported;

  @override
  bool get isCaptured => _lock.isCaptured;

  @override
  Stream<bool> get changes => _lock.onStateChanged.map(
    (CaptureState state) => state == CaptureState.captured,
  );

  @override
  Offset drainDelta() => _lock.drainDelta();

  @override
  Future<void> capture() => _lock.capture();

  @override
  Future<void> release() => _lock.release();
}
