/// LDR-FLIP, the perceptual difference between two pictures — `N2`.
///
/// **A number that means what a person sees.** The golden checks count pixels
/// that moved by more than a few steps, which is right for "did the renderer
/// change" and wrong for "how much worse does this look": a frame drawn at 70%
/// resolution moves nearly every pixel by a step or two and looks almost the
/// same, and a missing shadow moves a few hundred and looks broken. FLIP
/// answers the second question, which is the one the adaptive quality table
/// needs — it ranks settings by what they cost the picture.
///
/// FLIP (Andersson, Nilsson, Akenine-Möller, Oskarsson, Åström and Fairchild,
/// "FLIP: A Difference Evaluator for Alternating Images", HPG 2020): both
/// pictures are filtered by the contrast sensitivity of the eye at a viewing
/// distance given in pixels per degree, compared in a perceptually uniform
/// colour space with the Hunt effect, and the colour difference is raised by
/// how much the edges and points differ. Nought is identical; one is as
/// different as green is from blue.
///
/// Ported line for line from the reference C++ (`FLIP.h`, the CPU path of
/// `LDR_FLIP`) so a value here is the value there; the test holds it to the
/// error maps that implementation publishes.
///
/// Copyright (c) 2020-2025, NVIDIA CORPORATION & AFFILIATES. All rights
/// reserved. Redistributed under the BSD 3-Clause conditions in
/// `third_party/flip/LICENSE`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// The reference implementation's default viewing condition: a 0.7 m wide
/// 3840-pixel monitor seen from 0.7 m, about 67 pixels per degree.
final double defaultFlipPpd = 0.7 * (3840.0 / 0.7) * (math.pi / 180.0);

/// A per-pixel FLIP error map and its mean.
final class FlipResult {
  FlipResult(this.errors, this.width, this.height);

  /// One error per pixel, row-major from the top, each in [0, 1].
  final Float64List errors;
  final int width;
  final int height;

  /// The mean error — the one number the reference tool prints.
  late final double mean =
      errors.fold(0.0, (double sum, double e) => sum + e) / errors.length;
}

/// FLIP between two 8-bit sRGB pictures of [width] × [height], [channels]
/// bytes a pixel (3 or 4; a fourth is ignored).
///
/// sRGB because that is what a frame read back from a device and a PNG on
/// disk both are; [flipLinear] takes linear light for a caller that has it.
FlipResult flip(
  Uint8List reference,
  Uint8List test, {
  required int width,
  required int height,
  int channels = 4,
  double? ppd,
}) {
  final count = width * height;
  if (reference.length < count * channels || test.length < count * channels) {
    throw ArgumentError(
      'a $width×$height picture of $channels channels needs '
      '${count * channels} bytes',
    );
  }
  // A table rather than a pow per channel: there are 256 inputs.
  final toLinear = Float64List.fromList(
    List<double>.generate(256, (int i) => _srgbToLinear(i / 255.0)),
  );
  Float64List linear(Uint8List bytes) {
    final out = Float64List(count * 3);
    for (var i = 0; i < count; i++) {
      out[i * 3] = toLinear[bytes[i * channels]];
      out[i * 3 + 1] = toLinear[bytes[i * channels + 1]];
      out[i * 3 + 2] = toLinear[bytes[i * channels + 2]];
    }
    return out;
  }

  return flipLinear(
    linear(reference),
    linear(test),
    width: width,
    height: height,
    ppd: ppd,
  );
}

/// FLIP between two pictures in linear RGB, three values a pixel, each in
/// [0, 1] — the input the reference `LDR_FLIP` takes.
FlipResult flipLinear(
  Float64List reference,
  Float64List test, {
  required int width,
  required int height,
  double? ppd,
}) {
  final viewing = ppd ?? defaultFlipPpd;
  final count = width * height;
  final ref = _toYCxCz(reference, count);
  final tst = _toYCxCz(test, count);

  final errors = _colorDifference(ref, tst, width, height, viewing);
  _featureDifferenceAndFinalError(errors, ref, tst, width, height, viewing);
  return FlipResult(errors, width, height);
}

// The constants of the paper: the colour difference's exponent, the point
// and threshold of its remapping, the feature filter's width in degrees and
// the feature difference's exponent.
const double _gqc = 0.7;
const double _gpc = 0.4;
const double _gpt = 0.95;
const double _gw = 0.082;
const double _gqf = 0.5;

