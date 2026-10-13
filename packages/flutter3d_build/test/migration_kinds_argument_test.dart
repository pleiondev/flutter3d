// The `argument` kind: an argument whose parameter changed its name, its
// type or its unit, rewritten where it is passed and where it is assigned:
// `Lamp(glow: Vector4(…))` to `Lamp(glow: LinearColor.fromSrgb(…))`,
// `beamDegrees: 45` to `beam: 45 * pi / 180`, and a colour made a vector
// only to be passed on, `c.toVector3()`, to the colour itself; and a colour
// the engine hands out passed or kept where the project's own code takes a
// vector, `shine(lamp.glow)`, converted to one.
import 'package:flutter3d_build/src/migrate/guide.dart';
import 'package:flutter3d_build/src/migrate/lints_table.dart';
import 'package:test/test.dart';

import 'migration_kinds_support.dart';

void main() {
  test('the plugin table and the guide carry it', () {
    final table = kindTable('argument');
    final lints = generateLintsTable([table], stamp: 's');
    expect(lints, contains('kind: MigrationKind.argument'));
    expect(lints, contains("members: <String>['glow']"));
    expect(lints, contains("types: <String>['Vector4']"));
    expect(lints, contains("to: 'beam'"));
    expect(lints, contains("template: 'LinearColor.fromSrgb({components})'"));
    final guide = generateGuideTable([table]);
    expect(
      guide,
      contains(
        '(`migrate`). `beamDegrees: x` of `Lamp` is `beam: x * pi / 180`.',
      ),
    );
    expect(
      guide,
      contains(
        '(`migrate`). `color: Vector3(x, y, z)` of `Lamp.tinted` is '
        '`color: LinearColor(x, y, z)`.',
      ),
    );
  });

  test('literal, named, cascaded and coalesced values are rewritten, and '
      'a component read through its new name; a value of another shape '
      'keeps a TODO', () async {
    final report = await migrateKindFixture('argument');
    expect(appliedOf(report), <String>[
      'kinds-Lamp-glow',
      'kinds-Lamp-beamDegrees',
      'kinds-Lamp-glow',
      'kinds-Lamp-beamDegrees',
      'kinds-Lamp-glow',
      'kinds-Lamp-tinted',
      'kinds-Lamp-glow',
      'kinds-Lamp-glow',
      'kinds-Lamp-tinted',
      'kinds-LinearColor-as-vector',
      'kinds-LinearColor-as-vector',
    ]);
    expect(manualOf(report), <String>['kinds-Lamp-glow:15']);
  });
}
