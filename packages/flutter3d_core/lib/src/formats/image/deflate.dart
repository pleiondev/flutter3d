/// [zlibCompress]: a real, RFC 1951 (DEFLATE) compressing writer — the half
/// `inflate.dart` has no reverse of, and `mat-12`'s own reason to exist:
/// `cpu_png.dart` writes DEFLATE's *stored* block type, which is nothing to
/// unpack rather than something compressed, and nowhere else in this
/// repository writes a real one.
///
/// **LZ77 over a fixed Huffman block, not dynamic.** A dynamic block earns
/// its own header (`HLIT`/`HDIST`/`HCLEN`, a run-length-coded table of code
/// lengths) by adapting the code lengths to what the data actually
/// contains; fixed Huffman's own lengths (RFC 1951 §3.2.6, the ones
/// `inflate.dart` already decodes against) are the specification's fixed
/// table, so nothing has to be built or written for it. The compression
/// this file gets is almost entirely LZ77's own — a long, exact match
/// costs a handful of bits regardless of which Huffman table encodes it —
/// which is enough for `mat-12`'s own acceptance (a gradient under a
/// quarter of its stored size) without the added weight of a second
/// encoding scheme.
///
/// **Deliberately not `package:archive`.** The plan's own Г6 names that as
/// one option and leaves the row without the "Закрыт" mark every actually
/// decided question in the same table carries elsewhere — read as a
/// default worth reconsidering, not a closed choice. `archive`'s own
/// current release pulls in `posix`, a native binding this package's own
/// "resolves without the Flutter SDK, everywhere that SDK resolves"
/// boundary has no room for; rolling this compressor by hand, the same
/// call `mat-09n` already made for the decoder, keeps that boundary intact
/// and reuses the fixed-Huffman tables this package already carries for
/// reading.
library;

import 'dart:collection';
import 'dart:typed_data';

/// [data] compressed as a complete zlib (RFC 1950) stream — the two-byte
/// header, one final DEFLATE block, and the trailing Adler-32
/// [_adler32] computes over the uncompressed bytes, which every real
/// decoder checks even though this package's own [zlibInflate] does not.
Uint8List zlibCompress(Uint8List data) {
  final deflated = _deflate(data);
  final out = BytesBuilder();
  out.add(const <int>[0x78, 0x9C]); // CMF/FLG: deflate, 32K window, level 2
  out.add(deflated);
  final adler = _adler32(data);
  out.add(<int>[
    (adler >> 24) & 0xFF,
    (adler >> 16) & 0xFF,
    (adler >> 8) & 0xFF,
    adler & 0xFF,
  ]);
  return out.toBytes();
}

int _adler32(Uint8List data) {
  var a = 1;
  var b = 0;
  for (final byte in data) {
    a = (a + byte) % 65521;
    b = (b + a) % 65521;
  }
  return (b << 16) | a;
}

/// [data] as one final, fixed-Huffman DEFLATE block (RFC 1951 §3.2.6): a
/// 3-bit header (`BFINAL=1`, `BTYPE=01`), then a run of literal and
/// length/distance symbols from [_lz77], each written most-significant-bit
/// first the way every Huffman code in this format is (§3.1.1), and a
/// trailing end-of-block symbol.
///
/// One block for the whole input rather than several: DEFLATE's own block
/// size limit is on the *stored* block type only (`cpu_png.dart`'s own,
/// 65 535 bytes a block) — a compressed block has none, so there is
/// nothing splitting the input would buy here.
Uint8List _deflate(Uint8List data) {
  final writer = _BitWriter();
  writer.bitsLsbFirst(1, 1); // BFINAL
  writer.bitsLsbFirst(1, 2); // BTYPE = 01
  for (final token in _lz77(data)) {
    switch (token) {
      case _Literal(:final byte):
        _writeLiteral(writer, byte);
      case _Match(:final length, :final distance):
        _writeLength(writer, length);
        _writeDistance(writer, distance);
    }
  }
  _writeLiteral(writer, 256); // end of block
  return writer.finish();
}

void _writeLiteral(_BitWriter writer, int symbol) {
  if (symbol < 144) {
    writer.huffmanCode(0x30 + symbol, 8);
  } else if (symbol < 256) {
    writer.huffmanCode(0x190 + (symbol - 144), 9);
  } else if (symbol < 280) {
    writer.huffmanCode(symbol - 256, 7);
  } else {
    writer.huffmanCode(0xC0 + (symbol - 280), 8);
  }
}

void _writeLength(_BitWriter writer, int length) {
  var index = _lengthBase.length - 1;
  for (var i = 0; i < _lengthBase.length; i++) {
    if (_lengthBase[i] > length) {
      index = i - 1;
      break;
    }
  }
  _writeLiteral(writer, 257 + index);
  writer.bitsLsbFirst(length - _lengthBase[index], _lengthExtra[index]);
}

