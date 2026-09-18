import 'dart:typed_data';

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
/// **The block-mode field is this port's own layout, not the specification's
/// row-selection table.** ASTC's actual 11-bit block-mode field encodes
/// weight-grid width and height through a branching table with special cases
/// for widths/heights up to 12 and for dual-plane blocks — reproducing it
/// bit-for-bit from the specification text without a reference decoder to
/// check against risks a block that looks self-consistent and is not, the
/// exact failure mode a corrupted or misread field is hardest to catch. This
/// encoder instead writes its own fixed, documented bit layout into the same
/// 16-byte container (partition count and colour-endpoint mode use the
/// specification's real field widths and the real `LDR RGB Direct` CEM
/// value, 8) and reads it back with a matching test decoder in this
/// package's own test suite — proved by decode-and-compare and by PSNR
/// against a real texture, the same bar `fmt-22`'s own BC1/BC3/ETC2 encoders
/// were held to.
/// **That gap has now been exercised, and it is real — `gfx-88n`, 2026-09-18.**
/// This comment used to end by naming a risk nobody had measured, because there
/// was no reference decoder to measure it with. There is one: ARM's own
/// `astcenc` installs from npm. Fed a file this encoder wrote, it returns
/// `(255, 0, 255)` for every block — ASTC's error colour — because an all-zero
/// block-mode field is not a 4×4 weight grid, it is a reserved encoding. So
/// what this writes is a 16-byte-per-block container that only this package can
/// read, and a real GPU would draw magenta.
///
/// Nothing ships magenta today: `texture_encode.dart` switches on `bc` and
/// `etc2` and returns the image untouched for anything else, so no build can
/// select this. What it does mean is that the function is exported and cannot
/// be used for what its name promises. `gfx-88n` is the row that makes it
/// conformant, and it now starts with the oracle that was missing — the correct
/// mode for this configuration is `0x242`, read out of `decode_block_mode_2d`
/// in the reference encoder rather than guessed.
///
/// **Endpoints from the same principal-axis fit [encodeBc1Block] uses, one
/// weight per texel from an exhaustive nearest-level search against the
/// endpoint line** — not the two-endpoint interpolation table BC1 is stuck
/// with: a 4-bit (sixteen-level) independent weight per texel is far finer
/// than BC1's four-entry palette, which is where ASTC's real quality
/// advantage over block formats from the same era actually comes from.
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

/// Encodes one 4×4 block (row-major, alpha ignored) as sixteen bytes: an
/// 11-bit header this port does not itself interpret past its own decoder
/// (see the library doc comment), a 2-bit partition count of zero (one
/// partition), a 4-bit CEM of [_kCemLdrRgbDirect], six [_kColorBits]-wide
/// endpoint channel values, then sixteen [_kWeightBits]-wide per-texel
/// weights packed from the end of the block backward — 17 + 42 + 64 = 123 of
/// the block's 128 bits, the rest zero.
Uint8List encodeAstc4x4Block(List<(int, int, int, int)> pixels) {
  final rgb = <(double, double, double)>[
    for (final (r, g, b, _) in pixels)
      (r.toDouble(), g.toDouble(), b.toDouble()),
  ];

  var meanR = 0.0, meanG = 0.0, meanB = 0.0;
  for (final (r, g, b) in rgb) {
    meanR += r;
    meanG += g;
    meanB += b;
  }
  meanR /= 16;
  meanG /= 16;
  meanB /= 16;

  final (axisR, axisG, axisB) = _principalAxis(rgb, meanR, meanG, meanB);

  var minT = double.infinity, maxT = -double.infinity;
  var minIndex = 0, maxIndex = 0;
  for (var i = 0; i < 16; i++) {
    final (r, g, b) = rgb[i];
    final t = (r - meanR) * axisR + (g - meanG) * axisG + (b - meanB) * axisB;
    if (t < minT) {
      minT = t;
      minIndex = i;
    }
    if (t > maxT) {
      maxT = t;
      maxIndex = i;
    }
  }

  // Endpoint 0 is the block's brightest-along-the-axis pixel, endpoint 1 its
  // dimmest — a flat block (every projection equal) puts both at the same
  // pixel, which decodes solid regardless of which weight a texel picks.
  final e0 = rgb[maxIndex];
  final e1 = minIndex == maxIndex ? e0 : rgb[minIndex];

  final (r0q, g0q, b0q) = _quantizeColor(e0);
  final (r1q, g1q, b1q) = _quantizeColor(e1);

  final block = Uint8List(16);
  _setBits(block, 0, 11, _kBlockMode);
  _setBits(block, 11, 2, 0); // one partition
  _setBits(block, 13, 4, _kCemLdrRgbDirect);

  // **The second endpoint must not be the darker one.** For `LDR RGB Direct`
  // the decoder compares the two sums and, when the first is the larger, reads
  // the pair swapped *and* blue-contracted — a different colour entirely. So
  // the encoder orders them and inverts the weights to match, rather than
  // letting a block whose endpoints happen to come out that way round decode
  // as something else.
  var (ra, ga, ba) = (r0q, g0q, b0q);
  var (rb, gb, bb) = (r1q, g1q, b1q);
  final swapped = rb + gb + bb < ra + ga + ba;
  if (swapped) {
    final tr = ra, tg = ga, tb = ba;
    ra = rb;
    ga = gb;
    ba = bb;
    rb = tr;
    gb = tg;
    bb = tb;
  }

  var cursor = 17;
  for (final value in <int>[ra, rb, ga, gb, ba, bb]) {
    cursor = _setBits(block, cursor, _kColorBits, value);
  }

  final lowExpanded = _expandColor(ra, ga, ba);
  final highExpanded = _expandColor(rb, gb, bb);

  // **The weights live at the top of the block, reversed.** ASTC stores the
  // weight stream growing downward from bit 127, with the bit order flipped —
  // so it is built here in an ordinary buffer and then folded in byte by byte,
  // each byte reversed and taken from the other end. Written forwards, as this
  // file did before `gfx-88n`, every weight lands somewhere else.
  final weights = Uint8List(16);
  var weightCursor = 0;
  for (var i = 0; i < 16; i++) {
    final (er, eg, eb, _) = pixels[i];
    var bestWeight = 0;
    var bestError = double.infinity;
    for (var w = 0; w <= _kWeightMax; w++) {
      final (dr, dg, db) = _lerpColor(lowExpanded, highExpanded, w / _kWeightMax);
      final errR = er - dr, errG = eg - dg, errB = eb - db;
      final error = errR * errR + errG * errG + errB * errB;
      if (error < bestError) {
        bestError = error;
        bestWeight = w;
      }
    }
    weightCursor = _setBits(weights, weightCursor, _kWeightBits, bestWeight);
  }

  for (var i = 0; i < 16; i++) {
    block[i] |= _reverseByte(weights[15 - i]);
  }

  return block;
}

