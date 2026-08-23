/// The rules this package keeps: it names no genre, and it shares no mutable
/// value as a constant.
///
///     flutter test test/boundaries_test.dart
///
/// **It was keeping both by being clean rather than by being checked.** Eight
/// packages ran this and thirteen did not, which is the same gap that made
/// `flutter3d_boundaries` a package in the first place — only one layer down.
/// Every one of the thirteen passed on the day the call was added, which is the
/// argument for adding it on that day rather than on the day one of them fails.
///
/// **`@TestOn('vm')`, and this package is the only one that needs it.** The
/// rule is a scan over `lib/`, so it wants `dart:io` — and `tool/ci.sh` runs
/// this package's suite a second time under `--platform chrome`, where
/// `Directory.existsSync` is `Unsupported operation: _Namespace`. Without the
/// annotation the first browser run of this file failed on the rule being read
/// rather than on the rule being broken.
@TestOn('vm')
library;

import 'package:flutter3d_boundaries/flutter3d_boundaries.dart';
import 'package:flutter_test/flutter_test.dart' show TestOn;

void main() {
  expectPackageBoundaries();
}
