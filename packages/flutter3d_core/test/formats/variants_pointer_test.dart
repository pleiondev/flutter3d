/// Material variants and animation pointers survive glTF and `.f3d`.
///
///     dart test test/formats/variants_pointer_test.dart
///
/// `KHR_materials_variants` and `KHR_animation_pointer` used to be refused
/// outright when a file required them and read past when it merely used
/// them. They are decoded now — variants into `ModelDocument.variants` and
/// `ModelSurface.variantMaterials`, pointer channels into tracks on a
/// material or light property — and these hold both writers to giving back
/// what the loaders read.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_core/geometry.dart';
import 'package:test/test.dart';

MeshData _triangle() => MeshData(
  layout: VertexLayout.positionNormalTexcoord,
  vertices: Float32List.fromList(<double>[
    0, 0, 0, 0, 0, 1, 0, 0, //
    1, 0, 0, 0, 0, 1, 1, 0, //
    0, 1, 0, 0, 0, 1, 0, 1, //
  ]),
  indices: Uint32List.fromList(<int>[0, 1, 2]),
);

AnimationTrack _pointerTrack(String pointer, List<double> values, int n) =>
    AnimationTrack(
      nodeIndex: -1,
      path: AnimationPath.pointer,
      interpolation: AnimationInterpolation.linear,
      times: Float32List.fromList(<double>[0.0, 1.0]),
      values: Float32List.fromList(values),
      componentCount: n,
      pointer: AnimationPointer.parse(pointer),
    );

/// Two surfaces, three materials, two variants: the first surface changes
/// in both, the second only in "night"; one clip mixes a node track between
/// two pointer tracks, so the order they come back in is checked too.
PlainModelDocument _document() {
  final mesh = _triangle();
  return PlainModelDocument(
    surfaces: <ModelSurface>[
      ModelSurface(
        mesh: mesh,
        materialIndex: 0,
        variantMaterials: <int, int>{0: 1, 1: 2},
      ),
      ModelSurface(mesh: mesh, materialIndex: 0, variantMaterials: {1: 1}),
    ],
    materials: <SurfaceMaterial>[
      SurfaceMaterial(),
      SurfaceMaterial(),
      SurfaceMaterial(),
    ],
    nodes: <ModelNode>[
      ModelNode(surfaces: <int>[0, 1]),
    ],
    variants: const <String>['day', 'night'],
    animations: <AnimationClip>[
      AnimationClip(
        name: 'glow',
        tracks: <AnimationTrack>[
          _pointerTrack(
            '/materials/1/pbrMetallicRoughness/baseColorFactor',
            <double>[1, 0, 0, 1, 0, 0, 1, 1],
            4,
          ),
          AnimationTrack(
            nodeIndex: 0,
            path: AnimationPath.translation,
            interpolation: AnimationInterpolation.linear,
            times: Float32List.fromList(<double>[0.0, 1.0]),
            values: Float32List.fromList(<double>[0, 0, 0, 0, 1, 0]),
            componentCount: 3,
          ),
          _pointerTrack(
            '/materials/0/emissiveTexture/extensions/KHR_texture_transform/'
            'offset',
            <double>[0, 0, 0.5, 0.25],
            2,
          ),
        ],
      ),
    ],
  );
}

void _expectSame(ModelDocument source, ModelDocument readBack) {
  expect(readBack.variants, source.variants);
  expect(
    <Map<int, int>>[for (final s in readBack.surfaces) s.variantMaterials],
    <Map<int, int>>[for (final s in source.surfaces) s.variantMaterials],
  );

  final a = source.animations.single.tracks;
  final b = readBack.animations.single.tracks;
  expect(b.map((t) => t.path), a.map((t) => t.path), reason: 'track order');
  for (var i = 0; i < a.length; i++) {
    expect(b[i].pointer, a[i].pointer, reason: 'track $i pointer');
    expect(b[i].componentCount, a[i].componentCount, reason: 'track $i');
    expect(b[i].values.toList(), a[i].values.toList(), reason: 'track $i');
    expect(b[i].times.toList(), a[i].times.toList(), reason: 'track $i');
  }
}

const String _textureScale =
    '/materials/0/pbrMetallicRoughness/baseColorTexture/extensions/'
    'KHR_texture_transform/scale';

