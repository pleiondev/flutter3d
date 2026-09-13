/// `decodePng`: `mat-09n`'s pure-Dart PNG half.
///
/// **Every expected pixel here is worked out by hand from the PNG
/// specification's own filter formulas**, not read back from another
/// decoder — this package has no `dart:ui` to cross-check against, and
/// that cross-check belongs to whichever app-layer test reads real
/// `test/goldens` fixtures, `mcp-04n`'s own row. What this file proves is
/// that the arithmetic in `png_decoder.dart` matches the specification's,
/// one filter type and one colour type at a time.
///
///     dart test test/png_decoder_test.dart
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:test/test.dart';

Uint8List _chunk(String type, List<int> data) {
  final out = BytesBuilder();
  out.add(
    (ByteData(4)..setUint32(0, data.length, Endian.big)).buffer.asUint8List(),
  );
  out.add(ascii.encode(type));
  out.add(data);
  out.add(const <int>[0, 0, 0, 0]); // CRC — this decoder does not read it
  return out.toBytes();
}

/// A minimal, valid PNG: signature, `IHDR`, an optional `PLTE`, one `IDAT`
/// holding [scanlines] — filter-type byte then row data, [height] of them —
/// compressed through `dart:io`'s own `ZLibCodec`, a different
/// implementation of the same RFC `zlibInflate` reads, and `IEND`.
Uint8List _png({
  required int width,
  required int height,
  required int bitDepth,
  required int colorType,
  required List<int> scanlines,
  List<int>? palette,
  bool interlace = false,
}) {
  final out = BytesBuilder();
  out.add(const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  final ihdr = ByteData(13)
    ..setUint32(0, width, Endian.big)
    ..setUint32(4, height, Endian.big)
    ..setUint8(8, bitDepth)
    ..setUint8(9, colorType)
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, interlace ? 1 : 0);
  out.add(_chunk('IHDR', ihdr.buffer.asUint8List()));
  if (palette != null) out.add(_chunk('PLTE', palette));
  out.add(_chunk('IDAT', ZLibCodec().encode(scanlines)));
  out.add(_chunk('IEND', const <int>[]));
  return out.toBytes();
}

/// One pixel's RGBA, for building the expected buffer without repeating
/// four `expect`s per pixel.
List<int> _rgba(int r, int g, int b, int a) => <int>[r, g, b, a];

