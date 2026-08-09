// Sampling the directional light's shadow map.
//
// A separate header for the same reason material_maps.glsl is one: the sampler
// must only be declared by shaders that actually read it, or the compiler drops
// the slot while the engine still tries to bind it.

#ifndef SHADOW_GLSL_
#define SHADOW_GLSL_

#include <lib/surface.glsl>

/// Linear depth from the light's point of view, in the red channel.
uniform sampler2D shadow_texture;

/// How much of the light survives at this fragment, from 0 to 1.
///
/// Returns 1 when shadows are off, when the fragment falls outside the map, or
/// when the light in question is not the caster — a fragment beyond the shadow
/// volume is unshadowed, not black, and getting that wrong puts a hard edge
/// across the scene at the edge of the map.
float ShadowFactor(Surface s, LightSample light, int lightIndex) {
  float strength = frag_info.shadow_params.w;
  if (strength <= 0.0) return 1.0;
  if (lightIndex != int(frag_info.frame_params.z + 0.5)) return 1.0;

  // Normal offset: move the sample point along the surface normal before
  // projecting it. It costs nothing and fixes the shadow acne that a depth bias
  // alone cannot, because the error is proportional to the surface's slope
  // relative to the light rather than to depth.
  vec3 origin = v_world_position + s.n * frag_info.shadow_params.z;

  vec4 lightSpace = frag_info.shadow_matrix * vec4(origin, 1.0);
  if (lightSpace.w <= 0.0) return 1.0;
  vec3 projected = lightSpace.xyz / lightSpace.w;

  // Clip space x and y are in [-1, 1]; the texture is in [0, 1] with the
  // origin at the top, matching where the render target's row zero is.
  vec2 uv = vec2(projected.x * 0.5 + 0.5, 0.5 - projected.y * 0.5);
  if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return 1.0;
  // Depth is already in [0, 1] here, as every projection in this engine
  // produces; beyond the far plane there is nothing left to shadow.
  if (projected.z > 1.0) return 1.0;

  float bias = frag_info.shadow_params.y;
  float texel = frag_info.shadow_params.x;

  // PCF 3x3. Four samples would band visibly at this map size and nine is the
  // smallest kernel that reads as a soft edge rather than as stair steps.
  float lit = 0.0;
  for (int y = -1; y <= 1; y++) {
    for (int x = -1; x <= 1; x++) {
      float occluder =
          texture(shadow_texture, uv + vec2(float(x), float(y)) * texel).r;
      lit += projected.z - bias > occluder ? 0.0 : 1.0;
    }
  }
  lit *= 1.0 / 9.0;

  // Strength lerps towards fully lit, so the control is "how dark", not "how
  // much of the kernel".
  return mix(1.0, lit, clamp(strength, 0.0, 1.0));
}

#endif  // SHADOW_GLSL_
