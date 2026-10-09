import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_build/convert.dart';
import 'package:flutter3d_core/formats.dart' show F3dDocument;
import 'package:test/test.dart';

import 'convert_support.dart';

/// Every file under [root], by its path inside it: a bundle as an upload
/// arrives.
Map<String, Uint8List> _bundle(String root) => <String, Uint8List>{
  for (final entity in Directory(root).listSync(recursive: true))
    if (entity is File)
      entity.path.substring(root.length + 1): entity.readAsBytesSync(),
};

void main() {
  test('by default a Unity scene is one .f3d carrying everything', () async {
    final result = await convertFiles(
      _bundle('$fixtures/unity'),
      to: ConversionTarget.everything,
      entry: 'Assets/Scenes/Room.unity',
      assetPrefix: 'assets/imported',
    );
    expect(
      result.isOk,
      isTrue,
      reason: '${result.reports.map((r) => r.describe())}',
    );
    // Mutation: skip the bundling step and the sidecars come back.
    expect(result.files.keys, <String>['Room.f3d']);
    final bundle = F3dDocument.parse(result.files['Room.f3d']!);
    expect(bundle.prefabs.keys, contains('Room'));
    expect(
      bundle.files.keys,
      containsAll(<String>['materials/Wood.fmat', 'models/crate.f3d']),
    );
    expect(result.reports.single.written, <String>['Room.f3d']);
  });

  test('a Unity bundle in, the scene\'s files out, as bytes', () async {
    final result = await convertFiles(
      _bundle('$fixtures/unity'),
      to: ConversionTarget.everything,
      entry: 'Assets/Scenes/Room.unity',
      assetPrefix: 'assets/imported',
      bundle: false,
    );
    expect(
      result.isOk,
      isTrue,
      reason: '${result.reports.map((r) => r.describe())}',
    );
    expect(
      result.files.keys,
      containsAll(<String>[
        'Room.level.json',
        'materials/Wood.fmat',
        'models/crate.f3d',
      ]),
    );
    expect(result.reports.single.input, 'Assets/Scenes/Room.unity');
    expect(
      String.fromCharCodes(result.files['Room.level.json']!),
      contains('assets/imported/models/crate.f3d'),
    );
  });

  test('a target keeps only its kind of file', () async {
    final result = await convertFiles(
      _bundle('$fixtures/godot'),
      to: ConversionTarget.materials,
      entry: 'room.tscn',
      bundle: false,
    );
    expect(
      result.files.keys,
      everyElement(anyOf(endsWith('.fmat'), startsWith('textures/'))),
    );
    expect(result.files, isNotEmpty);
  });

  test('no entry converts every file a directory walk would', () async {
    final result = await convertFiles(<String, Uint8List>{
      'a/wedge.stl': File('$fixtures/wedge.stl').readAsBytesSync(),
      'readme.txt': Uint8List.fromList('hi'.codeUnits),
    }, to: ConversionTarget.models);
    expect(result.files.keys, <String>['wedge.f3d']);
    expect(result.reports.single.input, 'a/wedge.stl');
  });

  test('FBX runs no program here: unsupported, exit code 3', () async {
    final result = await convertFiles(<String, Uint8List>{
      'chair.fbx': Uint8List.fromList('Kaydara FBX Binary'.codeUnits),
    }, to: ConversionTarget.everything);
    expect(result.exitCode, 3);
    expect(result.reports.single.outcome, ConvertOutcome.missingTool);
    expect(result.files, isEmpty);
  });

  test('a path that climbs out of the bundle is refused', () {
    expect(
      () => convertFiles(<String, Uint8List>{
        '../escape.stl': Uint8List(0),
      }, to: ConversionTarget.everything),
      throwsArgumentError,
    );
  });
}
