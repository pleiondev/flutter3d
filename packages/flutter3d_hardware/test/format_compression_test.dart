/// [TextureFormatCompression] — the block-compressed tail of [TextureFormat],
/// named once so a backend does not re-list it.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_test/flutter_test.dart';

const compressed = {
  TextureFormat.bc1RGBAUNormInt,
  TextureFormat.bc1RGBAUNormIntSRGB,
  TextureFormat.bc3RGBAUNormInt,
  TextureFormat.bc3RGBAUNormIntSRGB,
  TextureFormat.bc5RGUNormInt,
  TextureFormat.bc7RGBAUNormInt,
  TextureFormat.bc7RGBAUNormIntSRGB,
  TextureFormat.etc2RGB8UNormInt,
  TextureFormat.etc2RGB8UNormIntSRGB,
  TextureFormat.etc2RGBA8UNormInt,
  TextureFormat.etc2RGBA8UNormIntSRGB,
  TextureFormat.astc4x4LDR,
  TextureFormat.astc4x4LDRSRGB,
  TextureFormat.astc8x8LDR,
  TextureFormat.astc8x8LDRSRGB,
  TextureFormat.astc4x4HDR,
  TextureFormat.astc8x8HDR,
};

void main() {
  test('isCompressed is true for exactly the block-compressed values', () {
    for (final format in TextureFormat.values) {
      expect(
        format.isCompressed,
        compressed.contains(format),
        reason: '$format',
      );
    }
  });

  test('blockLayout throws for an uncompressed format', () {
    for (final format in TextureFormat.values) {
      if (compressed.contains(format)) continue;
      expect(() => format.blockLayout, throwsStateError, reason: '$format');
    }
  });

  test(
    'every ASTC value here is one of the two block sizes this repository carries',
    () {
      const eightByEight = {
        TextureFormat.astc8x8LDR,
        TextureFormat.astc8x8LDRSRGB,
        TextureFormat.astc8x8HDR,
      };
      for (final format in compressed) {
        if (!format.name.startsWith('astc')) continue;
        final layout = format.blockLayout;
        final expected = eightByEight.contains(format) ? 8 : 4;
        expect(layout.blockWidth, expected, reason: '$format');
        expect(layout.blockHeight, expected, reason: '$format');
        // ASTC is always 128 bits a block, whatever its footprint.
        expect(layout.bytesPerBlock, 16, reason: '$format');
      }
    },
  );

  test('every BC and ETC2 value here is a 4x4 block', () {
    for (final format in compressed) {
      if (format.name.startsWith('astc')) continue;
      final layout = format.blockLayout;
      expect(layout.blockWidth, 4, reason: '$format');
      expect(layout.blockHeight, 4, reason: '$format');
    }
  });

  test('bytesPerBlock matches each format\'s bit depth', () {
    // Half a byte a texel (8 bytes / 16 texels): BC1 and ETC2 without alpha.
    for (final format in [
      TextureFormat.bc1RGBAUNormInt,
      TextureFormat.bc1RGBAUNormIntSRGB,
      TextureFormat.etc2RGB8UNormInt,
      TextureFormat.etc2RGB8UNormIntSRGB,
    ]) {
      expect(format.blockLayout.bytesPerBlock, 8, reason: '$format');
    }
    // One byte a texel (16 bytes / 16 texels): everything else at a 4x4 block.
    for (final format in [
      TextureFormat.bc3RGBAUNormInt,
      TextureFormat.bc3RGBAUNormIntSRGB,
      TextureFormat.bc5RGUNormInt,
      TextureFormat.bc7RGBAUNormInt,
      TextureFormat.bc7RGBAUNormIntSRGB,
      TextureFormat.etc2RGBA8UNormInt,
      TextureFormat.etc2RGBA8UNormIntSRGB,
    ]) {
      expect(format.blockLayout.bytesPerBlock, 16, reason: '$format');
    }
  });
}
