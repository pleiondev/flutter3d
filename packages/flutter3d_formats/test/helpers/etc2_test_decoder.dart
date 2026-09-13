/// A decoder for the ETC1-compatible subset of ETC2 RGB8 this port's own
/// encoder writes — individual and differential mode, flip = 0 only. Written
/// only so a test can ask what came back out of what the encoder wrote; see
/// `bc_test_decoders.dart`'s doc comment for why this stays out of `lib/`
/// and what actually proves the block layout against a real GPU.
library;

import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';

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

Rgba8Image decodeEtc2Rgb8(Uint8List bytes, int width, int height) {
  final blocksX = width ~/ 4;
  final blocksY = height ~/ 4;
  final out = Uint8List(width * height * 4);
  var offset = 0;
  for (var by = 0; by < blocksY; by++) {
    for (var bx = 0; bx < blocksX; bx++) {
      final block = decodeEtc2Rgb8Block(
        Uint8List.sublistView(bytes, offset, offset + 8),
      );
      for (var p = 0; p < 16; p++) {
        final col = p ~/ 4;
        final row = p % 4;
        final x = bx * 4 + col;
        final y = by * 4 + row;
        final dst = (y * width + x) * 4;
        out.setRange(dst, dst + 4, block, p * 4);
      }
      offset += 8;
    }
  }
  return Rgba8Image(width: width, height: height, pixels: out);
}

/// Sixteen RGBA bytes in the same column-major pixel order `p ~/ 4, p % 4`
/// the encoder's `_packIndices` reads — the caller above is what puts them
/// back into row-major image order.
List<int> decodeEtc2Rgb8Block(Uint8List block) {
  final byte3 = block[3];
  final diff = (byte3 & 0x2) != 0;
  final flip = (byte3 & 0x1) != 0;
  if (flip) {
    throw UnsupportedError('this test decoder only reads flip = 0 blocks');
  }
  final topTable = (byte3 >> 5) & 0x7;
  final bottomTable = (byte3 >> 2) & 0x7;

  final (int, int, int) topBase, bottomBase;
  if (diff) {
    int signed3(int v) => v >= 4 ? v - 8 : v;
    final r5 = (block[0] >> 3) & 0x1F;
    final g5 = (block[1] >> 3) & 0x1F;
    final b5 = (block[2] >> 3) & 0x1F;
    final dr = signed3(block[0] & 0x7);
    final dg = signed3(block[1] & 0x7);
    final db = signed3(block[2] & 0x7);
    int expand5(int v) => (v << 3) | (v >> 2);
    topBase = (expand5(r5), expand5(g5), expand5(b5));
    bottomBase = (
      expand5((r5 + dr).clamp(0, 31)),
      expand5((g5 + dg).clamp(0, 31)),
      expand5((b5 + db).clamp(0, 31)),
    );
  } else {
    int both4(int v) => (v << 4) | v;
    topBase = (both4(block[0] >> 4), both4(block[1] >> 4), both4(block[2] >> 4));
    bottomBase = (
      both4(block[0] & 0xF),
      both4(block[1] & 0xF),
      both4(block[2] & 0xF),
    );
  }

  final indexWord =
      ByteData.sublistView(block, 4, 8).getUint32(0, Endian.big);
  final msb = (indexWord >> 16) & 0xFFFF;
  final lsb = indexWord & 0xFFFF;

  final out = List<int>.filled(64, 0);
  for (var p = 0; p < 16; p++) {
    final inTop = (p % 4) < 2;
    final (base, table) = inTop ? (topBase, topTable) : (bottomBase, bottomTable);
    final m = (msb >> p) & 1;
    final l = (lsb >> p) & 1;
    final magnitude = _modifierTables[table][l];
    final signed = m == 0 ? magnitude : -magnitude;
    final (br, bg, bb) = base;
    out[p * 4] = (br + signed).clamp(0, 255);
    out[p * 4 + 1] = (bg + signed).clamp(0, 255);
    out[p * 4 + 2] = (bb + signed).clamp(0, 255);
    out[p * 4 + 3] = 255;
  }
  return out;
}
