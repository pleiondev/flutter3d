/// UASTC LDR 4×4 blocks, unpacked to RGBA8 — `gfx-78n`.
///
/// **The other half of Basis Universal, and the half modern toolchains write.**
/// ETC1S is the small one: codebooks shared across the whole image, quality to
/// match. UASTC is the good one: sixteen self-contained bytes a block, like
/// BC7 or ASTC, designed so that it *is* a restricted subset of ASTC 4×4 and
/// close to a subset of BC7 — which is what makes it quick to turn into either
/// on a device that samples them. `toktx --uastc`, `gltf-transform uastc` and
/// `basisu -uastc` all write it, and a KTX2 that holds it was refused here by
/// name until this existed.
///
/// **Unpacked to pixels, not repacked to blocks.** The reference transcoder
/// has a path from UASTC to every GPU format. This has the one to RGBA8, which
/// then goes the way every decoded image goes. That is a texture four to eight
/// times larger in memory than the repack would give — the honest cost of this
/// row stopping where it does — and it is a complete answer in the sense that
/// matters: every UASTC file opens, on every device, with the pixels the
/// reference produces. The repack is an optimisation on top, and `gfx-83n`'s
/// universal blocks are this engine's own route to the same place.
///
/// **Transcribed, with the tables, from the reference transcoder** —
/// `unpack_uastc` and what it reaches in `transcoder/basisu_transcoder.cpp` and
/// `basisu_transcoder_uastc.h`, Basis Universal, Binomial LLC, Apache-2.0
/// (https://github.com/BinomialLLC/basis_universal). The block layout is also
/// written down in that repository's `spec/` — but the tables below are the
/// ones the code uses, copied rather than re-derived, and every one of the
/// nineteen modes is checked in `uastc_test.dart` against what that
/// transcoder's own RGBA32 output is for files its own encoder wrote, byte for
/// byte. `zstd.dart` is why: four bugs there each looked right.
///
/// ## A block
///
/// A Huffman-coded *mode* (2 to 7 bits), then — skipped here — hints that let
/// the other transcoders cheat, then for most modes a partition pattern, a
/// second-plane selector, the colour endpoints and the weights. A mode fixes
/// everything ASTC would spend bits describing: how many *subsets* the sixteen
/// texels are divided into (one to three, each with its own pair of endpoint
/// colours), whether there are two *planes* of weights (one channel
/// interpolating independently of the rest), how many components the endpoints
/// have (luminance+alpha, RGB or RGBA), how finely the endpoints are quantised
/// and how many bits a weight gets. A texel's colour is its subset's two
/// endpoints, interpolated by its weight.
library;

import 'dart:typed_data';

import '../ktx2_format.dart';

/// Bytes in one block, whatever it holds.
const int kUastcBlockBytes = 16;

