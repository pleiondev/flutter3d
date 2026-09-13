import 'dart:typed_data';

import 'rgba8_image.dart';

/// The eight "intensity modifier" tables ETC1 (and ETC2's individual and
/// differential modes, which are ETC1 blocks by construction) select a pair
/// from per sub-block. Khronos's own numbers — `KhronosGroup/KTX-Software`
/// states them as `etc1_utils.cc` does, copied rather than derived for the
/// reason `ktx2_format.dart`'s `VkFormat` gives about numbers like these.
///
/// A pixel's 2-bit code picks a signed value from the row a sub-block names
/// in byte 3: `(0, 0)` is `+table[0]`, `(0, 1)` is `+table[1]`, `(1, 0)` is
/// `-table[0]`, `(1, 1)` is `-table[1]` — confirmed against a real GPU by
/// `flutter3d_conformance`'s `checkCompressedTextureSamples`, whose all-zero
/// index block under table 0 is documented there as decoding to `+2`, which
/// is exactly `+_modifierTables[0][0]`.
const List<List<int>> _modifierTables = <List<int>>[
  [2, 8],
  [5, 17],
  [9, 29],
  [13, 42],
  [18, 60],
  [24, 80],
  [33, 106],
  [47, 183],
];

/// Encodes [image] as ETC2 RGB8 (`vkFormat.etc2R8g8b8UNormBlock`): one
/// 8-byte block per 4×4 tile.
///
/// **The ETC1-compatible subset of ETC2's modes, not the full format.** ETC2
/// added three block modes over ETC1 — "T", "H" and "planar" — each a
/// different trade of precision for a specific kind of block (planar for a
/// smooth gradient across all sixteen texels, T/H for a block with one
/// colour cutting sharply through the rest). None is required: every ETC2
/// decoder — hardware or software — already accepts an ETC1 block as valid
/// ETC2, because ETC2 is specified as a strict superset. What is given up is
/// some quality on the specific block shapes those modes target, not
/// correctness or conformance; picking the better of ETC1's own two modes
/// (individual, differential) per block, done here, is most of the way
/// there and a fraction of the code.
///
/// **Individual or differential mode, chosen per block, never the flip
/// bit's alternative split.** Both encode two 4×2 sub-blocks stacked
/// vertically (rows 0–1, rows 2–3) — flip = 0 throughout — rather than ever
/// trying the 2×4 side-by-side split flip = 1 offers. A real encoder gets a
/// little more from choosing per block; this one accepts the loss for the
/// same reason it skips T/H/planar: the two vertical halves already carry
/// two independent base colours and tables, which is most of what a smarter
/// split would add.
Uint8List encodeEtc2Rgb8(Rgba8Image image) {
  requireWholeBlocks(image, 'encodeEtc2Rgb8');
  final blocksX = image.width ~/ 4;
  final blocksY = image.height ~/ 4;
  final out = Uint8List(blocksX * blocksY * 8);
  var offset = 0;
  for (var by = 0; by < blocksY; by++) {
    for (var bx = 0; bx < blocksX; bx++) {
      final block = encodeEtc2Rgb8Block(readBlock(image, bx, by));
      out.setRange(offset, offset + 8, block);
      offset += 8;
    }
  }
  return out;
}

/// Encodes one 4×4 block (row-major, alpha ignored) as the eight bytes of an
/// ETC1-compatible ETC2 RGB8 block — flip = 0, top and bottom 4×2 halves each
/// with their own base colour and modifier table.
Uint8List encodeEtc2Rgb8Block(List<(int, int, int, int)> pixels) {
  // Row-major input, top half rows 0-1 (pixels 0-7), bottom half rows 2-3
  // (pixels 8-15) — flip = 0's split.
  final top = pixels.sublist(0, 8);
  final bottom = pixels.sublist(8, 16);

  final individual = _fitIndividual(top, bottom);
  final differential = _fitDifferential(top, bottom);
  final chosen = individual.error <= differential.error ? individual : differential;

  final out = Uint8List(8);
  out[0] = chosen.byte0;
  out[1] = chosen.byte1;
  out[2] = chosen.byte2;
  out[3] = chosen.byte3;
  final indexWord = _packIndices(top, bottom, chosen);
  out[4] = (indexWord >> 24) & 0xFF;
  out[5] = (indexWord >> 16) & 0xFF;
  out[6] = (indexWord >> 8) & 0xFF;
  out[7] = indexWord & 0xFF;
  return out;
}

