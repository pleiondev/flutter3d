import 'dart:typed_data';

import 'principal_axis.dart';
import 'rgba8_image.dart';

/// Encodes [image] as ASTC 4×4 LDR (`vkFormat.astc4x4UNormBlock`): one
/// 16-byte block per 4×4 tile — mat-30's own gap on top of `fmt-22`'s
/// BC1/BC3/ETC2 trio, `doc/asset-pipeline-plan.md`'s `ap-07`.
///
/// **Single partition, single plane, a 4×4 weight grid — the ETC2-shaped
/// subset of ASTC, not the full format.** Real ASTC's block-mode field packs
/// a whole table of weight-grid shapes (2×2 up to 12×12, non-square,
/// interpolated) and up to four colour partitions with dual-plane
/// (per-channel-independent weight) blocks on top of that; a full encoder
/// for all of it is the size of a small library. What is implemented here is
/// the same trade [encodeEtc2Rgb8Block] documents making: one shape (the
/// weight grid equals the 4×4 texel grid exactly, so every texel gets its
/// own weight with no interpolation to derive), one partition, one
/// colour-endpoint pair, `LDR RGB Direct` mode — a real GPU's ASTC decoder
/// accepts this shape as valid ASTC, since single-partition/single-plane is
/// one legal point in the format, not a reduced dialect of it.
///
/// **The block-mode field is the specification's, checked against ARM's own
/// decoder — `gfx-88n`, 2026-09-18.** Until that row this file wrote eleven
/// zero bits there and said so in this comment, calling the layout its own
/// because reproducing the real row-selection table with nothing to check
/// against risked a block that looks self-consistent and is not. The risk was
/// real and the check was a package away: `astcenc` installs from npm, and fed
/// a file this encoder wrote it returned `(255, 0, 255)` — ASTC's error colour
/// — for every block, because eleven zeros is a reserved encoding rather than
/// a 4×4 weight grid. What is written now is [_kBlockMode], read out of
/// `decode_block_mode_2d`, and `astc_conformance_test.dart` pins both the bytes
/// `astcenc` was handed and what it gave back.
///
/// **Endpoints from the same principal-axis fit [encodeBc1Block] uses, one
/// weight per texel from an exhaustive nearest-level search against the
/// endpoint line** — not the two-endpoint interpolation table BC1 is stuck
/// with: eight independent levels per texel against BC1's four-entry palette,
/// which is where ASTC's quality advantage over block formats from the same era
/// actually comes from.
Uint8List encodeAstc4x4(Rgba8Image image) {
  requireWholeBlocks(image, 'encodeAstc4x4');
  final blocksX = image.width ~/ 4;
  final blocksY = image.height ~/ 4;
  final out = Uint8List(blocksX * blocksY * 16);
  var offset = 0;
  for (var by = 0; by < blocksY; by++) {
    for (var bx = 0; bx < blocksX; bx++) {
      final block = encodeAstc4x4Block(readBlock(image, bx, by));
      out.setRange(offset, offset + 16, block);
      offset += 16;
    }
  }
  return out;
}

/// Bits per endpoint channel value — `gfx-88n`.
///
/// **Eight, and it is derived rather than chosen.** ASTC does not let an
/// encoder pick the endpoint precision: the decoder computes it from what is
/// left after the block mode, the partition count, the colour-endpoint mode and
/// the weights, and reads the endpoints at the highest level that fits. With
/// three-bit weights the leftovers are 63 bits for six values, and the highest
/// level fitting that is the 256-level one — plain eight-bit binary, no trits
/// and no quints. Four-bit weights would leave 47, where the answer is a
/// trit-packed 192-level range instead, so this pair of widths is what keeps
/// both halves of the block plain binary.
const int _kColorBits = 8;
const int _kColorMax = (1 << _kColorBits) - 1; // 255

/// Bits per texel weight (3 bits, 8 levels, plain binary). See [_kColorBits]
/// for why three rather than four.
const int _kWeightBits = 3;
const int _kWeightMax = (1 << _kWeightBits) - 1; // 7

/// The block mode for one plane, a 4×4 weight grid and eight weight levels.
///
/// **Read out of the reference decoder, not derived.** `decode_block_mode_2d`
/// in ARM's `astc-encoder` unpacks this field through a branching table; the
/// bits that make it say what this block is are `[1:0] = 3`, `[3:2] = 0`,
/// `[4] = 1`, `[6:5] = 2` (height 4), `[8:7] = 0` (width 4), `[9] = 0` and
/// `[10] = 0` (single plane). The version of this file before `gfx-88n` wrote
/// eleven zeros here and called the layout its own, which is a reserved
/// encoding: `astcenc` returned magenta — ASTC's error colour — for every block.
const int _kBlockMode = 0x53;

/// The real specification's colour-endpoint-mode value for "LDR RGB Direct"
/// — two RGB endpoints, no alpha (alpha reads back as opaque), the same
/// shape [encodeBc1Block]'s colour half and [encodeEtc2Rgb8Block] both are.
const int _kCemLdrRgbDirect = 8;

/// Encodes one 4×4 block (row-major, alpha ignored) as sixteen bytes: the
/// 11-bit [_kBlockMode], a 2-bit partition count of zero (one partition), a
/// 4-bit CEM of [_kCemLdrRgbDirect], six [_kColorBits]-wide endpoint channel
/// values, then sixteen [_kWeightBits]-wide per-texel weights packed downward
/// from bit 127 — 17 + 48 from the bottom and 48 from the top, leaving the
/// fifteen bits between them zero.
Uint8List encodeAstc4x4Block(List<(int, int, int, int)> pixels) {
  final fit = blockEndpoints(pixels);

  // The weights are chosen against the endpoints as the block will *store*
  // them, which is why the ordering happens first and the search reads the
  // pair back out of it.
  final ordered = orderAstc4x4Endpoints(
    _quantizeColor(fit.high),
    _quantizeColor(fit.low),
  );
  final lowExpanded = _expandColor(ordered.low);
  final highExpanded = _expandColor(ordered.high);

  final weights = <int>[
    for (final (er, eg, eb, _) in pixels)
      _nearestWeight(er, eg, eb, lowExpanded, highExpanded),
  ];
  return packAstc4x4Block(
    endpoint0: ordered.low,
    endpoint1: ordered.high,
    weights: weights,
  );
}

