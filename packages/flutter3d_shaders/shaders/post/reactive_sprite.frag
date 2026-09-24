#version 460 core

// A particle or a splat, marked as reactive in the velocity target's blue —
// `R4`. See `reactive.frag` for what the mark is for; this is the same mark
// for what `particle.vert` draws.
//
// **Particles have no motion the resolve can see.** They write no depth and
// no velocity, so an ember that flew across a wall is reprojected as the
// wall, the history there is the wall, and the neighbourhood clip lets most
// of that wall through: the ember shows at a tenth of its brightness and
// trails. Marked here, the resolve takes that pixel mostly from this frame.
//
// **How much of a pixel a sprite covers**, which is what is written, comes
// from the same falloff its own stage draws with, so a spark's soft edge is
// only a little reactive and its core is fully so:
//
//   * a disc — `particle.frag`'s squared smoothstep, times the particle's
//     alpha;
//   * a Gaussian — `splat.frag`'s falloff, cut off at the same three
//     standard deviations, times the splat's alpha;
//   * a sprite — the texture's alpha, times the particle's.
//
// All three are worked out and one is chosen, rather than branching into
// one: the texture read has to sit in uniform control flow for WGSL, and the
// sprite stage is bound a white texel when the draw has none.

#include <lib/frag_coord.glsl>

in vec4 v_color;
in vec2 v_uv;
in vec3 v_world_position;

out vec4 frag_color;

uniform sampler2D surface_texture;
uniform sampler2D sprite_texture;

/// The same block `reactive.frag` declares, member for member.
uniform ReactiveInfo {
  vec4 target;
  vec4 eye;
  vec4 forward;
  vec4 params;
}
reactive_info;

void main() {
  float spriteAlpha = texture(sprite_texture, v_uv).a;

  vec2 centred = v_uv * 2.0 - 1.0;
  float falloff = 1.0 - smoothstep(0.0, 1.0, length(centred));
  float disc = falloff * falloff;

  float power = -0.5 * dot(v_uv, v_uv);
  float gaussian = power < -4.5 ? 0.0 : exp(power);

  float shape = reactive_info.params.y;
  float coverage =
      v_color.a *
      (shape < 0.5 ? disc : (shape < 1.5 ? gaussian : spriteAlpha));

  vec2 uv = FragCoordFromTop(reactive_info.target.z) * reactive_info.target.xy;
  float stored = textureLod(surface_texture, uv, 0.0).a;
  float depth = dot(v_world_position - reactive_info.eye.xyz,
                    reactive_info.forward.xyz);
  bool hidden = stored > 0.0 &&
                depth > stored * (1.0 + reactive_info.target.w) + 1e-3;
  float reactive = reactive_info.params.x * coverage;
  if (hidden || reactive <= 0.0) discard;
  frag_color = vec4(0.0, 0.0, reactive, 0.0);
}
