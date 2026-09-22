/// The bit reader and canonical-Huffman decoder Basis Universal's ETC1S
/// codec builds everything else on.
///
/// Ported line-for-line from `bitwise_decoder` and `huffman_decoding_table`
/// in `KhronosGroup/KTX-Software`'s
/// `external/basis_universal/transcoder/basisu_transcoder_internal.h` — not
/// redesigned from the general idea of canonical Huffman decoding, because
/// the exact tie-breaking in the tree construction and the one-bit overlap
/// between the fast-lookup index and the tree walk (`rev_code >>=
/// (fastLookupBits - 1)`, not `fastLookupBits`) are load-bearing: a decoder
/// that reconstructs "an equivalent" canonical code from the same code
/// lengths is not guaranteed to assign the same codes bit-for-bit unless it
/// builds them by the same rule the encoder used.
library;

import 'dart:typed_data';

import '../ktx2_format.dart';

/// Constants from `basisu.h`'s Huffman table format — the same DEFLATE-style
/// scheme (a Huffman-coded table of code lengths, with run-length escapes for
/// the zeros dynamic tables are mostly made of) reused for every table this
/// codec reads.
abstract final class _Huffman {
  static const int fastLookupBits = 10;
  static const int maxSupportedInternalCodeSize = 31;
  static const int maxSymsLog2 = 14;
  static const int totalCodelengthCodes = 21;
  static const int smallZeroRunCode = 17;
  static const int smallZeroRunSizeMin = 3;
  static const int smallZeroRunExtraBits = 3;
  static const int bigZeroRunCode = 18;
  static const int bigZeroRunSizeMin = 11;
  static const int bigZeroRunExtraBits = 7;
  static const int smallRepeatCode = 19;
  static const int smallRepeatSizeMin = 3;
  static const int smallRepeatExtraBits = 2;
  static const int bigRepeatCode = 20;
  static const int bigRepeatSizeMin = 7;
  static const int bigRepeatExtraBits = 7;

  /// The order code-length-code sizes arrive in — short-run and repeat codes
  /// first (they matter most for a mostly-zero table), then the sixteen
  /// literal lengths zigzagging out from the middle.
  static const List<int> sortedCodelengthCodes = [
    smallZeroRunCode,
    bigZeroRunCode,
    smallRepeatCode,
    bigRepeatCode,
    0,
    8,
    7,
    9,
    6,
    0xA,
    5,
    0xB,
    4,
    0xC,
    3,
    0xD,
    2,
    0xE,
    1,
    0xF,
    0x10,
  ];
}

/// A canonical Huffman code, built from an array of per-symbol code lengths.
///
/// Two lookup paths, matching the encoder's own fast/slow split: codes of
/// [_Huffman.fastLookupBits] or fewer bits resolve in one table read; longer
/// codes walk a small binary tree encoded as negative indices into the same
/// kind of table. Both are populated by [init].
final class HuffmanDecodingTable {
  Uint8List _codeSizes = Uint8List(0);
  List<int> _lookup = const [];
  List<int> _tree = const [];

  bool get isValid => _codeSizes.isNotEmpty;

