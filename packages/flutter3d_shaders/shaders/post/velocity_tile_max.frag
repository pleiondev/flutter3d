#version 460 core

// The longest motion in a tile, one axis at a time — `R6`.
//
// The first half of the motion blur's neighbourhood: the frame is cut into
// square tiles as wide as the longest blur, and each tile learns the longest
// motion anywhere in it. Two passes rather than one, each over one axis of
// the tile — a tile of twenty pixels is forty reads that way instead of four
// hundred — and the same stage draws both: the step between taps says which
// axis it is walking.
//
// **The first pass also turns the velocity into what the blur spreads**:
// the velocity buffer holds a whole frame's motion in UV units, and the blur
// wants half the exposed part of it in pixels, clamped to the largest radius.
// The second pass reads what the first wrote and scales by one.

in vec2 v_uv;

out vec4 frag_color;

uniform sampler2D velocity_texture;

uniform TileMaxInfo {
  // xy: one texel of the source. zw: the step between taps, in texels —
  // (1, 0) walks a row, (0, 1) a column.
  vec4 source;

  // xy: what a source value is multiplied by to be a half-motion in pixels.
  // z: the longest a half-motion may be, in pixels. w: taps per tile.
  vec4 params;

  // xy: this target's size in texels. zw unused.
  vec4 target;
}
tile_info;

// [motion] scaled into pixels and no longer than the largest radius.
vec2 HalfMotion(vec2 motion) {
  vec2 pixels = motion * tile_info.params.xy;
  float span = length(pixels);
  float most = max(tile_info.params.z, 0.0);
  return span > most ? pixels * (most / span) : pixels;
}

void main() {
  // `textureLod` for `depth_of_field.frag`'s reason: the reads sit in a loop
  // whose exit is per fragment, and WGSL refuses an implicit derivative
  // there.
  vec2 walk = tile_info.source.zw;
  vec2 tile = floor(v_uv * tile_info.target.xy);
  int taps = int(tile_info.params.w + 0.5);
  // A tile's first texel: a whole tile along the axis walked, the tile's own
  // row or column across it.
  vec2 start = tile * mix(vec2(1.0), vec2(float(taps)), walk);

  vec2 longest = vec2(0.0);
  float longestSpan = 0.0;
  for (int i = 0; i < 64; i++) {
    if (i >= taps) break;
    vec2 at = (start + walk * float(i) + 0.5) * tile_info.source.xy;
    vec2 motion = HalfMotion(textureLod(velocity_texture, at, 0.0).rg);
    float span = dot(motion, motion);
    if (span > longestSpan) {
      longest = motion;
      longestSpan = span;
    }
  }
  frag_color = vec4(longest, 0.0, 1.0);
}
