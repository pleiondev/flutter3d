import 'dart:io';

import 'package:flutter3d_build/src/build_exceptions.dart';
import 'package:flutter3d_build/src/convert/ply_mesh.dart';
import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show Level;
import 'package:test/test.dart';

import 'convert_support.dart';

void main() {
  late Directory scratch;
  setUp(() => scratch = Directory.systemTemp.createTempSync('f3d_models_'));
  tearDown(() => scratch.deleteSync(recursive: true));

  test('glTF: a model, its material as .fmat with its layers, and a level '
      'placing it', () async {
    final run = await convert(<String>[
      '$fixtures/triangle.gltf',
    ], output: scratch);
    expect(run.code, 0);
    expect(run.wrote('triangle.f3d'), isTrue);
    final material = readFmat(
      File('${scratch.path}/materials/triangle_Lacquer.fmat').readAsBytesSync(),
    );
    expect(material.surface.roughness, closeTo(0.4, 1e-6));
    expect(material.surface.extensions?.clearcoat, 1.0);
    expect(
      run.report('triangle.gltf')['mapped'],
      contains(contains('clearcoat')),
    );

    final level = run.readJson('triangle.level.json')! as Map<String, Object?>;
    expect(level['version'], Level.formatVersion);
    final row = run.rows('triangle.level.json', 'triangle').single;
    expect(row['type'], 'model');
    expect((row['asset']! as String).endsWith('triangle.f3d'), isTrue);
  });

  test(
    'OBJ with an MTL: the map is copied once and named from the .fmat',
    () async {
      final run = await convert(<String>[
        '$fixtures/quad.obj',
      ], output: scratch);
      expect(run.code, 0);
      expect(run.wrote('textures/wood.png'), isTrue);
      final material = readFmat(
        File('${scratch.path}/materials/quad_Wood.fmat').readAsBytesSync(),
      );
      expect(material.images, <String>['../textures/wood.png']);
      // No level for a format without a scene.
      expect(run.wrote('quad.level.json'), isFalse);
    },
  );

  test('STL: a model and no material', () async {
    final run = await convert(<String>['$fixtures/wedge.stl'], output: scratch);
    expect(run.code, 0);
    expect(run.report('wedge.stl')['written'], <String>['wedge.f3d']);
  });

  group('PLY', () {
    test('ASCII with colours: a quad of two triangles, the extra property '
        'named', () {
      final warnings = <String>[];
      final document = readPlyMesh(
        File('$fixtures/quad_ascii.ply').readAsBytesSync(),
        warnings: warnings,
      );
      expect(document.triangleCount, 2);
      expect(document.surfaces.single.authoredAttributes, contains('color'));
      expect(warnings.single, contains('confidence'));
    });

    test('binary little-endian: one triangle, normals worked out', () {
      final document = readPlyMesh(
        File('$fixtures/tri_binary.ply').readAsBytesSync(),
      );
      expect(document.triangleCount, 1);
      expect(
        document.surfaces.single.authoredAttributes,
        isNot(contains('normal')),
      );
    });

    test('a cloud of points without faces is refused by name', () {
      expect(
        () => readPlyMesh(File('$fixtures/cloud_points.ply').readAsBytesSync()),
        throwsA(
          isA<SourceFormatException>().having(
            (SourceFormatException e) => e.message,
            'message',
            contains('point cloud'),
          ),
        ),
      );
    });

    test('a splat capture is told apart by its header', () {
      expect(
        isSplatPly(File('$fixtures/quad_ascii.ply').readAsBytesSync()),
        isFalse,
      );
    });
  });
}
