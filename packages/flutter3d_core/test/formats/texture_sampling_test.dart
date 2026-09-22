/// glTF packs minification filtering into one enum with six values; two of
/// those pairs agree on everything except whether the mip level itself is
/// interpolated. This is the seam that distinguishes them.
///
///     dart test test/texture_sampling_test.dart
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_core/geometry.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A one-triangle glTF whose single texture uses sampler 0, so a test can
/// vary just `magFilter`/`minFilter`/`wrapS`/`wrapT` and decode.
Uint8List _gltfWithSampler(Map<String, Object?> sampler) {
  final positions = Float32List.fromList(<double>[0, 0, 0, 1, 0, 0, 0, 1, 0]);
  final buffer = base64Encode(positions.buffer.asUint8List());
  final document = <String, Object?>{
    'asset': <String, Object?>{'version': '2.0'},
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
      <String, Object?>{
        'pbrMetallicRoughness': <String, Object?>{
          'baseColorTexture': <String, Object?>{'index': 0},
        },
      },
    ],
    'textures': <Object?>[
      <String, Object?>{'source': 0, 'sampler': 0},
    ],
    'samplers': <Object?>[sampler],
    'images': <Object?>[
      <String, Object?>{'uri': 'brick.png'},
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
  };
  return Uint8List.fromList(utf8.encode(jsonEncode(document)));
}

Future<TextureSampling> _decode(int? minFilter) async {
  final asset = await GltfLoader().load(
    _gltfWithSampler(<String, Object?>{
      'magFilter': 9729,
      'minFilter': ?minFilter,
    }),
  );
  return asset.materials.single.baseColorTexture!.sampling;
}

void main() {
  group('the four mipmap filters decode to four different samplings', () {
    test('9984 NEAREST_MIPMAP_NEAREST: nearest texel, nearest mip', () async {
      final sampling = await _decode(9984);
      expect(sampling.minLinear, isFalse);
      expect(sampling.mipLinear, isFalse);
      expect(sampling.useMipmaps, isTrue);
    });

    test('9985 LINEAR_MIPMAP_NEAREST: linear texel, nearest mip', () async {
      final sampling = await _decode(9985);
      expect(sampling.minLinear, isTrue);
      // Mutation: drop the `minFilter != 9985` half of `mipLinear`'s
      // condition. 9985 and 9987 both have minLinear true, and only this
      // check tells them apart.
      expect(sampling.mipLinear, isFalse);
      expect(sampling.useMipmaps, isTrue);
    });

    test('9986 NEAREST_MIPMAP_LINEAR: nearest texel, linear mip', () async {
      final sampling = await _decode(9986);
      expect(sampling.minLinear, isFalse);
      expect(sampling.mipLinear, isTrue);
      expect(sampling.useMipmaps, isTrue);
    });

    test('9987 LINEAR_MIPMAP_LINEAR: linear texel, linear mip', () async {
      final sampling = await _decode(9987);
      expect(sampling.minLinear, isTrue);
      expect(sampling.mipLinear, isTrue);
      expect(sampling.useMipmaps, isTrue);
    });

    test('9728 NEAREST: no mipmaps at all', () async {
      final sampling = await _decode(9728);
      expect(sampling.minLinear, isFalse);
      expect(sampling.useMipmaps, isFalse);
    });

    test('9729 LINEAR: no mipmaps at all', () async {
      final sampling = await _decode(9729);
      expect(sampling.minLinear, isTrue);
      expect(sampling.useMipmaps, isFalse);
    });

    test('an absent minFilter keeps the mipmapped-trilinear default', () async {
      final sampling = await _decode(null);
      expect(sampling.minLinear, isTrue);
      expect(sampling.mipLinear, isTrue);
      expect(sampling.useMipmaps, isTrue);
    });
  });

  group('toGltfFilters is the exact inverse of decoding', () {
    const cases = <int, TextureSampling>{
      9728: TextureSampling(minLinear: false, useMipmaps: false),
      9729: TextureSampling(minLinear: true, useMipmaps: false),
      9984: TextureSampling(
        minLinear: false,
        useMipmaps: true,
        mipLinear: false,
      ),
      9985: TextureSampling(
        minLinear: true,
        useMipmaps: true,
        mipLinear: false,
      ),
      9986: TextureSampling(
        minLinear: false,
        useMipmaps: true,
        mipLinear: true,
      ),
      9987: TextureSampling(minLinear: true, useMipmaps: true, mipLinear: true),
    };

    for (final entry in cases.entries) {
      test('minFilter ${entry.key} round-trips through toGltfFilters', () {
        final (magFilter, minFilter) = toGltfFilters(entry.value);
        expect(magFilter, 9729);
        expect(minFilter, entry.key);
      });
    }

    test('decoding 9985 and re-encoding it names 9985, not 9987', () async {
      final sampling = await _decode(9985);
      final (_, minFilter) = toGltfFilters(sampling);
      expect(minFilter, 9985);
    });
  });

  group('.f3d round-trips mipLinear', () {
    ModelSurface surface() => ModelSurface(
      mesh: MeshData(
        layout: VertexLayout.positionOnly,
        vertices: Float32List(3 * 3),
        indices: Uint32List.fromList(<int>[0, 1, 2]),
      ),
      transform: Matrix4.identity(),
      materialIndex: 0,
    );

    F3dDocument roundTrip(TextureSampling sampling) {
      final document = PlainModelDocument(
        surfaces: <ModelSurface>[surface()],
        materials: <SurfaceMaterial>[
          SurfaceMaterial(
            baseColorTexture: TextureBinding(imageIndex: 0, sampling: sampling),
          ),
        ],
        images: <EncodedImage>[
          EncodedImage(bytes: Uint8List.fromList(<int>[1, 2, 3])),
        ],
      );
      final bytes = F3dWriter(document).write();
      return F3dDocument.parse(bytes);
    }

    test('mipLinear: false survives the round trip', () {
      final reread = roundTrip(
        const TextureSampling(useMipmaps: true, mipLinear: false),
      );
      final sampling = reread.materials.single.baseColorTexture!.sampling;
      expect(sampling.mipLinear, isFalse);
      expect(sampling.useMipmaps, isTrue);
    });

    test('the default (mipLinear: true) survives the round trip', () {
      final reread = roundTrip(const TextureSampling());
      final sampling = reread.materials.single.baseColorTexture!.sampling;
      // Mutation: encode `mipLinear` directly rather than inverted
      // (`mipNearest`). A file written before this flag existed leaves the
      // bit at its zeroed default, and a direct encoding would read that back
      // as `mipLinear: false` — silently darkening every old trilinear
      // texture's mip transitions rather than keeping the historical default.
      expect(sampling.mipLinear, isTrue);
    });
  });
}
