/// The rules this package keeps: it names no genre, and it shares no mutable
/// value as a constant.
///
///     flutter test test/boundaries_test.dart
///
/// **It was keeping this rule by being clean rather than by being checked.**
/// Only `flutter3d_game` and `flutter3d_bridge` were scanned; the other six
/// were assumed. Today is the cheapest day this will ever be, which is the
/// argument for doing it on a day when nothing fails.
library;

import 'package:flutter3d_boundaries/flutter3d_boundaries.dart';

void main() => expectPackageBoundaries();
