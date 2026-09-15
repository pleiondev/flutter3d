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
    show ArrayModifier, EditMesh, MirrorModifier, ParametricCuboid, weightsOf;
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';
import 'package:flutter3d_rig/flutter3d_rig.dart' show BoneMap, looseAutoMap;
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

import 'fixtures/tutorial/case1_scenario.dart';
import 'fixtures/tutorial/case2_scenario.dart';
import 'fixtures/tutorial/case3_scenario.dart';
import 'fixtures/tutorial/case4_scenario.dart';
import 'fixtures/tutorial/case5_scenario.dart';
import 'fixtures/tutorial/case6_scenario.dart';

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

    test("the case's own journal, replayed from an empty project, now "
        'rebuilds the exact document a live session reaches — `tut-05`, '
        'closed (doc/modeler-tutorial-gaps.md): `session.select` runs a '
        'real, if non-mutating, `SelectElements` command now, so the two '
        "rim/belly picks this case's own mesh edits depend on are on the "
        "journal too, and a cold replay no longer gets stuck at the first "
        'extrude for want of a selection nothing was recorded', () {
      final journalBytes = File(
        'test/fixtures/tutorial/case2.jsonl',
      ).readAsBytesSync();
      final replay = CommandJournal.replay(journalBytes, const ModelProject());
      // Mutation: assert `replay.ok` were false instead. A build that
      // stopped recording `select` as a real command would mean `tut-05`
      // had reopened — worth catching, not a check this test should pass
      // by accident on a change nobody meant.
      expect(replay.ok, isTrue, reason: replay.refused);
      expect(
        writeProject(replay.history!.project),
        File('test/fixtures/tutorial/case2.f3dproj').readAsBytesSync(),
        reason:
            'replaying case2.jsonl cold from an empty project should reach '
            'the identical document a live session reaches running the '
            'same steps through ModelSession.run/select',
      );
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

    test('the last-operation card (ModelSession.amend, `tut-03` fixed) '
        're-runs the rim extrude against the mesh as it was before it, '
        'adjusting one step rather than leaving two, and this time the '
        'journal hears about it too: a cold replay lands on the adjusted '
        'distance, not the original one', () {
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
      final amended = session.amend(const Extrude(0.09));
      expect(amended.did, isTrue, reason: amended.says);

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

      // `tut-03`, closed: the journal this session writes now names the
      // *adjusted* distance, because `ModelHistory.amend` records to
      // whichever journal is attached the same moment it re-runs the
      // replacement, rather than leaving the journal to a caller that
      // reached `ModelHistory` directly. (A cold replay of *this* journal
      // now also gets past its own earlier `select` calls too — `tut-05`,
      // closed alongside `tut-15` — though the next test below still
      // isolates `amend`'s own journal fix with a command that needs no
      // selection at all, on its own merits.)
      final journalPath = '${workspace.path}/case2_amend.jsonl';
      session.journal(journalPath);
      final lines = File(journalPath).readAsLinesSync();
      expect(
        lines.firstWhere((l) => l.contains('"extrude"')),
        contains('"distance":0.09'),
      );
    });

    test('`tut-03`, closed: a session\'s own journal, after an amend, '
        'replays cold to the adjusted state rather than the original one '
        '— with `addPrimitive`, a command that takes its own arguments '
        "rather than reading `session.select`, so this journal's own "
        'single line replays from nothing but itself, isolating `amend`\'s '
        "own fix from `tut-05`'s (both closed now, but this case's own "
        'rim/belly picks are not the only thing this test needs to prove '
        'not-broken)', () {
      final session = ModelSession(ModelHistory(const ModelProject()));
      final added = session.run(const AddPrimitive(kind: 'box', size: 1.0));
      expect(added.did, isTrue, reason: added.says);

      final amended = session.amend(const AddPrimitive(kind: 'box', size: 2.0));
      expect(amended.did, isTrue, reason: amended.says);
      expect(session.project.objects, hasLength(1));
      final geometry = session.project.objects.single.geometry;
      final shape = (geometry as ParametricGeometry).shape as ParametricCuboid;
      expect(shape.size, Vector3.all(2.0));

      final journalPath = '${workspace.path}/case2_amend_primitive.jsonl';
      session.journal(journalPath);
      final lines = File(journalPath).readAsLinesSync();
      // One line, not two: `amend` overwrote the original rather than
      // appending an adjustment beside it.
      expect(lines, hasLength(1));
      expect(lines.single, contains('"size":2.0'));

      final replay = CommandJournal.replay(
        File(journalPath).readAsBytesSync(),
        const ModelProject(),
      );
      expect(replay.ok, isTrue, reason: replay.refused);
      final replayedGeometry = replay.history!.project.objects.single.geometry;
      final replayedShape =
          (replayedGeometry as ParametricGeometry).shape as ParametricCuboid;
      expect(replayedShape.size, Vector3.all(2.0));
    });
  });

  group('case 3 — a lit corner', () {
    late Directory workspace;

    setUp(() {
      workspace = Directory.systemTemp.createTempSync('tutorial_case3');
    });

    tearDown(() {
      workspace.deleteSync(recursive: true);
    });

    test("the case's own journal, replayed from right after the import, now "
        'rebuilds the exact document a live session reaches — the same '
        'fix as case 2 (`tut-05`, closed), now at the plain object level '
        "`MoveBy`/`RotateBy` need rather than at mesh-element level: "
        "`ModelSession.select`'s own object-level pick runs a real "
        '`SelectElements` command now too, so the box pick this case '
        'depends on is on the journal', () async {
      final starting = await case3StartingProject();
      final journalBytes = File(
        'test/fixtures/tutorial/case3.jsonl',
      ).readAsBytesSync();
      final replay = CommandJournal.replay(journalBytes, starting);
      // Mutation: assert `replay.ok` were false instead. A build that
      // stopped recording `select` as a real command would mean `tut-05`
      // had reopened — worth catching, not a check this test should pass
      // by accident on a change nobody meant.
      expect(replay.ok, isTrue, reason: replay.refused);
      expect(
        writeProject(replay.history!.project),
        File('test/fixtures/tutorial/case3.f3dproj').readAsBytesSync(),
        reason:
            'replaying case3.jsonl cold from right after the import should '
            'reach the identical document a live session reaches running '
            'the same steps through ModelSession.run/select',
      );
    });

    test('building the scenario fresh against ModelSession — selecting the '
        'imported box the way a live session or a person actually would — '
        'reaches the exact project committed as case3.f3dproj, and exports '
        'the exact case3.glb', () async {
      final path = '${workspace.path}/case3.f3dproj';
      final starting = await case3StartingProject();
      final session = ModelSession(ModelHistory(starting), path: path);
      runCase3Scenario(session);

      final saved = session.save(path);
      expect(saved.did, isTrue, reason: saved.says);
      final writtenBytes = File(path).readAsBytesSync();
      final fixtureBytes = File(
        'test/fixtures/tutorial/case3.f3dproj',
      ).readAsBytesSync();
      expect(
        writtenBytes,
        fixtureBytes,
        reason:
            'the project this scenario reaches is not the one in '
            'test/fixtures/tutorial/case3.f3dproj. If the change was '
            'meant, rerun tool/make_case3_fixtures.dart and read the diff '
            'before committing the new fixtures',
      );

      final journaled = session.journal('${workspace.path}/case3.jsonl');
      expect(journaled.did, isTrue, reason: journaled.says);
      expect(
        File('${workspace.path}/case3.jsonl').readAsStringSync(),
        File('test/fixtures/tutorial/case3.jsonl').readAsStringSync(),
      );

      final exported = session.export('${workspace.path}/case3.glb');
      expect(exported.did, isTrue, reason: exported.says);
      final writtenGlb = File('${workspace.path}/case3.glb').readAsBytesSync();
      final fixtureGlb = File(
        'test/fixtures/tutorial/case3.glb',
      ).readAsBytesSync();
      expect(writtenGlb, fixtureGlb);

      final writtenDocument = await GltfLoader().load(writtenGlb);
      final fixtureDocument = await GltfLoader().load(fixtureGlb);
      expect(compareModelDocuments(fixtureDocument, writtenDocument), isEmpty);
    });

    test('the exported GLB carries both assets as their own surface-bearing '
        'nodes, at different placements, each keeping its own material — '
        "mat-24's own acceptance for `ImportInto` plus a gizmo move, now "
        'through a real case rather than `scene_multi_asset_export_test.dart'
        "'s in-memory `_Doc` fixtures", () async {
      final bytes = File('test/fixtures/tutorial/case3.glb').readAsBytesSync();
      final document = await GltfLoader().load(bytes);

      // Mutation: import the box but never run the `moveBy`/`rotateBy` — the
      // vase surface and the box surface would then carry equal or
      // near-identical transforms instead of two genuinely different
      // placements.
      expect(document.surfaces, hasLength(2));
      expect(
        document.surfaces[0].transform,
        isNot(equals(document.surfaces[1].transform)),
      );
      // The vase (surface 0) sat at the world origin in case 2 and case 3
      // never moves it — only the imported box (surface 1) is selected and
      // transformed.
      expect(document.surfaces[0].transform, Matrix4.identity());

      // Two genuinely different materials — the vase's own "glazed clay"
      // and the box's own textured material from `BoxTextured.glb` — so
      // both stay in the export rather than being deduped into one: doing
      // that here would misrepresent what a "shared material" check is
      // supposed to catch, which `import_into_test.dart`'s own dedup tests
      // already cover with two materials that really do match.
      expect(document.materials, hasLength(2));
      expect(document.surfaces[0].materialIndex, 0);
      expect(document.surfaces[1].materialIndex, 1);
    });

    test('the scene carries one point light, shadows on, a studio '
        "environment and bloom — T3.4's own four scene panels "
        '(sources/shadows/environment/post), each set through the real '
        "command its panel already runs", () async {
      final starting = await case3StartingProject();
      final session = ModelSession(ModelHistory(starting));
      runCase3Scenario(session);

      final lighting = session.project.lighting;
      expect(lighting.lights, hasLength(1));
      expect(lighting.lights.single.type, ProjectLightType.point);
      expect(lighting.lights.single.castsShadow, isTrue);
      expect(lighting.environment, SceneEnvironmentPreset.studio);
      expect(lighting.shadows, isTrue);
      expect(lighting.post.bloomEnabled, isTrue);
    });
  });

  group('case 4 — a character from a bare mesh', () {
    late Directory workspace;

    setUp(() {
      workspace = Directory.systemTemp.createTempSync('tutorial_case4');
    });

    tearDown(() {
      workspace.deleteSync(recursive: true);
    });

    test("the case's own journal, replayed from right after the import, now "
        'rebuilds the exact document a live session reaches — the same '
        "fix as cases 2 and 3's own `tut-05` (closed), now over the "
        "mesh-vertex selection this case's own shape key depends on: "
        '`PaintWeights` and `SetRig` both replayed clean cold already '
        "(neither one reads `session.select`), and the `TransformElements` "
        'that scales the chest out now has a real `SelectElements` line '
        'to read before it, the same as the `rotateBy` on the elbow after '
        'it', () async {
      final starting = await case4StartingProject();
      final journalBytes = File(
        'test/fixtures/tutorial/case4.jsonl',
      ).readAsBytesSync();
      final replay = CommandJournal.replay(journalBytes, starting);
      // Mutation: assert `replay.ok` were false instead. A build that
      // stopped recording `select` as a real command would mean `tut-05`
      // had reopened — worth catching, not a check this test should pass
      // by accident on a change nobody meant.
      expect(replay.ok, isTrue, reason: replay.refused);
      expect(
        writeProject(replay.history!.project),
        File('test/fixtures/tutorial/case4.f3dproj').readAsBytesSync(),
        reason:
            'replaying case4.jsonl cold from right after the import should '
            'reach the identical document a live session reaches running '
            'the same steps through ModelSession.run/select',
      );
    });

    test('building the scenario fresh against ModelSession — running the '
        'real buildSkeleton -> bindWeightsJobRequestFor -> SetRig pipeline, '
        'the way a live session or an agent over MCP actually would — '
        'reaches the exact project committed as case4.f3dproj, and exports '
        'the exact case4.glb', () async {
      final path = '${workspace.path}/case4.f3dproj';
      final starting = await case4StartingProject();
      final session = ModelSession(ModelHistory(starting), path: path);
      await runCase4Scenario(session);

      final saved = session.save(path);
      expect(saved.did, isTrue, reason: saved.says);
      final writtenBytes = File(path).readAsBytesSync();
      final fixtureBytes = File(
        'test/fixtures/tutorial/case4.f3dproj',
      ).readAsBytesSync();
      expect(
        writtenBytes,
        fixtureBytes,
        reason:
            'the project this scenario reaches is not the one in '
            'test/fixtures/tutorial/case4.f3dproj. If the change was '
            'meant, rerun tool/make_case4_fixtures.dart and read the diff '
            'before committing the new fixtures',
      );

      final journaled = session.journal('${workspace.path}/case4.jsonl');
      expect(journaled.did, isTrue, reason: journaled.says);
      expect(
        File('${workspace.path}/case4.jsonl').readAsStringSync(),
        File('test/fixtures/tutorial/case4.jsonl').readAsStringSync(),
      );

      final exported = session.export('${workspace.path}/case4.glb');
      expect(exported.did, isTrue, reason: exported.says);
      final writtenGlb = File('${workspace.path}/case4.glb').readAsBytesSync();
      final fixtureGlb = File(
        'test/fixtures/tutorial/case4.glb',
      ).readAsBytesSync();
      expect(writtenGlb, fixtureGlb);

      final writtenDocument = await GltfLoader().load(writtenGlb);
      final fixtureDocument = await GltfLoader().load(fixtureGlb);
      expect(compareModelDocuments(fixtureDocument, writtenDocument), isEmpty);
    });

    test('the rig this case builds is the real T4/T5 pipeline: a 17-joint '
        'humanoid skeleton, the body mesh actually bound to it, and weights '
        "that vary joint to joint — not a simplified stand-in", () async {
      final starting = await case4StartingProject();
      final session = ModelSession(ModelHistory(starting));
      await runCase4Scenario(session);

      final project = session.project;
      expect(project.skeletons, hasLength(1));
      final skeleton = project.skeletons.single;
      expect(skeleton.jointCount, 17);
      expect(skeleton.joints, hasLength(17));

      final body = project[case4BodyId]!;
      expect(body.skeletonIndex, 0);
      final mesh = (body.geometry as EditedGeometry).mesh;

      // Every live vertex is bound, weights summing to 1 — the same
      // acceptance `bindWeightsJobRequestFor`'s own test names — and more
      // than one joint actually carries weight across the mesh as a whole,
      // which a rig that only ever bound everything to a single joint could
      // not say.
      final jointsSeen = <int>{};
      for (var v = 0; v < mesh.vertexSlotCount; v++) {
        if (!mesh.isVertexAlive(v)) continue;
        final pairs = weightsOf(mesh, v);
        expect(pairs, isNotEmpty);
        final total = pairs.fold<double>(0, (sum, p) => sum + p.weight);
        expect(total, closeTo(1.0, 1e-4));
        for (final pair in pairs) {
          jointsSeen.add(pair.joint);
        }
      }
      expect(
        jointsSeen.length,
        greaterThan(1),
        reason:
            'a real distance-and-visibility bind over a whole body should '
            'reach more than one joint, not collapse to a single-joint '
            'assign',
      );
    });

    test('the case builds one real shape key with a real driver, and one '
        "short clip carrying both the elbow's own bend and the shape's own "
        'weight', () async {
      final starting = await case4StartingProject();
      final session = ModelSession(ModelHistory(starting));
      await runCase4Scenario(session);

      final body = session.project[case4BodyId]!;
      expect(body.shapeSet.keys, hasLength(1));
      expect(body.shapeSet.keys.single.name, 'chestPuff');
      expect(body.shapeDrivers, hasLength(1));
      final driver = body.shapeDrivers.single;
      expect(driver.shapeIndex, 0);
      expect(
        session.project[driver.jointId]!.name,
        'leftElbow',
        reason: 'the driver should read the same joint this case bends',
      );

      expect(session.project.clips, hasLength(1));
      final clip = session.project.clips.single;
      expect(clip.name, 'wave');
      expect(clip.tracks, hasLength(2));
      final rotationTrack = clip.tracks.firstWhere(
        (t) => t.track.path == AnimationPath.rotation,
      );
      expect(rotationTrack.track.keyCount, 2);
      final weightsTrack = clip.tracks.firstWhere(
        (t) => t.track.path == AnimationPath.weights,
      );
      expect(weightsTrack.track.keyCount, 2);
    });

    test('the exported GLB carries a real skin and a real animation clip — '
        'the acceptance line `rig_pipeline_mcp_test.dart`\'s own `anim-30` '
        'scenario already checks for this exact file, now through this '
        "case's own committed fixture", () async {
      final bytes = File('test/fixtures/tutorial/case4.glb').readAsBytesSync();
      final document = await GltfLoader().load(bytes);

      expect(
        document.skins,
        isNotEmpty,
        reason: 'the exported GLB has no skin — no skeleton made it across',
      );
      expect(
        document.animations,
        isNotEmpty,
        reason: 'the exported GLB has no animation — no clip made it across',
      );
      final hasRealKeys = document.animations.any(
        (AnimationClip clip) =>
            clip.tracks.any((AnimationTrack track) => track.times.length >= 2),
      );
      expect(
        hasRealKeys,
        isTrue,
        reason:
            'no animation track in the exported GLB carries more than one '
            'key',
      );
    });
  });

  group('case 5 — borrowing a walk', () {
    late Directory workspace;

    setUp(() {
      workspace = Directory.systemTemp.createTempSync('tutorial_case5');
    });

    tearDown(() {
      workspace.deleteSync(recursive: true);
    });

    test('looseAutoMap really does map this exact pair of rigs correctly — '
        "tut-13, closed: RiggedFigure.glb's own joint names follow neither "
        "Mixamo's `mixamorig:` convention nor 3ds Max Biped's `Bip01_` one, "
        'and their generic body words (`torso`/`arm`/`leg`/`neck`) are in '
        "neither of looseAutoMap's own synonym tables at all — its own "
        'third matching path reads them by chain position instead, off '
        "the trailing numeric index each of this file's own joint names "
        'carries', () async {
      final starting = await case5StartingProject();
      final source = await case5RetargetSource();
      final targetSkeleton = starting.skeletons.single;
      final sourceNames = <String>[
        for (final id in source.skeleton.joints) source.project[id]!.name,
      ];
      final targetNames = <String>[
        for (final id in targetSkeleton.joints) starting[id]!.name,
      ];
      final mapped = looseAutoMap(sourceNames, targetNames);
      // Mutation: assert `mapped.isEmpty` were true instead. A narrowed
      // `looseAutoMap` that stopped matching this file's own joint names
      // would mean tut-13 had reopened — worth catching, not a check this
      // test should pass by accident on a change nobody meant.
      expect(mapped.isEmpty, isFalse);
      expect(mapped.length, case5ExpectedAutoMap.length);
      for (final entry in case5ExpectedAutoMap.entries) {
        expect(
          mapped.targetOf(entry.key),
          entry.value,
          reason: '${entry.key} should auto-map onto ${entry.value}',
        );
      }
    });

    test('retargeting this exact pair of rigs with `lockFeet: true` (the '
        "default) no longer throws — tut-12, fixed: RiggedFigure.glb's own "
        "clip animates every joint's translation, rotation and scale, not "
        "only the root's, and used to make `_lockFeet`'s own "
        '`Map<int, RigTrack>` collapse a joint\'s three retargeted tracks '
        'onto one and read it back as if it always held a rotation; keying '
        'that lookup by node and path instead means every one of a '
        "joint's own three tracks — including the hip and knee rotation "
        'the foot lock itself corrects — survives', () async {
      final starting = await case5StartingProject();
      final source = await case5RetargetSource();
      final targetSkeleton = starting.skeletons.single;
      final request = RetargetClipJobRequest(
        sourceProject: source.project,
        sourceSkeleton: source.skeleton,
        sourceClip: source.clips.single,
        targetProject: starting,
        targetSkeleton: targetSkeleton,
        boneMap: const BoneMap(case5ExpectedAutoMap),
      );
      // Mutation: pass `lockFeet: false` here instead — the call would
      // still succeed either way, but the crash tut-12 named only ever
      // happened with `lockFeet` at its own default.
      final retargeted = await request.run();

      final targetJointByName = <String, int>{
        for (final id in targetSkeleton.joints) starting[id]!.name: id,
      };
      // Confirmed directly (see this file's own `tut-12` fixture probe):
      // this real clip animates translation, rotation *and* scale for
      // every one of the seventeen mapped joints, not only the root's —
      // the exact shape that used to make `_lockFeet`'s own lookup
      // collapse onto whichever of a joint's three tracks was built last.
      // Every mapped joint keeping all three tracks after retargeting is
      // the direct evidence none of them were dropped.
      for (final name in targetJointByName.keys) {
        final id = targetJointByName[name]!;
        final paths = retargeted.tracks
            .where((t) => t.objectId == id)
            .map((t) => t.track.path)
            .toSet();
        expect(paths, {
          AnimationPath.translation,
          AnimationPath.rotation,
          AnimationPath.scale,
        }, reason: '$name should keep all three of its own retargeted tracks');
      }
    });

    test("the case's own journal, replayed from right after case 4's own "
        "saved project, now rebuilds the exact document a live session's "
        'own `applyClipResult`/`extractRootMotion` calls reach — `tut-14`, '
        'fixed: `ApplyClipResult` is registered in `modelCommandNames`/'
        '`modelCommandFromJson` now, so a cold replay no longer refuses at '
        'its own first line for want of a name this build did not know — a '
        "different shape than cases 2–4's own `tut-05` (a command this "
        'build does know, refused for want of a selection), and one this '
        'fix actually closes', () async {
      final starting = await case5StartingProject();
      final journalBytes = File(
        'test/fixtures/tutorial/case5.jsonl',
      ).readAsBytesSync();
      final replay = CommandJournal.replay(journalBytes, starting);
      // Mutation: assert `replay.ok` were false instead. A build that
      // stopped knowing `applyClipResult` would mean `tut-14` had
      // reopened — worth catching, not a check this test should pass by
      // accident on a change nobody meant.
      expect(replay.ok, isTrue, reason: replay.refused);

      final path = '${workspace.path}/case5_replay.f3dproj';
      final replayed = ModelSession(replay.history!, path: path);
      final saved = replayed.save(path);
      expect(saved.did, isTrue, reason: saved.says);
      expect(
        File(path).readAsBytesSync(),
        File('test/fixtures/tutorial/case5.f3dproj').readAsBytesSync(),
        reason:
            'replaying case5.jsonl cold from right after case 4 should '
            'reach the identical document a live session reaches running '
            'the same two steps through ModelSession.run',
      );
    });

    test('building the scenario fresh against ModelSession — auto-mapping '
        'first and succeeding (tut-13), retargeting with `lockFeet` at its '
        'own default (`true`, now that tut-12 is fixed), and extracting '
        'root motion "in code" — reaches the exact project committed as '
        'case5.f3dproj, and exports the exact case5.glb', () async {
      final path = '${workspace.path}/case5.f3dproj';
      final starting = await case5StartingProject();
      final session = ModelSession(ModelHistory(starting), path: path);
      await runCase5Scenario(session);

      final saved = session.save(path);
      expect(saved.did, isTrue, reason: saved.says);
      final writtenBytes = File(path).readAsBytesSync();
      final fixtureBytes = File(
        'test/fixtures/tutorial/case5.f3dproj',
      ).readAsBytesSync();
      expect(
        writtenBytes,
        fixtureBytes,
        reason:
            'the project this scenario reaches is not the one in '
            'test/fixtures/tutorial/case5.f3dproj. If the change was '
            'meant, rerun tool/make_case5_fixtures.dart and read the diff '
            'before committing the new fixtures',
      );

      final journaled = session.journal('${workspace.path}/case5.jsonl');
      expect(journaled.did, isTrue, reason: journaled.says);
      expect(
        File('${workspace.path}/case5.jsonl').readAsStringSync(),
        File('test/fixtures/tutorial/case5.jsonl').readAsStringSync(),
      );

      final exported = session.export('${workspace.path}/case5.glb');
      expect(exported.did, isTrue, reason: exported.says);
      final writtenGlb = File('${workspace.path}/case5.glb').readAsBytesSync();
      final fixtureGlb = File(
        'test/fixtures/tutorial/case5.glb',
      ).readAsBytesSync();
      expect(writtenGlb, fixtureGlb);

      final writtenDocument = await GltfLoader().load(writtenGlb);
      final fixtureDocument = await GltfLoader().load(fixtureGlb);
      expect(compareModelDocuments(fixtureDocument, writtenDocument), isEmpty);
    });

    test('the retargeted clip carries every mapped joint, keeps case 4\'s '
        "own \"wave\" clip untouched, and its root motion has been "
        'extracted into extras', () async {
      final starting = await case5StartingProject();
      final session = ModelSession(ModelHistory(starting));
      await runCase5Scenario(session);

      final project = session.project;
      expect(project.clips, hasLength(2));
      expect(project.clips[0].name, 'wave');

      final retargeted = project.clips[1];
      // Seventeen mapped joints × translation/rotation/scale; the file's
      // own two toe joints (`leg_joint_L_5`/`leg_joint_R_5`) have no
      // humanoid bone to land on and are dropped, per `retargetClip`'s own
      // "a track whose source node the bone map does not answer for is
      // dropped rather than guessed at."
      expect(retargeted.tracks, hasLength(17 * 3));
      final targetSkeleton = project.skeletons.single;
      final mappedIds = targetSkeleton.joints.toSet();
      for (final track in retargeted.tracks) {
        expect(mappedIds, contains(track.objectId));
      }
      expect(retargeted.extras, contains('flutter3dRootMotion'));
      final rootMotion = retargeted.extras!['flutter3dRootMotion']! as List;
      expect(rootMotion, hasLength(2));
    });

    test('the exported GLB carries two animations — case 4\'s own short '
        'clip and the retargeted walk — the second with real multi-key '
        'tracks', () async {
      final bytes = File('test/fixtures/tutorial/case5.glb').readAsBytesSync();
      final document = await GltfLoader().load(bytes);

      expect(document.skins, isNotEmpty);
      expect(document.animations, hasLength(2));
      final retargetedAnimation = document.animations.firstWhere(
        (AnimationClip clip) => clip.tracks.length > 2,
      );
      expect(retargetedAnimation.tracks, hasLength(17 * 3));
      final hasRealKeys = retargetedAnimation.tracks.any(
        (AnimationTrack track) => track.times.length >= 2,
      );
      expect(hasRealKeys, isTrue);
    });
  });

  group('case 6 — an agent beside you', () {
    late Directory workspace;

    setUp(() {
      workspace = Directory.systemTemp.createTempSync('tutorial_case6');
    });

    tearDown(() {
      workspace.deleteSync(recursive: true);
    });

    test("the case's own journal, replayed cold from the same post-import "
        "project case 1 starts from, now reproduces the person's own "
        'roughness edit too — that edit used to never reach this '
        "session's own recovery journal at all, because it ran directly "
        'against `ModelHistory` rather than through `ModelSession.run`/the '
        'tool surface. `tut-15`, closed (doc/modeler-tutorial-gaps.md): '
        '`ModelHistory.run` now records to whichever journal is attached '
        'regardless of which door a caller comes in through, so a person\'s '
        "own edit on the same shared history an agent's `--mcp-port` "
        'session is bound over lands on the recovery file exactly where it '
        'happened, under `StepAuthor.person`', () async {
      final imported = await case1ImportedProject();
      final journalBytes = File(
        'test/fixtures/tutorial/case6.jsonl',
      ).readAsBytesSync();
      final replay = CommandJournal.replay(journalBytes, imported);
      expect(replay.ok, isTrue, reason: replay.refused);

      final material = replay.history!.project.materials.single.surface;
      // The agent's own tool calls (baseColor, metallic) are real
      // `ModelCommand`s run through `ModelSession.run` and *do* survive a
      // cold replay, same as every earlier case.
      for (final (i, expected) in <double>[0.92, 0.89, 0.82, 1.0].indexed) {
        expect(material.baseColor.storage[i], closeTo(expected, 1e-6));
      }
      expect(material.metallic, 0.0);
      // Mutation: assert `closeTo(0.5, 1e-9)` instead — `SetMaterialField`'s
      // own default roughness (`flutter3d_formats`' `SurfaceMaterial`),
      // which is what a cold replay reached silently before `tut-15` was
      // fixed, since the person's own edit was not on the journal at all.
      expect(material.roughness, closeTo(0.35, 1e-9));
      // The step's own author survives the round trip too — recorded as
      // `StepAuthor.person` (`ModelHistory.run`'s own default when nobody
      // names one, the same as `ModelerCubit.run`), which is what a cold
      // replay needs to get right for an agent's own later `undo` to
      // refuse reaching past this step the way the live session does (see
      // the "undo restricted to only the agent's own steps" test below).
      final HistoryStep roughnessStep = replay.history!.steps.firstWhere(
        (HistoryStep step) =>
            step.command is SetMaterialField &&
            (step.command as SetMaterialField).field == 'roughness',
      );
      expect(roughnessStep.author, StepAuthor.person);
    });

    test('building the scenario fresh against ModelSession — calling the '
        'real MCP tool handlers with JSON arguments, the way an MCP client '
        "actually would (`tools_test.dart`'s own pattern), not the raw "
        'ModelCommand constructors cases 1-5 called directly — reaches the '
        'exact project committed as case6.f3dproj, and exports the exact '
        'case6.glb', () async {
      final path = '${workspace.path}/case6.f3dproj';
      final imported = await case1ImportedProject();
      final session = ModelSession(ModelHistory(imported), path: path);
      await runCase6Scenario(session);

      final saved = session.save(path);
      expect(saved.did, isTrue, reason: saved.says);
      final writtenBytes = File(path).readAsBytesSync();
      final fixtureBytes = File(
        'test/fixtures/tutorial/case6.f3dproj',
      ).readAsBytesSync();
      expect(
        writtenBytes,
        fixtureBytes,
        reason:
            'the project this scenario reaches is not the one in '
            'test/fixtures/tutorial/case6.f3dproj. If the change was '
            'meant, rerun tool/make_case6_fixtures.dart and read the diff '
            'before committing the new fixtures',
      );

      final journaled = session.journal('${workspace.path}/case6.jsonl');
      expect(journaled.did, isTrue, reason: journaled.says);
      expect(
        File('${workspace.path}/case6.jsonl').readAsStringSync(),
        File('test/fixtures/tutorial/case6.jsonl').readAsStringSync(),
      );

      final exported = session.export('${workspace.path}/case6.glb');
      expect(exported.did, isTrue, reason: exported.says);
      final writtenGlb = File('${workspace.path}/case6.glb').readAsBytesSync();
      final fixtureGlb = File(
        'test/fixtures/tutorial/case6.glb',
      ).readAsBytesSync();
      expect(writtenGlb, fixtureGlb);

      final writtenDocument = await GltfLoader().load(writtenGlb);
      final fixtureDocument = await GltfLoader().load(fixtureGlb);
      expect(compareModelDocuments(fixtureDocument, writtenDocument), isEmpty);
    });

    test('undo restricted to only the agent\'s own steps is a real, working '
        'mechanism today (mcp-10n), not a gap: `session.undo()` — the exact '
        'method the "undo" tool calls — refuses once the top step is a '
        "person's own, by name, and leaves it and everything before it in "
        "place; a person's own ⌘Z, unlike the agent's, is not gated the "
        'same way, and reaches straight past it', () async {
      final imported = await case1ImportedProject();
      final session = ModelSession(ModelHistory(imported));
      await runCase6Scenario(session);

      // The scenario's last step was the agent's own `assignMaterial` tool
      // call, run after the person's own roughness edit.
      expect(session.history.topStepAuthor, StepAuthor.agent);

      final undoTool = modelTools.firstWhere((ModelTool t) => t.name == 'undo');
      final firstUndo = await undoTool.run(session, const <String, Object?>{});
      expect(firstUndo.did, isTrue, reason: firstUndo.says);
      expect(firstUndo.says, contains('undid assign a material'));

      // Mutation: assert `StepAuthor.agent` here instead. The top step is
      // now the person's own roughness edit — `ModelSession.undo`'s own
      // check (`history.topStepAuthor != StepAuthor.agent`) is what the next
      // call actually refuses on.
      expect(session.history.topStepAuthor, StepAuthor.person);

      final secondUndo = await undoTool.run(session, const <String, Object?>{});
      expect(secondUndo.did, isFalse);
      expect(secondUndo.says, contains("is a person's own"));
      expect(secondUndo.says, contains('an agent does not undo'));

      // The person's own edit is untouched — the refusal changed nothing.
      final afterRefusal = session.project.materials.single.surface;
      expect(afterRefusal.roughness, closeTo(0.35, 1e-9));
      expect(afterRefusal.metallic, 0.0);

      // A person's own ⌘Z in the real app calls `ModelHistory.undo()` with
      // no restriction at all (`ModelerCubit` never passes
      // `onlyIfAuthoredBy`) — reaching straight past their own step, which
      // an agent's own undo just refused to do.
      final personsOwnUndo = session.history.undo();
      expect(personsOwnUndo, isTrue);
      expect(session.history.topStepAuthor, StepAuthor.agent);
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
