/// The endpoint fit every block encoder in this directory starts from, in one
/// place — `gfx-83n`.
///
/// BC1, ASTC and the universal block all begin the same way: find the line a
/// block's sixteen colours actually lie along, and take the two pixels
/// furthest apart on it as the endpoints. Each had its own copy, and
/// `astc4x4_encoder.dart`'s copy carried a comment apologising for being one
/// — Dart's library privacy put `bc1_encoder.dart`'s out of reach, and the
/// answer to that is a file both can import rather than a third transcription.
library;

/// The dominant direction sixteen `(r, g, b)` points vary along, found by
/// power iteration on their covariance matrix rather than an eigenvalue
/// solver — a 3×3 matrix converges in a handful of iterations and needs no
/// dependency this package does not already carry.
(double, double, double) principalAxis(
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

/// The two pixels of [pixels] furthest apart when projected onto the block's
/// own [principalAxis] — not the axis's own extremes, which need not be
/// colours any real pixel has.
///
/// **A block's sixteen colours rarely spread along an axis aligned with R, G
/// or B**, so picking `min`/`max` per channel finds a box around the data
/// rather than a line through it — visibly worse on the kind of smooth
/// gradient a real texture is made of.
///
/// A flat block projects every pixel to the same point, so [high] and [low]
/// land on the same pixel; any endpoint works, and the block decodes solid
/// either way.
({(double, double, double) high, (double, double, double) low}) blockEndpoints(
  List<(int, int, int, int)> pixels,
) {
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

  final (axisR, axisG, axisB) = principalAxis(rgb, meanR, meanG, meanB);

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

  return (
    high: rgb[maxIndex],
    low: minIndex == maxIndex ? rgb[maxIndex] : rgb[minIndex],
  );
}

double _length(double x, double y, double z) => _sqrt(x * x + y * y + z * z);

/// Newton's method rather than `dart:math`'s `sqrt`, to keep this file — and
/// the encoders that import it — free of an import the rest of them do not
/// need. Twelve iterations converges far past what an 8-bit endpoint holds.
double _sqrt(double x) {
  if (x <= 0) return 0;
  var guess = x;
  for (var i = 0; i < 12; i++) {
    guess = 0.5 * (guess + x / guess);
  }
  return guess;
}

/// The alpha range of one block, brightest first — the endpoint pair the
/// alpha half of a block format starts from, and a straight min/max because
/// alpha is one channel and has no axis to find.
({int high, int low}) blockAlphaRange(List<(int, int, int, int)> pixels) {
  var lo = 255, hi = 0;
  for (final (_, _, _, a) in pixels) {
    if (a < lo) lo = a;
    if (a > hi) hi = a;
  }
  return (high: hi, low: lo);
}
