// Exponential variance shadow maps — `S2`.
//
// Shared by the pass that turns the directional depth atlas into moments
// (`evsm_filter.frag`) and by `ShadowFactor`, which reads them back: the two
// halves must warp depth with the same two exponents, or every comparison is
// between numbers on different scales.
//
// A header of its own rather than a section of `shadow.glsl`, because that
// one declares the lit stages' shadow sampler and the filter pass has no
// business declaring it.

#ifndef EVSM_GLSL_
#define EVSM_GLSL_

precision highp float;

// The two exponents depth is warped by. **Forty and five, and the ceiling is
// the format.** The moments are stored squared, so the positive side reaches
// e^80 at the far plane, about 5.5e34 — inside a 32-bit float with three
// orders of magnitude to spare, and far outside a half float, which is why
// the moments live in an rgba32f atlas and the depth atlas does not. The
// negative side only has to catch what the positive side lets through at a
// receiver just behind a caster, and five is the usual answer.
const float kEvsmPositive = 40.0;
const float kEvsmNegative = 5.0;

/// [depth], in [0, 1], warped onto both exponentials: x positive, y negative.
///
/// Depth is first spread to [-1, 1] so the two sides share the range evenly
/// rather than the negative one flattening to nothing at the far end.
vec2 EvsmWarp(float depth) {
  float d = 2.0 * clamp(depth, 0.0, 1.0) - 1.0;
  return vec2(exp(kEvsmPositive * d), -exp(-kEvsmNegative * d));
}

/// What one texel of the depth atlas stores in the moments atlas: each warp
/// and its square, which a blur then averages into a mean and a variance.
vec4 EvsmMoments(float depth) {
  vec2 warped = EvsmWarp(depth);
  return vec4(warped.x, warped.x * warped.x, warped.y, warped.y * warped.y);
}

/// Chebyshev's upper bound on the share of [moments]'s distribution at or
/// beyond [t], with the light-bleeding cut [bleed] taken off the bottom.
///
/// A select at the end rather than an early return of one, because a phi of
/// constants is what SPIRV-Cross refuses when it writes the WGSL.
float EvsmChebyshev(vec2 moments, float t, float minVariance, float bleed) {
  float variance = max(moments.y - moments.x * moments.x, minVariance);
  float d = t - moments.x;
  float pMax = variance / (variance + d * d);
  // Light bleeding: where two casters overlap, the bound admits light the
  // nearer one should block. Everything under [bleed] is called shadow and
  // the rest stretched back over [0, 1].
  float reduced = clamp((pMax - bleed) / max(1.0 - bleed, 1e-4), 0.0, 1.0);
  return t <= moments.x ? 1.0 : reduced;
}

/// How much light reaches a receiver at [depth] past filtered [moments].
///
/// The smaller of the two bounds: each exponential lets through a different
/// kind of error, and neither lets through what the other stops.
float EvsmVisibility(vec4 moments, float depth, float bleed) {
  vec2 warped = EvsmWarp(depth);
  // A floor on the variance proportional to the warped depth's own slope,
  // so a flat receiver compared against its own texel does not divide
  // nought by nought — the variance of one depth is zero.
  vec2 scale = 0.0001 * vec2(kEvsmPositive, kEvsmNegative) * warped;
  float positive = EvsmChebyshev(moments.xy, warped.x, scale.x * scale.x, bleed);
  float negative = EvsmChebyshev(moments.zw, warped.y, scale.y * scale.y, bleed);
  return min(positive, negative);
}

#endif  // EVSM_GLSL_
