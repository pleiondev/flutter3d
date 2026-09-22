/// A cooked texture that is not yet a GPU format — `gfx-83n`.
///
/// **The problem this exists for.** `texture_encode.dart` bakes one final
/// format at CLI time, so a cooked asset belongs to the device family it was
/// cooked for: BC on a desktop, ETC2 on a phone, and a build for both ships
/// the texture twice. What a device-agnostic pipeline cooks instead is a 4×4
/// block *intermediate*, and the load turns it into whatever the device
/// reports sampling.
///
/// **The intermediate is the shape the other formats already agree on.** BC1,
/// BC3's alpha half and this package's ASTC subset are the same idea written
/// three ways: two endpoints and one index per texel along the line between
/// them. A block here is exactly that, at the finest precision any of them
/// uses — eight bits per endpoint channel, eight evenly spaced levels per
/// texel, for colour and for alpha alike.
///
/// ```text
///  byte  0..2   endpoint 0, R G B, eight bits each
///  byte  3..5   endpoint 1
///  byte  6..11  sixteen 3-bit colour weights, texel i at bit 3i
///  byte 12      alpha at weight 0
///  byte 13      alpha at weight 7
///  byte 14..19  sixteen 3-bit alpha weights, packed the same way
/// ```
///
/// Weight `w` means the texel is `lerp(endpoint0, endpoint1, w / 7)`, and the
/// alpha half reads the same way against its own pair. Twenty bytes a block —
/// a quarter more than UASTC and two and a half times BC1, which is the size
/// of the trade: the cooked file is bigger than a final-format one and it is
/// the only file.
///
/// **Eight levels is what makes two of the three legs exact.** ASTC's weights
/// here are eight levels and BC3's alpha ramp is eight values, so both take
/// the intermediate's index unchanged and only the endpoints move — for ASTC
/// not even those, since both hold eight-bit channels. BC1 has four levels and
/// so re-picks, against the palette its own quantised endpoints give, which is
/// the same search `encodeBc1Block` runs.
///
/// Measured against the Khronos sample texture `ktx2_encoder_psnr_test.dart`
/// uses, going through the intermediate rather than encoding the source
/// directly costs: ASTC nothing (38.3 dB either way), BC1 0.6 dB, ETC2 0.9 dB.
/// Four levels in the intermediate, which would have made BC1's leg a relabel
/// instead of a search, cost ASTC 5.5 dB and ETC2 3.1 dB — which is what
/// decided the width.
///
/// **ETC2 is the leg with no shortcut.** ETC does not store endpoints; it
/// stores a base colour per half-block and a signed offset from a table, so
/// there is no relabelling that turns one into the other. That leg decodes the
/// block and re-encodes it, which is correct and slow: a second per 1024²
/// level, against 32 ms for BC1, 39 for ASTC and 55 for BC3. A table-driven
/// fast path is what Basis Universal does there and it is not written here,
/// so a device whose best format is ETC2 pays that second on the isolate the
/// load already runs the transcode on.
///
/// **Alpha survives to BC3 and to RGBA8 only.** This package's ASTC subset is
/// `LDR RGB Direct` and its ETC2 is RGB8; neither carries alpha, which is what
/// [UniversalTarget.carriesAlpha] says and what the engine's own target choice
/// reads before sending a texture with alpha anywhere.
library;

import 'dart:typed_data';

import '../encode/astc4x4_encoder.dart';
import '../encode/bc1_encoder.dart';
import '../encode/bc3_encoder.dart';
import '../encode/etc2_encoder.dart';
import '../encode/principal_axis.dart';
import '../encode/rgba8_image.dart';
import '../ktx2_format.dart';

/// Bytes per block: six of endpoints, six of colour weights, two of alpha
/// endpoints and six of alpha weights.
const int kUniversalBlockBytes = 20;

/// How many levels one weight names — see the library comment for why this is
/// the number ASTC and BC3's alpha both use natively.
const int kUniversalWeightLevels = 8;

