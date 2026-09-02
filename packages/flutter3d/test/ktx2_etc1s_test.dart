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
/// `flutter3d_samples/doc/ktx2_fixtures.md` for the full byte-layout
/// cross-check this fixture was also used for, and for the two files with
/// mip chains checked below.
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

  // Two more files from the same encoder, each with `-mipmap`, held level by
  // level against `basisu -unpack`'s RGBA32 output stored raw under
  // `test/fixtures/ktx2/`. The first carries alpha, so every level is two
  // ETC1S slices; the second is 64×64 of chequered gradient and noise, which
  // is sixteen tiles of endpoint prediction and selector runs long enough to
  // reach the run-length path — an 8×8 gradient is two tiles and never does.
  for (final (name, width, height, levels) in <(String, int, int, int)>[
    ('etc1s_alpha_mips', 16, 16, 5),
    ('etc1s_field_mips', 64, 64, 7),
  ]) {
    test(
      '$name transcodes every level and its alpha as basisu unpacks them',
      () {
        final texture = Ktx2Texture.parse(_readSample('ktx2/$name.ktx2'));

        expect(texture.pixelWidth, width);
        expect(texture.pixelHeight, height);
        expect(texture.format, TextureFormat.r8g8b8a8UNormInt);
        expect(texture.levels, hasLength(levels));

        for (var level = 0; level < levels; level++) {
          final expected = File(
            'test/fixtures/ktx2/${name}_level_$level.rgba',
          ).readAsBytesSync();
          final actual = texture.levels[level].buffer.asUint8List(
            texture.levels[level].offsetInBytes,
            texture.levels[level].lengthInBytes,
          );
          expect(actual.length, expected.length, reason: 'level $level size');
          for (var i = 0; i < expected.length; i++) {
            if (actual[i] != expected[i]) {
              final pixel = i ~/ 4;
              final levelWidth = (width >> level).clamp(1, width);
              fail(
                'level $level pixel (${pixel % levelWidth}, '
                '${pixel ~/ levelWidth}) channel ${i % 4}: '
                'expected ${expected[i]}, got ${actual[i]}',
              );
            }
          }
        }
      },
    );
  }
}
