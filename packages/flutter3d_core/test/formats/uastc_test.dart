/// UASTC unpacks to the pixels the reference transcoder produces — `gfx-78n`.
///
///     dart test test/formats/uastc_test.dart
///
/// **Encoded and unpacked by Basis Universal's own tool**, built from source
/// (`BinomialLLC/basis_universal`, `cmake` and `make basisu`) because it is
/// what defines the format:
///
///     basisu -uastc -uastc_level 4 -ktx2 photo.png
///     basisu -uastc -uastc_level 4 -ktx2 -ktx2_no_zstandard -mipmap alpha.png
///     basisu -uastc -uastc_level 4 -ktx2 -ktx2_no_zstandard [-linear] …
///     basisu -unpack file.ktx2      # → …_unpacked_rgba_RGBA32_level_N_….png
///
/// Each `_level_N.rgba` beside a `.ktx2` is that tool's RGBA32 transcode of
/// level *N*, as raw bytes. So what is compared is this decoder and the
/// reference one on the same blocks — and unpacking is exact integer
/// arithmetic, so they are compared **byte for byte**. A PSNR threshold would
/// be the wrong instrument: it is how a lossy encoder is judged against its
/// source, and a decoder that is one rounding off in one mode passes any
/// threshold worth setting.
///
/// **Nineteen modes, and a test that they are all here.** A UASTC decoder is
/// nineteen decoders behind one switch, and a photograph exercises about four
/// of them. The sources were chosen until every mode appears:
///
/// * `uastc_photo_zstd` — a crop of `AnimatedCube_BaseColor.png`; Zstandard
///   supercompressed, which is what the encoder does by default and is where
///   the two halves of this row meet.
/// * `uastc_alpha_mips` — another crop with a painted alpha channel and a full
///   mip chain down to 1×1, so every level size below one block is covered.
/// * `uastc_grey_alpha_partial` — luminance and alpha, 30×22, so the last row
///   and column of blocks are partial; flat areas for the solid-colour mode.
/// * `uastc_stress`, `uastc_stress_alpha` — built block by block from the
///   format's own partition shapes with two- and many-level content, because
///   nothing else makes an encoder choose the two- and three-subset modes,
///   mode 7's BC7-derived partitions, or one-bit weights.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

const String _fixtures = 'test/formats/fixtures/ktx2';

Uint8List _fixture(String name) => File('$_fixtures/$name').readAsBytesSync();

/// name, width, height, levels.
const List<(String, int, int, int)> _files = <(String, int, int, int)>[
  ('uastc_photo_zstd', 96, 64, 1),
  ('uastc_alpha_mips', 64, 64, 7),
  ('uastc_grey_alpha_partial', 30, 22, 1),
  ('uastc_stress', 64, 64, 1),
  ('uastc_stress_alpha', 64, 64, 1),
];

/// `g_uastc_huff_modes` in the reference transcoder: a block's low seven bits,
/// to its mode. Copied here rather than imported so that the coverage test
/// below does not take the decoder's word for which modes it was shown.
const List<int> _huffModes = <int>[
  11, 0, 10, 3, 11, 15, 12, 7, 11, 18, 10, 5, 11, 14, 12, 9, //
  11, 0, 10, 4, 11, 16, 12, 8, 11, 18, 10, 6, 11, 2, 12, 13,
  11, 0, 10, 3, 11, 17, 12, 7, 11, 18, 10, 5, 11, 14, 12, 9,
  11, 0, 10, 4, 11, 1, 12, 8, 11, 18, 10, 6, 11, 2, 12, 13,
  11, 0, 10, 3, 11, 19, 12, 7, 11, 18, 10, 5, 11, 14, 12, 9,
  11, 0, 10, 4, 11, 16, 12, 8, 11, 18, 10, 6, 11, 2, 12, 13,
  11, 0, 10, 3, 11, 17, 12, 7, 11, 18, 10, 5, 11, 14, 12, 9,
  11, 0, 10, 4, 11, 1, 12, 8, 11, 18, 10, 6, 11, 2, 12, 13,
];

/// The raw blocks of every level of an *uncompressed* UASTC file.
Iterable<Uint8List> _blocksOf(Uint8List ktx2) sync* {
  final view = ByteData.sublistView(ktx2);
  final levelCount = view.getUint32(
    kKtx2HeaderOffset + Ktx2HeaderField.levelCount,
    Endian.little,
  );
  for (var level = 0; level < levelCount; level++) {
    final entry = kKtx2LevelIndexOffset + level * kKtx2LevelIndexEntryBytes;
    final offset = view.getUint32(entry, Endian.little);
    final length = view.getUint32(entry + 8, Endian.little);
    for (var at = offset; at < offset + length; at += 16) {
      yield Uint8List.sublistView(ktx2, at, at + 16);
    }
  }
}

