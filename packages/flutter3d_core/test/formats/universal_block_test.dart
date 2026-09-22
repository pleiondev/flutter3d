/// One cooked texture, four GPU formats — `gfx-83n`.
///
///     dart test test/formats/universal_block_test.dart
///
/// **The row's acceptance, checked literally.** "One cooked asset uploads as
/// BC on a desktop and as ASTC or ETC2 on a phone, from the same bytes": the
/// tests below cook the Khronos sample texture *once* and then transcode that
/// one buffer to each target, measuring each against the source through the
/// same independent decoders `ktx2_encoder_psnr_test.dart` uses — not through
/// this package's own reader, which would only prove the intermediate is
/// self-consistent.
///
/// The bound is the same 30 dB `ap-07` set for the direct encoders, and it is
/// the interesting number: an intermediate that has to survive being turned
/// into three different formats is allowed to cost something, and this says
/// how much.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

import 'helpers/astc4x4_test_decoder.dart';
import 'helpers/bc_test_decoders.dart';
import 'helpers/etc2_test_decoder.dart';
import 'helpers/load_png.dart';
import 'helpers/psnr.dart';

/// The same image with an alpha ramp across it, for the one target that keeps
/// alpha.
Rgba8Image _withAlphaRamp(Rgba8Image source) {
  final pixels = Uint8List.fromList(source.pixels);
  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      pixels[(y * source.width + x) * 4 + 3] = (x * 255) ~/ (source.width - 1);
    }
  }
  return Rgba8Image(width: source.width, height: source.height, pixels: pixels);
}

