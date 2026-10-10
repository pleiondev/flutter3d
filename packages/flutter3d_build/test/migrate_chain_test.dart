/// The migration tables as a chain: `0.8_to_1.0.yaml`, then
/// `1.0.0-rc.1_to_rc.2.yaml`, and so on. `migrate` applies the ones newer
/// than what `pubspec.lock` holds, the generator folds them into one
/// `fix_data.yaml` per package and the guide lists them newest first, and a
/// table is closed once its release is tagged.
///
///     dart test test/migrate_chain_test.dart
library;

import 'package:flutter3d_build/src/migrate/fix_data.dart';
import 'package:flutter3d_build/src/migrate/guide.dart';
import 'package:flutter3d_build/src/migrate/table.dart';
import 'package:test/test.dart';

import '../../../tool/structure/migration.dart' as structure;

const String _first = '''
format: 1
from: 0.8.5
to: 1.0.0-rc.1
date: 2026-10-08
guide: https://example.dev/guide/
packages:
  constraint: ^1.0.0-rc.1
  versions:
    pad_input: ^0.5.0
  renamed:
    flutter3d_addon_hud: flutter3d_game_ui
    flutter3d_lab: flutter3d_education
entries:
  - id: core-Old
    kind: rename
    package: flutter3d_core
    symbol: Old
    to: Middle
  - id: lab-moved
    kind: import
    from: package:flutter3d_lab/lab.dart
    to: package:flutter3d_education/lab.dart
''';

const String _second = '''
format: 1
from: 1.0.0-rc.1
to: 1.0.0-rc.2
date: 2026-11-01
guide: https://example.dev/guide/
packages:
  constraint: ^1.0.0-rc.2
  versions:
    pad_input: ^0.6.0
  renamed:
    flutter3d_education: flutter3d_school
entries:
  - id: core-Middle
    kind: rename
    package: flutter3d_core
    symbol: Middle
    to: New
''';

final MigrationTable _a = MigrationTable.parse(_first, source: 'a');
final MigrationTable _b = MigrationTable.parse(_second, source: 'b');

