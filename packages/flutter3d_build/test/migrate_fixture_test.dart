// The 0.8 -> 1.0 migration, end to end, on a small project written against
// 0.8.5: `test/fixtures/migrate_0_8/before/` migrated by
// `dart run flutter3d_build:migrate` must come out as `after/`, and analyse
// with no errors against this tree.
//
// Slow (two `flutter pub get`s, `dart fix`, a resolved analysis) and it
// needs the Flutter SDK on PATH, so it is tagged `slow` and skipped where
// there is no `flutter`. The same run over the 0.8.5 demos is
// `tool/migrate_corpus.sh`.
@Tags(<String>['slow'])
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  final package = Directory.current.absolute;
  final repo = package.parent.parent;
  final fixture = Directory('${package.path}/test/fixtures/migrate_0_8');
  final hasFlutter =
      Process.runSync('flutter', <String>['--version']).exitCode == 0;

  test(
    'a 0.8 project migrates to what after/ holds, and analyses clean',
    () async {
      final scratch = Directory.systemTemp.createTempSync('migrate_fixture_');
      addTearDown(() => scratch.deleteSync(recursive: true));
      final project = Directory('${scratch.path}/migrate_fixture')
        ..createSync();
      _copy(Directory('${fixture.path}/before'), project);
      File(
        '${project.path}/pubspec_overrides.yaml',
      ).writeAsStringSync(_overrides(repo));

      final run = await Process.run('dart', <String>[
        'run',
        'flutter3d_build:migrate',
        '--lints-from',
        repo.path,
        project.path,
      ], workingDirectory: package.path);
      expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');

      final report = '${run.stdout}';
      expect(report, contains('Rewritten with the resolved code:'));
      expect(report, contains('hardware-supportsWireframe'));
      expect(report, contains('sim-Rider'));
      expect(report, contains('sim-GameLoop'));
      expect(report, contains('textureBytes'));

      final expected = Directory('${fixture.path}/after');
      for (final file in expected.listSync(recursive: true).whereType<File>()) {
        final relative = file.path.substring(expected.path.length + 1);
        final got = File('${project.path}/$relative');
        expect(got.existsSync(), isTrue, reason: relative);
        expect(
          got.readAsStringSync(),
          file.readAsStringSync(),
          reason: '$relative is not what the migration should leave',
        );
      }

      final analysis = await Process.run('flutter', <String>[
        'analyze',
        '--no-pub',
        '--no-fatal-infos',
        '--no-fatal-warnings',
      ], workingDirectory: project.path);
      // A `manual` entry leaves the code to its reader: the symbol is gone
      // and the TODO above the use says what to write instead. Those errors
      // are the migration's report; any other error is the migration's bug.
      final errors = '${analysis.stdout}'
          .split('\n')
          .where((String l) => l.trimLeft().startsWith('error '))
          .where((String l) => !_underManualTodo(l, project))
          .toList();
      expect(errors, isEmpty, reason: '${analysis.stdout}');
    },
    skip: hasFlutter ? false : 'needs the Flutter SDK on PATH',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

/// Whether the analyzer's [line] points into a declaration the migration
/// marked with a `TODO(flutter3d-1.0)`: the TODO sits at most three lines
/// above, past the declaration's doc comment.
bool _underManualTodo(String line, Directory project) {
  final at = RegExp(r'• (\S+):(\d+):\d+ •').firstMatch(line);
  if (at == null) return false;
  final file = File('${project.path}/${at.group(1)}');
  if (!file.existsSync()) return false;
  final lines = file.readAsLinesSync();
  final index = int.parse(at.group(2)!) - 1;
  return lines
      .sublist((index - 3).clamp(0, lines.length), index)
      .any((String l) => l.contains('TODO(flutter3d-1.0)'));
}

void _copy(Directory from, Directory to) {
  for (final entity in from.listSync(recursive: true)) {
    final relative = entity.path.substring(from.path.length + 1);
    if (entity is File) {
      File('${to.path}/$relative')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(entity.readAsBytesSync());
    }
  }
}

/// Every package of this repository by path: the project resolves against
/// this tree, as it would against 1.0.0-rc.1 on pub.dev.
String _overrides(Directory repo) {
  final out = StringBuffer('dependency_overrides:\n');
  for (final parent in <String>['packages']) {
    final dir = Directory('${repo.path}/$parent');
    if (!dir.existsSync()) continue;
    for (final child in dir.listSync().whereType<Directory>()) {
      final pubspec = File('${child.path}/pubspec.yaml');
      if (!pubspec.existsSync()) continue;
      final name = RegExp(
        r'^name:\s*(\S+)',
        multiLine: true,
      ).firstMatch(pubspec.readAsStringSync())?.group(1);
      if (name != null) out.writeln('  $name: {path: ${child.path}}');
    }
  }
  return out.toString();
}
