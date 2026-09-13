/// `MaterialFileWriter` — the disk half of `mat-08`'s own round trip: link
/// (`LinkMaterialFile`, in `flutter3d_model_core`), edit (`SetMaterialField`),
/// write (this), read back (`readFmat`) with nothing left to warn about.
///
///     dart test test/material_file_writer_test.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/material_file_writer.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('mat08_fmat_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test(
    'link, edit, write, readFmat: the row\'s own acceptance, no warnings',
    () async {
      final history = ModelHistory(const ModelProject());
      history.run(const AddMaterial(materialName: 'steel'));
      history.run(
        const LinkMaterialFile(index: 0, path: 'materials/steel.fmat'),
      );
      history.run(
        const SetMaterialField(index: 0, field: 'roughness', value: 0.35),
      );
      history.run(
        const SetMaterialField(index: 0, field: 'metallic', value: 0.8),
      );
      final material = history.project.materials.single;

      await MaterialFileWriter.write(material, baseDir: dir.path);

      final written = File('${dir.path}/materials/steel.fmat');
      expect(written.existsSync(), isTrue);

      final document = readFmat(
        written.readAsBytesSync(),
        name: material.fmat!,
      );
      // Mutation: have `bytesFor` write the material's un-edited surface —
      // this catches it on the field the edit above actually changed.
      expect(document.surface.roughness, closeTo(0.35, 1e-6));
      expect(document.surface.metallic, closeTo(0.8, 1e-6));
      expect(document.surface.name, 'steel');
      expect(document.warnings, isEmpty);
    },
  );

  test(
    'writing an unlinked material refuses rather than guessing a path',
    () async {
      final material = ProjectMaterial(surface: SurfaceMaterial(name: 'brass'));

      await expectLater(
        () => MaterialFileWriter.write(material, baseDir: dir.path),
        throwsA(isA<StateError>()),
      );
      // Nothing was created.
      expect(Directory(dir.path).listSync(), isEmpty);
    },
  );

  test('bytesFor is exactly what write puts on disk', () async {
    final material = ProjectMaterial(
      surface: SurfaceMaterial(name: 'copper', roughness: 0.4),
      fmat: 'copper.fmat',
    );

    await MaterialFileWriter.write(material, baseDir: dir.path);

    final onDisk = File('${dir.path}/copper.fmat').readAsBytesSync();
    expect(onDisk, MaterialFileWriter.bytesFor(material));
  });

  test(
    'a hand-edited .fmat naming a shader this engine does not ship reads '
    'back as a warning, not a crash — the row\'s other acceptance clause',
    () {
      final file = File('${dir.path}/custom.fmat')
        ..writeAsStringSync(
          json.encode(<String, Object?>{
            'fmat': 1,
            'lighting': 'studio-toon-v3',
          }),
        );

      final document = readFmat(file.readAsBytesSync(), name: 'custom.fmat');
      expect(document.lighting, isNull);
      expect(document.warnings, hasLength(1));
      expect(document.warnings.single, contains('studio-toon-v3'));
    },
  );
}
