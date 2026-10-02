/// Writing CPU pixels out as an image.
///
/// It belongs here rather than in a tool, because this is the one backend whose
/// pixels are already in ordinary memory — the round trip the other two need a
/// device for. Looking at what it drew should not require a window.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// [rgba] as a PNG: 8-bit RGBA, one IDAT, rows from the top.
///
/// Written out rather than taken as a dependency, because a package that pulled
/// in an image library for one call would have a heavier dependency graph than
/// its job. Eleven lines of that is the deflate, which stores rather than
/// compresses — the output is a few percent larger than it needs to be and is
/// read by everything, which is the right trade for a debugging aid.
///
/// Pure Dart, with no `dart:io`: this package is reachable from a web build,
/// and `ZLibEncoder` is not.
Uint8List encodePng(Uint8List rgba, int width, int height) {
  // Filter byte 0 (none) in front of each row, which is what the format wants
  // and what makes this short.
  final raw = Uint8List(height * (width * 4 + 1));
  for (var y = 0; y < height; y++) {
    raw[y * (width * 4 + 1)] = 0;
    raw.setRange(
      y * (width * 4 + 1) + 1,
      y * (width * 4 + 1) + 1 + width * 4,
      rgba,
      y * width * 4,
    );
  }

  final out = BytesBuilder();
  out.add(<int>[137, 80, 78, 71, 13, 10, 26, 10]);

  void chunk(String type, List<int> data) {
    final body = <int>[...ascii.encode(type), ...data];
    out.add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List());
    out.add(body);
    out.add((ByteData(4)..setUint32(0, _crc32(body))).buffer.asUint8List());
  }

  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 6); // colour type: RGBA
  chunk('IHDR', header.buffer.asUint8List());
  chunk('IDAT', _storedZlib(raw));
  chunk('IEND', const <int>[]);
  return out.toBytes();
}

/// A PNG written a strip of rows at a time — `N8`'s photo of any size.
///
/// **One IDAT chunk per strip**, which the format allows outright: the
/// chunks' contents are concatenated into one zlib stream before anything
/// reads them. So each strip becomes stored deflate blocks in a chunk of its
/// own and goes to [sink] as soon as it arrives, and the writer keeps only
/// the running Adler-32 between strips — never the picture.
///
/// **The last block is not known to be last until [close]**, and deflate
/// marks the final block in its header. Rather than hold back a block on the
/// chance it is the end, every block is written as not-final and [close]
/// adds an empty final block, five bytes, which every decoder reads.
///
/// Not [encodePng] rewritten on top of this: that one writes a single IDAT,
/// and every golden in the tree was written by it. Byte-identical files are
/// worth more than one fewer function.
final class PngStripWriter {
  /// Writes the signature and the header to [sink] at once.
  PngStripWriter({
    required this.width,
    required this.height,
    required this.sink,
  }) {
    if (width <= 0 || height <= 0 || width > 0x7FFFFFFF ~/ 4) {
      throw ArgumentError('A PNG of ${width}x$height cannot be written.');
    }
    sink(Uint8List.fromList(const <int>[137, 80, 78, 71, 13, 10, 26, 10]));
    final header = ByteData(13)
      ..setUint32(0, width)
      ..setUint32(4, height)
      ..setUint8(8, 8)
      ..setUint8(9, 6);
    _chunk('IHDR', header.buffer.asUint8List());
  }

  final int width;
  final int height;

  /// Where the bytes go, in order.
  final void Function(Uint8List bytes) sink;

  int _rowsWritten = 0;
  int _adlerA = 1;
  int _adlerB = 0;
  bool _headerWritten = false;

