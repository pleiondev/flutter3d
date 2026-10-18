import 'generate_level.dart';

/// In a browser: after the frame in hand, on this thread — a package cannot
/// start a worker of its own there, and a level is a few milliseconds.
Future<Generated> generateOffThread(
  LevelRules rules, {
  required int seed,
  required int attempts,
}) => Future<Generated>(
  () => generateLevel(rules, seed: seed, attempts: attempts),
);
