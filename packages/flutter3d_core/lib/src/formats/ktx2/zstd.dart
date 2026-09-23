/// [zstdDecode]: a Zstandard (RFC 8878) decompressor, in Dart — `gfx-78n`.
///
/// **Why this is here rather than reached for.** `Ktx2Texture.parse` refused
/// every supercompression scheme but Basis-LZ, and `toktx --zcmp` — the way a
/// modern toolchain writes a KTX2 — produces exactly one of the refused ones.
/// Nothing in this package's dependency list decompresses it: `flutter3d_core`
/// depends on `flutter3d_hardware` and `vector_math` and nothing else, which is
/// a property worth keeping, and the only Dart zstd implementations are
/// bindings to the C library, which a web build cannot load. `inflate.dart`
/// made the same call for DEFLATE one directory over and for the same reason.
///
/// No compressor lives here. Nothing in this repository writes a zstd stream,
/// and a compressor is the half that needs tuning rather than the half that
/// needs to be right.
///
/// **Every table below is the specification's own**, copied rather than
/// derived — the predefined distributions of §3.1.1.3.2.2, the baselines and
/// extra-bit counts of the literal-length, match-length and offset codes. That
/// is `inflate.dart`'s choice for RFC 1951's tables, and it holds here for the
/// same reason: a number worked out from first principles is a number that can
/// be worked out differently.
///
/// What it does **not** implement, named so the gap is not mistaken for
/// coverage: dictionaries, multi-frame concatenation beyond reading frames in
/// sequence, and the optional content checksum, which is parsed past and not
/// verified. A KTX2 level is one frame, written by a tool that has no reason to
/// use a dictionary, so none of the three has appeared.
library;

import 'dart:typed_data';

/// The magic number at the head of a zstd frame, little-endian.
const int kZstdMagic = 0xFD2FB528;

/// Whether [bytes] starts with a zstd frame.
bool isZstd(Uint8List bytes) =>
    bytes.length >= 4 &&
    bytes[0] == 0x28 &&
    bytes[1] == 0xB5 &&
    bytes[2] == 0x2F &&
    bytes[3] == 0xFD;

/// [bytes] decompressed, or null if it is not a zstd stream this decodes.
///
/// Null rather than an exception, matching [zlibInflate]'s convention one
/// directory over: a caller that has just sniffed a container has one shape to
/// check either way, and a corrupt texture should not take a frame down.
///
/// [sizeHint] is the decompressed length when the container knows it — a KTX2
/// level index carries one — which lets the output be allocated once instead of
/// grown. It is a hint: a stream that decodes to a different length still
/// returns, at its real length.
Uint8List? zstdDecode(Uint8List bytes, {int? sizeHint}) {
  try {
    return _Decoder(bytes, sizeHint).run();
  } on _ZstdError {
    return null;
  } on RangeError {
    // A truncated stream indexes past its own end somewhere unpredictable.
    // Catching it here rather than bounds-checking every read keeps the hot
    // loops free of tests that only ever fire on a corrupt file.
    return null;
  }
}

class _ZstdError implements Exception {
  const _ZstdError(this.message);
  final String message;
  @override
  String toString() => 'zstd: $message';
}

Never _fail(String message) => throw _ZstdError(message);

// ---------------------------------------------------------------------------
// Bit readers
// ---------------------------------------------------------------------------

/// Bits in stream order, least significant first.
///
/// What the FSE table descriptions and the Huffman weight header are written
/// in. Unlike [_BackwardBits] below, this one runs the same direction as the
/// bytes.
final class _ForwardBits {
  _ForwardBits(this._bytes, this._start, this._end);

  final Uint8List _bytes;
  final int _start;
  final int _end;
  int _bit = 0;

  /// How many whole bytes have been consumed, rounded up — where the next
  /// section starts once a table description ends mid-byte.
  int get bytesConsumed => (_bit + 7) >> 3;

  int peek(int count) {
    if (count == 0) return 0;
    var value = 0;
    for (var i = 0; i < count; i++) {
      final index = _start + ((_bit + i) >> 3);
      // Past the end reads as zero. A well-formed table description never
      // needs it; a malformed one would otherwise throw from three call sites.
      final byte = index < _end ? _bytes[index] : 0;
      value |= ((byte >> ((_bit + i) & 7)) & 1) << i;
    }
    return value;
  }

