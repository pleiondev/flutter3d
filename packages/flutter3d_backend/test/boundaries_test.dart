/// The rules this package keeps: it names no genre, and it shares no mutable
/// value as a constant.
///
///     flutter test test/boundaries_test.dart
///
/// It has two files and picks between two backends, so there is little here for
/// either rule to catch. That is the argument for the call rather than against
/// it: this file costs one line, and the day it stops being true is a day
/// nobody would otherwise be looking.
library;

import 'package:flutter3d_boundaries/flutter3d_boundaries.dart';

void main() {
  expectPackageBoundaries();
}
