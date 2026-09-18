#version 460 core

// The point-light depth pass for a cut-out caster — `gfx-60n`.
//
// `shadow_distance.frag` with the same mask test `shadow_depth_masked.frag`
// carries, and a separate stage for the same reason: a caster that is not cut
// out keeps a pipeline with no sampler in it.
//
// Both stages exist because both shadow paths record a caster, and a leaf card
// lit by a torch is exactly as wrong as one lit by the sun. Point lights are
// where it shows worst, in fact: a cube face is a ninety-degree frustum with a
// caster close to it, so the slab of a foliage quad fills much more of the
// tile than it would in a cascade.

#define F3D_NO_SURFACE_BUFFER
#include <lib/color.glsl>

uniform ShadowLight {
  /// xyz: the light's world position. w: its range in metres.
  vec4 light;
}
shadow_light;

/// The base colour map, whose alpha is the mask.
uniform sampler2D base_color_texture;

uniform MaskInfo {
  // x: the cutoff, from `Material.alphaCutoff`. y: the base colour's own
  // alpha. z, w: unused.
  vec4 mask;
}
mask_info;

void main() {
  float alpha = texture(base_color_texture, v_texcoord).a * mask_info.mask.y;
  if (alpha < mask_info.mask.x) discard;

  float range = max(shadow_light.light.w, 1e-4);
  float distance = length(v_world_position - shadow_light.light.xyz);
  frag_color = vec4(clamp(distance / range, 0.0, 1.0), 0.0, 0.0, 1.0);
}
