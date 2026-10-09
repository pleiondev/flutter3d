/// The pieces of a frame capture's JSON that are not one class's: numbers
/// that may be NaN, images as PNG, floats as bytes, uniforms by shape —
/// `A5.23`.
///
/// Not exported. `FrameCapture.toJson` and `DrawRecord.fromJson` are the
/// API; this is how they spell things.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../formats/format_exceptions.dart';
import '../../formats/image/png_decoder.dart';

/// [value] as JSON can hold it: a NaN or an infinity as the strings `"NaN"`,
/// `"Infinity"` and `"-Infinity"`, which `jsonEncode` would otherwise
/// refuse, and which are what somebody opens a capture to find.
Object captureNumber(double value) => value.isNaN
    ? 'NaN'
    : value == double.infinity
    ? 'Infinity'
    : value == double.negativeInfinity
    ? '-Infinity'
    : value;

/// [captureNumber] read back, or null for anything that is not a number.
double? readCaptureNumber(Object? value) => switch (value) {
  final num n => n.toDouble(),
  'NaN' => double.nan,
  'Infinity' => double.infinity,
  '-Infinity' => double.negativeInfinity,
  _ => null,
};

/// [value] with every double made safe for `jsonEncode`, through maps and
/// lists — for the free-form state of a draw.
Object? captureValue(Object? value) => switch (value) {
  /// A number of whatever unit the draw's state holds it in.
  final double d => captureNumber(d),
  final Map<Object?, Object?> map => <String, Object?>{
    for (final MapEntry(:key, :value) in map.entries)
      '$key': captureValue(value),
  },
  final List<Object?> list => <Object?>[for (final v in list) captureValue(v)],
  _ => value,
};

/// The name of the shape [length] floats most likely are, as a uniform:
/// `mat4` for sixteen, `vec4` for four and so on, `float[n]` otherwise.
/// A guess from the count alone, which is all a journal keeps; the decoded
/// form says it is one by keeping the raw values beside it.
String uniformShape(int length) => switch (length) {
  1 => 'float',
  2 => 'vec2',
  3 => 'vec3',
  4 => 'vec4',
  9 => 'mat3',
  16 => 'mat4',
  _ => 'float[$length]',
};

/// One uniform, decoded: its shape, its values, and for a matrix its
/// columns, each number through [captureNumber].
Map<String, Object?> decodeUniform(List<double> values) {
  final shape = uniformShape(values.length);
  final columns = switch (shape) {
    'mat3' => 3,
    'mat4' => 4,
    _ => 0,
  };
  return <String, Object?>{
    'type': shape,
    'values': <Object>[for (final v in values) captureNumber(v)],
    if (columns > 0)
      'columns': <List<Object>>[
        for (var c = 0; c < columns; c++)
          <Object>[
            for (var r = 0; r < columns; r++)
              captureNumber(values[c * columns + r]),
          ],
      ],
  };
}

/// A uniform from either form a capture may hold it in: the decoded map
/// [decodeUniform] writes, or a bare list of numbers.
List<double>? readUniform(Object? value) {
  final raw = switch (value) {
    {'values': final List<Object?> values} => values,
    final List<Object?> values => values,
    _ => null,
  };
  if (raw == null) return null;
  final read = <double>[for (final v in raw) readCaptureNumber(v) ?? 0.0];
  return List<double>.unmodifiable(read);
}

/// Floats as base64 of their little-endian bytes: exact, NaNs and all.
String encodeFloats(Float32List floats) {
  final bytes = ByteData(floats.length * 4);
  for (var i = 0; i < floats.length; i++) {
    bytes.setFloat32(i * 4, floats[i], Endian.little);
  }
  return base64Encode(bytes.buffer.asUint8List());
}

/// [encodeFloats] read back, or null when it is not that.
Float32List? decodeFloats(Object? value) {
  if (value is! String) return null;
  final Uint8List bytes;
  try {
    bytes = base64Decode(value);
  } on FormatException {
    return null;
  }
  if (bytes.length % 4 != 0) return null;
  final view = ByteData.sublistView(bytes);
  return Float32List.fromList(<double>[
    for (var i = 0; i < bytes.length; i += 4) view.getFloat32(i, Endian.little),
  ]);
}

