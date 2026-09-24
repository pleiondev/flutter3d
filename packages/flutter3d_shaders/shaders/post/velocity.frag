#version 460 core

// A moved node's velocity, from the two clip positions its vertex stage
// wrote — `R1`. Now minus then, in UV, as `camera_velocity.frag` writes it.
//
// Divided per fragment rather than per vertex: the perspective divide does
// not interpolate linearly across a triangle, and a velocity divided at the
// corners would bend across a large polygon seen at a slant.
//
// A fragment behind what the scene drew at this pixel is dropped, which is
// the depth test done against the surface buffer — see `lib/velocity.glsl`.

#include <lib/frag_coord.glsl>

in vec4 v_current;
in vec4 v_previous;
in float v_depth;

out vec4 frag_color;

uniform sampler2D surface_texture;

uniform VelocityInfo {
  /// xy: one over the target's size in pixels. z: the target's rows when
  /// its row zero is the bottom, zero when it is the top — see
  /// `FragCoordFromTop`. w: how far behind the stored depth a fragment may
  /// lie and still count as the surface, as a fraction of that depth.
  vec4 target;
}
velocity_info;

vec2 UvFromClip(vec4 clip) {
  vec2 ndc = clip.xy / clip.w;
  return vec2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
}

void main() {
  vec2 uv = FragCoordFromTop(velocity_info.target.z) * velocity_info.target.xy;
  float stored = textureLod(surface_texture, uv, 0.0).a;
  // Sky, or something nearer: this fragment is not what the pixel shows.
  // The tolerance is relative, for the reason every comparison against this
  // buffer is: a fixed one is a different share of a pixel at every range.
  if (stored <= 0.0 ||
      v_depth > stored * (1.0 + velocity_info.target.w) + 1e-3) {
    discard;
  }
  if (v_previous.w <= 0.0) {
    frag_color = vec4(0.0, 0.0, 0.0, 1.0);
    return;
  }
  frag_color = vec4(UvFromClip(v_current) - UvFromClip(v_previous), 0.0, 1.0);
}
