/// A level's values for a material's parameters, written for an older
/// version of that material, lifted on load through its `updates`
/// (`MaterialProgram.lift`).
///
///     flutter test test/level_material_lift_test.dart
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';

/// A material file drawn with the rim material's own shader.
const String _rim = '''
{
  "fmat": 1,
  "name": "rim",
  "lighting": {"shader": "RimGlow", "materialMaps": false,
               "metallicRoughnessMap": false},
  "parameterBlock": "RimGlowParams",
  "parameters": {"rimColor": [0.2, 0.5, 1.0], "rimPower": 3.0}
}
''';

/// One wall deferring to [_rim], giving its parameters [values] written for
/// [version] of the material.
Level _level(Map<String, Object?> values, {int? version}) =>
    Level.fromJson(<String, Object?>{
      'version': 5,
      'materials': <String, Object?>{
        'wall': <String, Object?>{
          'fmat': 'materials/rim.fmat',
          'parameters': values,
          'materialVersion': ?version,
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
    });

void main() {
  final device = CpuDevice(
    width: 16,
    height: 16,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final registry = EntityRegistry(<EntityKind>[]);
  // The rim material at its version 3: `rim` became `rimColor` at 2, which
  // was halved and lost `pulse` at 3.
  final program = parseMaterial(
    File(
      '../flutter3d_core/test/fixtures/v3/rim_glow.f3dmat',
    ).readAsStringSync(),
  );

  Future<ByteData> readAsset(AssetRequest request) async =>
      switch (request.uri) {
        'materials/rim.fmat' => ByteData.sublistView(
          Uint8List.fromList(utf8.encode(_rim)),
        ),
        final String other => throw StateError('no such asset: $other'),
      };

  Future<LoadedLevel> load(Level level, {bool withProgram = true}) =>
      const LevelLoader().build(
        level,
        device: device,
        registry: registry,
        readAsset: readAsset,
        programs: withProgram
            ? <String, MaterialProgram>{'RimGlow': program}
            : const <String, MaterialProgram>{},
      );

  test('values written for version 1 reach the wall as version 3 reads '
      'them', () async {
    // Mutation: hand the values on without `program.lift`. The wall then
    // has a `rim` its shader never reads and a `pulse` it no longer has,
    // and its `rimColor` is the file's rather than the level's.
    expect(program.version, 3);
    final loaded = await load(
      _level(<String, Object?>{
        'rim': <double>[0.4, 0.8, 1.0],
        'pulse': 1.0,
        'rimPower': 2.0,
      }),
    );
    expect(loaded.issues, isEmpty);
    final parameters = loaded.brushNodes.single.material.parameters;
    expect(
      parameters['rimColor'],
      Float32List.fromList(<double>[0.2, 0.4, 0.5]),
    );
    expect(parameters['rimPower'], <double>[2.0]);
    expect(parameters.names.contains('rim'), isFalse);
    expect(parameters.names.contains('pulse'), isFalse);
  });

  test('values for a newer material keep the material\'s own, with a '
      'word', () async {
    // Mutation: let `MaterialVersionException` through. A level saved
    // against a newer build then does not load at all.
    final loaded = await load(
      _level(<String, Object?>{
        'rimColor': <double>[1.0, 0.0, 0.0],
      }, version: 4),
    );
    expect(loaded.issues, hasLength(1));
    expect(loaded.issues.single.where, 'material "wall"');
    expect(
      loaded.brushNodes.single.material.parameters['rimColor']![1],
      closeTo(0.5, 1e-6),
    );
  });

  test('a value for a parameter the material no longer has is left out, '
      'with a word', () async {
    final loaded = await load(
      _level(<String, Object?>{'glare': 1.0, 'rimPower': 5.0}, version: 3),
    );
    expect(loaded.issues.single.message, contains('"glare"'));
    final parameters = loaded.brushNodes.single.material.parameters;
    expect(parameters.names.contains('glare'), isFalse);
    expect(parameters['rimPower'], <double>[5.0]);
  });

  test('with no program known the values arrive as written', () async {
    final loaded = await load(
      _level(<String, Object?>{
        'rim': <double>[0.4, 0.8, 1.0],
      }),
      withProgram: false,
    );
    expect(loaded.issues, isEmpty);
    expect(
      loaded.brushNodes.single.material.parameters['rim'],
      Float32List.fromList(<double>[0.4, 0.8, 1.0]),
    );
  });
}
