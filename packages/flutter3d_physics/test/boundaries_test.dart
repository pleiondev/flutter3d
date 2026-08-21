/// The rules this package keeps: it names no genre, and it shares no mutable
/// value as a constant.
///
///     dart test test/boundaries_test.dart
///
/// **It was keeping this rule by being clean rather than by being checked.**
/// Only `flutter3d_game` and `flutter3d_bridge` were scanned; the other six
/// were assumed.
///
/// `dart test`, not `flutter test` — this package has no Flutter in it, which is
/// the boundary it exists to keep, and the rule package is pure Dart for
/// exactly that reason.
library;

import 'package:flutter3d_boundaries/flutter3d_boundaries.dart';

void main() => expectPackageBoundaries();
