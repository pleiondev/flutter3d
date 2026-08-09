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
in vec3 v_world_position;

out vec4 frag_color;

/// The same block the lit shaders use, declared again because this shader
/// shares none of their headers — it has a different vertex layout and none of
/// their varyings.
uniform FogInfo {
  /// rgb: linear fog colour. w: density per metre, zero for no fog.
  vec4 fog;

  /// xyz: camera position in world space.
  vec4 eye;
}
fog_info;

void main() {
  // Distance from the middle of the quad, where the corners sit at 1.
  vec2 centred = v_uv * 2.0 - 1.0;
  float radius = length(centred);

  // Soft edge, and a brighter core: a flat disc reads as a paper cut-out, and
  // the falloff is what makes a cluster of these look like light rather than
  // like confetti.
  float falloff = 1.0 - smoothstep(0.0, 1.0, radius);
  float intensity = falloff * falloff;

  // Fog on an additive particle is attenuation, not a mix. Blending toward
  // the fog colour would make a distant flame *add* fog to the wall behind it
  // and come out brighter than the wall it is supposed to be fading into;
  // multiplying toward zero is what "further away contributes less" means when
  // the destination is only ever added to.
  float fogged = 1.0;
  if (fog_info.fog.w > 0.0) {
    fogged = clamp(
        exp(-fog_info.fog.w * distance(v_world_position, fog_info.eye.xyz)),
        0.0,
        1.0);
  }

  frag_color = vec4(v_color.rgb * v_color.a * intensity * fogged, 1.0);
}
