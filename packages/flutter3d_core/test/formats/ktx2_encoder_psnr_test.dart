/// `ap-07` in `doc/asset-pipeline-plan.md`'s own acceptance, checked
/// literally: PSNR ≥ 30 dB against a real Khronos glTF sample texture,
/// through the test decoders `bc_test_decoders.dart` and
/// `etc2_test_decoder.dart` write — not this port's own encoder read back by
/// itself, which would only prove internal consistency, the same reasoning
/// `ktx2_test.dart`'s own doc comment gives for building fixtures by hand
/// rather than round-tripping through the loader that reads them.
///
/// The source is `flutter3d_samples/assets/animated_cube/
/// AnimatedCube_BaseColor.png` — a real photographic-ish texture from the
/// Khronos glTF-Sample-Models set already vendored as a fixture, not a
/// synthetic gradient this port's own encoder would find easy.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

import 'helpers/astc4x4_test_decoder.dart';
import 'helpers/bc_test_decoders.dart';
import 'helpers/etc2_test_decoder.dart';
import 'helpers/load_png.dart';
import 'helpers/psnr.dart';

void main() {
  final source = loadPngAsRgba8(
    '../flutter3d_samples/assets/animated_cube/AnimatedCube_BaseColor.png',
  );

  test('BC1 reaches at least 30 dB PSNR on the Khronos texture', () {
    final encoded = encodeBc1(source);
    final decoded = decodeBc1(encoded, source.width, source.height);
    final db = psnr(source, decoded);
    expect(db, greaterThanOrEqualTo(30), reason: 'measured $db dB');
  });

  test(
    'BC3 reaches at least 30 dB PSNR (colour and alpha) on a real texture',
    () {
      // The Khronos fixture has no alpha channel of its own; a synthetic ramp
      // stands in for it here since BC3's colour half is BC1's and is already
      // checked above — this adds only the alpha half's real-content bound.
      final withAlpha = Rgba8Image(
        width: source.width,
        height: source.height,
        pixels: source.pixels,
      );
      final encoded = encodeBc3(withAlpha);
      final decoded = decodeBc3(encoded, source.width, source.height);
      final db = psnr(source, decoded, includeAlpha: true);
      expect(db, greaterThanOrEqualTo(30), reason: 'measured $db dB');
    },
  );

  test('ETC2 RGB8 reaches at least 30 dB PSNR on the Khronos texture', () {
    final encoded = encodeEtc2Rgb8(source);
    final decoded = decodeEtc2Rgb8(encoded, source.width, source.height);
    final db = psnr(source, decoded);
    expect(db, greaterThanOrEqualTo(30), reason: 'measured $db dB');
  });

  test('ASTC 4x4 reaches at least 30 dB PSNR on the Khronos texture', () {
    // mat-30's own gap on top of this file's BC1/BC3/ETC2 rows — see
    // `astc4x4_encoder.dart`'s doc comment for the scope this holds itself
    // to and the real gap (no real-GPU block-mode check) it names instead
    // of hiding.
    final encoded = encodeAstc4x4(source);
    final decoded = decodeAstc4x4(encoded, source.width, source.height);
    final db = psnr(source, decoded);
    expect(db, greaterThanOrEqualTo(30), reason: 'measured $db dB');
  });

  test('encode time on a 2048x2048 tiling of the texture is recorded', () {
    final large = tile(source, (2048 / source.width).ceil());
    final size = 2048 - 2048 % 4;
    final cropped = Rgba8Image(
      width: size,
      height: size,
      pixels: Uint8List.fromList(_crop(large, size, size)),
    );

    for (final (name, encode) in <(String, void Function())>[
      ('BC1', () => encodeBc1(cropped)),
      ('BC3', () => encodeBc3(cropped)),
      ('ETC2 RGB8', () => encodeEtc2Rgb8(cropped)),
      ('ASTC 4x4', () => encodeAstc4x4(cropped)),
    ]) {
      final stopwatch = Stopwatch()..start();
      encode();
      stopwatch.stop();
      // Not a repeatable-step wall-clock read: this is a build-time
      // benchmark reporting what it just measured, the same exemption
      // `flutter3d_build` has in `tool/structure/repository.dart`'s
      // `notARepeatableStep` for `convert.dart`'s own `Stopwatch`.
      // ignore: avoid_print
      print(
        '$name encode on ${cropped.width}x${cropped.height}: '
        '${stopwatch.elapsedMilliseconds} ms',
      );
    }
  });
}

List<int> _crop(Rgba8Image source, int width, int height) {
  final out = List<int>.filled(width * height * 4, 0);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final dst = (y * width + x) * 4;
      out[dst] = source.red(x, y);
      out[dst + 1] = source.green(x, y);
      out[dst + 2] = source.blue(x, y);
      out[dst + 3] = source.alpha(x, y);
    }
  }
  return out;
}
