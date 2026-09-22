/// Proves the ASTC 4×4 encoder self-consistent — decoded here, not by a real
/// GPU. `astc4x4_encoder.dart`'s own doc comment names the real gap this
/// cannot replace: nothing here checks the block against a real GPU's own
/// ASTC block-mode decode, the way `flutter3d_conformance` already does for
/// BC1/BC3/ETC2. Mirrors `bc_encoder_test.dart` and `etc2_encoder_test.dart`
/// in shape and intent.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

import 'helpers/astc4x4_test_decoder.dart';

Rgba8Image _solid(int r, int g, int b) => Rgba8Image(
  width: 4,
  height: 4,
  pixels: Uint8List.fromList(
    List<int>.generate(64, (i) {
      switch (i % 4) {
        case 0:
          return r;
        case 1:
          return g;
        case 2:
          return b;
        default:
          return 255;
      }
    }),
  ),
);

/// A 4×4 block ramping red left to right, green and blue held constant — a
/// single axis of variation, the same shape `bc_encoder_test.dart`'s own
/// `_ramp()` uses for BC1's red channel, so this checks the sixteen-level
/// weight quantization in isolation from the two-dimensional endpoint-fit
/// error a ramp varying on more than one axis at once would also add.
Rgba8Image _ramp() {
  final pixels = Uint8List(64);
  for (var y = 0; y < 4; y++) {
    for (var x = 0; x < 4; x++) {
      final at = (y * 4 + x) * 4;
      pixels[at] = (x * 255 / 3).round();
      pixels[at + 1] = 40;
      pixels[at + 2] = 200;
      pixels[at + 3] = 255;
    }
  }
  return Rgba8Image(width: 4, height: 4, pixels: pixels);
}

void main() {
  test('a block is exactly 16 bytes', () {
    expect(
      encodeAstc4x4Block(List.generate(16, (_) => (0, 0, 0, 255))),
      hasLength(16),
    );
  });

  test('a solid block round-trips to the same colour', () {
    final source = _solid(136, 68, 204);
    final decoded = decodeAstc4x4(encodeAstc4x4(source), 4, 4);
    for (var i = 0; i < 16; i++) {
      expect(decoded.red(i % 4, i ~/ 4), closeTo(136, 4));
      expect(decoded.green(i % 4, i ~/ 4), closeTo(68, 4));
      expect(decoded.blue(i % 4, i ~/ 4), closeTo(204, 4));
    }
  });

  test('a ramp decodes within one weight step of the source', () {
    final source = _ramp();
    final decoded = decodeAstc4x4(encodeAstc4x4(source), 4, 4);
    for (var y = 0; y < 4; y++) {
      for (var x = 0; x < 4; x++) {
        // Sixteen independent weight levels across a 0-255 red ramp: roughly
        // 17 per step, well inside BC1's own four-level-palette tolerance of
        // 90 for the same shape of ramp.
        expect(
          (decoded.red(x, y) - source.red(x, y)).abs(),
          lessThan(20),
          reason: 'pixel ($x, $y)',
        );
      }
    }
  });

  test('an 8x8 image encodes as four independent blocks', () {
    final pixels = Uint8List(8 * 8 * 4);
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        final at = (y * 8 + x) * 4;
        final quadrant = (x >= 4 ? 1 : 0) + (y >= 4 ? 2 : 0);
        final colors = <(int, int, int)>[
          (255, 0, 0),
          (0, 255, 0),
          (0, 0, 255),
          (255, 255, 0),
        ];
        final (r, g, b) = colors[quadrant];
        pixels[at] = r;
        pixels[at + 1] = g;
        pixels[at + 2] = b;
        pixels[at + 3] = 255;
      }
    }
    final source = Rgba8Image(width: 8, height: 8, pixels: pixels);
    final encoded = encodeAstc4x4(source);
    expect(encoded, hasLength(4 * 16));
    final decoded = decodeAstc4x4(encoded, 8, 8);
    expect(decoded.red(0, 0), closeTo(255, 4));
    expect(decoded.green(0, 0), closeTo(0, 4));
    expect(decoded.green(7, 0), closeTo(255, 4));
    expect(decoded.blue(0, 7), closeTo(255, 4));
  });
}
