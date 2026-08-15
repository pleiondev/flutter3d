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

  // Which cascade covers this fragment.
  //
  // Chosen by distance from the camera and then *checked*, because the volumes
  // are spheres on the line of sight rather than fitted frusta: a fragment at
  // the edge of the view can be past the end of the cascade its distance
  // suggests. Falling through to the next one costs a branch and removes a
  // whole class of missing-shadow bug, and the last cascade is fitted to the
  // entire scene, so the fall-through always terminates somewhere real.
  int cascadeCount = int(frag_info.shadow_cascades.z + 0.5);
  float viewDistance = length(v_world_position - frag_info.camera_position.xyz);
  int cascade = 0;
  if (cascadeCount > 1 && viewDistance > frag_info.shadow_cascades.x) cascade = 1;
  if (cascadeCount > 2 && viewDistance > frag_info.shadow_cascades.y) cascade = 2;

  vec2 uv = vec2(0.0);
  vec3 projected = vec3(0.0);
  bool found = false;
  for (int attempt = 0; attempt < 3; attempt++) {
    int which = cascade + attempt;
    if (which >= cascadeCount) break;

    mat4 matrix = which == 0
        ? frag_info.shadow_matrix
        : (which == 1 ? frag_info.shadow_matrix_far
                      : frag_info.shadow_matrix_farthest);
    vec4 lightSpace = matrix * vec4(origin, 1.0);
    if (lightSpace.w <= 0.0) continue;
    vec3 candidate = lightSpace.xyz / lightSpace.w;

    // Clip space x and y are in [-1, 1]; a tile is in [0, 1] with the origin at
    // the top, matching where the render target's row zero is.
    vec2 inTile = vec2(candidate.x * 0.5 + 0.5, 0.5 - candidate.y * 0.5);
    if (inTile.x < 0.0 || inTile.x > 1.0 || inTile.y < 0.0 || inTile.y > 1.0) {
      continue;
    }
    // Depth is already in [0, 1] here, as every projection in this engine
    // produces; beyond the far plane there is nothing left to shadow.
    if (candidate.z > 1.0) continue;

    // Into the atlas: the cascades sit side by side in one texture.
    uv = vec2((inTile.x + float(which)) / float(cascadeCount), inTile.y);
    projected = candidate;
    cascade = which;
    found = true;
    break;
  }
  if (!found) return 1.0;

  float bias = frag_info.shadow_params.y;
  // Horizontally a texel of the atlas, vertically a texel of a tile. With one
  // cascade they are the same number and this is the kernel it has always been.
  vec2 texel = vec2(frag_info.shadow_params.x, frag_info.shadow_cascades.w);

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
