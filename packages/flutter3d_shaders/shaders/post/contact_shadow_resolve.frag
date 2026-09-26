#version 460 core

// The contact shadow's resolve when no temporal one runs.
//
// **Why the march needs one.** `contact_shadow.frag` offsets each pixel's
// march by the 4 x 4 Bayer cell while the temporal resolve is off, and each
// pixel returns the first thing its own march hit. Neighbouring pixels start
// their march at different fractions of a step, so along an edge the answer
// alternates with the pattern: a thin blocker held just off the floor draws
// its shadow as a comb. With the temporal resolve on, the history averages a
// new slice of blue noise every frame and the comb never shows; off, the
// pattern is the same every frame and stays in the picture.
//
// **A 4 x 4 window, one tap of each phase.** Offsets -2..+1 on both axes cover
// every cell of the Bayer matrix exactly once, wherever the window sits, so
// the average is what sixteen marches from the same pixel at the sixteen
// offsets would give — with the neighbours' positions standing in for this
// one's, which is a pixel or two of blur on a shadow whose edge is the thing
// being smoothed.
//
// **Depth-aware, for `ssao_blur.frag`'s reason.** A plain box pulls the dark
// under an object out past its silhouette and onto whatever is in front. Each
// tap is weighted by how close its depth is to the centre's, relative to the
// centre's own depth, so a tap on another surface contributes almost nothing;
// sky taps, which have no depth, contribute nothing at all.

in vec2 v_uv;

out vec4 frag_color;

uniform sampler2D contact_shadow_texture;
uniform sampler2D surface_texture;

uniform ContactShadowResolveInfo {
  // x, y: one texel of the contact shadow buffer. z: how much difference in
  // depth, as a fraction of the centre's depth, drops a tap's weight to 1/e.
  // w unused.
  vec4 params;
}
resolve_info;

void main() {
  vec4 centre = texture(contact_shadow_texture, v_uv);
  float centreDepth = texture(surface_texture, v_uv).a;
  // The sky: the march wrote one here and there is no depth to weigh by.
  if (centreDepth <= 0.0) {
    frag_color = centre;
    return;
  }

  float falloff = max(resolve_info.params.z, 1e-4) * max(centreDepth, 1e-3);

  vec4 total = vec4(0.0);
  float weightSum = 0.0;
  for (int y = -2; y <= 1; y++) {
    for (int x = -2; x <= 1; x++) {
      vec2 at = v_uv + vec2(float(x), float(y)) * resolve_info.params.xy;
      // `textureLod` at level zero, as `contact_shadow.frag`'s own march:
      // after the early return and the `continue` this is non-uniform control
      // flow, where WGSL refuses an implicit-derivative sample.
      float depth = textureLod(surface_texture, at, 0.0).a;
      if (depth <= 0.0) continue;
      float weight = exp(-abs(depth - centreDepth) / falloff);
      total += textureLod(contact_shadow_texture, at, 0.0) * weight;
      weightSum += weight;
    }
  }

  // The centre is always one of the taps and always weighs one, so the sum is
  // never below that.
  frag_color = total / max(weightSum, 1e-4);
}
