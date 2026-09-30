/// A dungeon crawl for one to four players sharing one screen.
///
/// The fifth genre, and the first with more than one player in the same
/// world: every monster goes for the hero it can reach first, the heroes
/// share a view none of them can walk out of, and health drains until food
/// puts it back.
///
/// Nothing here imports the renderer or another genre, so all of it runs in
/// a test with no device.
library;

export 'src/crawl_camera.dart';
export 'src/events.dart';
export 'src/framing.dart';
export 'src/generator.dart';
export 'src/hero.dart';
export 'src/hero_class.dart';
export 'src/horde.dart';
export 'src/loot.dart';
export 'src/monster_kind.dart';
export 'src/simulation.dart';
export 'src/volley.dart';
