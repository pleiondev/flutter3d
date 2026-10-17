// The `enumToClass` kind: a type that stopped being an enum or sealed
// leaves every `switch` that named each value one value short later, so
// such a switch gains a wildcard that throws, with a TODO.
import 'package:flutter3d_build/src/migrate/guide.dart';
import 'package:flutter3d_build/src/migrate/lints_table.dart';
import 'package:test/test.dart';

import 'migration_kinds_support.dart';

void main() {
  test('the plugin table and the guide carry it', () {
    final table = kindTable('enumToClass');
    final lints = generateLintsTable([table], stamp: 's');
    expect(lints, contains('kind: MigrationKind.enumToClass'));
    expect(lints, contains("switchOver: 'Weather'"));
    expect(
      generateGuideTable([table]),
      contains('(`migrate`, with a TODO). `Weather` is a class'),
    );
  });

  test('a switch expression and a switch statement gain the wildcard; one '
      'with a wildcard is left alone', () async {
    final report = await migrateKindFixture('enumToClass');
    expect(appliedOf(report), <String>[
      'kinds-Weather-open',
      'kinds-Weather-open',
    ]);
    expect(manualOf(report), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
