/// `tool/build_apps.sh`: every application under `apps/` is built by CI on
/// some platform, and every one that has a web folder is built for the web.
///
///     dart test test/build_apps_test.dart
///
/// The workflow's build matrix is this script's `--matrix` output, so the list
/// of applications is read from the disk and not kept by hand in YAML, where
/// the seventeenth application would have been forgotten.
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  late final List<Map<String, Object?>> cells;
  late final String stderrText;

  setUpAll(() async {
    final result = await Process.run('bash', <String>[
      'tool/build_apps.sh',
      '--matrix',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    final matrix = jsonDecode(result.stdout as String) as Map<String, Object?>;
    cells = (matrix['include']! as List).cast<Map<String, Object?>>();
    stderrText = result.stderr as String;
  });

  final apps = <String>[
    for (final dir in Directory('apps').listSync().whereType<Directory>())
      if (File('${dir.path}/pubspec.yaml').existsSync())
        dir.path.split('/').last,
  ]..sort();

  test('every application is built, or is exempt with its reason', () {
    final built = {for (final cell in cells) cell['app']! as String};
    for (final app in apps) {
      // Mutation: leave an application out of the walk, and it is neither
      // built nor named.
      expect(
        built.contains(app) || stderrText.contains('$app:'),
        isTrue,
        reason: '$app is neither in the matrix nor exempt',
      );
    }
  });

  test('an application with a web folder is built for the web', () {
    for (final app in apps) {
      if (!Directory('apps/$app/web').existsSync()) continue;
      expect(
        cells.where((cell) => cell['app'] == app && cell['target'] == 'web'),
        hasLength(1),
        reason: '$app has a web folder and no web build',
      );
    }
  });

  test('each cell names a runner its target can be built on', () {
    const runners = <String, String>{
      'web': 'ubuntu-latest',
      'linux': 'ubuntu-latest',
      'macos': 'macos-latest',
      'windows': 'windows-latest',
    };
    for (final cell in cells) {
      expect(runners[cell['target']], cell['os'], reason: '$cell');
      expect(
        Directory('apps/${cell['app']}/${cell['target']}').existsSync(),
        isTrue,
        reason: '$cell builds for a platform the application has no folder for',
      );
    }
  });

  test(
    'an application it is asked to build that is not there is refused',
    () async {
      final result = await Process.run('bash', <String>[
        'tool/build_apps.sh',
        'flutter3d_demo_golf',
        'web',
      ]);
      expect(result.exitCode, 2);
      expect(result.stderr, contains('flutter3d_demo_golf'));
    },
  );
}
