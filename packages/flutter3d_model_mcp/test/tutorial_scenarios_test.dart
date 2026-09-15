/// `tut-00`'s own "туториал как тест": every case in the modeler tutorial
/// (`cloud/server/content/learn/modeler/`) is also a `.jsonl` scenario here,
/// replayed the way `journal_replay_test.dart` replays a session's own
/// journal — a case that only "worked" by hand and was never replayed this
/// way is not trusted the same way. Later cases are added to this same file
/// as T5's animation screens land and cases 4–6 become writable.
///
///     dart test test/tutorial_scenarios_test.dart
library;

import 'dart:io';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart' show EditMesh;
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

import 'fixtures/tutorial/case1_scenario.dart';

void main() {
  group('case 1 — a prop from a scan', () {
    late Directory workspace;

    setUp(() {
      workspace = Directory.systemTemp.createTempSync('tutorial_case1');
    });

    tearDown(() {
      workspace.deleteSync(recursive: true);
    });

    test("the case's own journal replays onto a fresh import to the exact "
        'project committed as its .f3dproj fixture', () async {
      // The import step itself is not on the journal — see
      // `case1_scenario.dart`'s own doc comment for why `ReplaceDocument`
      // (what `session.import` would have run) is not journalable — so
      // replay starts from the project right after import, built fresh
      // here rather than read back from anything this test wrote itself.
      final imported = await case1ImportedProject();

      final journalBytes = File(
        'test/fixtures/tutorial/case1.jsonl',
      ).readAsBytesSync();
      final replay = CommandJournal.replay(journalBytes, imported);
      expect(replay.ok, isTrue, reason: replay.refused);

      final replayedBytes = writeProject(replay.history!.project);
      final fixtureBytes = File(
        'test/fixtures/tutorial/case1.f3dproj',
      ).readAsBytesSync();
      expect(
        replayedBytes,
        fixtureBytes,
        reason:
            'the project the journal replays to is not the one in '
            'test/fixtures/tutorial/case1.f3dproj. If the change was '
            'meant, rerun tool/make_case1_fixtures.dart and read the diff '
            'before committing the new fixtures',
      );
    });

    test('building the scenario fresh against ModelSession reaches the same '
        'journal and the same exported GLB as the fixtures', () async {
      final imported = await case1ImportedProject();
      final path = '${workspace.path}/case1.f3dproj';
      final session = ModelSession(ModelHistory(imported), path: path);
      runCase1Scenario(session);

      final journaled = session.journal('${workspace.path}/case1.jsonl');
      expect(journaled.did, isTrue, reason: journaled.says);
      expect(
        File('${workspace.path}/case1.jsonl').readAsStringSync(),
        File('test/fixtures/tutorial/case1.jsonl').readAsStringSync(),
      );

      final exported = session.export('${workspace.path}/case1.glb');
      expect(exported.did, isTrue, reason: exported.says);
      final writtenGlb = File('${workspace.path}/case1.glb').readAsBytesSync();
      final fixtureGlb = File(
        'test/fixtures/tutorial/case1.glb',
      ).readAsBytesSync();
      expect(writtenGlb, fixtureGlb);

      // `compareModelDocuments` on top of the byte check: the acceptance
      // criterion the plan names by name, over the two GLBs decoded back
      // rather than over their raw bytes, so a change that reordered
      // vertices without losing any of them would still be caught by the
      // byte check above and separately confirmed geometry-equal here.
      final writtenDocument = await GltfLoader().load(writtenGlb);
      final fixtureDocument = await GltfLoader().load(fixtureGlb);
      expect(compareModelDocuments(fixtureDocument, writtenDocument), isEmpty);
    });

    test('readiness before export: one warning, none of it an error — the '
        "case's own diagnosis step", () async {
      final imported = await case1ImportedProject();
      final session = ModelSession(ModelHistory(imported));
      runCase1Scenario(session);

      final readiness = ExportReadiness.check(session.project);
      expect(readiness.canExport, isTrue);
      expect(readiness.issues, hasLength(1));
      expect(readiness.says, contains('two pieces of surface meet at a point'));
    });

    test('cleanup finds nothing left to do once import has already welded', () {
      // Grounds the case page's own claim that `cleanup` is a real no-op
      // here, not a step the page merely asserts without checking: an
      // `ImportedGeometry` object has no topology `cleanup` could act on
      // (`mesh_commands.dart`'s own `_meshTarget`), and the screen's own
      // "weld" checkbox — replayed here as `importMeshData` — already
      // welded what there was to weld before `cleanup` ever runs.
      final answer = ModelSession(
        ModelHistory(
          const ModelProject().added(
            (id) => ModelObject(
              id: id,
              name: 'welded already',
              geometry: EditedGeometry(EditMesh.cuboid()),
              transform: Matrix4.identity(),
            ),
          ),
        ),
      ).cleanup();
      expect(answer.did, isFalse);
      expect(answer.says, contains('nothing needed cleaning'));
    });
  });
}
