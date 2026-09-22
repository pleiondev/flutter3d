import 'dart:math' as math;
import 'dart:typed_data';

import 'rgba8_image.dart';

/// Builds a full mip chain from [base] down to a 1×1 level, each level a
/// proper Kaiser-windowed resample of the one above rather than a box
/// average — `ap-08` in `doc/asset-pipeline-plan.md`.
///
/// **Three different channels, three different filters, because averaging
/// bytes is only ever correct for one of them.**
///
///  * [srgb] — a base-colour or emissive map's bytes are gamma-encoded, and
///    averaging them in that space darkens every edge a mip crosses (the
///    textbook mipmapping artifact: two texels at 0 and 255 average to 128
///    in byte space, but a display expects the *linear-light* average, which
///    decodes back to about 188). RGB is decoded to linear, filtered, and
///    re-encoded; alpha is never gamma data and is filtered as-is.
///  * [isNormalMap] — R, G, B decode to a `-1..1` component each, are
///    filtered as vectors (never gamma), and every output texel is
///    renormalized to unit length: averaging unit vectors does not produce
///    one, and a mip whose normals have drifted off unit length makes a
///    surface's lighting dimmer exactly where the mip is coarsest.
///  * [alphaTestThreshold] — set for a mask this engine cuts holes with, not
///    blends: an ordinary filtered alpha shrinks the fraction of texels
///    above the threshold at every level down (a leaf card's coverage drops
///    each mip and the foliage visibly thins with distance), so alpha here
///    is rescaled per level to hold the same fraction above the threshold
///    the base level has — see [_preserveCoverage].
///
/// [base]'s dimensions need not be a power of two or even square; each level
/// halves both dimensions, rounding up, down to 1×1 — the same halving a
/// GPU's own mip chain performs, so a device that reads this chain samples
/// exactly the level count [MipChain.levelsFor] in `texture_upload.dart`
/// already expects it to.
///
/// **Clamp-to-edge only.** A tiling texture wants its mip filter to wrap, the
/// same way its sampler does, so a seam at the U/V wrap does not darken at
/// distance the way an edge that clamped would. Nothing in this repository's
/// three games currently generates mips for a texture whose sampler wraps —
/// every tiled surface here samples a single level — so this is a real gap
/// named rather than a silent wrong answer for whichever texture hits it
/// first.
List<Rgba8Image> buildMipChain(
  Rgba8Image base, {
  bool srgb = false,
  bool isNormalMap = false,
  double? alphaTestThreshold,
}) {
  final baseCoverage = alphaTestThreshold == null
      ? null
      : _coverage(base, alphaTestThreshold);

  final levels = <Rgba8Image>[base];
  var current = base;
  while (current.width > 1 || current.height > 1) {
    final nextWidth = math.max(1, (current.width / 2).ceil());
    final nextHeight = math.max(1, (current.height / 2).ceil());
    current = _downsample(
      current,
      nextWidth,
      nextHeight,
      srgb: srgb,
      isNormalMap: isNormalMap,
    );
    if (baseCoverage != null) {
      current = _preserveCoverage(current, alphaTestThreshold!, baseCoverage);
    }
    levels.add(current);
  }
  return levels;
}

