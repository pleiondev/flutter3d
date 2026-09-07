/// A level surface that defers its whole look to a `.fmat`.
///
///     flutter test test/level_fmat_material_test.dart
///
/// **Two dictionaries, and until now only one of them reached a wall.** A
/// `LevelMaterial` is the eight fields a level author blocks a room out in;
/// the engine's `MaterialDocument` is fourteen scalars, five texture slots
/// with samplers of their own, alpha, a shader an application compiled itself
/// and the parameters that shader reads. The bridge between them ran one way
/// and only inside `materialFrom`, which meant `.fmat` was a complete format
/// with no consumer: nothing in a playable level could ask for a shader.
///
/// This is the fork. It has to do two things and the second matters as much as
/// the first: a level that names a material file gets what the file says, and
/// a level that names none is drawn exactly as it always was — which is every
/// level in this repository.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';

/// A material with a shader of its own, the parameters it reads and a hint
/// saying how one of them should be shown.
const String _water = '''
{
  "fmat": 1,
  "name": "canal water",
  "lighting": {"shader": "Water", "materialMaps": false,
               "metallicRoughnessMap": false},
  "baseColor": [0.1, 0.3, 0.35, 1.0],
  "roughness": 0.05,
  "parameterBlock": "WaterParams",
  "parameters": {"speed": 2.5, "tint": [0.1, 0.4, 0.5]},
  "hints": {
    "speed": {"kind": "range", "min": 0, "max": 4, "step": 0.1,
              "label": "Current"}
  },
  "textures": {"albedo": "water.png"}
}
''';

/// The document a level with one wall in one material parses from. [fmat]
/// names the material file that wall defers to, when it defers to one.
Map<String, Object?> _levelJson({String? fmat}) => <String, Object?>{
  'version': 1,
  'materials': <String, Object?>{
    'wall': <String, Object?>{
      'fmat': ?fmat,
      'color': <double>[0.8, 0.8, 0.8],
      'roughness': 0.9,
    },
  },
  'brushes': <Object?>[
    <String, Object?>{
      'material': 'wall',
      'at': <double>[0.0, 1.5, -1.5],
      'size': <double>[4.0, 3.0, 1.0],
    },
  ],
  'lights': <Object?>[
    <String, Object?>{
      'type': 'point',
      'at': <double>[0.0, 2.0, 0.0],
      'color': <double>[1.0, 1.0, 1.0],
      'range': 8.0,
    },
  ],
};

void main() {
  final device = CpuDevice(
    width: 16,
    height: 16,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final registry = EntityRegistry(<EntityKind>[]);

  /// Answers `materials/water.fmat` with [_water] and its sibling image with a
  /// pixel, and refuses everything else — so a loader reaching for a path the
  /// material did not name is a failure rather than a silent success.
  Future<ByteData> readAsset(AssetRequest request) async =>
      switch (request.uri) {
        'materials/water.fmat' => ByteData.sublistView(
          Uint8List.fromList(utf8.encode(_water)),
        ),
        'materials/water.png' => _onePixelPng(),
        final String other => throw StateError('no such asset: $other'),
      };

  test('brings the file\'s shader, parameters and maps onto the wall', () async {
    // Mutation: drop the `deferred[surface.material] ??` fork in
    // `LevelLoader.build` and every expectation below reports the level's own
    // numbers instead — a wall with the scene's shader, no parameters and the
    // roughness of 0.9 the document happens to carry.
    final loaded = await const LevelLoader().build(
      Level.fromJson(_levelJson(fmat: 'materials/water.fmat')),
      device: device,
      registry: registry,
      readAsset: readAsset,
    );

    expect(loaded.issues, isEmpty);
    final material = loaded.brushNodes.single.material;
    // The thing a level material has no word for at all, and the reason the
    // fork exists: a surface drawn with a shader the application compiled.
    expect(material.lighting.shaderName, 'Water');
    expect(material.parameterBlock, 'WaterParams');
    expect(material.parameters['speed'], <double>[2.5]);
    expect(material.parameters['tint'], hasLength(3));
    expect(material.name, 'canal water');
    expect(
      material.roughness,
      closeTo(0.05, 1e-6),
      reason: 'the file is the whole answer, not a set of overrides',
    );
    // Resolved relative to the material file rather than to the level, the way
    // a `.gltf`'s buffers already are — the fake reader above throws on any
    // other spelling, so a wrong join is a thrown level rather than a flat wall.
    expect(material.albedo, isNotNull);
  });

  test('and its hints travel with it, describing without constraining', () async {
    // A hint is a description for an inspector, so it stops at the document —
    // a `Material` is what the renderer draws and has no use for a slider's
    // ends. What this measures is that the path a level names is the path the
    // hints arrive by: the same bytes, read through the loader's own reader.
    //
    // Mutation: drop `hints` from `readFmat` and the second expectation fails
    // while the wall keeps drawing, which is precisely the property a hint has.
    final bytes = await readAsset(const AssetRequest('materials/water.fmat'));
    final document = readFmat(bytes.buffer.asUint8List());

    expect(document.parameters['speed'], <double>[2.5]);
    expect((document.hints['speed']!.kind as RangeHint).max, 4.0);
    expect(document.hints['speed']!.label, 'Current');
  });

  test('while a level that names none is built exactly as before', () async {
    // **The regression guard, and the reason it is worth a test of its own.**
    // Every level in this repository takes this branch, and a fork that
    // quietly changed it would change every wall in the crypt at once.
    //
    // Mutation: make the fork read a `.fmat` for a material that names none —
    // the loader throws or warns, and both expectations fail.
    final loaded = await const LevelLoader().build(
      Level.fromJson(_levelJson()),
      device: device,
      registry: registry,
      readAsset: readAsset,
    );

    expect(loaded.issues, isEmpty);
    final material = loaded.brushNodes.single.material;
    expect(material.roughness, closeTo(0.9, 1e-6));
    expect(material.parameters, isEmpty);
    expect(material.albedo, isNull);
  });

  test(
    'and a material file that will not read costs a look, not a level',
    () async {
      // The same bargain a missing texture strikes: the room stays walkable, the
      // wall falls back to the numbers the level itself carries, and the person
      // who renamed the file hears about it. Mutation: let the exception out of
      // `_fmatMaterial` and the level stops loading over a decoration.
      final loaded = await const LevelLoader().build(
        Level.fromJson(_levelJson(fmat: 'materials/gone.fmat')),
        device: device,
        registry: registry,
        readAsset: readAsset,
      );

      expect(loaded.issues, hasLength(1));
      expect(loaded.issues.single.isError, isFalse);
      expect(loaded.issues.single.where, contains('gone.fmat'));
      expect(
        loaded.brushNodes.single.material.roughness,
        closeTo(0.9, 1e-6),
        reason: 'the level\'s own numbers are what it falls back to',
      );
    },
  );
}

/// One opaque white pixel, as a PNG. Written out rather than read from a file,
/// for the reason `level_loader_test.dart` gives where it does the same.
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
