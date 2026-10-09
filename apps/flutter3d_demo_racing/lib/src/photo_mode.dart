import 'package:flutter/services.dart';
import 'package:flutter3d_game_ui/photo_mode.dart';

export 'package:flutter3d_game_ui/photo_mode.dart';

/// This game's photo mode — `N8`, from `flutter3d_game_ui/photo_mode.dart`: the
/// race stopped and a camera to fly round the car.
///
/// **A keyboard, and nothing else.** This game is driven from the keys and
/// never takes the pointer, so the camera is flown and turned from them too:
/// the letters fly, Q and E take it down and up, the arrows turn it at 0.9
/// rad/s — a quarter turn in a little under two seconds, slow enough to line
/// up a shot. They are read as held each frame, because the race's loop is
/// paused and nothing steps its `InputState`.
///
/// **Every key is taken while it is open**: the race is stopped, and a key
/// let through to the car would be held down in it when the race comes back.
/// The chase camera's lens is handed to `PhotoMode.enter`.
PhotoMode chasePhotoMode() => PhotoMode(
  controls: const KeyPhotoControls(
    up: LogicalKeyboardKey.keyE,
    down: LogicalKeyboardKey.keyQ,
    turnRate: 0.9,
  ),
  takesEveryKey: true,
  keysHint:
      'WASD fly · Q/E down and up · arrows turn · Shift faster · '
      '[ ] filter · , . tilt · − = zoom · Enter 2× · '
      'Shift+Enter 4× · P back',
);
