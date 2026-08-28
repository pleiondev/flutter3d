/// The mip chain, which three backends upload verbatim.
///
/// Worth testing here rather than through a picture: these bytes are the one
/// thing every backend agrees on by construction, so a defect in them is a
/// defect on all three at once — and three backends failing identically is
/// exactly the shape a golden cannot tell from correct.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_test/flutter_test.dart';

/// A texture of one flat colour, so an average has a known answer.
ByteData _flat(int width, int height, int value) {
  final bytes = Uint8List(width * height * 4);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = value;
  }
  return ByteData.sublistView(bytes);
}

void main() {
  group('the chain', () {
    test('runs from half size down to one by one', () {
      expect(MipChain.levelsFor(8, 8), 3, reason: '4, 2, 1');
      expect(MipChain.levelsFor(1, 1), 0, reason: 'nothing below the base');
      // Non-square: the chain does not stop when the short side reaches one,
      // because the long side is still being minified.
      expect(MipChain.levelsFor(8, 2), 3, reason: '4x1, 2x1, 1x1');
      expect(MipChain.levelsFor(1, 16), 4);
    });

    test('has as many levels as it says, at the sizes it says', () {
      final levels = MipChain.build(_flat(8, 4, 0), 8, 4);
      expect(levels, hasLength(MipChain.levelsFor(8, 4)));
      // 4x2, 2x1, 1x1.
      expect(levels[0].lengthInBytes, 4 * 2 * 4);
      expect(levels[1].lengthInBytes, 2 * 1 * 4);
      expect(levels[2].lengthInBytes, 1 * 1 * 4);
    });

    test('a flat texture stays exactly that colour all the way down', () {
      // The rounding test in disguise. Averaging four equal values must give
      // that value back; a filter that truncated instead would lose a level of
      // brightness per step, and ten levels down a white texture would be grey.
      final levels = MipChain.build(_flat(16, 16, 200), 16, 16);
      for (final level in levels) {
        final bytes = level.buffer.asUint8List(level.offsetInBytes);
        for (final byte in bytes) {
          expect(byte, 200);
        }
      }
    });

    test('averages its four texels rather than picking one', () {
      // A 2x2 of 0, 100, 200, 255 comes to 138.75, which rounds to 139.
      final base = ByteData.sublistView(
        Uint8List.fromList(<int>[
          0, 0, 0, 0, //
          100, 100, 100, 100,
          200, 200, 200, 200,
          255, 255, 255, 255,
        ]),
      );
      final levels = MipChain.build(base, 2, 2);
      expect(levels, hasLength(1));
      final one = levels.single.buffer.asUint8List(levels.single.offsetInBytes);
      expect(one, hasLength(4));
      for (final byte in one) {
        expect(
          byte,
          139,
          reason: 'a nearest-texel filter would answer 0, 100, 200 or 255',
        );
      }
    });

    test('keeps the channels apart', () {
      // Every channel averaged with its own kind. A filter that walked the
      // bytes without the stride would blend red into green, which on a normal
      // map is a surface that leans the wrong way rather than one that looks
      // blurry.
      final base = ByteData.sublistView(
        Uint8List.fromList(<int>[
          10, 20, 30, 40, //
          10, 20, 30, 40,
          30, 40, 50, 60,
          30, 40, 50, 60,
        ]),
      );
      final one = MipChain.build(base, 2, 2).single;
      final bytes = one.buffer.asUint8List(one.offsetInBytes);
      expect(bytes, <int>[20, 30, 40, 50]);
    });

    test('a one-by-one texture has no chain at all', () {
      expect(MipChain.build(_flat(1, 1, 128), 1, 1), isEmpty);
    });

    test('an axis already at one is read twice rather than off the end', () {
      // The bounds case: at 4x1 the vertical neighbour of row zero is row zero.
      // Reading row one instead would walk past the buffer, and reading it as
      // zero would darken every level of a texture that is one texel tall.
      final base = _flat(4, 1, 90);
      final levels = MipChain.build(base, 4, 1);
      expect(levels, hasLength(2));
      for (final level in levels) {
        final bytes = level.buffer.asUint8List(level.offsetInBytes);
        for (final byte in bytes) {
          expect(byte, 90);
        }
      }
    });
  });
}
