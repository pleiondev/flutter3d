/// Moves a project written against flutter3d 0.8 to 1.0.0-rc.1.
///
/// ```
/// dart pub global activate flutter3d_build 1.0.0-rc.1
/// dart pub global activate flutter3d_lints 1.0.0-rc.1
/// dart pub global run flutter3d_build:migrate [--dry-run] [--from 0.8] <project>
/// ```
///
/// **Thin on purpose.** Most of a migration is the Dart tooling's own: each
/// flutter3d package ships a `lib/fix_data.yaml` that `dart fix` applies,
/// and the `flutter3d_lints` analyzer plugin carries what needs the resolved
/// code. This does what neither can, and runs both:
///
///  1. moves every dependency on a flutter3d package to its 1.0 constraint,
///     renaming a package the release renamed;
///  2. rewrites imports of libraries that moved to another package;
///  3. `flutter pub get` (`dart pub get` for a plain Dart package);
///  4. `dart fix --apply`;
///  5. `flutter3d_lints:migrate`, the plugin's fixes applied across the
///     project, and its TODOs for what a person has to decide;
///  6. adds the dependencies the new imports need, and gets them;
///  7. prints what changed and what is left, each item with the guide's link.
///
/// All of it comes from the tables in `lib/migrations/`, which also generate
/// the fix data and the plugin's rules. They are a chain, `0.8_to_1.0.yaml`
/// then `1.0.0-rc.1_to_rc.2.yaml` and on: the project's `pubspec.lock` says
/// which release it is on, and every table after that release is applied
/// in one run, read as one table (`MigrationTable.merge`).
///
/// `--data` does something else: it lifts the project's data files (levels,
/// runs, effects, data plugins…) to the version this build writes, in
/// place, and reports `file: vN → vM` for each (`lib/src/migrate/data.dart`).
///
/// Options:
///
/// ```text
///   --data              lift the data files instead of migrating the code
///   --backup            with --data, keep each file as it was beside it
///   --dry-run           make the changes in a copy beside the project, print
///                       the report, and remove the copy (with --data: write
///                       nothing, and report)
///   --from <version>    the release the project is on (default: what its
///                       pubspec.lock resolves, else the first table's)
///   --no-pub-get        skip `pub get` (and so steps 4–6, which need it)
///   --lints-from <dir>  run `dart run flutter3d_lints:migrate` from a
///                       checkout of flutter3d instead of the global one
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_build/src/cli_contract.dart' show migrateUsage;
import 'package:flutter3d_build/src/migrate/data.dart';
import 'package:flutter3d_build/src/migrate/project.dart';
import 'package:flutter3d_build/src/migrate/table.dart';

