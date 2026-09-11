/// `mcp-12n`'s own acceptance at the session layer: a session's own
/// `journal()` file, replayed in a clean process, reaches the same project
/// `writeProject` would write for the session that made it — author
/// included, since `ModelSession.run` is the one caller that always names
/// `StepAuthor.agent`.
///
///     dart test test/journal_replay_test.dart
library;

import 'dart:io';

import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';
import 'package:test/test.dart';

void main() {
  late Directory workspace;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('model_mcp_journal');
  });

  tearDown(() {
    workspace.deleteSync(recursive: true);
  });

  test('a session\'s own journal replays to the same bytes writeProject '
      'would write for it, in a process that never saw the session', () {
    final session = ModelSession(ModelHistory(const ModelProject()));
    session.run(const AddPrimitive(kind: 'box'));
    session.run(const Rename(id: 1, to: 'crate'));
    session.run(const AddMaterial(materialName: 'oak'));
    session.run(const AssignMaterial(id: 1, to: 0));

    final path = '${workspace.path}/table.jsonl';
    final wrote = session.journal(path);
    expect(wrote.did, isTrue, reason: wrote.says);

    // "A clean process": nothing below reaches `session` again, only the
    // bytes it wrote to disk and the empty project every session starts
    // from.
    final replay = CommandJournal.replay(
      File(path).readAsBytesSync(),
      const ModelProject(),
    );
    expect(replay.ok, isTrue, reason: replay.refused);
    expect(
      writeProject(replay.history!.project),
      writeProject(session.project),
    );

    // Mutation: `ModelSession.run` recording to `_journal` with no author
    // (the default `StepAuthor.person`) — the byte comparison above would
    // still pass, since neither `ModelProject` carries a step's author;
    // this is what actually catches it.
    expect(replay.history!.topStepAuthor, StepAuthor.agent);
  });

  test('a recipe\'s own transaction replays as one step, not one per '
      'command inside it', () {
    final session = ModelSession(ModelHistory(const ModelProject()));
    session.buildFrom(<Map<String, Object?>>[
      <String, Object?>{'kind': 'box', 'name': 'trunk'},
      <String, Object?>{'kind': 'sphere', 'name': 'leaves', 'parent': 0},
    ]);

    final path = '${workspace.path}/tree.jsonl';
    session.journal(path);

    final replay = CommandJournal.replay(
      File(path).readAsBytesSync(),
      const ModelProject(),
    );
    expect(replay.ok, isTrue, reason: replay.refused);
    // Mutation: record each of buildFrom's own commands without the
    // transaction markers `ModelHistory.transaction` uses — four commands
    // (two addPrimitive, two rename) would replay as four steps instead of
    // one.
    expect(replay.history!.steps, hasLength(1));
    expect(
      writeProject(replay.history!.project),
      writeProject(session.project),
    );
  });
}
