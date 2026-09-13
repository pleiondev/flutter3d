/// `fmt-21`'s own row: KTX2 through `GltfWriter` — `KHR_texture_basisu`
/// for a Basis Universal file, a warning otherwise; a warning from
/// `ObjWriter` either way, since `map_Kd` cannot say KTX2 at all.
///
///     dart test test/ktx2_texture_export_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A minimal KTX2 file: the twelve-byte magic, then [vkFormat] little-endian.
Uint8List _ktx2Of({required int vkFormat}) {
  final bytes = Uint8List(32);
  bytes.setRange(0, 12, const <int>[
    0xAB, 0x4B, 0x54, 0x58, 0x20, 0x32, 0x30, 0xBB, //
    0x0D, 0x0A, 0x1A, 0x0A,
  ]);
  ByteData.sublistView(bytes, 12, 16).setUint32(0, vkFormat, Endian.little);
  return bytes;
}

MeshData _texturedTriangle() {
  final builder = MeshBuilder(
    VertexLayout.positionNormalTexcoord,
    reserveVertices: 3,
    reserveIndices: 3,
  );
  for (var i = 0; i < 3; i++) {
    builder.addVertex(
      position: Vector3(i.toDouble(), 0.0, 0.0),
      normal: Vector3(0.0, 0.0, 1.0),
      texcoord: Vector2(0.0, 0.0),
    );
  }
  builder.addTriangle(0, 1, 2);
  return builder.build();
}

/// A one-triangle, one-material document whose material's own
/// `baseColorTexture` names image 0 — [ktx2] is that image's bytes.
PlainModelDocument _documentWithImage(Uint8List ktx2) {
  final mesh = _texturedTriangle();
  return PlainModelDocument(
    surfaces: <ModelSurface>[
      ModelSurface(
        name: 'a',
        mesh: mesh,
        transform: Matrix4.identity(),
        materialIndex: 0,
      ),
    ],
    nodes: <ModelNode>[
      ModelNode(name: 'a', surfaces: <int>[0]),
    ],
    materials: <SurfaceMaterial>[
      SurfaceMaterial(baseColorTexture: const TextureBinding(imageIndex: 0)),
    ],
    images: <EncodedImage>[EncodedImage(bytes: ktx2)],
  );
}

void main() {
  group('GltfWriter and Basis Universal KTX2', () {
    test('a Basis Universal texture writes through KHR_texture_basisu, no '
        'warning, and the loader reads it back', () async {
      final document = _documentWithImage(_ktx2Of(vkFormat: 0));
      final writer = GltfWriter(document);
      final bytes = writer.writeGlb();

      expect(writer.warnings, isEmpty);

      // The texture's own JSON shape, not just the loader's own answer:
      // a texture carrying *both* a core `source` and the extension
      // would still read back correctly (the loader prefers the core
      // one when it is there), which would hide a writer that stopped
      // omitting it.
      final json = GlbContainer.parse(bytes).json;
      final textures = json['textures']! as List<Object?>;
      final texture = textures.single! as Map<String, Object?>;
      expect(texture.containsKey('source'), isFalse);
      expect(
        texture['extensions'],
        equals(<String, Object?>{
          'KHR_texture_basisu': <String, Object?>{'source': 0},
        }),
      );
      expect(json['extensionsUsed'], contains('KHR_texture_basisu'));
      expect(json['extensionsRequired'], contains('KHR_texture_basisu'));

      final readBack = await GltfLoader().load(bytes);
      expect(readBack.materials.single.baseColorTexture, isNotNull);
      final imageIndex = readBack.materials.single.baseColorTexture!.imageIndex;
      expect(readBack.images[imageIndex].bytes, _ktx2Of(vkFormat: 0));
    });

    test(
      'a non-Basis KTX2 (a real vkFormat) writes as the core image and warns',
      () {
        final document = _documentWithImage(_ktx2Of(vkFormat: 131));
        final writer = GltfWriter(document);
        writer.writeGlb();

        expect(
          writer.warnings,
          contains(predicate<String>((w) => w.contains('Basis Universal'))),
        );
      },
    );

    test('a plain PNG image gets no KTX2 warning at all', () {
      final png = Uint8List.fromList(<int>[
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
        0, 0, 0, 0,
      ]);
      final document = _documentWithImage(png);
      final writer = GltfWriter(document);
      writer.writeGlb();
      expect(writer.warnings, isEmpty);
    });
  });

  group('ObjWriter and KTX2', () {
    test(
      'a material referencing a KTX2 texture is warned about either way',
      () {
        final document = _documentWithImage(_ktx2Of(vkFormat: 0));
        final writer = ObjWriter(document);
        expect(
          writer.warnings,
          contains(predicate<String>((w) => w.contains('KTX2'))),
        );
      },
    );

    test('a material referencing a PNG texture gets no KTX2 warning', () {
      final png = Uint8List.fromList(<int>[
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
        0, 0, 0, 0,
      ]);
      final document = _documentWithImage(png);
      final writer = ObjWriter(document);
      expect(writer.warnings, isEmpty);
    });
  });
}
