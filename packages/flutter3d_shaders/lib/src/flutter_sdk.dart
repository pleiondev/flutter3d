/// What a build can read about the Flutter SDK it runs under.
library;

import 'dart:io';

/// The engine revision of the Flutter SDK at [sdkRoot]: what
/// `bin/cache/engine.stamp` holds, or `bin/internal/engine.version` where the
/// cache has none; empty when neither is there.
///
/// The revision rather than the Flutter version, because it is what
/// `impellerc` and the runtime that reads its output were built from: a
/// hotfix release moves it, and a local engine build has one of its own.
String engineRevisionAt(String sdkRoot) {
  for (final path in <String>[
    '$sdkRoot/bin/cache/engine.stamp',
    '$sdkRoot/bin/internal/engine.version',
  ]) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final revision = file.readAsStringSync().trim();
    if (revision.isNotEmpty) return revision;
  }
  return '';
}
