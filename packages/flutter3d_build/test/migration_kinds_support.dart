// What the tests of the migration kinds share: a fixture's table, and its
// `before/` run through the batch migrator of `flutter3d_lints` with that
// table alone.
//
// Each fixture under `test/fixtures/migrate_kinds/<kind>/` is a table with
// the kind's entries, a `before/` written against 0.8 and the `after/` the
// migration must leave. They all resolve against
// `migrate_kinds/flutter3d_kinds/`, a package of the 1.0 side of each break
// whose name the scan counts as the engine's.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_build/src/migrate/lints_table.dart';
import 'package:flutter3d_build/src/migrate/table.dart';
import 'package:test/test.dart';

import '../../../tool/structure/migration.dart' as structure;

final Directory _package = Directory.current.absolute;
final Directory _fixtures = Directory(
  '${_package.path}/test/fixtures/migrate_kinds',
);

/// The text of [kind]'s table.
String kindTableText(String kind) =>
    File('${_fixtures.path}/$kind/table.yaml').readAsStringSync();

/// [kind]'s table, after checking the structure scan reads it as YAML does
/// and finds nothing wrong with it.
MigrationTable kindTable(String kind) {
  final text = kindTableText(kind);
  final table = MigrationTable.parse(text);
  final lines = structure.readMigrationTable(text);
  expect(structure.migrationTableProblems(lines), isEmpty);
  expect(
    <String>[
      for (final e in lines.entries)
        '${e.id}/${e.kind}/${e.package}/${e.symbol}',
    ],
    <String>[
      for (final e in table.entries)
        '${e.id}/${e.kind}/${e.package}/${e.symbol}',
    ],
  );
  return table;
}

/// [kind]'s `before/` migrated by `flutter3d_lints:migrate` with only its
/// own table, compared file by file with `after/`; the report's entries.
Future<List<Map<String, Object?>>> migrateKindFixture(String kind) async {
  final table = kindTable(kind);
  final scratch = Directory.systemTemp.createTempSync('migrate_kinds_');
  addTearDown(() => scratch.deleteSync(recursive: true));
  final project = Directory('${scratch.path}/project')..createSync();
  _copy(Directory('${_fixtures.path}/$kind/before'), project);
  _copy(
    Directory('${_fixtures.path}/flutter3d_kinds'),
    Directory('${scratch.path}/flutter3d_kinds')..createSync(),
  );
  File(
    '${project.path}/pubspec.yaml',
  ).writeAsStringSync('name: fixture\nenvironment:\n  sdk: ^3.9.0\n');
  File('${project.path}/.dart_tool/package_config.json')
    ..createSync(recursive: true)
    ..writeAsStringSync(
      jsonEncode(<String, Object?>{
        'configVersion': 2,
        'packages': <Map<String, String>>[
          <String, String>{
            'name': 'flutter3d_kinds',
            'rootUri': '../../flutter3d_kinds',
            'packageUri': 'lib/',
            'languageVersion': '3.9',
          },
          <String, String>{
            'name': 'fixture',
            'rootUri': '../',
            'packageUri': 'lib/',
            'languageVersion': '3.9',
          },
        ],
      }),
    );
  final rules = File('${scratch.path}/rules.json')
    ..writeAsStringSync(jsonEncode(lintsRules(<MigrationTable>[table])));

  final run = await Process.run('dart', <String>[
    'run',
    'bin/migrate.dart',
    '--json',
    '--rules=${rules.path}',
    project.path,
  ], workingDirectory: '${_package.parent.path}/flutter3d_lints');
  expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');

  final expected = Directory('${_fixtures.path}/$kind/after');
  for (final file in expected.listSync(recursive: true).whereType<File>()) {
    final relative = file.path.substring(expected.path.length + 1);
    expect(
      File('${project.path}/$relative').readAsStringSync(),
      file.readAsStringSync(),
      reason: '$relative is not what the migration should leave',
    );
  }
  return <Map<String, Object?>>[
    for (final line in '${run.stdout}'.split('\n'))
      if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, Object?>,
  ];
}

/// The manual items of [report], as `id:line`.
List<String> manualOf(List<Map<String, Object?>> report) => <String>[
  for (final file in report)
    for (final m
        in (file['manual']! as List<Object?>).cast<Map<String, Object?>>())
      '${m['id']}:${m['line']}',
];

/// The rule ids [report] says were carried out, once per use.
List<String> appliedOf(List<Map<String, Object?>> report) => <String>[
  for (final file in report)
    for (final id in file['applied']! as List<Object?>) '$id',
];

void _copy(Directory from, Directory to) {
  for (final entity in from.listSync(recursive: true)) {
    final relative = entity.path.substring(from.path.length + 1);
    if (entity is Directory) {
      Directory('${to.path}/$relative').createSync(recursive: true);
    } else if (entity is File) {
      File('${to.path}/$relative')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(entity.readAsBytesSync());
    }
  }
}
