#version 460 core

// The fragment half of the vertex-texture probe. See `vertex_texture.vert`.
//
// It writes what the *vertex* stage sampled, and that is the whole design: a
// probe whose fragment stage did its own sampling would come back green on a
// backend where the vertex stage read nothing, which is the answer it exists to
// distinguish.
precision highp float;

in vec4 v_sampled;

out vec4 frag_color;

void main() {
  frag_color = v_sampled;
}
