/// Photo mode for a game on flutter3d: the run stopped, a camera to fly, a
/// filter to pick and a picture larger than the window.
///
/// [PhotoMode] holds the engine's `PhotoCamera` and `PhotoFilter` together
/// and owns the keys while it is open; [PhotoBar] is the strip it shows.
/// How a game's own keys fly the camera is a [PhotoControls]: its actions
/// and mouse ([ActionPhotoControls]) or the keyboard read as held
/// ([KeyPhotoControls]).
///
/// A library rather than a plugin: photo mode stops the loop rather than
/// running in it, and the game decides which key opens it.
library;

export 'src/photo_mode/photo_controls.dart';
export 'src/photo_mode/photo_mode.dart';
