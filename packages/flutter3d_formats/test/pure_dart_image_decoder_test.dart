/// `decodeImagePure`: the `ImageDecoder`-shaped wrapper `mcp-04n` names.
///
/// `decodePng`/`decodeJpeg`'s own tests already prove the arithmetic; this
/// file proves the dispatch — that a caller handing this one function raw
/// bytes gets the right decoder by sniffing, wrapped into an [Rgba8Image]
/// rather than left as the internal [DecodedImage] shape.
///
///     dart test test/pure_dart_image_decoder_test.dart
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:test/test.dart';

Uint8List _chunk(String type, List<int> data) {
  final out = BytesBuilder();
  out.add(
    (ByteData(4)..setUint32(0, data.length, Endian.big)).buffer.asUint8List(),
  );
  out.add(ascii.encode(type));
  out.add(data);
  out.add(const <int>[0, 0, 0, 0]);
  return out.toBytes();
}

/// A minimal, valid 1×1 red PNG.
Uint8List _onePixelPng() {
  final out = BytesBuilder();
  out.add(const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  final ihdr = ByteData(13)
    ..setUint32(0, 1, Endian.big)
    ..setUint32(4, 1, Endian.big)
    ..setUint8(8, 8)
    ..setUint8(9, 2); // RGB, 8-bit
  out.add(_chunk('IHDR', ihdr.buffer.asUint8List()));
  out.add(_chunk('IDAT', ZLibCodec().encode(<int>[0, 255, 0, 0])));
  out.add(_chunk('IEND', const <int>[]));
  return out.toBytes();
}

void main() {
  test('a PNG decodes into an Rgba8Image the same size and colour', () async {
    final decoded = await decodeImagePure(_onePixelPng());
    expect(decoded, isNotNull);
    expect(decoded!.width, 1);
    expect(decoded.height, 1);
    expect(decoded.pixels, <int>[255, 0, 0, 255]);
  });

  test(
    'bytes matching no known signature decode to null, not a throw',
    () async {
      final decoded = await decodeImagePure(
        Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8]),
      );
      expect(decoded, isNull);
    },
  );

  test('a truncated PNG signature decodes to null, not a throw', () async {
    final decoded = await decodeImagePure(_onePixelPng().sublist(0, 20));
    expect(decoded, isNull);
  });
}
