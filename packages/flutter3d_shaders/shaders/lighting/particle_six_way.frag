#version 460 core

// Particles lit from six directions — `N6`.
//
// Smoke is the one effect additive blending cannot draw: it is dark where it
// is thick and lit where a light reaches into it, and addition can only ever
// brighten. So this stage blends over what is behind it, and lights each
// fragment by the scene's lights through six pictures of the same puff, each
// rendered with a light from one side. Mixing those by where a light really is
// gives the self-shadowing a volume would have, at the cost of two texture
// reads: a light low on the right brightens the lower right rim and leaves the
// far side in the puff's own shade.
//
// **Its own stage beside `particle_textured.frag`, not a branch inside it.**
// The textured stage has one sampler and one block, and every recorded frame
// with a sprite in it goes through it; a six-way branch there would declare
// three samplers and two blocks more that every sprite then has to be bound.
// `ParticleContributor` picks this one when it is handed a six-way material,
// the way it already picks between the sprite and the procedural disc.
//
// ## The layout
//
// Two textures, the channels as the engine's baker writes them and the
// EmberGen and Houdini six-way exports lay them out:
//
//  * `six_way_positive` — r: lit from the right, g: from the top, b: from the
//    back, a: coverage.
//  * `six_way_negative` — r: lit from the left, g: from the bottom, b: from
//    the front, a: emission.
//
// "Back" is the far side of the puff from the viewer, so a light behind smoke
// shows through its thin edges; "front" is the viewer's side. Right and top are
// the quad's own: top is the way a cell's texture coordinate rises, which
// `ParticleSystem.writeQuads` points along the camera's up.
//
// The responses are unpremultiplied — light as it would read at full coverage
// — and the blend is premultiplied, so this multiplies by the coverage once.

#include <lib/contributor_lights.glsl>

in vec4 v_color;
in vec2 v_uv;
in vec3 v_world_position;

out vec4 frag_color;

uniform sampler2D six_way_positive;
uniform sampler2D six_way_negative;

/// Declared again, as in the other particle stages, since this shares none of
/// the lit path's headers.
uniform FogInfo {
  /// rgb: linear fog colour. w: density per metre, zero for no fog.
  vec4 fog;

  /// xyz: camera position in world space.
  vec4 eye;
}
fog_info;

uniform SixWayInfo {
  /// xyz: the quad's right, which is the camera's, in world space.
  vec4 right;

  /// xyz: the quad's up, the way a cell's v rises.
  vec4 up;

  /// xyz: away from the viewer, which is where "back" is.
  vec4 forward;

  /// rgb: what the emission channel's full value emits, linear. w unused.
  vec4 emission;

  /// rgb: light arriving evenly from every side. w unused.
  vec4 ambient;
}
six_way_info;

/// How much of a light arriving from [l] the puff sends to the viewer.
///
/// The squared components of a unit direction sum to one, so they are weights:
/// a light straight to the right reads the right picture alone, and one up and
/// to the right reads half of each. The sign picks which of a pair.
float SixWayResponse(vec3 l, vec3 positive, vec3 negative) {
  float x = dot(l, six_way_info.right.xyz);
  float y = dot(l, six_way_info.up.xyz);
  float z = dot(l, six_way_info.forward.xyz);
  return x * x * (x > 0.0 ? positive.r : negative.r) +
         y * y * (y > 0.0 ? positive.g : negative.g) +
         z * z * (z > 0.0 ? positive.b : negative.b);
}

void main() {
  // `texture`, as the sprite stage has it: the level comes from the
  // footprint, and a receding puff wants its chain.
  vec4 positive = texture(six_way_positive, v_uv);
  vec4 negative = texture(six_way_negative, v_uv);

  vec3 lit = vec3(0.0);
  int count = ContributorLightCount(v_world_position);
  for (int i = 0; i < kContributorLights; i++) {
    if (i >= count) break;
    vec3 l;
    vec3 radiance;
    ContributorLight(i, v_world_position, l, radiance);
    lit += radiance * SixWayResponse(l, positive.rgb, negative.rgb);
  }

  // Light from every side at once reads each picture for a sixth of the
  // sphere, so the ambient term is their mean.
  float mean = (positive.r + positive.g + positive.b + negative.r +
                negative.g + negative.b) /
               6.0;
  vec3 color = v_color.rgb * (lit + six_way_info.ambient.rgb * mean) +
               six_way_info.emission.rgb * negative.a;

  // A mix toward the fog, unlike the additive stages: this one covers what is
  // behind it, and covered smoke far away should read as the fog does.
  float fogged = 1.0;
  if (fog_info.fog.w > 0.0) {
    fogged = clamp(
        exp(-fog_info.fog.w * distance(v_world_position, fog_info.eye.xyz)),
        0.0,
        1.0);
  }
  color = mix(fog_info.fog.rgb, color, fogged);

  float coverage = clamp(v_color.a * positive.a, 0.0, 1.0);
  frag_color = vec4(color * coverage, coverage);
}