void main() {
  test('releases compare by number, a candidate before its release', () {
    expect(compareReleases('0.8.5', '1.0.0-rc.1'), lessThan(0));
    expect(compareReleases('1.0.0-rc.1', '1.0.0-rc.2'), lessThan(0));
    expect(compareReleases('1.0.0-rc.2', '1.0.0-rc.10'), lessThan(0));
    expect(compareReleases('1.0.0-rc.10', '1.0.0'), lessThan(0));
    expect(compareReleases('0.8', '0.8.0'), 0);
    expect(compareReleases('1.0.0', '0.9.9'), greaterThan(0));
  });

  test('the tables are a chain whatever their files are called', () {
    // Mutation: sort the tables by file name, and `1.0.0-rc.10_to_…` comes
    // before `1.0.0-rc.2_to_…`.
    expect(MigrationTable.chain(<MigrationTable>[_b, _a]), <MigrationTable>[
      _a,
      _b,
    ]);
    final gap = MigrationTable.parse(
      _second.replaceFirst('from: 1.0.0-rc.1', 'from: 1.0.0-rc.0'),
    );
    expect(
      () => MigrationTable.chain(<MigrationTable>[_a, gap]),
      throwsA(
        isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          contains('1.0.0-rc.1'),
        ),
      ),
    );
  });

  test('a project takes every table newer than the release it is on', () {
    // Mutation: start at the table whose `from` equals the release, and a
    // project on 0.8.3 gets nothing.
    final chain = <MigrationTable>[_a, _b];
    expect(MigrationTable.after('0.8.3', chain), <MigrationTable>[_a, _b]);
    expect(MigrationTable.after('0.8', chain), <MigrationTable>[_a, _b]);
    expect(MigrationTable.after('1.0.0-rc.1', chain), <MigrationTable>[_b]);
    expect(MigrationTable.after('1.0.0-rc.2', chain), isEmpty);
  });

  test('the release a project is on is the oldest engine package its lock '
      'resolves', () {
    // Mutation: take the first package of the lock, or count one off the
    // engine's number (`pad_input`).
    const lock = '''
packages:
  collection:
    dependency: transitive
    source: hosted
    version: "1.19.1"
  flutter3d:
    dependency: "direct main"
    source: hosted
    version: "0.8.5"
  flutter3d_addon_hud:
    dependency: "direct main"
    source: hosted
    version: "0.8.3"
  pad_input:
    dependency: transitive
    source: hosted
    version: "0.4.0"
sdks:
  dart: ">=3.12.0 <4.0.0"
''';
    expect(lockedRelease(lock, <MigrationTable>[_a, _b]), '0.8.3');
    expect(lockedRelease('packages: {}\n', <MigrationTable>[_a]), isNull);
    expect(lockedRelease('not: [a lock', <MigrationTable>[_a]), isNull);
  });

  test('the chain reads as one table: renames composed, the newest '
      'constraint, every entry', () {
    // Mutation: merge the renames without composing them, and a project on
    // `flutter3d_lab` lands on `flutter3d_education`, which rc.2 renamed.
    final merged = MigrationTable.merge(<MigrationTable>[_a, _b]);
    expect(merged.from, '0.8.5');
    expect(merged.to, '1.0.0-rc.2');
    expect(merged.constraint, '^1.0.0-rc.2');
    expect(merged.versions, <String, String>{'pad_input': '^0.6.0'});
    expect(merged.renamedPackages, <String, String>{
      'flutter3d_addon_hud': 'flutter3d_game_ui',
      'flutter3d_lab': 'flutter3d_school',
      'flutter3d_education': 'flutter3d_school',
    });
    expect(
      merged.movedUri('package:flutter3d_lab/lab.dart'),
      'package:flutter3d_school/lab.dart',
    );
    expect(
      <String>[for (final e in merged.entries) e.id],
      <String>['core-Old', 'lab-moved', 'core-Middle'],
    );
  });

  test('the guide lists the tables newest first', () {
    // Mutation: write the tables in the order they are given.
    final guide = generateGuideTable(<MigrationTable>[_a, _b]);
    expect(
      guide.indexOf('from 1.0.0-rc.1 to 1.0.0-rc.2'),
      lessThan(guide.indexOf('from 0.8.5 to 1.0.0-rc.1')),
    );
  });

  test('the generator folds both tables into one fix_data.yaml for the '
      'package', () {
    // Mutation: write a file per table, and the second one's transforms
    // replace the first's.
    const api = '''
library package:flutter3d_core/flutter3d_core.dart
class Old
class Middle
''';
    final out = generateFixData(
      <MigrationTable>[_a, _b],
      released: <String, Map<String, String>>{
        '0.8.5': <String, String>{'flutter3d_core': api},
        '1.0.0-rc.1': <String, String>{'flutter3d_core': api},
      },
      current: <String, String>{
        'flutter3d_core':
            'library package:flutter3d_core/flutter3d_core.dart\nclass New\n',
      },
      stamp: 'x',
    );
    final file = out.files['flutter3d_core']!;
    expect(file, contains("title: 'flutter3d 1.0.0-rc.1: core-Old'"));
    expect(file, contains("title: 'flutter3d 1.0.0-rc.2: core-Middle'"));
  });

  group('a table is closed once its release is tagged', () {
    test('inert until the tag exists', () {
      expect(
        structure.closedTableProblems(
          tables: <String, String>{'0.8_to_1.0.yaml': _first},
          tags: const <String>{'v0.8.5'},
          atTag: (String tag, String file) => fail('no tag to read'),
        ),
        isEmpty,
      );
    });

    test('names a table changed since its tag, and passes one that is not', () {
      // Mutation: compare the table with itself instead of with the tagged
      // text, and an entry appended after the tag passes.
      final tables = <String, String>{
        '0.8_to_1.0.yaml': _first,
        '1.0.0-rc.1_to_rc.2.yaml': _second,
      };
      expect(
        structure.closedTableProblems(
          tables: tables,
          tags: const <String>{'v0.8.5', 'v1.0.0-rc.1'},
          atTag: (String tag, String file) =>
              tag == 'v1.0.0-rc.1' && file == '0.8_to_1.0.yaml' ? _first : null,
        ),
        isEmpty,
      );
      final changed = structure.closedTableProblems(
        tables: <String, String>{
          ...tables,
          '0.8_to_1.0.yaml': '$_first  - id: late\n    kind: none\n',
        },
        tags: const <String>{'v1.0.0-rc.1'},
        atTag: (String tag, String file) => _first,
      );
      expect(changed.single.$1, '0.8_to_1.0.yaml');
      expect(changed.single.$2, contains('closed at v1.0.0-rc.1'));
      expect(changed.single.$2, contains('1.0.0-rc.1_to_rc.2.yaml'));
    });

    test('a table missing at its tag is named', () {
      // Mutation: skip a table the tag does not hold, and one added after
      // the release as if it were the release's passes.
      final problems = structure.closedTableProblems(
        tables: <String, String>{'0.8_to_1.0.yaml': _first},
        tags: const <String>{'v1.0.0-rc.1'},
        atTag: (String tag, String file) => null,
      );
      expect(problems.single.$2, contains('not at v1.0.0-rc.1'));
      expect(problems.single.$2, contains('1.0.0-rc.1_to_'));
    });

    test('the open table is the newest one whose release is not tagged', () {
      final tables = <String, String>{
        '0.8_to_1.0.yaml': _first,
        '1.0.0-rc.1_to_rc.2.yaml': _second,
      };
      expect(
        structure.openMigrationTable(tables, tags: const <String>{}),
        '1.0.0-rc.1_to_rc.2.yaml',
      );
      expect(
        structure.openMigrationTable(
          <String, String>{'0.8_to_1.0.yaml': _first},
          tags: const <String>{'v1.0.0-rc.1'},
        ),
        isNull,
      );
      expect(
        structure.openMigrationTable(
          <String, String>{'0.8_to_1.0.yaml': _first},
          tags: const <String>{'v0.8.5'},
        ),
        '0.8_to_1.0.yaml',
      );
    });
  });
}
