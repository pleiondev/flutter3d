import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter3d_game_ui/photo_mode.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'lens.dart';

export 'package:flutter3d_game_ui/photo_mode.dart';

/// This game's photo mode — `N8`, from `flutter3d_game_ui/photo_mode.dart`: the
/// world stopped and a camera to fly.
///
/// What is this game's is which keys do what, and how the camera meets this
/// game's lens. **The world's own input, read rather than stepped**: the
/// loop is paused, so nothing drains `InputState`; the keys the player
/// already has for running fly the camera instead, and the jump and the drop
/// take it up and down. The view turns at the follow camera's own mouse
/// sensitivity, the rate the player's hand already knows.
PhotoMode runnerPhotoMode() => PhotoMode(
  controls: const ActionPhotoControls(
    up: GameAction.jump,
    down: PlatformerActions.dropThrough,
    sensitivity: 0.0035,
  ),
  lens: ascentLens.base,
);
