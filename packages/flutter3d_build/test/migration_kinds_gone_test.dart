// Names 1.0 took away where `dart fix` cannot follow them: a class renamed
// inside a creation the analyzer reads as no type at all (`const Shade()`),
// a class renamed in an import's `show`; a class renamed whose old name is the Dart SDK's too (`Match`), which the
// engine's import shadowed; a static member that is gone (`Board.table()`), rewritten through its
// class rather than through an instance; a top-level function gone with all
// its arguments handed on (`srgbColor(…)`); an extension's member gone
// (`events.has<T>()`); a static getter that became an instance's field
// (`Mode.touch`), rewritten only where it is named through the class; and,
// where nothing can be written, a TODO at each use of a gone function and
// of a gone library's names, on the line of the use, and at each override
// of a type whose implementers have something to do, and at a creation and
// each argument it lost of a constructor whose shape changed.
import 'package:flutter3d_build/src/migrate/lints_table.dart';
import 'package:test/test.dart';

import 'migration_kinds_support.dart';

void main() {
  test('a class rename and a member rename reach the plugin table', () {
    final lints = generateLintsTable([kindTable('gone')], stamp: 's');
    expect(lints, contains('kind: MigrationKind.rename'));
    expect(lints, contains("to: 'KindShade'"));
    expect(lints, contains("member: 'count'"));
    expect(lints, contains("to: 'tally'"));
  });

  test('the creations are renamed and the static is rewritten', () async {
    final report = await migrateKindFixture('gone');
    expect(appliedOf(report), <String>[
      'kinds-Shade',
      'kinds-Shade',
      'kinds-Shade',
      'kinds-Board-table',
      'kinds-srgbColor',
      'kinds-srgbColor',
      'kinds-Tally-has',
      'kinds-Mode-touch',
      'kinds-Match',
      'kinds-Match',
      'kinds-Ledger-total',
      'kinds-Ledger-count',
      'kinds-Wrench',
      'kinds-Board-pile',
      'kinds-Store-load',
      'kinds-Store-load',
      'kinds-Seat',
      'kinds2-Seat',
      'kinds2-Seat',
      'kinds-Wheel-rolling',
    ]);
    expect(manualOf(report), <String>[
      'kinds-roster:3',
      'kinds-oldHelperGone:22',
      'kinds-roster:23',
      'kinds-Shelf:26',
      'kinds-Shelf:29',
      'kinds-Dial-constructor:35',
      'kinds-Dial-constructor:37',
      'kinds-Store-load:60',
    ]);
  });
}
