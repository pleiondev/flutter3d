/// The elements of `flutter3d_effects`, met by the rest of a game: the fires
/// and the water `flutter3d_effects`' `PhysicsHearing` reports, played as [ElementSounds] from
/// [ElementCues], and the water lit by the hour of the day
/// ([DaylightOnWater.lightWater]).
///
/// A library, not a plugin: a game plays the elements on its own audio scene
/// and lights the water where it moves the day, and nothing here registers
/// with the engine.
library;

export 'src/elements/daylight_on_water.dart';
export 'src/elements/element_sounds.dart';
