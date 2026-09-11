/// `imageDimensions`: width and height from a header, no decoder.
///
///     dart test test/image_dimensions_test.dart
///
/// Three fixtures, one per container this reads — each built as the fewest
/// bytes the reader itself looks at, not a real encoder's output, since
/// nothing here decodes a pixel. Width and height are deliberately not
/// multiples of 256 (257×131) so a byte-order mistake in either field lands
/// on a wildly different, easy-to-notice number rather than a coincidental
/// match.
library;

import 'dart:typed_data';

import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';

Uint8List _png(int width, int height) {
  final bytes = Uint8List(33);
  final view = ByteData.sublistView(bytes);
  bytes.setAll(0, <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  view.setUint32(8, 13, Endian.big); // IHDR data length
  bytes.setAll(12, <int>[0x49, 0x48, 0x44, 0x52]); // "IHDR"
  view.setUint32(16, width, Endian.big);
  view.setUint32(20, height, Endian.big);
  // bit depth, colour type, compression, filter, interlace, then a CRC this
  // reader never checks.
  bytes.setAll(24, <int>[8, 6, 0, 0, 0]);
  return bytes;
}

Uint8List _jpeg(int width, int height) {
  // SOI(2) + APP0 marker(2) + APP0 length-inclusive payload(16) + SOF0
  // marker(2) + SOF0 length-inclusive payload(11) = 33.
  final bytes = Uint8List(2 + 2 + 16 + 2 + 11);
  final view = ByteData.sublistView(bytes);
  var o = 0;
  bytes.setAll(o, <int>[0xFF, 0xD8]); // SOI
  o += 2;
  // APP0 (JFIF), a segment before the frame header, the way a real encoder
  // writes one — exercises that this reader skips segments it does not want.
  // The length field counts itself, so the marker's two bytes plus that
  // length is the segment's whole size on the wire: 2 + 16 = 18.
  bytes.setAll(o, <int>[0xFF, 0xE0]);
  view.setUint16(o + 2, 16, Endian.big);
  bytes.setAll(o + 4, <int>[
    0x4A, 0x46, 0x49, 0x46, 0x00, // "JFIF\0"
    0x01, 0x01, // version
    0x00, // units
    0x00, 0x01, 0x00, 0x01, // x/y density
    0x00, 0x00, // thumbnail width/height
  ]);
  o += 18;
  // SOF0 (baseline): length, precision, height, width, one component.
  bytes.setAll(o, <int>[0xFF, 0xC0]);
  view.setUint16(o + 2, 11, Endian.big);
  bytes[o + 4] = 8; // precision
  view.setUint16(o + 5, height, Endian.big);
  view.setUint16(o + 7, width, Endian.big);
  bytes[o + 9] = 1; // one component
  bytes.setAll(o + 10, <int>[1, 0x11, 0]);
  return bytes;
}

Uint8List _ktx2(int width, int height) {
  final bytes = Uint8List(12 + 36);
  final view = ByteData.sublistView(bytes);
  bytes.setAll(0, <int>[
    0xAB,
    0x4B,
    0x54,
    0x58,
    0x20,
    0x32,
    0x30,
    0xBB,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ]);
  view.setUint32(12, 0, Endian.little); // vkFormat
  view.setUint32(16, 1, Endian.little); // typeSize
  view.setUint32(20, width, Endian.little); // pixelWidth
  view.setUint32(24, height, Endian.little); // pixelHeight
  view.setUint32(28, 0, Endian.little); // pixelDepth
  view.setUint32(32, 0, Endian.little); // layerCount
  view.setUint32(36, 1, Endian.little); // faceCount
  view.setUint32(40, 1, Endian.little); // levelCount
  view.setUint32(44, 0, Endian.little); // supercompressionScheme
  return bytes;
}

void main() {
  group('the three headers it reads', () {
    test('PNG: width and height from IHDR, not swapped', () {
      expect(imageDimensions(_png(257, 131)), const ImageDimensions(257, 131));
    });

    test('JPEG: SOF0 past an APP0 segment it has to skip first', () {
      expect(imageDimensions(_jpeg(257, 131)), const ImageDimensions(257, 131));
    });

    test('KTX2: pixelWidth/pixelHeight from the fixed header', () {
      expect(imageDimensions(_ktx2(257, 131)), const ImageDimensions(257, 131));
    });
  });

  group('what is not any of the three', () {
    test('unrecognised bytes answer null, not a guess', () {
      expect(
        imageDimensions(Uint8List.fromList(List<int>.filled(64, 0x41))),
        isNull,
      );
    });

    test('an empty file answers null', () {
      expect(imageDimensions(Uint8List(0)), isNull);
    });
  });

  group('a truncated file answers null rather than throwing', () {
    test('PNG cut before IHDR\'s data', () {
      final full = _png(257, 131);
      expect(imageDimensions(Uint8List.sublistView(full, 0, 15)), isNull);
    });

    test('PNG cut inside the width/height fields, past the chunk type', () {
      // 20 bytes: signature, length, "IHDR" and width all present, height
      // is not — a case the length guard has to reject on its own, since the
      // width read below it would otherwise succeed and the height read
      // would run off the end of the buffer.
      final full = _png(257, 131);
      expect(imageDimensions(Uint8List.sublistView(full, 0, 20)), isNull);
    });

    test('JPEG cut inside the APP0 segment, before SOF0 is reached', () {
      final full = _jpeg(257, 131);
      expect(imageDimensions(Uint8List.sublistView(full, 0, 10)), isNull);
    });

    test('JPEG cut inside SOF0 itself, past the marker and length', () {
      // Past APP0 (20 bytes) and into SOF0's own marker, length and
      // precision — height and width are not there yet. A guard that only
      // checked the length field, not this segment's own bounds, would read
      // past the end instead of answering null.
      final full = _jpeg(257, 131);
      expect(imageDimensions(Uint8List.sublistView(full, 0, 25)), isNull);
    });

    test('KTX2 cut inside the header, before pixelHeight', () {
      final full = _ktx2(257, 131);
      expect(imageDimensions(Uint8List.sublistView(full, 0, 22)), isNull);
    });
  });

  group('equality', () {
    test('two readings of the same bytes compare equal', () {
      expect(imageDimensions(_png(64, 32)), imageDimensions(_png(64, 32)));
    });

    test('a swapped width and height do not compare equal', () {
      expect(
        imageDimensions(_png(64, 32)) == imageDimensions(_png(32, 64)),
        isFalse,
      );
    });
  });
}
