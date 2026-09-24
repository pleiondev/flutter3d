#version 460 core

// The longest motion in a tile and the eight around it — `R6`.
//
// A pixel is blurred by what moves near it, and "near" reaches as far as the
// longest blur, which is a tile. A pixel at the edge of its own tile can be
// crossed by something moving in the next one, so the blur asks this
// neighbourhood rather than its own tile: the dominant motion within one
// radius of any pixel in the tile.

in vec2 v_uv;

out vec4 frag_color;

uniform sampler2D tile_texture;

uniform NeighborMaxInfo {
  // xy: one tile texel. zw unused.
  vec4 texel;
}
neighbor_info;

void main() {
  vec2 longest = vec2(0.0);
  float longestSpan = 0.0;
  for (int dy = -1; dy <= 1; dy++) {
    for (int dx = -1; dx <= 1; dx++) {
      vec2 at = v_uv + vec2(float(dx), float(dy)) * neighbor_info.texel.xy;
      vec2 motion = textureLod(tile_texture, at, 0.0).rg;
      float span = dot(motion, motion);
      if (span > longestSpan) {
        longest = motion;
        longestSpan = span;
      }
    }
  }
  frag_color = vec4(longest, 0.0, 1.0);
}
