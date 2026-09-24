#version 460 core

// A blended surface, marked as reactive in the velocity target's blue — `R4`.
//
// **What the mark is for.** The temporal resolve keeps most of each pixel
// from the frames before, and that is right for anything the velocity can
// follow. Glass cannot be followed: it wrote no depth, so the velocity under
// it is the motion of what is behind it, and whatever moves across the glass
// itself (a reflection, the light it tints) is remembered for a dozen frames
// after it went. Where this is drawn the resolve keeps less of the past, in
// proportion to the value written here.
//
// Drawn through the three velocity vertex stages, so a skinned, morphed or
// batched surface lands where the scene drew it; of what they hand on only
// the depth along the camera's axis is read. The other two are declared
// because a stage's inputs are matched to the vertex stage's outputs by
// position on some targets, and a stage that declared the depth alone would
// read `v_current` in its place.
//
// Added into blue under an additive blend that finds red, green and alpha
// the velocity passes left and adds nought to each, which leaves them exactly
// as they were: flutter_gpu has no colour write mask, and adding zero is the
// one blend that is a mask.

#include <lib/frag_coord.glsl>

in vec4 v_current;
in vec4 v_previous;
in float v_depth;

out vec4 frag_color;

uniform sampler2D surface_texture;

uniform ReactiveInfo {
  /// xy: one over the target's size in pixels. z: the target's rows when
  /// its row zero is the bottom, zero when it is the top. w: how far behind
  /// the stored depth a fragment may lie and still count as in front of it,
  /// as a fraction of that depth.
  vec4 target;

  /// xyz: where the eye is. Read by the sprite stage, which has no depth of
  /// its own handed on.
  vec4 eye;

  /// xyz: the direction the camera looks, the surface buffer's axis.
  vec4 forward;

  /// x: how reactive full coverage is, nought to one. y: the sprite stage's
  /// shape — nought a disc, one a Gaussian, two the sprite's own alpha.
  /// z: this draw's coverage, for a surface: its material's alpha.
  vec4 params;
}
reactive_info;

void main() {
  vec2 uv = FragCoordFromTop(reactive_info.target.z) * reactive_info.target.xy;
  float stored = textureLod(surface_texture, uv, 0.0).a;
  // Behind what the opaque scene drew here: the glass is hidden and so is
  // whatever it would have smeared. Over the sky, or over a pixel the blend
  // left no depth in, it is in front of everything there is.
  bool hidden = stored > 0.0 &&
                v_depth > stored * (1.0 + reactive_info.target.w) + 1e-3;
  float coverage = reactive_info.params.x * reactive_info.params.z;
  if (hidden || coverage <= 0.0) discard;
  frag_color = vec4(0.0, 0.0, coverage, 0.0);
}