// The spatial filters' Gaussians: a1/b1 for luminance, red–green and the
// first blue–yellow lobe, a2/b2 for the second blue–yellow lobe.
const List<double> _a1 = <double>[1.0, 1.0, 34.1];
const List<double> _b1 = <double>[0.0047, 0.0053, 0.04];
const List<double> _a2 = <double>[0.0, 0.0, 13.5];
const List<double> _b2 = <double>[1.0e-5, 1.0e-5, 0.025];

// D65.
const List<double> _illuminant = <double>[0.950428545, 1.0, 1.088900371];
const List<double> _invIlluminant = <double>[1.052156925, 1.0, 0.918357670];

double _srgbToLinear(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

(double, double, double) _linearToXyz(double r, double g, double b) => (
  10135552.0 / 24577794.0 * r +
      8788810.0 / 24577794.0 * g +
      4435075.0 / 24577794.0 * b,
  2613072.0 / 12288897.0 * r +
      8788810.0 / 12288897.0 * g +
      887015.0 / 12288897.0 * b,
  1425312.0 / 73733382.0 * r +
      8788810.0 / 73733382.0 * g +
      70074185.0 / 73733382.0 * b,
);

(double, double, double) _xyzToLinear(double x, double y, double z) => (
  3.241003275 * x - 1.537398934 * y - 0.498615861 * z,
  -0.969224334 * x + 1.875930071 * y + 0.041554224 * z,
  0.055639423 * x - 0.204011202 * y + 1.057148933 * z,
);

(double, double, double) _xyzToLab(double x, double y, double z) {
  const delta = 6.0 / 29.0;
  const deltaCube = delta * delta * delta;
  const factor = 1.0 / (3.0 * delta * delta);
  const term = 4.0 / 29.0;
  double f(double v) =>
      v > deltaCube ? math.pow(v, 1.0 / 3.0).toDouble() : factor * v + term;
  final fx = f(x * _invIlluminant[0]);
  final fy = f(y * _invIlluminant[1]);
  final fz = f(z * _invIlluminant[2]);
  return (116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz));
}

double _hunt(double luminance, double chrominance) =>
    0.01 * luminance * chrominance;

double _hyab((double, double, double) a, (double, double, double) b) {
  final dy = a.$2 - b.$2;
  final dz = a.$3 - b.$3;
  return (a.$1 - b.$1).abs() + math.sqrt(dy * dy + dz * dz);
}

(double, double, double) _huntLab((double, double, double) lab) =>
    (lab.$1, _hunt(lab.$1, lab.$2), _hunt(lab.$1, lab.$3));

/// The largest colour difference there is, green against blue.
double _maxDistance() {
  final green = _huntLab(_labOf(0.0, 1.0, 0.0));
  final blue = _huntLab(_labOf(0.0, 0.0, 1.0));
  return math.pow(_hyab(green, blue), _gqc).toDouble();
}

(double, double, double) _labOf(double r, double g, double b) {
  final (x, y, z) = _linearToXyz(r, g, b);
  return _xyzToLab(x, y, z);
}

/// Linear RGB to YCxCz, as three planes.
List<Float64List> _toYCxCz(Float64List rgb, int count) {
  final y = Float64List(count);
  final cx = Float64List(count);
  final cz = Float64List(count);
  for (var i = 0; i < count; i++) {
    final (x, yy, z) = _linearToXyz(rgb[i * 3], rgb[i * 3 + 1], rgb[i * 3 + 2]);
    final nx = x * _invIlluminant[0];
    final ny = yy * _invIlluminant[1];
    final nz = z * _invIlluminant[2];
    y[i] = 116.0 * ny - 16.0;
    cx[i] = 500.0 * (nx - ny);
    cz[i] = 200.0 * (ny - nz);
  }
  return <Float64List>[y, cx, cz];
}

double _gaussian(double x2, double a, double b) =>
    a * math.sqrt(math.pi / b) * math.exp(-math.pi * math.pi * x2 / b);

double _gaussianSqrt(double x2, double a, double b) =>
    math.sqrt(a * math.sqrt(math.pi / b)) *
    math.exp(-math.pi * math.pi * x2 / b);

