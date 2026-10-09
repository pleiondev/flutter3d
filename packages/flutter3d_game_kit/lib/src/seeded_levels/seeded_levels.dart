import 'package:flutter3d_sim/flutter3d_sim.dart';

/// The rules of the level [depth] places past the first seeded one: nought
/// for the first, one for the next.
typedef DepthRules = LevelRules Function(int depth);

/// Levels nobody built, each made from its seed when it is reached.
///
/// **A seed where an asset path would be.** A level's `next`, a save's
/// current level and a run's first one all name a level by a string; these
/// levels are named `<prefix><seed>` — `generated:7` — so every place that
/// already names a level names one of these unchanged. The same seed makes
/// the same level, so a save opens it again and a run through them replays.
///
/// **Each level names the one after it**, the seed the generator used plus
/// one, so a game reaches as many as the player walks through and makes none
/// ahead of time. [rulesFor] is asked for each with how deep it lies, which is
/// how the levels get harder on the way down.
///
/// ```dart
/// const depths = SeededLevels(rulesFor: crowdedRooms);
///
/// final seed = depths.seedOf(asset);
/// final level = seed == null
///     ? await loadAsset(asset)
///     : await depths.level(seed, first: firstSeed);
/// ```
final class SeededLevels {
  const SeededLevels({required this.rulesFor, this.prefix = defaultPrefix});

  /// The prefix a seeded level is named by unless a game picks its own.
  static const String defaultPrefix = 'generated:';

  /// What a seeded level's name starts with where an asset path would be.
  final String prefix;

  /// The rules for the level [DepthRules] places at a depth.
  final DepthRules rulesFor;

  /// The name of the level [seed] makes: the first one a game opens.
  String first(int seed) => '$prefix$seed';

  /// The seed [asset] names, or null when it is an asset of its own.
  int? seedOf(String asset) => asset.startsWith(prefix)
      ? int.tryParse(asset.substring(prefix.length))
      : null;

  /// The level [seed] names, made off the drawing thread, with the next one
  /// after it named — or a [StateError] saying why the generator made none.
  ///
  /// [first] is the seed the run started the levels at, so the depth
  /// [rulesFor] is asked about is `seed - first`.
  Future<Level> level(int seed, {required int first}) async {
    final made = await generateLevelOffThread(
      rulesFor(seed - first),
      seed: seed,
    );
    final level = made.level;
    if (level == null) throw StateError(made.says);
    return Level.fromJson(<String, Object?>{
      ...level.toJson(),
      'next': '$prefix${made.seed + 1}',
    });
  }
}
