#version 460 core

// The directional atlas as exponential variance moments, blurred — `S2`.
//
// Drawn twice over the whole atlas: first across, reading the depth atlas
// and warping each tap into moments before it is averaged, then down,
// reading what the first pass wrote. A separable Gaussian, so a radius of r
// texels costs 2r + 1 taps a pass rather than (2r + 1)² in one.
//
// **After the static and dynamic casters are combined, not instead of
// them.** `S1` puts the two halves together by drawing dynamic casters over
// a copy of the static tile, which works because depth combines by keeping
// the nearer. Moments do not combine that way — the average of two
// distributions is not the nearer of them — so the depth atlas stays as it
// is and this pass is the step after it.
//
// **Every tap stays inside its own cascade's tile**, clamped half a texel in
// from the edge: the cascades sit side by side, and a blur that crossed a
// seam would average in depths measured through another projection.

in vec2 v_uv;

out vec4 frag_color;

#include <lib/evsm.glsl>

uniform sampler2D evsm_source;

uniform EvsmFilterInfo {
  /// xy: one texel of the atlas along the axis this pass blurs, nought on
  /// the other. z: taps to each side, nought to eight. w: 1 when the source
  /// is the depth atlas and each tap is warped first, 0 when it already
  /// holds moments.
  vec4 axis;

  /// x: how many cascades share the atlas across. y, z: half a texel of the
  /// atlas, across and down, which is how far in from a tile's edge a tap is
  /// held.
  vec4 tile;
}
evsm_info;

void main() {
  float count = max(evsm_info.tile.x, 1.0);
  float which = min(floor(v_uv.x * count), count - 1.0);
  vec2 lo = vec2(which / count + evsm_info.tile.y, evsm_info.tile.z);
  vec2 hi = vec2((which + 1.0) / count - evsm_info.tile.y,
                 1.0 - evsm_info.tile.z);

  float taps = clamp(evsm_info.axis.z, 0.0, 8.0);
  // A Gaussian whose tail is two deviations out at the last tap, which is
  // where its weight has fallen to an eighth and a tap still earns its read.
  float sigma = max(taps * 0.5, 0.5);
  bool warp = evsm_info.axis.w > 0.5;

  vec4 total = vec4(0.0);
  float weightSum = 0.0;
  // Bounded at eight to each side whatever the uniform says, the rule every
  // blur here keeps: a loop a uniform can lengthen is a hang, not a slow frame.
  for (int i = -8; i <= 8; i++) {
    float offset = float(i);
    if (abs(offset) > taps) continue;
    vec2 at = clamp(v_uv + evsm_info.axis.xy * offset, lo, hi);
    vec4 texel = textureLod(evsm_source, at, 0.0);
    vec4 value = warp ? EvsmMoments(texel.r) : texel;
    float weight = exp(-(offset * offset) / (2.0 * sigma * sigma));
    total += value * weight;
    weightSum += weight;
  }
  frag_color = total / weightSum;
}