  /// Builds the tables [BitwiseDecoder.decodeHuffman] reads.
  ///
  /// Throws [Ktx2FormatException] for code lengths that cannot form a valid
  /// prefix code — a corrupt or truncated table, not a recoverable case.
  void init(
    Uint8List codeSizes, {
    int fastLookupBits = _Huffman.fastLookupBits,
  }) {
    final totalSyms = codeSizes.length;
    if (totalSyms == 0) {
      _codeSizes = Uint8List(0);
      _lookup = const [];
      _tree = const [];
      return;
    }
    _codeSizes = codeSizes;

    final fastLookupSize = 1 << fastLookupBits;
    final lookup = List<int>.filled(fastLookupSize, 0);
    final tree = <int>[];

    final symsUsingCodesize = List<int>.filled(
      _Huffman.maxSupportedInternalCodeSize + 1,
      0,
    );
    for (final size in codeSizes) {
      if (size > _Huffman.maxSupportedInternalCodeSize) {
        throw const Ktx2FormatException(
          'Huffman table: a code length exceeds what this format supports.',
        );
      }
      symsUsingCodesize[size]++;
    }

    final nextCode = List<int>.filled(
      _Huffman.maxSupportedInternalCodeSize + 1,
      0,
    );
    var usedSyms = 0;
    var total = 0;
    for (var i = 1; i < _Huffman.maxSupportedInternalCodeSize; i++) {
      usedSyms += symsUsingCodesize[i];
      total = (total + symsUsingCodesize[i]) << 1;
      nextCode[i + 1] = total;
    }
    if ((1 << _Huffman.maxSupportedInternalCodeSize) != total &&
        usedSyms != 1) {
      throw const Ktx2FormatException(
        'Huffman table: code lengths do not form a complete prefix code.',
      );
    }

    void growTreeTo(int length) {
      while (tree.length < length) {
        tree.add(0);
      }
    }

    var treeNext = -1;
    for (var symIndex = 0; symIndex < totalSyms; symIndex++) {
      final codeSize = codeSizes[symIndex];
      if (codeSize == 0) continue;

      var curCode = nextCode[codeSize]++;
      var revCode = 0;
      for (var l = codeSize; l > 0; l--, curCode >>= 1) {
        revCode = (revCode << 1) | (curCode & 1);
      }

      if (codeSize <= fastLookupBits) {
        final k = (codeSize << 16) | symIndex;
        var rc = revCode;
        while (rc < fastLookupSize) {
          if (lookup[rc] != 0) {
            throw const Ktx2FormatException(
              'Huffman table: code lengths do not form a valid prefix code.',
            );
          }
          lookup[rc] = k;
          rc += 1 << codeSize;
        }
        continue;
      }

      int treeCur;
      final idx0 = revCode & (fastLookupSize - 1);
      if (lookup[idx0] == 0) {
        lookup[idx0] = treeNext;
        treeCur = treeNext;
        treeNext -= 2;
      } else {
        treeCur = lookup[idx0];
      }
      if (treeCur >= 0) {
        throw const Ktx2FormatException(
          'Huffman table: code lengths do not form a valid prefix code.',
        );
      }

      // Deliberately (fastLookupBits - 1): the top bit of the fast-lookup
      // index is reused as the first bit the tree walk consumes.
      revCode >>= fastLookupBits - 1;

      for (var j = codeSize; j > fastLookupBits + 1; j--) {
        revCode >>= 1;
        treeCur -= revCode & 1;
        final idx = -treeCur - 1;
        if (idx < 0) {
          throw const Ktx2FormatException(
            'Huffman table: code lengths do not form a valid prefix code.',
          );
        }
        growTreeTo(idx + 1);
        if (tree[idx] == 0) {
          tree[idx] = treeNext;
          treeCur = treeNext;
          treeNext -= 2;
        } else {
          treeCur = tree[idx];
          if (treeCur >= 0) {
            throw const Ktx2FormatException(
              'Huffman table: code lengths do not form a valid prefix code.',
            );
          }
        }
      }

      revCode >>= 1;
      treeCur -= revCode & 1;
      final idx = -treeCur - 1;
      if (idx < 0) {
        throw const Ktx2FormatException(
          'Huffman table: code lengths do not form a valid prefix code.',
        );
      }
      growTreeTo(idx + 1);
      if (tree[idx] != 0) {
        throw const Ktx2FormatException(
          'Huffman table: code lengths do not form a valid prefix code.',
        );
      }
      tree[idx] = symIndex;
    }

    _lookup = lookup;
    _tree = tree;
  }
}

/// Reads a byte stream as a sequence of variable-width, LSB-first bit fields
/// and Huffman codes.
///
/// LSB-first: each byte is folded into a growing bit buffer at its current
/// high end (`c << m_bit_buf_size`), and every read takes from the low end —
/// the same convention `basist::bitwise_decoder` uses, and not an arbitrary
/// choice a reimplementation could get either way and still "work": every
/// table and every block in the file was written by an encoder that packed
/// bits this way.
final class BitwiseDecoder {
  BitwiseDecoder(this._buf);

  final Uint8List _buf;
  int _pos = 0;
  int _bitBuf = 0;
  int _bitBufSize = 0;

  int _nextByte() => _pos < _buf.length ? _buf[_pos++] : 0;

  int peekBits(int numBits) {
    if (numBits == 0) return 0;
    while (_bitBufSize < numBits) {
      _bitBuf |= _nextByte() << _bitBufSize;
      _bitBufSize += 8;
    }
    return _bitBuf & ((1 << numBits) - 1);
  }

  void removeBits(int numBits) {
    _bitBuf >>= numBits;
    _bitBufSize -= numBits;
  }

