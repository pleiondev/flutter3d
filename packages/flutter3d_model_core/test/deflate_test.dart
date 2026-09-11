/// `zlibCompress`: a real, compressing DEFLATE writer — `mat-12`'s own
/// half of the pair `inflate_test.dart` already exercises the other side
/// of.
///
/// **Checked against `dart:io`'s own `ZLibCodec`, an independent decoder**,
/// not only against this package's own `zlibInflate` — agreeing with
/// itself would prove this file is internally consistent, not that it
/// writes a real RFC 1950/1951 stream anything else can read.
///
///     dart test test/deflate_test.dart
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';

void main() {
  group('round-trips through this package\'s own zlibInflate', () {
    test('empty input', () {
      expect(zlibInflate(zlibCompress(Uint8List(0))), <int>[]);
    });

    test('a short, highly repetitive run', () {
      final data = Uint8List.fromList(List<int>.filled(500, 9));
      expect(zlibInflate(zlibCompress(data)), data);
    });

    test('incompressible-looking bytes', () {
      var seed = 54321;
      final data = Uint8List.fromList(
        List<int>.generate(3000, (_) {
          seed = (seed * 1103515245 + 12345) & 0x7fffffff;
          return seed & 0xFF;
        }),
      );
      expect(zlibInflate(zlibCompress(data)), data);
    });

    test('a run longer than the 258-byte maximum match length', () {
      final data = Uint8List.fromList(List<int>.filled(50000, 3));
      expect(zlibInflate(zlibCompress(data)), data);
    });

    test('an overlapping repeat — distance shorter than any one match '
        'could be', () {
      final data = Uint8List.fromList(
        List<int>.generate(4000, (i) => i.isEven ? 11 : 22),
      );
      expect(zlibInflate(zlibCompress(data)), data);
    });

    test('a match distance right at the 32768-byte window edge', () {
      final data = Uint8List(40000);
      data[0] = 77;
      data[32768] = 77; // exactly at the boundary this file's own limit names
      expect(zlibInflate(zlibCompress(data)), data);
    });
  });

  group('read by an independent decoder — dart:io\'s own ZLibCodec', () {
    test('a mixed run of literals and repeats', () {
      final data = Uint8List.fromList(<int>[
        for (var i = 0; i < 2000; i++) (i % 37 < 5) ? 200 : i % 251,
      ]);
      // Mutation: write the length/distance extra bits in the wrong order,
      // or the fixed-Huffman code for a literal past 143 without the 9-bit
      // table's own offset — either produces a stream this package's own
      // (matching) decoder might still misread the same wrong way, but
      // dart:io's independent one would not.
      final decoded = ZLibCodec().decode(zlibCompress(data));
      expect(decoded, data);
    });

    test('empty input', () {
      expect(ZLibCodec().decode(zlibCompress(Uint8List(0))), <int>[]);
    });
  });

  group('mat-12\'s own acceptance: a gradient compresses well', () {
    test('a 1024x1024 RGBA gradient compresses under 25% of its stored '
        'size', () {
      // A horizontal gradient in the red channel, everything else flat —
      // the shape `mat-12`'s own row names, and the shape a PNG's own Sub
      // filter turns into a near-constant byte stream before this even
      // sees it (built the same way `png_encoder_test.dart` builds its
      // own copy of this fixture, so both tests are measuring the same
      // acceptance line from two different angles).
      const side = 1024;
      final rgba = Uint8List(side * side * 4);
      for (var y = 0; y < side; y++) {
        for (var x = 0; x < side; x++) {
          final at = (y * side + x) * 4;
          rgba[at] = x * 255 ~/ side;
          rgba[at + 3] = 255;
        }
      }
      final compressed = zlibCompress(rgba);
      expect(compressed.length, lessThan(rgba.length * 0.25));
      expect(zlibInflate(compressed), rgba);
    });
  });
}
