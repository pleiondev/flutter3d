/// One severity for every issue the engine reports.
///
///     dart test test/issues_test.dart
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:test/test.dart';

void main() {
  // Mutation: reorder `Severity.values`, or drop `note`, and a mesh check's
  // sort by index or a file's word reads another tier.
  test('a severity reads back by its word, least serious first', () {
    expect(
      <String>[for (final s in Severity.values) s.name],
      <String>['note', 'warning', 'error'],
    );
    for (final s in Severity.values) {
      expect(Severity.byName(s.name), same(s));
      expect(s.index, Severity.values.indexOf(s));
    }
    expect(Severity.byName('fatal'), isNull);
  });

  test('an issue is a warning unless its library says otherwise', () {
    expect(const Issue('a missing texture').severity, Severity.warning);
    expect(
      const Issue('no spawn', severity: Severity.error).severity,
      Severity.error,
    );
  });
}