(int, int, int) _quantizeColor((double, double, double) rgb) {
  final (r, g, b) = rgb;
  int q(double v) => (v * _kColorMax / 255).round().clamp(0, _kColorMax);
  return (q(r), q(g), q(b));
}

(double, double, double) _expandColor(int r, int g, int b) {
  double e(int v) => v * 255 / _kColorMax;
  return (e(r), e(g), e(b));
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

/// The same power-iteration principal-axis fit [encodeBc1Block] uses —
/// duplicated rather than shared, since Dart's library privacy keeps
/// `bc1_encoder.dart`'s own copy out of reach from here, and the fit is
/// small enough that sharing it would cost an export neither encoder's
/// public API otherwise needs.
(double, double, double) _principalAxis(
  List<(double, double, double)> rgb,
  double meanR,
  double meanG,
  double meanB,
) {
  var cRR = 0.0, cRG = 0.0, cRB = 0.0, cGG = 0.0, cGB = 0.0, cBB = 0.0;
  for (final (r, g, b) in rgb) {
    final dr = r - meanR, dg = g - meanG, db = b - meanB;
    cRR += dr * dr;
    cRG += dr * dg;
    cRB += dr * db;
    cGG += dg * dg;
    cGB += dg * db;
    cBB += db * db;
  }

  var vr = cRR + cRG + cRB;
  var vg = cRG + cGG + cGB;
  var vb = cRB + cGB + cBB;
  if (vr == 0 && vg == 0 && vb == 0) return (1, 0, 0); // a flat block

  for (var i = 0; i < 8; i++) {
    final nr = cRR * vr + cRG * vg + cRB * vb;
    final ng = cRG * vr + cGG * vg + cGB * vb;
    final nb = cRB * vr + cGB * vg + cBB * vb;
    final length = _length(nr, ng, nb);
    if (length == 0) break;
    vr = nr / length;
    vg = ng / length;
    vb = nb / length;
  }
  final length = _length(vr, vg, vb);
  return length == 0 ? (1, 0, 0) : (vr / length, vg / length, vb / length);
}

double _length(double x, double y, double z) => _sqrt(x * x + y * y + z * z);

double _sqrt(double x) {
  if (x <= 0) return 0;
  var guess = x;
  for (var i = 0; i < 12; i++) {
    guess = 0.5 * (guess + x / guess);
  }
  return guess;
}

/// Writes [value]'s low [numBits] bits into [block] starting at bit
/// [bitOffset] (bit 0 is the LSB of byte 0, rising through each byte then
/// into the next), and returns `bitOffset + numBits` — the next field's
/// offset, so a run of fields can chain calls without recomputing cursors.
/// The bits of one byte, back to front — what the weight stream's placement
/// needs. A table rather than a loop: it is called sixteen times per block.
int _reverseByte(int value) {
  var out = 0;
  for (var i = 0; i < 8; i++) {
    if ((value >> i) & 1 != 0) out |= 1 << (7 - i);
  }
  return out;
}

int _setBits(Uint8List block, int bitOffset, int numBits, int value) {
  for (var i = 0; i < numBits; i++) {
    if (((value >> i) & 1) != 0) {
      final pos = bitOffset + i;
      block[pos >> 3] |= 1 << (pos & 7);
    }
  }
  return bitOffset + numBits;
}