/// The per-block decision either fit function reaches: byte-ready base
/// colours and table indices, a per-half decoded colour to re-derive the
/// best pixel index against, and the summed squared error the two modes are
/// compared by.
final class _BlockFit {
  const _BlockFit({
    required this.byte0,
    required this.byte1,
    required this.byte2,
    required this.byte3,
    required this.topBase,
    required this.bottomBase,
    required this.topTable,
    required this.bottomTable,
    required this.error,
  });

  final int byte0, byte1, byte2, byte3;
  final (int, int, int) topBase;
  final (int, int, int) bottomBase;
  final int topTable;
  final int bottomTable;
  final int error;
}

/// Individual mode: each half's base colour is its own 4-bit-per-channel
/// average, replicated to 8 bits (`(v << 4) | v`) the same way
/// `flutter3d_conformance`'s solid block does.
_BlockFit _fitIndividual(
  List<(int, int, int, int)> top,
  List<(int, int, int, int)> bottom,
) {
  final topAvg = _average4bit(top);
  final bottomAvg = _average4bit(bottom);

  int both4(int v) => (v << 4) | v;
  final (tr, tg, tb) = topAvg;
  final (br, bg, bb) = bottomAvg;
  final topBase = (both4(tr), both4(tg), both4(tb));
  final bottomBase = (both4(br), both4(bg), both4(bb));
  // The table search needs the expanded 8-bit base a real pixel is compared
  // against, not the raw 4-bit average — passing the latter looks the same
  // type but is off by a factor that made every table look equally bad.
  final (topTable, topError) = _bestTable(top, topBase);
  final (bottomTable, bottomError) = _bestTable(bottom, bottomBase);

  return _BlockFit(
    byte0: (tr << 4) | br,
    byte1: (tg << 4) | bg,
    byte2: (tb << 4) | bb,
    byte3: (topTable << 5) | (bottomTable << 2), // diff=0, flip=0
    topBase: topBase,
    bottomBase: bottomBase,
    topTable: topTable,
    bottomTable: bottomTable,
    error: topError + bottomError,
  );
}

/// Differential mode: one 5-bit base (the top half's average, expanded to 8
/// bits with `(v << 3) | (v >> 2)`, the same expansion `_expand565` in
/// `bc1_encoder.dart` does for BC1's own 5-bit channels) plus a 3-bit signed
/// delta (`-4..3`) from it to the bottom half's average — clamped to that
/// range and refit from the clamped base, since a delta ETC2 cannot express
/// is a block this mode cannot fit exactly and individual mode is what the
/// caller falls back to when that costs more than it is worth.
_BlockFit _fitDifferential(
  List<(int, int, int, int)> top,
  List<(int, int, int, int)> bottom,
) {
  final (tr5, tg5, tb5) = _average5bit(top);
  final (br5, bg5, bb5) = _average5bit(bottom);
  final dr = (br5 - tr5).clamp(-4, 3);
  final dg = (bg5 - tg5).clamp(-4, 3);
  final db = (bb5 - tb5).clamp(-4, 3);
  final clampedBr = (tr5 + dr).clamp(0, 31);
  final clampedBg = (tg5 + dg).clamp(0, 31);
  final clampedBb = (tb5 + db).clamp(0, 31);

  int expand5(int v) => (v << 3) | (v >> 2);
  final topBase = (expand5(tr5), expand5(tg5), expand5(tb5));
  final bottomBase = (expand5(clampedBr), expand5(clampedBg), expand5(clampedBb));

  final (topTable, topError) = _bestTable(top, topBase);
  final (bottomTable, bottomError) = _bestTable(bottom, bottomBase);

  int signed3(int v) => v & 0x7; // two's complement in 3 bits
  return _BlockFit(
    byte0: (tr5 << 3) | signed3(dr),
    byte1: (tg5 << 3) | signed3(dg),
    byte2: (tb5 << 3) | signed3(db),
    byte3: (topTable << 5) | (bottomTable << 2) | 0x2, // diff=1, flip=0
    topBase: topBase,
    bottomBase: bottomBase,
    topTable: topTable,
    bottomTable: bottomTable,
    error: topError + bottomError,
  );
}

(int, int, int) _average4bit(List<(int, int, int, int)> half) {
  var r = 0, g = 0, b = 0;
  for (final (pr, pg, pb, _) in half) {
    r += pr;
    g += pg;
    b += pb;
  }
  int to4(int sum) => ((sum ~/ 8) * 15 / 255).round().clamp(0, 15);
  return (to4(r), to4(g), to4(b));
}