/// [rgba] scaled down to fit [maxSide] on its longer side, each new pixel
/// the mean of the ones it covers, or the pixels as they are when they fit.
({int width, int height, Uint8List rgba}) shrinkRgba(
  Uint8List rgba,
  int width,
  int height,
  int maxSide,
) {
  final longest = width > height ? width : height;
  if (longest <= maxSide || maxSide < 1) {
    return (width: width, height: height, rgba: rgba);
  }
  final outWidth = (width * maxSide / longest).round().clamp(1, maxSide);
  final outHeight = (height * maxSide / longest).round().clamp(1, maxSide);
  final out = Uint8List(outWidth * outHeight * 4);
  for (var y = 0; y < outHeight; y++) {
    final y0 = y * height ~/ outHeight;
    final y1 = ((y + 1) * height ~/ outHeight).clamp(y0 + 1, height);
    for (var x = 0; x < outWidth; x++) {
      final x0 = x * width ~/ outWidth;
      final x1 = ((x + 1) * width ~/ outWidth).clamp(x0 + 1, width);
      final count = (y1 - y0) * (x1 - x0);
      for (var channel = 0; channel < 4; channel++) {
        var sum = 0;
        for (var sy = y0; sy < y1; sy++) {
          for (var sx = x0; sx < x1; sx++) {
            sum += rgba[(sy * width + sx) * 4 + channel];
          }
        }
        out[(y * outWidth + x) * 4 + channel] = (sum / count).round();
      }
    }
  }
  return (width: outWidth, height: outHeight, rgba: out);
}

/// [rgba] as a PNG, eight-bit RGBA, rows from the top, the bytes as they
/// are — a premultiplied readback stays premultiplied, so reading it back
/// gives the same bytes.
///
/// Stored rather than compressed, as `flutter3d_cpu`'s writer does and for
/// its reason: no `dart:io` on the web, and a debugging file that is a
/// little larger is a better trade than a compressor to vendor.
Uint8List encodeCapturePng(Uint8List rgba, int width, int height) {
  final stride = width * 4 + 1;
  final raw = Uint8List(height * stride);
  for (var y = 0; y < height; y++) {
    raw.setRange(
      y * stride + 1,
      y * stride + stride,
      Uint8List.sublistView(rgba, y * width * 4, (y + 1) * width * 4),
    );
  }
  final out = BytesBuilder(copy: false)
    ..add(const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, Uint8List data) {
    final body = Uint8List(4 + data.length)
      ..setRange(0, 4, ascii.encode(type))
      ..setRange(4, 4 + data.length, data);
    out
      ..add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List())
      ..add(body)
      ..add((ByteData(4)..setUint32(0, _crc32(body))).buffer.asUint8List());
  }

  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8)
    ..setUint8(9, 6);
  chunk('IHDR', header.buffer.asUint8List());
  chunk('IDAT', _storedZlib(raw));
  chunk('IEND', Uint8List(0));
  return out.toBytes();
}

/// A PNG back to its RGBA bytes, or null when it is not one this reader
/// takes.
({int width, int height, Uint8List rgba})? decodeCapturePng(Object? value) {
  if (value is! String) return null;
  final Uint8List bytes;
  try {
    bytes = base64Decode(value);
  } on FormatException {
    return null;
  }
  // An image the file damaged is left out, as the capture's doc promises,
  // rather than failing the whole file.
  final DecodedImage decoded;
  try {
    decoded = decodePng(bytes);
  } on ImageFormatException {
    return null;
  }
  return (width: decoded.width, height: decoded.height, rgba: decoded.rgba);
}

final List<int> _crcTable = List<int>.generate(256, (int n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(Uint8List bytes) =>
    bytes.fold(
      0xFFFFFFFF,
      (int c, int byte) => _crcTable[(c ^ byte) & 0xFF] ^ (c >> 8),
    ) ^
    0xFFFFFFFF;

/// Deflate's stored blocks in a zlib wrapper, with the Adler-32 at the end.
Uint8List _storedZlib(Uint8List data) {
  final out = BytesBuilder(copy: false)..add(const <int>[0x78, 0x01]);
  var offset = 0;
  do {
    final length = data.length - offset < 65535 ? data.length - offset : 65535;
    final last = offset + length >= data.length ? 1 : 0;
    final complement = 0xFFFF - length;
    out
      ..addByte(last)
      ..add(<int>[length & 0xFF, (length >> 8) & 0xFF])
      ..add(<int>[complement & 0xFF, (complement >> 8) & 0xFF])
      ..add(Uint8List.sublistView(data, offset, offset + length));
    offset += length;
  } while (offset < data.length);
  final (a, b) = data.fold((1, 0), ((int, int) sums, int byte) {
    final a = (sums.$1 + byte) % 65521;
    return (a, (sums.$2 + a) % 65521);
  });
  out.add((ByteData(4)..setUint32(0, (b << 16) | a)).buffer.asUint8List());
  return out.toBytes();
}