  void skip(int count) => _bit += count;

  int read(int count) {
    final value = peek(count);
    _bit += count;
    return value;
  }
}

/// Bits from the end of the stream towards its start, most significant first.
///
/// **The direction is the format's, not a choice.** zstd writes its FSE and
/// Huffman streams backwards so that a decoder can read the states it needs
/// before the symbols that follow them. The final byte carries a single set bit
/// marking where the data stops; everything above it is padding, which is why
/// the constructor hunts for it instead of starting at bit 63.
final class _BackwardBits {
  _BackwardBits(this._bytes, int start, int end) : _base = start {
    if (end <= start) _fail('empty backward bitstream');
    final last = _bytes[end - 1];
    if (last == 0) _fail('backward bitstream ends in a zero byte');
    var highest = 7;
    while ((last & (1 << highest)) == 0) {
      highest--;
    }
    // The marker bit itself is not data.
    _bit = (end - 1 - start) * 8 + highest - 1;
  }

  final Uint8List _bytes;
  final int _base;
  int _bit = 0;

  /// How many data bits are still unread.
  int get remaining => _bit + 1;

  int read(int count) {
    if (count == 0) return 0;
    var value = 0;
    for (var i = 0; i < count; i++) {
      final p = _bit - i;
      if (p < 0) {
        // Reading past the start is zero-padding, which the format relies on
        // for the last sequence of a block.
        value <<= 1;
        continue;
      }
      value = (value << 1) | ((_bytes[_base + (p >> 3)] >> (p & 7)) & 1);
    }
    _bit -= count;
    return value;
  }
}

// ---------------------------------------------------------------------------
// FSE
// ---------------------------------------------------------------------------

final class _FseTable {
  _FseTable(this.accuracyLog)
    : symbol = Uint8List(1 << accuracyLog),
      bits = Uint8List(1 << accuracyLog),
      next = Uint16List(1 << accuracyLog);

  final int accuracyLog;
  final Uint8List symbol;
  final Uint8List bits;
  final Uint16List next;

  /// A table for a symbol that always decodes to itself, costing no bits —
  /// what an `RLE` compression mode means.
  factory _FseTable.rle(int value) {
    final table = _FseTable(0);
    table.symbol[0] = value;
    table.bits[0] = 0;
    table.next[0] = 0;
    return table;
  }
}

int _highestBit(int value) {
  var bit = 0;
  var v = value;
  while (v > 1) {
    v >>= 1;
    bit++;
  }
  return bit;
}

/// Builds the decoding table from normalized counts, §4.1.1.
///
/// The spread is the specification's own walk — a step of
/// `size/2 + size/8 + 3` around the table, skipping the tail where the
/// probability-below-one symbols were parked — and it has to be exactly this
/// walk, because the encoder used it too.
_FseTable _buildFse(Int16List counts, int maxSymbol, int accuracyLog) {
  final table = _FseTable(accuracyLog);
  final size = 1 << accuracyLog;
  final mask = size - 1;
  var highThreshold = size - 1;

  // A count of -1 means "less than one in the table": those symbols get the
  // high end, one slot each, and are not part of the walk below.
  final effective = Int16List(maxSymbol + 1);
  for (var s = 0; s <= maxSymbol; s++) {
    if (counts[s] == -1) {
      table.symbol[highThreshold--] = s;
      effective[s] = 1;
    } else {
      effective[s] = counts[s];
    }
  }

  final step = (size >> 1) + (size >> 3) + 3;
  var position = 0;
  for (var s = 0; s <= maxSymbol; s++) {
    if (counts[s] == -1) continue;
    for (var i = 0; i < counts[s]; i++) {
      table.symbol[position] = s;
      do {
        position = (position + step) & mask;
      } while (position > highThreshold);
    }
  }
  if (position != 0) _fail('FSE spread did not close the cycle');

  final nextState = Int32List(maxSymbol + 1);
  for (var s = 0; s <= maxSymbol; s++) {
    nextState[s] = effective[s];
  }
  for (var u = 0; u < size; u++) {
    final s = table.symbol[u];
    final value = nextState[s]++;
    table.bits[u] = accuracyLog - _highestBit(value);
    table.next[u] = (value << table.bits[u]) - size;
  }
  return table;
}

