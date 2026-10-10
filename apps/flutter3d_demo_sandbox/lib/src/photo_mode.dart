import 'package:flutter/services.dart';
import 'package:flutter3d_game_ui/photo_mode.dart';

export 'package:flutter3d_game_ui/photo_mode.dart';

/// The sandbox's photo mode — `N8`, from `flutter3d_game_ui/photo_mode.dart`: the
/// world stopped and a camera to fly through the engine's default lens,
/// which is what the sandbox has always drawn through.
///
/// **The keys are read as held, not stepped.** The run is not stepped while
/// a picture is lined up, so nothing would drain an `InputState`; the
/// walking keys fly the camera, Space and C take it up and down, and a drag
/// turns it through `PhotoMode.turn` as it turns the eye. Every key is taken
/// while it is open: the game's own keys dig, place and pour into a world
/// that is stopped.
PhotoMode sandboxPhotoMode() => PhotoMode(
  controls: const KeyPhotoControls(
    up: LogicalKeyboardKey.space,
    down: LogicalKeyboardKey.keyC,
  ),
  takesEveryKey: true,
  keysHint:
      'WASD fly · drag to look · Space/C up and down · Shift faster '
      '· [ ] filter · , . tilt · − = zoom · Enter 2× · '
      'Shift+Enter 4× · P back',
);
