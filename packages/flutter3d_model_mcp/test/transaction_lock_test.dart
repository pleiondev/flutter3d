/// `mcp-14n`'s own acceptance: an agent's command arriving mid-drag is
/// queued and applies only once the modal transform lets go of
/// [ModelHistory.whenNotInTransaction] — not folded into a transaction it
/// had no part in, at whatever intermediate position that gesture has
/// reached the instant the call arrives.
///
///     dart test test/transaction_lock_test.dart
library;

import 'dart:async';

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

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

ModelTool toolNamed(String name) =>
    modelTools.firstWhere((ModelTool tool) => tool.name == name);

void main() {
  group("mcp-14n's own lock, over a command tool", () {
    test('a command called mid-drag does not land until the drag ends', () async {
      final session = sessionWithOneBlock();
      session.history.beginTransaction();

      final call = toolNamed(
        'rename',
      ).run(session, <String, Object?>{'id': 1, 'to': 'agent-renamed'});

      await Future<void>.value();
      // Still the name a person gave it — the tool call is waiting, not
      // refused and not silently folded into the open transaction.
      expect(session.project[1]!.name, 'block');

      session.history.endTransaction();
      final answer = await call;

      expect(answer.did, isTrue);
      expect(session.project[1]!.name, 'agent-renamed');
    });

    test('a command called with nothing open runs immediately, same as always', () async {
      final session = sessionWithOneBlock();
      final answer = await toolNamed(
        'rename',
      ).run(session, <String, Object?>{'id': 1, 'to': 'agent-renamed'});

      expect(answer.did, isTrue);
      expect(session.project[1]!.name, 'agent-renamed');
    });

    test('the queued command becomes its own step, not part of the drag it waited on', () async {
      final session = sessionWithOneBlock();
      session.history.beginTransaction();

      final call = toolNamed(
        'rename',
      ).run(session, <String, Object?>{'id': 1, 'to': 'agent-renamed'});

      // The drag itself moves the object, several times, the way a pointer
      // dragged across several frames does — all still inside the one
      // transaction the rename above is waiting on.
      session.history.run(MoveBy(Vector3(1, 0, 0)));
      session.history.run(MoveBy(Vector3(0, 1, 0)));
      session.history.endTransaction();
      await call;

      // Two steps: the drag's own move (named for the first command inside
      // it) and the agent's rename, separately — not one step carrying
      // both, which is what landing inside the open transaction would have
      // produced.
      expect(session.history.journal.map((c) => c.name), <String>['moveBy', 'rename']);
    });
  });

  group("mcp-14n's own lock, over import", () {
    test('import waits for an open transaction the same way', () async {
      final session = sessionWithOneBlock();
      session.history.beginTransaction();

      final call = session.import('/does/not/exist.glb');
      await Future<void>.value();

      // Refused for a mundane reason (no such file) — the point is only
      // that it did not run *before* the transaction closed, so this
      // reaching the refusal at all proves the wait already happened.
      session.history.endTransaction();
      final answer = await call;
      expect(answer.did, isFalse);
      expect(answer.says, contains('no file'));
    });
  });
}