int _clampIndex(int i, int n) => i < 0 ? 0 : (i >= n ? n - 1 : i);

/// The spatially filtered colour difference, remapped to [0, 1].
///
/// The blue–yellow filter is a sum of two Gaussians, which is not separable;
/// it is run as two separable ones whose squared results add up to it, the
/// construction of `separatedConvolutions.pdf` in the reference repository.
Float64List _colorDifference(
  List<Float64List> ref,
  List<Float64List> tst,
  int w,
  int h,
  double ppd,
) {
  final maxScale = <double>[..._b1, ..._b2].reduce(math.max);
  final radius = (3.0 * math.sqrt(maxScale / (2.0 * math.pi * math.pi)) * ppd)
      .ceil();
  final width = 2 * radius + 1;

  final fY = Float64List(width);
  final fCx = Float64List(width);
  final fCz1 = Float64List(width);
  final fCz2 = Float64List(width);
  for (var x = 0; x < width; x++) {
    final ix = (x - radius) / ppd;
    final ix2 = ix * ix;
    fY[x] = _gaussian(ix2, _a1[0], _b1[0]);
    fCx[x] = _gaussian(ix2, _a1[1], _b1[1]);
    fCz1[x] = _gaussianSqrt(ix2, _a1[2], _b1[2]);
    fCz2[x] = _gaussianSqrt(ix2, _a2[2], _b2[2]);
  }
  final sumY = fY.fold(0.0, (double s, double v) => s + v);
  final sumCx = fCx.fold(0.0, (double s, double v) => s + v);
  final sumCz1 = fCz1.fold(0.0, (double s, double v) => s + v);
  final sumCz2 = fCz2.fold(0.0, (double s, double v) => s + v);
  final normCz = 1.0 / math.sqrt(sumCz1 * sumCz1 + sumCz2 * sumCz2);
  for (var x = 0; x < width; x++) {
    fY[x] /= sumY;
    fCx[x] /= sumCx;
    fCz1[x] *= normCz;
    fCz2[x] *= normCz;
  }

  final count = w * h;
  // Per image: Y, Cx, and the two blue–yellow lobes, filtered along x.
  List<Float64List> alongX(List<Float64List> image) {
    final y = Float64List(count);
    final cx = Float64List(count);
    final cz1 = Float64List(count);
    final cz2 = Float64List(count);
    for (var row = 0; row < h; row++) {
      for (var x = 0; x < w; x++) {
        var sy = 0.0, scx = 0.0, scz1 = 0.0, scz2 = 0.0;
        for (var i = -radius; i <= radius; i++) {
          final at = row * w + _clampIndex(x + i, w);
          final k = i + radius;
          sy += fY[k] * image[0][at];
          scx += fCx[k] * image[1][at];
          scz1 += fCz1[k] * image[2][at];
          scz2 += fCz2[k] * image[2][at];
        }
        final at = row * w + x;
        y[at] = sy;
        cx[at] = scx;
        cz1[at] = scz1;
        cz2[at] = scz2;
      }
    }
    return <Float64List>[y, cx, cz1, cz2];
  }

  final refX = alongX(ref);
  final tstX = alongX(tst);

  final cmax = _maxDistance();
  final pccmax = _gpc * cmax;
  final out = Float64List(count);

  (double, double, double) filteredLab(List<Float64List> image, int x, int y) {
    var sy = 0.0, scx = 0.0, scz1 = 0.0, scz2 = 0.0;
    for (var i = -radius; i <= radius; i++) {
      final at = _clampIndex(y + i, h) * w + x;
      final k = i + radius;
      sy += fY[k] * image[0][at];
      scx += fCx[k] * image[1][at];
      scz1 += fCz1[k] * image[2][at];
      scz2 += fCz2[k] * image[3][at];
    }
    // YCxCz back to linear RGB, clamped to the displayable range, then Lab.
    final yy = (sy + 16.0) / 116.0;
    final xx = yy + scx / 500.0;
    final zz = yy - (scz1 + scz2) / 200.0;
    final (r, g, b) = _xyzToLinear(
      xx * _illuminant[0],
      yy * _illuminant[1],
      zz * _illuminant[2],
    );
    return _huntLab(
      _labOf(r.clamp(0.0, 1.0), g.clamp(0.0, 1.0), b.clamp(0.0, 1.0)),
    );
  }

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final difference = math
          .pow(_hyab(filteredLab(refX, x, y), filteredLab(tstX, x, y)), _gqc)
          .toDouble();
      // Up to pccmax maps onto [0, gpt]; the rest onto (gpt, 1].
      out[y * w + x] = difference < pccmax
          ? difference * _gpt / pccmax
          : _gpt + (difference - pccmax) / (cmax - pccmax) * (1.0 - _gpt);
    }
  }
  return out;
}

