#version 460 core

// Particles, as a procedural round sprite.
//
// No texture, and that is a decision rather than a placeholder. A sampler here
// would be one more slot to bind correctly, and this engine's most expensive
// recurring bug is binding a texture a compiled shader has no room for — the
// crash is native and carries no Dart stack. A smooth falloff computed from the
// quad's own coordinates costs a length and a smoothstep, needs no asset, and
// scales to any resolution without a mip chain, which this channel cannot
// produce anyway.
//
// The alpha is folded into the colour instead of being blended with it. These
// are drawn additively, where the destination is only ever added to: a spark
// brightens what is behind it and a faded spark adds nothing. That is also why
// they need no sorting — addition does not care about order, which is the whole
// reason additive is the right mode for fire and sparks and the wrong one for
// smoke.

in vec4 v_color;
in vec2 v_uv;

out vec4 frag_color;

void main() {
  // Distance from the middle of the quad, where the corners sit at 1.
  vec2 centred = v_uv * 2.0 - 1.0;
  float radius = length(centred);

  // Soft edge, and a brighter core: a flat disc reads as a paper cut-out, and
  // the falloff is what makes a cluster of these look like light rather than
  // like confetti.
  float falloff = 1.0 - smoothstep(0.0, 1.0, radius);
  float intensity = falloff * falloff;

  frag_color = vec4(v_color.rgb * v_color.a * intensity, 1.0);
}
