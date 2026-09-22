import 'dart:typed_data';

import 'package:flutter3d_models/src/storage/png.dart';
import 'package:test/test.dart';

/// A minimal PNG: the signature, then an `IHDR` chunk naming [width] and
/// [height] — no CRC and no later chunks, because `inspectPreviewPng` never
/// reads past `IHDR`'s own 13 data bytes.
Uint8List _png(int width, int height) {
  final bytes = BytesBuilder();
  bytes.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  final length = ByteData(4)..setUint32(0, 13, Endian.big);
  bytes.add(length.buffer.asUint8List());
  bytes.add('IHDR'.codeUnits);
  final data = ByteData(13)
    ..setUint32(0, width, Endian.big)
    ..setUint32(4, height, Endian.big)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 6) // color type: RGBA
    ..setUint8(10, 0) // compression
    ..setUint8(11, 0) // filter
    ..setUint8(12, 0); // interlace
  bytes.add(data.buffer.asUint8List());
  return bytes.toBytes();
}

void main() {
  group('inspectPreviewPng', () {
    test(
      'a well-formed PNG in range is accepted, width and height read back',
      () {
        final result = inspectPreviewPng(_png(512, 256));
        expect(result, isA<PngAccepted>());
        final accepted = result as PngAccepted;
        expect(accepted.width, 512);
        expect(accepted.height, 256);
      },
    );

    test('the smallest and largest allowed sides are both accepted', () {
      expect(
        inspectPreviewPng(_png(previewMinSide, previewMaxSide)),
        isA<PngAccepted>(),
      );
    });

    test('bytes that are not a PNG at all are rejected', () {
      final result = inspectPreviewPng(
        Uint8List.fromList('v 0 0 0\nf 1 2 3\n'.codeUnits),
      );
      expect(result, isA<PngRejected>());
    });

    test('a GLB, which starts with its own unrelated magic, is rejected', () {
      final result = inspectPreviewPng(
        Uint8List.fromList([0x67, 0x6C, 0x54, 0x46, 2, 0, 0, 0]),
      );
      expect(result, isA<PngRejected>());
    });

    test('a signature with nothing after it is rejected, not crashed on', () {
      final result = inspectPreviewPng(
        Uint8List.fromList(const [
          0x89,
          0x50,
          0x4E,
          0x47,
          0x0D,
          0x0A,
          0x1A,
          0x0A,
        ]),
      );
      expect(result, isA<PngRejected>());
    });

    test('a first chunk that is not IHDR is rejected', () {
      final bytes = _png(64, 64);
      // Overwrite the chunk type (bytes 12..16) with something else.
      bytes.setRange(12, 16, 'IDAT'.codeUnits);
      expect(inspectPreviewPng(bytes), isA<PngRejected>());
    });

    test('a picture smaller than the minimum side is rejected', () {
      final result = inspectPreviewPng(_png(previewMinSide - 1, 64));
      expect(result, isA<PngRejected>());
      expect((result as PngRejected).because, contains('between'));
    });

    test('a picture larger than the maximum side is rejected', () {
      final result = inspectPreviewPng(_png(64, previewMaxSide + 1));
      expect(result, isA<PngRejected>());
    });
  });
}
