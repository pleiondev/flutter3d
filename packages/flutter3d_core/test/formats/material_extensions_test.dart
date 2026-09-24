/// A material's layers beyond metal-rough — `M1`: read from glTF, and kept
/// through every format the engine writes a material to.
///
///     dart test test/formats/material_extensions_test.dart
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A one-triangle glTF whose single material carries [extensions], with one
/// texture on image 0 for them to name.
Uint8List _gltf(
  Map<String, Object?> extensions, {
  List<String> required = const <String>[],
}) {
  final positions = Float32List.fromList(<double>[0, 0, 0, 1, 0, 0, 0, 1, 0]);
  final buffer = base64Encode(positions.buffer.asUint8List());
  return Uint8List.fromList(
    utf8.encode(
      jsonEncode(<String, Object?>{
        'asset': <String, Object?>{'version': '2.0'},
        if (required.isNotEmpty) 'extensionsUsed': required,
        if (required.isNotEmpty) 'extensionsRequired': required,
        'scene': 0,
        'scenes': <Object?>[
          <String, Object?>{
            'nodes': <Object?>[0],
          },
        ],
        'nodes': <Object?>[
          <String, Object?>{'mesh': 0},
        ],
        'meshes': <Object?>[
          <String, Object?>{
            'primitives': <Object?>[
              <String, Object?>{
                'attributes': <String, Object?>{'POSITION': 0},
                'material': 0,
              },
            ],
          },
        ],
        'materials': <Object?>[
          <String, Object?>{'extensions': extensions},
        ],
        'textures': <Object?>[
          <String, Object?>{'source': 0},
        ],
        'images': <Object?>[
          <String, Object?>{'uri': 'data:image/png;base64,iVBORw0KGgo='},
        ],
        'accessors': <Object?>[
          <String, Object?>{
            'bufferView': 0,
            'componentType': 5126,
            'count': 3,
            'type': 'VEC3',
            'min': <Object?>[0, 0, 0],
            'max': <Object?>[1, 1, 0],
          },
        ],
        'bufferViews': <Object?>[
          <String, Object?>{
            'buffer': 0,
            'byteOffset': 0,
            'byteLength': positions.lengthInBytes,
          },
        ],
        'buffers': <Object?>[
          <String, Object?>{
            'byteLength': positions.lengthInBytes,
            'uri': 'data:application/octet-stream;base64,$buffer',
          },
        ],
      }),
    ),
  );
}

const Map<String, Object?> _carPaint = <String, Object?>{
  'KHR_materials_ior': <String, Object?>{'ior': 1.8},
  'KHR_materials_specular': <String, Object?>{
    'specularFactor': 0.5,
    'specularColorFactor': <Object?>[1.0, 0.5, 0.25],
  },
  'KHR_materials_clearcoat': <String, Object?>{
    'clearcoatFactor': 1.0,
    'clearcoatTexture': <String, Object?>{'index': 0},
    'clearcoatRoughnessFactor': 0.125,
    'clearcoatRoughnessTexture': <String, Object?>{'index': 0},
  },
};

/// Every field [_carPaint] sets, as read back.
void _expectCarPaint(MaterialExtensions? layers) {
  expect(layers, isNotNull);
  expect(layers!.ior, closeTo(1.8, 1e-6));
  expect(layers.specular, closeTo(0.5, 1e-6));
  expect(layers.specularColor.y, closeTo(0.5, 1e-6));
  expect(layers.specularColor.z, closeTo(0.25, 1e-6));
  expect(layers.clearcoat, 1.0);
  expect(layers.clearcoatRoughness, closeTo(0.125, 1e-6));
  expect(layers.clearcoatTexture?.imageIndex, 0);
  expect(layers.clearcoatRoughnessTexture?.imageIndex, 0);
  expect(layers.shades, isTrue);
}

