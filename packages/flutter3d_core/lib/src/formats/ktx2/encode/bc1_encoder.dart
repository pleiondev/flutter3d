import 'dart:typed_data';

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
/// **Endpoints from a principal-axis fit, not a bounding box.** A block's
/// sixteen colours rarely spread along an axis aligned with R, G or B, so
/// picking `min`/`max` per channel finds a box around the data rather than a
/// line through it — visibly worse on the kind of smooth gradient a real
/// texture is made of. [_principalAxis] finds that line by power iteration
/// on the block's 3×3 covariance matrix (eight iterations converges well
/// past what an 8-bit endpoint can represent, and a 4×4 block's covariance
/// is cheap enough to build sixteen times over without it ever being the
/// slow part of an encode). The two pixels furthest apart when projected
/// onto that axis become the endpoints — not the axis's own extremes, which
/// need not be colours any real pixel has.
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

  // The two pixels whose projection onto the axis is furthest apart, not the
  // axis's own extremes — see the library doc comment.
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

  final e0 = rgb[maxIndex];
  // A flat block projects every pixel to the same point, so min and max land
  // on the same pixel; any endpoint works, and the block decodes solid
  // either way.
  final e1 = minIndex == maxIndex ? e0 : rgb[minIndex];

  var pack0 = _quantize565(e0);
  var pack1 = _quantize565(e1);
  (pack0, pack1) = _orderEndpoints(pack0, pack1);

  final (r0, g0, b0) = _expand565(pack0);
  final (r1, g1, b1) = _expand565(pack1);
  // BC1's four-color palette: the two endpoints, then 2/3 and 1/3 blends —
  // the interpolation every BC1 decoder performs, reproduced here so the
  // index each pixel picks is the index that decoder will actually resolve
  // to that pixel's nearest colour, not to the un-quantized endpoint.
  final palette = <(int, int, int)>[
    (r0, g0, b0),
    (r1, g1, b1),
    ((2 * r0 + r1) ~/ 3, (2 * g0 + g1) ~/ 3, (2 * b0 + b1) ~/ 3),
    ((r0 + 2 * r1) ~/ 3, (g0 + 2 * g1) ~/ 3, (b0 + 2 * b1) ~/ 3),
  ];

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

/// The dominant direction sixteen `(r, g, b)` points vary along, found by
/// power iteration on their covariance matrix rather than an eigenvalue
/// solver — a 3×3 matrix converges in a handful of iterations and needs no
/// dependency this package does not already carry.
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

  // Seeded along the block's own colour range rather than an arbitrary axis:
  // a block that varies in only one channel (a pure red gradient, say) would
  // otherwise converge slower from a symmetric start, and eight iterations
  // is a budget chosen assuming a reasonable seed.
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

int _quantize565((double, double, double) rgb) {
  final (r, g, b) = rgb;
  final r5 = (r * 31 / 255).round().clamp(0, 31);
  final g6 = (g * 63 / 255).round().clamp(0, 63);
  final b5 = (b * 31 / 255).round().clamp(0, 31);
  return (r5 << 11) | (g6 << 5) | b5;
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