  int getBits(int numBits) {
    final bits = peekBits(numBits);
    removeBits(numBits);
    return bits;
  }

  /// A variable-length code: repeated `chunkBits`-wide groups, each with one
  /// continuation bit, low group first.
  int decodeVlc(int chunkBits) {
    final chunkMask = (1 << chunkBits) - 1;
    var v = 0;
    var ofs = 0;
    for (;;) {
      final s = getBits(chunkBits + 1);
      v |= (s & chunkMask) << ofs;
      ofs += chunkBits;
      if ((s & (1 << chunkBits)) == 0) break;
    }
    return v;
  }

  int decodeHuffman(HuffmanDecodingTable table) {
    while (_bitBufSize < 16) {
      _bitBuf |= _nextByte() << _bitBufSize;
      _bitBufSize += 8;
    }

    final fastLookupSize = 1 << _Huffman.fastLookupBits;
    var sym = table._lookup[_bitBuf & (fastLookupSize - 1)];
    int codeLen;
    if (sym >= 0) {
      codeLen = sym >> 16;
      sym &= 0xFFFF;
    } else {
      codeLen = _Huffman.fastLookupBits;
      do {
        sym = table._tree[~sym + ((_bitBuf >> codeLen) & 1)];
        codeLen++;
      } while (sym < 0);
    }

    _bitBuf >>= codeLen;
    _bitBufSize -= codeLen;
    return sym;
  }

  /// Reads one DEFLATE-style Huffman table: a Huffman-coded array of code
  /// lengths (itself described by a small fixed-alphabet code), decoded into
  /// [table].
  void readHuffmanTable(HuffmanDecodingTable table) {
    final totalUsedSyms = getBits(_Huffman.maxSymsLog2);
    if (totalUsedSyms == 0) {
      table.init(Uint8List(0));
      return;
    }

    final codeLengthCodeSizes = Uint8List(_Huffman.totalCodelengthCodes);
    final numCodelengthCodes = getBits(5);
    if (numCodelengthCodes < 1 ||
        numCodelengthCodes > _Huffman.totalCodelengthCodes) {
      throw const Ktx2FormatException(
        'Huffman table: invalid code-length code count.',
      );
    }
    for (var i = 0; i < numCodelengthCodes; i++) {
      codeLengthCodeSizes[_Huffman.sortedCodelengthCodes[i]] = getBits(3);
    }

    final codeLengthTable = HuffmanDecodingTable()..init(codeLengthCodeSizes);
    if (!codeLengthTable.isValid) {
      throw const Ktx2FormatException(
        'Huffman table: the code-length code itself is invalid.',
      );
    }

    final codeSizes = Uint8List(totalUsedSyms);
    var cur = 0;
    while (cur < totalUsedSyms) {
      final c = decodeHuffman(codeLengthTable);
      if (c <= 16) {
        codeSizes[cur++] = c;
      } else if (c == _Huffman.smallZeroRunCode) {
        cur +=
            getBits(_Huffman.smallZeroRunExtraBits) +
            _Huffman.smallZeroRunSizeMin;
      } else if (c == _Huffman.bigZeroRunCode) {
        cur +=
            getBits(_Huffman.bigZeroRunExtraBits) + _Huffman.bigZeroRunSizeMin;
      } else {
        if (cur == 0) {
          throw const Ktx2FormatException(
            'Huffman table: a repeat code appears before any code length.',
          );
        }
        final int l;
        if (c == _Huffman.smallRepeatCode) {
          l =
              getBits(_Huffman.smallRepeatExtraBits) +
              _Huffman.smallRepeatSizeMin;
        } else {
          l = getBits(_Huffman.bigRepeatExtraBits) + _Huffman.bigRepeatSizeMin;
        }
        final prev = codeSizes[cur - 1];
        if (prev == 0) {
          throw const Ktx2FormatException(
            'Huffman table: a repeat code repeats a zero length.',
          );
        }
        for (var i = 0; i < l; i++) {
          if (cur >= totalUsedSyms) {
            throw const Ktx2FormatException(
              'Huffman table: a repeat code runs past the table.',
            );
          }
          codeSizes[cur++] = prev;
        }
      }
    }
    if (cur != totalUsedSyms) {
      throw const Ktx2FormatException(
        'Huffman table: code lengths do not add up to the declared symbol count.',
      );
    }

    table.init(codeSizes);
  }
}
