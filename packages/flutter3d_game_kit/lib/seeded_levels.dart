/// Levels made from a seed when they are reached: `generated:<seed>` where a
/// level would name its asset, the same seed making the same level.
///
/// A library, not a plugin: it registers nothing with the engine. A game asks
/// [SeededLevels.seedOf] where it opens a level and [SeededLevels.level] for
/// the document when the answer is a seed.
library;

export 'src/seeded_levels/seeded_levels.dart';
