/// Guessing an image's format from its own bytes, with no filename to help.
///
///     dart test test/image_sniff_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

void main() {
  test('PNG is sniffed by its eight-byte magic', () {
    expect(
      sniffImageMimeType(
        Uint8List.fromList(<int>[
          0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
          0, 0, 0, 0,
        ]),
      ),
      'image/png',
    );
  });

  test('JPEG is sniffed by its three-byte magic', () {
    expect(
      sniffImageMimeType(Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE0])),
      'image/jpeg',
    );
  });

  test('KTX2 is sniffed by its twelve-byte magic', () {
    expect(
      sniffImageMimeType(
        Uint8List.fromList(<int>[
          0xAB, 0x4B, 0x54, 0x58, 0x20, 0x32, 0x30, 0xBB, //
          0x0D, 0x0A, 0x1A, 0x0A,
        ]),
      ),
      'image/ktx2',
    );
  });

  test('WebP is sniffed by RIFF plus the WEBP tag at byte 8', () {
    expect(
      sniffImageMimeType(
        Uint8List.fromList(<int>[
          0x52, 0x49, 0x46, 0x46, // RIFF
          0, 0, 0, 0, // size, ignored
          0x57, 0x45, 0x42, 0x50, // WEBP
        ]),
      ),
      'image/webp',
    );
  });

  test('a RIFF file that is not WebP is not sniffed as one', () {
    // Mutation: stop checking bytes 8-11 once RIFF is seen. AVI and WAV are
    // both RIFF containers, and a writer that called either one WebP would
    // hand a decoder a file its own magic says is something else.
    expect(
      sniffImageMimeType(
        Uint8List.fromList(<int>[
          0x52, 0x49, 0x46, 0x46, //
          0, 0, 0, 0, //
          0x41, 0x56, 0x49, 0x20, // AVI
        ]),
      ),
      isNull,
    );
  });

  test('nothing recognised is null, not a guess', () {
    expect(sniffImageMimeType(Uint8List.fromList(<int>[1, 2, 3])), isNull);
    expect(sniffImageMimeType(Uint8List(0)), isNull);
  });

  test('bytes shorter than a magic do not throw', () {
    expect(sniffImageMimeType(Uint8List.fromList(<int>[0x89, 0x50])), isNull);
  });

  group('isKtx2BasisUniversal', () {
    test('vkFormat 0 (VK_FORMAT_UNDEFINED) is Basis Universal', () {
      expect(isKtx2BasisUniversal(_ktx2Of(vkFormat: 0)), isTrue);
    });

    test('a real vkFormat — BC1, say — is not Basis Universal', () {
      // 131 = VK_FORMAT_BC1_RGB_UNORM_BLOCK, an already-compressed block
      // format Basis Universal never produces.
      expect(isKtx2BasisUniversal(_ktx2Of(vkFormat: 131)), isFalse);
    });

    test('a non-KTX2 file, even one long enough, is not Basis Universal', () {
      expect(
        isKtx2BasisUniversal(
          Uint8List.fromList(<int>[
            0x89,
            0x50,
            0x4E,
            0x47,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
          ]),
        ),
        isFalse,
      );
    });

    test('a KTX2 file too short to hold vkFormat does not throw', () {
      expect(
        isKtx2BasisUniversal(
          Uint8List.fromList(<int>[
            0xAB, 0x4B, 0x54, 0x58, 0x20, 0x32, 0x30, 0xBB, //
            0x0D, 0x0A, 0x1A, 0x0A,
          ]),
        ),
        isFalse,
      );
    });
  });
}

/// A minimal KTX2 file: the twelve-byte magic, then [vkFormat] as the next
/// four bytes little-endian, padded to a header a real file's own length
/// checks would accept.
Uint8List _ktx2Of({required int vkFormat}) {
  final bytes = Uint8List(32);
  bytes.setRange(0, 12, const <int>[
    0xAB, 0x4B, 0x54, 0x58, 0x20, 0x32, 0x30, 0xBB, //
    0x0D, 0x0A, 0x1A, 0x0A,
  ]);
  ByteData.sublistView(bytes, 12, 16).setUint32(0, vkFormat, Endian.little);
  return bytes;
}
