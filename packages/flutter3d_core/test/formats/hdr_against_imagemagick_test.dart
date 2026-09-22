/// `ux-49`'s Radiance reader, against files this repository did not write.
///
///     dart test test/formats/hdr_decoder_test.dart
///
/// **The check `hdr_decoder_test.dart` beside it cannot make.** That file
/// forges its own `.hdr`s, and says why: a second implementation of the
/// layout is what makes a disagreement mean something, and a refusal needs a
/// file no real writer would produce. Both are true. What it still cannot
/// reach is a file written by somebody else — the two implementations in it
/// are one person's reading of the specification, encoded twice, and they
/// agree about anything they are both wrong about.
///
/// `fmt-30n` is what makes that worth spending a fixture on. Its index codec
/// passed its own round trip for a week while writing a byte `meshoptimizer`'s
/// own decoder read as index 4294967295: the encoder and the decoder shared a
/// zero-filled buffer and agreed about a phantom. Nothing but an outside
/// implementation could have said so.
///
/// So: three files written by ImageMagick, and beside each one *ImageMagick's
/// own reading of it* as raw float triples. This decodes the first and
/// compares against the second, which makes it a comparison between two
/// programs rather than between a repository and itself.
/// `assets/radiance/PROVENANCE.md` has the commands and what each covers.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_core/src/formats/image/hdr_decoder.dart';
import 'package:test/test.dart';

Uint8List _bytes(String name) =>
    File('../flutter3d_samples/assets/radiance/$name').readAsBytesSync();

/// ImageMagick's own reading of the same file: little-endian float32 RGB.
Float32List _reference(String name) {
  final raw = _bytes(name);
  return raw.buffer.asFloat32List(raw.offsetInBytes, raw.lengthInBytes ~/ 4);
}

void main() {
  group('against ImageMagick reading the same file', () {
    for (final (String name, int width, int height) in <(String, int, int)>[
      ('gradient', 64, 32),
      ('plasma', 40, 10),
      ('tiny', 4, 4),
    ]) {
      test('$name decodes to the same pixels', () {
        final HdrImage image = readHdr(_bytes('$name.hdr'));
        expect(image.width, width);
        expect(image.height, height);

        final Float32List want = _reference('$name.rgbf');
        expect(image.rgb.length, want.length);

        // **A relative tolerance, and the reason is RGBE rather than
        // arithmetic.** Both readers recover the same three mantissas and the
        // same exponent, so they agree wherever the format is exact — but
        // ImageMagick writes its floats after its own quantum conversion,
        // which is not bit for bit the same multiply. A hundred-thousandth of
        // the value is far below what a shared eight-bit mantissa can even
        // represent.
        var worst = 0.0;
        for (var i = 0; i < want.length; i++) {
          final double scale = want[i].abs() < 1e-6 ? 1.0 : want[i].abs();
          final double off = (image.rgb[i] - want[i]).abs() / scale;
          if (off > worst) worst = off;
        }
        expect(worst, lessThan(1e-5), reason: '$name: worst relative error');
      });
    }

    test('the three files really do take different paths through the '
        'decoder', () {
      // Without this the group above could be three runs of one branch, and
      // the fixture set would be one fixture with three names. `gradient` and
      // `plasma` announce the packed form; `tiny` is four pixels wide, which
      // is below the eight the format allows it for, so it is flat.
      for (final (String name, bool packed) in <(String, bool)>[
        ('gradient', true),
        ('plasma', true),
        ('tiny', false),
      ]) {
        final Uint8List file = _bytes('$name.hdr');
        // Past the header: two newlines, then the resolution line.
        var at = 0;
        var blanks = 0;
        while (at < file.length && blanks < 1) {
          if (file[at] == 0x0a &&
              at + 1 < file.length &&
              file[at + 1] == 0x0a) {
            blanks++;
            at += 2;
            break;
          }
          at++;
        }
        while (at < file.length && file[at] != 0x0a) {
          at++;
        }
        at++;
        expect(
          file[at] == 0x02 && file[at + 1] == 0x02,
          packed,
          reason: '$name should ${packed ? '' : 'not '}be run-length coded',
        );
      }
    });
  });

  test('a value above one survives, which is what the format is for', () {
    // An eight-bit reader would clip this and nothing would say so. The
    // gradient's brightest channel comes from sRGB 255, which lands close to
    // one in the linear floats ImageMagick writes, and the exponent byte is
    // what carries anything above it.
    final HdrImage image = readHdr(_bytes('gradient.hdr'));
    var brightest = 0.0;
    for (final double v in image.rgb) {
      if (v > brightest) brightest = v;
    }
    expect(brightest, greaterThan(0.9));
  });
}
