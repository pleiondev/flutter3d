import 'package:flutter/foundation.dart';
import 'package:pointer_lock/pointer_lock.dart';

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
/// **`kIsWeb` is not asked at all any more, and that is the change worth
/// reading.** It was the wrong question twice over. A browser on a desktop can
/// capture a pointer — it has had `requestPointerLock` for a decade, and the web
/// build of a first-person game was being dragged around like a phone because
/// this file said otherwise. A browser on a phone has fingers, and the same line
/// hid the on-screen stick from every player who opened a demo on one, leaving
/// them a game with no controls at all.
///
/// So each question is now asked of the thing that knows the answer: the pointer
/// capture backend for the first, the platform for the second.
///
/// **A `flutter test` reports itself as Android**, which is `flutter_test`'s own
/// default, so anything here answers as the touch build inside a test. That is
/// harmless today because nothing mounts the game in a test, and it is a trap
/// worth knowing about the day something does: pass the answer in rather than
/// reading it, as `TitleCard` does.
abstract final class Playing {
  /// Whether the pointer can be taken, so the mouse reports motion.
  ///
  /// **Asked of `pointer_lock` rather than of a platform list**, because the
  /// list was a copy of that package's own support and the copy was wrong in
  /// both directions. It claimed Windows and Linux, where the plugin has no
  /// native side, so those builds captured nothing and — because this getter
  /// also turns off drag-look — could not turn the camera at all. And it denied
  /// the browser, which can.
  ///
  /// **This is the gate the game pauses on**, and getting it wrong is a game
  /// that never starts.
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
      !touch && PointerLockPlatform.instance.isSupported;

  /// Whether the player has fingers rather than a keyboard and a mouse.
  ///
  /// **No `kIsWeb` guard**, which is the whole fix: Flutter reports a mobile
  /// browser as `android` or `iOS` — it reads the browser's own operating
  /// system — so a phone that opens the web build now gets the touch controls
  /// that a phone running the native build has always had.
  ///
  /// The cost is stated rather than hidden: a browser whose user agent Flutter
  /// cannot place answers `android`, so an unrecognised desktop browser shows
  /// the on-screen stick. A visible control nobody needs is the better half of
  /// that trade against no controls on a phone, and the keyboard keeps working
  /// underneath it either way.
  static bool get touch =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// Whether the camera is turned by dragging.
  ///
  /// True wherever the pointer cannot be captured — a phone, and a desktop
  /// browser that refuses the lock.
  static bool get dragLook => !capturesPointer;
}
