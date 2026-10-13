// The `subclassModifier` kind: a class that became `base` makes every class
// of the project's own below it `base` too, directly or through the
// project's own classes, and one that implemented it extends it instead
// where nothing else is its superclass; a class that became `final` leaves
// a TODO at each clause that extends or implements it.
import 'package:flutter3d_build/src/migrate/guide.dart';
import 'package:flutter3d_build/src/migrate/lints_table.dart';
import 'package:flutter3d_build/src/migrate/table.dart';
import 'package:test/test.dart';

import 'migration_kinds_support.dart';

void main() {
  test('the plugin table and the guide carry it', () {
    final table = kindTable('subclassModifier');
    final lints = generateLintsTable([table], stamp: 's');
    expect(lints, contains('kind: MigrationKind.subclassModifier'));
    expect(lints, contains("to: 'base'"));
    expect(lints, contains("to: 'final'"));
    final guide = generateGuideTable([table]);
    expect(
      guide,
      contains('`Component` is a `base` class: a class below it is `base`'),
    );
    expect(guide, contains('`Badge` is a `final` class'));
    expect(
      howCarriedOut(table.entries.first),
      isNot('by hand'),
      reason: 'a base class is carried out by `migrate`',
    );
    expect(howCarriedOut(table.entries.last), isNot('by hand'));
  });

  test('a modifier that is neither base nor final is refused', () {
    final table = MigrationTable.parse(
      kindTableText('subclassModifier').replaceFirst('to: base', 'to: sealed'),
    );
    expect(() => lintsRules([table]), throwsStateError);
  });

  test('subclasses become base, an implementer extends, a final class '
      'gets a TODO', () async {
    final report = await migrateKindFixture('subclassModifier');
    expect(appliedOf(report)..sort(), <String>[
      for (var i = 0; i < 6; i++) 'kinds-Component-base',
    ]);
    expect(manualOf(report)..sort(), <String>[
      'kinds-Badge-final:37',
      'kinds-Badge-final:41',
      'kinds-Component-base:25',
      'kinds-Component-base:31',
    ]);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('a project named like one of the engine\'s packages has its own '
      'classes made base all the same', () async {
    // Mutation: take a class whose package has the engine's prefix for the
    // engine's, and `flame_flutter3d_example`'s game is left a subclass of
    // a base class that is not base itself.
    final report = await migrateKindFixture(
      'subclassModifier',
      project: 'flame_flutter3d_example',
    );
    expect(appliedOf(report), hasLength(6));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
