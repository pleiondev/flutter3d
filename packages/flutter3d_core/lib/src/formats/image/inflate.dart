/// [inflate]: a DEFLATE (RFC 1951) decompressor behind a zlib (RFC 1950)
/// wrapper — the half of `mat-09n` that PNG's own `IDAT` chunk needs, and
/// the only thing in this file. No compressor lives here; nothing in this
/// repository has ever needed to write a compressed stream — `cpu_png.dart`
/// writes DEFLATE's own *stored* block type, which decompresses to itself
/// with nothing to unpack, and that is deliberately the cheapest way to
/// write a PNG this repository has wanted so far.
///
/// **Every table is RFC 1951's own**, copied rather than derived, the same
/// choice `texture_info.dart` already made for KTX2's `vkFormat` numbers
/// across a different boundary: the fixed Huffman lengths (§3.2.6), the
/// length and distance extra-bit tables (§3.2.5) and the code-length
/// alphabet's own bit order (§3.2.7) are exactly the numbers the
/// specification prints, not values worked out from first principles.
library;

import 'dart:typed_data';

/// [zlib] decompressed — the zlib header (RFC 1950) stripped and read, and
/// the raw DEFLATE stream behind it inflated. Returns null rather than
/// throwing on anything short, malformed, or naming a compression method or
/// a block type this does not decode — the same "no size to answer with"
/// convention [imageDimensions] already uses for a truncated header, so a
/// caller has one shape to check either way.
Uint8List? zlibInflate(Uint8List zlib) {
  if (zlib.length < 6) return null;
  final cmf = zlib[0];
  final flg = zlib[1];
  if ((cmf & 0x0F) != 8) return null; // not the "deflate" method
  if ((cmf * 256 + flg) % 31 != 0) return null; // the header's own checksum
  if ((flg & 0x20) != 0) return null; // FDICT: a preset dictionary, unread
  return inflate(Uint8List.sublistView(zlib, 2, zlib.length - 4));
}

/// A raw DEFLATE stream, with no zlib wrapper around it — [zlibInflate]'s
/// own worker, public because a caller that already has the wrapper
/// stripped (or none at all, as in a raw `.deflate` stream) should not have
/// to fake one back on to call this.
///
/// Returns null on anything this reader cannot make sense of: a reserved
/// block type, a stored block whose length and its own complement disagree,
/// a Huffman code with no match in fifteen bits, a back-reference reaching
/// before the start of the output. Every one of those is a malformed or
/// truncated stream, and this makes the same choice [zlibInflate] does
/// about what a malformed stream is worth answering.
Uint8List? inflate(Uint8List data) {
  final reader = _BitReader(data);
  final out = _ByteSink();
  try {
    while (true) {
      final isFinal = reader.readBits(1) == 1;
      final type = reader.readBits(2);
      switch (type) {
        case 0:
          if (!_stored(reader, out)) return null;
        case 1:
          if (!_huffmanBlock(reader, out, _fixedLiteral, _fixedDistance)) {
            return null;
          }
        case 2:
          final tables = _dynamicTables(reader);
          if (tables == null) return null;
          if (!_huffmanBlock(reader, out, tables.$1, tables.$2)) return null;
        default:
          return null; // type 3 is reserved
      }
      if (isFinal) break;
    }
  } on _Truncated {
    return null;
  }
  return out.toBytes();
}

/// Thrown by [_BitReader] on reading past the end — caught once, at the top
/// of [inflate], rather than checked after every read.
final class _Truncated implements Exception {
  const _Truncated();
}

/// Bits out of [bytes], least-significant bit of each byte first — the
/// order every DEFLATE field but a Huffman code itself is packed in
/// (RFC 1951 §3.1.1).
final class _BitReader {
  _BitReader(this.bytes);

  final Uint8List bytes;
  int _pos = 0;
  int _bitBuf = 0;
  int _bitCount = 0;

  int readBits(int n) {
    var value = 0;
    for (var i = 0; i < n; i++) {
      if (_bitCount == 0) {
        if (_pos >= bytes.length) throw const _Truncated();
        _bitBuf = bytes[_pos++];
        _bitCount = 8;
      }
      value |= (_bitBuf & 1) << i;
      _bitBuf >>= 1;
      _bitCount--;
    }
    return value;
  }

  /// One bit, for a Huffman code — [_CanonicalHuffman.decode] builds the
  /// code's own value most-significant-bit first from these, which is the
  /// one field DEFLATE packs the other way round (RFC 1951 §3.1.1).
  int readBit() => readBits(1);

  /// Drops whatever is left of the current byte, for a stored block's own
  /// length header, which starts on a byte boundary.
  void alignToByte() {
    _bitCount = 0;
  }