/// Reads a normalized-count table description, §4.1.1.
///
/// Returns the table and advances [bits] past the description, which ends on a
/// byte boundary from the caller's point of view even though it did not end on
/// one here.
_FseTable _readFseTable(_ForwardBits bits, int maxSymbol, int maxAccuracy) {
  final accuracyLog = bits.read(4) + 5;
  if (accuracyLog > maxAccuracy) {
    _fail('FSE accuracy log $accuracyLog above the $maxAccuracy allowed here');
  }

  final counts = Int16List(maxSymbol + 1);
  var remaining = (1 << accuracyLog) + 1;
  var threshold = 1 << accuracyLog;
  var nbBits = accuracyLog + 1;
  var symbol = 0;
  var previousZero = false;

  while (remaining > 1 && symbol <= maxSymbol) {
    if (previousZero) {
      var runEnd = symbol;
      // Runs of zero counts are written in groups: 0xFFFF means "twenty-four
      // more and keep reading", then pairs of bits up to three at a time.
      while (bits.peek(16) == 0xFFFF) {
        runEnd += 24;
        bits.skip(16);
      }
      while (bits.peek(2) == 3) {
        runEnd += 3;
        bits.skip(2);
      }
      runEnd += bits.read(2);
      while (symbol < runEnd && symbol <= maxSymbol) {
        counts[symbol++] = 0;
      }
      previousZero = false;
      if (symbol > maxSymbol) break;
    }

    final max = (2 * threshold - 1) - remaining;
    int count;
    if (bits.peek(nbBits - 1) < max) {
      count = bits.read(nbBits - 1);
    } else {
      count = bits.read(nbBits);
      if (count >= threshold) count -= max;
    }
    // One is subtracted so that a stored zero can mean "below one in the
    // table" — the -1 the spread above parks at the high end.
    count -= 1;
    remaining -= count < 0 ? -count : count;
    counts[symbol++] = count;
    previousZero = count == 0;
    while (remaining < threshold) {
      nbBits--;
      threshold >>= 1;
    }
  }
  if (remaining != 1) _fail('FSE counts do not sum to the table size');

  return _buildFse(counts, maxSymbol, accuracyLog);
}

/// A table built from a distribution the specification prints, for the modes
/// that name one instead of describing it.
_FseTable _predefined(List<int> counts, int accuracyLog) {
  final normalized = Int16List(counts.length);
  for (var i = 0; i < counts.length; i++) {
    normalized[i] = counts[i];
  }
  return _buildFse(normalized, counts.length - 1, accuracyLog);
}

// The three predefined distributions, §3.1.1.3.2.2. `-1` is the
// probability-below-one marker the builder parks at the top of the table.
const List<int> _predefLiteralLength = <int>[
  4, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, //
  2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 2, 1, 1, 1, 1, 1, //
  -1, -1, -1, -1,
];
// **The tail of this one is where a wrong table hides.** It has to run out of
// ones at code 36 and be `-1` from 37 on. A version that kept going to 43
// still summed to the table size — the `-1` entries take a slot each, so
// trading ones for them balances — so it built without complaint and decoded
// code 45 where the stream meant 47, which came out as a match 751 bytes long
// instead of 2998. The sum is not the check; the shape is.
const List<int> _predefMatchLength = <int>[
  1, 4, 3, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, //
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, //
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, -1, -1, //
  -1, -1, -1, -1, -1,
];
const List<int> _predefOffset = <int>[
  1, 1, 1, 1, 1, 1, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, //
  1, 1, 1, 1, 1, 1, 1, 1, -1, -1, -1, -1, -1,
];