/// Which of the [_kWeightMax] + 1 levels along the endpoint line is closest to
/// one texel.
int _nearestWeight(
  int r,
  int g,
  int b,
  (double, double, double) low,
  (double, double, double) high,
) {
  var bestWeight = 0;
  var bestError = double.infinity;
  for (var w = 0; w <= _kWeightMax; w++) {
    final (dr, dg, db) = _lerpColor(low, high, w / _kWeightMax);
    final errR = r - dr, errG = g - dg, errB = b - db;
    final error = errR * errR + errG * errG + errB * errB;
    if (error < bestError) {
      bestError = error;
      bestWeight = w;
    }
  }
  return bestWeight;
}

/// The two endpoints in the order `LDR RGB Direct` reads them, and whether
/// that meant swapping the pair.
///
/// **The second endpoint must not be the darker one.** The decoder compares
/// the two channel sums and, when the first is the larger, reads the pair
/// swapped *and* blue-contracted — a different colour entirely. A caller that
/// swaps must mirror its weights to match, which is what [swapped] is for.
({(int, int, int) low, (int, int, int) high, bool swapped})
orderAstc4x4Endpoints((int, int, int) e0, (int, int, int) e1) {
  final sum0 = e0.$1 + e0.$2 + e0.$3;
  final sum1 = e1.$1 + e1.$2 + e1.$3;
  return sum1 < sum0
      ? (low: e1, high: e0, swapped: true)
      : (low: e0, high: e1, swapped: false);
}

/// The sixteen bytes of one block, given endpoints already in
/// [orderAstc4x4Endpoints]' order and one weight per texel in `0..7`.
///
/// Split out of [encodeAstc4x4Block] for `gfx-83n`: the universal-block
/// transcoder arrives with endpoints and weights already decided and needs the
/// same packing, and this is the packing `astc_conformance_test.dart` holds to
/// what ARM's decoder accepts. Two copies of it would be two things to keep
/// conformant.
Uint8List packAstc4x4Block({
  required (int, int, int) endpoint0,
  required (int, int, int) endpoint1,
  required List<int> weights,
}) {
  final block = Uint8List(16);
  _setBits(block, 0, 11, _kBlockMode);
  _setBits(block, 11, 2, 0); // one partition
  _setBits(block, 13, 4, _kCemLdrRgbDirect);

  var cursor = 17;
  final channels = <int>[
    endpoint0.$1, endpoint1.$1, //
    endpoint0.$2, endpoint1.$2,
    endpoint0.$3, endpoint1.$3,
  ];
  for (final value in channels) {
    cursor = _setBits(block, cursor, _kColorBits, value);
  }

  // **The weights live at the top of the block, reversed.** ASTC stores the
  // weight stream growing downward from bit 127, with the bit order flipped —
  // so it is built here in an ordinary buffer and then folded in byte by byte,
  // each byte reversed and taken from the other end. Written forwards, as this
  // file did before `gfx-88n`, every weight lands somewhere else.
  final packed = Uint8List(16);
  var weightCursor = 0;
  for (final weight in weights) {
    weightCursor = _setBits(packed, weightCursor, _kWeightBits, weight);
  }
  for (var i = 0; i < 16; i++) {
    block[i] |= _reverseByte(packed[15 - i]);
  }
  return block;
}

/// How many levels a weight written by [packAstc4x4Block] has — eight, so the
/// caller's weights run `0..7`. Named for the transcoder, which has to spread
/// its own four levels across them.
const int kAstc4x4WeightLevels = _kWeightMax + 1;

(int, int, int) _quantizeColor((double, double, double) rgb) {
  final (r, g, b) = rgb;
  int q(double v) => (v * _kColorMax / 255).round().clamp(0, _kColorMax);
  return (q(r), q(g), q(b));
}

(double, double, double) _expandColor((int, int, int) rgb) {
  double e(int v) => v * 255 / _kColorMax;
  return (e(rgb.$1), e(rgb.$2), e(rgb.$3));
}

(double, double, double) _lerpColor(
  (double, double, double) e0,
  (double, double, double) e1,
  double t,
) {
  final (r0, g0, b0) = e0;
  final (r1, g1, b1) = e1;
  return (r0 + (r1 - r0) * t, g0 + (g1 - g0) * t, b0 + (b1 - b0) * t);
}

/// The bits of one byte, back to front — what the weight stream's placement
/// needs.
int _reverseByte(int value) {
  var out = 0;
  for (var i = 0; i < 8; i++) {
    if ((value >> i) & 1 != 0) out |= 1 << (7 - i);
  }
  return out;
}

/// Writes [value]'s low [numBits] bits into [block] starting at bit
/// [bitOffset] (bit 0 is the LSB of byte 0, rising through each byte then
/// into the next), and returns `bitOffset + numBits` — the next field's
/// offset, so a run of fields can chain calls without recomputing cursors.
int _setBits(Uint8List block, int bitOffset, int numBits, int value) {
  for (var i = 0; i < numBits; i++) {
    if (((value >> i) & 1) != 0) {
      final pos = bitOffset + i;
      block[pos >> 3] |= 1 << (pos & 7);
    }
  }
  return bitOffset + numBits;
}
