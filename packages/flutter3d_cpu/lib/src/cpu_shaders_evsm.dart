/// `evsm.glsl` and `evsm_filter.frag`: exponential variance shadow maps —
/// `S2`.
///
/// The warp and the Chebyshev bound live here once, for the filter pass that
/// writes the moments and for `shadowFactor`, which reads them, as they live
/// in one header on the GPU side.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';

/// `kEvsmPositive` and `kEvsmNegative`.
const double kEvsmPositive = 40.0;
const double kEvsmNegative = 5.0;

/// `EvsmWarp`: [depth] on both exponentials, positive then negative.
(double, double) evsmWarp(double depth) {
  final d = 2.0 * depth.clamp(0.0, 1.0) - 1.0;
  return (math.exp(kEvsmPositive * d), -math.exp(-kEvsmNegative * d));
}

/// `EvsmMoments`: each warp and its square.
Vector4 evsmMoments(double depth) {
  final (positive, negative) = evsmWarp(depth);
  return Vector4(positive, positive * positive, negative, negative * negative);
}

/// `EvsmChebyshev`: the upper bound on light past [mean] and [square] at
/// [t], less the light-bleeding cut [bleed].
double evsmChebyshev(
  double mean,
  double square,
  double t,
  double minVariance,
  double bleed,
) {
  final variance = math.max(square - mean * mean, minVariance);
  final d = t - mean;
  final pMax = variance / (variance + d * d);
  final reduced = ((pMax - bleed) / math.max(1.0 - bleed, 1e-4)).clamp(
    0.0,
    1.0,
  );
  return t <= mean ? 1.0 : reduced;
}

/// `EvsmVisibility`: the smaller of the two bounds.
double evsmVisibility(Vector4 moments, double depth, double bleed) {
  final (positive, negative) = evsmWarp(depth);
  final scalePositive = 0.0001 * kEvsmPositive * positive;
  final scaleNegative = 0.0001 * kEvsmNegative * negative;
  return math.min(
    evsmChebyshev(
      moments.x,
      moments.y,
      positive,
      scalePositive * scalePositive,
      bleed,
    ),
    evsmChebyshev(
      moments.z,
      moments.w,
      negative,
      scaleNegative * scaleNegative,
      bleed,
    ),
  );
}

/// `evsm_filter.frag`: one axis of the separable blur over the directional
/// atlas, warping depth into moments on the first of the two.
final class EvsmFilterShader implements CpuFragmentShader {
  const EvsmFilterShader();

  @override
  Vector4? run(Float32List v, ShaderBindings bindings, FragmentContext c) {
    final source = bindings.textures['evsm_source'];
    if (source == null) return null;
    final axis = bindings.vec4('EvsmFilterInfo', 'axis', Vector4.zero());
    final tile = bindings.vec4('EvsmFilterInfo', 'tile', Vector4.zero());

    // Held inside the cascade's own tile, as the shader.
    final count = math.max(tile.x, 1.0);
    final which = math.min((v[0] * count).floorToDouble(), count - 1.0);
    final loU = which / count + tile.y;
    final hiU = (which + 1.0) / count - tile.y;
    final loV = tile.z;
    final hiV = 1.0 - tile.z;

    final taps = axis.z.clamp(0.0, 8.0);
    final sigma = math.max(taps * 0.5, 0.5);
    final warp = axis.w > 0.5;

    final total = Vector4.zero();
    var weightSum = 0.0;
    for (var i = -8; i <= 8; i++) {
      final offset = i.toDouble();
      if (offset.abs() > taps) continue;
      final texel = source.sample(
        (v[0] + axis.x * offset).clamp(loU, hiU),
        (v[1] + axis.y * offset).clamp(loV, hiV),
      );
      final value = warp ? evsmMoments(texel.x) : texel;
      final weight = math.exp(-(offset * offset) / (2.0 * sigma * sigma));
      total.addScaled(value, weight);
      weightSum += weight;
    }
    return total..scale(1.0 / weightSum);
  }
}