// Baselines and extra bits, §3.1.1.3.2.1.1.
const List<int> _literalLengthBase = <int>[
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, //
  16, 18, 20, 22, 24, 28, 32, 40, 48, 64, 128, 256, 512, 1024, 2048, 4096, //
  8192, 16384, 32768, 65536,
];
const List<int> _literalLengthBits = <int>[
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, //
  1, 1, 1, 1, 2, 2, 3, 3, 4, 6, 7, 8, 9, 10, 11, 12, //
  13, 14, 15, 16,
];
const List<int> _matchLengthBase = <int>[
  3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, //
  19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, //
  35, 37, 39, 41, 43, 47, 51, 59, 67, 83, 99, 131, 259, 515, 1027, 2051, //
  4099, 8195, 16387, 32771, 65539,
];
const List<int> _matchLengthBits = <int>[
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, //
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, //
  1, 1, 1, 1, 2, 2, 3, 3, 4, 4, 5, 7, 8, 9, 10, 11, //
  12, 13, 14, 15, 16,
];

// ---------------------------------------------------------------------------
// Huffman
// ---------------------------------------------------------------------------

final class _HuffmanTable {
  _HuffmanTable(this.maxBits)
    : symbol = Uint8List(1 << maxBits),
      bits = Uint8List(1 << maxBits);

  final int maxBits;
  final Uint8List symbol;
  final Uint8List bits;
}

/// Turns per-symbol weights into a flat decoding table, §4.2.1.
///
/// The last symbol's weight is not stored: it is whatever makes the total a
/// power of two, which is a property of a complete prefix code and is why the
/// arithmetic below can recover it rather than read it.
_HuffmanTable _buildHuffman(Uint8List weights, int count) {
  var totalWeight = 0;
  for (var i = 0; i < count; i++) {
    if (weights[i] > 0) totalWeight += 1 << (weights[i] - 1);
  }
  if (totalWeight == 0) _fail('Huffman weights are all zero');

  final maxBits = _highestBit(totalWeight) + 1;
  final left = (1 << maxBits) - totalWeight;
  if (left <= 0 || (left & (left - 1)) != 0) {
    _fail('Huffman weights do not complete to a power of two');
  }
  final all = Uint8List(count + 1);
  all.setRange(0, count, weights);
  all[count] = _highestBit(left) + 1;

  final table = _HuffmanTable(maxBits);
  // **Ranked by weight ascending, which is the rarest symbols first.** A
  // weight of `w` occupies `2^(w-1)` entries and costs `maxBits + 1 - w` bits,
  // so ordering by weight and ordering by code length are reverses of each
  // other — and getting that backwards builds a table that is a valid prefix
  // code, fills exactly, and decodes every symbol to the wrong one. It did:
  // the first version here ran the loop over code lengths and the text fixture
  // came out wrong at byte zero with no other symptom.
  final rankStart = Int32List(maxBits + 2);
  for (var i = 0; i <= count; i++) {
    if (all[i] > 0) rankStart[all[i]]++;
  }
  var start = 0;
  for (var weight = 1; weight <= maxBits; weight++) {
    final width = rankStart[weight] << (weight - 1);
    rankStart[weight] = start;
    start += width;
  }
  if (start != (1 << maxBits)) _fail('Huffman table did not fill');

  for (var i = 0; i <= count; i++) {
    final weight = all[i];
    if (weight == 0) continue;
    final width = 1 << (weight - 1);
    final at = rankStart[weight];
    for (var j = 0; j < width; j++) {
      table.symbol[at + j] = i;
      table.bits[at + j] = maxBits + 1 - weight;
    }
    rankStart[weight] = at + width;
  }
  return table;
}

