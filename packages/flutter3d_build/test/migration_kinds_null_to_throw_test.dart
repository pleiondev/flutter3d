// The `nullToThrow` kind: a call that answered null and throws in 1.0.
// Where its null check is right beside it (`?? x`, or `if (v == null)` on
// the next line), the check becomes `try … on` the entry's exception, with
// a TODO; it is never a silent rewrite. A call with no check beside it is
// a TODO alone.
import 'package:flutter3d_build/src/migrate/guide.dart';
import 'package:flutter3d_build/src/migrate/lints_table.dart';
import 'package:test/test.dart';

import 'migration_kinds_support.dart';

void main() {
  test('the plugin table and the guide carry it', () {
    final table = kindTable('nullToThrow');
    final lints = generateLintsTable([table], stamp: 's');
    expect(lints, contains('kind: MigrationKind.nullToThrow'));
    expect(lints, contains("exception: 'AssetNotFoundException'"));
    expect(
      generateGuideTable([table]),
      contains('becomes `try … on AssetNotFoundException`'),
    );
  });

  test('a declaration, an if-null check, an expression body and a '
      'statement each get their try; an unchecked call a TODO', () async {
    final report = await migrateKindFixture('nullToThrow');
    expect(appliedOf(report), hasLength(4));
    expect(manualOf(report), <String>['kinds-loadText-throws:25']);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
