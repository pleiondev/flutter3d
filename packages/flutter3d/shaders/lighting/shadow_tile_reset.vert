#version 460 core

// Vertex stage for the atlas tile reset. See shadow_tile_reset.frag.
//
// The same oversized triangle every full-screen pass uses, with one difference
// that matters: **z sits on the far plane, not at zero.**
//
// post/fullscreen.vert emits z = 0, which is mid-depth. That is harmless for a
// post pass, where nothing depth-tests afterwards. Here the casters are drawn
// into the same tile immediately after, comparing `less` against a buffer this
// triangle has just covered — and a mid-depth value stamped across the tile
// makes every caster beyond it fail the test and vanish. It showed up as a
// shadow that was present before the tile reset existed and missing after:
// 423 pixels of `cube-shadow`, all inside the one occupied tile.
//
// Depth writes are switched off for this draw as well, so in principle the
// value is never stored. Writing the far plane anyway costs nothing and means
// the pass does not depend on that being true — which is worth more than the
// elegance, given the value written would be invisible right up until it
// silently deleted a shadow.
in vec2 position;
in vec2 texcoord;

out vec2 v_uv;

void main() {
  v_uv = texcoord;
  gl_Position = vec4(position, 1.0, 1.0);
}
