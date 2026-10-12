// Every kind `flutter3d create project` makes, end to end: scaffolded,
// resolved against this tree as it would be against 1.0.0-rc.1 on pub.dev,
// analysed with no issue at all, and its own `test/widget_test.dart` run on
// the software device.
//
// Slow and it needs the Flutter SDK on PATH, so it is tagged `slow` and
// skipped where there is no `flutter`. **The widget test's first run is
// minutes, and the reason is the build hooks**: `flutter test` runs every
// hook in the project's graph, the C physics core and the engine's shader
// bundle among them, before it runs a test. Each kind is therefore made in
// one place under the system temp directory that is kept between runs, the
// project's own files replaced and its `.dart_tool` left, so only the first
// run on a machine pays for the hooks.
@Tags(<String>['slow'])
library;

import 'dart:io';

import 'package:flutter3d_build/cli.dart';
import 'package:test/test.dart';

void main() {
  final package = Directory.current.absolute;
  final repo = package.parent.parent;
  final hasFlutter =
      Process.runSync('flutter', <String>['--version']).exitCode == 0;

  for (final kind in ProjectKind.values) {
    group('the ${kind.name} kind', () {
      final project = Directory(
        '${Directory.systemTemp.path}/flutter3d_create_kinds/${kind.name}',
      );

      setUpAll(() async {
        _scaffoldInto(project, kind);
        File(
          '${project.path}/pubspec_overrides.yaml',
        ).writeAsStringSync(_overrides(repo));
        final got = await Process.run('flutter', <String>[
          'pub',
          'get',
          '--offline',
        ], workingDirectory: project.path);
        expect(got.exitCode, 0, reason: '${got.stdout}\n${got.stderr}');
      });

      test('analyses with no issue', () async {
        final analysis = await Process.run('flutter', <String>[
          'analyze',
          '--no-pub',
        ], workingDirectory: project.path);
        expect(
          analysis.exitCode,
          0,
          reason: '${analysis.stdout}\n${analysis.stderr}',
        );
        expect('${analysis.stdout}', contains('No issues found'));
      });

      test(
        'passes its own widget test on the software device',
        () async {
          final run = await Process.run('flutter', <String>[
            'test',
            '--no-pub',
          ], workingDirectory: project.path);
          expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
          expect('${run.stdout}', contains('All tests passed'));
        },
        // The hooks' first run: 2 to 4.5 min a kind on an M3 Pro on
        // 2026-10-12, 10 to 75 s once they are built.
        timeout: const Timeout(Duration(minutes: 8)),
      );
    }, skip: hasFlutter ? false : 'needs the Flutter SDK on PATH');
  }
}

/// [kind] made afresh in [project], keeping what the last run built there
/// (`.dart_tool`, `build`) so the hooks are not built again.
void _scaffoldInto(Directory project, ProjectKind kind) {
  const kept = <String>{'.dart_tool', 'build'};
  if (project.existsSync()) {
    for (final entity in project.listSync()) {
      if (kept.contains(
        entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
      )) {
        continue;
      }
      entity.deleteSync(recursive: true);
    }
  }
  final fresh = Directory.systemTemp.createTempSync('create_kind_');
  try {
    final made = createProject(
      '${fresh.path}/app',
      'try_${kind.name}',
      kind: kind,
    );
    expect(made.did, isTrue, reason: made.says);
    final from = Directory('${fresh.path}/app');
    for (final entity in from.listSync(recursive: true)) {
      final relative = entity.path.substring(from.path.length + 1);
      if (entity is Directory) {
        Directory('${project.path}/$relative').createSync(recursive: true);
      } else if (entity is File) {
        File('${project.path}/$relative')
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(entity.readAsBytesSync());
      }
    }
  } finally {
    fresh.deleteSync(recursive: true);
  }
}

/// Every package of this repository by path: the project resolves against
/// this tree, as it would against 1.0.0-rc.1 on pub.dev.
String _overrides(Directory repo) {
  final out = StringBuffer('dependency_overrides:\n');
  for (final child in Directory(
    '${repo.path}/packages',
  ).listSync().whereType<Directory>()) {
    final pubspec = File('${child.path}/pubspec.yaml');
    if (!pubspec.existsSync()) continue;
    final name = RegExp(
      r'^name:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec.readAsStringSync())?.group(1);
    if (name != null) out.writeln('  $name: {path: ${child.path}}');
  }
  return out.toString();
}
