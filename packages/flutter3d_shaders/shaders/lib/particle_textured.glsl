// Particles with a texture, beside the procedural one rather than replacing it:
// the body of `lighting/particle_textured.frag` and, with `F3D_SOFT_PARTICLE`,
// of `lighting/particle_textured_soft.frag`.
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

#include <lib/particle_soft.glsl>

in vec4 v_color;
in vec2 v_uv;
in vec3 v_world_position;

out vec4 frag_color;

uniform sampler2D particle_texture;

// The fog's block, whole — see `lib/particle_fog.glsl`.
#include <lib/particle_fog.glsl>

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
  float fogged = ParticleFogTransmittance();

  // The texture's alpha is coverage and the particle's is brightness, so the
  // two multiply rather than one replacing the other: a faded spark of a
  // half-transparent sprite contributes a quarter, which is what additive
  // blending means by both of those at once.
  float scale = v_color.a * texel.a * fogged;
#ifdef F3D_SOFT_PARTICLE
  scale *= SoftParticleFade(v_world_position);
#endif
  frag_color = vec4(v_color.rgb * texel.rgb * scale, 1.0);
}
