/// `ap-08`'s own glue, `writeKtx2WithMips`, proven against the same loader
/// `ktx2_writer_test.dart` already proves `writeKtx2` against — not a second,
/// hand-rolled reader.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

Rgba8Image _checkerboard({int size = 12, int a = 0, int b = 255}) {
  final pixels = Uint8List(size * size * 4);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final on = (x + y).isEven ? a : b;
      final at = (y * size + x) * 4;
      pixels[at] = on;
      pixels[at + 1] = on;
      pixels[at + 2] = on;
      pixels[at + 3] = 255;
    }
  }
  return Rgba8Image(width: size, height: size, pixels: pixels);
}

void main() {
  test('every level of the chain lands in the file, in order, unchanged', () {
    final source = _checkerboard();
    final chain = buildMipChain(source);
    final bytes = writeKtx2WithMips(source);

    final texture = Ktx2Texture.parse(bytes);
    expect(texture.pixelWidth, source.width);
    expect(texture.pixelHeight, source.height);
    expect(texture.vkFormat, VkFormat.r8g8b8a8UNorm);
    expect(texture.levels, hasLength(chain.length));
    for (var i = 0; i < chain.length; i++) {
      final level = texture.levels[i];
      expect(
        level.buffer.asUint8List(level.offsetInBytes, level.lengthInBytes),
        chain[i].pixels,
        reason: 'level $i (${chain[i].width}x${chain[i].height})',
      );
    }
  });

  test(
    'srgb: true writes the sRGB format and still linear-filters the chain',
    () {
      // The same textbook case `mip_chain_test.dart` uses directly on
      // `buildMipChain`: a black-and-white checkerboard's small level should
      // read near mid-grey once decoded, not dark — proving `writeKtx2WithMips`
      // actually threads `srgb` into the chain it builds, not only into the
      // header field.
      final bytes = writeKtx2WithMips(_checkerboard(size: 16), srgb: true);
      final texture = Ktx2Texture.parse(bytes);
      expect(texture.vkFormat, VkFormat.r8g8b8a8Srgb);

      final small = texture.levels[texture.levels.length - 3];
      expect(small.getUint8(0), greaterThan(160));
    },
  );

  test('a normal map keeps unit-length normals after the round trip', () {
    const size = 16;
    final pixels = Uint8List(size * size * 4);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final (nx, ny, nz) = (x + y).isEven ? (1.0, 0.0, 0.0) : (0.0, 1.0, 0.0);
        final at = (y * size + x) * 4;
        pixels[at] = ((nx + 1) / 2 * 255).round();
        pixels[at + 1] = ((ny + 1) / 2 * 255).round();
        pixels[at + 2] = ((nz + 1) / 2 * 255).round();
        pixels[at + 3] = 255;
      }
    }
    final bytes = writeKtx2WithMips(
      Rgba8Image(width: size, height: size, pixels: pixels),
      isNormalMap: true,
    );
    final texture = Ktx2Texture.parse(bytes);

    for (final level in texture.levels) {
      final bytesPerLevel = level.lengthInBytes ~/ 4;
      for (var i = 0; i < bytesPerLevel; i++) {
        final nx = level.getUint8(i * 4) / 255 * 2 - 1;
        final ny = level.getUint8(i * 4 + 1) / 255 * 2 - 1;
        final nz = level.getUint8(i * 4 + 2) / 255 * 2 - 1;
        final length = math.sqrt(nx * nx + ny * ny + nz * nz);
        expect(length, closeTo(1.0, 0.02), reason: 'texel $i');
      }
    }
  });
}
