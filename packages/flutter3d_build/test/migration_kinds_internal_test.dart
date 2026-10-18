// The `internal` kind: a name the package keeps to itself since 1.0 gets
// one diagnostic per import of the package that brought it, naming every
// such name the file uses, one line per package in the guide, and a TODO on
// each line of a use, where the analyzer's error stands.
import 'package:flutter3d_build/src/migrate/guide.dart';
import 'package:flutter3d_build/src/migrate/lints_table.dart';
import 'package:test/test.dart';

import 'migration_kinds_support.dart';

void main() {
  test('the plugin table and the guide carry it, one line per package', () {
    final table = kindTable('internal');
    final lints = generateLintsTable([table], stamp: 's');
    expect(lints, contains('kind: MigrationKind.internal'));
    expect(lints, contains("instead: 'A stage of your own is written with"));
    expect(lints, contains('#internal-flutter3d_kinds'));
    final guide = generateGuideTable([table]);
    expect(
      RegExp('<a id="internal-flutter3d_kinds">').allMatches(guide),
      hasLength(1),
    );
    expect(guide, contains('**2 names were the package\'s own**'));
    // Each id still has its anchor, inside the one line.
    expect(guide, contains('<a id="kinds-oldHelper"></a>`oldHelper`'));
    expect(guide, contains('0 by hand'));
  });

  test('three uses through one import leave one TODO on the import, '
      'listing both names, and one on each line of a use', () async {
    final report = await migrateKindFixture('internal');
    expect(manualOf(report), <String>[
      'internal-flutter3d_kinds:1',
      'internal-flutter3d_kinds:3',
      'internal-flutter3d_kinds:5',
      'internal-flutter3d_kinds:5',
    ]);
    expect(appliedOf(report), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
