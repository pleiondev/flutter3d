/// `ap-07`/`fmt-22`/`mat-30`: the converter actually re-encodes a texture,
/// not only accepts the flag that asks for it.
library;

import 'dart:typed_data';

import 'package:flutter3d_build/flutter3d_build.dart';
import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

Uint8List _pngOf({required bool alpha}) {
  final image = img.Image(width: 8, height: 8, numChannels: alpha ? 4 : 3);
  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 8; x++) {
      image.setPixelRgba(x, y, (x * 30) & 0xFF, 80, (y * 30) & 0xFF, alpha ? 128 : 255);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

EncodedImage _image(Uint8List bytes) => EncodedImage(bytes: bytes, name: 'test');

void main() {
  test('none and auto leave every image untouched', () async {
    final document = PlainModelDocument(images: [_image(_pngOf(alpha: false))]);

    for (final family in <TextureFamily>[TextureFamily.none, TextureFamily.auto]) {
      final result = await encodeDocumentTextures(document, family);
      expect(result.images.single.bytes, same(document.images.single.bytes));
    }
  });

  test('bc encodes an opaque image as BC1', () async {
    final document = PlainModelDocument(images: [_image(_pngOf(alpha: false))]);
    final result = await encodeDocumentTextures(document, TextureFamily.bc);

    final bytes = result.images.single.bytes;
    expect(isKtx2File(bytes), isTrue);
    final texture = Ktx2Texture.parse(bytes);
    expect(texture.vkFormat, VkFormat.bc1RgbaUNormBlock);
    expect(texture.pixelWidth, 8);
    expect(texture.pixelHeight, 8);
  });

  test('bc encodes an image with alpha as BC3', () async {
    final document = PlainModelDocument(images: [_image(_pngOf(alpha: true))]);
    final result = await encodeDocumentTextures(document, TextureFamily.bc);

    final texture = Ktx2Texture.parse(result.images.single.bytes);
    expect(texture.vkFormat, VkFormat.bc3UNormBlock);
  });

  test('etc2 encodes an opaque image as ETC2 RGB8', () async {
    final document = PlainModelDocument(images: [_image(_pngOf(alpha: false))]);
    final result = await encodeDocumentTextures(document, TextureFamily.etc2);

    final texture = Ktx2Texture.parse(result.images.single.bytes);
    expect(texture.vkFormat, VkFormat.etc2R8g8b8UNormBlock);
  });

  test('etc2 refuses an image with alpha and reports why, by name', () async {
    final document = PlainModelDocument(images: [_image(_pngOf(alpha: true))]);
    final messages = <String>[];
    final result = await encodeDocumentTextures(
      document,
      TextureFamily.etc2,
      report: messages.add,
    );

    expect(result.images.single.bytes, same(document.images.single.bytes));
    expect(messages.single, contains('test'));
    expect(messages.single, contains('alpha'));
  });

  test('an odd size is left alone and named, not silently cropped', () async {
    final oddPng = Uint8List.fromList(
      img.encodePng(img.Image(width: 5, height: 5)),
    );
    final document = PlainModelDocument(images: [_image(oddPng)]);
    final messages = <String>[];
    final result = await encodeDocumentTextures(
      document,
      TextureFamily.bc,
      report: messages.add,
    );

    expect(result.images.single.bytes, same(oddPng));
    expect(messages.single, contains('5x5'));
  });

  test('an already-KTX2 image is left alone', () async {
    final ktx2 = writeKtx2(
      vkFormat: VkFormat.bc1RgbaUNormBlock,
      pixelWidth: 4,
      pixelHeight: 4,
      levels: [Uint8List(8)],
    );
    final document = PlainModelDocument(images: [_image(ktx2)]);
    final result = await encodeDocumentTextures(document, TextureFamily.bc);
    expect(result.images.single.bytes, same(ktx2));
  });

  test('every other field of the document survives untouched', () async {
    final document = PlainModelDocument(
      images: [_image(_pngOf(alpha: false))],
      warnings: const ['a decoder warning'],
    );
    final result = await encodeDocumentTextures(document, TextureFamily.bc);
    expect(result.warnings, document.warnings);
    expect(result.surfaces, document.surfaces);
  });

  group('ap-09: rolesByImageIndex', () {
    // Image 0 is base colour (sRGB), image 1 is a normal map (never sRGB,
    // filtered as vectors), image 2 is metallic-roughness (plain linear
    // data, neither treatment applies) — the three cases `SurfaceMaterial`
    // actually distinguishes.
    final material = SurfaceMaterial(
      baseColorTexture: const TextureBinding(imageIndex: 0),
      normalTexture: const TextureBinding(imageIndex: 1),
      metallicRoughnessTexture: const TextureBinding(imageIndex: 2),
    );

    test('base colour is sRGB, not a normal map, no alpha test', () {
      final roles = rolesByImageIndex(
        PlainModelDocument(materials: [material]),
      );
      expect(roles[0]!.srgb, isTrue);
      expect(roles[0]!.isNormalMap, isFalse);
      expect(roles[0]!.alphaTestThreshold, isNull);
    });

    test('a normal map is never sRGB', () {
      final roles = rolesByImageIndex(
        PlainModelDocument(materials: [material]),
      );
      expect(roles[1]!.isNormalMap, isTrue);
      expect(roles[1]!.srgb, isFalse);
    });

    test('metallic-roughness is plain linear data, neither treatment', () {
      final roles = rolesByImageIndex(
        PlainModelDocument(materials: [material]),
      );
      expect(roles[2]!.srgb, isFalse);
      expect(roles[2]!.isNormalMap, isFalse);
    });

    test('an unreferenced image index gets no entry at all', () {
      final roles = rolesByImageIndex(
        PlainModelDocument(materials: [material]),
      );
      expect(roles.containsKey(3), isFalse);
    });

    test(
      'a mask material\'s own cutoff becomes the base colour\'s alpha threshold',
      () {
        final masked = SurfaceMaterial(
          baseColorTexture: const TextureBinding(imageIndex: 0),
          alphaMode: SurfaceAlphaMode.mask,
          alphaCutoff: 0.3,
        );
        final roles = rolesByImageIndex(
          PlainModelDocument(materials: [masked]),
        );
        expect(roles[0]!.alphaTestThreshold, 0.3);
      },
    );

    test('opaque and blend materials carry no alpha-test threshold', () {
      for (final mode in [SurfaceAlphaMode.opaque, SurfaceAlphaMode.blend]) {
        final material = SurfaceMaterial(
          baseColorTexture: const TextureBinding(imageIndex: 0),
          alphaMode: mode,
        );
        final roles = rolesByImageIndex(
          PlainModelDocument(materials: [material]),
        );
        expect(roles[0]!.alphaTestThreshold, isNull, reason: '$mode');
      }
    });

    test('the first material to claim an image wins over a later one', () {
      final first = SurfaceMaterial(
        baseColorTexture: const TextureBinding(imageIndex: 0),
      );
      final second = SurfaceMaterial(
        normalTexture: const TextureBinding(imageIndex: 0),
      );
      final roles = rolesByImageIndex(
        PlainModelDocument(materials: [first, second]),
      );
      expect(roles[0]!.srgb, isTrue);
      expect(roles[0]!.isNormalMap, isFalse);
    });
  });
}
