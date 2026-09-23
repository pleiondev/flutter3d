/// Radiance `.hdr` — the panorama format every HDRI library hands out —
/// `ux-49`.
///
/// **RGBE, which is four bytes for three floats.** Radiance stores a shared
/// exponent per pixel: three eight-bit mantissas and one exponent byte, so a
/// sky whose sun is four hundred times brighter than its clouds fits in the
/// same four bytes a PNG pixel takes. The decode is `mantissa × 2^(e-136)`,
/// the `-136` being the 128 bias plus the 8 bits of mantissa scale.
///
/// **Two scanline encodings, and both are here.** The old one is pixels
/// straight through. The new one — everything written since about 1991, and
/// everything a library hands out today — writes each of the four channels as
/// its own run-length-encoded row, so the exponent byte of a smooth sky costs
/// two bytes a scanline instead of one a pixel. A decoder that only read the
/// flat form would read a modern file as noise rather than refusing, which is
/// the failure worth avoiding.
///
/// **Float out, not eight-bit.** Converting to bytes here would throw away
/// the whole point of the format on the way in, and the caller — which knows
/// whether it is building an eight-bit cube or measuring an average — is the
/// one that can decide what to do with a value above one.
library;

import 'dart:convert';
import 'dart:typed_data';

/// A decoded Radiance image: three floats a pixel, row 0 at the top.
typedef HdrImage = ({int width, int height, Float32List rgb});

/// What a file that is not a readable `.hdr` is answered with.
///
/// An exception rather than a null, because every caller of this wants to say
/// *why* — "not a Radiance file", "the resolution line is not one this reads"
/// and "a scanline runs off the end" are three different things for somebody
/// to do something about, and a null flattens them into one.
final class HdrFormatException implements Exception {
  const HdrFormatException(this.message);

  final String message;

  @override
  String toString() => 'HdrFormatException: $message';
}

/// How big [bytes] says it is, without decoding a pixel of it — `ux-49`.
///
/// **The header is a few dozen bytes and the image is megabytes.** What asks
/// this is a check — "is this panorama twice as wide as it is tall" — and
/// decoding four million floats to answer it would make a refusal cost more
/// than an acceptance.
///
/// Null for anything [readHdr] would refuse, without saying why: a caller
/// that wants the reason calls [readHdr] and catches it.
({int width, int height})? hdrSizeOf(Uint8List bytes) {
  try {
    final _Header header = _readHeader(bytes);
    return (width: header.width, height: header.height);
  } on HdrFormatException {
    return null;
  }
}

/// [bytes] as an HDR image.
///
/// Throws [HdrFormatException] for anything this cannot read, naming what it
/// found rather than what it wanted.
HdrImage readHdr(Uint8List bytes) {
  final _Header header = _readHeader(bytes);
  final int width = header.width;
  final int height = header.height;
  var at = header.pixelsFrom;

  // The fewest bytes a scanline can take: a run-length row is its four-byte
  // marker and, per channel, a two-byte run for every 127 pixels; a flat row
  // is four bytes a pixel. A header that names more rows than the file could
  // hold is refused here, before the float buffer it sizes is allocated.
  final int leastPerRow = width >= 8 && width < 32768
      ? 4 + 4 * 2 * ((width + 126) ~/ 127)
      : 4 * width;
  if (height * leastPerRow > bytes.length - at) {
    throw HdrFormatException(
      'a $width by $height image runs off the end of the file: '
      '${bytes.length - at} bytes of pixels cannot hold that many rows',
    );
  }

  final Float32List rgb = Float32List(width * height * 3);
  final Uint8List scanline = Uint8List(width * 4);

  for (var y = 0; y < height; y++) {
    at = _readScanline(bytes, at, scanline, width, y);
    for (var x = 0; x < width; x++) {
      final int e = scanline[x * 4 + 3];
      // Exponent zero is Radiance's own "black": the mantissas are ignored
      // rather than scaled by 2^-136, which would be a denormal.
      final double scale = e == 0 ? 0.0 : _exponent(e);
      final int out = (y * width + x) * 3;
      rgb[out] = scanline[x * 4] * scale;
      rgb[out + 1] = scanline[x * 4 + 1] * scale;
      rgb[out + 2] = scanline[x * 4 + 2] * scale;
    }
  }
  return (width: width, height: height, rgb: rgb);
}

/// What the header said, and where the pixels start.
typedef _Header = ({int width, int height, int pixelsFrom});

