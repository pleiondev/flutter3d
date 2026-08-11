#version 460 core

// The depth pass for a point light: radial distance rather than clip depth.
//
// A cube shadow compares how far a fragment is from the light against how far
// the nearest caster in that direction was. Clip depth cannot answer that: it
// is measured along one face's axis, so the same distance reads differently
// depending on which face a direction lands on, and every face boundary would
// show a seam. Distance from the light is the same number whichever face
// recorded it.
//
// Normalised by the light's range so it fits an 8-bit-ish target and so the
// comparison is a plain fraction. Beyond the range there is no light, so the
// shadow there is nobody's business.
//
// One attachment: this writes a shadow atlas, and the surface buffer belongs
// to the scene pass.
#define F3D_NO_SURFACE_BUFFER
#include <lib/color.glsl>

uniform ShadowLight {
  /// xyz: the light's world position. w: its range in metres.
  vec4 light;
}
shadow_light;

void main() {
  float range = max(shadow_light.light.w, 1e-4);
  float distance = length(v_world_position - shadow_light.light.xyz);
  frag_color = vec4(clamp(distance / range, 0.0, 1.0), 0.0, 0.0, 1.0);
}
