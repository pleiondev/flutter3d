/// Decoders for BC1 and BC3, written only so a test can ask "what came back
/// out of what the encoder wrote" — a real GPU is the decoder that matters,
/// and `flutter3d_conformance`'s `checkCompressedTextureSamples` already
/// proves this engine's block layout against one. This is the "тестовый
/// распаковщик" `ap-07` in `doc/asset-pipeline-plan.md` names for the PSNR
/// check, deliberately kept out of `lib/` — nothing here ships.
library;

import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';

Rgba8Image decodeBc1(Uint8List bytes, int width, int height) =>
    _decodeBlocks(bytes, width, height, 8, _decodeBc1Block);

Rgba8Image decodeBc3(Uint8List bytes, int width, int height) =>
    _decodeBlocks(bytes, width, height, 16, _decodeBc3Block);

Rgba8Image _decodeBlocks(
  Uint8List bytes,
  int width,
  int height,
  int blockBytes,
  List<int> Function(Uint8List block) decodeBlock,
) {
  final blocksX = width ~/ 4;
  final blocksY = height ~/ 4;
  final out = Uint8List(width * height * 4);
  var offset = 0;
  for (var by = 0; by < blocksY; by++) {
    for (var bx = 0; bx < blocksX; bx++) {
      final block = decodeBlock(
        Uint8List.sublistView(bytes, offset, offset + blockBytes),
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
      offset += blockBytes;
    }
  }
  return Rgba8Image(width: width, height: height, pixels: out);
}

(int, int, int) _expand565(int packed) {
  final r5 = (packed >> 11) & 0x1F;
  final g6 = (packed >> 5) & 0x3F;
  final b5 = packed & 0x1F;
  return ((r5 << 3) | (r5 >> 2), (g6 << 2) | (g6 >> 4), (b5 << 3) | (b5 >> 2));
}

/// Sixteen RGBA bytes, opaque — BC1 carries no alpha.
List<int> _decodeBc1Block(Uint8List block) {
  final view = ByteData.sublistView(block);
  final pack0 = view.getUint16(0, Endian.little);
  final pack1 = view.getUint16(2, Endian.little);
  final indices = view.getUint32(4, Endian.little);
  final (r0, g0, b0) = _expand565(pack0);
  final (r1, g1, b1) = _expand565(pack1);
  // Four-color mode only — this port's encoder never writes the other, and a
  // test decoder for it has nothing of its own to decode.
  final palette = <(int, int, int)>[
    (r0, g0, b0),
    (r1, g1, b1),
    ((2 * r0 + r1) ~/ 3, (2 * g0 + g1) ~/ 3, (2 * b0 + b1) ~/ 3),
    ((r0 + 2 * r1) ~/ 3, (g0 + 2 * g1) ~/ 3, (b0 + 2 * b1) ~/ 3),
  ];
  final out = List<int>.filled(64, 0);
  for (var i = 0; i < 16; i++) {
    final idx = (indices >> (2 * i)) & 0x3;
    final (r, g, b) = palette[idx];
    out[i * 4] = r;
    out[i * 4 + 1] = g;
    out[i * 4 + 2] = b;
    out[i * 4 + 3] = 255;
  }
  return out;
}

List<int> _decodeBc3Block(Uint8List block) {
  final alphaBlock = Uint8List.sublistView(block, 0, 8);
  final colorBlock = Uint8List.sublistView(block, 8, 16);
  final rgb = _decodeBc1Block(colorBlock);

  final a0 = alphaBlock[0];
  final a1 = alphaBlock[1];
  final List<int> ramp;
  if (a0 > a1) {
    ramp = <int>[
      a0,
      a1,
      ((6 * a0 + 1 * a1) + 3) ~/ 7,
      ((5 * a0 + 2 * a1) + 3) ~/ 7,
      ((4 * a0 + 3 * a1) + 3) ~/ 7,
      ((3 * a0 + 4 * a1) + 3) ~/ 7,
      ((2 * a0 + 5 * a1) + 3) ~/ 7,
      ((1 * a0 + 6 * a1) + 3) ~/ 7,
    ];
  } else {
    ramp = <int>[
      a0,
      a1,
      ((4 * a0 + 1 * a1) + 2) ~/ 5,
      ((3 * a0 + 2 * a1) + 2) ~/ 5,
      ((2 * a0 + 3 * a1) + 2) ~/ 5,
      ((1 * a0 + 4 * a1) + 2) ~/ 5,
      0,
      255,
    ];
  }

  var indices = 0;
  for (var i = 0; i < 6; i++) {
    indices |= alphaBlock[2 + i] << (8 * i);
  }
  for (var i = 0; i < 16; i++) {
    final idx = (indices >> (3 * i)) & 0x7;
    rgb[i * 4 + 3] = ramp[idx];
  }
  return rgb;
}
