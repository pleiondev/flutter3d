/// `ux-49`'s own Radiance reader, against files this test writes itself.
///
///     dart test test/hdr_decoder_test.dart
///
/// **The files are forged here rather than checked in.** Every refusal below
/// needs a file no writer would produce — a magic from another format, a
/// resolution line in the wrong order, a run claiming more pixels than the
/// row has — and a test that could only use real `.hdr` files could reach
/// none of them. The two encodings are written by hand for the same reason
/// the container tests in this package forge their own headers: a second
/// implementation of the layout is what makes a disagreement mean something.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

/// The header every file below starts with.
List<int> _header(int width, int height) =>
    utf8.encode('#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y $height +X $width\n');

/// A file whose scanlines are pixels straight through — the old encoding.
Uint8List _flat(int width, int height, List<List<int>> pixels) {
  final out = <int>[..._header(width, height)];
  for (final List<int> pixel in pixels) {
    out.addAll(pixel);
  }
  return Uint8List.fromList(out);
}

/// One new-style scanline: the 2/2/width marker, then four RLE channel rows.
///
/// Every row here is one run of [width] copies, which is the shape a smooth
/// sky actually takes and the shape a decoder that ignored the run bit would
/// read as four pixels followed by noise.
List<int> _rleScanline(int width, List<int> rgbe) => <int>[
  2,
  2,
  (width >> 8) & 0xff,
  width & 0xff,
  for (final int channel in rgbe) ...<int>[128 + width, channel],
];

void main() {
  group('the old encoding', () {
    test('reads four bytes a pixel as three floats', () {
      // 128 mantissa, exponent 136 → 128 × 2^0 = 128… no: the scale is
      // 2^(136-136) = 1, so the channel reads back as its own mantissa.
      final Uint8List file = _flat(2, 1, <List<int>>[
        <int>[128, 64, 32, 136],
        <int>[255, 0, 0, 136],
      ]);

      final HdrImage image = readHdr(file);

      expect(image.width, 2);
      expect(image.height, 1);
      expect(image.rgb.sublist(0, 3), <double>[128, 64, 32]);
      expect(image.rgb.sublist(3, 6), <double>[255, 0, 0]);
    });

    test('and the exponent really is a power of two', () {
      // One stop down: the same mantissa at exponent 135 is half as bright.
      final Uint8List file = _flat(1, 1, <List<int>>[
        <int>[100, 100, 100, 135],
      ]);

      expect(readHdr(file).rgb[0], 50.0);
    });

    test('exponent zero is black, not a denormal', () {
      // Mutation: scale the mantissas by 2^-136 anyway. Every "black" pixel
      // in every sky comes back as a number too small for a float to hold
      // usefully, and an average over the image stops meaning anything.
      final Uint8List file = _flat(1, 1, <List<int>>[
        <int>[200, 200, 200, 0],
      ]);

      expect(readHdr(file).rgb.sublist(0, 3), <double>[0, 0, 0]);
    });
  });

  group('the new encoding', () {
    test('a run-length scanline reads back as the run it names', () {
      final out = <int>[
        ..._header(16, 2),
        ..._rleScanline(16, <int>[10, 20, 30, 136]),
        ..._rleScanline(16, <int>[40, 50, 60, 137]),
      ];

      final HdrImage image = readHdr(Uint8List.fromList(out));

      expect(image.width, 16);
      expect(image.height, 2);
      // **Every file a library hands out is written this way.** Mutation:
      // read only the flat form, which is what a decoder written from the
      // format's first paragraph does — the marker bytes become the first
      // pixel and the rest of the row is noise.
      expect(image.rgb.sublist(0, 3), <double>[10, 20, 30]);
      expect(image.rgb.sublist(45, 48), <double>[10, 20, 30]);
      // Row two, at exponent 137: one stop up.
      expect(image.rgb.sublist(48, 51), <double>[80, 100, 120]);
    });

    test('a literal run reads its bytes one at a time', () {
      final out = <int>[
        ..._header(8, 1),
        2, 2, 0, 8,
        // Red: eight literals, then the other three channels as runs.
        8, 1, 2, 3, 4, 5, 6, 7, 8,
        for (var channel = 0; channel < 3; channel++) ...<int>[
          128 + 8,
          channel == 2 ? 136 : 0,
        ],
      ];

      final HdrImage image = readHdr(Uint8List.fromList(out));

      expect(image.rgb[0], 1.0);
      expect(image.rgb[21], 8.0);
    });

    test('a row whose marker is not the width is read flat instead', () {
      // A genuine old-style scanline whose first pixel happens to be
      // 2,2,0,9 — the marker check has to let that through rather than
      // reading the row as a run of nine.
      final Uint8List file = _flat(8, 1, <List<int>>[
        <int>[2, 2, 0, 9],
        for (var i = 0; i < 7; i++) <int>[1, 1, 1, 136],
      ]);

      final HdrImage image = readHdr(file);
      expect(image.rgb.sublist(3, 6), <double>[1, 1, 1]);
    });
  });

  group('what it refuses, and what it says', () {
    test('a file that is not Radiance at all', () {
      expect(
        () => readHdr(Uint8List.fromList(utf8.encode('\x89PNG\r\n\x1a\n\n'))),
        throwsA(
          isA<HdrFormatException>().having(
            (HdrFormatException it) => it.message,
            'message',
            contains('not a Radiance file'),
          ),
        ),
      );
    });

    test('a colour space this does not read', () {
      final Uint8List file = Uint8List.fromList(
        utf8.encode('#?RADIANCE\nFORMAT=32-bit_rle_xyze\n\n-Y 1 +X 1\n'),
      );
      expect(
        () => readHdr(file),
        throwsA(
          isA<HdrFormatException>().having(
            (HdrFormatException it) => it.message,
            'message',
            contains('xyze'),
          ),
        ),
      );
    });

    test('a resolution line in an order this does not read', () {
      final Uint8List file = Uint8List.fromList(
        utf8.encode('#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n+X 4 -Y 2\n'),
      );
      expect(
        () => readHdr(file),
        throwsA(
          isA<HdrFormatException>().having(
            (HdrFormatException it) => it.message,
            'message',
            contains('-Y height +X width'),
          ),
        ),
      );
    });

    test('and a scanline that runs off the end', () {
      final out = <int>[..._header(4, 1), 1, 2, 3];
      expect(
        () => readHdr(Uint8List.fromList(out)),
        throwsA(
          isA<HdrFormatException>().having(
            (HdrFormatException it) => it.message,
            'message',
            contains('off the end'),
          ),
        ),
      );
    });
  });
}
