#version 460 core

// Weighted blended transparency's resolve — `R8`.
//
// The transparent draws went into two targets instead of the picture: the
// accumulation target holds the sum of every layer's premultiplied colour and
// alpha, each times its weight, and the revealage target the product of one
// minus every layer's alpha — how much of what is behind still shows. This
// turns the pair into one layer over the lit scene: the weighted average
// colour, covering as much of the pixel as the layers together do. Drawn with
// the engine's premultiplied source-over, so a pixel no layer touched —
// revealage one — writes nothing and leaves the scene exactly as it was.
//
// Addition and multiplication do not care about order, which is the point:
// the transparent list needs no sort, and two intersecting panes composite
// the same whichever was drawn first.
precision highp float;

in vec2 v_uv;

out vec4 frag_color;

uniform sampler2D accumulation_texture;
uniform sampler2D revealage_texture;

void main() {
  vec4 accumulation = texture(accumulation_texture, v_uv);
  float coverage = 1.0 - texture(revealage_texture, v_uv).r;
  // Sums past half float's range come back infinite; clamped, their ratio is
  // still a colour rather than a NaN.
  vec3 average = min(accumulation.rgb, vec3(65504.0)) /
                 clamp(accumulation.a, 1e-5, 65504.0);
  frag_color = vec4(average * coverage, coverage);
}
