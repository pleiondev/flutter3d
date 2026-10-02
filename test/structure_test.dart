/// The repository's own arrangement, held to the rules `tool/structure.dart`
/// checks, under `dart test` from the root.
///
///     dart test
///
/// **The same rules, not a second copy of them.** The script is the first step
/// of `tool/ci.sh` and prints a report a person reads; this runs the list it
/// runs, `allRules`, so a check that only knows to call `dart test` at the root
/// asks the same questions. Before this file the root held only reference
/// pictures, and `dart test` there found nothing and exited 79.
library;

import 'package:test/test.dart';

import '../tool/structure/detectors.dart';
import '../tool/structure/rules.dart';

void main() {
  // Mutation: a detector that can no longer fire passes every rule built on
  // it; this is the test that says so before the rules are believed.
  test('every detector fires on what it is meant to find', () {
    final broken = proveDetectorsWork();
    expect(broken, isEmpty, reason: broken.join('\n'));
  });

  for (final rule in allRules) {
    // Mutation: change a test count in README.md, or drop a golden from one
    // set, and the rule that holds it fails here as it does in the script.
    test(rule.name, () {
      final found = rule.run();
      expect(found, isEmpty, reason: found.join('\n'));
    });
  }
}
