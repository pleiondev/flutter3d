/// The rules this package keeps: it names no genre, and it shares no mutable
/// value as a constant.
///
///     flutter test test/boundaries_test.dart
///
/// The rule and its detector live in `flutter3d_boundaries`, because they were
/// two hundred lines in two copies and one of the copies had already lost the
/// test that proves the detector fires. Eight packages keep this rule now; six
/// of them were keeping it by being clean rather than by being checked.
library;

import 'package:flutter3d_boundaries/flutter3d_boundaries.dart';

void main() {
  expectPackageBoundaries();
  // The generator itself is what everything else is required to use.
  expectRepeatableStep(allowing: const <String, String>{
    'lib/src/save/game_random.dart': 'it is the seeded generator',
  });
}