/// Reads the weight header and returns the table it describes, §4.2.1.1.
///
/// Returns the table and how many bytes of [bytes] it took.
({_HuffmanTable table, int size}) _readHuffmanTable(
  Uint8List bytes,
  int start,
  int end,
) {
  if (start >= end) _fail('Huffman description is empty');
  final header = bytes[start];

  if (header >= 128) {
    // Weights written directly, four bits each, two to a byte.
    final count = header - 127;
    final size = 1 + ((count + 1) >> 1);
    if (start + size > end) _fail('direct Huffman weights run past the end');
    final weights = Uint8List(count);
    for (var i = 0; i < count; i++) {
      final byte = bytes[start + 1 + (i >> 1)];
      weights[i] = (i & 1) == 0 ? byte >> 4 : byte & 15;
    }
    return (table: _buildHuffman(weights, count), size: size);
  }

  // Weights themselves FSE-coded, with two interleaved states.
  final compressedSize = header;
  final from = start + 1;
  final to = from + compressedSize;
  if (to > end) _fail('FSE Huffman weights run past the end');

  final describe = _ForwardBits(bytes, from, to);
  final table = _readFseTable(describe, 255, 6);
  final streamStart = from + describe.bytesConsumed;
  final stream = _BackwardBits(bytes, streamStart, to);

  var state1 = stream.read(table.accuracyLog);
  var state2 = stream.read(table.accuracyLog);
  final weights = Uint8List(256);
  var count = 0;
  // **Two states alternating, and the last weight comes from the state that
  // did not run the stream out.** When the bits are gone both states still
  // name a symbol, and the one belonging to the *other* state is the final
  // weight — dropping it was the second thing wrong here, and it shows up as a
  // Huffman table one symbol short, which still builds and still decodes, into
  // the wrong bytes.
  while (count < 254) {
    weights[count++] = table.symbol[state1];
    if (stream.remaining < table.bits[state1]) {
      weights[count++] = table.symbol[state2];
      break;
    }
    state1 = table.next[state1] + stream.read(table.bits[state1]);

    weights[count++] = table.symbol[state2];
    if (stream.remaining < table.bits[state2]) {
      weights[count++] = table.symbol[state1];
      break;
    }
    state2 = table.next[state2] + stream.read(table.bits[state2]);
  }
  return (table: _buildHuffman(weights, count), size: 1 + compressedSize);
}

// ---------------------------------------------------------------------------
// The frame
// ---------------------------------------------------------------------------

final class _Decoder {
  _Decoder(this.bytes, this.sizeHint);

  final Uint8List bytes;
  final int? sizeHint;

  late Uint8List _out;
  int _written = 0;

  /// The Huffman table the previous block left behind, for a `Treeless`
  /// literals section to reuse. Null until a block ships one.
  _HuffmanTable? _literalTable;

  /// The three FSE tables a block may tell the next one to repeat.
  _FseTable? _literalLengthTable;
  _FseTable? _offsetTable;
  _FseTable? _matchLengthTable;

  /// The three repeat offsets, which live for the whole **frame** rather than
  /// the block.
  ///
  /// A block that carries them over is the ordinary case — that is what makes
  /// them worth having — and resetting them per block is a bug that hides
  /// completely until a stream is longer than one block. It did: the first
  /// version declared this inside the sequences reader, every fixture under
  /// 128 KiB passed, and the one file past that size went wrong at byte
  /// 131073, which is the second byte of the second block.
  final List<int> _repeats = <int>[1, 4, 8];

  void _grow(int extra) {
    if (_written + extra <= _out.length) return;
    var size = _out.isEmpty ? 1024 : _out.length;
    while (size < _written + extra) {
      size *= 2;
    }
    _out = Uint8List(size)..setRange(0, _written, _out);
  }

  /// The most [sizeHint] is trusted for up front. The hint comes from the
  /// container, not the stream, and a KTX2 level index can name four gigabytes
  /// in front of a handful of compressed bytes; past this the output grows as
  /// the stream actually produces it.
  static const int _maxPreallocation = 1 << 26;

  Uint8List run() {
    final hint = sizeHint;
    _out = Uint8List(
      hint != null && hint >= 0 && hint <= _maxPreallocation ? hint : 1024,
    );
    var at = 0;
    var frames = 0;
    while (at + 4 <= bytes.length) {
      final magic =
          bytes[at] |
          (bytes[at + 1] << 8) |
          (bytes[at + 2] << 16) |
          (bytes[at + 3] << 24);
      if (magic != kZstdMagic) {
        // A skippable frame is magic 0x184D2A5? with a four-byte length after
        // it; anything else ends the stream rather than being guessed at.
        if ((magic & 0xFFFFFFF0) == 0x184D2A50) {
          final size = ByteData.sublistView(
            bytes,
            at + 4,
            at + 8,
          ).getUint32(0, Endian.little);
          at += 8 + size;
          continue;
        }
        if (frames == 0) _fail('not a zstd frame');
        break;
      }
      at = _frame(at + 4);
      frames++;
    }
    if (frames == 0) _fail('no frame found');
    return Uint8List.sublistView(_out, 0, _written);
  }

