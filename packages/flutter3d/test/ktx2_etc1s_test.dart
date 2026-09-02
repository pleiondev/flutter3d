/// Proves the ETC1S transcoder against a real Basis Universal encoder's
/// output, not against this port's own understanding of the format.
///
/// `packages/flutter3d_samples/assets/ktx2/etc1s_gradient_quadrants.ktx2` was
/// produced by a from-source build of `BinomialLLC/basis_universal`'s
/// `basisu` CLI (not vendored here — `toktx`/`basisu` are not available as
/// packages):
///
/// ```
/// git clone --depth 1 https://github.com/BinomialLLC/basis_universal.git
/// cmake -G Ninja -B build -DCMAKE_BUILD_TYPE=Release -DBASISU_EXAMPLES=OFF \
///   -DBASISU_BUILD_PYTHON=OFF -DBASISU_OPENCL=OFF -DBASISU_SUPPORT_ASTCENC=OFF
/// ninja -C build basisu
/// ./bin/basisu -ktx2 -linear -no_multithreading source.png
/// ```
///
/// `source.png` is an 8x8 image with four 4x4 quadrants (red, green, blue,
/// yellow), each with a small per-pixel gradient so the encoder has more
/// than one colour to pick a selector for. The expected pixels below are
/// `basisu -unpack`'s own RGBA32 transcode of the same file — the ground
/// truth this port either matches or does not; see
/// `~/.claude/plans/ktx2-etc1s-fixture/README.md` for the full byte-layout
/// cross-check this fixture was also used for.
///
/// Runs off-device: reading the file is the only I/O, same as
/// `f3d_test.dart`'s samples.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d/src/engine/assets/ktx2/ktx2.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_samples/flutter3d_samples.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _readSample(String name) =>
    File('$kSamplesPath/$name').readAsBytesSync();

/// One packed `0xAABBGGRR` per pixel, matching how [transcodeEtc1sSliceToRgba8]
/// (reached through [Ktx2Texture.parse]) writes `Endian.little` uint32s — so
/// comparing four bytes at a time here is comparing exactly what a
/// `createTextureFromPixels` call would receive.
int _rgba(int r, int g, int b, int a) => r | (g << 8) | (b << 16) | (a << 24);

void main() {
  test(
    'a real basisu ETC1S file transcodes to the same pixels basisu unpacks',
    () {
      final bytes = _readSample('ktx2/etc1s_gradient_quadrants.ktx2');
      final texture = Ktx2Texture.parse(bytes);

      expect(texture.pixelWidth, 8);
      expect(texture.pixelHeight, 8);
      expect(texture.format, TextureFormat.r8g8b8a8UNormInt);
      expect(texture.levels, hasLength(1));

      // basisu -unpack's RGBA32 transcode of the same file, row by row —
      // captured once from a real decode, not derived from this port.
      const topLeft = (253, 0, 0);
      const topLeftLower = (255, 2, 2);
      const topRight = (6, 253, 0);
      const bottomLeft = (0, 6, 253);
      const bottomRight = (255, 255, 2);
      final expectedRows = <List<(int, int, int)>>[
        List.filled(4, topLeft) + List.filled(4, topRight),
        List.filled(4, topLeft) + List.filled(4, topRight),
        List.filled(4, topLeftLower) + List.filled(4, topRight),
        List.filled(4, topLeftLower) + List.filled(4, topRight),
        List.filled(4, bottomLeft) + List.filled(4, bottomRight),
        List.filled(4, bottomLeft) + List.filled(4, bottomRight),
        List.filled(4, bottomLeft) + List.filled(4, bottomRight),
        List.filled(4, bottomLeft) + List.filled(4, bottomRight),
      ];

      final pixels = texture.levels.single;
      for (var y = 0; y < 8; y++) {
        for (var x = 0; x < 8; x++) {
          final (r, g, b) = expectedRows[y][x];
          final actual = pixels.getUint32((y * 8 + x) * 4, Endian.little);
          expect(
            actual,
            _rgba(r, g, b, 255),
            reason:
                'pixel ($x, $y): expected rgb($r,$g,$b), got '
                '0x${actual.toRadixString(16)}',
          );
        }
      }
    },
  );
}
