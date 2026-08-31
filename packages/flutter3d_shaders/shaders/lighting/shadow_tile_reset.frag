#version 460 core

// Clearing one tile of the shadow atlas, by drawing over it.
//
// A render pass clears its whole colour attachment: viewport and scissor bound
// where the rasteriser may write, and neither bounds the load action. That is
// fine while every tile is redrawn every frame, and fatal the moment they are
// not — refreshing one light's face would erase every other face in the atlas.
//
// So the atlas pass loads its previous contents instead of clearing them, and
// a tile that *is* being refreshed is reset by drawing this over it first,
// inside that tile's viewport. A draw is bounded by the viewport where a clear
// is not, which is the whole reason this shader exists.
//
// One, the far end of the range: a texel no caster covers means "nothing
// between the light and its range", which is the right answer for a direction
// with nothing in it. The same value the pass used to clear to.
precision highp float;

in vec2 v_uv;

out vec4 frag_color;

void main() {
  frag_color = vec4(1.0);
}
