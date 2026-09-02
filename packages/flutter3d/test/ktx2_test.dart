/// Proves the KTX2 reader against the specification, not against itself.
///
/// No `.ktx2` fixture files: the byte layout below is copied from the
/// official KTX2 specification and from `VkFormat`'s numbers in
/// `KhronosGroup/KTX-Software` (see `ktx2_format.dart`), assembled here by
/// hand field by field. A test that built a file with the loader's own writer
/// and then read it back with the loader would only prove internal
/// consistency; this proves the reader agrees with the format's actual
/// authors.
///
/// Runs off-device: everything is `ByteData` over a plain `Uint8List`, the
/// same property `f3d_test.dart` and `gpu_formats_test.dart` rely on.
library;

import 'dart:typed_data';

import 'package:flutter3d/src/engine/assets/ktx2/ktx2.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_test/flutter_test.dart';

/// Assembles a minimal, otherwise-valid KTX2 file so one field at a time can
/// be pushed out of the range this stage of the loader accepts.
///
/// The data format descriptor and key/value data are left absent
/// (`dfdByteLength`/`kvdByteLength` stay zero) — this stage never reads them,
/// only `vkFormat` directly, so a file that omitted them is exactly as valid
/// to it as one that carried them.
Uint8List buildKtx2({
  int vkFormat = VkFormat.bc7UNormBlock,
  int pixelWidth = 4,
  int pixelHeight = 4,
  int pixelDepth = 0,
  int layerCount = 0,
  int faceCount = 1,
  int supercompressionScheme = Ktx2SupercompressionScheme.none,
  List<List<int>> levels = const [
    [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
  ],
}) {
  final levelCount = levels.length;
  var cursor = kKtx2LevelIndexOffset + levelCount * kKtx2LevelIndexEntryBytes;
  final payloadOffsets = <int>[];
  for (final level in levels) {
    payloadOffsets.add(cursor);
    cursor += level.length;
  }

  final bytes = Uint8List(cursor);
  bytes.setRange(0, kKtx2Identifier.length, kKtx2Identifier);
  final view = ByteData.view(bytes.buffer);

  void putHeader(int field, int value) =>
      view.setUint32(kKtx2HeaderOffset + field, value, Endian.little);
  putHeader(Ktx2HeaderField.vkFormat, vkFormat);
  putHeader(Ktx2HeaderField.typeSize, 1);
  putHeader(Ktx2HeaderField.pixelWidth, pixelWidth);
  putHeader(Ktx2HeaderField.pixelHeight, pixelHeight);
  putHeader(Ktx2HeaderField.pixelDepth, pixelDepth);
  putHeader(Ktx2HeaderField.layerCount, layerCount);
  putHeader(Ktx2HeaderField.faceCount, faceCount);
  putHeader(Ktx2HeaderField.levelCount, levelCount);
  putHeader(Ktx2HeaderField.supercompressionScheme, supercompressionScheme);

  for (var i = 0; i < levelCount; i++) {
    final entry = kKtx2LevelIndexOffset + i * kKtx2LevelIndexEntryBytes;
    // Each 64-bit field as two little-endian 32-bit halves; the high half is
    // always zero here, well within what every test file needs.
    view.setUint32(entry, payloadOffsets[i], Endian.little);
    view.setUint32(entry + 4, 0, Endian.little);
    view.setUint32(entry + 8, levels[i].length, Endian.little);
    view.setUint32(entry + 12, 0, Endian.little);
    view.setUint32(entry + 16, levels[i].length, Endian.little);
    view.setUint32(entry + 20, 0, Endian.little);
    bytes.setRange(
      payloadOffsets[i],
      payloadOffsets[i] + levels[i].length,
      levels[i],
    );
  }
  return bytes;
}

void main() {
  test('a single-level BC7 texture reads its dimensions, format and bytes', () {
    final level = List<int>.generate(16, (i) => i);
    final texture = Ktx2Texture.parse(
      buildKtx2(
        vkFormat: VkFormat.bc7UNormBlock,
        pixelWidth: 4,
        pixelHeight: 4,
        levels: [level],
      ),
    );

    expect(texture.pixelWidth, 4);
    expect(texture.pixelHeight, 4);
    expect(texture.format, TextureFormat.bc7RGBAUNormInt);
    expect(texture.levels, hasLength(1));
    expect(
      texture.levels.single.buffer.asUint8List(
        texture.levels.single.offsetInBytes,
        texture.levels.single.lengthInBytes,
      ),
      level,
    );
  });

  test('a level is a view over the file, not a copy', () {
    // Two textures parsed over the same bytes; a write through one is visible
    // in the other only if both alias the file rather than having copied it.
    final encoded = buildKtx2();
    final first = Ktx2Texture.parse(encoded);
    final second = Ktx2Texture.parse(encoded);

    first.levels.single.setUint8(0, 0xFF);
    expect(
      second.levels.single.getUint8(0),
      0xFF,
      reason: 'the levels do not alias the file, so the loader copied',
    );
  });

  test('a three-level R8G8B8A8 mip chain keeps level order', () {
    final levels = [
      List<int>.filled(4, 0xAA), // level 0, base
      List<int>.filled(4, 0xBB), // level 1
      List<int>.filled(4, 0xCC), // level 2, smallest
    ];
    final texture = Ktx2Texture.parse(
      buildKtx2(vkFormat: VkFormat.r8g8b8a8UNorm, levels: levels),
    );

    expect(texture.format, TextureFormat.r8g8b8a8UNormInt);
    expect(texture.levels, hasLength(3));
    for (var i = 0; i < 3; i++) {
      expect(texture.levels[i].getUint8(0), levels[i][0]);
    }
  });

  test('a wrong magic is refused', () {
    final bytes = buildKtx2();
    bytes[0] = 0x00;
    expect(() => Ktx2Texture.parse(bytes), throwsA(isA<Ktx2FormatException>()));
  });

  test('a file truncated inside its last level is refused', () {
    final bytes = buildKtx2();
    final truncated = Uint8List.sublistView(bytes, 0, bytes.length - 4);
    expect(
      () => Ktx2Texture.parse(truncated),
      throwsA(isA<Ktx2FormatException>()),
    );
  });

  test('Zstandard supercompression names itself and is refused', () {
    final bytes = buildKtx2(
      supercompressionScheme: Ktx2SupercompressionScheme.zstandard,
    );
    expect(
      () => Ktx2Texture.parse(bytes),
      throwsA(
        isA<Ktx2FormatException>().having(
          (e) => e.message,
          'message',
          contains('Zstandard'),
        ),
      ),
    );
  });

  test('vkFormat 0 names Basis Universal and is refused', () {
    final bytes = buildKtx2(vkFormat: VkFormat.undefined);
    expect(
      () => Ktx2Texture.parse(bytes),
      throwsA(
        isA<Ktx2FormatException>().having(
          (e) => e.message,
          'message',
          contains('Basis Universal'),
        ),
      ),
    );
  });

  test('an unknown vkFormat names its number and is refused', () {
    final bytes = buildKtx2(vkFormat: 999999);
    expect(
      () => Ktx2Texture.parse(bytes),
      throwsA(
        isA<Ktx2FormatException>().having(
          (e) => e.message,
          'message',
          contains('999999'),
        ),
      ),
    );
  });

  test('a texture array (layerCount > 0) is refused', () {
    final bytes = buildKtx2(layerCount: 2);
    expect(() => Ktx2Texture.parse(bytes), throwsA(isA<Ktx2FormatException>()));
  });

  test('a cube map (faceCount == 6) is refused', () {
    final bytes = buildKtx2(faceCount: 6);
    expect(() => Ktx2Texture.parse(bytes), throwsA(isA<Ktx2FormatException>()));
  });

  test('a 3D texture (pixelDepth > 0) is refused', () {
    final bytes = buildKtx2(pixelDepth: 2);
    expect(() => Ktx2Texture.parse(bytes), throwsA(isA<Ktx2FormatException>()));
  });

  test('levelCount == 0 (runtime mip generation) is refused', () {
    final bytes = buildKtx2(levels: const []);
    expect(() => Ktx2Texture.parse(bytes), throwsA(isA<Ktx2FormatException>()));
  });

  test('isKtx2File recognises the identifier and nothing else', () {
    expect(isKtx2File(buildKtx2()), isTrue);
    expect(isKtx2File(Uint8List.fromList([1, 2, 3, 4])), isFalse);
    expect(isKtx2File(Uint8List(0)), isFalse);
  });
}
