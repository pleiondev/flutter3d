/// The `experiment.*` tools: an agent opens the pendulum experiment beside a
/// level, edits it one value at a time, is refused what the reader refuses,
/// takes an edit back and saves inside the project only.
///
///     dart test test/editor/experiment_tools_test.dart
///
/// Each test was written by breaking what it covers; the mutation is named.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_education/experiment.dart';
import 'package:flutter3d_mcp/editor.dart';
import 'package:test/test.dart';

void main() {
  late Directory sandbox;
  late Directory project;
  late EditorSession session;
  late String experiment;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('editor_experiment');
    project = Directory('${sandbox.path}/lab')..createSync();
    File('${project.path}/pubspec.yaml').writeAsStringSync('name: lab\n');
    Directory('${project.path}/assets/levels').createSync(recursive: true);
    final level = '${project.path}/assets/levels/pendulum.level.json';
    File(level).writeAsStringSync(
      jsonEncode(<String, Object?>{'version': 1, 'name': 'pendulum'}),
    );
    experiment = '${project.path}/assets/levels/pendulum.f3d.experiment';
    File(experiment).writeAsStringSync(
      File(
        '../flutter3d_education/test/fixtures/v1/pendulum.f3d.experiment',
      ).readAsStringSync(),
    );
    session = EditorSession.open(level);
  });

  tearDown(() => sandbox.deleteSync(recursive: true));

  Future<Answer> call(String name, Map<String, Object?> arguments) =>
      Future<Answer>.value(
        editorTools
            .firstWhere((EditorTool it) => it.name == name)
            .run(session, arguments),
      );

  test('an agent opens, edits, undoes and saves the pendulum', () async {
    final none = await call('experiment.list', const <String, Object?>{});
    expect(none.did, isFalse);

    final opened = await call('experiment.open', <String, Object?>{
      'path': experiment,
    });
    expect(opened.did, isTrue, reason: opened.says);
    expect(opened.says, contains('parameter length = 1.0 m from 0.2 m'));
    expect(opened.says, contains('step 1 shorten: set length 0.25 m'));

    final edited = await call('experiment.edit', <String, Object?>{
      'edit': 'setParameter',
      'arguments': <String, Object?>{'id': 'length', 'value': '1.5 m'},
    });
    // Mutation: drop the arguments on the way to the edit.
    expect(edited.did, isTrue, reason: edited.says);
    expect(session.experiment!.document.parameter('length')!.value.value, 1.5);

    final refused = await call('experiment.edit', <String, Object?>{
      'edit': 'removeProbe',
      'arguments': <String, Object?>{'id': 'period'},
    });
    expect(refused.did, isFalse);
    expect(refused.says, contains('not a probe'));

    final undone = await call('experiment.undo', const <String, Object?>{});
    expect(undone.says, contains('set parameter length'));
    await call('experiment.undo', <String, Object?>{'redo': true});

    final saved = await call('experiment.save', const <String, Object?>{});
    expect(saved.did, isTrue);
    expect(
      ExperimentDocument.parse(
        File(experiment).readAsStringSync(),
      ).parameter('length')!.value.value,
      1.5,
    );
  });

  test('a document outside the project is neither read nor written', () async {
    File('${sandbox.path}/stray.f3d.experiment').writeAsStringSync('{}');
    // Mutation: read the path unresolved.
    final outside = await call('experiment.open', <String, Object?>{
      'path': '${sandbox.path}/stray.f3d.experiment',
    });
    expect(outside.did, isFalse);
    expect(outside.says, contains('outside the project'));

    await call('experiment.open', <String, Object?>{'path': experiment});
    final escaping = await call('experiment.save', <String, Object?>{
      'path': '../../escaped.f3d.experiment',
    });
    expect(escaping.did, isFalse);
    expect(
      File('${sandbox.path}/escaped.f3d.experiment').existsSync(),
      isFalse,
    );
  });

  test('a file the reader refuses does not open', () async {
    File(experiment).writeAsStringSync(
      File(experiment).readAsStringSync().replaceFirst(
        '"probe": "period"',
        '"probe": "speed"',
      ),
    );
    final refused = await call('experiment.open', <String, Object?>{
      'path': experiment,
    });
    expect(refused.did, isFalse);
    expect(refused.says, contains('"speed"'));
    expect(session.experiment, isNull);
  });
}
