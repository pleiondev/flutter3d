import 'dart:typed_data';

import 'bc1_encoder.dart';
import 'rgba8_image.dart';

/// Encodes [image] as BC3 (`vkFormat.bc3UNormBlock`): sixteen bytes per 4×4
/// tile — an eight-byte alpha block, then the same eight-byte colour block
/// [encodeBc1Block] writes, in that order.
///
/// **The colour half is BC1's, unchanged.** BC3's colour block never has a
/// three-color-plus-transparent mode the way a standalone BC1 block can —
/// alpha lives in the block beside it — so the endpoint-ordering concern
/// [encodeBc1Block] documents does not even apply here; it is reused for the
/// fit quality, not to dodge a mode bit.
///
/// **Alpha always in eight-value mode.** BC3's alpha block has a second mode,
/// for a block whose two endpoints do not order strictly, that trades two of
/// the eight interpolated levels for hard 0 and 255 — meant for an alpha
/// channel that is genuinely binary (a cutout) rather than a ramp. A texture
/// asking for smooth alpha (a decal's soft edge, a foliage card) wants the
/// finer ramp, so [_alphaEndpoints] always forces `alpha0 > alpha1` — see its
/// own doc comment for the tie it has to break to do that.
Uint8List encodeBc3(Rgba8Image image) {
  requireWholeBlocks(image, 'encodeBc3');
  final blocksX = image.width ~/ 4;
  final blocksY = image.height ~/ 4;
  final out = Uint8List(blocksX * blocksY * 16);
  var offset = 0;
  for (var by = 0; by < blocksY; by++) {
    for (var bx = 0; bx < blocksX; bx++) {
      final pixels = readBlock(image, bx, by);
      final alphaBlock = encodeBc3AlphaBlock([
        for (final (_, _, _, a) in pixels) a,
      ]);
      final colorBlock = encodeBc1Block(pixels);
      out.setRange(offset, offset + 8, alphaBlock);
      out.setRange(offset + 8, offset + 16, colorBlock);
      offset += 16;
    }
  }
  return out;
}

/// The eight bytes of one BC3 alpha block, from sixteen alpha values in
/// row-major order.
///
/// Public since `gfx-83n`: the universal-block transcoder has decoded alpha in
/// hand and wants this half of a BC3 block without the colour half beside it.
Uint8List encodeBc3AlphaBlock(List<int> alphas) {
  var lo = 255, hi = 0;
  for (final a in alphas) {
    if (a < lo) lo = a;
    if (a > hi) hi = a;
  }
  final (a0, a1) = _alphaEndpoints(lo, hi);

  final ramp = _alphaRamp(a0, a1);
  var indices = 0;
  for (var i = 0; i < 16; i++) {
    final a = alphas[i];
    var best = 0;
    var bestError = 1 << 30;
    for (var candidate = 0; candidate < 8; candidate++) {
      final error = (a - ramp[candidate]).abs();
      if (error < bestError) {
        bestError = error;
        best = candidate;
      }
    }
    indices |= best << (3 * i);
  }

  final out = Uint8List(8);
  out[0] = a0;
  out[1] = a1;
  for (var i = 0; i < 6; i++) {
    out[2 + i] = (indices >> (8 * i)) & 0xFF;
  }
  return out;
}

/// `a0` = the block's brightest alpha, `a1` its dimmest — `a0 > a1` selects
/// the eight-value interpolation mode this encoder always wants.
///
/// **A flat block ties, and a tie flips the mode.** `a0 > a1` fails when the
/// block's alpha is a single value, which switches the decoder to the
/// six-value-plus-hard-0-and-255 mode this encoder is not writing indices
/// for — every texel would then read whichever of those eight candidates its
/// 3-bit index happens to name, essentially at random. `hi` nudged down by
/// one (or, at the floor, `lo` nudged up) costs one part in 255 of a
/// perfectly flat channel and removes the case.
(int, int) _alphaEndpoints(int lo, int hi) {
  if (hi > lo) return (hi, lo);
  return hi > 0 ? (hi, hi - 1) : (1, 0);
}

/// The eight alpha values a decoder resolves indices 0–7 to, for endpoints
/// with `a0 > a1` — the interpolation this engine's own formats state in
/// `formats.dart`'s block documentation, reproduced here bit for bit so an
/// index chosen against it is the index a real decoder resolves back to the
/// texel it was chosen for.
List<int> _alphaRamp(int a0, int a1) => <int>[
  a0,
  a1,
  ((6 * a0 + 1 * a1) + 3) ~/ 7,
  ((5 * a0 + 2 * a1) + 3) ~/ 7,
  ((4 * a0 + 3 * a1) + 3) ~/ 7,
  ((3 * a0 + 4 * a1) + 3) ~/ 7,
  ((2 * a0 + 5 * a1) + 3) ~/ 7,
  ((1 * a0 + 6 * a1) + 3) ~/ 7,
];
