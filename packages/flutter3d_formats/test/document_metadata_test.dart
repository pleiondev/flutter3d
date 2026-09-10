/// What a document says about itself: the tool that made it, and where each
/// piece came from.
///
///     dart test test/document_metadata_test.dart
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

final class _BytesSource extends AssetSource {
  const _BytesSource(this.bytes);

  final Uint8List bytes;

  @override
  String get key => 'memory:fixture';

  @override
  Future<Uint8List> read() async => bytes;

  @override
  AssetUriResolver get resolveUri =>
      (request) async => throw StateError('nothing to resolve');
}

/// A one-triangle glTF with a named mesh, an `asset.generator`, and an image
/// referenced by an external (non-`data:`) URI.
Uint8List _annotatedGltf() {
  final positions = Float32List.fromList(<double>[0, 0, 0, 1, 0, 0, 0, 1, 0]);
  final buffer = base64Encode(positions.buffer.asUint8List());
  final document = <String, Object?>{
    'asset': <String, Object?>{'version': '2.0', 'generator': 'flutter3d test'},
    'scene': 0,
    'scenes': <Object?>[
      <String, Object?>{
        'nodes': <Object?>[0],
      },
    ],
    'nodes': <Object?>[
      <String, Object?>{'mesh': 0, 'name': 'the node'},
    ],
    'meshes': <Object?>[
      <String, Object?>{
        'name': 'the mesh asset',
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
      <String, Object?>{'source': 0},
    ],
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

void main() {
  group('defaults, for a document nobody set these on', () {
    test('ModelDocument.asset is null', () {
      const document = PlainModelDocument();
      expect(document.asset, isNull);
    });

    test('ModelSurface.meshName is null', () {
      final surface = ModelSurface(
        mesh: MeshData(
          layout: VertexLayout.positionOnly,
          vertices: Float32List(0),
          indices: Uint32List(0),
        ),
        transform: Matrix4.identity(),
      );
      expect(surface.meshName, isNull);
    });

    test('EncodedImage.sourceUri is null', () {
      final image = EncodedImage(bytes: Uint8List.fromList(<int>[1]));
      expect(image.sourceUri, isNull);
    });
  });

  group('glTF names both halves, and only a real path is a source URI', () {
    test('the mesh asset name is not the node name', () async {
      final document = await decodeModel(
        ModelLoadRequest(source: _BytesSource(_annotatedGltf())),
      );
      final surface = document.surfaces.single;
      // Mutation: read `node['name']` for `meshName` too. `name` already
      // carries the node's own — "the node" — and a `meshName` that agreed
      // with it would tell a caller nothing `name` did not.
      expect(surface.name, 'the node');
      expect(surface.meshName, 'the mesh asset');
    });

    test('asset.generator survives to ModelDocument.asset', () async {
      final document = await decodeModel(
        ModelLoadRequest(source: _BytesSource(_annotatedGltf())),
      );
      expect(document.asset, DocumentAsset(generator: 'flutter3d test'));
    });

    test('an external image URI is a source URI; a data URI is not', () async {
      final document = await decodeModel(
        ModelLoadRequest(source: _BytesSource(_annotatedGltf())),
      );
      expect(document.images.single.sourceUri, 'brick.png');
    });

    test('a document with no asset block reads back with asset null', () async {
      final positions = Float32List.fromList(<double>[
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        1,
        0,
      ]);
      final buffer = base64Encode(positions.buffer.asUint8List());
      final bare = <String, Object?>{
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
              },
            ],
          },
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
      final document = await decodeModel(
        ModelLoadRequest(
          source: _BytesSource(
            Uint8List.fromList(utf8.encode(jsonEncode(bare))),
          ),
        ),
      );
      expect(document.asset, isNull);
      expect(document.surfaces.single.meshName, isNull);
    });
  });

  group('OBJ has one name for a texture, and it is the source URI too', () {
    test('map_Kd names the source URI', () async {
      const obj = '''
mtllib m.mtl
v 0 0 0
v 1 0 0
v 0 1 0
usemtl brick
f 1 2 3
''';
      const mtl = '''
newmtl brick
map_Kd textures/brick.png
''';
      final document = await ObjLoader().load(
        Uint8List.fromList(utf8.encode(obj)),
        resolveUri: (request) async {
          if (request.uri == 'm.mtl') {
            return Uint8List.fromList(utf8.encode(mtl));
          }
          if (request.uri == 'textures/brick.png') {
            return Uint8List.fromList(<int>[1, 2, 3]);
          }
          throw StateError('nothing to resolve "${request.uri}"');
        },
      );
      expect(document.images.single.sourceUri, 'textures/brick.png');
    });
  });

  group('.f3d carries all three through a round trip', () {
    test('meshName, asset.generator and an image sourceUri all survive', () {
      final surface = ModelSurface(
        mesh: MeshData(
          layout: VertexLayout.positionOnly,
          vertices: Float32List(3 * 3),
          indices: Uint32List.fromList(<int>[0, 1, 2]),
        ),
        transform: Matrix4.identity(),
        meshName: 'the mesh asset',
      );
      final document = PlainModelDocument(
        surfaces: <ModelSurface>[surface],
        images: <EncodedImage>[
          EncodedImage(
            bytes: Uint8List.fromList(<int>[1, 2, 3]),
            sourceUri: 'brick.png',
          ),
        ],
        asset: const DocumentAsset(generator: 'flutter3d test'),
      );
      final bytes = F3dWriter(document).write();
      final reread = F3dDocument.parse(bytes);

      expect(reread.surfaces.single.meshName, 'the mesh asset');
      expect(reread.asset, const DocumentAsset(generator: 'flutter3d test'));
      expect(reread.images.single.sourceUri, 'brick.png');
    });

    test('none of the three is required; all read back null', () {
      final surface = ModelSurface(
        mesh: MeshData(
          layout: VertexLayout.positionOnly,
          vertices: Float32List(3 * 3),
          indices: Uint32List.fromList(<int>[0, 1, 2]),
        ),
        transform: Matrix4.identity(),
      );
      final document = PlainModelDocument(
        surfaces: <ModelSurface>[surface],
        images: <EncodedImage>[
          EncodedImage(bytes: Uint8List.fromList(<int>[1])),
        ],
      );
      final bytes = F3dWriter(document).write();
      final reread = F3dDocument.parse(bytes);

      expect(reread.surfaces.single.meshName, isNull);
      expect(reread.asset, isNull);
      expect(reread.images.single.sourceUri, isNull);
    });
  });
}
