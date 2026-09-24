#version 460 core

// A depth-aware blur over the occlusion buffer — `gfx-32n`.
//
// **Why the occlusion needs one and the composite cannot give it.** The
// composite already averages a 2x2, and that is not a blur: the occlusion
// pass rotates its kernel by the parity of the pixel and the 2x2 averages
// exactly that pattern away. Widening it would smear the contact shadows the
// pass exists to draw, and the two are sized to each other on purpose. So the
// quality has to come from somewhere else, and that somewhere is a pass of
// its own over the occlusion buffer, before the composite reads it.
//
// **Depth-aware, because occlusion is the one signal a blur must not spread
// across a silhouette.** A plain blur pulls the dark of a corner out past the
// object that made it, which reads as a halo around every shape — the
// artefact that makes people switch ambient occlusion off. Each tap is
// weighted by how close its depth is to the centre's, so a tap on the other
// side of an edge contributes nothing.
//
// Depth comes from the surface buffer's alpha, which carries view-axis
// distance in metres — the same channel `ssao.frag` reconstructs positions
// from, and the reason this pass needs no depth attachment of its own.

in vec2 v_uv;

out vec4 frag_color;

uniform sampler2D ao_texture;
uniform sampler2D surface_texture;

uniform SsaoBlurInfo {
  // x, y: one texel of the occlusion buffer. z: how many taps to each side,
  // 0 for none. w: how much difference in depth, in metres, halves a tap's
  // weight.
  vec4 params;
}
blur_info;

void main() {
  float taps = blur_info.params.z;
  float centre = texture(ao_texture, v_uv).r;
  if (taps < 1.0) {
    frag_color = vec4(centre, centre, centre, 1.0);
    return;
  }

  float centreDepth = texture(surface_texture, v_uv).a;
  float falloff = max(blur_info.params.w, 1e-4);

  float total = centre;
  float weightSum = 1.0;
  // Bounded at eight to each side whatever the uniform says, the same rule
  // `ssao.frag`'s own sample loop keeps: a loop a uniform can lengthen
  // without limit is a hang rather than a slow frame.
  for (int i = 1; i <= 8; i++) {
    if (float(i) > taps) break;
    float offset = float(i);
    vec2 steps[4];
    steps[0] = vec2(blur_info.params.x * offset, 0.0);
    steps[1] = vec2(-blur_info.params.x * offset, 0.0);
    steps[2] = vec2(0.0, blur_info.params.y * offset);
    steps[3] = vec2(0.0, -blur_info.params.y * offset);

    for (int s = 0; s < 4; s++) {
      vec2 at = v_uv + steps[s];
      float depth = texture(surface_texture, at).a;
      // A tap across a silhouette is a tap from another surface, and the
      // whole reason this is depth-aware is that it must not count. The
      // weight falls off with the difference rather than cutting at a
      // threshold, so a curved surface does not band where the cut would be.
      // Relative to the centre's own depth, as XeGTAO's denoiser: a
      // difference that is a silhouette a metre away is one pixel's worth of
      // a floor at twenty.
      float closeness =
          exp(-abs(depth - centreDepth) / (falloff * max(centreDepth, 1e-3)));
      // And further taps count for less, which is what makes this a blur
      // rather than a box.
      float weight = closeness / offset;
      total += texture(ao_texture, at).r * weight;
      weightSum += weight;
    }
  }

  float blurred = total / weightSum;
  frag_color = vec4(blurred, blurred, blurred, 1.0);
}
