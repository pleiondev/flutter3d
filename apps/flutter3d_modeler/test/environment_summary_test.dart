/// `environmentSummary`: `rel-15`'s own honest stand-in for `flutter
/// --version`, which this running app cannot shell out to on every
/// platform it ships to.
///
///     flutter test test/environment_summary_test.dart
library;

import 'package:flutter3d_modeler/src/environment_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads as a real platform name, not a placeholder', () {
    final summary = environmentSummary();
    expect(summary, isNotEmpty);
    // On the machine running this suite (never a browser), it is a native
    // platform name — `TargetPlatform.name` in lower camel case, e.g.
    // "macOS" — not the literal string "web".
    expect(summary, isNot('web'));
  });

  test('is stable across calls — a platform does not change mid-session', () {
    expect(environmentSummary(), environmentSummary());
  });
}
