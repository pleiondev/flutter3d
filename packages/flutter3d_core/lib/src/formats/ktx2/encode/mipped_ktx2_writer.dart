import 'dart:typed_data';

import '../ktx2_format.dart';
import 'ktx2_writer.dart';
import 'mip_chain.dart';
import 'rgba8_image.dart';

/// `ap-08`'s own glue: builds the mip chain over [base] and writes every
/// level through [writeKtx2] in one call, so a caller that wants a
/// ready-to-load file does not have to know that a chain and a writer are
/// two different pieces.
///
/// **Levels are written uncompressed, not through one of `ap-07`'s four
/// encoders, and that is a real, named boundary rather than an oversight.**
/// `encodeBc1`/`encodeBc3`/`encodeEtc2`/`encodeAstc4x4` all
/// `requireWholeBlocks` — a 4×4 minimum — and a mip chain built down to its
/// own 1×1 end passes through 2×2 and 1×1 levels on the way, neither of
/// which is a whole block of anything. A real GPU stores such a level padded
/// to one whole block; nothing in this package pads a level to reach that
/// yet, so this function never asks an encoder to look at one. `vkFormat` is
/// [VkFormat.r8g8b8a8Srgb] or [VkFormat.r8g8b8a8UNorm] — the same plain
/// per-texel format `_uploadRgba8` in `flutter3d`'s own
/// `texture_upload.dart` already reads a multi-level chain of, uncompressed,
/// the same way a PNG's own built chain is. Threading a real per-target
/// compressed family (`ap-09`) through a chain this deep is that item's own
/// work, not silently solved here.
Uint8List writeKtx2WithMips(
  Rgba8Image base, {
  bool srgb = false,
  bool isNormalMap = false,
  double? alphaTestThreshold,
}) {
  final levels = buildMipChain(
    base,
    srgb: srgb,
    isNormalMap: isNormalMap,
    alphaTestThreshold: alphaTestThreshold,
  );
  return writeKtx2(
    vkFormat: srgb ? VkFormat.r8g8b8a8Srgb : VkFormat.r8g8b8a8UNorm,
    pixelWidth: base.width,
    pixelHeight: base.height,
    levels: [for (final level in levels) level.pixels],
  );
}