void main() {
  for (final (name, width, height, levels) in _files) {
    test('$name unpacks to what basisu unpacks, byte for byte', () {
      final texture = Ktx2Texture.parse(_fixture('$name.ktx2'));
      expect(texture.pixelWidth, width);
      expect(texture.pixelHeight, height);
      expect(texture.vkFormat, VkFormat.r8g8b8a8UNorm);
      expect(texture.levels, hasLength(levels));

      for (var level = 0; level < levels; level++) {
        final expected = _fixture('${name}_level_$level.rgba');
        final actual = Uint8List.sublistView(texture.levels[level]);
        expect(actual.length, expected.length, reason: 'level $level size');

        // The first difference, as a pixel and a block, rather than two
        // sixteen-kilobyte lists: which block is wrong is the whole diagnosis,
        // since its first byte says which mode it is.
        final levelWidth = width >> level < 1 ? 1 : width >> level;
        final firstWrong = Iterable<int>.generate(
          expected.length,
        ).where((i) => actual[i] != expected[i]).firstOrNull;
        expect(
          firstWrong,
          isNull,
          reason: firstWrong == null
              ? ''
              : 'level $level, pixel '
                    '(${firstWrong ~/ 4 % levelWidth}, '
                    '${firstWrong ~/ 4 ~/ levelWidth}) channel '
                    '${firstWrong % 4}: ${actual[firstWrong]} here, '
                    '${expected[firstWrong]} from basisu',
        );
      }
    });
  }

  test('between them the fixtures hold every one of the nineteen modes', () {
    // Byte-exactness above means nothing for a mode no fixture contains, and a
    // re-encoded fixture could quietly stop containing one. Zstandard hides
    // the blocks, so the photograph sits this out; the other four cover the
    // modes between them and the photograph covers the supercompression.
    final seen = <int>{
      for (final (name, _, _, _) in _files)
        if (!name.endsWith('_zstd'))
          for (final block in _blocksOf(_fixture('$name.ktx2')))
            _huffModes[block[0] & 127],
    };
    expect(
      seen,
      containsAll(<int>[for (var mode = 0; mode < 19; mode++) mode]),
    );
  });

  test('a glTF that ships only a UASTC texture opens, and the texture is '
      'the one basisu unpacks', () async {
    // What `gltf-transform uastc` leaves behind: a texture with no core
    // `source`, a `KHR_texture_basisu` one, the extension named as required,
    // and an `image/ktx2` image. The loader has carried such an image through
    // since ETC1S was read; what changed is that the bytes it carries now
    // decode, so the material keeps its texture instead of a warning.
    final ktx2 = _fixture('uastc_alpha_mips.ktx2');
    final asset = await GltfLoader().load(
      GlbContainer.encode(<String, Object?>{
        'asset': <String, Object?>{'version': '2.0'},
        'extensionsUsed': <Object?>['KHR_texture_basisu'],
        'extensionsRequired': <Object?>['KHR_texture_basisu'],
        'buffers': <Object?>[
          <String, Object?>{'byteLength': ktx2.length},
        ],
        'bufferViews': <Object?>[
          <String, Object?>{'buffer': 0, 'byteLength': ktx2.length},
        ],
        'images': <Object?>[
          <String, Object?>{'bufferView': 0, 'mimeType': 'image/ktx2'},
        ],
        'textures': <Object?>[
          <String, Object?>{
            'extensions': <String, Object?>{
              'KHR_texture_basisu': <String, Object?>{'source': 0},
            },
          },
        ],
        'materials': <Object?>[
          <String, Object?>{
            'pbrMetallicRoughness': <String, Object?>{
              'baseColorTexture': <String, Object?>{'index': 0},
            },
          },
        ],
      }, binary: ktx2),
    );

    expect(asset.warnings, isEmpty);
    final binding = asset.materials.single.baseColorTexture;
    expect(binding, isNotNull);
    final image = asset.images[binding!.imageIndex];

    final texture = Ktx2Texture.parse(image.bytes);
    expect(texture.levels, hasLength(7));
    expect(
      Uint8List.sublistView(texture.levels.first),
      orderedEquals(_fixture('uastc_alpha_mips_level_0.rgba')),
    );
  });

  group('what is refused, and the message says which', () {
    test('the reserved twentieth mode', () {
      // 0x45 in the low seven bits is the one Huffman code that is not a
      // mode — the format keeps it for later. Reading it as any of the others
      // would decode a block of noise without complaint.
      final bytes = Uint8List.fromList(_fixture('uastc_stress.ktx2'));
      final firstBlock = ByteData.sublistView(
        bytes,
      ).getUint32(kKtx2LevelIndexOffset, Endian.little);
      bytes[firstBlock] = 0x45;
      expect(
        () => Ktx2Texture.parse(bytes),
        throwsA(
          isA<Ktx2FormatException>().having(
            (e) => e.message,
            'message',
            contains('mode 19'),
          ),
        ),
      );
    });

    test('a level shorter than its blocks', () {
      final bytes = Uint8List.fromList(_fixture('uastc_stress.ktx2'));
      // Level 0's byteLength, in the level index: claim one block fewer.
      ByteData.sublistView(bytes).setUint32(
        kKtx2LevelIndexOffset + 8,
        (64 ~/ 4) * (64 ~/ 4) * 16 - 16,
        Endian.little,
      );
      expect(
        () => Ktx2Texture.parse(bytes),
        throwsA(
          isA<Ktx2FormatException>().having(
            (e) => e.message,
            'message',
            contains('16 x 16 blocks'),
          ),
        ),
      );
    });

    test('UASTC HDR, by name', () {
      // The colour model byte of the data format descriptor: 166 is UASTC LDR
      // and 167 is the HDR format the same encoder now writes, whose blocks
      // are a different thing entirely.
      final bytes = Uint8List.fromList(_fixture('uastc_stress.ktx2'));
      final dfd = ByteData.sublistView(bytes).getUint32(
        kKtx2IndexOffset + Ktx2IndexField.dfdByteOffset,
        Endian.little,
      );
      expect(bytes[dfd + 12], Ktx2ColorModel.uastc);
      bytes[dfd + 12] = 167;
      expect(
        () => Ktx2Texture.parse(bytes),
        throwsA(
          isA<Ktx2FormatException>().having(
            (e) => e.message,
            'message',
            contains('UASTC HDR 4x4'),
          ),
        ),
      );
    });
  });
}
