/// The ASTC this repository writes is ASTC — `gfx-88n`.
///
///     dart test test/formats/astc_conformance_test.dart
///
/// **The test that was missing, and its absence had a consequence.** The
/// encoder and the decoder beside it were written from one reading of the block
/// layout, so they agreed with each other and with nothing else; fed a file
/// this encoder wrote, ARM's own `astcenc` returned `(255, 0, 255)` for every
/// block — ASTC's error colour — because eleven zero bits is a reserved
/// encoding rather than a 4×4 weight grid. A round trip through our own decoder
/// could never have found that.
///
/// So this test does not round-trip. It pins two committed artefacts:
///
///   * `gradient.astc` — the exact bytes this encoder produced for a gradient
///     the test regenerates, in the `.astc` container, which is what `astcenc`
///     was handed;
///   * `gradient_astcenc_decoded.rgba` — what `astcenc` gave back.
///
/// Regenerating the second one has a trap in it that cost a run: `astcenc -dl`
/// writes a TGA, and its TGA is 32-bit BGRA, run-length encoded, with the
/// origin bit clear, so the first row in the file is the bottom one. Kept in
/// that order the comparison below fails at 252 on a gradient whose whole
/// quantisation budget is 12.
///
/// Encoding the same gradient must produce those bytes, and that decode must be
/// close to the source. The first half says the encoder has not drifted from
/// what a real decoder was shown; the second says what the real decoder made of
/// it was the picture. Neither can be satisfied by our own decoder agreeing
/// with our own encoder, which is the property the previous arrangement lacked.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

import 'helpers/astc4x4_test_decoder.dart';

const String _fixtures = 'test/formats/fixtures/astc';
const int _size = 64;

/// The gradient both fixtures were made from.
Rgba8Image _gradient() {
  final pixels = Uint8List(_size * _size * 4);
  for (var y = 0; y < _size; y++) {
    for (var x = 0; x < _size; x++) {
      final i = (y * _size + x) * 4;
      pixels[i] = (x * 4) & 255;
      pixels[i + 1] = (y * 4) & 255;
      pixels[i + 2] = ((x + y) * 2) & 255;
      pixels[i + 3] = 255;
    }
  }
  return Rgba8Image(width: _size, height: _size, pixels: pixels);
}

void main() {
  test('the encoder still writes the bytes the real decoder was shown', () {
    final blocks = encodeAstc4x4(_gradient());
    final container = File('$_fixtures/gradient.astc').readAsBytesSync();
    // The container's own sixteen-byte header, then the blocks.
    expect(container.length, 16 + blocks.length);
    expect(
      Uint8List.sublistView(container, 16),
      orderedEquals(blocks),
      reason: 'the encoder has drifted from the bytes astcenc accepted',
    );
  });

  test('the block mode is a real one, not eleven zeros', () {
    // The single bit pattern that made the difference, checked directly so that
    // a change to it fails here with its own message rather than as a diff of
    // four thousand bytes. `0x53` is one plane, a 4×4 weight grid and eight
    // weight levels, read out of `decode_block_mode_2d` in the reference
    // encoder.
    final blocks = encodeAstc4x4(_gradient());
    final mode = blocks[0] | ((blocks[1] & 0x07) << 8);
    expect(mode, 0x53);
  });

  test('what astcenc made of those bytes is the picture', () {
    final decoded = File(
      '$_fixtures/gradient_astcenc_decoded.rgba',
    ).readAsBytesSync();
    final source = _gradient().pixels;
    expect(decoded.length, source.length);

    var worst = 0;
    var total = 0.0;
    for (var i = 0; i < source.length; i++) {
      if (i % 4 == 3) continue; // alpha is opaque throughout
      final error = (decoded[i] - source[i]).abs();
      worst = math.max(worst, error);
      total += error * error;
    }
    final rmse = math.sqrt(total / (source.length * 3 / 4));

    // Eight weight levels along one line through a block, so a gradient with
    // three channels moving at once cannot be exact. What the bound says is
    // that it is *compression* error and not a misread block: magenta against
    // this gradient would be an error of 255 and an RMSE near 150.
    expect(worst, lessThanOrEqualTo(12), reason: 'worst channel error $worst');
    expect(rmse, lessThan(4.0), reason: 'rmse $rmse');
  });

  test('our own decoder agrees with astcenc on the same bytes', () {
    // Now worth asserting, where before it was the only thing asserted. The
    // test decoder exists so other tests can look inside a block; this is what
    // says it is looking at the same block a GPU would.
    final blocks = encodeAstc4x4(_gradient());
    final ours = decodeAstc4x4(blocks, _size, _size).pixels;
    final theirs = File(
      '$_fixtures/gradient_astcenc_decoded.rgba',
    ).readAsBytesSync();

    var worst = 0;
    for (var i = 0; i < ours.length; i++) {
      worst = math.max(worst, (ours[i] - theirs[i]).abs());
    }
    // Not zero: the two interpolate a weight to a colour by slightly different
    // arithmetic — ours is a plain lerp, ASTC's is a fixed-point blend through
    // a 0..64 scale. Close enough that they are reading the same weights and
    // the same endpoints, which is what this checks.
    expect(
      worst,
      lessThanOrEqualTo(4),
      reason: 'worst channel difference $worst',
    );
  });
}
