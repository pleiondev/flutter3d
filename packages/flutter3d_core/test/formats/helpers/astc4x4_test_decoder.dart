/// A decoder for the block layout `astc4x4_encoder.dart`'s own doc comment
/// documents: single partition, single plane, a 4×4 weight grid, `LDR RGB
/// Direct` endpoints. Written only so a test can ask what came back out of
/// what the encoder wrote — see `bc_test_decoders.dart`'s doc comment for why
/// this stays out of `lib/`, and `astc4x4_encoder.dart`'s own doc comment for
/// the real gap this leaves: nothing here (or in the encoder) is checked
/// against a real GPU's own ASTC block-mode decode.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';

const int _kColorBits = 7;
const int _kColorMax = (1 << _kColorBits) - 1; // 127
const int _kWeightBits = 4;
const int _kWeightMax = (1 << _kWeightBits) - 1; // 15

Rgba8Image decodeAstc4x4(Uint8List bytes, int width, int height) {
  final blocksX = width ~/ 4;
  final blocksY = height ~/ 4;
  final out = Uint8List(width * height * 4);
  var offset = 0;
  for (var by = 0; by < blocksY; by++) {
    for (var bx = 0; bx < blocksX; bx++) {
      final block = decodeAstc4x4Block(
        Uint8List.sublistView(bytes, offset, offset + 16),
      );
      for (var py = 0; py < 4; py++) {
        for (var px = 0; px < 4; px++) {
          final x = bx * 4 + px;
          final y = by * 4 + py;
          final src = (py * 4 + px) * 4;
          final dst = (y * width + x) * 4;
          out.setRange(dst, dst + 4, block, src);
        }
      }
      offset += 16;
    }
  }
  return Rgba8Image(width: width, height: height, pixels: out);
}

/// Reads one block `encodeAstc4x4Block` wrote: six [_kColorBits]-wide
/// endpoint channel values starting right after the 11-bit header, 2-bit
/// partition count and 4-bit CEM (17 bits), then sixteen [_kWeightBits]-wide
/// per-texel weights packed from the end of the block backward, one per
/// texel in raster order — the exact layout `astc4x4_encoder.dart`'s own doc
/// comment describes and this file does not reproduce the specification's
/// version of.
List<int> decodeAstc4x4Block(Uint8List block) {
  var cursor = 17;
  final values = <int>[];
  for (var i = 0; i < 6; i++) {
    values.add(_getBits(block, cursor, _kColorBits));
    cursor += _kColorBits;
  }
  final (r0, g0, b0) = _expandColor(values[0], values[2], values[4]);
  final (r1, g1, b1) = _expandColor(values[1], values[3], values[5]);

  final out = List<int>.filled(64, 0);
  for (var i = 0; i < 16; i++) {
    final weightOffset = 128 - (i + 1) * _kWeightBits;
    final w = _getBits(block, weightOffset, _kWeightBits);
    final t = w / _kWeightMax;
    out[i * 4] = (r0 + (r1 - r0) * t).round().clamp(0, 255);
    out[i * 4 + 1] = (g0 + (g1 - g0) * t).round().clamp(0, 255);
    out[i * 4 + 2] = (b0 + (b1 - b0) * t).round().clamp(0, 255);
    out[i * 4 + 3] = 255;
  }
  return out;
}

(double, double, double) _expandColor(int r, int g, int b) {
  double e(int v) => v * 255 / _kColorMax;
  return (e(r), e(g), e(b));
}

int _getBits(Uint8List block, int bitOffset, int numBits) {
  var value = 0;
  for (var i = 0; i < numBits; i++) {
    final pos = bitOffset + i;
    final bit = (block[pos >> 3] >> (pos & 7)) & 1;
    value |= bit << i;
  }
  return value;
}
