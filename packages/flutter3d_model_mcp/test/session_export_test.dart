/// `ModelSession.export`/`.import`: `mcp-15n`'s own session verbs, gated by
/// `ExportReadiness` the same way `ui-17`'s screen is.
///
///     dart test test/session_export_test.dart
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
    workspace = Directory.systemTemp.createTempSync('model_session_export');
  });

  tearDown(() {
    workspace.deleteSync(recursive: true);
  });

  /// A quad (a warning: the writer cuts it) beside an object with no faces
  /// at all (an error: `ExportReadiness` refuses to write it).
  ModelSession sessionWithAGhostAndAQuad() {
    var project = const ModelProject();
    project = project.added(
      (int id) => ModelObject(
        id: id,
        name: 'panel',
        geometry: EditedGeometry(EditMesh.cuboid()),
        transform: Matrix4.identity(),
      ),
    );
    project = project.added(
      (int id) => ModelObject(
        id: id,
        name: 'ghost',
        geometry: EditedGeometry(EditMesh.empty()),
        transform: Matrix4.identity(),
      ),
    );
    return ModelSession(ModelHistory(project));
  }

  group('export', () {
    test('an object with no faces refuses the export and names it — the '
        "row's own worked example", () {
      final session = sessionWithAGhostAndAQuad();
      final path = '${workspace.path}/blocked.obj';

      final result = session.export(path);

      expect(result.did, isFalse);
      expect(result.says, contains('ghost'));
      expect(File(path).existsSync(), isFalse);
    });

    test('force writes it anyway and says what it cut — the row\'s own '
        'worked example', () {
      final session = sessionWithAGhostAndAQuad();
      final path = '${workspace.path}/forced.obj';

      final result = session.export(path, force: true);

      expect(result.did, isTrue, reason: result.says);
      expect(File(path).existsSync(), isTrue);
      // The cube is six quads: the writer cuts every one of them, and the
      // warning says so — `_wideFaces`'s own "more than three sides".
      expect(result.says, contains('more than three sides'));
    });

    test('an empty project is refused rather than written empty', () {
      final session = ModelSession(ModelHistory(const ModelProject()));
      final result = session.export('${workspace.path}/nothing.obj');

      expect(result.did, isFalse);
      expect(result.says, contains('nothing'));
    });

    test('glb is written through the same gate as obj and f3d', () {
      final session = sessionWithAGhostAndAQuad();
      final path = '${workspace.path}/forced.glb';

      final blocked = session.export(path);
      expect(blocked.did, isFalse);

      final written = session.export(path, force: true);
      expect(written.did, isTrue, reason: written.says);
      expect(File(path).existsSync(), isTrue);
    });
  });

  group('import', () {
    test('a written export reopens as the same shape it was written from',
        () async {
      final session = sessionWithAGhostAndAQuad();
      final path = '${workspace.path}/roundtrip.f3d';
      final written = session.export(path, force: true);
      expect(written.did, isTrue, reason: written.says);

      final blank = ModelSession(ModelHistory(const ModelProject()));
      final result = await blank.import(path);

      expect(result.did, isTrue, reason: result.says);
      // The panel's own quad survives; the ghost, with no faces, brings
      // nothing across for `importInto` to place.
      expect(blank.project.objects, isNotEmpty);
    });

    test('a path with nothing at it is refused rather than crashing',
        () async {
      final session = ModelSession(ModelHistory(const ModelProject()));
      final result = await session.import(
        '${workspace.path}/does-not-exist.glb',
      );

      expect(result.did, isFalse);
      expect(result.says, contains('no file'));
    });
  });
}