void main() {
  group('glTF', () {
    test('reads ior, specular and clearcoat', () async {
      final asset = await GltfLoader().load(_gltf(_carPaint));
      // Mutation: drop `extensions:` from `_decodeMaterials`. Null.
      _expectCarPaint(asset.materials.single.extensions);
    });

    test('a file that requires them loads', () async {
      // Mutation: take 'KHR_materials_clearcoat' out of
      // `_checkRequiredExtensions`' supported set. The load throws.
      final asset = await GltfLoader().load(
        _gltf(
          _carPaint,
          required: <String>[
            'KHR_materials_ior',
            'KHR_materials_specular',
            'KHR_materials_clearcoat',
          ],
        ),
      );
      expect(asset.materials.single.extensions?.clearcoat, 1.0);
    });

    test('a material without any has none, and writes none', () async {
      final asset = await GltfLoader().load(_gltf(const <String, Object?>{}));
      expect(asset.materials.single.extensions, isNull);
      final json = GlbContainer.parse(GltfWriter(asset).writeGlb()).json;
      final material =
          (json['materials']! as List<Object?>).single! as Map<String, Object?>;
      expect(material.containsKey('extensions'), isFalse);
    });

    test('the writer gives back what the file said', () async {
      final asset = await GltfLoader().load(_gltf(_carPaint));
      final written = GltfWriter(asset).writeGlb();
      final json = GlbContainer.parse(written).json;
      // Mutation: drop the `extensionsUsed.addAll` in the writer. A reader
      // that checks the list sees extensions the file never declared.
      expect(
        json['extensionsUsed'],
        containsAll(<String>['KHR_materials_ior', 'KHR_materials_clearcoat']),
      );
      final reread = await GltfLoader().load(written);
      _expectCarPaint(reread.materials.single.extensions);
    });

    test('the textures not drawn are named in the warnings', () async {
      final asset = await GltfLoader().load(
        _gltf(<String, Object?>{
          'KHR_materials_clearcoat': <String, Object?>{
            'clearcoatFactor': 1.0,
            'clearcoatNormalTexture': <String, Object?>{'index': 0},
          },
        }),
      );
      expect(asset.warnings.join(), contains('clear coat\'s normal map'));
      expect(
        asset.materials.single.extensions?.clearcoatNormalTexture?.imageIndex,
        0,
      );
    });
  });

  test('.f3d keeps them in section 22, and a material without has none', () {
    final layers = MaterialExtensions(
      ior: 1.8,
      specular: 0.5,
      specularColor: Vector3(1.0, 0.5, 0.25),
      clearcoat: 1.0,
      clearcoatTexture: TextureBinding(
        imageIndex: 0,
        sampling: const TextureSampling(wrapS: TextureWrap.clampToEdge),
      ),
      clearcoatRoughness: 0.125,
      clearcoatRoughnessTexture: const TextureBinding(imageIndex: 0),
    );
    final document = PlainModelDocument(
      surfaces: <ModelSurface>[
        ModelSurface(
          mesh: MeshData(
            layout: VertexLayout.positionOnly,
            vertices: Float32List(3 * 3),
            indices: Uint32List.fromList(<int>[0, 1, 2]),
          ),
          transform: Matrix4.identity(),
          materialIndex: 0,
        ),
      ],
      materials: <SurfaceMaterial>[
        SurfaceMaterial(extensions: layers),
        SurfaceMaterial(),
      ],
      images: <EncodedImage>[
        EncodedImage(bytes: Uint8List.fromList(<int>[1, 2, 3])),
      ],
    );
    final reread = F3dDocument.parse(F3dWriter(document).write());
    // Mutation: leave `_writeMaterialExtensions` out of the directory. Null.
    _expectCarPaint(reread.materials.first.extensions);
    expect(
      reread.materials.first.extensions!.clearcoatTexture!.sampling.wrapS,
      TextureWrap.clampToEdge,
    );
    expect(reread.materials.last.extensions, isNull);
  });

  test('.fmat keeps them, with its own texture slots', () {
    final document = MaterialDocument(
      surface: SurfaceMaterial(
        extensions: MaterialExtensions(
          ior: 1.8,
          specular: 0.5,
          specularColor: Vector3(1.0, 0.5, 0.25),
          clearcoat: 1.0,
          clearcoatTexture: const TextureBinding(imageIndex: 0),
          clearcoatRoughness: 0.125,
          clearcoatRoughnessTexture: const TextureBinding(imageIndex: 0),
        ),
      ),
      images: const <String>['coat.png'],
    );
    final text = writeFmat(document);
    expect(text, contains('"clearcoatTexture": "coat.png"'));
    final reread = readFmat(Uint8List.fromList(utf8.encode(text)));
    // Mutation: drop 'extensions' from `readFmat`'s known keys. The reread
    // warns about a key it wrote itself.
    expect(reread.warnings, isEmpty);
    _expectCarPaint(reread.surface.extensions);
    expect(reread.images, <String>['coat.png']);
  });

  group('the layered model', () {
    test('is what a metal-rough surface with layers is drawn by', () {
      final coated = MaterialExtensions(clearcoat: 1.0);
      expect(
        LightingModel.pbr.withLayers(coated),
        same(LightingModel.pbrLayered),
      );
      // Layers at their defaults change nothing, and ask for nothing.
      expect(
        LightingModel.pbr.withLayers(MaterialExtensions()),
        same(LightingModel.pbr),
      );
      // A coat map under a factor of nought is still no coat.
      expect(
        LightingModel.pbr.withLayers(
          MaterialExtensions(
            clearcoatTexture: const TextureBinding(imageIndex: 0),
          ),
        ),
        same(LightingModel.pbr),
      );
      // A surface that chose another model keeps it.
      expect(LightingModel.toon.withLayers(coated), same(LightingModel.toon));
    });
  });

  group('packLanes', () {
    Rgba8Image solid(int width, int height, List<int> rgba) => Rgba8Image(
      width: width,
      height: height,
      pixels: Uint8List.fromList(<int>[
        for (var i = 0; i < width * height; i++) ...rgba,
      ]),
    );

    test('copies one channel of each source into its lane', () {
      final packed = packLanes(<PackedLane>[
        (image: solid(2, 2, <int>[10, 20, 30, 40]), channel: 0),
        (image: solid(4, 1, <int>[50, 60, 70, 80]), channel: 1),
        null,
        null,
      ])!;
      // The largest of the sources, in each direction.
      expect(packed.width, 4);
      expect(packed.height, 2);
      // Mutation: write every lane from channel 0. Green reads 50.
      expect(packed.pixels.sublist(0, 4), <int>[10, 60, 255, 255]);
      expect(packed.pixels.sublist(28, 32), <int>[10, 60, 255, 255]);
    });

    test('nothing to pack is no map', () {
      expect(packLanes(const <PackedLane>[null, null]), isNull);
    });
  });
}