Future<void> main(List<String> args) async {
  String? valueOf(String flag) {
    final i = args.indexOf(flag);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final fromFlag = valueOf('--from');
  final lintsFrom = valueOf('--lints-from');
  final positional = <String>[
    for (var i = 0; i < args.length; i++)
      if (!args[i].startsWith('--') &&
          !(i > 0 &&
              (args[i - 1] == '--from' || args[i - 1] == '--lints-from')))
        args[i],
  ];
  // Asked for, the usage is an answer; given for a wrong call, an error.
  if (args.contains('--help') || args.contains('-h')) {
    stdout.write(migrateUsage);
    return;
  }
  if (positional.length != 1) {
    stderr.write(migrateUsage);
    exitCode = 2;
    return;
  }
  final dryRun = args.contains('--dry-run');
  final pubGet = !args.contains('--no-pub-get');
  final project = Directory(positional.single).absolute;
  if (!File('${project.path}/pubspec.yaml').existsSync()) {
    stderr.writeln('${project.path} has no pubspec.yaml');
    exitCode = 2;
    return;
  }

  // The data files, on their own: no table, no `pub get`, nothing to undo
  // on a dry run since nothing is written.
  if (args.contains('--data')) {
    final data = migrateData(
      project,
      dryRun: dryRun,
      backup: args.contains('--backup'),
    );
    stdout.writeln(data.describe(dryRun: dryRun));
    return;
  }

  final List<MigrationTable> chain;
  try {
    chain = await MigrationTable.shipped();
  } on StateError catch (e) {
    stderr.writeln(e.message);
    exitCode = 2;
    return;
  }
  // The release the project is on: what `--from` says, else what its
  // `pubspec.lock` resolves, else the release the first table starts at.
  final lock = File('${project.path}/pubspec.lock');
  final from =
      fromFlag ??
      (lock.existsSync()
          ? lockedRelease(lock.readAsStringSync(), chain)
          : null) ??
      chain.first.from;
  final tables = MigrationTable.after(from, chain);
  if (tables.isEmpty) {
    stdout.writeln(
      'The project is on $from, and the newest migration table goes to '
      '${chain.last.to}: nothing to migrate.',
    );
    return;
  }
  final table = MigrationTable.merge(tables);

  // A dry run works on a copy at the same depth, so relative path
  // dependencies still resolve.
  final work = dryRun ? _copyBeside(project) : project;
  final report = MigrationReport();
  try {
    final before = _snapshot(work);
    await _migrate(work, table, report, pubGet: pubGet, lintsFrom: lintsFrom);
    final after = _snapshot(work);
    report.changed.addAll(<String>[
      for (final path in <String>{
        ...before.keys,
        ...after.keys,
      }.toList()..sort())
        if (before[path] != after[path]) path,
    ]);
    stdout.writeln(report.describe(dryRun: dryRun, table: table));
    if (report.failed) exitCode = 1;
  } finally {
    if (dryRun) work.deleteSync(recursive: true);
  }
}

Future<void> _migrate(
  Directory project,
  MigrationTable table,
  MigrationReport report, {
  required bool pubGet,
  required String? lintsFrom,
}) async {
  final pubspecFile = File('${project.path}/pubspec.yaml');
  final pubspec = pubspecFile.readAsStringSync();
  final self = RegExp(
    r'^name:\s*(\S+)',
    multiLine: true,
  ).firstMatch(pubspec)?.group(1);

  // 1. The pubspec.
  final moved = migratePubspec(pubspec, table, notes: report.pubspecNotes);
  pubspecFile.writeAsStringSync(moved);
  report.steps.add('ok     dependencies moved to ${table.constraint}');

  // 2. Imports of libraries that moved.
  final uris = <String, String>{
    for (final e in table.entries)
      if (e.kind == 'import' && e.from != null && e.to != null) e.from!: e.to!,
  };
  var rewritten = 0;
  for (final file in projectDartFiles(project)) {
    final text = file.readAsStringSync();
    final next = migrateDirectives(
      text,
      uris: uris,
      packages: table.renamedPackages,
    );
    if (next != text) {
      file.writeAsStringSync(next);
      rewritten++;
    }
  }
  report.steps.add('ok     imports of moved libraries ($rewritten files)');

  if (!pubGet) return;
  final flutter = RegExp(
    r'^\s+sdk:\s*flutter\s*$',
    multiLine: true,
  ).hasMatch(moved);
  final pub = flutter ? 'flutter' : 'dart';

  // 3–4. Resolve against the release, and let `dart fix` work.
  final got = await runStep(report, 'pub get', pub, <String>[
    'pub',
    'get',
  ], project);
  if (got.exitCode != 0) return;
  await runStep(report, 'dart fix', 'dart', <String>[
    'fix',
    '--apply',
  ], project);

  // 5. What needs the resolved code.
  final lints = lintsFrom == null
      ? await runStep(report, 'flutter3d_lints:migrate', 'dart', <String>[
          'pub',
          'global',
          'run',
          'flutter3d_lints:migrate',
          '--json',
          project.path,
        ], project)
      : await runStep(report, 'flutter3d_lints:migrate', 'dart', <String>[
          'run',
          'flutter3d_lints:migrate',
          '--json',
          project.path,
        ], Directory(lintsFrom));
  for (final line in LineSplitter.split('${lints.stdout}')) {
    if (!line.startsWith('{')) continue;
    final r = jsonDecode(line) as Map<String, Object?>;
    for (final m
        in (r['manual']! as List<Object?>).cast<Map<String, Object?>>()) {
      report.manual.add((
        file: '${r['file']}',
        line: m['line']! as int,
        id: '${m['id']}',
        message: '${m['message']}',
        link: '${m['link']}',
      ));
    }
    report.hidden.addAll(
      (r['hidden']! as List<Object?>).map((Object? h) => '$h'),
    );
    for (final id in (r['applied']! as List<Object?>).map(
      (Object? a) => '$a',
    )) {
      report.rewritten[id] = (report.rewritten[id] ?? 0) + 1;
    }
  }

  // 6. Dependencies the new imports need. `dart fix` may have added some
  // already, as `any` (its fix for `depend_on_referenced_packages`): those
  // move to the release's constraint like the rest.
  final fixed = pubspecFile.readAsStringSync();
  final pinned = migratePubspec(fixed, table, notes: <String>[]);
  if (pinned != fixed) pubspecFile.writeAsStringSync(pinned);
  final declared = declaredDependencies(pubspecFile.readAsStringSync());
  final main = <String, String>{};
  final dev = <String, String>{};
  for (final file in projectDartFiles(project)) {
    final top = file.path
        .substring(project.path.length + 1)
        .split(Platform.pathSeparator)
        .first;
    for (final package in referencedPackages(file.readAsStringSync())) {
      if (package == self || !table.owns(package)) continue;
      // Declared either way already: the project chose where it goes.
      if (declared.main.contains(package) || declared.dev.contains(package)) {
        continue;
      }
      if (devDirectories.contains(top)) {
        if (!declared.dev.contains(package)) {
          dev[package] = table.constraintFor(package);
        }
      } else {
        main[package] = table.constraintFor(package);
        dev.remove(package);
      }
    }
  }
  dev.removeWhere((String k, String _) => main.containsKey(k));
  if (main.isNotEmpty || dev.isNotEmpty) {
    var text = pubspecFile.readAsStringSync();
    text = addDependencies(text, main);
    text = addDependencies(text, dev, section: 'dev_dependencies');
    pubspecFile.writeAsStringSync(text);
    report.added
      ..addAll(main)
      ..addAll(<String, String>{
        for (final MapEntry(:key, :value) in dev.entries) '$key (dev)': value,
      });
    await runStep(report, 'pub get', pub, <String>['pub', 'get'], project);
  }
}

Directory _copyBeside(Directory project) {
  final name = project.uri.pathSegments.where((String s) => s.isNotEmpty).last;
  final copy = Directory('${project.parent.path}/.$name.flutter3d-migrate');
  if (copy.existsSync()) copy.deleteSync(recursive: true);
  copy.createSync();
  for (final entity in project.listSync(recursive: true, followLinks: false)) {
    final relative = entity.path.substring(project.path.length + 1);
    final top = relative.split(Platform.pathSeparator).first;
    if (top == 'build' || top == '.dart_tool' || top == '.git') continue;
    final target = '${copy.path}/$relative';
    if (entity is Directory) {
      Directory(target).createSync(recursive: true);
    } else if (entity is File) {
      File(target).parent.createSync(recursive: true);
      entity.copySync(target);
    }
  }
  return copy;
}

/// The text of the files a migration may change, by path relative to
/// [project].
Map<String, String> _snapshot(Directory project) => <String, String>{
  for (final name in const <String>['pubspec.yaml', 'analysis_options.yaml'])
    if (File('${project.path}/$name') case final f when f.existsSync())
      name: f.readAsStringSync(),
  for (final f in projectDartFiles(project))
    f.path.substring(project.path.length + 1): f.readAsStringSync(),
};