  int readByte() {
    alignToByte();
    if (_pos >= bytes.length) throw const _Truncated();
    return bytes[_pos++];
  }
}

/// Output bytes, growable, with the one operation DEFLATE's own
/// back-references need: copying already-written bytes forward, which can
/// overlap its own source — RFC 1951's length/distance pair is a run-length
/// encoding as much as a dictionary reference, and a distance shorter than
/// the length being copied is the ordinary case for a run of one repeated
/// byte, not a special one.
final class _ByteSink {
  Uint8List _buffer = Uint8List(4096);
  int _length = 0;

  void _grow(int extra) {
    if (_length + extra <= _buffer.length) return;
    var next = _buffer.length * 2;
    while (next < _length + extra) {
      next *= 2;
    }
    final grown = Uint8List(next)..setRange(0, _length, _buffer);
    _buffer = grown;
  }

  void addByte(int byte) {
    _grow(1);
    _buffer[_length++] = byte;
  }

  /// Copies [length] bytes from [distance] bytes behind the write cursor to
  /// the write cursor, one at a time — never `List.copyRange` over the
  /// whole span, because a [distance] smaller than [length] means the
  /// source overlaps the destination the copy is still writing into, and a
  /// bulk copy reads the source before this byte's own write can feed it.
  void copyBack(int distance, int length) {
    if (distance > _length) throw const _Truncated();
    _grow(length);
    final from = _length - distance;
    for (var i = 0; i < length; i++) {
      _buffer[_length + i] = _buffer[from + i];
    }
    _length += length;
  }

  Uint8List toBytes() => Uint8List.sublistView(_buffer, 0, _length);
}

bool _stored(_BitReader reader, _ByteSink out) {
  final low = reader.readByte();
  final high = reader.readByte();
  final len = low | (high << 8);
  final nLow = reader.readByte();
  final nHigh = reader.readByte();
  final nLen = nLow | (nHigh << 8);
  if (len != (nLen ^ 0xFFFF)) return false;
  for (var i = 0; i < len; i++) {
    out.addByte(reader.readByte());
  }
  return true;
}

/// A canonical Huffman code, built from [lengths] — RFC 1951 §3.2.2's own
/// algorithm: how many codes each length has, the first code of each
/// length in order, then one code per symbol handed out in symbol order.
/// A symbol whose own length is 0 is unused and never decoded.
final class _CanonicalHuffman {
  factory _CanonicalHuffman(List<int> lengths) {
    var maxLength = 0;
    for (final length in lengths) {
      if (length > maxLength) maxLength = length;
    }
    final countPerLength = List<int>.filled(maxLength + 1, 0);
    for (final length in lengths) {
      if (length > 0) countPerLength[length]++;
    }
    final nextCode = List<int>.filled(maxLength + 1, 0);
    var code = 0;
    for (var bits = 1; bits <= maxLength; bits++) {
      code = (code + countPerLength[bits - 1]) << 1;
      nextCode[bits] = code;
    }
    final byLength = <int, Map<int, int>>{};
    for (var symbol = 0; symbol < lengths.length; symbol++) {
      final length = lengths[symbol];
      if (length == 0) continue;
      final table = byLength.putIfAbsent(length, () => <int, int>{});
      table[nextCode[length]] = symbol;
      nextCode[length]++;
    }
    return _CanonicalHuffman._(byLength, maxLength);
  }

  _CanonicalHuffman._(this._byLength, this._maxLength);

  final Map<int, Map<int, int>> _byLength;
  final int _maxLength;

  int decode(_BitReader reader) {
    var code = 0;
    for (var length = 1; length <= _maxLength; length++) {
      code = (code << 1) | reader.readBit();
      final symbol = _byLength[length]?[code];
      if (symbol != null) return symbol;
    }
    throw const _Truncated();
  }
}

/// RFC 1951 §3.2.6: the fixed literal/length lengths — 0–143 at 8 bits,
/// 144–255 at 9, 256–279 at 7, 280–287 at 8 — and the fixed distance
/// lengths, all 30 codes at 5 bits (only 0–29 are ever valid distances;
/// 30 and 31 exist as code points and decode as a malformed stream).
final _CanonicalHuffman _fixedLiteral = _CanonicalHuffman(<int>[
  for (var i = 0; i < 144; i++) 8,
  for (var i = 144; i < 256; i++) 9,
  for (var i = 256; i < 280; i++) 7,
  for (var i = 280; i < 288; i++) 8,
]);

final _CanonicalHuffman _fixedDistance = _CanonicalHuffman(
  List<int>.filled(32, 5),
);

