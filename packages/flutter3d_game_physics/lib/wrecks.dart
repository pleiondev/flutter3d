/// Wrecks that burn and sink: [BurningWrecks] places a slick of oil or a heap
/// of timbers in a game's `Elements`, lights it with a blast's fireball, and
/// lets it go once the player is far enough past.
///
/// A library, not a plugin: the elements step and draw the fires, and this
/// registers nothing with the engine.
library;

export 'src/wrecks/burning_wrecks.dart';
