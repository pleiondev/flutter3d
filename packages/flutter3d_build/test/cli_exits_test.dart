import 'dart:io';

import 'package:flutter3d_build/cli.dart';
import 'package:test/test.dart';

/// Every command answers the same situation with the same exit code and on
/// the same stream: its usage asked for is stdout and 0, an option it does
/// not take is stderr and 2, a file or project that is not there is 1.
///
/// **One table over every command**, so a new command joins it by being in
/// [cliCommands] and a command that answers differently is named. `init`
/// and `lights` printed their help to stderr with 2, and `create` and
/// `migrate` dropped an option they did not know; a script cannot tell a
/// typo from a run that did nothing.
void main() {
  late Directory scratch;
  setUp(() => scratch = Directory.systemTemp.createTempSync('cli_exits'));
  tearDown(() => scratch.deleteSync(recursive: true));

  /// A file under the scratch directory that is not there.
  String missing(String name) => '${scratch.path}/$name';

  /// For each command, a command line naming a file or a project that is
  /// not there; null where the command reads no file it is handed.
  final missingFile = <String, List<String> Function()?>{
    'convert': () => <String>['convert', missing('a.glb'), '--dry-run'],
    'create': null,
    'init': () => <String>['init', missing('project')],
    'plugins': null,
    'shaders': null,
    'migrate': () => <String>['migrate', '--no-pub-get', scratch.path],
    'lights': () => <String>['lights', '--optimize', missing('a.json')],
    'lightmap': () => <String>['lightmap', missing('a.json')],
    'visibility': () => <String>['visibility', missing('a.json')],
    'decode-worker': null,
    'doctor': null,
    'help': null,
  };

  test('the table names every command', () {
    expect(missingFile.keys.toSet(), cliCommands.toSet());
  });

  for (final command in cliCommands) {
    group(command, () {
      test('--help prints the usage to stdout and exits 0', () async {
        final run = await _run(<String>[command, '--help']);
        expect(run.code, CliExit.ok, reason: run.err);
        expect(run.out.trim(), isNotEmpty);
        expect(run.err, isEmpty);
      });

      test('help $command says what --help says', () async {
        final asked = await _run(<String>['help', command]);
        final help = await _run(<String>[command, '--help']);
        expect(asked.code, CliExit.ok, reason: asked.err);
        expect(asked.out, help.out);
        expect(asked.err, isEmpty);
      });

      test('an option it does not take is 2, on stderr', () async {
        final forms = command == 'create'
            ? <List<String>>[
                <String>['create', '--frobnicate'],
                <String>['create', 'project', missing('p'), '--knd=viewer'],
                <String>[
                  'create',
                  'plugin',
                  '--kind',
                  'tool',
                  '--name',
                  'x',
                  '--targte',
                  missing('t'),
                ],
              ]
            : <List<String>>[
                <String>[command, '--frobnicate'],
              ];
        for (final line in forms) {
          final run = await _run(line);
          expect(
            run.code,
            CliExit.usage,
            reason: '${line.join(' ')}: ${run.out}',
          );
          expect(run.err, contains('Unknown option'), reason: line.join(' '));
          expect(run.out, isEmpty, reason: line.join(' '));
        }
        // Nothing was written by the forms that would have.
        expect(scratch.listSync(), isEmpty);
      });

      if (missingFile[command] case final line?) {
        test('a file or a project that is not there is 1', () async {
          final run = await _run(line());
          expect(run.code, CliExit.failure, reason: '${run.out}${run.err}');
          // `convert` says which input failed in its report, on stdout.
          expect('${run.out}${run.err}', isNotEmpty);
        });
      }
    });
  }

  test('help for a command that is not one is 2', () async {
    final run = await _run(const <String>['help', 'frobnicate']);
    expect(run.code, CliExit.usage);
    expect(run.out, isEmpty);
  });

  test(
    'init --check is 1 for a hook edited by hand, as its usage says',
    () async {
      File('${scratch.path}/pubspec.yaml').writeAsStringSync('name: game\n');
      File('${scratch.path}/hook/build.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('// mine\n');
      final run = await _run(<String>['init', '--check', scratch.path]);
      expect(run.code, CliExit.failure);
      expect(
        initUsage,
        contains(
          '1 the directory is not there, or\nhook/build.dart was edited by hand',
        ),
      );
    },
  );
}

/// What one run of the command printed and answered.
final class _Run {
  const _Run(this.code, this.out, this.err);
  final int code;
  final String out;
  final String err;
}

/// Runs `flutter3d` with [arguments], its two streams caught.
Future<_Run> _run(List<String> arguments) async {
  final out = _Caught();
  final err = _Caught();
  final code = await IOOverrides.runZoned(
    () => runFlutter3d(arguments),
    stdout: () => out,
    stderr: () => err,
  );
  return _Run(code, '${out.text}', '${err.text}');
}

/// A stream that keeps what is written to it.
final class _Caught implements Stdout {
  final StringBuffer text = StringBuffer();

  @override
  void write(Object? object) => text.write(object);

  @override
  void writeln([Object? object = '']) => text.writeln(object);

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      text.writeAll(objects, separator);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
