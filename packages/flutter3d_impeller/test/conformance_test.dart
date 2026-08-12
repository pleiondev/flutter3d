/// This backend cannot run the conformance checks as tests.
///
/// Flutter GPU needs Impeller enabled and a headless `flutter test` does not
/// provide it — the same reason the golden suite drives an application rather
/// than asserting in a test. The checks are the same list either way; this
/// backend runs them from `example/lib/conformance_main.dart`:
///
///     cd ../flutter3d/example && flutter run -d macos -t lib/conformance_main.dart
///
/// Left here as a file rather than not written, because "the other backend has
/// conformance tests and this one has none" reads as an oversight, and this is
/// a platform fact.
library;

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('conformance runs from an application on this backend', () {
    // Nothing to assert here. The pointer above is the content.
  }, skip: 'Flutter GPU needs Impeller, which flutter test does not enable');
}
