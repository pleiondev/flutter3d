import 'package:flutter/widgets.dart';

import 'run_session.dart';

/// When a run is written down without the player asking.
///
/// ## The moments
///
/// * **A checkpoint**, because that is what a checkpoint promises: the place
///   you come back to has moved. The game says when — only it knows what its
///   checkpoints are — by calling [checkpoint].
/// * **A pause**, because a pause is the moment before most of the ways a
///   session ends: the menu opened to quit, the pad put down, the window left.
///   Written on the way in and not on every paused frame.
/// * **The application going to the background**, which on a phone is the
///   only warning before the system ends the process. There is no pause
///   screen between a home-button press and a kill, so a game that saved only
///   on pause lost whatever was played since the last one.
///
/// Not every frame, and not on a timer: a write in the frame budget is a
/// stutter, and a save from the middle of a jump restores into the air.
///
/// Repeated writes of the same run cost nothing — `SaveFile` keeps the digest
/// of the last one — so a player toggling the menu does not rewrite the disk.
final class Autosave with WidgetsBindingObserver {
  Autosave(this.session);

  final RunSession<Object?> session;

  bool _paused = false;
  bool _watching = false;

  /// Tells this whether the game is paused now. Call once per frame, or on
  /// every change; only the step into a pause writes.
  ///
  /// Returns whether it wrote.
  bool paused(bool now) {
    final entering = now && !_paused;
    _paused = now;
    return entering && session.save();
  }

  /// The game passed a checkpoint. Returns whether it wrote.
  bool checkpoint() => session.save();

  /// Starts hearing about the application going to the background.
  void watchLifecycle() {
    if (_watching) return;
    _watching = true;
    WidgetsBinding.instance.addObserver(this);
  }

  /// Stops it. Call from the game's `dispose`.
  void dispose() {
    if (!_watching) return;
    _watching = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      // `inactive` first, because it is the one every platform sends before
      // the others, and on iOS the last one a process is sure to see.
      case AppLifecycleState.inactive ||
          AppLifecycleState.hidden ||
          AppLifecycleState.paused ||
          AppLifecycleState.detached:
        session.save();
      case AppLifecycleState.resumed:
        break;
    }
  }
}