double _srgbToLinear(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _linearToSrgb(double c) => c <= 0.0031308
    ? c * 12.92
    : 1.055 * math.pow(c, 1 / 2.4).toDouble() - 0.055;

int _clampByte(double v) => v.round().clamp(0, 255);

Rgba8Image _downsample(
  Rgba8Image source,
  int dstWidth,
  int dstHeight, {
  required bool srgb,
  required bool isNormalMap,
}) {
  // Four independent channels, filtered separably (rows, then columns) —
  // each as plain doubles in whatever space that channel's own encoding
  // above says to filter in.
  final channels = List<List<double>>.generate(4, (c) {
    final plane = List<double>.filled(source.width * source.height, 0);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        final byte = source.pixels[(y * source.width + x) * 4 + c];
        plane[y * source.width + x] = switch ((c, srgb, isNormalMap)) {
          (0 || 1 || 2, true, _) => _srgbToLinear(byte / 255),
          (0 || 1 || 2, false, true) => byte / 255 * 2 - 1,
          _ => byte / 255,
        };
      }
    }
    return plane;
  });

  final resized = channels
      .map(
        (plane) => _resizeSeparable(
          plane,
          source.width,
          source.height,
          dstWidth,
          dstHeight,
        ),
      )
      .toList();

  final out = Uint8List(dstWidth * dstHeight * 4);
  for (var i = 0; i < dstWidth * dstHeight; i++) {
    if (isNormalMap) {
      var nx = resized[0][i];
      var ny = resized[1][i];
      var nz = resized[2][i];
      final length = math.sqrt(nx * nx + ny * ny + nz * nz);
      if (length > 1e-9) {
        nx /= length;
        ny /= length;
        nz /= length;
      } else {
        // A texel whose neighbourhood's normals cancelled out exactly —
        // vanishingly rare and, since it has no preferred direction of its
        // own, points straight out of the surface rather than encode a
        // near-zero vector no renormalization can fix.
        nx = 0;
        ny = 0;
        nz = 1;
      }
      out[i * 4] = _clampByte((nx + 1) / 2 * 255);
      out[i * 4 + 1] = _clampByte((ny + 1) / 2 * 255);
      out[i * 4 + 2] = _clampByte((nz + 1) / 2 * 255);
    } else if (srgb) {
      out[i * 4] = _clampByte(_linearToSrgb(resized[0][i].clamp(0, 1)) * 255);
      out[i * 4 + 1] = _clampByte(
        _linearToSrgb(resized[1][i].clamp(0, 1)) * 255,
      );
      out[i * 4 + 2] = _clampByte(
        _linearToSrgb(resized[2][i].clamp(0, 1)) * 255,
      );
    } else {
      out[i * 4] = _clampByte(resized[0][i] * 255);
      out[i * 4 + 1] = _clampByte(resized[1][i] * 255);
      out[i * 4 + 2] = _clampByte(resized[2][i] * 255);
    }
    out[i * 4 + 3] = _clampByte(resized[3][i] * 255);
  }
  return Rgba8Image(width: dstWidth, height: dstHeight, pixels: out);
}

/// Resamples a `srcWidth x srcHeight` plane to `dstWidth x dstHeight` by
/// filtering rows then columns with [_kaiserResize1d] — separable, since a
/// 2D Kaiser-windowed sinc is the product of two 1D ones along each axis,
/// the same property a Gaussian blur's separability rests on.
List<double> _resizeSeparable(
  List<double> plane,
  int srcWidth,
  int srcHeight,
  int dstWidth,
  int dstHeight,
) {
  final rowsResized = List<double>.filled(dstWidth * srcHeight, 0);
  for (var y = 0; y < srcHeight; y++) {
    final row = List<double>.generate(srcWidth, (x) => plane[y * srcWidth + x]);
    final resizedRow = _kaiserResize1d(row, dstWidth);
    for (var x = 0; x < dstWidth; x++) {
      rowsResized[y * dstWidth + x] = resizedRow[x];
    }
  }

  final out = List<double>.filled(dstWidth * dstHeight, 0);
  for (var x = 0; x < dstWidth; x++) {
    final column = List<double>.generate(
      srcHeight,
      (y) => rowsResized[y * dstWidth + x],
    );
    final resizedColumn = _kaiserResize1d(column, dstHeight);
    for (var y = 0; y < dstHeight; y++) {
      out[y * dstWidth + x] = resizedColumn[y];
    }
  }
  return out;
}

/// A 3-lobe (support radius 3), Kaiser-windowed (`beta = 4`) sinc resample
/// of [src] to [dstLen] samples, clamped to the edge sample past either end.
///
/// **`beta = 4` is a middle ground, not a tuned constant.** A higher beta
/// narrows the window's own passband ripple at the cost of a softer image; a
/// lower one sharpens at the cost of more ringing on a hard edge (a
/// checkerboard UV seam, an alpha cutout's border). Four is the value the
/// reference implementations this format's own literature cites — Valve's
/// and NVIDIA's texture-tool documentation for a general-purpose mip
/// filter — settle on for the same trade-off, rather than one picked to
/// pass this package's own tests.
List<double> _kaiserResize1d(List<double> src, int dstLen) {
  const support = 3.0;
  const beta = 4.0;
  final scale = src.length / dstLen;
  // Never sharper than the source's own sampling rate: a downsample widens
  // the filter by the same ratio it shrinks the image, which is what keeps
  // the result band-limited rather than aliased.
  final filterScale = math.max(1.0, scale);
  final radius = support * filterScale;

  final out = List<double>.filled(dstLen, 0);
  for (var i = 0; i < dstLen; i++) {
    // The centre of output sample i in source-space coordinates, at the
    // sample's own midpoint rather than its left edge.
    final center = (i + 0.5) * scale - 0.5;
    final lo = (center - radius).ceil();
    final hi = (center + radius).floor();

    var sum = 0.0;
    var weightSum = 0.0;
    for (var s = lo; s <= hi; s++) {
      final x = (s - center) / filterScale;
      final weight = _sinc(x) * _kaiserWindow(x / support, beta);
      if (weight == 0) continue;
      final sample = src[s.clamp(0, src.length - 1)];
      sum += sample * weight;
      weightSum += weight;
    }
    out[i] = weightSum > 0
        ? sum / weightSum
        : src[center.round().clamp(0, src.length - 1)];
  }
  return out;
}

