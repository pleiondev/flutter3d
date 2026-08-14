#version 460 core

// Particles with a texture, beside the procedural one rather than replacing it.
//
// `lighting/particle.frag` computes a round falloff from the quad's own
// coordinates and has no sampler at all. Its comment says why, and the reason
// has not expired: "this engine's most expensive recurring bug is binding a
// texture a compiled shader has no room for — the crash is native and carries
// no Dart stack". A stage with a sampler and a stage without are two stages,
// and a contributor picks between them by whether it was given a texture.
//
// What the procedural one cannot do is be a *shape*: smoke needs an edge that
// is not a circle, a flipbook needs frames, and an ember needs to look like
// something burnt rather than like a dot. That is what this is for.
//
// The same vertex stage feeds both — `particle.vert` already carries `v_uv`
// across, which the procedural stage uses for its radius and this one uses as a
// texture coordinate.

in vec4 v_color;
in vec2 v_uv;
in vec3 v_world_position;

out vec4 frag_color;

uniform sampler2D particle_texture;

/// Declared again for the same reason the other particle stages declare it:
/// this shader shares none of the lit path's headers.
uniform FogInfo {
  /// rgb: linear fog colour. w: density per metre, zero for no fog.
  vec4 fog;

  /// xyz: camera position in world space.
  vec4 eye;
}
fog_info;

void main() {
  // `texture`, not `textureLod`. The level is chosen from the derivative the
  // hardware computes for this fragment, which is the whole point of building
  // the chain — and it is the one place the software backend cannot follow
  // exactly, since it has no neighbouring fragments to difference. See
  // `BoundTexture.sample`.
  vec4 texel = texture(particle_texture, v_uv);

  // Attenuation rather than a mix. Blending an additive particle toward the
  // fog colour makes a distant one *add* fog to the wall behind it — the same
  // note as the other two particle stages, kept because each is read alone.
  float fogged = 1.0;
  if (fog_info.fog.w > 0.0) {
    fogged = clamp(
        exp(-fog_info.fog.w * distance(v_world_position, fog_info.eye.xyz)),
        0.0,
        1.0);
  }

  // The texture's alpha is coverage and the particle's is brightness, so the
  // two multiply rather than one replacing the other: a faded spark of a
  // half-transparent sprite contributes a quarter, which is what additive
  // blending means by both of those at once.
  float scale = v_color.a * texel.a * fogged;
  frag_color = vec4(v_color.rgb * texel.rgb * scale, 1.0);
}