void _writeDistance(_BitWriter writer, int distance) {
  var index = _distanceBase.length - 1;
  for (var i = 0; i < _distanceBase.length; i++) {
    if (_distanceBase[i] > distance) {
      index = i - 1;
      break;
    }
  }
  writer.huffmanCode(index, 5); // fixed distance codes: 5 bits, code == index
  writer.bitsLsbFirst(distance - _distanceBase[index], _distanceExtra[index]);
}

/// RFC 1951 §3.2.5's own tables — copied from `inflate.dart` rather than
/// shared, since a private top-level name in one library file is invisible
/// to another even in the same package, and these thirty numbers apiece
/// are the specification's, not this file's own to keep in sync by hand
/// with a private import that does not exist.
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

sealed class _Token {}

final class _Literal extends _Token {
  _Literal(this.byte);
  final int byte;
}

final class _Match extends _Token {
  _Match(this.length, this.distance);
  final int length;
  final int distance;
}

const int _minMatch = 3;
const int _maxMatch = 258;
const int _maxDistance = 32768;

/// The longest hash chain [_lz77] follows at one position before giving up
/// and emitting a literal — bounds the worst case on a file with many
/// colliding 3-byte runs (a flat-coloured region, the common case a texture
/// actually has) without changing what a shorter search finds on ordinary
/// data, since ties are broken by the *first, nearest* candidate either way.
const int _maxChainLength = 128;

/// [data] as a run of [_Literal]/[_Match] tokens — a hash-chain LZ77 match
/// finder (the shape `zlib`'s own reference encoder uses, though not its
/// code): every 3-byte position is hashed into [_ByteBucket]'s own chain of
/// earlier positions sharing that hash, walked nearest-first up to
/// [_maxChainLength] deep, greedy on the longest match found within
/// [_maxDistance] and [_maxMatch].
List<_Token> _lz77(Uint8List data) {
  final tokens = <_Token>[];
  final head = HashMap<int, int>();
  final prev = Int32List(data.length)..fillRange(0, data.length, -1);

  int hashAt(int i) =>
      (data[i] << 16 | data[i + 1] << 8 | data[i + 2]) & 0xFFFFF;

  var i = 0;
  while (i < data.length) {
    var bestLength = 0;
    var bestDistance = 0;
    if (i + _minMatch <= data.length) {
      final h = hashAt(i);
      var candidate = head[h] ?? -1;
      var chain = 0;
      while (candidate >= 0 &&
          chain < _maxChainLength &&
          i - candidate <= _maxDistance) {
        var length = 0;
        final remaining = data.length - i;
        final maxLen = remaining < _maxMatch ? remaining : _maxMatch;
        while (length < maxLen &&
            data[candidate + length] == data[i + length]) {
          length++;
        }
        if (length > bestLength) {
          bestLength = length;
          bestDistance = i - candidate;
          if (length >= _maxMatch) break;
        }
        candidate = prev[candidate];
        chain++;
      }
      prev[i] = head[h] ?? -1;
      head[h] = i;
    }

    if (bestLength >= _minMatch) {
      tokens.add(_Match(bestLength, bestDistance));
      // Every position the match covers still needs its own hash entry, so
      // a later, nearer match starting inside it can still be found.
      final end = i + bestLength;
      for (var j = i + 1; j < end && j + _minMatch <= data.length; j++) {
        final h = hashAt(j);
        prev[j] = head[h] ?? -1;
        head[h] = j;
      }
      i = end;
    } else {
      tokens.add(_Literal(data[i]));
      i++;
    }
  }
  return tokens;
}

/// Bits packed DEFLATE's own two ways — plain fields least-significant-bit
/// first, Huffman codes most-significant-bit first — the write side of the
/// same convention `inflate_test.dart`'s own `_BitWriter` already builds
/// malformed streams with, here writing real ones instead.
final class _BitWriter {
  final BytesBuilder _bytes = BytesBuilder();
  int _current = 0;
  int _filled = 0;

  void _writeBit(int bit) {
    _current |= (bit & 1) << _filled;
    _filled++;
    if (_filled == 8) {
      _bytes.addByte(_current);
      _current = 0;
      _filled = 0;
    }
  }

  void bitsLsbFirst(int value, int count) {
    for (var i = 0; i < count; i++) {
      _writeBit((value >> i) & 1);
    }
  }

  void huffmanCode(int code, int length) {
    for (var i = length - 1; i >= 0; i--) {
      _writeBit((code >> i) & 1);
    }
  }

  Uint8List finish() {
    if (_filled > 0) _bytes.addByte(_current);
    return _bytes.toBytes();
  }
}