double _sinc(double x) {
  if (x.abs() < 1e-9) return 1.0;
  final piX = math.pi * x;
  return math.sin(piX) / piX;
}

/// The Kaiser window, `|t| <= 1` outside which it is zero — `I0` is the
/// zeroth-order modified Bessel function of the first kind, approximated by
/// its own series (`_besselI0`), the standard way to compute it with no
/// special-function library.
double _kaiserWindow(double t, double beta) {
  if (t.abs() > 1) return 0;
  return _besselI0(beta * math.sqrt(1 - t * t)) / _besselI0(beta);
}

/// `I0(x)`, by the series `sum_k (x/2)^(2k) / (k!)^2` — accurate to double
/// precision for the `x` range a Kaiser window with `beta <= 8` or so ever
/// evaluates it at, which is every call this file makes.
double _besselI0(double x) {
  var sum = 1.0;
  var term = 1.0;
  final halfXSquared = (x / 2) * (x / 2);
  for (var k = 1; k <= 24; k++) {
    term *= halfXSquared / (k * k);
    sum += term;
    if (term < sum * 1e-16) break;
  }
  return sum;
}

/// The fraction of [image]'s texels whose alpha is above [threshold] —
/// what an alpha-test shader actually draws, and the number
/// [_preserveCoverage] holds constant across the chain.
double _coverage(Rgba8Image image, double threshold) {
  final cutoff = (threshold * 255).round();
  var count = 0;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (image.alpha(x, y) > cutoff) count++;
    }
  }
  return count / (image.width * image.height);
}

/// Rescales [level]'s alpha around [threshold] so its own coverage matches
/// [targetCoverage] — Castano's coverage-preserving mipmap technique: alpha
/// is remapped by `clamp((alpha - cutoff) * scale + cutoff)`, pivoted on the
/// alpha-test reference itself rather than a fixed midpoint (a threshold of
/// 0.3 that pivoted on 0.5 would move coverage in the wrong direction for
/// every texel already below 0.5), and [scale] is found by binary search,
/// since coverage is monotonic in it but has no closed form worth deriving
/// for a value only ever wanted to a fraction of a percent.
///
/// **A real limit, not only this port's.** Pivoting on one point can only
/// spread or compress texels around it — it can never move a level whose
/// filtered alpha lands entirely on one side of the threshold to the other,
/// which a target coverage far from 50% eventually does once enough levels
/// have shrunk the feature the alpha describes to a handful of texels. The
/// technique's own literature accepts this the same way: coverage is held as
/// closely as a pivot-and-scale can, not exactly, and the levels small
/// enough to hit the limit are the ones an alpha-tested feature is already a
/// few pixels wide or fewer in.
Rgba8Image _preserveCoverage(
  Rgba8Image level,
  double threshold,
  double targetCoverage,
) {
  final cutoff = threshold * 255;
  double coverageAt(double scale) {
    var count = 0;
    for (var y = 0; y < level.height; y++) {
      for (var x = 0; x < level.width; x++) {
        final a = level.alpha(x, y).toDouble();
        final rescaled = ((a - cutoff) * scale + cutoff).clamp(0, 255);
        if (rescaled > cutoff) count++;
      }
    }
    return count / (level.width * level.height);
  }

  var lo = 0.01, hi = 20.0;
  // Coverage rises with scale (it steepens the ramp around the midpoint,
  // pushing more texels past the threshold on whichever side of it they
  // already are), so twelve bisections narrow the bracket to about 1/4096th
  // of its span — plenty for a value that only has to hold coverage within
  // a fraction of a texel's worth of pixels.
  for (var i = 0; i < 12; i++) {
    final mid = (lo + hi) / 2;
    if (coverageAt(mid) < targetCoverage) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  final scale = (lo + hi) / 2;

  final out = Uint8List.fromList(level.pixels);
  for (var y = 0; y < level.height; y++) {
    for (var x = 0; x < level.width; x++) {
      final at = (y * level.width + x) * 4 + 3;
      final a = out[at].toDouble();
      out[at] = _clampByte((a - cutoff) * scale + cutoff);
    }
  }
  return Rgba8Image(width: level.width, height: level.height, pixels: out);
}