  /// One frame, starting just past its magic. Returns where it ended.
  int _frame(int start) {
    var at = start;
    final descriptor = bytes[at++];
    final contentSizeFlag = descriptor >> 6;
    final singleSegment = (descriptor >> 5) & 1;
    final hasChecksum = (descriptor >> 2) & 1;
    final dictionaryIdFlag = descriptor & 3;
    if ((descriptor >> 3) & 1 != 0) _fail('reserved frame header bit is set');

    if (singleSegment == 0) at++; // window descriptor

    const dictionaryBytes = <int>[0, 1, 2, 4];
    at += dictionaryBytes[dictionaryIdFlag];
    if (dictionaryIdFlag != 0) _fail('dictionaries are not supported');

    if (contentSizeFlag != 0 || singleSegment != 0) {
      final sizes = <int>[1, 2, 4, 8];
      at += sizes[contentSizeFlag];
    }

    while (true) {
      final header = bytes[at] | (bytes[at + 1] << 8) | (bytes[at + 2] << 16);
      at += 3;
      final last = header & 1;
      final type = (header >> 1) & 3;
      final size = header >> 3;

      switch (type) {
        case 0:
          _grow(size);
          _out.setRange(_written, _written + size, bytes, at);
          _written += size;
          at += size;
        case 1:
          _grow(size);
          _out.fillRange(_written, _written + size, bytes[at]);
          _written += size;
          at += 1;
        case 2:
          _compressedBlock(at, at + size);
          at += size;
        default:
          _fail('reserved block type');
      }
      if (last == 1) break;
    }

    // Parsed past rather than verified — see the library comment.
    if (hasChecksum == 1) at += 4;
    return at;
  }

  void _compressedBlock(int start, int end) {
    final literals = _literalsSection(start, end);
    _sequences(literals.next, end, literals.bytes);
  }

  // -------------------------------------------------------------------------
  // Literals
  // -------------------------------------------------------------------------

  ({Uint8List bytes, int next}) _literalsSection(int start, int end) {
    var at = start;
    final first = bytes[at];
    final type = first & 3;
    final sizeFormat = (first >> 2) & 3;

    if (type == 0 || type == 1) {
      final int size;
      switch (sizeFormat) {
        case 0:
        case 2:
          size = first >> 3;
          at += 1;
        case 1:
          size = (first >> 4) | (bytes[at + 1] << 4);
          at += 2;
        default:
          size = (first >> 4) | (bytes[at + 1] << 4) | (bytes[at + 2] << 12);
          at += 3;
      }
      if (type == 0) {
        final out = Uint8List.sublistView(bytes, at, at + size);
        return (bytes: Uint8List.fromList(out), next: at + size);
      }
      return (
        bytes: Uint8List(size)..fillRange(0, size, bytes[at]),
        next: at + 1,
      );
    }

    // Huffman, either with its own table or reusing the last one.
    final int regenerated;
    final int compressed;
    final int streams;
    switch (sizeFormat) {
      case 0:
        streams = 1;
        regenerated = (first >> 4) | ((bytes[at + 1] & 0x3F) << 4);
        compressed = (bytes[at + 1] >> 6) | (bytes[at + 2] << 2);
        at += 3;
      case 1:
        streams = 4;
        regenerated = (first >> 4) | ((bytes[at + 1] & 0x3F) << 4);
        compressed = (bytes[at + 1] >> 6) | (bytes[at + 2] << 2);
        at += 3;
      case 2:
        streams = 4;
        regenerated =
            (first >> 4) | (bytes[at + 1] << 4) | ((bytes[at + 2] & 3) << 12);
        compressed = (bytes[at + 2] >> 2) | (bytes[at + 3] << 6);
        at += 4;
      default:
        streams = 4;
        regenerated =
            (first >> 4) |
            (bytes[at + 1] << 4) |
            ((bytes[at + 2] & 0x3F) << 12);
        compressed =
            (bytes[at + 2] >> 6) | (bytes[at + 3] << 2) | (bytes[at + 4] << 10);
        at += 5;
    }

    var streamStart = at;
    final streamEnd = at + compressed;
    if (type == 2) {
      final read = _readHuffmanTable(bytes, at, streamEnd);
      _literalTable = read.table;
      streamStart = at + read.size;
    }
    final table = _literalTable;
    if (table == null) _fail('treeless literals with no table to reuse');

    final out = Uint8List(regenerated);
    if (streams == 1) {
      _huffmanStream(table, streamStart, streamEnd, out, 0, regenerated);
    } else {
      // Four streams with a six-byte jump table, so that a decoder can run
      // them in parallel. Read one after another here; the sizes are what the
      // table is for either way.
      final j = streamStart;
      final size1 = bytes[j] | (bytes[j + 1] << 8);
      final size2 = bytes[j + 2] | (bytes[j + 3] << 8);
      final size3 = bytes[j + 4] | (bytes[j + 5] << 8);
      var from = j + 6;
      final quarter = (regenerated + 3) >> 2;
      final sizes = <int>[size1, size2, size3];
      var written = 0;
      for (var i = 0; i < 4; i++) {
        final to = i == 3 ? streamEnd : from + sizes[i];
        final want = i == 3 ? regenerated - written : quarter;
        _huffmanStream(table, from, to, out, written, want);
        written += want;
        from = to;
      }
    }
    return (bytes: out, next: streamEnd);
  }

