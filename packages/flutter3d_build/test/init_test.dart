// `ap-10`: `dart run flutter3d_build:init` writes `hook/build.dart`, the
// two `pubspec.yaml` entries, and the `.gitignore` line a project needs for
// `ap-05`'s hook to run on every build — idempotently, honouring a
// person's own edits to the hook, and reporting rather than silently
// changing anything under `--check`.
import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_build/flutter3d_build.dart';
import 'package:test/test.dart';

/// The `flutter:` section a real `flutter create` writes: an active
/// `uses-material-design`, and an `assets:` example left commented out — the
/// shape `init` must treat as "no active assets: key", not read the comment
/// as one.
const String _freshPubspec = '''
name: my_app
publish_to: 'none'

environment:
  sdk: ^3.12.2

dependencies:
  flutter:
    sdk: flutter

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0

flutter:
  uses-material-design: true

  # To add assets to your application, add an assets section, like this:
  # assets:
  #   - images/a_dot_burr.jpeg
''';

void main() {
  late Directory scratch;

  setUp(() => scratch = Directory.systemTemp.createTempSync('f3d_init_'));
  tearDown(() => scratch.deleteSync(recursive: true));

  void writePubspec(String content) =>
      File('${scratch.path}/pubspec.yaml').writeAsStringSync(content);

  test('a fresh project plans all four steps', () {
    writePubspec(_freshPubspec);
    final steps = planInit(scratch);
    expect(steps, hasLength(4));
    expect(steps.every((s) => !s.blocked), isTrue);
  });

  test('a real run writes the hook, both pubspec entries, and .gitignore', () async {
    writePubspec(_freshPubspec);
    final out = _BufferSink();
    final code = await runInit(<String>[], out: out, projectRoot: scratch);
    expect(code, 0);

    final hook = File('${scratch.path}/hook/build.dart');
    expect(hook.existsSync(), isTrue);
    expect(hook.readAsStringSync(), kHookBuildContent);

    final pubspec = File('${scratch.path}/pubspec.yaml').readAsStringSync();
    expect(
      pubspec,
      contains('flutter3d_build: $kFlutter3dBuildVersionConstraint'),
    );
    expect(pubspec, contains('- flutter3d_generated/'));
    // The original, still-commented example line is untouched — init adds
    // an active entry, it does not rewrite what was already there.
    expect(pubspec, contains('#   - images/a_dot_burr.jpeg'));

    final gitignore = File('${scratch.path}/.gitignore').readAsStringSync();
    expect(gitignore, contains(kGitignoreEntry));
  });

  test('a second run is a clean no-op', () async {
    writePubspec(_freshPubspec);
    await runInit(<String>[], out: _BufferSink(), projectRoot: scratch);

    final pubspecBefore = File(
      '${scratch.path}/pubspec.yaml',
    ).readAsStringSync();
    final hookBefore = File('${scratch.path}/hook/build.dart').readAsStringSync();

    final out = _BufferSink();
    final code = await runInit(<String>[], out: out, projectRoot: scratch);
    expect(code, 0);
    expect(out.text, contains('already up to date'));
    expect(planInit(scratch), isEmpty);

    expect(
      File('${scratch.path}/pubspec.yaml').readAsStringSync(),
      pubspecBefore,
      reason: 'a second run must not touch a line it already wrote',
    );
    expect(
      File('${scratch.path}/hook/build.dart').readAsStringSync(),
      hookBefore,
    );
  });

  test('--check reports without writing anything', () async {
    writePubspec(_freshPubspec);
    final out = _BufferSink();
    final code = await runInit(<String>['--check'], out: out, projectRoot: scratch);
    expect(code, 1);
    expect(out.text, contains('hook/build.dart'));
    expect(File('${scratch.path}/hook/build.dart').existsSync(), isFalse);
    expect(
      File('${scratch.path}/pubspec.yaml').readAsStringSync(),
      _freshPubspec,
    );
  });

  test('a hook a person edited is left alone without --force', () async {
    writePubspec(_freshPubspec);
    await runInit(<String>[], out: _BufferSink(), projectRoot: scratch);

    final hook = File('${scratch.path}/hook/build.dart');
    hook.writeAsStringSync('// a person added something here\n$kHookBuildContent');

    final err = _BufferSink();
    final code = await runInit(<String>[], err: err, out: _BufferSink(), projectRoot: scratch);
    expect(code, 1);
    expect(err.text, contains('refusing to overwrite without --force'));
    expect(hook.readAsStringSync(), contains('a person added something'));
  });

  test('--force overwrites an edited hook', () async {
    writePubspec(_freshPubspec);
    await runInit(<String>[], out: _BufferSink(), projectRoot: scratch);

    final hook = File('${scratch.path}/hook/build.dart');
    hook.writeAsStringSync('// a person added something here\n');

    final code = await runInit(
      <String>['--force'],
      out: _BufferSink(),
      projectRoot: scratch,
    );
    expect(code, 0);
    expect(hook.readAsStringSync(), kHookBuildContent);
  });

  test('an existing active assets: list keeps its own entries', () async {
    writePubspec('''
name: my_app
environment:
  sdk: ^3.12.2

flutter:
  uses-material-design: true

  assets:
    - assets/levels/
    - assets/sounds/
''');
    await runInit(<String>[], out: _BufferSink(), projectRoot: scratch);
    final pubspec = File('${scratch.path}/pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- assets/levels/'));
    expect(pubspec, contains('- assets/sounds/'));
    expect(pubspec, contains('- flutter3d_generated/'));
  });

  test('a pubspec.yaml with no flutter: section at all gets one', () async {
    writePubspec('''
name: my_app
environment:
  sdk: ^3.12.2
''');
    await runInit(<String>[], out: _BufferSink(), projectRoot: scratch);
    final pubspec = File('${scratch.path}/pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('flutter:'));
    expect(pubspec, contains('  assets:'));
    expect(pubspec, contains('    - flutter3d_generated/'));
  });

  test('an existing dev_dependencies: block keeps its own entries', () async {
    writePubspec(_freshPubspec);
    await runInit(<String>[], out: _BufferSink(), projectRoot: scratch);
    final pubspec = File('${scratch.path}/pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('flutter_lints: ^6.0.0'));
    expect(pubspec, contains('flutter3d_build:'));
  });

  test(
    'a source in a subdirectory gets its own assets: entry too — '
    'Flutter does not bundle a declared directory recursively',
    () async {
      // `ap-12`'s own real-world find: `flutter_tools`' own asset bundler
      // lists a declared directory with plain `listSync()` (no
      // `recursive: true`), so `- flutter3d_generated/` alone bundles only
      // what sits directly in it — never `flutter3d_generated/models/`,
      // where a source under `assets_src/models/` actually converts to.
      writePubspec(_freshPubspec);
      File('${scratch.path}/assets_src/models/chair.glb')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('not a real glb, just a recognised extension');

      final steps = planInit(scratch);
      expect(
        steps.any(
          (s) => s.description.contains('flutter3d_generated/models/'),
        ),
        isTrue,
        reason:
            'a source under assets_src/models/ needs its own generated/ '
            'subdirectory declared, not just the root',
      );

      await runInit(<String>[], out: _BufferSink(), projectRoot: scratch);
      final pubspec = File('${scratch.path}/pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('- flutter3d_generated/'));
      expect(pubspec, contains('- flutter3d_generated/models/'));

      // Idempotent with both entries already there, exactly like the
      // single-entry case.
      expect(planInit(scratch), isEmpty);
    },
  );

  test('a pinned flutter3d_build constraint is left as the person set it', () {
    writePubspec('''
name: my_app
environment:
  sdk: ^3.12.2

dev_dependencies:
  flutter3d_build: ^0.5.0
''');
    final steps = planInit(scratch);
    expect(
      steps.any((s) => s.description.contains('dev_dependencies')),
      isFalse,
      reason: 'already present, whatever the version, is already satisfied',
    );
  });

  test('a missing target directory fails cleanly', () async {
    final err = _BufferSink();
    final code = await runInit(
      <String>[Directory('${scratch.path}/nope').path],
      err: err,
    );
    expect(code, 1);
    expect(err.text, contains('No such directory'));
  });

  test('--help asks for the usage text, not a crash', () async {
    final err = _BufferSink();
    final code = await runInit(<String>['--help'], err: err);
    expect(code, 2);
    expect(err.text, contains('Usage: dart run flutter3d_build:init'));
    expect(err.text, contains('--force'));
  });

  test('an unrecognised flag asks for the usage text too', () async {
    final err = _BufferSink();
    final code = await runInit(<String>['--nope'], err: err);
    expect(code, 2);
    expect(err.text, contains('Usage:'));
  });
}

final class _BufferSink implements IOSink {
  final StringBuffer _buffer = StringBuffer();
  String get text => _buffer.toString();

  @override
  void writeln([Object? object = '']) => _buffer.writeln(object);

  @override
  void write(Object? object) => _buffer.write(object);

  @override
  void add(List<int> data) => _buffer.write(utf8.decode(data));

  @override
  Encoding encoding = utf8;

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      add(chunk);
    }
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> get done => Future<void>.value();

  @override
  Future<void> flush() async {}

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      _buffer.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => _buffer.writeCharCode(charCode);
}
