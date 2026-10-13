// The `hookContext` kind: a hook an outside class overrides takes one
// context object where it took a list of parameters. The batch migrator
// rewrites the override to take the context and read each old parameter
// from it, and a call to build the context; `dart fix` has no change that
// reaches an override, so this kind is the lints' alone.
import 'package:flutter3d_build/src/migrate/guide.dart';
import 'package:flutter3d_build/src/migrate/lints_table.dart';
import 'package:test/test.dart';

import 'migration_kinds_support.dart';

void main() {
  test('the plugin table and the guide carry it', () {
    final table = kindTable('hookContext');
    final lints = generateLintsTable([table], stamp: 's');
    expect(lints, contains('kind: MigrationKind.hookContext'));
    expect(lints, contains("member: 'sense'"));
    expect(lints, contains("options: 'Sensing'"));
    expect(
      lints,
      contains(
        "fields: <String, String>{'0': 'what', '1': 'amount', "
        "'loud': 'loud'}",
      ),
    );
    expect(lints, contains("member: 'read'"));
    final guide = generateGuideTable([table]);
    expect(
      guide,
      contains(
        '`Depot.read` takes one `Reading` where it took nothing: an override '
        'takes it, and a call hands one asking for nothing, '
        '`const Reading()`.',
      ),
    );
    expect(
      guide,
      contains(
        '`Sensor.sense` takes one `Sensing`: an override reads its old '
        'parameters from it (parameter 1 is `.what`, parameter 2 is '
        '`.amount`, `loud:` is `.loud`), and a call builds one.',
      ),
    );
  });

  // Six seconds with the migrator compiled; a cold `dart run` compiles it
  // first, which is what the three minutes are for.
  test('an override takes the context and reads what it used from it, an '
      'interpolation included; a call builds the context', () async {
    final report = await migrateKindFixture('hookContext');
    // The table's second entry for the same hook, as an engine
    // implementation's entry is, matches every use the first one does and
    // must rewrite none of them a second time.
    // A hook that took nothing (`Depot.read`): the override takes the
    // context, and each call is handed one asking for nothing.
    expect(appliedOf(report), <String>[
      for (var i = 0; i < 6; i++) 'kinds-Sensor-sense',
      for (var i = 0; i < 3; i++) 'kinds-Depot-read',
    ]);
    expect(manualOf(report), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