  /// Adds [rows] rows of RGBA, top first, `width × rows × 4` bytes.
  void addRows(Uint8List rgba, int rows) {
    if (rgba.length < width * rows * 4) {
      throw ArgumentError(
        '$rows rows of $width pixels are ${width * rows * 4} bytes, and '
        '${rgba.length} were given.',
      );
    }
    if (_rowsWritten + rows > height) {
      throw StateError(
        'The PNG is $height rows tall; $_rowsWritten are written and $rows '
        'more would run past the bottom.',
      );
    }
    if (rows == 0) return;
    final stride = width * 4 + 1;
    final raw = Uint8List(rows * stride);
    for (var y = 0; y < rows; y++) {
      raw.setRange(y * stride + 1, (y + 1) * stride, rgba, y * width * 4);
    }
    for (final byte in raw) {
      _adlerA = (_adlerA + byte) % 65521;
      _adlerB = (_adlerB + _adlerA) % 65521;
    }
    final out = BytesBuilder(copy: false);
    if (!_headerWritten) {
      out.add(const <int>[0x78, 0x01]);
      _headerWritten = true;
    }
    for (var offset = 0; offset < raw.length; offset += 65535) {
      final length = math.min(65535, raw.length - offset);
      _storedBlock(out, Uint8List.sublistView(raw, offset, offset + length));
    }
    _chunk('IDAT', out.toBytes());
    _rowsWritten += rows;
  }

  /// Ends the stream and the file. Every row has to be in.
  void close() {
    if (_rowsWritten != height) {
      throw StateError(
        'The PNG is $height rows tall and only $_rowsWritten were added; a '
        'file closed now would be read as damaged.',
      );
    }
    final out = BytesBuilder(copy: false);
    if (!_headerWritten) out.add(const <int>[0x78, 0x01]);
    out.add(const <int>[1, 0, 0, 0xFF, 0xFF]);
    out.add(
      (ByteData(
        4,
      )..setUint32(0, (_adlerB << 16) | _adlerA)).buffer.asUint8List(),
    );
    _chunk('IDAT', out.toBytes());
    _chunk('IEND', Uint8List(0));
  }

  static void _storedBlock(BytesBuilder out, Uint8List data) {
    final n = 0xFFFF - data.length;
    out
      ..add(<int>[0, data.length & 0xFF, (data.length >> 8) & 0xFF])
      ..add(<int>[n & 0xFF, (n >> 8) & 0xFF])
      ..add(data);
  }

  void _chunk(String type, Uint8List data) {
    final body = Uint8List(data.length + 4)
      ..setRange(0, 4, ascii.encode(type))
      ..setRange(4, data.length + 4, data);
    sink((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List());
    sink(body);
    sink((ByteData(4)..setUint32(0, _crc32(body))).buffer.asUint8List());
  }
}

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final byte in bytes) {
    c = _crcTable[(c ^ byte) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// A zlib stream that stores rather than compresses.
///
/// Deflate's uncompressed block type, which every decoder must support: a
/// two-byte header, then blocks of at most 65535 bytes each announcing their
/// length and its complement, then Adler-32 of the input. Whole thing is
/// shorter than choosing and vendoring a compressor.
Uint8List _storedZlib(Uint8List data) {
  final out = BytesBuilder();
  out.add(<int>[0x78, 0x01]);
  var offset = 0;
  while (offset < data.length || data.isEmpty) {
    final length = data.length - offset < 65535 ? data.length - offset : 65535;
    final last = offset + length >= data.length ? 1 : 0;
    out.addByte(last);
    out.add(<int>[length & 0xFF, (length >> 8) & 0xFF]);
    final n = 0xFFFF - length;
    out.add(<int>[n & 0xFF, (n >> 8) & 0xFF]);
    out.add(Uint8List.sublistView(data, offset, offset + length));
    offset += length;
    if (last == 1) break;
  }
  var a = 1;
  var b = 0;
  for (final byte in data) {
    a = (a + byte) % 65521;
    b = (b + a) % 65521;
  }
  out.add((ByteData(4)..setUint32(0, (b << 16) | a)).buffer.asUint8List());
  return out.toBytes();
}
