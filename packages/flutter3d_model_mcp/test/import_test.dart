/// `ModelSession.import`, wired through `doc-11a-n`'s own `importInto` —
/// the end-to-end path `importInto`'s own tests in `flutter3d_model_core`
/// do not reach, since those call the pure function directly.
///
///     dart test test/import_test.dart
library;

import 'dart:io';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';
import 'package:test/test.dart';

void main() {
  group('import', () {
    test('a file that does not exist is refused', () async {
      final session = ModelSession(ModelHistory(const ModelProject()));
      final answer = await session.import('test/fixtures/does-not-exist.glb');
      expect(answer.did, isFalse);
    });

    test('importing the same file twice merges materials and images '
        'rather than doubling them', () async {
      final session = ModelSession(ModelHistory(const ModelProject()));

      final first = await session.import('test/fixtures/table.glb');
      expect(first.did, isTrue, reason: first.says);
      final objectsAfterFirst = session.history.project.objects.length;
      final materialsAfterFirst = session.history.project.materials.length;
      final imagesAfterFirst = session.history.project.images.length;
      expect(objectsAfterFirst, greaterThan(0));

      final second = await session.import('test/fixtures/table.glb');
      expect(second.did, isTrue, reason: second.says);

      // Mutation: revert `import` to its own pre-`importInto` merge (every
      // object copied across with `materialSlots` left pointing at the
      // *document's* own table rather than folded into the project's) —
      // this would still show objects doubling, but the material and image
      // counts would double right along with them instead of staying put.
      expect(session.history.project.objects.length, objectsAfterFirst * 2);
      expect(session.history.project.materials.length, materialsAfterFirst);
      expect(session.history.project.images.length, imagesAfterFirst);
    });

    test('undoing the second import returns the exact first project, by '
        'identical', () async {
      final session = ModelSession(ModelHistory(const ModelProject()));

      await session.import('test/fixtures/table.glb');
      final afterFirst = session.history.project;

      await session.import('test/fixtures/table.glb');
      expect(identical(session.history.project, afterFirst), isFalse);

      session.history.undo();
      // `ModelHistory` keeps the project it replaced as a plain value, not
      // a diff to reverse — the same reason every other `ReplaceDocument`
      // undo in this project already holds, and the acceptance this test
      // is named for.
      expect(identical(session.history.project, afterFirst), isTrue);
    });

    // `tut-01`'s own acceptance: `ImportOptions` reaches `session.import`
    // now, and reads a file the identical way `fromModelDocument` already
    // does when called directly with the same options.
    test('options: ImportOptions(scale: 0.001) scales an import exactly '
        'the way fromModelDocument does called directly with the same '
        'options', () async {
      const stlPath = '../flutter3d_formats/test/fixtures/stl/cube.stl';
      final bytes = File(stlPath).readAsBytesSync();
      final document = await StlLoader().load(bytes);
      final direct = fromModelDocument(
        document,
        options: const ImportOptions(scale: 0.001),
      );

      final session = ModelSession(ModelHistory(const ModelProject()));
      final answer = await session.import(
        stlPath,
        options: const ImportOptions(scale: 0.001),
      );
      expect(answer.did, isTrue, reason: answer.says);

      expect(writeProject(session.history.project), writeProject(direct));
    });

    // The regression guard the same row asks for: a call with no options at
    // all still behaves exactly as it did before `ImportOptions` reached
    // this far — unscaled, up axis `y`, every object left as
    // `ImportedGeometry`.
    test('called with no options at all still behaves exactly as it does '
        'today', () async {
      const stlPath = '../flutter3d_formats/test/fixtures/stl/cube.stl';
      final bytes = File(stlPath).readAsBytesSync();
      final document = await StlLoader().load(bytes);
      final direct = fromModelDocument(document);

      final session = ModelSession(ModelHistory(const ModelProject()));
      final answer = await session.import(stlPath);
      expect(answer.did, isTrue, reason: answer.says);

      expect(writeProject(session.history.project), writeProject(direct));
      expect(
        session.history.project.objects.every(
          (ModelObject o) => o.geometry is ImportedGeometry,
        ),
        isTrue,
        reason: 'weld/fixNormals/triangulate all default to off',
      );
    });
  });
}
