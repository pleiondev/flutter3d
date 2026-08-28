/// Building a level into a scene, and saying what would not build.
///
///     flutter test test/level_loader_test.dart
///
/// **The first test this package ever had.** A thousand lines binding the two
/// halves of the engine, and the only file under `test/` was the rule that it
/// names no genre. What made it testable was already here: `build` takes a
/// `Level` rather than an asset path, and `readAsset` is an argument — both
/// added for the editor, both exactly what a test wants.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';

/// The document a level with one wall, in one material, parses from.
Map<String, Object?> _levelJson({String? albedo}) => <String, Object?>{
  'version': 1,
  'materials': <String, Object?>{
    'wall': <String, Object?>{
      'albedo': ?albedo,
      'color': <double>[0.8, 0.8, 0.8],
    },
  },
  'brushes': <Object?>[
    <String, Object?>{
      'material': 'wall',
      'at': <double>[0.0, 1.5, -1.5],
      'size': <double>[4.0, 3.0, 1.0],
    },
  ],
  // A level with no lights is a level the validator warns about, and this
  // file is about the other warnings.
  'lights': <Object?>[
    <String, Object?>{
      'type': 'point',
      'at': <double>[0.0, 2.0, 0.0],
      'color': <double>[1.0, 1.0, 1.0],
      'range': 8.0,
    },
  ],
};

/// A level with one wall, in one material.
Level _level({String? albedo}) => Level.fromJson(_levelJson(albedo: albedo));

void main() {
  final device = CpuDevice(
    width: 16,
    height: 16,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final registry = EntityRegistry(<EntityKind>[]);

  test('a level with no textures builds with nothing to report', () async {
    final loaded = await const LevelLoader().build(
      _level(),
      device: device,
      registry: registry,
    );

    expect(loaded.issues, isEmpty);
    expect(
      loaded.drawCallCount,
      greaterThan(0),
      reason: 'the one brush did not become geometry',
    );
  });

  test(
    'and a texture that will not load is a warning, not a console line',
    () async {
      // **It printed and returned null.** The level plays and the wall is flat,
      // which is right — but a flat wall and a wall meant to be flat look the
      // same, and the difference is a file somebody renamed. `LoadedLevel` has
      // carried `issues` since the validator did; this is the same kind of fact.
      final loaded = await const LevelLoader().build(
        _level(albedo: 'assets/textures/gone.png'),
        device: device,
        registry: registry,
        readAsset: (String path) async => throw StateError('no such asset'),
      );

      expect(loaded.issues, hasLength(1));
      expect(
        loaded.issues.single.isError,
        isFalse,
        reason: 'a missing texture stopped the level',
      );
      expect(loaded.issues.single.where, contains('gone.png'));
    },
  );

  test('and a texture that loads is not reported', () async {
    final loaded = await const LevelLoader().build(
      _level(albedo: 'assets/textures/wall.png'),
      device: device,
      registry: registry,
      readAsset: (String path) async => _onePixelPng(),
    );

    expect(
      loaded.issues,
      isEmpty,
      reason: 'a texture that loaded was reported as missing',
    );
    expect(loaded.materialTextures['assets/textures/wall.png'], isNotNull);
  });

  test(
    'load reads its document through readDocument, not just its textures',
    () async {
      // The editor's whole reason to want this: a level on disk, read the same
      // way `readAsset` already lets its textures be. Nothing here touches the
      // asset bundle, so a real one is never needed to prove it.
      final read = <String>[];
      final loaded = await const LevelLoader().load(
        'levels/wall.level.json',
        device: device,
        registry: registry,
        readDocument: (String path) async {
          read.add(path);
          return jsonEncode(_levelJson());
        },
      );

      expect(read, <String>['levels/wall.level.json']);
      expect(loaded.issues, isEmpty);
      expect(loaded.drawCallCount, greaterThan(0));
    },
  );
}

/// One opaque white pixel, as a PNG.
///
/// Written out rather than read from a file, because a package's test that
/// reaches into an application's assets is the dependency this package's other
/// test file exists to forbid.
ByteData _onePixelPng() => ByteData.sublistView(
  Uint8List.fromList(<int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0B, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0xF8, 0x0F, 0x04, 0x00,
    0x09, 0xFB, 0x03, 0xFD, 0xFB, 0x5E, 0x6B, 0x2B,
    0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44,
    0xAE, 0x42, 0x60, 0x82,
  ]),
);
