import 'package:flutter/foundation.dart';

/// How this build is played.
///
/// **An application used to ask `kIsWeb` and mean three different things by
/// it**, which was true while there were two builds and stopped being true the
/// day a phone appeared. Here rather than in one game because the second game
/// wanted the same three answers, and two copies of a platform list is two
/// copies that disagree the day a platform is added. Every one of those questions is asked here instead,
/// under the name of the thing it is actually asking about:
///
/// * whether there is a pointer to capture, which decides the pause and whether
///   a press is the game's to spend;
/// * whether the camera comes from a captured mouse or from a drag;
/// * whether the player has fingers rather than a keyboard.
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
  ///
  /// It answers a second question as well, and they turn out to be the same one:
  /// **whether a press is the game's to spend.** A captured pointer has nothing
  /// else to do, so a click can mean an action; anywhere else the press is
  /// already busy — it is the only way to look around — and a game that also put
  /// an action on it would spend one on every turn of the camera.
  ///
  /// There was briefly a second name for that second question. It carried one
  /// genre's word for the action, `no_genre_test.dart` said so, and the test was
  /// right twice: the word did not belong here, and neither did the field.
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
}
