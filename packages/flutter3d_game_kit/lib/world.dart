/// The world around the part a game simulates: [Daylight], the hour of the
/// day with its sun, moon and physical sky, and [Horizon], the ground and a
/// level surface going on from the simulated square's edge out to the
/// horizon.
///
/// A library, not a plugin: a game moves the day and adds the horizon where
/// it builds its scene, and nothing here registers with the engine. The
/// water of `flutter3d_effects` is lit by the day with `lightWater`, from
/// `flutter3d_game_physics`' `elements.dart`.
library;

export 'src/world/daylight.dart';
export 'src/world/horizon.dart';
