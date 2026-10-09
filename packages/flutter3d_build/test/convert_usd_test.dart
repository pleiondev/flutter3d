import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_build/src/convert/usda.dart';
import 'package:flutter3d_build/src/convert/zip_reader.dart';
import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

import 'convert_support.dart';

void main() {
  late Directory scratch;
  setUp(() => scratch = Directory.systemTemp.createTempSync('f3d_usd_'));
  tearDown(() => scratch.deleteSync(recursive: true));

  group('the .usda reader', () {
    test('reads the layer metadata, prims, attributes and connections', () {
      final layer = parseUsda(
        File('$fixtures/usd/stage.usda').readAsStringSync(),
      );
      expect(layer.upAxis, 'Z');
      expect(layer.metersPerUnit, 1.0);
      final floor = layer.find('/World/Floor')!;
      expect(floor.typeName, 'Mesh');
      expect(floor['faceVertexCounts'], <Object?>[4.0]);
      expect(
        floor.properties['primvars:st']!.metadata['interpolation'],
        'faceVarying',
      );
      expect((floor['material:binding']! as UsdPath).text, '/World/Looks/Wood');
      final chair = layer.find('/World/Chair')!;
      final reference = chair.metadata['references'];
      expect(reference, isA<UsdAsset>());
      expect((reference! as UsdAsset).path, './prop.usda');
      final surface = layer.find('/World/Looks/Wood/Surface')!;
      expect(
        (surface['inputs:diffuseColor.connect']! as UsdPath).text,
        '/World/Looks/Wood/Texture.outputs:rgb',
      );
    });

    test('time samples read as their first, a variant set is read past', () {
      final layer = parseUsda('''
#usda 1.0
def Xform "A" {
    double3 xformOp:translate.timeSamples = { 0: (1, 2, 3), 10: (4, 5, 6) }
    variantSet "look" = { "red" { def Mesh "M" {} } }
    uniform token[] xformOpOrder = ["xformOp:translate"]
}
''');
      final a = layer.find('/A')!;
      expect(a['xformOp:translate'], <Object?>[1.0, 2.0, 3.0]);
      expect(a.children, isEmpty);
    });

    test('a binary layer is told apart by its magic', () {
      expect(isUsdCrate('PXR-USDC\u0000'.codeUnits), isTrue);
      expect(isUsdaText('#usda 1.0'.codeUnits), isTrue);
    });
  });

  test('a stored ZIP reads back entry by entry', () {
    final zip = UsdzZip()
      ..store('a.usda', Uint8List.fromList('#usda 1.0\n'.codeUnits))
      ..store('b.png', Uint8List.fromList(<int>[1, 2, 3]));
    final entries = readZip(zip.build());
    expect(entries.keys, <String>['a.usda', 'b.png']);
    expect(entries['b.png'], <int>[1, 2, 3]);
  });

  test('a stage: Z up turned to Y, a referenced layer as a nested prefab, '
      'its material as .fmat, its light dropped', () async {
    final run = await convert(<String>[
      '$fixtures/usd/stage.usda',
    ], output: scratch);
    expect(run.code, 0);
    final report = run.report('stage.usda');
    expect(report['mapped'], contains(contains('upAxis Z -> Y')));
    expect(report['dropped'], contains(contains('SphereLight')));
    expect(report['warnings'], contains(contains('other units')));

    final level = run.readJson('stage.level.json')! as Map<String, Object?>;
    final prefabs = level['prefabs']! as Map<String, Object?>;
    expect(prefabs.keys, containsAll(<String>['stage', 'prop']));
    final rows =
        ((prefabs['stage']! as Map<String, Object?>)['entities']!
                as List<Object?>)
            .cast<Map<String, Object?>>();
    final chair = rows.firstWhere(
      (Map<String, Object?> r) => r['name'] == 'Chair',
    );
    expect(chair['type'], 'prefab');
    expect(chair['prefab'], 'prop');
    // (2, 0, 0) in a Z-up layer is (2, 0, 0) in the engine's.
    expect(chair['at'], <Object?>[2.0, 0.0, 0.0]);

    final wood = readFmat(
      File('${scratch.path}/materials/stage_Wood.fmat').readAsBytesSync(),
    );
    expect(wood.surface.roughness, closeTo(0.7, 1e-6));
    expect(wood.images, <String>['../textures/wood.png']);

    // The prop layer is in centimetres: its 50-unit seat is half a metre.
    final prop = F3dDocument.parse(
      File('${scratch.path}/models/prop.f3d').readAsBytesSync(),
    );
    expect(prop.computeBounds().max.x, closeTo(0.5, 1e-5));
  });

  test(
    'a .usdz: the first entry is the layer, a translucent coated material',
    () async {
      final run = await convert(<String>[
        '$fixtures/usd/packaged.usdz',
      ], output: scratch);
      expect(run.code, 0);
      final red = readFmat(
        File('${scratch.path}/materials/packaged_Red.fmat').readAsBytesSync(),
      );
      expect(red.surface.alphaMode, SurfaceAlphaMode.blend);
      expect(red.surface.baseColor.a, closeTo(0.5, 1e-6));
      expect(red.surface.extensions?.clearcoat, 1.0);
    },
  );
}
