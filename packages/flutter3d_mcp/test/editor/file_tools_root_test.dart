/// The level editor's file tools — `save`, `capture_open`,
/// `render_capture_save` — read and write inside the level's project and
/// nowhere else.
///
///     dart test test/editor/file_tools_root_test.dart
///
/// Each payload is an argument a prompt could put in an agent's call. Each
/// test was written by breaking what it covers; the mutation is named.
library;

import 'dart:io';

import 'package:flutter3d_mcp/editor.dart';
import 'package:test/test.dart';

void main() {
  late Directory sandbox;
  late Directory project;
  late String level;
  late EditorSession session;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('editor_file_tools');
    project = Directory('${sandbox.path}/game')..createSync();
    File('${project.path}/pubspec.yaml').writeAsStringSync('name: game\n');
    Directory('${project.path}/assets/levels').createSync(recursive: true);
    level = '${project.path}/assets/levels/level.first.json';
    File(level).writeAsStringSync(
      File('test/editor/fixtures/shooter.first.json').readAsStringSync(),
    );
    File('${sandbox.path}/capture.json').writeAsStringSync('{}');
    session = EditorSession.open(level);
  });

  tearDown(() => sandbox.deleteSync(recursive: true));

  Future<PictureAnswer> call(String name, Map<String, Object?> arguments) =>
      Future<PictureAnswer>.value(
        editorTools
            .firstWhere((EditorTool it) => it.name == name)
            .run(session, arguments),
      );

  test('the root is the project the level belongs to', () {
    // Mutation: take the level's own directory. A save into `test/` beside
    // `assets/` would be refused, and play's project would not be the root.
    expect(session.root.path, File(project.path).resolveSymbolicLinksSync());
  });

  test(
    'a save that leaves the project is refused and writes nothing',
    () async {
      // Mutation: write `path` unresolved, as before 1.0.
      for (final where in <String>[
        '../../../escaped.json',
        '${sandbox.path}/escaped.json',
      ]) {
        final answer = await call('save', <String, Object?>{'path': where});
        expect(answer.did, isFalse, reason: where);
        expect(answer.says, contains('outside the project'));
      }
      expect(File('${sandbox.path}/escaped.json').existsSync(), isFalse);
    },
  );

  test(
    'the generated level is not written over under another spelling',
    () async {
      // Mutation: compare the asked path with the level's as text. `./` or an
      // absolute path through a link names the same generated file, and the
      // save would claim it — the work the next generator run throws away.
      Link('${sandbox.path}/alias').createSync(project.path);
      for (final where in <String>[
        'assets/levels/./level.first.json',
        '${sandbox.path}/alias/assets/levels/level.first.json',
      ]) {
        final answer = await call('save', <String, Object?>{'path': where});
        expect(answer.did, isFalse, reason: where);
        expect(answer.says, contains('will not be overwritten'));
      }
      final copy = await call('save', <String, Object?>{
        'path': 'assets/levels/mine.json',
      });
      expect(copy.did, isTrue, reason: copy.says);
    },
  );

  test('a capture is opened only from inside the project', () async {
    Link('${project.path}/out').createSync(sandbox.path);
    // Mutation: open `path` unresolved. A file the agent was never given
    // would be read, and a parse error quotes it back.
    for (final where in <String>[
      '/etc/passwd',
      '../../capture.json',
      'out/capture.json',
    ]) {
      final answer = await call('capture_open', <String, Object?>{
        'path': where,
      });
      expect(answer.did, isFalse, reason: where);
      expect(answer.says, contains('is refused'), reason: where);
    }
  });

  test('a capture is written only inside the project, refused before the '
      'game is asked', () async {
    // Mutation: resolve after asking the game. The refusal would wait on a
    // VM service, and here none answers.
    final answer = await call('render_capture_save', <String, Object?>{
      'vmService': 'ws://127.0.0.1:9/nobody',
      'path': '../../../escaped.json',
    });
    expect(answer.did, isFalse);
    expect(answer.says, contains('outside the project'));
  });
}
