#version 460 core

// The nodes a game outlines, each in its own colour, where the scene shows
// them — `N9`, the high-contrast look's second half.
//
// **A colour on the node, written into a target of its own**, and only for
// the nodes that carry one. `MeshNode.outlineColor` is null on everything a
// game did not mark, so a level of walls and props draws nothing here at all;
// a frame with no marked node in view does not even run the pass. What it
// writes is the colour and a flag, into eight bits a channel cleared to
// nought, which `high_contrast.frag` reads to draw a ring of that colour
// around whatever is marked.
//
// Drawn through the three velocity vertex stages, as `reactive.frag` is and
// for its reason: they already land a skinned, morphed or batched node where
// the scene drew it, and they hand on the one number this needs — the
// fragment's depth along the camera's axis. The other two outputs are
// declared because a stage's inputs are matched to the vertex stage's outputs
// by position on some targets.
//
// **Hidden parts are dropped against the surface buffer, not a depth
// attachment** — every pass in this engine clears depth on entry, so the
// scene's depth is not there to test against, and the surface buffer holds
// the same answer in metres. That is what keeps a monster behind a wall from
// being outlined *through* it: a ring around what cannot be seen is a sensor,
// which is `RenderSettings.xray`'s job and a game decision, not an
// accessibility one. A fragment behind what the opaque scene drew is not
// written; over a pixel that holds no depth — a marked node that blends —
// it is in front of everything there is.

#include <lib/frag_coord.glsl>

in vec4 v_current;
in vec4 v_previous;
in float v_depth;

out vec4 frag_color;

uniform sampler2D surface_texture;

uniform OutlineMaskInfo {
  /// xy: one over the target's size in pixels. z: the target's rows when
  /// its row zero is the bottom, zero when it is the top. w: how far behind
  /// the stored depth a fragment may lie and still count as the surface the
  /// scene drew there, as a fraction of that depth.
  vec4 target;

  /// rgb: the node's outline colour, display-referred, as a `Color` gives
  /// it. w: unused, written one.
  vec4 color;
}
mask_info;

void main() {
  vec2 uv = FragCoordFromTop(mask_info.target.z) * mask_info.target.xy;
  float stored = textureLod(surface_texture, uv, 0.0).a;
  bool hidden =
      stored > 0.0 && v_depth > stored * (1.0 + mask_info.target.w) + 1e-3;
  if (hidden) discard;
  frag_color = vec4(mask_info.color.rgb, 1.0);
}
