/// This package names no genre.
///
///     flutter test test/no_genre_test.dart
///
/// **It was keeping this rule by being clean rather than by being checked.**
/// Only `flutter3d_game` and `flutter3d_bridge` were scanned; the other six
/// were assumed. Today is the cheapest day this will ever be, which is the
/// argument for doing it on a day when nothing fails.
library;

import 'package:flutter3d_boundaries/flutter3d_boundaries.dart';

void main() => expectNoGenre();
