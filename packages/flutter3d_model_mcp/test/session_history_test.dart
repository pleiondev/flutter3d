/// `ModelSession.save`'s own `includeHistory` — `doc-31d` wired to the one
/// place an agent actually calls `save` from.
///
///     dart test test/session_history_test.dart
library;

import 'dart:io';

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  late Directory workspace;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('model_session_history');
  });

  tearDown(() {
    workspace.deleteSync(recursive: true);
  });

  ModelSession sessionWithOneBlock() {
    var project = const ModelProject();
    project = project.added(
      (int id) => ModelObject(
        id: id,
        name: 'block',
        geometry: EditedGeometry(EditMesh.cuboid()),
        transform: Matrix4.identity(),
      ),
    );
    final history = ModelHistory(project);
    history.selection = ProjectSelection(
      mode: SelectionMode.object,
      objects: const <int>[1],
    );
    return ModelSession(history);
  }

  test('the default save writes no history — the same bytes as before this '
      'row existed', () {
    final session = sessionWithOneBlock();
    session.run(MoveBy(Vector3(1, 0, 0)));
    final path = '${workspace.path}/plain.f3dproj';

    final saved = session.save(path);
    expect(saved.did, isTrue, reason: saved.says);

    final reopened = ModelSession.open(path);
    expect(reopened.history.canUndo, isFalse);
  });

  test('save(includeHistory: true) reopens with real undo already on the '
      'stack', () {
    final session = sessionWithOneBlock();
    session.run(MoveBy(Vector3(1, 0, 0)));
    session.run(MoveBy(Vector3(0, 2, 0)));
    final path = '${workspace.path}/with_history.f3dproj';

    // Mutation: pass `history: null` regardless of `includeHistory` in
    // `ModelSession.save` — `reopened.history.canUndo` would read false
    // here exactly the way the test above expects it to for the *default*
    // call, and only asking for both in the same file tells them apart.
    session.save(path, includeHistory: true);

    final reopened = ModelSession.open(path);
    expect(reopened.history.canUndo, isTrue);
    expect(reopened.undo().did, isTrue);
    expect(reopened.history.canUndo, isTrue);
    expect(reopened.undo().did, isTrue);
    expect(reopened.history.canUndo, isFalse);
    expect(
      reopened.history.project.objects.single.transform.getTranslation(),
      Vector3.zero(),
    );
  });

  group('mcp-10n: an agent\'s own undo does not reach a person\'s step', () {
    test('session.undo() refuses, by name, when the top step is not this '
        'session\'s own', () {
      final session = sessionWithOneBlock();
      session.run(MoveBy(Vector3(1, 0, 0))); // through session.run: agent

      // A step this session never made — the same shape a person's own
      // edit at the app takes, run straight against the shared
      // `ModelHistory` rather than through `session.run`.
      session.history.run(MoveBy(Vector3(0, 1, 0)));

      // Mutation: call `history.undo(onlyIfAuthoredBy: StepAuthor.agent)`
      // without checking `topStepAuthor` first and reporting `did: true`
      // regardless — the underlying `ModelHistory.undo` would correctly
      // do nothing, but this session's own `Answer` would still claim it
      // worked, which is exactly the "clear sentence" the row's own
      // acceptance asks a refusal to have instead.
      final answer = session.undo();
      expect(answer.did, isFalse);
      expect(answer.says, contains('person'));
      expect(session.history.steps, hasLength(2)); // nothing taken back
    });

    test('session.undo() succeeds once the top step really is this '
        'session\'s own', () {
      final session = sessionWithOneBlock();
      session.run(MoveBy(Vector3(1, 0, 0)));
      session.run(MoveBy(Vector3(0, 1, 0)));

      final answer = session.undo();
      expect(answer.did, isTrue);
      expect(session.history.steps, hasLength(1));
    });
  });
}