/// RFC 1951 §3.2.5: length code 257–285 → (base length, extra bits).
const List<int> _lengthBase = <int>[
  3,
  4,
  5,
  6,
  7,
  8,
  9,
  10,
  11,
  13,
  15,
  17,
  19,
  23,
  27,
  31,
  35,
  43,
  51,
  59,
  67,
  83,
  99,
  115,
  131,
  163,
  195,
  227,
  258,
];
const List<int> _lengthExtra = <int>[
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  1,
  1,
  1,
  1,
  2,
  2,
  2,
  2,
  3,
  3,
  3,
  3,
  4,
  4,
  4,
  4,
  5,
  5,
  5,
  5,
  0,
];

/// RFC 1951 §3.2.5: distance code 0–29 → (base distance, extra bits).
const List<int> _distanceBase = <int>[
  1,
  2,
  3,
  4,
  5,
  7,
  9,
  13,
  17,
  25,
  33,
  49,
  65,
  97,
  129,
  193,
  257,
  385,
  513,
  769,
  1025,
  1537,
  2049,
  3073,
  4097,
  6145,
  8193,
  12289,
  16385,
  24577,
];
const List<int> _distanceExtra = <int>[
  0,
  0,
  0,
  0,
  1,
  1,
  2,
  2,
  3,
  3,
  4,
  4,
  5,
  5,
  6,
  6,
  7,
  7,
  8,
  8,
  9,
  9,
  10,
  10,
  11,
  11,
  12,
  12,
  13,
  13,
];

bool _huffmanBlock(
  _BitReader reader,
  _ByteSink out,
  _CanonicalHuffman literal,
  _CanonicalHuffman distance,
) {
  while (true) {
    final symbol = literal.decode(reader);
    if (symbol < 256) {
      out.addByte(symbol);
      continue;
    }
    if (symbol == 256) return true; // end of block
    final lengthIndex = symbol - 257;
    if (lengthIndex >= _lengthBase.length) return false;
    final length =
        _lengthBase[lengthIndex] + reader.readBits(_lengthExtra[lengthIndex]);
    final distanceSymbol = distance.decode(reader);
    if (distanceSymbol >= _distanceBase.length) return false;
    final dist =
        _distanceBase[distanceSymbol] +
        reader.readBits(_distanceExtra[distanceSymbol]);
    out.copyBack(dist, length);
  }
}

/// The order code-length codes 0–18 are themselves given a bit-length in, in
/// a dynamic block's own header — RFC 1951 §3.2.7's own table, not a sorted
/// or otherwise derivable order.
const List<int> _codeLengthOrder = <int>[
  16,
  17,
  18,
  0,
  8,
  7,
  9,
  6,
  10,
  5,
  11,
  4,
  12,
  3,
  13,
  2,
  14,
  1,
  15,
];

/// The two Huffman tables a dynamic block's own header describes — the
/// literal/length table first, the distance table second — read the way
/// RFC 1951 §3.2.7 lays the header out: `HLIT`/`HDIST`/`HCLEN` counts, the
/// code-length alphabet's own lengths in [_codeLengthOrder]'s order, then
/// the literal/length and distance lengths themselves, run-length coded
/// through that alphabet (16 repeats the previous length, 17 and 18 repeat
/// a zero — three different repeat counts and extra-bit widths, all named
/// literally rather than derived).
(_CanonicalHuffman, _CanonicalHuffman)? _dynamicTables(_BitReader reader) {
  final literalCount = reader.readBits(5) + 257;
  final distanceCount = reader.readBits(5) + 1;
  final codeLengthCount = reader.readBits(4) + 4;

  final codeLengthLengths = List<int>.filled(19, 0);
  for (var i = 0; i < codeLengthCount; i++) {
    codeLengthLengths[_codeLengthOrder[i]] = reader.readBits(3);
  }
  final codeLengthTable = _CanonicalHuffman(codeLengthLengths);

  final lengths = List<int>.filled(literalCount + distanceCount, 0);
  var at = 0;
  while (at < lengths.length) {
    final symbol = codeLengthTable.decode(reader);
    switch (symbol) {
      case < 16:
        lengths[at] = symbol;
        at++;
      case 16:
        if (at == 0) return null;
        final repeat = reader.readBits(2) + 3;
        final previous = lengths[at - 1];
        for (var i = 0; i < repeat && at < lengths.length; i++) {
          lengths[at++] = previous;
        }
      case 17:
        final repeat = reader.readBits(3) + 3;
        at += repeat;
      case 18:
        final repeat = reader.readBits(7) + 11;
        at += repeat;
      default:
        return null;
    }
  }
  if (at != lengths.length) return null;

  return (
    _CanonicalHuffman(lengths.sublist(0, literalCount)),
    _CanonicalHuffman(lengths.sublist(literalCount)),
  );
}
