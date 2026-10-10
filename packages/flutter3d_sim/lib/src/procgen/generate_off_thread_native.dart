import 'dart:isolate';

import '../level/level.dart';
import 'generate_level.dart';

/// In an isolate: the rules go over as JSON and the level comes back as
/// its document, both of which any isolate can carry.
Future<Generated> generateOffThread(
  LevelRules rules, {
  required int seed,
  required int attempts,
}) async {
  final asked = rules.toJson();
  final made = await Isolate.run(() {
    final (:level, seed: made, :says) = generateLevel(
      LevelRules.fromJson(asked),
      seed: seed,
      attempts: attempts,
    );
    return (level: level?.toJson(), seed: made, says: says);
  });
  return (
    level: switch (made.level) {
      final Map<String, Object?> document => Level.fromJson(document),
      null => null,
    },
    seed: made.seed,
    says: made.says,
  );
}
