// The `recordToClass` kind: `.$1` and `.$2` of a record that became a class
// are the class's getters; a destructuring pattern is left to a person.
import 'package:flutter3d_build/src/migrate/guide.dart';
import 'package:flutter3d_build/src/migrate/lints_table.dart';
import 'package:test/test.dart';

import 'migration_kinds_support.dart';

void main() {
  test('the plugin table and the guide carry it', () {
    final table = kindTable('recordToClass');
    final lints = generateLintsTable([table], stamp: 's');
    expect(lints, contains('kind: MigrationKind.recordToClass'));
    expect(lints, contains(r"fields: <String, String>{'\$1': 'start'"));
    expect(
      generateGuideTable([table]),
      contains(r'`Span` is a class: `.$1` is `.start`, `.$2` is `.end`'),
    );
  });

  test('positional fields become getters; destructuring gets a TODO', () async {
    final report = await migrateKindFixture('recordToClass');
    expect(appliedOf(report), <String>['kinds-Span-class', 'kinds-Span-class']);
    expect(manualOf(report), <String>['kinds-Span-class:11']);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
