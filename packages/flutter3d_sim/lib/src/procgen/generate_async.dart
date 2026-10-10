import 'generate_level.dart';
import 'generate_off_thread_native.dart'
    if (dart.library.js_interop) 'generate_off_thread_web.dart';

/// [generateLevel], off the thread that draws — an isolate of its own where
/// there are isolates, and in a browser, which has none a package can make,
/// on this one after the current frame has been let go.
///
/// The level crosses back as its document, which is what a level is; the
/// same seed makes the same level either way.
Future<Generated> generateLevelOffThread(
  LevelRules rules, {
  required int seed,
  int attempts = 32,
}) => generateOffThread(rules, seed: seed, attempts: attempts);
