/// Writes everything the migration tables drive, from
/// `lib/migrations/*.yaml`:
///
///  * `lib/fix_data.yaml` in each package a `rename`, `moved` or
///    `parameters` entry lands in — what `dart fix` applies;
///  * `flutter3d_lints/lib/src/migration/table.g.dart` — what the analyzer
///    plugin and `dart run flutter3d_lints:migrate` check against;
///  * the generated half of the site's migration guide,
///    `site/content/reference/migrating-to-1.0.md`.
///
/// ```
/// cd packages/flutter3d_build
/// dart run tool/generate_migrations.dart          # write them
/// dart run tool/generate_migrations.dart --check  # exit 1 if any is stale
/// ```
///
/// Each output carries the stamp of the tables it came from, which the
/// structure rule compares against the tables without running this.
///
/// **It also holds the table's layout.** The structure scan reads the
/// tables without a YAML parser (`tool/structure/migration.dart`); this
/// reads them with one, and refuses a table where the two disagree on an
/// entry's id, kind, package or symbol — the drift that would otherwise let
/// the rule pass on entries it misread.
library;

import 'dart:io';

import 'package:flutter3d_build/src/migrate/fix_data.dart';
import 'package:flutter3d_build/src/migrate/guide.dart';
import 'package:flutter3d_build/src/migrate/lints_table.dart';
import 'package:flutter3d_build/src/migrate/table.dart';

import '../../../tool/structure/migration.dart' as structure;

void main(List<String> args) {
  final check = args.contains('--check');
  final package = Directory.current.absolute;
  final root = package.parent.parent;
  final tableFiles =
      Directory('${package.path}/lib/migrations')
          .listSync()
          .whereType<File>()
          .where((File f) => f.path.endsWith('.yaml'))
          .toList()
        ..sort((File a, File b) => a.path.compareTo(b.path));

  final texts = <String>[for (final f in tableFiles) f.readAsStringSync()];
  final stamp = structure.tableStamp(texts.join('\n'));
  final tables = <MigrationTable>[];
  final problems = <String>[];
  for (var i = 0; i < tableFiles.length; i++) {
    final name = tableFiles[i].uri.pathSegments.last;
    final table = MigrationTable.parse(texts[i], source: tableFiles[i].path);
    tables.add(table);
    final lines = structure.readMigrationTable(texts[i]);
    for (final (line, what) in structure.migrationTableProblems(lines)) {
      problems.add('$name:$line: $what');
    }
    if (lines.entries.length != table.entries.length) {
      problems.add(
        '$name: the structure scan reads ${lines.entries.length} entries and '
        'YAML ${table.entries.length}: keep each `  - id:` at two spaces and '
        'its keys at four',
      );
    }
    for (var j = 0; j < lines.entries.length && j < table.entries.length; j++) {
      final a = lines.entries[j];
      final b = table.entries[j];
      if (a.id != b.id ||
          a.kind != b.kind ||
          a.package != b.package ||
          a.symbol != b.symbol) {
        problems.add(
          '$name:${a.line}: the structure scan reads '
          '${a.id}/${a.kind}/${a.package}/${a.symbol}, YAML '
          '${b.id}/${b.kind}/${b.package}/${b.symbol}',
        );
      }
    }
  }

  // The release snapshots each table is measured against, and now.
  final released = <String, Map<String, String>>{};
  for (final table in tables) {
    final dir = Directory('${root.path}/tool/api/baseline/v${table.from}');
    if (!dir.existsSync()) {
      problems.add('there is no baseline for ${table.from} at ${dir.path}');
      continue;
    }
    released[table.from] = <String, String>{
      for (final f in dir.listSync().whereType<File>())
        if (f.path.endsWith('.api'))
          f.uri.pathSegments.last.replaceAll('.api', ''): f.readAsStringSync(),
    };
  }
  final homes = _packages(root);
  final current = <String, String>{
    for (final MapEntry(key: name, value: dir) in homes.entries)
      if (File('${dir.path}/api/$name.api').existsSync())
        name: File('${dir.path}/api/$name.api').readAsStringSync(),
  };

  final fixData = generateFixData(
    tables,
    released: released,
    current: current,
    stamp: stamp,
  );
  for (final (id, why) in fixData.problems) {
    problems.add('$id: $why');
  }

  final outputs = <String, String>{
    for (final MapEntry(key: name, value: text) in fixData.files.entries)
      '${homes[name]!.path}/lib/fix_data.yaml': text,
    '${root.path}/packages/flutter3d_lints/lib/src/migration/table.g.dart':
        generateLintsTable(tables, stamp: stamp),
  };
  final guide = File('${root.path}/site/content/reference/migrating-to-1.0.md');
  if (guide.existsSync()) {
    final spliced = spliceGuide(
      guide.readAsStringSync(),
      generateGuideTable(tables),
    );
    if (spliced == null) {
      problems.add('${guide.path} has no $guideStart … $guideEnd markers');
    } else {
      outputs[guide.path] = spliced;
    }
  }

  // A generated fix_data.yaml whose package no longer gets transforms goes.
  final stale = <String>[
    for (final dir in homes.values)
      if (File('${dir.path}/lib/fix_data.yaml') case final f
          when f.existsSync() &&
              f.readAsStringSync().contains('# table-stamp:') &&
              !outputs.containsKey(f.path))
        f.path,
  ];

  var differs = 0;
  for (final MapEntry(key: path, value: text) in outputs.entries) {
    final file = File(path);
    if (file.existsSync() && file.readAsStringSync() == text) continue;
    differs++;
    if (check) {
      stdout.writeln('stale: ${_rel(root, path)}');
    } else {
      file.writeAsStringSync(text);
      stdout.writeln('wrote ${_rel(root, path)}');
    }
  }
  for (final path in stale) {
    differs++;
    if (check) {
      stdout.writeln('stale: ${_rel(root, path)}');
    } else {
      File(path).deleteSync();
      stdout.writeln('removed ${_rel(root, path)}');
    }
  }

  final kinds = <String, int>{};
  for (final t in tables) {
    for (final e in t.entries) {
      kinds[e.kind] = (kinds[e.kind] ?? 0) + 1;
    }
  }
  stdout.writeln(
    '${tables.fold(0, (int n, MigrationTable t) => n + t.entries.length)} '
    'entries (${kinds.entries.map((MapEntry<String, int> k) => '${k.value} ${k.key}').join(', ')}); '
    '${fixData.files.length} fix_data.yaml files',
  );
  for (final p in problems) {
    stderr.writeln(p);
  }
  if (problems.isNotEmpty || (check && differs > 0)) exitCode = 1;
}

Map<String, Directory> _packages(Directory root) {
  final found = <String, Directory>{};
  for (final parent in <String>['packages']) {
    final dir = Directory('${root.path}/$parent');
    if (!dir.existsSync()) continue;
    for (final child in dir.listSync().whereType<Directory>()) {
      final pubspec = File('${child.path}/pubspec.yaml');
      if (!pubspec.existsSync()) continue;
      final name = RegExp(
        r'^name:\s*(\S+)',
        multiLine: true,
      ).firstMatch(pubspec.readAsStringSync())?.group(1);
      if (name != null) found[name] = child;
    }
  }
  return found;
}

String _rel(Directory root, String path) =>
    path.startsWith(root.path) ? path.substring(root.path.length + 1) : path;
