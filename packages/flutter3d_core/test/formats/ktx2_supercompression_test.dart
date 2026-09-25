/// A supercompressed KTX2 opens — `gfx-78n`.
///
///     dart test test/formats/ktx2_supercompression_test.dart
///
/// **What was refused and why it mattered.** `Ktx2Texture.parse` accepted
/// exactly one supercompression scheme, Basis-LZ, and refused the other two by
/// number. `toktx --zcmp` writes Zstandard; that is not an exotic option, it is
/// what a toolchain reaches for when it wants a KTX2 smaller than its pixels,
/// and a texture authored anywhere else simply did not open. ZLIB is the
/// cheaper sibling and the engine already had an inflate one directory over,
/// so refusing it was costing nothing and buying nothing.
///
/// Both wrap the ordinary level index rather than replacing it, which is the
/// whole reason this is one call per level: the pixels are a compressed stream
/// and the index's third field says what they unpack to.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

import 'helpers/build_ktx2.dart';

/// The payload the committed `.zst` beside this test was made from.
///
/// Repeated here rather than committed, so the only file in the fixture
/// directory is the one nothing in this repository can produce.
Uint8List _gradient([int n = 4096]) => Uint8List.fromList(<int>[
  for (var i = 0; i < n; i++) (i * 37 + (i >> 5)) & 255,
]);

void main() {
  test('a Zstandard KTX2 unpacks to the bytes the compressor was given', () {
    final compressed = File(
      'test/formats/fixtures/zstd/gradient.zst',
    ).readAsBytesSync();
    final plain = _gradient();

    final file = buildKtx2(
      vkFormat: VkFormat.r8g8b8a8UNorm,
      pixelWidth: 32,
      pixelHeight: 32,
      supercompressionScheme: Ktx2SupercompressionScheme.zstandard,
      levels: <List<int>>[compressed],
      uncompressedLengths: <int>[plain.length],
    );

    final texture = Ktx2Texture.parse(file);
    expect(texture.levels, hasLength(1));
    expect(
      Uint8List.view(
        texture.levels[0].buffer,
        texture.levels[0].offsetInBytes,
        texture.levels[0].lengthInBytes,
      ),
      orderedEquals(plain),
      reason: 'the level did not come back as the compressor was given it',
    );
  });

  test('a ZLIB KTX2 unpacks the same way', () {
    // Compressed here rather than committed, because this repository *can*
    // write a zlib stream — `deflate.dart` — so a fixture would be recording
    // our own output instead of somebody else's.
    final plain = _gradient(1024);
    final compressed = zlibCompress(plain);

    final file = buildKtx2(
      vkFormat: VkFormat.r8g8b8a8UNorm,
      pixelWidth: 16,
      pixelHeight: 16,
      supercompressionScheme: Ktx2SupercompressionScheme.zlib,
      levels: <List<int>>[compressed],
      uncompressedLengths: <int>[plain.length],
    );

    final texture = Ktx2Texture.parse(file);
    expect(
      Uint8List.view(
        texture.levels[0].buffer,
        texture.levels[0].offsetInBytes,
        texture.levels[0].lengthInBytes,
      ),
      orderedEquals(plain),
    );
  });

  test('a level that unpacks to the wrong size is refused', () {
    // The index's claim is held to rather than trusted: mip dimensions come
    // from the header and the pixels from here, and a file where the two
    // disagree uploads a level that reads past the end of one of them.
    final plain = _gradient(1024);
    final file = buildKtx2(
      vkFormat: VkFormat.r8g8b8a8UNorm,
      pixelWidth: 16,
      pixelHeight: 16,
      supercompressionScheme: Ktx2SupercompressionScheme.zlib,
      levels: <List<int>>[zlibCompress(plain)],
      uncompressedLengths: <int>[plain.length + 1],
    );

    expect(
      () => Ktx2Texture.parse(file),
      throwsA(
        isA<Ktx2FormatException>().having(
          (e) => e.message,
          'message',
          contains('decompressed to'),
        ),
      ),
    );
  });

  test('a stream that does not decompress is refused by name', () {
    final file = buildKtx2(
      vkFormat: VkFormat.r8g8b8a8UNorm,
      supercompressionScheme: Ktx2SupercompressionScheme.zstandard,
      levels: const <List<int>>[
        <int>[9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9],
      ],
      uncompressedLengths: const <int>[64],
    );

    expect(
      () => Ktx2Texture.parse(file),
      throwsA(
        isA<Ktx2FormatException>().having(
          (e) => e.message,
          'message',
          contains('Zstandard'),
        ),
      ),
    );
  });

  test('an unsupported scheme is still refused, and says which', () {
    // Khronos reserves everything to 0xFFFF, so a number this build does not
    // know is a scheme it predates rather than somebody's extension — and the
    // message has to keep saying so now that two of the four are handled.
    final file = buildKtx2(
      vkFormat: VkFormat.r8g8b8a8UNorm,
      supercompressionScheme: 77,
    );

    expect(
      () => Ktx2Texture.parse(file),
      throwsA(
        isA<Ktx2FormatException>().having(
          (e) => e.message,
          'message',
          contains('77'),
        ),
      ),
    );
  });

  test('an uncompressed file is untouched by any of this', () {
    // The path seventy-eight goldens and every existing asset take. A level with
    // no supercompression is handed back as a view on the file's own bytes,
    // with nothing copied and nothing decoded.
    final file = buildKtx2(
      vkFormat: VkFormat.r8g8b8a8UNorm,
      levels: const <List<int>>[
        <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
      ],
    );
    final texture = Ktx2Texture.parse(file);
    expect(texture.levels[0].lengthInBytes, 16);
    expect(texture.levels[0].getUint8(0), 1);
    expect(texture.levels[0].getUint8(15), 16);
  });
}