/// The last of them, which is what a weight is mirrored against when a target
/// orders its endpoints the other way round.
const int _kMaxWeight = kUniversalWeightLevels - 1;

const int _kColorWeights = 6;
const int _kAlphaHigh = 12;
const int _kAlphaLow = 13;
const int _kAlphaWeights = 14;

/// The KTX2 key/value key that says a file's blocks are these.
///
/// A universal file's `vkFormat` is `VK_FORMAT_UNDEFINED`, which is also what
/// Basis Universal writes, so the header alone cannot tell them apart — Basis
/// is then distinguished by its supercompression scheme and this by the key.
const String kUniversalBlockKey = 'f3dBlockFormat';

/// The key's value for a texture whose alpha is opaque throughout.
const String kUniversalBlockRgb = 'endpoint-weight-4x4-v1/rgb';

/// The key's value for a texture that carries alpha.
const String kUniversalBlockRgba = 'endpoint-weight-4x4-v1/rgba';

/// What a universal level can be turned into at load.
///
/// A `final class` with const instances rather than an `enum`, the same shape
/// `TextureFamily` takes and for the same reason: a target is a thing a later
/// format is added to — BC7 and ASTC with alpha are both obvious next ones —
/// and adding a value to an exported enum breaks every `switch` written
/// against it. Each instance carries what it is rather than being read by a
/// switch somewhere else, so adding one is a line here and nothing elsewhere.
final class UniversalTarget {
  const UniversalTarget._(
    this.name, {
    required this.vkFormat,
    required this.bytesPerBlock,
    required this.carriesAlpha,
    required this.encodeBlock,
  });

  /// BC1, eight bytes a block, no alpha.
  static const UniversalTarget bc1 = UniversalTarget._(
    'bc1',
    vkFormat: VkFormat.bc1RgbaUNormBlock,
    bytesPerBlock: 8,
    carriesAlpha: false,
    encodeBlock: _toBc1Block,
  );

  /// BC3, sixteen bytes a block, alpha in the first eight.
  static const UniversalTarget bc3 = UniversalTarget._(
    'bc3',
    vkFormat: VkFormat.bc3UNormBlock,
    bytesPerBlock: 16,
    carriesAlpha: true,
    encodeBlock: _toBc3Block,
  );

  /// ASTC 4×4 LDR, sixteen bytes a block, no alpha — see the library comment.
  static const UniversalTarget astc4x4 = UniversalTarget._(
    'astc4x4',
    vkFormat: VkFormat.astc4x4UNormBlock,
    bytesPerBlock: 16,
    carriesAlpha: false,
    encodeBlock: _toAstcBlock,
  );

  /// ETC2 RGB8, eight bytes a block, no alpha, and the slow leg.
  static const UniversalTarget etc2Rgb8 = UniversalTarget._(
    'etc2Rgb8',
    vkFormat: VkFormat.etc2R8g8b8UNormBlock,
    bytesPerBlock: 8,
    carriesAlpha: false,
    encodeBlock: _toEtc2Block,
  );

  /// Plain RGBA8. Not a block format: the fallback for a device that samples
  /// none of the others, and the one target that never loses a channel.
  static const UniversalTarget rgba8 = UniversalTarget._(
    'rgba8',
    vkFormat: VkFormat.r8g8b8a8UNorm,
    bytesPerBlock: 0,
    carriesAlpha: true,
    encodeBlock: null,
  );

  static const List<UniversalTarget> values = <UniversalTarget>[
    bc1,
    bc3,
    astc4x4,
    etc2Rgb8,
    rgba8,
  ];

  final String name;

  /// What the level's bytes are once this target has them — the number a
  /// caller puts in a KTX2 header or maps to its own texture format.
  final int vkFormat;

  /// Zero for [rgba8], which is not blocks at all.
  final int bytesPerBlock;

  final bool carriesAlpha;

  /// One block of [blocks] as this target, or null for [rgba8], which is a
  /// raster and is written whole rather than a block at a time.
  final Uint8List Function(Uint8List blocks, int index)? encodeBlock;

