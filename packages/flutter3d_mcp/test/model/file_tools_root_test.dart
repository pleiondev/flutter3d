/// The modeller's file tools — `save`, `export`, `import`, `journal` — read
/// and write inside the session's project and nowhere else.
///
///     dart test test/model/file_tools_root_test.dart
///
/// Each payload is an argument a prompt could put in an agent's call. Each
/// test was written by breaking what it covers; the mutation is named.
library;

import 'dart:io';

import 'package:flutter3d_mcp/kit.dart' show ProjectRoot;
import 'package:flutter3d_mcp/model.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Link;
import 'package:test/test.dart';

void main() {
  late Directory sandbox;
  late Directory project;
  late ModelSession session;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('model_file_tools');
    project = Directory('${sandbox.path}/project')..createSync();
    File('${sandbox.path}/outside.glb').writeAsBytesSync(<int>[1, 2, 3]);
    session = ModelSession(
      ModelHistory(const ModelProject()),
      path: '${project.path}/model.f3dproj',
    );
  });

  tearDown(() => sandbox.deleteSync(recursive: true));

  Future<({bool did, String says})> call(
    String name,
    Map<String, Object?> arguments,
  ) async {
    final answer = await modelTools
        .firstWhere((ModelTool it) => it.name == name)
        .run(session, arguments);
    return (did: answer.did, says: answer.says);
  }

  test('the root is the project the session was opened in', () {
    // Mutation: default the root to the working directory. The suite's own
    // package would be the project and the temp directory outside it.
    expect(session.root.path, ProjectRoot(project.path).path);
  });

  test(
    'a write that leaves the project is refused and writes nothing',
    () async {
      await call('addPrimitive', <String, Object?>{'kind': 'box'});
      // Mutation: hand `to` to the session unresolved (as before 1.0).
      // Each of these writes a file beside the project.
      for (final (tool, key, where) in <(String, String, String)>[
        ('export', 'to', '../escaped.glb'),
        ('export', 'to', '${sandbox.path}/escaped.obj'),
        ('journal', 'to', '../escaped.jsonl'),
        ('save', 'path', '../escaped.f3dproj'),
      ]) {
        final answer = await call(tool, <String, Object?>{key: where});
        expect(answer.did, isFalse, reason: '$tool $where');
        expect(answer.says, contains('outside the project'));
      }
      expect(
        sandbox.listSync().map((FileSystemEntity it) => it.path).toSet(),
        <String>{project.path, '${sandbox.path}/outside.glb'},
      );
    },
  );

  test(
    'a read from outside the project is refused before it is opened',
    () async {
      // Mutation: import from `from` unresolved. The bytes of a file the
      // agent was never given would be in the project, and an export later.
      for (final where in <String>[
        '../outside.glb',
        '${sandbox.path}/outside.glb',
        '/etc/passwd',
      ]) {
        final answer = await call('import', <String, Object?>{'from': where});
        expect(answer.did, isFalse, reason: where);
        expect(answer.says, contains('outside the project'));
      }
      expect(session.project.objects, isEmpty);
    },
  );

  test('a link in the project that leads out is refused', () async {
    Link('${project.path}/out').createSync(sandbox.path);
    await call('addPrimitive', <String, Object?>{'kind': 'box'});
    // Mutation: resolve without following links. `out/` is a directory of
    // the project by its name and the sandbox by what it is.
    final answer = await call('export', <String, Object?>{
      'to': 'out/escaped.glb',
    });
    expect(answer.did, isFalse);
    expect(answer.says, contains('a link in it leads out'));
    expect(File('${sandbox.path}/escaped.glb').existsSync(), isFalse);
  });

  test(
    'a path inside the project, relative or not, is written there',
    () async {
      await call('addPrimitive', <String, Object?>{'kind': 'box'});
      final relative = await call('export', <String, Object?>{
        'to': 'exports/../box.glb',
      });
      expect(relative.did, isTrue, reason: relative.says);
      expect(File('${project.path}/box.glb').existsSync(), isTrue);
      final journal = await call('journal', <String, Object?>{
        'to': '${project.path}/run.jsonl',
      });
      expect(journal.did, isTrue, reason: journal.says);
      expect(File('${project.path}/run.jsonl').existsSync(), isTrue);
    },
  );
}
