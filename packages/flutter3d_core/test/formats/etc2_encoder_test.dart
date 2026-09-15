/// Proves the ETC2 RGB8 encoder self-consistent — decoded here, not by a
/// real GPU. `doc/asset-pipeline-plan.md`'s `ap-07` write-up names the real
/// GPU check this cannot replace: ETC's column-major pixel numbering and its
/// two-plane index word are exactly the kind of bit-order choice that can be
/// self-consistent and still wrong against the specification, which only a
/// decoder this port did not write can catch.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

import 'helpers/etc2_test_decoder.dart';

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

/// Red on top, blue on the bottom — split along rows, the axis this
/// encoder's flip = 0 halves actually separate (see [encodeEtc2Rgb8Block]'s
/// own doc comment on why a left/right split is not this shape's strength),
/// with enough per-pixel variation within each half to still exercise more
/// than one modifier index.
Rgba8Image _rowSplit() {
  final pixels = Uint8List(64);
  for (var y = 0; y < 4; y++) {
    for (var x = 0; x < 4; x++) {
      final at = (y * 4 + x) * 4;
      final top = y < 2;
      pixels[at] = top ? 200 + x * 10 : 20;
      pixels[at + 1] = 30;
      pixels[at + 2] = top ? 20 : 200 + x * 10;
      pixels[at + 3] = 255;
    }
  }
  return Rgba8Image(width: 4, height: 4, pixels: pixels);
}

void main() {
  test(
    'a solid block matches flutter3d_conformance\'s own reference bytes',
    () {
      // `compressed_checks.dart`'s `_etc2Solid()`: (136, 68, 204) packed as
      // both(r), both(g), both(b), then a zero table/diff/flip byte and an
      // all-zero index word.
      final encoded = encodeEtc2Rgb8Block(
        List<(int, int, int, int)>.generate(16, (_) => (136, 68, 204, 255)),
      );
      int both(int v) => ((v >> 4) << 4) | (v >> 4);
      expect(encoded[0], both(136));
      expect(encoded[1], both(68));
      expect(encoded[2], both(204));
      expect(
        encoded[3] & 0x3,
        0,
        reason: 'diff = 0, flip = 0 for a flat block',
      );
      expect(encoded.sublist(4), <int>[0, 0, 0, 0]);
    },
  );

  test('a solid block round-trips through this port\'s own decoder', () {
    final source = _solid(90, 150, 40);
    final decoded = decodeEtc2Rgb8(encodeEtc2Rgb8(source), 4, 4);
    for (var y = 0; y < 4; y++) {
      for (var x = 0; x < 4; x++) {
        expect(decoded.red(x, y), closeTo(90, 10));
        expect(decoded.green(x, y), closeTo(150, 10));
        expect(decoded.blue(x, y), closeTo(40, 10));
      }
    }
  });

  test('a row split round-trips within one modifier step of the source', () {
    final source = _rowSplit();
    final decoded = decodeEtc2Rgb8(encodeEtc2Rgb8(source), 4, 4);
    for (var y = 0; y < 4; y++) {
      for (var x = 0; x < 4; x++) {
        expect(
          (decoded.red(x, y) - source.red(x, y)).abs(),
          lessThan(50),
          reason: 'pixel ($x, $y) red',
        );
        expect(
          (decoded.blue(x, y) - source.blue(x, y)).abs(),
          lessThan(50),
          reason: 'pixel ($x, $y) blue',
        );
      }
    }
  });

  test(
    'a wide-range block prefers differential when it fits, individual otherwise',
    () {
      // Top half near black, bottom half near white: a delta this large does
      // not fit differential mode's 3-bit range, so individual mode — two
      // independent base colours — has to win on error.
      final pixels = <(int, int, int, int)>[
        for (var i = 0; i < 8; i++) (10, 10, 10, 255),
        for (var i = 0; i < 8; i++) (250, 250, 250, 255),
      ];
      final encoded = encodeEtc2Rgb8Block(pixels);
      final diff = (encoded[3] & 0x2) != 0;
      expect(diff, isFalse, reason: 'a 240-level jump exceeds a 3-bit delta');

      final source = Rgba8Image(
        width: 4,
        height: 4,
        pixels: Uint8List.fromList(<int>[
          for (final (r, g, b, a) in pixels) ...<int>[r, g, b, a],
        ]),
      );
      final decoded = decodeEtc2Rgb8(encoded, 4, 4);
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 4; x++) {
          expect(
            decoded.red(x, y),
            closeTo(source.red(x, y), 10),
            reason: 'pixel ($x, $y)',
          );
        }
      }
    },
  );
}
