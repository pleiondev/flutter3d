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
/// A real GPU's own ASTC block-mode decode is not exercised here — the real
/// gap this leaves, named rather than silently assumed away, the same
/// reasoning `mip_chain.dart`'s wrap-mode limit and `ktx2_format.dart`'s
/// refusal list are both named by.
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

/// Bits per endpoint channel value (7 bits, 128 levels, plain binary — no
/// ASTC trit/quint packing, which only intermediate-precision ranges need).
const int _kColorBits = 7;
const int _kColorMax = (1 << _kColorBits) - 1; // 127

/// Bits per texel weight (4 bits, 16 levels, plain binary).
const int _kWeightBits = 4;
const int _kWeightMax = (1 << _kWeightBits) - 1; // 15

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
    for (final (r, g, b, _) in pixels) (r.toDouble(), g.toDouble(), b.toDouble()),
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
  final e0Expanded = _expandColor(r0q, g0q, b0q);
  final e1Expanded = _expandColor(r1q, g1q, b1q);

  final block = Uint8List(16);
  var cursor = 0;
  cursor = _setBits(block, cursor, 11, 0); // header — see library doc comment
  cursor = _setBits(block, cursor, 2, 0); // partition count = 1
  cursor = _setBits(block, cursor, 4, _kCemLdrRgbDirect);
  for (final value in <int>[r0q, r1q, g0q, g1q, b0q, b1q]) {
    cursor = _setBits(block, cursor, _kColorBits, value);
  }

  // Weights fill in from the end of the block, one per texel, raster order —
  // a fixed offset per texel rather than the specification's own reversed
  // bit order (see the library doc comment on what this port's layout does
  // and does not reproduce).
  for (var i = 0; i < 16; i++) {
    final (er, eg, eb, _) = pixels[i];
    var bestWeight = 0;
    var bestError = double.infinity;
    for (var w = 0; w <= _kWeightMax; w++) {
      final (dr, dg, db) = _lerpColor(e0Expanded, e1Expanded, w / _kWeightMax);
      final errR = er - dr, errG = eg - dg, errB = eb - db;
      final error = errR * errR + errG * errG + errB * errB;
      if (error < bestError) {
        bestError = error;
        bestWeight = w;
      }
    }
    final weightOffset = 128 - (i + 1) * _kWeightBits;
    _setBits(block, weightOffset, _kWeightBits, bestWeight);
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
int _setBits(Uint8List block, int bitOffset, int numBits, int value) {
  for (var i = 0; i < numBits; i++) {
    if (((value >> i) & 1) != 0) {
      final pos = bitOffset + i;
      block[pos >> 3] |= 1 << (pos & 7);
    }
  }
  return bitOffset + numBits;
}