  @override
  String toString() => name;
}

/// Encodes [image] as universal blocks, one per 4×4 tile.
Uint8List encodeUniversalBlocks(Rgba8Image image) {
  requireWholeBlocks(image, 'encodeUniversalBlocks');
  final blocksX = image.width ~/ 4;
  final blocksY = image.height ~/ 4;
  final out = Uint8List(blocksX * blocksY * kUniversalBlockBytes);
  var offset = 0;
  for (var by = 0; by < blocksY; by++) {
    for (var bx = 0; bx < blocksX; bx++) {
      out.setRange(
        offset,
        offset + kUniversalBlockBytes,
        encodeUniversalBlock(readBlock(image, bx, by)),
      );
      offset += kUniversalBlockBytes;
    }
  }
  return out;
}

/// Encodes one 4×4 block (sixteen `(r, g, b, a)` tuples, row-major).
Uint8List encodeUniversalBlock(List<(int, int, int, int)> pixels) {
  final fit = blockEndpoints(pixels);
  final e0 = _round(fit.high);
  final e1 = _round(fit.low);
  final alpha = blockAlphaRange(pixels);

  final block = Uint8List(kUniversalBlockBytes);
  block[0] = e0.$1;
  block[1] = e0.$2;
  block[2] = e0.$3;
  block[3] = e1.$1;
  block[4] = e1.$2;
  block[5] = e1.$3;
  block[_kAlphaHigh] = alpha.high;
  block[_kAlphaLow] = alpha.low;

  for (var i = 0; i < 16; i++) {
    final (r, g, b, a) = pixels[i];
    _putWeight(block, _kColorWeights, i, _nearestColorWeight(r, g, b, e0, e1));
    _putWeight(
      block,
      _kAlphaWeights,
      i,
      _nearestAlphaWeight(a, alpha.high, alpha.low),
    );
  }
  return block;
}

/// The sixteen texels of block [index], row-major — what the legs with no
/// structural shortcut start from, and what a test compares against.
List<(int, int, int, int)> decodeUniversalBlock(Uint8List blocks, int index) {
  final at = index * kUniversalBlockBytes;
  final e0 = (blocks[at], blocks[at + 1], blocks[at + 2]);
  final e1 = (blocks[at + 3], blocks[at + 4], blocks[at + 5]);
  final a0 = blocks[at + _kAlphaHigh];
  final a1 = blocks[at + _kAlphaLow];
  return <(int, int, int, int)>[
    for (var i = 0; i < 16; i++)
      _texel(
        e0,
        e1,
        a0,
        a1,
        _weight(blocks, at + _kColorWeights, i),
        _weight(blocks, at + _kAlphaWeights, i),
      ),
  ];
}

/// [blocks] as [target], ready to upload.
///
/// [width] and [height] are the level's pixel dimensions; only [
/// UniversalTarget.rgba8] reads them, and it needs them because it is the one
/// target whose bytes are a raster rather than a sequence of blocks.
Uint8List transcodeUniversal(
  Uint8List blocks,
  UniversalTarget target, {
  required int width,
  required int height,
}) {
  if (blocks.lengthInBytes % kUniversalBlockBytes != 0) {
    throw ArgumentError(
      'A universal level is whole $kUniversalBlockBytes-byte blocks; '
      '${blocks.lengthInBytes} bytes is not.',
    );
  }
  final count = blocks.lengthInBytes ~/ kUniversalBlockBytes;
  final encodeBlock = target.encodeBlock;
  if (encodeBlock == null) return _toRgba8(blocks, count, width, height);

  final out = Uint8List(count * target.bytesPerBlock);
  for (var i = 0; i < count; i++) {
    out.setRange(
      i * target.bytesPerBlock,
      (i + 1) * target.bytesPerBlock,
      encodeBlock(blocks, i),
    );
  }
  return out;
}

