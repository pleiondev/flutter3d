import 'package:flutter/foundation.dart';

/// How this build is played.
///
/// **The application used to ask `kIsWeb` and mean three different things by
/// it**, which was true while there were two builds and stopped being true the
/// day a phone appeared. Every one of those questions is asked here instead,
/// under the name of the thing it is actually asking about:
///
/// * whether there is a pointer to capture, which decides the pause;
/// * whether the camera comes from a captured mouse or from a drag;
/// * whether a press on the screen is a dash or a finger.
///
/// A browser and a phone agree about the first two and disagree about the
/// third, and `kIsWeb` could not say so.
///
/// **A `flutter test` reports itself as Android**, which is `flutter_test`'s own
/// default, so anything here answers as the touch build inside a test. That is
/// harmless today because nothing mounts the game in a test, and it is a trap
/// worth knowing about the day something does: pass the answer in rather than
/// reading it, as `TitleCard` does.
abstract final class Playing {
  /// Whether the pointer can be taken, so the mouse reports motion.
  ///
  /// `mouse_capture` serves macOS and nothing else; a browser has no pointer to
  /// take and a phone has no pointer at all. **This is the gate the game pauses
  /// on**, and getting it wrong is a game that never starts.
  static bool get capturesPointer =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  /// Whether the player has a keyboard and a mouse rather than a screen.
  static bool get touch =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Whether the camera is turned by dragging.
  ///
  /// True wherever the pointer cannot be captured — a browser and a phone both.
  static bool get dragLook => !capturesPointer;

  /// Whether pressing the screen dashes.
  ///
  /// True on the desktop only. In a browser a drag is the only way to look
  /// around and cannot also spend a dash; on a phone every tap would be one.
  static bool get dashOnPointer => capturesPointer;
}