  void _huffmanStream(
    _HuffmanTable table,
    int start,
    int end,
    Uint8List out,
    int at,
    int count,
  ) {
    if (count <= 0) return;
    final stream = _BackwardBits(bytes, start, end);
    final mask = (1 << table.maxBits) - 1;
    var written = 0;
    // A rolling window rather than a peek, because the reader consumes what it
    // reads: the code takes as many bits as its entry says and the rest are put
    // back by only advancing that far.
    var window = stream.read(table.maxBits);
    while (written < count) {
      final index = window & mask;
      final symbol = table.symbol[index];
      final used = table.bits[index];
      out[at + written++] = symbol;
      if (written >= count) break;
      window = ((window << used) | stream.read(used)) & mask;
    }
  }

  // -------------------------------------------------------------------------
  // Sequences
  // -------------------------------------------------------------------------

  void _sequences(int start, int end, Uint8List literals) {
    var at = start;
    if (at >= end) {
      // No sequences section at all: the literals are the whole block.
      _emitLiterals(literals, 0, literals.length);
      return;
    }

    var count = bytes[at++];
    if (count == 0) {
      _emitLiterals(literals, 0, literals.length);
      return;
    }
    if (count < 128) {
      // as is
    } else if (count < 255) {
      count = ((count - 128) << 8) + bytes[at++];
    } else {
      count = (bytes[at] | (bytes[at + 1] << 8)) + 0x7F00;
      at += 2;
    }

    final modes = bytes[at++];
    final literalMode = (modes >> 6) & 3;
    final offsetMode = (modes >> 4) & 3;
    final matchMode = (modes >> 2) & 3;

    final describe = _ForwardBits(bytes, at, end);
    _literalLengthTable = _sequenceTable(
      literalMode,
      _literalLengthTable,
      describe,
      at,
      end,
      35,
      9,
      _predefLiteralLength,
      6,
    );
    at += describe.bytesConsumed;
    // Each table description starts on a byte boundary of its own, so the
    // reader is rebuilt rather than carried across. An RLE table takes one
    // byte and no bits at all, which is why the helper reports its own size.
    final describeOffset = _ForwardBits(bytes, at, end);
    _offsetTable = _sequenceTable(
      offsetMode,
      _offsetTable,
      describeOffset,
      at,
      end,
      31,
      8,
      _predefOffset,
      5,
    );
    at += describeOffset.bytesConsumed;
    final describeMatch = _ForwardBits(bytes, at, end);
    _matchLengthTable = _sequenceTable(
      matchMode,
      _matchLengthTable,
      describeMatch,
      at,
      end,
      52,
      9,
      _predefMatchLength,
      6,
    );
    at += describeMatch.bytesConsumed;

    final literalTable = _literalLengthTable!;
    final offsetTable = _offsetTable!;
    final matchTable = _matchLengthTable!;

    final stream = _BackwardBits(bytes, at, end);
    var literalState = stream.read(literalTable.accuracyLog);
    var offsetState = stream.read(offsetTable.accuracyLog);
    var matchState = stream.read(matchTable.accuracyLog);

    var literalAt = 0;

    for (var i = 0; i < count; i++) {
      final offsetCode = offsetTable.symbol[offsetState];
      final matchCode = matchTable.symbol[matchState];
      final literalCode = literalTable.symbol[literalState];

      // The order is the format's: offset's extra bits first, then match
      // length's, then literal length's.
      final offsetExtra = offsetCode == 0 ? 0 : stream.read(offsetCode);
      final matchExtra = stream.read(_matchLengthBits[matchCode]);
      final literalExtra = stream.read(_literalLengthBits[literalCode]);

      final literalLength = _literalLengthBase[literalCode] + literalExtra;
      final matchLength = _matchLengthBase[matchCode] + matchExtra;
      final rawOffset = (1 << offsetCode) + offsetExtra;

      final int offset;
      if (offsetCode <= 2 && rawOffset <= 3) {
        // The three repeat offsets, whose meaning shifts when a sequence has
        // no literals — §3.1.1.3.2.1.2, and the one place a plain reading of
        // the table is wrong.
        var index = rawOffset - 1;
        if (literalLength == 0) index += 1;
        if (index == 3) {
          offset = _repeats[0] - 1;
          _repeats
            ..[2] = _repeats[1]
            ..[1] = _repeats[0]
            ..[0] = offset;
        } else if (index == 0) {
          offset = _repeats[0];
        } else {
          offset = _repeats[index];
          if (index == 1) {
            _repeats[1] = _repeats[0];
          } else {
            _repeats
              ..[2] = _repeats[1]
              ..[1] = _repeats[0];
          }
          _repeats[0] = offset;
        }
      } else {
        offset = rawOffset - 3;
        _repeats
          ..[2] = _repeats[1]
          ..[1] = _repeats[0]
          ..[0] = offset;
      }

      _emitLiterals(literals, literalAt, literalAt + literalLength);
      literalAt += literalLength;
      _emitMatch(offset, matchLength);

      if (i + 1 < count) {
        literalState =
            literalTable.next[literalState] +
            stream.read(literalTable.bits[literalState]);
        matchState =
            matchTable.next[matchState] +
            stream.read(matchTable.bits[matchState]);
        offsetState =
            offsetTable.next[offsetState] +
            stream.read(offsetTable.bits[offsetState]);
      }
    }

    // Whatever the last sequence did not consume is copied out as it is.
    _emitLiterals(literals, literalAt, literals.length);
  }

