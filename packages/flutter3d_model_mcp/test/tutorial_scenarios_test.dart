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
import 'package:flutter3d_mesh/flutter3d_mesh.dart'
    show ArrayModifier, EditMesh, MirrorModifier;
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

import 'fixtures/tutorial/case1_scenario.dart';
import 'fixtures/tutorial/case2_scenario.dart';

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

  group('case 2 — a vase from a profile', () {
    late Directory workspace;

    setUp(() {
      workspace = Directory.systemTemp.createTempSync('tutorial_case2');
    });

    tearDown(() {
      workspace.deleteSync(recursive: true);
    });

    test("the case's own journal, replayed from an empty project, gets stuck "
        'exactly where mesh-element selection is missing — the real gap this '
        "case found (tut-05, doc/modeler-tutorial-gaps.md): `session.select`'s "
        'own doc comment already says object-level picking is not something '
        '`CommandJournal` can replay, and this is the first case whose edits '
        'actually depend on that at *mesh*-element level', () {
      final journalBytes = File(
        'test/fixtures/tutorial/case2.jsonl',
      ).readAsBytesSync();
      final replay = CommandJournal.replay(journalBytes, const ModelProject());
      // Mutation: assert `replay.ok` instead. A journal that replayed
      // clean from a cold project would mean mesh-element selection had
      // quietly become recoverable — worth celebrating, not a check this
      // test should pass by accident on a change nobody meant.
      expect(replay.ok, isFalse);
      expect(replay.refused, contains('no faces are selected to extrude'));
    });

    test('building the scenario fresh against ModelSession — selecting '
        'elements the way a live session or a person actually would — '
        'reaches the exact project committed as case2.f3dproj', () {
      final path = '${workspace.path}/case2.f3dproj';
      final session = ModelSession(
        ModelHistory(const ModelProject()),
        path: path,
      );
      runCase2Scenario(session);

      final saved = session.save(path);
      expect(saved.did, isTrue, reason: saved.says);
      final writtenBytes = File(path).readAsBytesSync();
      final fixtureBytes = File(
        'test/fixtures/tutorial/case2.f3dproj',
      ).readAsBytesSync();
      expect(
        writtenBytes,
        fixtureBytes,
        reason:
            'the project this scenario reaches is not the one in '
            'test/fixtures/tutorial/case2.f3dproj. If the change was '
            'meant, rerun tool/make_case2_fixtures.dart and read the diff '
            'before committing the new fixtures',
      );

      final journaled = session.journal('${workspace.path}/case2.jsonl');
      expect(journaled.did, isTrue, reason: journaled.says);
      expect(
        File('${workspace.path}/case2.jsonl').readAsStringSync(),
        File('test/fixtures/tutorial/case2.jsonl').readAsStringSync(),
      );
    });

    test('the modifier stack holds a mirror and an array, exactly as the '
        "case's own page describes", () {
      final session = ModelSession(ModelHistory(const ModelProject()));
      runCase2Scenario(session);

      final modifiers = session.project[1]!.modifiers;
      expect(modifiers, hasLength(2));
      expect(modifiers[0].modifier, isA<MirrorModifier>());
      expect(modifiers[1].modifier, isA<ArrayModifier>());
      final array = modifiers[1].modifier as ArrayModifier;
      expect(array.count, 3);
    });

    test('the last-operation card (ModelHistory.amend) re-runs the rim '
        'extrude against the mesh as it was before it, adjusting one step '
        'rather than leaving two — a real, working path, though `tut-03` '
        "is that nothing above `ModelHistory` itself can reach it: there is "
        'no `ModelSession.amend`, and `CommandJournal` never hears about the '
        'adjustment at all', () {
      ModelSession fresh(double distance) {
        final session = ModelSession(ModelHistory(const ModelProject()));
        session.run(
          AddLathe(profile: vaseProfile(), segments: 12, shapeName: 'vase'),
        );
        session.run(const BakeToMesh(1));
        session.select(
          object: 1,
          level: 'face',
          elements: <int>[for (var i = 0; i < 12; i++) 61 + i],
        );
        session.run(Extrude(distance));
        return session;
      }

      final session = fresh(0.04);
      final mesh = (session.project[1]!.geometry as EditedGeometry).mesh;

      // Mutation: call `session.run(Extrude(0.09))` instead of `amend`.
      // A second `run` would push a *second* step — two extrudes deep —
      // rather than adjusting the one already there, which is exactly
      // the distinction the operation card exists to make.
      final said = session.history.amend(const Extrude(0.09));
      expect(said, isNull);

      final directly = fresh(0.09);
      final directMesh = (directly.project[1]!.geometry as EditedGeometry).mesh;
      expect(mesh.faceSlotCount, directMesh.faceSlotCount);
      expect(
        _sortedCorners(mesh),
        _sortedCorners(directMesh),
        reason:
            'amend re-running the extrude against the document before it '
            'should land the rim at the same place a fresh 0.09 m '
            'extrude would, not on top of the original 0.04 m one',
      );

      // The gap itself, made concrete: the journal this session would
      // write still names the *original* distance, because `amend` runs
      // through `ModelHistory` directly and never reaches
      // `ModelSession`'s own `_journal.record`.
      final journalPath = '${workspace.path}/case2_amend.jsonl';
      session.journal(journalPath);
      final lines = File(journalPath).readAsLinesSync();
      expect(
        lines.firstWhere((l) => l.contains('"extrude"')),
        contains('"distance":0.04'),
      );
    });
  });
}

/// Every alive vertex position in [mesh], rounded and sorted — order-
/// independent so an amend that rebuilds a mesh's own vertex slots in a
/// different sequence than a fresh extrude still compares equal on shape.
List<String> _sortedCorners(EditMesh mesh) => <String>[
  for (var v = 0; v < mesh.vertexSlotCount; v++)
    if (mesh.isVertexAlive(v))
      mesh
          .positionOf(v)
          .storage
          .map((double c) => c.toStringAsFixed(4))
          .join(','),
]..sort();
