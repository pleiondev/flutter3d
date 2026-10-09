import 'dart:io';
import 'dart:math' as math;

import 'package:flutter3d_build/src/convert/godot_text.dart';
import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

import 'convert_support.dart';

const String _project = '$fixtures/godot';

void main() {
  late Directory scratch;
  late ConvertRun run;
  setUpAll(() async {
    scratch = Directory.systemTemp.createTempSync('f3d_godot_');
    run = await convert(<String>['$_project/room.tscn'], output: scratch);
  });
  tearDownAll(() => scratch.deleteSync(recursive: true));

  List<Map<String, Object?>> rows(String prefab) {
    final level = run.readJson('room.level.json')! as Map<String, Object?>;
    final prefabs = level['prefabs']! as Map<String, Object?>;
    return ((prefabs[prefab]! as Map<String, Object?>)['entities']!
            as List<Object?>)
        .cast<Map<String, Object?>>();
  }

  test('the text reader: sections, attributes, constructors, resources', () {
    final sections = parseGodotText(
      File('$_project/props/crate.tscn').readAsStringSync(),
    );
    expect(sections.first.kind, 'gd_scene');
    final external = sections.firstWhere((s) => s.kind == 'ext_resource');
    expect(external.text('path'), 'res://props/crate.obj');
    final body = sections.firstWhere((s) => s.text('name') == 'Body');
    final transform = body.properties['transform']! as GodotCall;
    expect(transform.name, 'Transform3D');
    expect(transform.numbers, hasLength(12));
    expect(
      (body.properties['surface_material_override/0']! as GodotCall).name,
      'SubResource',
    );
  });

  test('the scene converts', () {
    expect(run.code, 0, reason: run.text);
    expect(run.wrote('models/crate.f3d'), isTrue);
  });

  test('a BoxMesh is a prop of its size, wearing the .tres material', () {
    final floor = rows('room').firstWhere((r) => r['name'] == 'Floor');
    expect(floor['type'], 'prop');
    expect(floor['size'], <Object?>[8.0, 0.2, 8.0]);
    expect(floor['material'], 'painted');
  });

  test('an instanced scene is an instance row; an editable child\'s '
      'material is its override', () {
    final crate = rows('room').firstWhere((r) => r['name'] == 'Crate1');
    expect(crate['type'], 'prefab');
    expect(crate['prefab'], 'crate');
    expect(crate['at'], <Object?>[2.0, 0.0, -1.0]);
    expect(crate['overrides'], <String, Object?>{
      'Body': <String, Object?>{
        'materials': <Object?>['painted'],
      },
    });
  });

  test('a scaled instance is written out row by row', () {
    final body = rows('room').firstWhere((r) => r['type'] == 'model');
    expect(body['scale'], <Object?>[0.5, 0.5, 0.5]);
    expect(run.report('room.tscn')['warnings'], contains(contains('Crate2')));
  });

  test('a basis written row by row reads as a quarter turn', () {
    final body = rows('crate').single;
    expect(body['yaw'], closeTo(math.pi / 2, 1e-5));
    expect(body['at'], <Object?>[0.0, 0.5, 0.0]);
    expect(body['materials'], <Object?>['CrateWood']);
  });

  test('hidden nodes and lights are dropped with their reasons', () {
    final dropped = run.report('room.tscn')['dropped']! as List<Object?>;
    expect(dropped, contains(contains('hidden')));
    expect(dropped, contains(contains('lights')));
  });

  test('ORMMaterial3D: one image for occlusion, roughness and metal; '
      'scissor, two sides, emission', () {
    final painted = readFmat(
      File('${scratch.path}/materials/painted.fmat').readAsBytesSync(),
    );
    expect(painted.surface.alphaMode, SurfaceAlphaMode.mask);
    expect(painted.surface.alphaCutoff, closeTo(0.4, 1e-6));
    expect(painted.surface.doubleSided, isTrue);
    expect(painted.surface.emissiveStrength, 2.0);
    expect(
      painted.surface.metallicRoughnessTexture?.imageIndex,
      painted.surface.occlusionTexture?.imageIndex,
    );
    expect(run.report('room.tscn')['dropped'], contains(contains('rim')));
  });

  test('StandardMaterial3D: albedo and its tiling', () {
    final wood = readFmat(
      File('${scratch.path}/materials/CrateWood.fmat').readAsBytesSync(),
    );
    expect(wood.surface.roughness, closeTo(0.8, 1e-6));
    expect(wood.surface.baseColorTexture?.transform?.scale.x, 2.0);
  });

  test('a .tres alone is an .fmat', () async {
    final alone = await convert(<String>['$_project/props/painted.tres']);
    try {
      expect(alone.code, 0);
      expect(alone.wrote('materials/painted.fmat'), isTrue);
    } finally {
      alone.output.deleteSync(recursive: true);
    }
  });
}
