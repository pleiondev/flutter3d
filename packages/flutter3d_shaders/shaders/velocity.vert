#version 460 core

// A moved mesh, drawn into the velocity buffer — `R1`. See
// `lib/velocity.glsl` for the two matrices and why the depth goes through a
// third.
//
// Only the position is declared: the pipeline is built with an explicit
// layout over the standard sixty-four-byte vertex, so the rest of the vertex
// is stepped over rather than read.

in vec3 position;

#include <lib/morph.glsl>

uniform FrameInfo {
  mat4 mvp;
  mat4 model;
  mat4 normal_matrix;
}
frame_info;

#include <lib/velocity.glsl>

void main() {
  vec3 now = MorphPositionWith(position, morph_info.morph_weights[0],
                               morph_info.morph_weights[1]);
  vec3 then = MorphPositionWith(position, prev_info.previous_morph_weights[0],
                                prev_info.previous_morph_weights[1]);
  v_current = prev_info.current_mvp * vec4(now, 1.0);
  v_depth = DepthAlongAxis(frame_info.model * vec4(now, 1.0));
  v_previous = prev_info.previous_mvp * vec4(then, 1.0);
  gl_Position = frame_info.mvp * vec4(now, 1.0);
}