void main() {
  final source = loadPngAsRgba8(
    '../flutter3d_samples/assets/animated_cube/AnimatedCube_BaseColor.png',
  );
  final cooked = encodeUniversalBlocks(source);

  test('the cooked file is twenty bytes a block', () {
    expect(cooked.length, (source.width ~/ 4) * (source.height ~/ 4) * 20);
  });

  group('the same cooked bytes reach 30 dB as', () {
    Rgba8Image transcode(
      UniversalTarget target,
      Rgba8Image Function(Uint8List, int, int) decode,
    ) => decode(
      transcodeUniversal(
        cooked,
        target,
        width: source.width,
        height: source.height,
      ),
      source.width,
      source.height,
    );

    test('BC1', () {
      final db = psnr(source, transcode(UniversalTarget.bc1, decodeBc1));
      expect(db, greaterThanOrEqualTo(30), reason: 'measured $db dB');
    });

    test('ASTC 4x4', () {
      final db = psnr(
        source,
        transcode(UniversalTarget.astc4x4, decodeAstc4x4),
      );
      expect(db, greaterThanOrEqualTo(30), reason: 'measured $db dB');
    });

    test('ETC2 RGB8', () {
      final db = psnr(
        source,
        transcode(UniversalTarget.etc2Rgb8, decodeEtc2Rgb8),
      );
      expect(db, greaterThanOrEqualTo(30), reason: 'measured $db dB');
    });
  });

  test('alpha survives the BC3 leg', () {
    final withAlpha = _withAlphaRamp(source);
    final bytes = transcodeUniversal(
      encodeUniversalBlocks(withAlpha),
      UniversalTarget.bc3,
      width: withAlpha.width,
      height: withAlpha.height,
    );
    final decoded = decodeBc3(bytes, withAlpha.width, withAlpha.height);
    final db = psnr(withAlpha, decoded, includeAlpha: true);
    expect(db, greaterThanOrEqualTo(30), reason: 'measured $db dB');
  });

  test('the RGBA8 leg is the block decoded, exactly', () {
    // The fallback for a device that samples no block format. Nothing is
    // requantised on this leg, so it is the one where "the same bytes" can be
    // checked as equality rather than as a bound — and it pins what the other
    // three are each an approximation *of*.
    final bytes = transcodeUniversal(
      cooked,
      UniversalTarget.rgba8,
      width: source.width,
      height: source.height,
    );
    expect(bytes.length, source.width * source.height * 4);

    final blocksX = source.width ~/ 4;
    for (final block in <int>[0, 1, blocksX, blocksX * 3 + 7]) {
      final texels = decodeUniversalBlock(cooked, block);
      final x0 = (block % blocksX) * 4;
      final y0 = (block ~/ blocksX) * 4;
      for (var i = 0; i < 16; i++) {
        final at = ((y0 + i ~/ 4) * source.width + x0 + i % 4) * 4;
        expect(
          (bytes[at], bytes[at + 1], bytes[at + 2], bytes[at + 3]),
          texels[i],
          reason: 'block $block texel $i',
        );
      }
    }
  });

  test('a flat block survives every leg', () {
    // The case where the endpoint fit degenerates: both endpoints land on the
    // same pixel, so the weights mean nothing and each format's own
    // endpoint-ordering rule — BC1's four-colour tie nudge, ASTC's sum
    // comparison — is the only thing deciding what comes back. A block that
    // decoded as anything but the colour it was given would say one of those
    // rules is being read the wrong way round.
    final flat = Rgba8Image(
      width: 4,
      height: 4,
      pixels: Uint8List.fromList(
        List<int>.generate(64, (i) => <int>[37, 142, 200, 255][i % 4]),
      ),
    );
    final blocks = encodeUniversalBlocks(flat);

    for (final (target, decode)
        in <(UniversalTarget, Rgba8Image Function(Uint8List, int, int))>[
          (UniversalTarget.bc1, decodeBc1),
          (UniversalTarget.astc4x4, decodeAstc4x4),
          (UniversalTarget.etc2Rgb8, decodeEtc2Rgb8),
        ]) {
      final decoded = decode(
        transcodeUniversal(blocks, target, width: 4, height: 4),
        4,
        4,
      );
      for (var i = 0; i < 16; i++) {
        final x = i % 4, y = i ~/ 4;
        expect(
          decoded.red(x, y),
          closeTo(37, 8),
          reason: '${target.name} texel $i red',
        );
        expect(
          decoded.green(x, y),
          closeTo(142, 8),
          reason: '${target.name} texel $i green',
        );
        expect(
          decoded.blue(x, y),
          closeTo(200, 8),
          reason: '${target.name} texel $i blue',
        );
      }
    }
  });

  group('what the container says, and what it refuses', () {
    Uint8List file({required bool hasAlpha}) => writeKtx2(
      vkFormat: VkFormat.undefined,
      pixelWidth: source.width,
      pixelHeight: source.height,
      levels: <Uint8List>[cooked],
      keyValues: <String, String>{
        kUniversalBlockKey: hasAlpha ? kUniversalBlockRgba : kUniversalBlockRgb,
      },
    );

    test('a universal file announces itself and its alpha', () {
      expect(universalBlockFormat(file(hasAlpha: false))?.hasAlpha, isFalse);
      expect(universalBlockFormat(file(hasAlpha: true))?.hasAlpha, isTrue);
    });

    test('an ordinary KTX2 announces nothing', () {
      final plain = writeKtx2(
        vkFormat: VkFormat.bc1RgbaUNormBlock,
        pixelWidth: source.width,
        pixelHeight: source.height,
        levels: <Uint8List>[encodeBc1(source)],
      );
      expect(universalBlockFormat(plain), isNull);
    });

    test('each target parses back as its own vkFormat', () {
      for (final (target, vkFormat) in <(UniversalTarget, int)>[
        (UniversalTarget.bc1, VkFormat.bc1RgbaUNormBlock),
        (UniversalTarget.astc4x4, VkFormat.astc4x4UNormBlock),
        (UniversalTarget.etc2Rgb8, VkFormat.etc2R8g8b8UNormBlock),
        (UniversalTarget.rgba8, VkFormat.r8g8b8a8UNorm),
      ]) {
        final texture = Ktx2Texture.parse(
          file(hasAlpha: false),
          universalTarget: target,
        );
        expect(texture.vkFormat, vkFormat, reason: target.name);
        expect(texture.pixelWidth, source.width);
        expect(texture.levels, hasLength(1));
      }
    });

    test('a parse with no target is refused by name', () {
      expect(
        () => Ktx2Texture.parse(file(hasAlpha: false)),
        throwsA(
          isA<Ktx2FormatException>().having(
            (e) => e.message,
            'message',
            contains('universalTarget'),
          ),
        ),
      );
    });

    test('a target that would drop alpha is refused rather than taken', () {
      expect(
        () => Ktx2Texture.parse(
          file(hasAlpha: true),
          universalTarget: UniversalTarget.etc2Rgb8,
        ),
        throwsA(
          isA<Ktx2FormatException>().having(
            (e) => e.message,
            'message',
            contains('carries alpha'),
          ),
        ),
      );
    });
  });
}
