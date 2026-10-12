// The `parameters` kind's `toNamed` change: an optional positional argument
// that became named, `Gauge(r, 2)` to `Gauge(r, scale: 2)`. `fix_data.yaml`
// carries it as `dart fix`'s add-then-remove, and the batch migrator writes
// the name, since `dart fix` offers no fix for an extra positional argument.
// A renamed named parameter is `dart fix`'s, and the batch migrator's too
// where `dart fix` does not reach the call.
import 'package:flutter3d_build/src/migrate/fix_data.dart';
import 'package:flutter3d_build/src/migrate/guide.dart';
import 'package:flutter3d_build/src/migrate/lints_table.dart';
import 'package:test/test.dart';

import 'migration_kinds_support.dart';

/// The 0.8 side of the fixture's three classes, as `tool/api` writes it.
const String _released = '''
library package:flutter3d_kinds/flutter3d_kinds.dart
final class Gauge
  const Gauge(this.reading, [this.scale = 1])
  final double reading
  final double scale
final class Sieve
  const Sieve([this.coarse = 4, this.fine = 1])
  final int coarse
  final int fine
final class Tap
  const Tap({this.centre = 0})
  final int centre
''';

void main() {
  test('dart fix adds the named parameter from the old place and removes '
      'the place', () {
    final table = kindTable('parameters');
    final (:files, :problems) = generateFixData(
      [table],
      released: {
        '0.8.5': {'flutter3d_kinds': _released},
      },
      current: const <String, String>{},
      stamp: 's',
    );
    expect(problems, isEmpty);
    final yaml = files['flutter3d_kinds']!;
    expect(
      yaml,
      contains(
        "      constructor: ''\n"
        "      inClass: 'Gauge'\n"
        '    changes:\n'
        "      - kind: 'addParameter'\n"
        '        index: 1\n'
        "        name: 'scale'\n"
        '        style: optional_named\n'
        '        argumentValue:\n'
        "          expression: '{% scale %}'\n"
        '          variables:\n'
        '            scale:\n'
        "              kind: 'fragment'\n"
        "              value: 'arguments[1]'\n"
        "      - kind: 'removeParameter'\n"
        '        index: 1\n',
      ),
    );
    expect(yaml, contains("value: 'arguments[0]'"));
    expect("removeParameter'".allMatches(yaml), hasLength(3));
  });

  test('the plugin table and the guide carry it', () {
    final table = kindTable('parameters');
    final lints = generateLintsTable([table], stamp: 's');
    expect(lints, contains('kind: MigrationKind.parameters'));
    expect(lints, contains("fields: <String, String>{'0': 'coarse', "));
    expect(lints, isNot(contains("member: 'Gauge'")));
    final guide = generateGuideTable([table]);
    expect(
      guide,
      contains('(`migrate`). `Gauge(x0, x1)` is `Gauge(x0, scale: x1)`.'),
    );
    expect(
      guide,
      contains('`Sieve(x0, x1)` is `Sieve(coarse: x0, fine: x1)`.'),
    );
  });

  // Six seconds with the migrator compiled; a cold `dart run` compiles it
  // first, which is what the three minutes are for.
  test('a positional argument is named where it stands, and a renamed '
      'one renamed; a call that passes the name as well keeps a TODO', () async {
    final report = await migrateKindFixture('parameters');
    expect(appliedOf(report), <String>[
      'kinds-Gauge-named',
      'kinds-Sieve-named',
      'kinds-Sieve-named',
      'kinds-Tap-center',
    ]);
    expect(manualOf(report), <String>['kinds-Gauge-named:9']);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
