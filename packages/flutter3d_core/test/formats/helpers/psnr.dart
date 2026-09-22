/// PSNR between two [Rgba8Image]s of the same size, over the channels named
/// — the metric `ap-07` in `doc/asset-pipeline-plan.md` states its
/// acceptance in, and nothing more elaborate than the textbook formula:
/// `10 * log10(255^2 / MSE)`, infinite (and reported as such rather than
/// dividing by zero) for a pixel-exact match.
library;

import 'dart:math' as math;

import 'package:flutter3d_core/formats.dart';

double psnr(Rgba8Image a, Rgba8Image b, {bool includeAlpha = false}) {
  if (a.width != b.width || a.height != b.height) {
    throw ArgumentError(
      'psnr needs equal dimensions: ${a.width}x${a.height} '
      'vs ${b.width}x${b.height}',
    );
  }
  var sumSquares = 0.0;
  var count = 0;
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      final channels = includeAlpha ? 4 : 3;
      for (var c = 0; c < channels; c++) {
        final av = switch (c) {
          0 => a.red(x, y),
          1 => a.green(x, y),
          2 => a.blue(x, y),
          _ => a.alpha(x, y),
        };
        final bv = switch (c) {
          0 => b.red(x, y),
          1 => b.green(x, y),
          2 => b.blue(x, y),
          _ => b.alpha(x, y),
        };
        final diff = (av - bv).toDouble();
        sumSquares += diff * diff;
        count++;
      }
    }
  }
  if (sumSquares == 0) return double.infinity;
  final mse = sumSquares / count;
  return 10 * (math.log(255 * 255 / mse) / math.ln10);
}
