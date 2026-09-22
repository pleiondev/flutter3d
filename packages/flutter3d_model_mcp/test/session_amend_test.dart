/// `tut-03`: `ModelSession.amend` — the operation card's own slider,
/// reachable from outside the application, with the adjustment actually
/// reaching the session's own recovery journal this time.
///
///     dart test test/session_amend_test.dart
library;

import 'dart:io';

import 'package:flutter3d_mesh/flutter3d_mesh.dart' show ParametricCuboid;
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  late Directory workspace;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('model_session_amend');
  });

  tearDown(() {
    workspace.deleteSync(recursive: true);
  });

  test('adjusts the top step in place rather than pushing a second one', () {
    final session = ModelSession(ModelHistory(const ModelProject()));
    session.run(const AddPrimitive(kind: 'box', size: 1.0));

    final amended = session.amend(const AddPrimitive(kind: 'box', size: 2.0));

    expect(amended.did, isTrue, reason: amended.says);
    expect(session.project.objects, hasLength(1));
    expect(session.history.steps, hasLength(1)); // still one step, adjusted
    final shape =
        (session.project.objects.single.geometry as ParametricGeometry).shape;
    expect((shape as ParametricCuboid).size, Vector3.all(2.0));
  });

  test('refuses, by name, the same way ModelHistory.amend does, when there '
      'is nothing to adjust', () {
    final session = ModelSession(ModelHistory(const ModelProject()));
    final amended = session.amend(const AddPrimitive(kind: 'box'));
    expect(amended.did, isFalse);
    expect(amended.says, contains('nothing to adjust'));
  });

  test('a refused replacement leaves the old step and its journal line in '
      'place', () {
    final session = ModelSession(ModelHistory(const ModelProject()));
    session.run(const AddPrimitive(kind: 'box', size: 1.0));

    final amended = session.amend(const AddPrimitive(kind: 'not-a-shape'));

    expect(amended.did, isFalse);
    final shape =
        (session.project.objects.single.geometry as ParametricGeometry).shape;
    expect((shape as ParametricCuboid).size, Vector3.all(1.0));

    final journalPath = '${workspace.path}/refused.jsonl';
    session.journal(journalPath);
    expect(File(journalPath).readAsStringSync(), contains('"size":1.0'));
  });

  test('tut-03, the row\'s own symptom, fixed: the journal names the '
      'adjusted argument, and a cold replay reaches the adjusted state', () {
    final session = ModelSession(ModelHistory(const ModelProject()));
    session.run(const AddPrimitive(kind: 'box', size: 1.0));
    session.amend(const AddPrimitive(kind: 'box', size: 2.0));

    final journalPath = '${workspace.path}/amend.jsonl';
    session.journal(journalPath);
    final lines = File(journalPath).readAsLinesSync();
    expect(lines, hasLength(1));
    expect(lines.single, contains('"size":2.0'));

    final replay = CommandJournal.replay(
      File(journalPath).readAsBytesSync(),
      const ModelProject(),
    );
    expect(replay.ok, isTrue, reason: replay.refused);
    final shape =
        (replay.history!.project.objects.single.geometry as ParametricGeometry)
            .shape;
    expect((shape as ParametricCuboid).size, Vector3.all(2.0));
  });

  test('records as StepAuthor.agent, the same as every other session.run', () {
    final session = ModelSession(ModelHistory(const ModelProject()));
    session.run(const AddPrimitive(kind: 'box', size: 1.0));
    session.amend(const AddPrimitive(kind: 'box', size: 2.0));

    expect(session.history.topStepAuthor, StepAuthor.agent);

    final journalPath = '${workspace.path}/author.jsonl';
    session.journal(journalPath);
    final replay = CommandJournal.replay(
      File(journalPath).readAsBytesSync(),
      const ModelProject(),
    );
    expect(replay.ok, isTrue, reason: replay.refused);
    expect(replay.history!.topStepAuthor, StepAuthor.agent);
  });
}
