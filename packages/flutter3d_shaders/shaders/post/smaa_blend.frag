#version 460 core

// SMAA 1x, last of three passes — `P1`: each pixel moved towards its
// neighbour across the edge by the share the second pass found.
//
// Four shares reach a pixel: its own for its top and left sides, and its
// right and bottom neighbours' far shares for the sides it shares with them.
// The larger pair wins — across or along — and the pixel is two filtered
// taps, each pulled that fraction of a texel towards its side.
//
// `flutter3d_cpu`'s `SmaaBlendShader` is this, line for line.
precision highp float;

in vec2 v_uv;

out vec4 frag_color;

/// The finished picture, filtered.
uniform sampler2D source_texture;

/// The second pass's shares.
uniform sampler2D blend_texture;

uniform SmaaInfo {
  /// x, y: one texel. z, w: the first pass's, unread here.
  vec4 params;
}
smaa_info;

void main() {
  vec2 texel = smaa_info.params.xy;
  float right = textureLod(blend_texture, v_uv + vec2(texel.x, 0.0), 0.0).a;
  float bottom = textureLod(blend_texture, v_uv + vec2(0.0, texel.y), 0.0).g;
  vec4 mine = textureLod(blend_texture, v_uv, 0.0);
  float top = mine.r;
  float left = mine.b;
  if (right + bottom + top + left < 1e-5) {
    frag_color = textureLod(source_texture, v_uv, 0.0);
    return;
  }

  bool across = max(right, left) > max(bottom, top);
  float toward = across ? right : bottom;
  float away = across ? left : top;
  vec2 axis = across ? vec2(texel.x, 0.0) : vec2(0.0, texel.y);
  vec4 first = textureLod(source_texture, v_uv + toward * axis, 0.0);
  vec4 second = textureLod(source_texture, v_uv - away * axis, 0.0);
  float total = toward + away;
  frag_color = first * (toward / total) + second * (away / total);
}