/// Unpacks [blocks] — row-major 4×4 blocks covering a [width]×[height] image —
/// to tightly packed RGBA8.
///
/// The image need not be a whole number of blocks: the last row and column of
/// blocks are decoded in full and the texels past the edge dropped, which is
/// what the encoder padded them for.
Uint8List decodeUastcToRgba8(
  Uint8List blocks, {
  required int width,
  required int height,
}) {
  final blocksX = (width + 3) ~/ 4;
  final blocksY = (height + 3) ~/ 4;
  if (blocks.length < blocksX * blocksY * kUastcBlockBytes) {
    throw Ktx2FormatException(
      'A ${width}x$height UASTC image is $blocksX x $blocksY blocks of '
      '$kUastcBlockBytes bytes, and only ${blocks.length} bytes are here.',
    );
  }

  final out = Uint8List(width * height * 4);
  final texels = Uint8List(64);
  for (var by = 0; by < blocksY; by++) {
    for (var bx = 0; bx < blocksX; bx++) {
      _unpackBlock(blocks, (by * blocksX + bx) * kUastcBlockBytes, texels);
      final rows = height - by * 4 < 4 ? height - by * 4 : 4;
      final columns = width - bx * 4 < 4 ? width - bx * 4 : 4;
      for (var y = 0; y < rows; y++) {
        out.setRange(
          ((by * 4 + y) * width + bx * 4) * 4,
          ((by * 4 + y) * width + bx * 4 + columns) * 4,
          texels,
          y * 16,
        );
      }
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Tables — `basisu_transcoder.cpp`, names kept so they can be found there.
// ---------------------------------------------------------------------------

/// `g_uastc_huff_modes`: the low seven bits of a block, to its mode. The code
/// is prefix-free and at most seven bits, so a lookup replaces the decode.
/// Nineteen is reserved and is the one value that is not a mode.
const List<int> _huffModes = <int>[
  11, 0, 10, 3, 11, 15, 12, 7, 11, 18, 10, 5, 11, 14, 12, 9, //
  11, 0, 10, 4, 11, 16, 12, 8, 11, 18, 10, 6, 11, 2, 12, 13,
  11, 0, 10, 3, 11, 17, 12, 7, 11, 18, 10, 5, 11, 14, 12, 9,
  11, 0, 10, 4, 11, 1, 12, 8, 11, 18, 10, 6, 11, 2, 12, 13,
  11, 0, 10, 3, 11, 19, 12, 7, 11, 18, 10, 5, 11, 14, 12, 9,
  11, 0, 10, 4, 11, 16, 12, 8, 11, 18, 10, 6, 11, 2, 12, 13,
  11, 0, 10, 3, 11, 17, 12, 7, 11, 18, 10, 5, 11, 14, 12, 9,
  11, 0, 10, 4, 11, 1, 12, 8, 11, 18, 10, 6, 11, 2, 12, 13,
];

const int _modeCount = 19;
const int _modeSolidColor = 8;

/// `g_uastc_mode_huff_codes[mode][1]`: how many bits the mode's own code took.
const List<int> _modeCodeBits = <int>[
  4, 6, 5, 5, 5, 5, 5, 5, 5, 5, 3, 2, 3, 5, 5, 7, 6, 6, 4, //
];

/// `g_uastc_mode_total_hint_bits`: the BC1, ETC1 and ETC2 hints between the
/// mode and the data. Help for transcoders that repack; dead weight for one
/// that unpacks, so they are stepped over.
const List<int> _modeHintBits = <int>[
  15, 15, 15, 15, 15, 15, 15, 15, 0, 23, 17, 17, 17, 23, 23, 23, 23, 23, 15, //
];

const List<int> _modeWeightBits = <int>[
  4, 2, 3, 2, 2, 3, 2, 2, 0, 2, 4, 2, 3, 1, 2, 4, 2, 2, 5, //
];

/// `g_uastc_mode_endpoint_ranges`: which ASTC quantisation range the endpoints
/// are stored in — an index into [_biseRanges].
const List<int> _modeEndpointRange = <int>[
  19, 20, 8, 7, 12, 20, 18, 12, 0, 8, 13, 13, 19, 20, 20, 20, 20, 20, 11, //
];

const List<int> _modeSubsets = <int>[
  1, 1, 2, 3, 2, 1, 1, 2, 0, 2, 1, 1, 1, 1, 1, 1, 2, 1, 1, //
];

const List<int> _modePlanes = <int>[
  1, 1, 1, 1, 1, 1, 2, 1, 0, 1, 1, 2, 1, 2, 1, 1, 1, 2, 1, //
];

/// `g_uastc_mode_comps`: 3 is RGB, 4 is RGBA, 2 is luminance and alpha.
const List<int> _modeComponents = <int>[
  3, 3, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 4, 2, 2, 2, 3, //
];

/// `g_astc_bise_range_table`: bits, trits, quints. A range with a trit stores
/// values of the form `trit * 2^bits + bits`, five trits packed into eight
/// bits; with a quint, three quints into seven. It is how ASTC gets level
/// counts that are not powers of two.
const List<List<int>> _biseRanges = <List<int>>[
  <int>[1, 0, 0], <int>[0, 1, 0], <int>[2, 0, 0], <int>[0, 0, 1], //
  <int>[1, 1, 0], <int>[3, 0, 0], <int>[1, 0, 1], <int>[2, 1, 0],
  <int>[4, 0, 0], <int>[2, 0, 1], <int>[3, 1, 0], <int>[5, 0, 0],
  <int>[3, 0, 1], <int>[4, 1, 0], <int>[6, 0, 0], <int>[4, 0, 1],
  <int>[5, 1, 0], <int>[7, 0, 0], <int>[5, 0, 1], <int>[6, 1, 0],
  <int>[8, 0, 0],
];

/// `g_astc_endpoint_unquant_params`, "taken right from the ASTC spec": for a
/// range with a trit or a quint, which stored bit lands in each of the nine
/// bits of `B`, and the multiplier `C`. Letters are bit indices, `a` lowest.
const List<(String, int)> _endpointUnquantParams = <(String, int)>[
  ('', 0), ('', 0), ('', 0), ('', 0), //
  ('000000000', 204), ('', 0), ('000000000', 113), ('b000b0bb0', 93),
  ('', 0), ('b0000bb00', 54), ('cb000cbcb', 44), ('', 0),
  ('cb0000cbc', 26), ('dcb000dcb', 22), ('', 0), ('dcb0000dc', 13),
  ('edcb000ed', 11), ('', 0), ('edcb0000e', 6), ('fedcb000f', 5),
  ('', 0),
];

/// `g_bc7_weights1..3`, `g_astc_weights4..5`, by bits a weight: what a weight
/// index means on the 0..64 scale the interpolation works in.
const List<List<int>> _weightTables = <List<int>>[
  <int>[],
  <int>[0, 64],
  <int>[0, 21, 43, 64],
  <int>[0, 9, 18, 27, 37, 46, 55, 64],
  <int>[0, 4, 8, 12, 17, 21, 25, 29, 35, 39, 43, 47, 52, 56, 60, 64],
  <int>[
    0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, //
    34, 36, 38, 40, 42, 44, 46, 48, 50, 52, 54, 56, 58, 60, 62, 64,
  ],
];

/// `g_astc_bc7_patterns2`: the thirty two-subset partitions ASTC and BC7 have
/// in common, texel by texel. UASTC stores an index into *this* list rather
/// than either format's own, which is the trick that makes it both.
const List<List<int>> _patterns2 = <List<int>>[
  <int>[0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1],
  <int>[0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1],
  <int>[1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0],
  <int>[0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 1, 1, 1],
  <int>[1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 0, 1, 1, 0, 0],
  <int>[0, 0, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1],
  <int>[1, 1, 1, 0, 1, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0],
  <int>[1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 0, 0, 1, 0, 0, 0],
  <int>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1],
  <int>[1, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  <int>[0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 1, 1, 1, 1, 1, 1],
  <int>[1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 0, 0, 0],
  <int>[1, 1, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  <int>[1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0],
  <int>[0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
  <int>[1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0],
  <int>[1, 0, 0, 0, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1],
  <int>[1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 0, 0, 0, 1],
  <int>[0, 1, 1, 1, 0, 0, 1, 1, 0, 0, 0, 1, 0, 0, 0, 0],
  <int>[0, 0, 1, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0],
  <int>[0, 0, 0, 0, 1, 0, 0, 0, 1, 1, 0, 0, 1, 1, 1, 0],
  <int>[1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 0, 0, 1, 1],
  <int>[1, 0, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 1, 0],
  <int>[0, 0, 1, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0],
  <int>[1, 1, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 0, 0, 1, 1],
  <int>[0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0],
  <int>[1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1],
  <int>[1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0],
  <int>[1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0],
  <int>[1, 0, 0, 1, 0, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 0],
];

/// `g_astc_bc7_patterns3`: the eleven three-subset partitions in common.
const List<List<int>> _patterns3 = <List<int>>[
  <int>[0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2, 2, 1, 1, 2, 2],
  <int>[1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 2, 2, 2, 2],
  <int>[1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 2],
  <int>[1, 1, 1, 1, 2, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0],
  <int>[1, 1, 2, 0, 1, 1, 2, 0, 1, 1, 2, 0, 1, 1, 2, 0],
  <int>[0, 1, 1, 2, 0, 1, 1, 2, 0, 1, 1, 2, 0, 1, 1, 2],
  <int>[0, 2, 1, 1, 0, 2, 1, 1, 0, 2, 1, 1, 0, 2, 1, 1],
  <int>[2, 0, 0, 0, 2, 0, 0, 0, 2, 1, 1, 1, 2, 1, 1, 1],
  <int>[2, 0, 1, 2, 2, 0, 1, 2, 2, 0, 1, 2, 2, 0, 1, 2],
  <int>[1, 1, 1, 1, 0, 0, 0, 0, 2, 2, 2, 2, 1, 1, 1, 1],
  <int>[0, 0, 2, 2, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 2, 2],
];

/// `g_bc7_3_astc2_patterns2`: mode 7's own nineteen — two-subset ASTC
/// partitions that a *three*-subset BC7 partition can reproduce.
const List<List<int>> _patterns2Mode7 = <List<int>>[
  <int>[0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0],
  <int>[0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0],
  <int>[1, 1, 0, 0, 1, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0],
  <int>[0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 1],
  <int>[1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1],
  <int>[0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0],
  <int>[0, 0, 0, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
  <int>[0, 1, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1],
  <int>[1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0],
  <int>[0, 1, 1, 1, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0],
  <int>[0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 1, 1, 1, 0],
  <int>[1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0],
  <int>[0, 1, 1, 1, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0],
  <int>[0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1],
  <int>[1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 0],
  <int>[1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 0, 0, 0],
  <int>[1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 1, 0, 0, 0],
  <int>[0, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 0, 1, 0, 0, 0],
  <int>[1, 1, 1, 1, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0],
];

/// The all-zero pattern of a block that is not partitioned.
final List<int> _pattern1 = List<int>.filled(16, 0);

// ---------------------------------------------------------------------------
// Derived tables
// ---------------------------------------------------------------------------

/// Where each subset's *anchor* texel is: the first texel of the subset, in
/// raster order. The reference keeps these as three more tables
/// (`g_astc_bc7_pattern2_anchors` and its two siblings) and asserts, in debug
/// builds, that they equal exactly this — so here they are computed, and
/// there is one fewer table to have copied wrongly.
List<int> _anchorsOf(List<int> pattern, int subsets) => <int>[
  for (var subset = 0; subset < subsets; subset++) pattern.indexOf(subset),
];

/// `g_astc_unquant[range][value].m_unquant`, built on first use per range:
/// what a stored endpoint value is as an eight-bit colour component.
final List<Uint8List?> _unquantCache = List<Uint8List?>.filled(
  _biseRanges.length,
  null,
);

Uint8List _unquantTable(int range) => _unquantCache[range] ??= () {
  final [bits, trits, quints] = _biseRanges[range];
  final levels = (1 + 2 * trits + 4 * quints) << bits;
  return Uint8List.fromList(<int>[
    for (var value = 0; value < levels; value++)
      _unquantEndpoint(
        value & ((1 << bits) - 1),
        value >> bits,
        range,
        bits,
        plainBits: trits == 0 && quints == 0,
      ),
  ]);
}();

/// `unquant_astc_endpoint`.
///
/// A range that is only bits is widened by repeating them — the usual way to
/// stretch *n* bits to eight. One with a trit or a quint goes through the ASTC
/// specification's `A`, `B`, `C`, `D` construction, which is the same idea for
/// a number that is not a power of two: `D` is the trit or quint, `C` spreads
/// it across the range, `B` scatters the plain bits into the gaps, and the low
/// bit mirrors the whole thing so that the top value comes out as exactly 255.
int _unquantEndpoint(
  int packedBits,
  int tritOrQuint,
  int range,
  int bits, {
  required bool plainBits,
}) {
  if (plainBits) {
    var value = 0;
    for (var bitsLeft = 8; bitsLeft > 0;) {
      final n = bitsLeft < bits ? bitsLeft : bits;
      value |= (packedBits >> (bits - n)) << (bitsLeft - n);
      bitsLeft -= n;
    }
    return value;
  }

  final (pattern, c) = _endpointUnquantParams[range];
  final a = packedBits & 1 != 0 ? 511 : 0;
  final b = pattern.codeUnits.fold<int>(
    0,
    (accumulated, letter) =>
        (accumulated << 1) |
        (letter == 0x30 ? 0 : (packedBits >> (letter - 0x61)) & 1),
  );
  final value = (tritOrQuint * c + b) ^ a;
  return (a & 0x80) | (value >> 2);
}

/// `astc_interpolate`, with `srgb` false — which is how the reference calls it
/// for RGBA32 whatever the file's transfer function says.
///
/// Endpoints are widened to sixteen bits by repetition, mixed on the 0..64
/// weight scale with rounding, and the top byte kept. The detour through
/// sixteen bits is ASTC's, and it is not the same as mixing the bytes: 1 and 0
/// at weight 21 are 0 this way and 1 that way, which a byte-for-byte
/// comparison with the reference notices.
int _interpolate(int low, int high, int weight) {
  final l = (low << 8) | low;
  final h = (high << 8) | high;
  return ((l * (64 - weight) + h * weight + 32) >> 6) >> 8;
}

// ---------------------------------------------------------------------------
// One block
// ---------------------------------------------------------------------------

/// A cursor over a block's 128 bits, least significant first.
final class _Bits {
  _Bits(this._bytes, this._base, this.position);

  final Uint8List _bytes;
  final int _base;
  int position;

  /// [count] bits, up to nine. A read that reaches past bit 127 sees zeros:
  /// only a malformed block asks for one, and what it gets is a wrong colour
  /// in one block rather than bytes from the next.
  int read(int count) {
    if (count == 0) return 0;
    final byte = position >> 3;
    int at(int i) => byte + i < kUastcBlockBytes ? _bytes[_base + byte + i] : 0;
    final word = at(0) | (at(1) << 8) | (at(2) << 16);
    final value = (word >> (position & 7)) & ((1 << count) - 1);
    position += count;
    return value;
  }
}

/// `unpack_uastc`, both halves: the block at [at] in [source], to the sixteen
/// RGBA texels of [texels], raster order.
void _unpackBlock(Uint8List source, int at, Uint8List texels) {
  final mode = _huffModes[source[at] & 127];
  if (mode >= _modeCount) {
    throw const Ktx2FormatException(
      'A UASTC block names mode 19, which the format reserves and no encoder '
      'writes.',
    );
  }
  final bits = _Bits(source, at, _modeCodeBits[mode]);

  if (mode == _modeSolidColor) {
    final r = bits.read(8), g = bits.read(8), b = bits.read(8);
    final a = bits.read(8);
    for (var i = 0; i < 64; i += 4) {
      texels[i] = r;
      texels[i + 1] = g;
      texels[i + 2] = b;
      texels[i + 3] = a;
    }
    return;
  }

  bits.position += _modeHintBits[mode];

  final subsets = _modeSubsets[mode];
  final planes = _modePlanes[mode];
  final components = _modeComponents[mode];
  final weightBits = _modeWeightBits[mode];

  // The partition, for the modes that have one: five bits for two subsets,
  // four for three.
  final patternIndex = switch (subsets) {
    2 => bits.read(5),
    3 => bits.read(4),
    _ => 0,
  };
  final patterns = switch (subsets) {
    1 => null,
    3 => _patterns3,
    _ => mode == 7 ? _patterns2Mode7 : _patterns2,
  };
  if (patterns != null && patternIndex >= patterns.length) {
    throw Ktx2FormatException(
      'A UASTC mode $mode block names partition $patternIndex of '
      '${patterns.length}.',
    );
  }
  final pattern = patterns?[patternIndex] ?? _pattern1;

  // Which channel the second plane of weights drives. Mode 17 is luminance
  // and alpha, where it can only be alpha, so it does not spend the bits.
  final secondPlaneChannel = switch (mode) {
    6 || 11 || 13 => bits.read(2),
    17 => 3,
    _ => -1,
  };

  // **Endpoints, in ASTC's BISE packing, regrouped.** ASTC interleaves each
  // trit or quint bundle with the plain bits of the values it covers; UASTC
  // stores every bundle first and every value's plain bits after. Five trits
  // to eight bits, three quints to seven, and a last bundle that covers fewer
  // values is correspondingly shorter.
  final range = _modeEndpointRange[mode];
  final [plainBits, trits, quints] = _biseRanges[range];
  final valueCount = components * 2 * subsets;
  final (bundleSize, radix) = trits != 0
      ? (5, 3)
      : quints != 0
      ? (3, 5)
      : (0, 0);
  final bundles = <int>[
    if (bundleSize != 0)
      for (var first = 0; first < valueCount; first += bundleSize)
        bits.read(switch ((radix, valueCount - first)) {
          (3, 1) => 2,
          (3, 2) => 4,
          (3, 3) => 5,
          (3, 4) => 7,
          (3, _) => 8,
          (5, 1) => 3,
          (5, 2) => 5,
          _ => 7,
        }),
  ];
  final unquant = _unquantTable(range);
  final endpoints = Uint8List(valueCount);
  for (var i = 0; i < valueCount; i++) {
    final plain = bits.read(plainBits);
    // The i-th value's trit or quint is a base-`radix` digit of its bundle.
    final digit = bundleSize == 0
        ? 0
        : _digit(bundles[i ~/ bundleSize], radix, i % bundleSize);
    endpoints[i] = unquant[plain | (digit << plainBits)];
  }

  // **Weights, with the anchors' top bit left out.** Swapping a subset's two
  // endpoints and inverting its weights gives the same block, so the encoder
  // picks the form in which each subset's first texel has a weight in the
  // lower half — and then does not store the bit that says so. With two
  // planes the first texel has two weights and both are anchors.
  final anchors = _anchorsOf(pattern, subsets);
  final weights = Uint8List(16 * planes);
  for (var i = 0; i < weights.length; i++) {
    final isAnchor = planes == 2 ? i < 2 : anchors.contains(i);
    weights[i] = bits.read(isAnchor ? weightBits - 1 : weightBits);
  }

  // Every colour a subset can produce, once, and then texels are lookups.
  final table = _weightTables[weightBits];
  final levels = table.length;
  final colors = Uint8List(subsets * levels * 4);
  for (var subset = 0; subset < subsets; subset++) {
    final e = subset * components * 2;
    for (var level = 0; level < levels; level++) {
      final to = (subset * levels + level) * 4;
      final w = table[level];
      if (components == 2) {
        // Luminance and alpha: the luminance pair, then the alpha pair.
        final l = _interpolate(endpoints[e], endpoints[e + 1], w);
        colors[to] = l;
        colors[to + 1] = l;
        colors[to + 2] = l;
        colors[to + 3] = _interpolate(endpoints[e + 2], endpoints[e + 3], w);
      } else {
        for (var c = 0; c < 4; c++) {
          colors[to + c] = c < components
              ? _interpolate(endpoints[e + c * 2], endpoints[e + c * 2 + 1], w)
              : 255;
        }
      }
    }
  }

  for (var i = 0; i < 16; i++) {
    final base = pattern[i] * levels;
    final first = (base + weights[i * planes]) * 4;
    final second = planes == 2 ? (base + weights[i * 2 + 1]) * 4 : first;
    for (var c = 0; c < 4; c++) {
      texels[i * 4 + c] =
          colors[(c == secondPlaneChannel ? second : first) + c];
    }
  }
}

/// The [index]-th base-[radix] digit of [bundle], least significant first.
int _digit(int bundle, int radix, int index) {
  var value = bundle;
  for (var i = 0; i < index; i++) {
    value ~/= radix;
  }
  return value % radix;
}
