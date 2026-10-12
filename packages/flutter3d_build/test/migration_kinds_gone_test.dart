// Names 1.0 took away where `dart fix` cannot follow them: a class renamed
// inside a creation the analyzer reads as no type at all (`const Shade()`),
// a static member that is gone (`Board.table()`), rewritten through its
// class rather than through an instance; a top-level function gone with all
// its arguments handed on (`srgbColor(…)`); an extension's member gone
// (`events.has<T>()`); a static getter that became an instance's field
// (`Mode.touch`), rewritten only where it is named through the class; and,
// where nothing can be written, a TODO at each use of a gone function and
// of a gone library's names, on the line of the use.
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
      'kinds-srgbColor',
      'kinds-srgbColor',
      'kinds-Tally-has',
      'kinds-Mode-touch',
    ]);
    expect(manualOf(report), <String>[
      'kinds-roster:2',
      'kinds-oldHelperGone:19',
      'kinds-roster:20',
    ]);
  });
}
