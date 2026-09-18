/// `ap-07`/`fmt-22`/`mat-30`: the converter actually re-encodes a texture,
/// not only accepts the flag that asks for it.
library;

import 'dart:typed_data';

import 'package:flutter3d_build/flutter3d_build.dart';
import 'package:flutter3d_core/formats.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

Uint8List _pngOf({required bool alpha, int size = 8}) {
  final image = img.Image(
    width: size,
    height: size,
    numChannels: alpha ? 4 : 3,
  );
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      image.setPixelRgba(
        x,
        y,
        (x * 30) & 0xFF,
        80,
        (y * 30) & 0xFF,
        alpha ? 128 : 255,
      );
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

EncodedImage _image(Uint8List bytes) =>
    EncodedImage(bytes: bytes, name: 'test');

void main() {
  test('none and auto leave every image untouched', () async {
    final document = PlainModelDocument(images: [_image(_pngOf(alpha: false))]);

    for (final family in <TextureFamily>[
      TextureFamily.none,
      TextureFamily.auto,
    ]) {
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

  test('a compressed texture carries a mip chain', () async {
    // **`gfx-69n`.** One level was the case where compressing makes the picture
    // worse: a minified surface has nothing to fall back to, samples the base
    // at a stride and shimmers, and the block artefacts shimmer with it. The
    // uploader has always taken `levels.sublist(1)` as the chain; nothing was
    // giving it one.
    //
    // 64 halves to 32, 16, 8 and 4, and four is the block, so five levels.
    final document = PlainModelDocument(
      images: [_image(_pngOf(alpha: false, size: 64))],
    );
    final result = await encodeDocumentTextures(document, TextureFamily.bc);
    final texture = Ktx2Texture.parse(result.images.single.bytes);

    expect(texture.levels.length, 5);
    expect(texture.pixelWidth, 64);

    // Each level is a quarter of the one above it, because a block-compressed
    // level is a fixed number of bytes per 4x4 block and halving both sides
    // quarters the blocks. A chain built by re-encoding the *base* every time
    // would have five identical lengths.
    for (var i = 1; i < texture.levels.length; i++) {
      expect(
        texture.levels[i].lengthInBytes * 4,
        texture.levels[i - 1].lengthInBytes,
        reason: 'level $i is not a quarter of level ${i - 1}',
      );
    }
  });

  test('the chain stops where the blocks stop', () async {
    // 12 halves to 6, which is not whole 4x4 blocks and cannot be encoded at
    // all — so the chain is the base alone rather than an error, on the same
    // terms the base itself is refused when it is not blocks.
    final document = PlainModelDocument(
      images: [_image(_pngOf(alpha: false, size: 12))],
    );
    final result = await encodeDocumentTextures(document, TextureFamily.bc);
    final texture = Ktx2Texture.parse(result.images.single.bytes);

    expect(texture.levels.length, 1);
    expect(texture.pixelWidth, 12);
  });

  test('a level averages the four texels it replaces', () async {
    // A box filter, because a mip level is the value a bilinear tap would have
    // found had it read four texels at once. A black-and-white checkerboard
    // halves to a flat mid grey, and a sharper kernel would leave it patterned
    // — which is aliasing put back by hand.
    final image = img.Image(width: 8, height: 8, numChannels: 3);
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        final on = (x + y).isEven;
        image.setPixelRgba(x, y, on ? 255 : 0, on ? 255 : 0, on ? 255 : 0, 255);
      }
    }

    final document = PlainModelDocument(
      images: [_image(Uint8List.fromList(img.encodePng(image)))],
    );
    final result = await encodeDocumentTextures(document, TextureFamily.bc);
    final texture = Ktx2Texture.parse(result.images.single.bytes);

    expect(texture.levels.length, 2);

    // BC1 stores two RGB565 endpoints and a two-bit selector per texel. A block
    // of one colour puts the endpoints on top of each other — within a step of
    // each other rather than exactly equal, which is the encoder's own choice
    // of where to sit and not this filter's business — and mid grey lands at
    // about 32 of the green channel's 63.
    final level = texture.levels.last;
    final first = level.getUint16(0, Endian.little);
    final second = level.getUint16(2, Endian.little);
    expect(
      (first - second).abs(),
      lessThanOrEqualTo(1),
      reason: 'the halved checkerboard is not one flat colour',
    );
    expect((first >> 5) & 0x3F, inInclusiveRange(30, 34));
  });

  group('the universal family — gfx-83n', () {
    test('writes no vkFormat, and says so in the key/value data', () async {
      final document = PlainModelDocument(
        images: [_image(_pngOf(alpha: false))],
      );
      final result = await encodeDocumentTextures(
        document,
        TextureFamily.universal,
      );

      final bytes = result.images.single.bytes;
      expect(isKtx2File(bytes), isTrue);
      // The header cannot name the format because the blocks are not one —
      // the key is what a loader reads instead.
      expect(universalBlockFormat(bytes)?.hasAlpha, isFalse);
      expect(
        Ktx2Texture.parse(bytes, universalTarget: UniversalTarget.bc1).vkFormat,
        VkFormat.bc1RgbaUNormBlock,
      );
    });

    test('an image with alpha is cooked rather than refused', () async {
      // The one place `universal` differs from `etc2` in what it accepts: ETC2
      // has no alpha block here and leaves such an image as it arrived, and
      // the intermediate carries alpha whether or not the device's eventual
      // format does.
      final document = PlainModelDocument(
        images: [_image(_pngOf(alpha: true))],
      );
      final result = await encodeDocumentTextures(
        document,
        TextureFamily.universal,
      );
      expect(
        universalBlockFormat(result.images.single.bytes)?.hasAlpha,
        isTrue,
      );
    });

    test('one cooked file becomes each device family\'s own format', () async {
      // The row's own acceptance, at the level the converter can state it: the
      // same bytes, parsed three ways, come back as three different formats.
      final document = PlainModelDocument(
        images: [_image(_pngOf(alpha: false, size: 16))],
      );
      final result = await encodeDocumentTextures(
        document,
        TextureFamily.universal,
      );
      final bytes = result.images.single.bytes;

      for (final (target, vkFormat) in <(UniversalTarget, int)>[
        (UniversalTarget.bc1, VkFormat.bc1RgbaUNormBlock),
        (UniversalTarget.astc4x4, VkFormat.astc4x4UNormBlock),
        (UniversalTarget.etc2Rgb8, VkFormat.etc2R8g8b8UNormBlock),
      ]) {
        final texture = Ktx2Texture.parse(bytes, universalTarget: target);
        expect(texture.vkFormat, vkFormat, reason: target.name);
        expect(texture.pixelWidth, 16);
        expect(texture.levels, hasLength(3));
      }
    });
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
}
