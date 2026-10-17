/// Wrecks that burn and sink: [BurningWrecks] places a slick of oil or a heap
/// of timbers in a game's elements, lights it with a blast's fireball, lets
/// it go once the player is far enough past, and publishes each as a
/// [BurningWreck]; [WreckLooks] draws the slicks from what was published.
/// [FuelCell] says which crash breaks a car's tank, by the test it was
/// built to pass.
///
/// A library, not a plugin: the elements step the fires and their view
/// draws them, and this registers nothing with the engine.
library;

export 'src/wrecks/burning_wrecks.dart';
export 'src/wrecks/fuel_cell.dart';
