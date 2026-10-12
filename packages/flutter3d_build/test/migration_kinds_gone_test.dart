// Names 1.0 took away where `dart fix` cannot follow them, each carried by
// the lints with the resolved code:
//
// * a class renamed inside a creation the analyzer reads as no type at all
//   (`const Shade()`), in an import's `show`, under an import prefix, and
//   where its old name is the Dart SDK's too (`Match`), which the engine's
//   import shadowed; where two classes had one old name (`Seat`), the one
//   whose old class the file did not hide;
// * a member renamed where `dart fix` did not reach it, a member of a
//   renamed class met under the new name, and an implementer's declaration
//   of a renamed member, a getter or a field;
// * a name moved to another library, imported from there;
// * a static member that is gone (`Board.table()`), a top-level function
//   gone with its arguments handed on (`srgbColor(…)`), an extension's
//   member gone (`events.has<T>()`), a static that became an instance's
//   member (`Mode.touch`), and a call whose parameter changed type,
//   rewritten only where it passes the old one;
// * a call of a member that became asynchronous, awaited in an `async` body
//   (a test's callback made `async` for it), and elsewhere a TODO at the
//   call and at each read of the variable that holds it;
// * and where nothing can be written, a TODO on the line of each use of a
//   gone function or a gone library's names, at each override of a type
//   whose implementers have something to do, and at a creation and each
//   argument it lost of a constructor whose shape changed.
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
      'kinds-Store-load',
      'kinds-Store-load',
      'kinds-Seat',
      'kinds2-Seat',
      'kinds2-Seat',
      'kinds-Wheel-rolling',
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
      'kinds-Store-load:61',
      'kinds-Store-load:62',
    ]);
  });
}
