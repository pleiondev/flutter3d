// The `regroup` kind: named arguments that moved into an options object,
// `View3d(fov: 1)` to `View3d(view: ViewOptions(fov: 1))`.
import 'package:flutter3d_build/src/migrate/guide.dart';
import 'package:flutter3d_build/src/migrate/lints_table.dart';
import 'package:test/test.dart';

import 'migration_kinds_support.dart';

void main() {
  test('the plugin table and the guide carry it', () {
    final table = kindTable('regroup');
    final lints = generateLintsTable([table], stamp: 's');
    expect(lints, contains('kind: MigrationKind.regroup'));
    expect(lints, contains("into: 'view'"));
    expect(lints, contains("options: 'ViewOptions'"));
    expect(lints, contains("members: <String>['fov', 'near']"));
    expect(
      generateGuideTable([table]),
      contains(
        '(`migrate`). `fov: near:` of `View3d` go inside '
        '`view: ViewOptions(…)`.',
      ),
    );
  });

  test('the arguments move, and a call that has the group already is '
      'left with a TODO', () async {
    final report = await migrateKindFixture('regroup');
    expect(appliedOf(report), <String>[
      'kinds-View3d-view',
      'kinds-View3d-view',
    ]);
    expect(manualOf(report), <String>['kinds-View3d-view:13']);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
