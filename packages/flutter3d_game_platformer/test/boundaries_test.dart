/// The rules a genre package keeps.
///
///     flutter test test/boundaries_test.dart
///
/// **The mirror image of the engine half's, and it was in three states at
/// once.** This package is *allowed* to know what its genre is — that is what
/// it is for — so what it is held to instead is that its simulation half draws
/// nothing, that it does not reach sideways into another genre, and that a step
/// is repeatable. Racing kept the first two in a file of its own, the shooter
/// kept one of them, and the platformer kept neither; the two that existed each
/// carried a private copy of the same twelve-line scan.
///
/// The rule and its detectors live in `flutter3d_boundaries` now, for the
/// reason they moved there the first time: two copies of a scan is one copy
/// that has quietly stopped working.
library;

import 'package:flutter3d_boundaries/flutter3d_boundaries.dart';

void main() {
  expectNoSharedMutables();
  // Nothing here draws at all: this package does not depend on `flutter3d`,
  // and an empty allowlist is the strongest form of the rule. When it grows
  // a visual half it grows a `bridge.dart` and a line here, as the other two
  // have.
  expectGenreIsolation();
  expectRepeatableStep();
}
