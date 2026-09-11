/// `textureInfo`: declared size, format badge and on-device weight, read
/// from a texture's own header, no decoder.
///
///     dart test test/texture_info_test.dart
///
/// Dimensions are deliberately not multiples of a block's width or height in
/// the compressed fixtures (68×40, a 4×4 block) so the ceiling-division a
/// partial block needs is actually exercised, not hidden behind numbers that
/// divide evenly.
library;

import 'dart:typed_data';

import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';

Uint8List _png(int width, int height) {
  final bytes = Uint8List(33);
  final view = ByteData.sublistView(bytes);
  bytes.setAll(0, <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  view.setUint32(8, 13, Endian.big);
  bytes.setAll(12, <int>[0x49, 0x48, 0x44, 0x52]);
  view.setUint32(16, width, Endian.big);
  view.setUint32(20, height, Endian.big);
  bytes.setAll(24, <int>[8, 6, 0, 0, 0]);
  return bytes;
}

const List<int> _ktx2Identifier = <int>[
  0xAB,
  0x4B,
  0x54,
  0x58,
  0x20,
  0x32,
  0x30,
  0xBB,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
];

/// A KTX2 fixture with just the 48-byte header, or — when [levelByteLengths]
/// is given — a level index behind it too, one 24-byte entry per level with
/// its `byteLength` field set from the list (`byteOffset` and
/// `uncompressedByteLength` left at zero; this reader never looks at
/// either).
Uint8List _ktx2(
  int width,
  int height, {
  required int vkFormat,
  int levelCount = 1,
  List<int>? levelByteLengths,
}) {
  final levels = levelCount == 0 ? 1 : levelCount;
  final withIndex = levelByteLengths != null;
  final bytes = Uint8List(48 + (withIndex ? levels * 24 : 0));
  final view = ByteData.sublistView(bytes);
  bytes.setAll(0, _ktx2Identifier);
  view.setUint32(12 + 0, vkFormat, Endian.little);
  view.setUint32(12 + 4, 1, Endian.little); // typeSize
  view.setUint32(12 + 8, width, Endian.little);
  view.setUint32(12 + 12, height, Endian.little);
  view.setUint32(12 + 16, 0, Endian.little); // pixelDepth
  view.setUint32(12 + 20, 0, Endian.little); // layerCount
  view.setUint32(12 + 24, 1, Endian.little); // faceCount
  view.setUint32(12 + 28, levelCount, Endian.little);
  view.setUint32(12 + 32, 0, Endian.little); // supercompressionScheme
  if (withIndex) {
    for (var i = 0; i < levels; i++) {
      final o = 48 + i * 24;
      view.setUint64(o, 0, Endian.little); // byteOffset, unread
      view.setUint64(o + 8, levelByteLengths[i], Endian.little);
      view.setUint64(o + 16, levelByteLengths[i], Endian.little); // unread
    }
  }
  return bytes;
}

void main() {
  group('PNG/JPEG: no GPU compression, no mips of their own', () {
    test('bytesOnDevice is width × height × 4', () {
      expect(
        textureInfo(_png(256, 128)),
        const TextureInfo(
          width: 256,
          height: 128,
          format: TextureFileFormat.rgba8,
          bytesOnDevice: 256 * 128 * 4,
          hasOwnMips: false,
        ),
      );
    });
  });

  group('KTX2: a recognised vkFormat, computed from block size alone', () {
    test('BC7, one level: blocks cover the image exactly', () {
      // 64×32 over a 4×4 block: 16×8 blocks, 16 bytes each.
      final info = textureInfo(_ktx2(64, 32, vkFormat: 145));
      expect(
        info,
        const TextureInfo(
          width: 64,
          height: 32,
          format: TextureFileFormat.bc7,
          bytesOnDevice: 16 * 8 * 16,
          hasOwnMips: false,
        ),
      );
    });

    test('BC1, three levels: partial blocks round up, mips halve', () {
      // Level 0: 68×40 → 17×10 blocks × 8 bytes = 1360.
      // Level 1: 34×20 → 9×5 blocks × 8 bytes = 360.
      // Level 2: 17×10 → 5×3 blocks × 8 bytes = 120.
      final info = textureInfo(_ktx2(68, 40, vkFormat: 133, levelCount: 3));
      expect(
        info,
        const TextureInfo(
          width: 68,
          height: 40,
          format: TextureFileFormat.bc1,
          bytesOnDevice: 1360 + 360 + 120,
          hasOwnMips: true,
        ),
      );
    });

    test('ETC2 RGBA8 and ASTC 4×4 both map to their own badge', () {
      expect(
        textureInfo(_ktx2(32, 32, vkFormat: 151))?.format,
        TextureFileFormat.etc2Rgba8,
      );
      expect(
        textureInfo(_ktx2(32, 32, vkFormat: 157))?.format,
        TextureFileFormat.astc4x4,
      );
    });
  });

  group('KTX2: a vkFormat this reader does not map', () {
    test('falls back to the level index\'s own stored total', () {
      final info = textureInfo(
        _ktx2(
          32,
          32,
          vkFormat: 0, // undefined: Basis Universal, by KTX2's own convention
          levelCount: 2,
          levelByteLengths: <int>[100, 30],
        ),
      );
      expect(
        info,
        const TextureInfo(
          width: 32,
          height: 32,
          format: TextureFileFormat.other,
          bytesOnDevice: 130,
          hasOwnMips: true,
        ),
      );
    });

    test('answers null when the level index itself is not there to fall '
        'back on', () {
      // levelByteLengths omitted: header only, no index bytes at all.
      expect(textureInfo(_ktx2(32, 32, vkFormat: 0, levelCount: 2)), isNull);
    });
  });

  group('what is not any of the three, and truncation', () {
    test('unrecognised bytes answer null', () {
      expect(
        textureInfo(Uint8List.fromList(List<int>.filled(64, 0x41))),
        isNull,
      );
    });

    test('a KTX2 header cut before pixelHeight answers null', () {
      final full = _ktx2(64, 32, vkFormat: 145);
      expect(textureInfo(Uint8List.sublistView(full, 0, 22)), isNull);
    });
  });

  group('equality', () {
    test('two readings of the same bytes compare equal', () {
      expect(
        textureInfo(_ktx2(16, 16, vkFormat: 145)),
        textureInfo(_ktx2(16, 16, vkFormat: 145)),
      );
    });

    test('a different format at the same size does not compare equal', () {
      expect(
        textureInfo(_ktx2(16, 16, vkFormat: 145)) ==
            textureInfo(_ktx2(16, 16, vkFormat: 133)),
        isFalse,
      );
    });
  });
}
