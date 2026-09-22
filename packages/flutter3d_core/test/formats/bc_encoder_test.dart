/// Proves the BC1/BC3 encoders against a decoder that reads exactly the
/// layout `flutter3d_conformance`'s `checkCompressedTextureSamples` has
/// already run on real Impeller and WebGL2 hardware — a solid block here
/// checks the same bytes that check does, and the gradient blocks check the
/// general index-packing that check's solid block cannot.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

import 'helpers/bc_test_decoders.dart';

Rgba8Image _solid(int r, int g, int b, int a) => Rgba8Image(
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
          return a;
      }
    }),
  ),
);

/// A 4×4 block ramping red left to right, alpha top to bottom — enough
/// variation that every one of BC1's four palette entries and every one of
/// BC3's eight alpha levels can be the nearest choice for some texel.
Rgba8Image _ramp() {
  final pixels = Uint8List(64);
  for (var y = 0; y < 4; y++) {
    for (var x = 0; x < 4; x++) {
      final at = (y * 4 + x) * 4;
      pixels[at] = (x * 255 / 3).round();
      pixels[at + 1] = 40;
      pixels[at + 2] = 200;
      pixels[at + 3] = (y * 255 / 3).round();
    }
  }
  return Rgba8Image(width: 4, height: 4, pixels: pixels);
}

void main() {
  group('BC1', () {
    test('a solid opaque block round-trips to the same colour', () {
      final source = _solid(136, 68, 204, 255);
      final encoded = encodeBc1(source);
      final decoded = decodeBc1(encoded, 4, 4);
      for (var i = 0; i < 16; i++) {
        expect(decoded.red(i % 4, i ~/ 4), closeTo(136, 4));
        expect(decoded.green(i % 4, i ~/ 4), closeTo(68, 4));
        expect(decoded.blue(i % 4, i ~/ 4), closeTo(204, 4));
      }
    });

    test('a solid block is stored four-color: pack0 strictly above pack1', () {
      final encoded = encodeBc1(_solid(100, 100, 100, 255));
      final view = ByteData.sublistView(encoded);
      final pack0 = view.getUint16(0, Endian.little);
      final pack1 = view.getUint16(2, Endian.little);
      expect(
        pack0,
        greaterThan(pack1),
        reason:
            'a tied endpoint would read as three-color-plus-transparent, and '
            'this block has no alpha to be transparent with',
      );
    });

    test('a ramp decodes within one BC1 palette step of the source', () {
      final source = _ramp();
      final decoded = decodeBc1(encodeBc1(source), 4, 4);
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 4; x++) {
          // A four-level 565 palette across a 0-255 red ramp: roughly 85 per
          // step is the worst any texel should see.
          expect(
            (decoded.red(x, y) - source.red(x, y)).abs(),
            lessThan(90),
            reason: 'pixel ($x, $y)',
          );
        }
      }
    });
  });

  group('BC3', () {
    test('a solid block round-trips colour and alpha', () {
      final source = _solid(10, 200, 30, 128);
      final decoded = decodeBc3(encodeBc3(source), 4, 4);
      for (var i = 0; i < 16; i++) {
        final x = i % 4, y = i ~/ 4;
        expect(decoded.red(x, y), closeTo(10, 4));
        expect(decoded.green(x, y), closeTo(200, 4));
        expect(decoded.blue(x, y), closeTo(30, 4));
        expect(decoded.alpha(x, y), closeTo(128, 2));
      }
    });

    test(
      'a flat-alpha block still writes strictly ordered alpha endpoints',
      () {
        final encoded = encodeBc3(_solid(0, 0, 0, 255));
        expect(
          encoded[0],
          greaterThan(encoded[1]),
          reason:
              'a tied alpha endpoint would read as the punch-through mode this '
              'encoder never writes indices for',
        );
      },
    );

    test('an alpha ramp decodes within one BC3 level of the source', () {
      final source = _ramp();
      final decoded = decodeBc3(encodeBc3(source), 4, 4);
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 4; x++) {
          // Eight alpha levels across a 0-255 ramp: roughly 36 per step.
          expect(
            (decoded.alpha(x, y) - source.alpha(x, y)).abs(),
            lessThan(40),
            reason: 'pixel ($x, $y)',
          );
        }
      }
    });
  });
}
