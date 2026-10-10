import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart'
    show ShooterActions;
import 'package:flutter3d_game_ui/photo_mode.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

export 'package:flutter3d_game_ui/photo_mode.dart';

/// The crypt's photo mode — `N8`, from `flutter3d_game_ui/photo_mode.dart`: the run
/// stopped, a camera to fly out of the player's eyes.
///
/// What is this game's is which keys fly it. **The run's own input, read
/// rather than stepped**: the loop is paused, so nothing drains
/// `InputState`; the keys the player walks with fly the camera instead,
/// jump taking it up and crouch down, and sprint is a faster camera as it is
/// a faster walk. The camera turns as the player's head does under the same
/// mouse: the game's own look sensitivity, radians a pixel.
PhotoMode cryptPhotoMode() => PhotoMode(
  controls: const ActionPhotoControls(
    up: GameAction.jump,
    down: ShooterActions.crouch,
    sensitivity: 0.0022,
  ),
);
