// Names 1.0 took away where `dart fix` cannot follow them: a class renamed
// inside a creation the analyzer reads as no type at all (`const Shade()`),
// and a static member that is gone (`Board.table()`), rewritten through its
// class rather than through an instance.
import 'package:flutter3d_build/src/migrate/lints_table.dart';
import 'package:test/test.dart';

import 'migration_kinds_support.dart';

void main() {
  test('a class rename reaches the plugin table; a member rename does not', () {
    final lints = generateLintsTable([kindTable('gone')], stamp: 's');
    expect(lints, contains('kind: MigrationKind.rename'));
    expect(lints, contains("to: 'KindShade'"));
  });

  test('the creations are renamed and the static is rewritten', () async {
    final report = await migrateKindFixture('gone');
    expect(appliedOf(report), <String>[
      'kinds-Shade',
      'kinds-Shade',
      'kinds-Board-table',
    ]);
    expect(manualOf(report), isEmpty);
  });
}