void main() {
  group('AnimationPointer.parse', () {
    test('resolves every property it names, and the index', () {
      final cases = <String, (AnimationPointerProperty, int)>{
        '/materials/3/pbrMetallicRoughness/baseColorFactor': (
          AnimationPointerProperty.baseColor,
          3,
        ),
        '/materials/0/pbrMetallicRoughness/roughnessFactor': (
          AnimationPointerProperty.roughness,
          0,
        ),
        '/materials/12/pbrMetallicRoughness/metallicFactor': (
          AnimationPointerProperty.metallic,
          12,
        ),
        '/materials/1/extensions/KHR_materials_emissive_strength/'
            'emissiveStrength': (
          AnimationPointerProperty.emissiveStrength,
          1,
        ),
        '/materials/2/normalTexture/extensions/KHR_texture_transform/offset': (
          AnimationPointerProperty.textureOffset,
          2,
        ),
        '/extensions/KHR_lights_punctual/lights/4/color': (
          AnimationPointerProperty.lightColor,
          4,
        ),
        '/extensions/KHR_lights_punctual/lights/0/intensity': (
          AnimationPointerProperty.lightIntensity,
          0,
        ),
      };
      for (final MapEntry(key: text, value: (property, index))
          in cases.entries) {
        final pointer = AnimationPointer.parse(text);
        expect(pointer?.property, property, reason: text);
        expect(pointer?.index, index, reason: text);
        expect(pointer?.pointer, text);
      }
    });

    test('refuses what it cannot move rather than guessing', () {
      for (final text in <String>[
        '/materials/0/emissiveFactor',
        '/materials/01/pbrMetallicRoughness/roughnessFactor',
        '/materials/-1/pbrMetallicRoughness/roughnessFactor',
        'materials/0/pbrMetallicRoughness/roughnessFactor',
        '/nodes/0/translation',
        '/materials/0/pbrMetallicRoughness/roughnessFactor/extra',
        '/extensions/KHR_lights_punctual/lights/0/range',
        _textureScale,
      ]) {
        expect(AnimationPointer.parse(text), isNull, reason: text);
      }
    });

    test('a hand-built pointer names the canonical path, and parses back', () {
      for (final property in AnimationPointerProperty.values) {
        final built = AnimationPointer.of(property, 5);
        expect(AnimationPointer.parse(built.pointer), built);
      }
    });
  });

  test('variants and pointer tracks round-trip through glTF', () async {
    final source = _document();
    final bytes = GltfWriter(source).writeGlb();
    final readBack = await GltfLoader().load(bytes);
    _expectSame(source, readBack);
    expect(readBack.warnings, isEmpty);

    final json = GlbContainer.parse(bytes).json;
    expect(
      json['extensionsUsed'],
      containsAll(<String>['KHR_materials_variants', 'KHR_animation_pointer']),
    );
    // Neither is required: a reader without them draws the default look and
    // plays the node tracks, which is a fair picture of the model.
    expect(json['extensionsRequired'], isNull);
  });

  test('variants and pointer tracks round-trip through .f3d', () {
    final source = _document();
    final readBack = F3dDocument.parse(F3dWriter(source).write());
    _expectSame(source, readBack);
  });

  test('a document with neither writes the .f3d it wrote before', () {
    final plain = PlainModelDocument(
      surfaces: <ModelSurface>[ModelSurface(mesh: _triangle())],
      nodes: <ModelNode>[
        ModelNode(surfaces: <int>[0]),
      ],
    );
    final bytes = F3dWriter(plain).write();
    final sectionCount = ByteData.sublistView(
      bytes,
    ).getUint32(8, Endian.little);
    final kinds = <int>[
      for (var i = 0; i < sectionCount; i++)
        ByteData.sublistView(
          bytes,
        ).getUint32(kF3dHeaderBytes + i * kF3dSectionEntryBytes, Endian.little),
    ];
    expect(kinds, isNot(contains(F3dSection.variants)));
    expect(kinds, isNot(contains(F3dSection.pointerTracks)));
  });

  test('a file requiring both loads, and says what it could not use', () async {
    final original = GlbContainer.parse(GltfWriter(_document()).writeGlb());
    final json = original.json;
    // The same file, now requiring both, with one channel aimed at a
    // property this engine does not animate and one mapping at a material
    // the file does not have.
    json['extensionsRequired'] = <String>[
      'KHR_materials_variants',
      'KHR_animation_pointer',
    ];
    final animation = (json['animations']! as List).single as Map;
    final channels = animation['channels']! as List;
    ((channels.first as Map)['target']!
        as Map)['extensions'] = <String, Object?>{
      'KHR_animation_pointer': <String, Object?>{
        'pointer': '/materials/0/emissiveFactor',
      },
    };
    final primitive =
        (((json['meshes']! as List).first as Map)['primitives']! as List).first
            as Map;
    (((primitive['extensions']! as Map)['KHR_materials_variants']!
                as Map)['mappings']!
            as List)
        .add(<String, Object?>{
          'material': 9,
          'variants': <int>[0],
        });

    final readBack = await GltfLoader().load(
      GlbContainer.encode(json, binary: original.binaryChunk),
    );

    expect(readBack.animations.single.tracks, hasLength(2));
    expect(readBack.surfaces.first.variantMaterials, <int, int>{0: 1, 1: 2});
    expect(
      readBack.warnings.join('\n'),
      allOf(contains('/materials/0/emissiveFactor'), contains('material 9')),
    );
  });

  test('a hand-written glTF names its variants and maps them', () async {
    final json = <String, Object?>{
      'asset': <String, Object?>{'version': '2.0'},
      'extensionsUsed': <String>['KHR_materials_variants'],
      'extensions': <String, Object?>{
        'KHR_materials_variants': <String, Object?>{
          'variants': <Object?>[
            <String, Object?>{'name': 'red'},
            <String, Object?>{},
          ],
        },
      },
      'materials': <Object?>[<String, Object?>{}, <String, Object?>{}],
    };
    final readBack = await GltfLoader().load(
      Uint8List.fromList(utf8.encode(jsonEncode(json))),
    );
    expect(readBack.variants, <String>['red', 'variant 1']);
  });

  test('a pointer track must carry its pointer', () {
    expect(
      () => AnimationTrack(
        nodeIndex: -1,
        path: AnimationPath.pointer,
        interpolation: AnimationInterpolation.step,
        times: Float32List.fromList(<double>[0]),
        values: Float32List.fromList(<double>[0]),
        componentCount: 1,
      ),
      throwsArgumentError,
    );
  });
}