/// The leg with no structural shortcut: the block's texels, re-encoded. See
/// the library comment for what that costs and why there is no other way to
/// reach ETC from a pair of endpoints.
Uint8List _toEtc2Block(Uint8List blocks, int index) =>
    encodeEtc2Rgb8Block(decodeUniversalBlock(blocks, index));

/// **BC1 is the one leg that searches**, because four levels cannot take eight
/// unchanged. The search is over the four entries of the palette BC1's own
/// *quantised* endpoints give, which is exactly what [encodeBc1Block] does
/// once it has picked its endpoints — so this arrives at the index that
/// encoder would have, from endpoints chosen by the same fit, without redoing
/// the fit.
Uint8List _toBc1Block(Uint8List blocks, int index) {
  final at = index * kUniversalBlockBytes;
  final e0 = (blocks[at], blocks[at + 1], blocks[at + 2]);
  final e1 = (blocks[at + 3], blocks[at + 4], blocks[at + 5]);
  final packed = packBc1Endpoints(e0, e1);
  final palette = bc1Palette(packed.pack0, packed.pack1);

  var indices = 0;
  for (var i = 0; i < 16; i++) {
    final weight = _weight(blocks, at + _kColorWeights, i);
    final r = _lerp8(e0.$1, e1.$1, weight);
    final g = _lerp8(e0.$2, e1.$2, weight);
    final b = _lerp8(e0.$3, e1.$3, weight);
    var best = 0;
    var bestError = 1 << 30;
    for (var p = 0; p < 4; p++) {
      final (pr, pg, pb) = palette[p];
      final dr = r - pr, dg = g - pg, db = b - pb;
      final error = dr * dr + dg * dg + db * db;
      if (error < bestError) {
        bestError = error;
        best = p;
      }
    }
    indices |= best << (2 * i);
  }

  final out = Uint8List(8);
  final view = ByteData.sublistView(out);
  view.setUint16(0, packed.pack0, Endian.little);
  view.setUint16(2, packed.pack1, Endian.little);
  view.setUint32(4, indices, Endian.little);
  return out;
}

Uint8List _toBc3Block(Uint8List blocks, int index) {
  final at = index * kUniversalBlockBytes;
  final a0 = blocks[at + _kAlphaHigh];
  final a1 = blocks[at + _kAlphaLow];
  // BC3's alpha ramp is eight values between two endpoints, which is the
  // intermediate's own alpha exactly; handing the decoded values back to the
  // encoder rather than relabelling the indices keeps one implementation of
  // the flat-block tie [encodeBc3AlphaBlock] has to break, and costs sixteen
  // comparisons against eight candidates.
  final alphas = <int>[
    for (var i = 0; i < 16; i++)
      _lerp8(a0, a1, _weight(blocks, at + _kAlphaWeights, i)),
  ];

  final out = Uint8List(16);
  out.setRange(0, 8, encodeBc3AlphaBlock(alphas));
  out.setRange(8, 16, _toBc1Block(blocks, index));
  return out;
}

/// **The exact leg**: eight-bit endpoints and eight weight levels are what
/// this package's ASTC subset holds too, so nothing is requantised and nothing
/// is re-picked. Only the order can differ — `LDR RGB Direct` reads the pair
/// swapped when the first channel sum is the larger — and a swap mirrors every
/// weight rather than changing any of them.
Uint8List _toAstcBlock(Uint8List blocks, int index) {
  final at = index * kUniversalBlockBytes;
  final ordered = orderAstc4x4Endpoints(
    (blocks[at], blocks[at + 1], blocks[at + 2]),
    (blocks[at + 3], blocks[at + 4], blocks[at + 5]),
  );
  final weights = <int>[
    for (var i = 0; i < 16; i++)
      if (_weight(blocks, at + _kColorWeights, i) case final w)
        ordered.swapped ? _kMaxWeight - w : w,
  ];
  return packAstc4x4Block(
    endpoint0: ordered.low,
    endpoint1: ordered.high,
    weights: weights,
  );
}