void main() {
  group('colour types, filter type None', () {
    test('colour type 2 (RGB), 8-bit — a 2×2 image', () {
      final png = _png(
        width: 2,
        height: 2,
        bitDepth: 8,
        colorType: 2,
        scanlines: <int>[
          0, 255, 0, 0, 0, 255, 0, // row 0: red, green
          0, 0, 0, 255, 255, 255, 0, // row 1: blue, yellow
        ],
      );
      final decoded = decodePng(png);
      expect(decoded, isNotNull);
      expect(decoded!.width, 2);
      expect(decoded.height, 2);
      expect(decoded.rgba, <int>[
        ..._rgba(255, 0, 0, 255),
        ..._rgba(0, 255, 0, 255),
        ..._rgba(0, 0, 255, 255),
        ..._rgba(255, 255, 0, 255),
      ]);
    });

    test('colour type 6 (RGBA), 8-bit, real alpha', () {
      final png = _png(
        width: 2,
        height: 1,
        bitDepth: 8,
        colorType: 6,
        scanlines: <int>[0, 10, 20, 30, 128, 200, 210, 220, 0],
      );
      final decoded = decodePng(png);
      expect(decoded!.rgba, <int>[
        ..._rgba(10, 20, 30, 128),
        ..._rgba(200, 210, 220, 0),
      ]);
    });

    test('colour type 0 (grey), 8-bit', () {
      final png = _png(
        width: 3,
        height: 1,
        bitDepth: 8,
        colorType: 0,
        scanlines: <int>[0, 10, 128, 250],
      );
      final decoded = decodePng(png);
      expect(decoded!.rgba, <int>[
        ..._rgba(10, 10, 10, 255),
        ..._rgba(128, 128, 128, 255),
        ..._rgba(250, 250, 250, 255),
      ]);
    });

    test('colour type 4 (grey + alpha), 8-bit', () {
      final png = _png(
        width: 2,
        height: 1,
        bitDepth: 8,
        colorType: 4,
        scanlines: <int>[0, 100, 50, 200, 150],
      );
      final decoded = decodePng(png);
      expect(decoded!.rgba, <int>[
        ..._rgba(100, 100, 100, 50),
        ..._rgba(200, 200, 200, 150),
      ]);
    });

    test('colour type 2 (RGB), 16-bit — the high byte of each sample', () {
      // Mutation: read the low byte instead of the high one — every value
      // here has a distinct high and low byte, so that mistake changes
      // every channel of the answer.
      final png = _png(
        width: 1,
        height: 1,
        bitDepth: 16,
        colorType: 2,
        scanlines: <int>[0, 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC],
      );
      final decoded = decodePng(png);
      expect(decoded!.rgba, _rgba(0x12, 0x56, 0x9A, 255));
    });
  });

  group('the palette', () {
    test('8-bit indices', () {
      final palette = List<int>.filled(3 * 3, 0)
        ..setRange(0, 3, <int>[10, 20, 30])
        ..setRange(3, 6, <int>[40, 50, 60])
        ..setRange(6, 9, <int>[70, 80, 90]);
      final png = _png(
        width: 3,
        height: 1,
        bitDepth: 8,
        colorType: 3,
        palette: palette,
        scanlines: <int>[0, 2, 0, 1],
      );
      final decoded = decodePng(png);
      expect(decoded!.rgba, <int>[
        ..._rgba(70, 80, 90, 255),
        ..._rgba(10, 20, 30, 255),
        ..._rgba(40, 50, 60, 255),
      ]);
    });

    test('4-bit indices, two packed per byte, most significant nibble '
        'first', () {
      final palette = List<int>.filled(16 * 3, 0);
      palette.setRange(5 * 3, 5 * 3 + 3, <int>[100, 150, 200]);
      palette.setRange(10 * 3, 10 * 3 + 3, <int>[50, 60, 70]);
      // Mutation: unpack the low nibble first — this byte's two nibbles
      // (5 and 10) decode to two different, real palette entries either
      // way round, so a swap changes which pixel gets which colour rather
      // than silently matching.
      final png = _png(
        width: 2,
        height: 1,
        bitDepth: 4,
        colorType: 3,
        palette: palette,
        scanlines: <int>[0, (5 << 4) | 10],
      );
      final decoded = decodePng(png);
      expect(decoded!.rgba, <int>[
        ..._rgba(100, 150, 200, 255),
        ..._rgba(50, 60, 70, 255),
      ]);
    });

    test('1-bit indices, eight packed per byte', () {
      final palette = List<int>.filled(2 * 3, 0)
        ..setRange(3, 6, <int>[255, 255, 255]); // index 1 is white
      final png = _png(
        width: 8,
        height: 1,
        bitDepth: 1,
        colorType: 3,
        palette: palette,
        // 1,0,1,1,0,0,1,0 packed MSB first: 0b10110010 = 0xB2
        scanlines: <int>[0, 0xB2],
      );
      final decoded = decodePng(png);
      for (var i = 0; i < 8; i++) {
        final bit = <int>[1, 0, 1, 1, 0, 0, 1, 0][i];
        expect(
          decoded!.rgba.sublist(i * 4, i * 4 + 4),
          bit == 1 ? _rgba(255, 255, 255, 255) : _rgba(0, 0, 0, 255),
          reason: 'pixel $i',
        );
      }
    });
  });

  group('every filter type, worked out by hand', () {
    // Grey, 8-bit — bpp 1, so the arithmetic below is one byte per pixel
    // and matches the PNG specification's own filter formulas directly.

    test('Sub (type 1)', () {
      // Wants [10, 20, 30]: recon[0]=filt[0]; recon[x]=filt[x]+recon[x-1].
      final png = _png(
        width: 3,
        height: 1,
        bitDepth: 8,
        colorType: 0,
        scanlines: <int>[1, 10, 10, 10],
      );
      final decoded = decodePng(png);
      expect(decoded!.rgba, <int>[
        ..._rgba(10, 10, 10, 255),
        ..._rgba(20, 20, 20, 255),
        ..._rgba(30, 30, 30, 255),
      ]);
    });

    test('Up (type 2)', () {
      // Row 0 (None) is [5, 15, 25]; row 1 (Up) wants [8, 10, 30] —
      // filt[x] = raw[x] - above[x], byte-wraparound.
      final png = _png(
        width: 3,
        height: 2,
        bitDepth: 8,
        colorType: 0,
        scanlines: <int>[0, 5, 15, 25, 2, 3, (10 - 15) & 0xFF, 5],
      );
      final decoded = decodePng(png);
      expect(decoded!.rgba.sublist(12), <int>[
        ..._rgba(8, 8, 8, 255),
        ..._rgba(10, 10, 10, 255),
        ..._rgba(30, 30, 30, 255),
      ]);
    });

    test('Average (type 3)', () {
      // Row 0 (None) is [4, 8, 12]; row 1 (Average) wants [10, 20, 30] —
      // recon[x] = filt[x] + floor((left + above) / 2), left/above 0 where
      // there is none.
      final png = _png(
        width: 3,
        height: 2,
        bitDepth: 8,
        colorType: 0,
        scanlines: <int>[0, 4, 8, 12, 3, 8, 11, 14],
      );
      final decoded = decodePng(png);
      expect(decoded!.rgba.sublist(12), <int>[
        ..._rgba(10, 10, 10, 255),
        ..._rgba(20, 20, 20, 255),
        ..._rgba(30, 30, 30, 255),
      ]);
    });

    test('Paeth (type 4)', () {
      // Row 0 (None) is [6, 9, 20]; row 1 (Paeth) wants [7, 25, 18] — the
      // predictor picks whichever of left/above/above-left is closest to
      // left + above - above-left, ties broken left then above.
      final png = _png(
        width: 3,
        height: 2,
        bitDepth: 8,
        colorType: 0,
        scanlines: <int>[0, 6, 9, 20, 4, 1, 16, 249],
      );
      final decoded = decodePng(png);
      expect(decoded!.rgba.sublist(12), <int>[
        ..._rgba(7, 7, 7, 255),
        ..._rgba(25, 25, 25, 255),
        ..._rgba(18, 18, 18, 255),
      ]);
    });

    test('Paeth\'s own second comparison, isolated from the first', () {
      // The predictor above never reaches a pixel where the first
      // comparison (`pa <= pb && pa <= pc`) is false but the *second*
      // still has to pick correctly between `pb <= pc` and `pa <= pc` —
      // every pixel there happened to agree on both. `a=0, b=10, c=1`
      // (left, above, above-left) gives `pa=9, pb=1, pc=8`: the first
      // comparison fails (9 is not ≤ 1), and only the real formula
      // (`pb <= pc`, true, answer `b`=10) and a mutated one comparing
      // `pa` instead (false, answer `c`=1) disagree on what comes next.
      //
      // Mutation: swap `pb <= pc` for `pa <= pc` in the second
      // comparison — every other test in this group still passes, since
      // none of them separately exercises this branch.
      final png = _png(
        width: 2,
        height: 2,
        bitDepth: 8,
        colorType: 0,
        scanlines: <int>[
          0, 1, 10, // row 0: above-left, above
          4, 255, 40, // row 1: Paeth-filtered
        ],
      );
      final decoded = decodePng(png);
      expect(decoded!.rgba.sublist(8), <int>[
        ..._rgba(0, 0, 0, 255),
        ..._rgba(50, 50, 50, 255),
      ]);
    });
  });

  group('refused, by value', () {
    test('not a PNG at all', () {
      expect(decodePng(Uint8List.fromList(<int>[1, 2, 3, 4])), isNull);
    });

    test('a file cut off partway through the IDAT chunk', () {
      final whole = _png(
        width: 4,
        height: 4,
        bitDepth: 8,
        colorType: 0,
        scanlines: <int>[
          for (var y = 0; y < 4; y++) ...<int>[0, 1, 2, 3, 4],
        ],
      );
      final cut = Uint8List.sublistView(whole, 0, whole.length - 10);
      expect(decodePng(cut), isNull);
    });

    test('interlaced — refused rather than drawn wrong', () {
      // Mutation: decode an interlaced file as if it were not — the
      // scanlines are real bytes, so a naive reader produces *a* picture,
      // just the wrong one, which is worse than a clean refusal.
      final png = _png(
        width: 2,
        height: 2,
        bitDepth: 8,
        colorType: 0,
        interlace: true,
        scanlines: <int>[0, 1, 2, 0, 3, 4],
      );
      expect(decodePng(png), isNull);
    });

    test('a bit depth colour type 2 never allows', () {
      // RGB has no 1-bit form in the specification — only 8 and 16.
      final png = _png(
        width: 1,
        height: 1,
        bitDepth: 1,
        colorType: 2,
        scanlines: <int>[0, 0],
      );
      expect(decodePng(png), isNull);
    });

    test('a palette image with no PLTE chunk', () {
      final png = _png(
        width: 1,
        height: 1,
        bitDepth: 8,
        colorType: 3,
        scanlines: <int>[0, 0],
      );
      expect(decodePng(png), isNull);
    });
  });
}