/// Raises each colour difference in [errors] by how much the edges and
/// points under it differ, which is FLIP's final error.
void _featureDifferenceAndFinalError(
  Float64List errors,
  List<Float64List> ref,
  List<Float64List> tst,
  int w,
  int h,
  double ppd,
) {
  final stdDev = 0.5 * _gw * ppd;
  final radius = (3.0 * stdDev).ceil();
  final width = 2 * radius + 1;
  final g = Float64List(width);
  final dg = Float64List(width);
  final ddg = Float64List(width);
  var gSum = 0.0;
  var dgNegative = 0.0, dgPositive = 0.0;
  var ddgNegative = 0.0, ddgPositive = 0.0;
  for (var x = 0; x < width; x++) {
    final xx = (x - radius).toDouble();
    final gaussian = math.exp(-(xx * xx) / (2.0 * stdDev * stdDev));
    g[x] = gaussian;
    gSum += gaussian;
    dg[x] = -xx * gaussian;
    if (dg[x] > 0.0) {
      dgPositive += dg[x];
    } else {
      dgNegative -= dg[x];
    }
    ddg[x] = (xx * xx / (stdDev * stdDev) - 1.0) * gaussian;
    if (ddg[x] > 0.0) {
      ddgPositive += ddg[x];
    } else {
      ddgNegative -= ddg[x];
    }
  }
  // The Gaussian sums to one; each derivative's positive and negative lobes
  // to one and minus one.
  for (var x = 0; x < width; x++) {
    g[x] /= gSum;
    dg[x] /= dg[x] > 0.0 ? dgPositive : dgNegative;
    ddg[x] /= ddg[x] > 0.0 ? ddgPositive : ddgNegative;
  }

  final count = w * h;
  // Along x: the first and second x-derivatives, and the plain Gaussian the
  // y-derivatives are taken of, all on luminance normalised to [0, 1].
  List<Float64List> alongX(Float64List luminance) {
    final d = Float64List(count);
    final dd = Float64List(count);
    final smooth = Float64List(count);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var sd = 0.0, sdd = 0.0, sg = 0.0;
        for (var i = -radius; i <= radius; i++) {
          final v =
              luminance[y * w + _clampIndex(x + i, w)] / 116.0 + 16.0 / 116.0;
          final k = i + radius;
          sd += dg[k] * v;
          sdd += ddg[k] * v;
          sg += g[k] * v;
        }
        d[y * w + x] = sd;
        dd[y * w + x] = sdd;
        smooth[y * w + x] = sg;
      }
    }
    return <Float64List>[d, dd, smooth];
  }

  final refX = alongX(ref[0]);
  final tstX = alongX(tst[0]);
  final normalization = 1.0 / math.sqrt(2.0);

  (double edge, double point) features(List<Float64List> image, int x, int y) {
    var dx = 0.0, ddx = 0.0, dy = 0.0, ddy = 0.0;
    for (var i = -radius; i <= radius; i++) {
      final at = _clampIndex(y + i, h) * w + x;
      final k = i + radius;
      dx += g[k] * image[0][at];
      ddx += g[k] * image[1][at];
      dy += dg[k] * image[2][at];
      ddy += ddg[k] * image[2][at];
    }
    return (math.sqrt(dx * dx + dy * dy), math.sqrt(ddx * ddx + ddy * ddy));
  }

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final (edgeRef, pointRef) = features(refX, x, y);
      final (edgeTest, pointTest) = features(tstX, x, y);
      final feature = math
          .pow(
            normalization *
                math.max(
                  (edgeRef - edgeTest).abs(),
                  (pointRef - pointTest).abs(),
                ),
            _gqf,
          )
          .toDouble();
      final at = y * w + x;
      errors[at] = math.pow(errors[at], 1.0 - feature).toDouble();
    }
  }
}
