/// This package names no genre.
///
///     flutter test test/no_genre_test.dart
///
/// The rule and its detector live in `flutter3d_boundaries`, because they were
/// two hundred lines in two copies and one of the copies had already lost the
/// test that proves the detector fires. Eight packages keep this rule now; six
/// of them were keeping it by being clean rather than by being checked.
library;

import 'package:flutter3d_boundaries/flutter3d_boundaries.dart';

void main() => expectNoGenre();