/// Reads the header of [bytes], throwing [HdrFormatException] for anything
/// this file cannot be.
_Header _readHeader(Uint8List bytes) {
  var at = 0;

  String nextLine() {
    final int start = at;
    while (at < bytes.length && bytes[at] != 0x0a) {
      at++;
    }
    if (at >= bytes.length) {
      throw const HdrFormatException(
        'the header runs to the end of the file without a resolution line',
      );
    }
    final String line = latin1.decode(bytes.sublist(start, at));
    at++;
    return line;
  }

  final String magic = nextLine();
  if (!magic.startsWith('#?')) {
    throw HdrFormatException(
      'not a Radiance file: it starts with '
      '"${magic.length > 16 ? '${magic.substring(0, 16)}\u2026' : magic}" '
      'rather than "#?RADIANCE"',
    );
  }

  // Header lines until a blank one. `FORMAT=` is the only one worth reading:
  // Radiance also writes XYZE, which is the same four bytes meaning a
  // different colour space, and decoding one as the other silently produces
  // a picture with the wrong hues.
  var format = '32-bit_rle_rgbe';
  while (true) {
    final String line = nextLine();
    if (line.trim().isEmpty) break;
    if (line.startsWith('FORMAT=')) format = line.substring(7).trim();
  }
  if (format != '32-bit_rle_rgbe') {
    throw HdrFormatException(
      'this reads 32-bit_rle_rgbe and the file says "$format"',
    );
  }

  // `-Y height +X width` — the one orientation Radiance writers emit, and
  // the one where row zero is the top. The others are legal and rare, and
  // refusing by name beats flipping a panorama upside down.
  final String resolution = nextLine().trim();
  final RegExpMatch? size = RegExp(
    r'^-Y\s+(\d+)\s*\+X\s+(\d+)$',
  ).firstMatch(resolution);
  if (size == null) {
    throw HdrFormatException(
      'the resolution line is "$resolution"; this reads "-Y height +X width"',
    );
  }
  final int height = int.parse(size.group(1)!);
  final int width = int.parse(size.group(2)!);
  if (width <= 0 || height <= 0) {
    throw HdrFormatException('the file says it is $width by $height');
  }
  return (width: width, height: height, pixelsFrom: at);
}

/// `2^(e - 136)`, memoised over the 256 exponents there are.
///
/// A `pow` per channel per pixel is four million calls on a 2048×1024
/// panorama, and there are 256 distinct answers.
double _exponent(int e) => _exponents[e] ??= _computed(e);
final List<double?> _exponents = List<double?>.filled(256, null);
double _computed(int e) {
  var value = 1.0;
  final int shift = e - 136;
  for (var i = 0; i < shift.abs(); i++) {
    value = shift > 0 ? value * 2.0 : value / 2.0;
  }
  return value;
}

/// Reads one scanline into [out] and answers where the next one starts.
int _readScanline(
  Uint8List bytes,
  int from,
  Uint8List out,
  int width,
  int row,
) {
  var at = from;
  int next() {
    if (at >= bytes.length) {
      throw HdrFormatException('scanline $row runs off the end of the file');
    }
    return bytes[at++];
  }

  // The new-style marker: 2, 2, and the width as a big-endian pair. A width
  // outside 8..32767 cannot be written this way at all, which is how a flat
  // scanline that happens to start with two reds of value 2 is told apart.
  if (width >= 8 && width < 32768) {
    final int a = next();
    final int b = next();
    final int hi = next();
    final int lo = next();
    if (a == 2 && b == 2 && ((hi << 8) | lo) == width) {
      for (var channel = 0; channel < 4; channel++) {
        var x = 0;
        while (x < width) {
          var count = next();
          if (count > 128) {
            // A run: one value repeated `count - 128` times.
            count -= 128;
            final int value = next();
            if (x + count > width) {
              throw HdrFormatException(
                'a run on scanline $row claims $count pixels past its end',
              );
            }
            for (var i = 0; i < count; i++) {
              out[(x++) * 4 + channel] = value;
            }
          } else {
            if (count == 0) {
              throw HdrFormatException(
                'a zero-length literal on scanline $row',
              );
            }
            if (x + count > width) {
              throw HdrFormatException(
                'a literal on scanline $row claims $count pixels past its end',
              );
            }
            for (var i = 0; i < count; i++) {
              out[(x++) * 4 + channel] = next();
            }
          }
        }
      }
      return at;
    }
    // Not a new-style scanline after all: those four bytes were the first
    // pixel, so rewind and read the row flat.
    at = from;
  }

  for (var x = 0; x < width; x++) {
    out[x * 4] = next();
    out[x * 4 + 1] = next();
    out[x * 4 + 2] = next();
    out[x * 4 + 3] = next();
  }
  return at;
}
