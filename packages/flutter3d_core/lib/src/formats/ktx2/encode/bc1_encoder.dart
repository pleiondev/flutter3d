import 'dart:typed_data';

import 'principal_axis.dart';
import 'rgba8_image.dart';

/// Encodes [image] as BC1 (`vkFormat.bc1RgbaUNormBlock`): one 8-byte block
/// per 4×4 tile, two RGB565 endpoints and sixteen 2-bit palette picks.
///
/// **Always four-color mode.** BC1 also has a three-color-plus-transparent
/// mode, signalled by writing the first endpoint as the numerically smaller
/// of the two — this encoder never does, because nothing here ever wants a
/// transparent pixel out of a *colour* block (alpha, when a texture has it,
/// is BC3's separate half). [_orderEndpoints] enforces this by swapping and,
/// on a tie, nudging one channel by one step — see its own doc comment for
/// why a tie is not a curiosity to leave alone.
///
/// **Endpoints from a principal-axis fit, not a bounding box** — see
/// [blockEndpoints], which every block encoder here shares.
Uint8List encodeBc1(Rgba8Image image) {
  requireWholeBlocks(image, 'encodeBc1');
  final blocksX = image.width ~/ 4;
  final blocksY = image.height ~/ 4;
  final out = Uint8List(blocksX * blocksY * 8);
  var offset = 0;
  for (var by = 0; by < blocksY; by++) {
    for (var bx = 0; bx < blocksX; bx++) {
      final block = encodeBc1Block(readBlock(image, bx, by));
      out.setRange(offset, offset + 8, block);
      offset += 8;
    }
  }
  return out;
}

/// Encodes one 4×4 block (sixteen `(r, g, b, a)` tuples, row-major) as the
/// eight bytes of a single BC1 block. Alpha is ignored — BC1 has none.
Uint8List encodeBc1Block(List<(int, int, int, int)> pixels) {
  final (:high, :low) = blockEndpoints(pixels);
  var pack0 = _quantize565(high);
  var pack1 = _quantize565(low);
  (pack0, pack1) = _orderEndpoints(pack0, pack1);

  final palette = bc1Palette(pack0, pack1);

  var indices = 0;
  for (var i = 0; i < 16; i++) {
    final (r, g, b, _) = pixels[i];
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
  view.setUint16(0, pack0, Endian.little);
  view.setUint16(2, pack1, Endian.little);
  view.setUint32(4, indices, Endian.little);
  return out;
}

/// The two endpoints as a BC1 block stores them, and whether ordering had to
/// swap the pair — `gfx-83n`.
///
/// The universal-block transcoder arrives with endpoints already chosen and
/// needs BC1's quantisation, its four-colour ordering and the tie nudge
/// [_orderEndpoints] documents, without the fit or the index search. It has to
/// know about [swapped] because its own weights are written against the
/// endpoints in the order it holds them.
({int pack0, int pack1, bool swapped}) packBc1Endpoints(
  (int, int, int) e0,
  (int, int, int) e1,
) {
  final first = _quantize565((
    e0.$1.toDouble(),
    e0.$2.toDouble(),
    e0.$3.toDouble(),
  ));
  final second = _quantize565((
    e1.$1.toDouble(),
    e1.$2.toDouble(),
    e1.$3.toDouble(),
  ));
  final (pack0, pack1) = _orderEndpoints(first, second);
  return (pack0: pack0, pack1: pack1, swapped: first < second);
}

int _quantize565((double, double, double) rgb) {
  final (r, g, b) = rgb;
  final r5 = (r * 31 / 255).round().clamp(0, 31);
  final g6 = (g * 63 / 255).round().clamp(0, 63);
  final b5 = (b * 31 / 255).round().clamp(0, 31);
  return (r5 << 11) | (g6 << 5) | b5;
}

/// BC1's four-colour palette for a pair of packed endpoints: the two
/// endpoints, then the ⅔ and ⅓ blends.
///
/// The interpolation every BC1 decoder performs, reproduced so that an index
/// chosen against it is the index that decoder resolves back to the colour it
/// was chosen for — not to the un-quantised endpoint. Public since `gfx-83n`,
/// for the universal-block transcoder, which picks indices against BC1's
/// palette without running BC1's fit.
List<(int, int, int)> bc1Palette(int pack0, int pack1) {
  final (r0, g0, b0) = _expand565(pack0);
  final (r1, g1, b1) = _expand565(pack1);
  return <(int, int, int)>[
    (r0, g0, b0),
    (r1, g1, b1),
    ((2 * r0 + r1) ~/ 3, (2 * g0 + g1) ~/ 3, (2 * b0 + b1) ~/ 3),
    ((r0 + 2 * r1) ~/ 3, (g0 + 2 * g1) ~/ 3, (b0 + 2 * b1) ~/ 3),
  ];
}

(int, int, int) _expand565(int packed) {
  final r5 = (packed >> 11) & 0x1F;
  final g6 = (packed >> 5) & 0x3F;
  final b5 = packed & 0x1F;
  return ((r5 << 3) | (r5 >> 2), (g6 << 2) | (g6 >> 4), (b5 << 3) | (b5 >> 2));
}

/// Makes `pack0 > pack1`, so a decoder reads four-color mode — see the
/// library doc comment on why this encoder never wants the alternative.
///
/// **A tie survives quantization more often than the two source colours
/// would suggest.** Two visibly different endpoints can round to the same
/// 565 value — a block whose whole range is four levels of blue, say, is
/// nowhere near BC1's precision limit but can still tie in R and G. Left
/// alone, `pack0 == pack1` fails `pack0 > pack1` and the block silently
/// becomes a transparent-mode block despite carrying no alpha channel at
/// all — a block that should be a flat colour instead samples black on
/// whichever texel a real GPU treats as the transparent index. The smallest
/// step BC1 can express, added to one endpoint, costs nothing visible and
/// removes the case entirely.
(int, int) _orderEndpoints(int pack0, int pack1) {
  if (pack0 < pack1) {
    (pack0, pack1) = (pack1, pack0);
  }
  if (pack0 == pack1) {
    // The packed value is a plain 16-bit integer, so `+1` always yields a
    // strictly greater one — it is only ever blue that ripples into green
    // and red on the way, the same carry any 5:6:5 addition has. `0xFFFF`
    // (pure white, every channel saturated) is the one value with no
    // greater neighbour, so there `pack1` is nudged down instead.
    if (pack0 == 0xFFFF) {
      pack1 -= 1;
    } else {
      pack0 += 1;
    }
  }
  return (pack0, pack1);
}