Uint8List _toRgba8(Uint8List blocks, int count, int width, int height) {
  final blocksX = width ~/ 4;
  if (blocksX * (height ~/ 4) != count) {
    throw ArgumentError(
      'A ${width}x$height level is ${blocksX * (height ~/ 4)} blocks, and '
      '$count were given.',
    );
  }
  final out = Uint8List(width * height * 4);
  for (var block = 0; block < count; block++) {
    final texels = decodeUniversalBlock(blocks, block);
    final x0 = (block % blocksX) * 4;
    final y0 = (block ~/ blocksX) * 4;
    for (var i = 0; i < 16; i++) {
      final (r, g, b, a) = texels[i];
      final at = ((y0 + i ~/ 4) * width + x0 + i % 4) * 4;
      out[at] = r;
      out[at + 1] = g;
      out[at + 2] = b;
      out[at + 3] = a;
    }
  }
  return out;
}

(int, int, int, int) _texel(
  (int, int, int) e0,
  (int, int, int) e1,
  int a0,
  int a1,
  int colorWeight,
  int alphaWeight,
) => (
  _lerp8(e0.$1, e1.$1, colorWeight),
  _lerp8(e0.$2, e1.$2, colorWeight),
  _lerp8(e0.$3, e1.$3, colorWeight),
  _lerp8(a0, a1, alphaWeight),
);

/// `from` at weight 0, `to` at the last weight, rounded — the one
/// interpolation both
/// halves of a block and every transcode leg read the same way.
///
/// Written as a weighted sum rather than `from + delta * w ~/ 3` because `~/`
/// truncates towards zero, which would round a descending ramp the other way
/// from an ascending one and make the two endpoints of a block behave
/// differently depending on which was brighter.
int _lerp8(int from, int to, int weight) =>
    ((from * (_kMaxWeight - weight) + to * weight) / _kMaxWeight).round();

int _nearestColorWeight(
  int r,
  int g,
  int b,
  (int, int, int) e0,
  (int, int, int) e1,
) {
  var best = 0;
  var bestError = 1 << 30;
  for (var w = 0; w < kUniversalWeightLevels; w++) {
    final dr = r - _lerp8(e0.$1, e1.$1, w);
    final dg = g - _lerp8(e0.$2, e1.$2, w);
    final db = b - _lerp8(e0.$3, e1.$3, w);
    final error = dr * dr + dg * dg + db * db;
    if (error < bestError) {
      bestError = error;
      best = w;
    }
  }
  return best;
}

int _nearestAlphaWeight(int a, int a0, int a1) {
  var best = 0;
  var bestError = 1 << 30;
  for (var w = 0; w < kUniversalWeightLevels; w++) {
    final error = (a - _lerp8(a0, a1, w)).abs();
    if (error < bestError) {
      bestError = error;
      best = w;
    }
  }
  return best;
}

(int, int, int) _round((double, double, double) rgb) => (
  rgb.$1.round().clamp(0, 255),
  rgb.$2.round().clamp(0, 255),
  rgb.$3.round().clamp(0, 255),
);

/// Texel [texel]'s weight, from the six-byte field starting at [base].
///
/// Three bits do not divide a byte, so a weight can straddle two of them —
/// read low bits first, then whatever is left from the byte above. Nothing
/// here assembles the field into one integer: on the web an `int` is a double
/// and a 48-bit shift is not the operation it looks like.
int _weight(Uint8List blocks, int base, int texel) {
  final bit = texel * 3;
  final byte = base + (bit >> 3);
  final offset = bit & 7;
  final low = blocks[byte] >> offset;
  return (offset <= 5 ? low : low | (blocks[byte + 1] << (8 - offset))) & 7;
}

void _putWeight(Uint8List block, int base, int texel, int weight) {
  final bit = texel * 3;
  final byte = base + (bit >> 3);
  final offset = bit & 7;
  block[byte] |= (weight << offset) & 0xFF;
  if (offset > 5) block[byte + 1] |= weight >> (8 - offset);
}