(int, int, int) _average5bit(List<(int, int, int, int)> half) {
  var r = 0, g = 0, b = 0;
  for (final (pr, pg, pb, _) in half) {
    r += pr;
    g += pg;
    b += pb;
  }
  int to5(int sum) => ((sum ~/ 8) * 31 / 255).round().clamp(0, 31);
  return (to5(r), to5(g), to5(b));
}

/// The table (0–7) that best fits [half] around [base], and the summed
/// squared error it leaves — tried exhaustively, since there are only eight.
(int, int) _bestTable(List<(int, int, int, int)> half, (int, int, int) base) {
  var bestTable = 0;
  var bestError = 1 << 30;
  for (var t = 0; t < _modifierTables.length; t++) {
    var error = 0;
    for (final pixel in half) {
      error += _nearestModifierError(pixel, base, t);
    }
    if (error < bestError) {
      bestError = error;
      bestTable = t;
    }
  }
  return (bestTable, bestError);
}

int _nearestModifierError(
  (int, int, int, int) pixel,
  (int, int, int) base,
  int table,
) {
  final (pr, pg, pb, _) = pixel;
  final (br, bg, bb) = base;
  var best = 1 << 30;
  for (final modifier in _modifierTables[table]) {
    for (final signed in <int>[modifier, -modifier]) {
      final dr = pr - (br + signed).clamp(0, 255);
      final dg = pg - (bg + signed).clamp(0, 255);
      final db = pb - (bb + signed).clamp(0, 255);
      final error = dr * dr + dg * dg + db * db;
      if (error < best) best = error;
    }
  }
  return best;
}

/// Packs the 2-bit index each of the sixteen pixels picks into ETC's 32-bit
/// index word.
///
/// **Column-major pixel numbering, not row-major** — ETC's own oddity, the
/// same the format's every implementation has to account for: pixel `p`
/// (0–15) sits at column `p ~/ 4`, row `p % 4`, so the block's top-left
/// texel is `p = 0` but its top-right is `p = 12`, not `p = 3`. The 32-bit
/// word is two 16-bit planes — bit `p` of the high 16 bits is that pixel's
/// MSB, bit `p` of the low 16 bits its LSB — read back exactly this way by
/// the modifier lookup `(0,0) -> +table[0]`, `(1,1) -> -table[1]` the
/// library doc comment states.
int _packIndices(
  List<(int, int, int, int)> top,
  List<(int, int, int, int)> bottom,
  _BlockFit chosen,
) {
  var msb = 0, lsb = 0;
  for (var p = 0; p < 16; p++) {
    final col = p ~/ 4;
    final row = p % 4;
    final inTop = row < 2;
    final half = inTop ? top : bottom;
    final base = inTop ? chosen.topBase : chosen.bottomBase;
    final table = inTop ? chosen.topTable : chosen.bottomTable;
    final localRow = inTop ? row : row - 2;
    final pixel = half[localRow * 4 + col];

    final (code0, code1) = _bestModifierCode(pixel, base, table);
    if (code0 != 0) msb |= 1 << p;
    if (code1 != 0) lsb |= 1 << p;
  }
  return (msb << 16) | lsb;
}

/// The 2-bit `(msb, lsb)` code whose modifier gets [pixel] closest to [base]
/// under [table].
(int, int) _bestModifierCode(
  (int, int, int, int) pixel,
  (int, int, int) base,
  int table,
) {
  final (pr, pg, pb, _) = pixel;
  final (br, bg, bb) = base;
  final codes = <(int, int, int)>[
    (0, 0, _modifierTables[table][0]),
    (0, 1, _modifierTables[table][1]),
    (1, 0, -_modifierTables[table][0]),
    (1, 1, -_modifierTables[table][1]),
  ];
  var bestMsb = 0, bestLsb = 0;
  var bestError = 1 << 30;
  for (final (msb, lsb, signed) in codes) {
    final dr = pr - (br + signed).clamp(0, 255);
    final dg = pg - (bg + signed).clamp(0, 255);
    final db = pb - (bb + signed).clamp(0, 255);
    final error = dr * dr + dg * dg + db * db;
    if (error < bestError) {
      bestError = error;
      bestMsb = msb;
      bestLsb = lsb;
    }
  }
  return (bestMsb, bestLsb);
}
