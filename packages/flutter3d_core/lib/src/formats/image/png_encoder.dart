/// [encodeCompressedPng]: plain RGBA8 written out as a real, compressed PNG —
/// `mat-12`'s own writing half, built on [zlibCompress].
///
/// **Adaptive per-row filtering, the thing `cpu_png.dart`'s own writer
/// skips.** That file always writes filter type `None` — correct, and the
/// reason its own doc comment gives is that its deflate is the *stored*
/// block type with nothing for a filter to help compress. This one has a
/// real compressor behind it, so which filter a row gets changes how well
/// [zlibCompress] can compress it: [_bestFilter] tries all five (RFC 2083
/// §6.2 — None/Sub/Up/Average/Paeth) and keeps whichever leaves the
/// smallest sum of absolute (signed) byte values, the same heuristic every
/// real PNG encoder uses since an exact answer means compressing five
/// candidates per row to find out.
library;

import 'dart:typed_data';

import 'deflate.dart';

const List<int> _signature = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
];

/// [rgba] ([width] × [height], four bytes a pixel, top row first — the same
/// shape [DecodedImage.rgba] reads back) written as an 8-bit RGBA PNG.
Uint8List encodeCompressedPng(int width, int height, Uint8List rgba) {
  const bpp = 4;
  final rowBytes = width * bpp;
  final filtered = Uint8List(height * (rowBytes + 1));
  final previous = Uint8List(rowBytes);
  final current = Uint8List(rowBytes);
  var out = 0;
  for (var y = 0; y < height; y++) {
    current.setRange(0, rowBytes, rgba, y * rowBytes);
    final (filterType, row) = _bestFilter(current, previous, bpp);
    filtered[out++] = filterType;
    filtered.setRange(out, out + rowBytes, row);
    out += rowBytes;
    previous.setRange(0, rowBytes, current);
  }

  final compressed = zlibCompress(filtered);
  final result = BytesBuilder();
  result.add(_signature);
  final ihdr = ByteData(13)
    ..setUint32(0, width, Endian.big)
    ..setUint32(4, height, Endian.big)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 6) // colour type: RGBA
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  _writeChunk(result, 'IHDR', ihdr.buffer.asUint8List());
  _writeChunk(result, 'IDAT', compressed);
  _writeChunk(result, 'IEND', const <int>[]);
  return result.toBytes();
}

void _writeChunk(BytesBuilder out, String type, List<int> data) {
  out.add(
    (ByteData(4)..setUint32(0, data.length, Endian.big)).buffer.asUint8List(),
  );
  final body = <int>[..._ascii(type), ...data];
  out.add(body.sublist(0, 4));
  out.add(data);
  final crc = _crc32(body);
  out.add((ByteData(4)..setUint32(0, crc, Endian.big)).buffer.asUint8List());
}

List<int> _ascii(String s) => s.codeUnits;

/// [current], filtered five ways against [previous] (the already-written
/// row above it, or an implicit all-zero row for `y == 0`) and scored by
/// [_score] — the filter type and the filtered bytes that scored best.
(int, Uint8List) _bestFilter(Uint8List current, Uint8List previous, int bpp) {
  final candidates = <(int, Uint8List)>[
    (0, current), // None
    (1, _sub(current, bpp)),
    (2, _up(current, previous)),
    (3, _average(current, previous, bpp)),
    (4, _paeth(current, previous, bpp)),
  ];
  var best = candidates.first;
  var bestScore = _score(best.$2);
  for (final candidate in candidates.skip(1)) {
    final score = _score(candidate.$2);
    if (score < bestScore) {
      best = candidate;
      bestScore = score;
    }
  }
  return best;
}

/// The minimum-sum-of-absolute-differences heuristic (RFC 2083 §"Filter
/// selection"): each byte read as signed (`>127` counts as `256 - value`),
/// summed — not an exact prediction of what the compressor will do with a
/// row, but the one every real PNG encoder uses because the exact answer
/// costs a full compression per candidate.
int _score(Uint8List row) {
  var total = 0;
  for (final b in row) {
    total += b < 128 ? b : 256 - b;
  }
  return total;
}

Uint8List _sub(Uint8List current, int bpp) {
  final out = Uint8List(current.length);
  for (var x = 0; x < current.length; x++) {
    final left = x >= bpp ? current[x - bpp] : 0;
    out[x] = (current[x] - left) & 0xFF;
  }
  return out;
}

Uint8List _up(Uint8List current, Uint8List previous) {
  final out = Uint8List(current.length);
  for (var x = 0; x < current.length; x++) {
    out[x] = (current[x] - previous[x]) & 0xFF;
  }
  return out;
}

Uint8List _average(Uint8List current, Uint8List previous, int bpp) {
  final out = Uint8List(current.length);
  for (var x = 0; x < current.length; x++) {
    final left = x >= bpp ? current[x - bpp] : 0;
    out[x] = (current[x] - ((left + previous[x]) >> 1)) & 0xFF;
  }
  return out;
}

Uint8List _paeth(Uint8List current, Uint8List previous, int bpp) {
  final out = Uint8List(current.length);
  for (var x = 0; x < current.length; x++) {
    final left = x >= bpp ? current[x - bpp] : 0;
    final above = previous[x];
    final aboveLeft = x >= bpp ? previous[x - bpp] : 0;
    out[x] = (current[x] - _paethPredictor(left, above, aboveLeft)) & 0xFF;
  }
  return out;
}

int _paethPredictor(int a, int b, int c) {
  final p = a + b - c;
  final pa = (p - a).abs();
  final pb = (p - b).abs();
  final pc = (p - c).abs();
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
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
