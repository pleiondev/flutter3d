import 'package:flutter3d_sim/flutter3d_sim.dart';

/// The depths: levels past the sanctum that nobody built, each made from its
/// seed when it is reached — `generated:<seed>` where a level would name its
/// asset. The same seed, the same level, so a save in one opens it again
/// and a run through them replays.
abstract final class Depths {
  /// What a level of the depths is called where an asset path would be.
  static const String prefix = 'generated:';

  /// The first of them, reached from the ending.
  static String first(int seed) => '$prefix$seed';

  /// The seed [asset] names, or null when it is an asset of its own.
  static int? seedOf(String asset) => asset.startsWith(prefix)
      ? int.tryParse(asset.substring(prefix.length))
      : null;

  /// How deep the depths go before they repeat their rules, and get more
  /// crowded on the way: a level more of monsters every few seeds down.
  static LevelRules rulesFor(int depth) => LevelRules(
    columns: 4,
    rows: 3,
    density: 0.65,
    clutter: 2,
    name: 'The Depths, ${depth + 1}',
    materials: const <String, Map<String, Object?>>{
      'floor': <String, Object?>{
        'baseColor': <num>[0.3, 0.29, 0.27, 1.0],
        'roughness': 0.9,
      },
      'wall': <String, Object?>{
        'baseColor': <num>[0.38, 0.35, 0.32, 1.0],
        'roughness': 0.85,
      },
      'ceiling': <String, Object?>{
        'baseColor': <num>[0.18, 0.17, 0.16, 1.0],
        'roughness': 0.95,
      },
    },
    perRoom: <({Map<String, Object?> entity, int count})>[
      (
        entity: const <String, Object?>{'type': 'monster', 'kind': 'runner'},
        count: 1 + depth ~/ 3,
      ),
      (
        entity: const <String, Object?>{
          'type': 'pickup',
          'gives': 'health',
          'amount': 25,
        },
        count: 1,
      ),
    ],
  );

  /// The level [seed] names, with the next of the depths after it — or why
  /// there is none.
  static Future<Level> level(int seed, {required int first}) async {
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
