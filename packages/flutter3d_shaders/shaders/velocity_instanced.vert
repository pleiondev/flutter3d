#version 460 core

// A moved batch, drawn into the velocity buffer — `R1`.
//
// Each instance is placed twice: by the transform it has now (slot 1) and by
// the one it had last frame (slot 2, the frame history's copy of the batch's
// bytes, laid out the same). Per-instance morph weights are not reprojected;
// a batch's morph moves by the batch-wide weights alone.

in vec3 position;

#include <lib/morph.glsl>

in vec4 i_row0;
in vec4 i_row1;
in vec4 i_row2;

in vec4 i_prev_row0;
in vec4 i_prev_row1;
in vec4 i_prev_row2;

uniform FrameInfo {
  mat4 mvp;
  mat4 model;
  mat4 normal_matrix;
}
frame_info;

#include <lib/velocity.glsl>

mat4 Affine(vec4 row0, vec4 row1, vec4 row2) {
  return mat4(vec4(row0.x, row1.x, row2.x, 0.0),
              vec4(row0.y, row1.y, row2.y, 0.0),
              vec4(row0.z, row1.z, row2.z, 0.0),
              vec4(row0.w, row1.w, row2.w, 1.0));
}

void main() {
  vec3 now = MorphPositionWith(position, morph_info.morph_weights[0],
                               morph_info.morph_weights[1]);
  vec3 then = MorphPositionWith(position, prev_info.previous_morph_weights[0],
                                prev_info.previous_morph_weights[1]);
  vec4 local = Affine(i_row0, i_row1, i_row2) * vec4(now, 1.0);
  vec4 before = Affine(i_prev_row0, i_prev_row1, i_prev_row2) * vec4(then, 1.0);
  v_current = prev_info.current_mvp * local;
  v_depth = DepthAlongAxis(frame_info.model * local);
  v_previous = prev_info.previous_mvp * before;
  gl_Position = frame_info.mvp * local;
}
