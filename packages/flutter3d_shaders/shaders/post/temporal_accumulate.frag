#version 460 core

// A noisy effect blended into its own history — `R3`.
//
// The occlusion and the contact shadow are drawn with fewer samples while a
// temporal resolve runs, each frame rotated or offset by the next slice of
// blue noise. This pass carries last frame's answer to where each pixel is
// now, through the velocity the resolve uses, clamps it to what this frame
// found around the pixel so a moved edge cannot drag a stale shadow along,
// and blends. What comes out is many frames' worth of samples.
//
// One pass for both, at whatever size the effect is drawn: the velocity is
// read by UV, and a half-size occlusion reads it at its own coarser UV.

in vec2 v_uv;

out vec4 frag_color;

uniform sampler2D current_texture;
uniform sampler2D history_texture;
uniform sampler2D velocity_texture;

uniform AccumulateInfo {
  /// x: how much of each pixel is history, nought to one. y: one when there
  /// is a history to read, nought on the first frame and after a cut.
  /// zw: one texel of the effect.
  vec4 params;
}
accumulate_info;

void main() {
  vec4 now = texture(current_texture, v_uv);
  vec2 then = v_uv - texture(velocity_texture, v_uv).xy;
  if (accumulate_info.params.y < 0.5 || then.x < 0.0 || then.x > 1.0 ||
      then.y < 0.0 || then.y > 1.0) {
    frag_color = now;
    return;
  }

  vec2 texel = accumulate_info.params.zw;
  vec4 lowest = now;
  vec4 highest = now;
  for (int dy = -1; dy <= 1; dy++) {
    for (int dx = -1; dx <= 1; dx++) {
      vec4 around =
          texture(current_texture, v_uv + vec2(float(dx), float(dy)) * texel);
      lowest = min(lowest, around);
      highest = max(highest, around);
    }
  }
  vec4 past = clamp(texture(history_texture, then), lowest, highest);
  frag_color = mix(now, past, accumulate_info.params.x);
}
