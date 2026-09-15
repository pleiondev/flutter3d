/// Proves `writeKtx2` against `Ktx2Texture.parse` — the same file this
/// package's own loader reads back, not a hand-built one.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

void main() {
  test('a single-level BC1 file round-trips through the loader', () {
    final level = Uint8List.fromList(List<int>.generate(8 * 4, (i) => i));
    final bytes = writeKtx2(
      vkFormat: VkFormat.bc1RgbaUNormBlock,
      pixelWidth: 16,
      pixelHeight: 4,
      levels: [level],
    );

    final texture = Ktx2Texture.parse(bytes);
    expect(texture.pixelWidth, 16);
    expect(texture.pixelHeight, 4);
    expect(texture.vkFormat, VkFormat.bc1RgbaUNormBlock);
    expect(texture.levels, hasLength(1));
    expect(
      texture.levels.single.buffer.asUint8List(
        texture.levels.single.offsetInBytes,
        texture.levels.single.lengthInBytes,
      ),
      level,
    );
  });

  test('a three-level chain keeps level order and each level\'s own bytes', () {
    final levels = [
      Uint8List.fromList(List<int>.filled(8, 0xAA)), // level 0, base
      Uint8List.fromList(List<int>.filled(8, 0xBB)),
      Uint8List.fromList(List<int>.filled(8, 0xCC)), // smallest
    ];
    final bytes = writeKtx2(
      vkFormat: VkFormat.etc2R8g8b8UNormBlock,
      pixelWidth: 16,
      pixelHeight: 16,
      levels: levels,
    );

    final texture = Ktx2Texture.parse(bytes);
    expect(texture.levels, hasLength(3));
    for (var i = 0; i < 3; i++) {
      expect(texture.levels[i].getUint8(0), levels[i][0]);
    }
  });

  test(
    'encodeBc1 into writeKtx2 into Ktx2Texture.parse round-trips a real texture',
    () {
      final source = Rgba8Image(
        width: 8,
        height: 8,
        pixels: Uint8List.fromList(
          List<int>.generate(8 * 8 * 4, (i) => (i * 7) & 0xFF),
        ),
      );
      final encoded = encodeBc1(source);
      final bytes = writeKtx2(
        vkFormat: VkFormat.bc1RgbaUNormBlock,
        pixelWidth: source.width,
        pixelHeight: source.height,
        levels: [encoded],
      );

      final texture = Ktx2Texture.parse(bytes);
      expect(texture.vkFormat, VkFormat.bc1RgbaUNormBlock);
      expect(texture.pixelWidth, 8);
      expect(texture.pixelHeight, 8);
      expect(
        texture.levels.single.buffer.asUint8List(
          texture.levels.single.offsetInBytes,
          texture.levels.single.lengthInBytes,
        ),
        encoded,
      );
    },
  );

  test(
    'encodeAstc4x4 into writeKtx2 into Ktx2Texture.parse round-trips a real texture',
    () {
      final source = Rgba8Image(
        width: 8,
        height: 8,
        pixels: Uint8List.fromList(
          List<int>.generate(8 * 8 * 4, (i) => (i * 5) & 0xFF),
        ),
      );
      final encoded = encodeAstc4x4(source);
      final bytes = writeKtx2(
        vkFormat: VkFormat.astc4x4UNormBlock,
        pixelWidth: source.width,
        pixelHeight: source.height,
        levels: [encoded],
      );

      final texture = Ktx2Texture.parse(bytes);
      expect(texture.vkFormat, VkFormat.astc4x4UNormBlock);
      expect(texture.pixelWidth, 8);
      expect(texture.pixelHeight, 8);
      expect(
        texture.levels.single.buffer.asUint8List(
          texture.levels.single.offsetInBytes,
          texture.levels.single.lengthInBytes,
        ),
        encoded,
      );
    },
  );

  test('at least one level is required', () {
    expect(
      () => writeKtx2(
        vkFormat: VkFormat.bc1RgbaUNormBlock,
        pixelWidth: 4,
        pixelHeight: 4,
        levels: const [],
      ),
      throwsArgumentError,
    );
  });
}
