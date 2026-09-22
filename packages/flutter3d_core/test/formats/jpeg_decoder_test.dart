/// `decodeJpeg`: `mat-09n`'s pure-Dart baseline-JPEG half.
///
/// **The fixtures are real JPEGs, not hand-built ones** — unlike
/// `png_decoder_test.dart`, which can construct a byte-exact PNG straight
/// from the specification's own filter formulas, a JPEG's entropy-coded
/// bitstream is not something to hand-assemble by hand without effectively
/// writing a second encoder. `test/fixtures/*.jpg` are real files (checked
/// into this package), and what this file checks is dimensions, specific
/// pixel values sanity-checked against what each fixture was built from,
/// and the refusal contract — the cross-check against another decoder's
/// own output (`dart:ui`) belongs to the app-level test, per
/// `png_decoder_test.dart`'s own doc comment about `mcp-04n`.
///
///     dart test test/jpeg_decoder_test.dart
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

Uint8List _fixture(String name) =>
    File('test/formats/fixtures/$name').readAsBytesSync();

void main() {
  group('dimensions', () {
    test('solid_8x8.jpg is 8x8 — one exact MCU', () {
      final decoded = decodeJpeg(_fixture('solid_8x8.jpg'));
      expect(decoded, isNotNull);
      expect(decoded!.width, 8);
      expect(decoded.height, 8);
      expect(decoded.rgba.length, 8 * 8 * 4);
    });

    test('gradient_444.jpg is 16x16', () {
      final decoded = decodeJpeg(_fixture('gradient_444.jpg'));
      expect(decoded, isNotNull);
      expect(decoded!.width, 16);
      expect(decoded.height, 16);
    });

    test('gradient_420.jpg is 16x16', () {
      final decoded = decodeJpeg(_fixture('gradient_420.jpg'));
      expect(decoded, isNotNull);
      expect(decoded!.width, 16);
      expect(decoded.height, 16);
    });

    test('gray_16x16.jpg is 16x16, single component', () {
      final decoded = decodeJpeg(_fixture('gray_16x16.jpg'));
      expect(decoded, isNotNull);
      expect(decoded!.width, 16);
      expect(decoded.height, 16);
    });
  });

  group('known pixel values, within lossy-JPEG rounding', () {
    // solid_8x8.jpg was encoded at quality 100 from a flat (200, 100, 50)
    // fill — one MCU, no block boundary for an error to hide across.
    test('solid_8x8.jpg decodes back to its own flat colour', () {
      final decoded = decodeJpeg(_fixture('solid_8x8.jpg'))!;
      for (var i = 0; i < decoded.rgba.length; i += 4) {
        expect(decoded.rgba[i], closeTo(200, 3));
        expect(decoded.rgba[i + 1], closeTo(100, 3));
        expect(decoded.rgba[i + 2], closeTo(50, 3));
        expect(decoded.rgba[i + 3], 255);
      }
    });

    // gradient_444.jpg's own source: r = x*255/15, g = y*255/15,
    // b = (x+y)*255/30 — so (0,0) is black and every corner is a known,
    // specific colour rather than a shape only "looks like a gradient".
    test('gradient_444.jpg — corner colours match the source gradient', () {
      final decoded = decodeJpeg(_fixture('gradient_444.jpg'))!;
      final w = decoded.width;
      int at(int x, int y, int channel) =>
          decoded.rgba[(y * w + x) * 4 + channel];

      // (0, 0): r=0, g=0, b=0.
      expect(at(0, 0, 0), closeTo(0, 4));
      expect(at(0, 0, 1), closeTo(0, 4));
      expect(at(0, 0, 2), closeTo(0, 4));

      // (15, 0): r=255, g=0, b=127 or 128.
      expect(at(15, 0, 0), closeTo(255, 4));
      expect(at(15, 0, 1), closeTo(0, 4));
      expect(at(15, 0, 2), closeTo(128, 4));

      // (0, 15): r=0, g=255, b=127 or 128.
      expect(at(0, 15, 0), closeTo(0, 4));
      expect(at(0, 15, 1), closeTo(255, 4));
      expect(at(0, 15, 2), closeTo(128, 4));
    });
  });

  group('truncated or malformed files refuse by value', () {
    test('too short to hold even a signature', () {
      expect(decodeJpeg(Uint8List.fromList(<int>[0xFF, 0xD8])), isNull);
    });

    test('missing the SOI marker entirely', () {
      final bytes = _fixture('solid_8x8.jpg');
      final wrongSignature = Uint8List.fromList(bytes);
      wrongSignature[0] = 0x00;
      expect(decodeJpeg(wrongSignature), isNull);
    });

    test('cut off partway through the entropy-coded scan', () {
      final bytes = _fixture('gradient_444.jpg');
      final truncated = Uint8List.sublistView(bytes, 0, bytes.length - 20);
      expect(decodeJpeg(truncated), isNull);
    });

    test('cut off before any SOF/scan at all', () {
      final bytes = _fixture('gradient_444.jpg');
      final truncated = Uint8List.sublistView(bytes, 0, 4);
      expect(decodeJpeg(truncated), isNull);
    });

    test('an empty byte list', () {
      expect(decodeJpeg(Uint8List(0)), isNull);
    });
  });
}
