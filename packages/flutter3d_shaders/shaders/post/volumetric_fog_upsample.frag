#version 460 core

// The half-resolution fog laid over the full-resolution scene — `S4`.
//
// **Depth-aware, which is the whole reason this is its own pass.** A plain
// bilinear stretch of a half-resolution fog mixes, at every silhouette, a ray
// that stopped at the near wall with one that ran on to the far one: the
// torch's halo behind a pillar bleeds a pixel over the pillar's edge, and the
// pillar's edge brings its clear air into the halo. Here each of the four
// nearest fog texels is weighted by its bilinear share *and* by how close the
// depth its ray stopped at is to this pixel's own, so the texels on the other
// side of an edge all but drop out and the edge stays where the scene has it.
//
// The fog texel's depth is read from the full-resolution surface buffer at
// that texel's centre, which is the very texel the march read — nearest on
// both — so the depth compared is the one the ray was actually cut at.
//
// **Composited before the tone map**: the scene behind keeps the share the
// air lets through and the in-scatter is added, both in linear light.
//
// **The occlusion lands on the surface here, before the air, and not in the
// composite.** Ambient occlusion and the contact shadow say how much light
// reaches the surface a ray stopped at; they have nothing to say about the
// air in front of it. The composite multiplies them into the whole colour,
// which, once the fog is in that colour, draws the creases of a far wall on
// the air in front of it: dark lines that thicker fog should wash out and
// instead makes plainer. So this pass takes them over, the same 2×2 average
// and the same strengths the composite uses, and the renderer zeroes the
// composite's strengths on a frame where it did. Zero strengths here are a
// multiplier of exactly one, so fog without occlusion is what it was.

in vec2 v_uv;

out vec4 frag_color;

uniform sampler2D scene_texture;
uniform sampler2D fog_texture;
uniform sampler2D surface_texture;
uniform sampler2D ao_texture;
uniform sampler2D contact_shadow_texture;

uniform FogUpsampleInfo {
  // xy: the fog texture's size in texels. zw: one texel of the occlusion
  // buffer, for the composite's 2×2 average.
  vec4 size;
  // x: the occlusion's strength, y: the contact shadow's, z: one when the
  // occlusion buffer holds bounced light in rgb (`L5`). All nought when the
  // composite keeps them. w unused.
  vec4 occlusion;
}
upsample_info;

// A depth to compare: the surface buffer's, with the cleared sky pushed far
// away so a sky pixel matches sky texels and not the nearest wall.
float DepthAt(vec2 uv) {
  float depth = textureLod(surface_texture, uv, 0.0).a;
  return depth > 0.0 ? depth : 1e6;
}

// Adds fog texel [cell], at bilinear share [share], weighted against the
// pixel's own depth [here].
void Tap(vec2 cell, float share, float here, inout vec4 sum,
         inout float weight) {
  vec2 size = upsample_info.size.xy;
  vec2 uv = (clamp(cell, vec2(0.0), size - 1.0) + 0.5) / size;
  float difference = abs(DepthAt(uv) - here) / max(here, 1e-3);
  float w = share / (0.01 + difference);
  sum += textureLod(fog_texture, uv, 0.0) * w;
  weight += w;
}

void main() {
  vec4 scene = texture(scene_texture, v_uv);
  vec2 size = max(upsample_info.size.xy, vec2(1.0));
  vec2 at = v_uv * size - 0.5;
  vec2 base = floor(at);
  vec2 f = at - base;
  float here = DepthAt(v_uv);

  vec4 sum = vec4(0.0);
  float weight = 0.0;
  Tap(base, (1.0 - f.x) * (1.0 - f.y), here, sum, weight);
  Tap(base + vec2(1.0, 0.0), f.x * (1.0 - f.y), here, sum, weight);
  Tap(base + vec2(0.0, 1.0), (1.0 - f.x) * f.y, here, sum, weight);
  Tap(base + vec2(1.0, 1.0), f.x * f.y, here, sum, weight);
  vec4 fog = weight > 1e-6 ? sum / weight : vec4(0.0, 0.0, 0.0, 1.0);

  // What `composite.frag` does to the scene, operation for operation.
  vec2 half_texel = upsample_info.size.zw * 0.5;
  vec4 occlusion =
      0.25 * (texture(ao_texture, v_uv + vec2(half_texel.x, half_texel.y)) +
              texture(ao_texture, v_uv + vec2(-half_texel.x, half_texel.y)) +
              texture(ao_texture, v_uv + vec2(half_texel.x, -half_texel.y)) +
              texture(ao_texture, v_uv + vec2(-half_texel.x, -half_texel.y)));
  float strength = clamp(upsample_info.occlusion.x, 0.0, 1.0);
  float ao = mix(1.0, occlusion.a, strength);
  float contact = texture(contact_shadow_texture, v_uv).r;
  ao *= mix(1.0, contact, clamp(upsample_info.occlusion.y, 0.0, 1.0));
  vec3 surfaceLight =
      scene.rgb * ao + occlusion.rgb * upsample_info.occlusion.z * strength;

  frag_color = vec4(surfaceLight * fog.a + fog.rgb, scene.a);
}
