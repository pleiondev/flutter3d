/// `audit` and `repair` on `flutter3d_model_core`'s broken fixture GLB — see
/// its `test/broken_asset.dart` for the faults it carries — and `import`
/// passing on what the reader said.
///
///     dart test test/audit_tool_test.dart
library;

import 'dart:io';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';
import 'package:test/test.dart';

const String _broken = '../flutter3d_model_core/test/fixtures/broken_asset.glb';

Future<ModelSession> _imported() async {
  final session = ModelSession(ModelHistory(const ModelProject()));
  final answer = await session.import(_broken);
  expect(answer.did, isTrue, reason: answer.says);
  return session;
}

void main() {
  test('an empty project refuses rather than auditing nothing', () async {
    final session = ModelSession(ModelHistory(const ModelProject()));
    final answer = await auditTool.run(session, const <String, Object?>{});
    expect(answer.did, isFalse);
    expect(answer.png, isNull);
  });

  test('audit names every fault and draws all seven views, changing '
      'nothing', () async {
    final session = await _imported();
    final before = session.history.project;

    final answer = await auditTool.run(session, const <String, Object?>{});
    expect(answer.did, isTrue);
    for (final String check in <String>[
      'units:',
      'pivot:',
      'materials:',
      'mesh:',
    ]) {
      expect(answer.says, contains(check));
    }
    expect(answer.says, contains('unit "cm"'));
    expect(identical(session.history.project, before), isTrue);

    // Four columns of two rows: seven views and one empty tile.
    final sheet = (await decodeImagePure(answer.png!))!;
    expect((sheet.width, sheet.height), (1024, 512));
  });

  test('repair puts the base on the origin and the meshes right, as one '
      'step, and leaves units and materials to the person', () async {
    final session = await _imported();
    final stepsBefore = session.history.steps.length;
    final before = session.history.project;
    final sizeBefore = AssetAudit.of(before).size;

    final answer = await auditTool.run(session, const <String, Object?>{
      'repair': true,
    });
    expect(answer.did, isTrue, reason: answer.says);
    expect(answer.says, contains('before:'));
    expect(answer.says, contains('after:'));

    final after = AssetAudit.of(session.history.project);
    // Mutation: drop the `MoveBy` from `repairAsset` — the origin stays a
    // hundred metres from the base and this fails.
    expect(after.pivotDistance, closeTo(0, 1e-3), reason: after.says);
    expect(after.size, closeTo(sizeBefore, 1e-3));
    expect(after.meshes, isEmpty, reason: 'every mesh is editable now');
    expect(
      after.findings.map((AuditFinding f) => f.check).toSet(),
      <AuditCheck>{AuditCheck.units, AuditCheck.materials},
      reason: after.says,
    );
    for (final ModelObject object in session.history.project.objects) {
      expect(object.geometry, isA<EditedGeometry>());
    }

    expect(session.history.steps.length, stepsBefore + 1);
    session.history.undo();
    expect(identical(session.history.project, before), isTrue);
  });

  test('import passes on what the reader said about the file', () async {
    final dir = Directory.systemTemp.createTempSync('audit_tool_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final obj = File('${dir.path}/stray.obj')
      ..writeAsStringSync('v 0 0 0\nv 1 0 0\nv 0 1 0\nusemtl ghost\nf 1 2 3\n');
    final session = ModelSession(ModelHistory(const ModelProject()));
    final answer = await session.import(obj.path);
    expect(answer.did, isTrue, reason: answer.says);
    // Mutation: drop the `report.issues` suffix from `import` — fails here.
    expect(answer.says, contains('the reader said'));
    expect(answer.says, contains('"ghost" was never defined'));
  });
}
