import 'dart:io';
import 'dart:math' as math;

import 'package:flutter3d_build/src/build_exceptions.dart';
import 'package:flutter3d_build/src/convert/unity_yaml.dart';
import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

import 'convert_support.dart';

const String _project = '$fixtures/unity';

void main() {
  late Directory scratch;
  late ConvertRun run;
  setUpAll(() async {
    scratch = Directory.systemTemp.createTempSync('f3d_unity_');
    run = await convert(<String>[
      '$_project/Assets/Scenes/Room.unity',
    ], output: scratch);
  });
  tearDownAll(() => scratch.deleteSync(recursive: true));

  List<Map<String, Object?>> rows(String prefab) =>
      run.rows('Room.level.json', prefab);

  group('the YAML reader', () {
    test('objects by file ID, stripped ones marked, built-in GUIDs kept as '
        'text', () {
      final objects = parseUnityYaml(
        File('$_project/Assets/Prefabs/Shelf.prefab').readAsStringSync(),
      );
      expect(objects[200000]!.type, 'GameObject');
      expect(objects[500002]!.stripped, isTrue);
      expect(
        unityRef(objects[3300000]!['m_Mesh'])!.guid,
        '0000000000000000e000000000000000',
      );
    });

    test('a binary asset is refused with the setting that fixes it', () {
      expect(
        () => parseUnityYaml('\u0000\u0000binary'),
        throwsA(
          isA<SourceFormatException>().having(
            (SourceFormatException e) => e.message,
            'message',
            contains('Force Text'),
          ),
        ),
      );
    });

    test('the project is found above the asset and indexed by GUID', () {
      final index = UnityAssetIndex.around(
        '$_project/Assets/Scenes/Room.unity',
      );
      expect(index.length, 7);
      expect(
        index.path('a0000000000000000000000000000001')!.endsWith('crate.obj'),
        isTrue,
      );
    });
  });

  test('the scene converts', () {
    expect(run.code, 0, reason: run.text);
    expect(run.wrote('models/crate.f3d'), isTrue);
    expect(run.wrote('materials/Wood.fmat'), isTrue);
  });

  test('a nested prefab instance is an instance row, mirrored through Z', () {
    final shelf = rows('Room').firstWhere((r) => r['name'] == 'Shelf');
    expect(shelf['type'], 'prefab');
    expect(shelf['prefab'], 'Shelf');
    expect(shelf['at'], <Object?>[3.0, 0.0, -2.0]);
  });

  test('a model prefab is a model row with the importer\'s half turn', () {
    final loose = rows('Room').firstWhere((r) => r['name'] == 'LooseCrate');
    expect(loose['type'], 'model');
    expect(loose['at'], <Object?>[-2.0, 0.0, -1.0]);
    expect((loose['yaw']! as num).abs(), closeTo(math.pi, 1e-5));
  });

  test('a built-in cube is a prop with the .mat as its material', () {
    final cube = rows('Shelf').firstWhere((r) => r['type'] == 'prop');
    expect(cube['shape'], 'box');
    // The shelf's scale is taken into the box's size.
    expect(cube['size'], <Object?>[2.0, 0.1, 1.0]);
    expect(cube.containsKey('scale'), isFalse);
    expect(cube['material'], 'Wood');
  });

  test('a mesh row keeps its MeshRenderer\'s material and its turn', () {
    final body = rows('Crate').single;
    expect(body['materials'], <Object?>['Wood']);
    // 45° about Unity's Y is -45° in the engine's, then the half turn.
    expect(body['yaw'], closeTo(3 * math.pi / 4, 1e-5));
    expect(body['at'], <Object?>[0.0, 0.5, -1.0]);
  });

  test('the instance under a scaled parent is written out row by row, and '
      'says so', () {
    final report = run.report('Room.unity');
    expect(report['warnings'], contains(contains('TopCrate')));
    expect(report['dropped'], contains(contains('m_CastShadows')));
    expect(report['dropped'], contains(contains('lights')));
  });

  test('the level expands: the Shelf instance\'s rows land at its place', () {
    final level = Level.fromJson(
      run.readJson('Room.level.json')! as Map<String, Object?>,
    );
    final expanded = expandPrefabs(level);
    final cube = expanded.entities.firstWhere(
      (EntityDef e) => e.type == 'prop',
    );
    expect(cube.position.x, closeTo(3.0, 1e-5));
    expect(cube.position.z, closeTo(-2.0, 1e-5));
  });

  test('URP Lit: base map tiled, metal and smoothness repacked, two-sided', () {
    final wood = readFmat(
      File('${scratch.path}/materials/Wood.fmat').readAsBytesSync(),
    );
    expect(wood.surface.doubleSided, isTrue);
    expect(wood.surface.baseColorTexture?.transform?.scale.x, 2.0);
    expect(wood.surface.metallicRoughnessTexture, isNotNull);
    expect(wood.images, contains('../textures/Wood_orm.png'));
    expect(
      run.report('Room.unity')['dropped'],
      contains(contains('_DetailAlbedoMap')),
    );
  });
}
