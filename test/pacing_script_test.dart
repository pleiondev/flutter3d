/// `tool/pacing.sh` picks the demo, its tape and its harness, and says what
/// it would run without building anything (`--dry-run`), which is how the
/// nightly's three demos are proved to resolve on a machine with no phone.
///
///     dart test test/pacing_script_test.dart
library;

import 'dart:io';

import 'package:test/test.dart';

Future<ProcessResult> _pacing(List<String> args) =>
    Process.run('bash', <String>['tool/pacing.sh', ...args]);

void main() {
  test(
    'the shooter resolves to the dungeon, its tape and its harness',
    () async {
      final result = await _pacing(<String>[
        '--demo',
        'shooter',
        '-d',
        'R5CX00A55',
        '--fail-on',
        'p99=33.3',
        '--dry-run',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      final out = result.stdout as String;
      expect(out, contains('apps/flutter3d_demo_dungeon'));
      expect(out, contains('site/assets/samples/shooter.f3drun'));
      expect(out, contains('integration_test/pacing_test.dart'));
      expect(out, contains('R5CX00A55'));
      expect(out, contains('p99=33.3'));
    },
  );

  test('each of the three demos names its own application and tape', () async {
    for (final (demo, app) in <(String, String)>[
      ('platformer', 'apps/flutter3d_demo_platformer'),
      ('racing', 'apps/flutter3d_demo_racing'),
    ]) {
      final result = await _pacing(<String>['--demo', demo, '--dry-run']);
      final said = '${result.stdout}${result.stderr}';
      expect(said, contains(app), reason: said);
      expect(said, contains('site/assets/samples/$demo.f3drun'), reason: said);
      // An application with no harness is refused by name, with the file it
      // needs, rather than played through the dungeon's.
      final harness = File('$app/integration_test/pacing_test.dart');
      expect(result.exitCode, harness.existsSync() ? 0 : 2, reason: said);
      if (!harness.existsSync()) {
        expect(said, contains('$app/integration_test/pacing_test.dart'));
      }
    }
  });

  test(
    'a demo it does not know and a bad threshold stop before a build',
    () async {
      final unknown = await _pacing(<String>['--demo', 'golf', '--dry-run']);
      expect(unknown.exitCode, 2);
      expect(unknown.stderr, contains('golf'));

      // Mutation: drop the threshold check from the dry run, and a nightly
      // with a misspelt line builds for ten minutes before it says so.
      final bad = await _pacing(<String>['--fail-on', 'p95=20', '--dry-run']);
      expect(bad.exitCode, 2);
      expect(bad.stderr, contains('p95'));
    },
  );
}