  _FseTable _sequenceTable(
    int mode,
    _FseTable? previous,
    _ForwardBits describe,
    int start,
    int end,
    int maxSymbol,
    int maxAccuracy,
    List<int> predefined,
    int predefinedLog,
  ) {
    switch (mode) {
      case 0:
        return _predefined(predefined, predefinedLog);
      case 1:
        final table = _FseTable.rle(bytes[start]);
        describe.skip(8);
        return table;
      case 2:
        return _readFseTable(describe, maxSymbol, maxAccuracy);
      default:
        if (previous == null) _fail('repeat mode with no previous table');
        return previous;
    }
  }

  void _emitLiterals(Uint8List literals, int from, int to) {
    if (to <= from) return;
    final length = to - from;
    _grow(length);
    _out.setRange(_written, _written + length, literals, from);
    _written += length;
  }

  void _emitMatch(int offset, int length) {
    if (offset <= 0 || offset > _written) {
      _fail('match offset $offset reaches before the start of the output');
    }
    _grow(length);
    var from = _written - offset;
    // Byte at a time, because a match may overlap itself — an offset of one
    // repeating a single byte is the ordinary case, and `setRange` with
    // overlapping source and destination would copy the pre-existing bytes.
    for (var i = 0; i < length; i++) {
      _out[_written++] = _out[from++];
    }
  }
}
