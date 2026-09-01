#version 460 core

// Vertex stage for an instanced mesh: one mesh, drawn once per instance, each
// instance with a transform and a colour of its own.
//
// The same varyings as mesh.vert and the same FrameInfo block, and that is the
// whole design: every fragment shader in the bundle and both shadow passes
// take this stage without knowing it is instanced. What differs is slot 1 —
// the placements, stepping once per instance — and that `model` here is the
// node's transform, which the instance transform sits inside. An instance is
// placed relative to its node, so moving the node moves the whole batch and a
// batch of a thousand costs one uniform write.
//
// Twelve floats an instance for the transform, not sixteen: the bottom row of
// an affine matrix is always (0, 0, 0, 1), and a quarter of the buffer would
// be spent saying so. Stored as three rows so the vertex stage assembles a
// mat4 from them in three moves.

in vec3 position;
in vec3 normal;
in vec2 texcoord;
in vec4 tangent;
in vec4 color;

/// Rows of the instance's 3x4 affine transform, in the node's space.
in vec4 i_row0;
in vec4 i_row1;
in vec4 i_row2;
/// Multiplied into the vertex colour, so a batch of one mesh can vary its tint.
in vec4 i_color;

uniform FrameInfo {
  mat4 mvp;
  mat4 model;
  mat4 normal_matrix;
}
frame_info;

out vec3 v_world_position;
out vec3 v_normal;
out vec2 v_texcoord;
out vec4 v_tangent;
out vec4 v_color;

void main() {
  // Columns from rows: GLSL matrices are column-major, so the constructor is
  // handed the transpose of what the buffer holds.
  mat4 instance = mat4(
      vec4(i_row0.x, i_row1.x, i_row2.x, 0.0),
      vec4(i_row0.y, i_row1.y, i_row2.y, 0.0),
      vec4(i_row0.z, i_row1.z, i_row2.z, 0.0),
      vec4(i_row0.w, i_row1.w, i_row2.w, 1.0));
  vec4 local = instance * vec4(position, 1.0);
  vec4 world = frame_info.model * local;
  v_world_position = world.xyz;
  // The instance's rotation and scale applied before the node's normal matrix.
  // Correct for a rotation and a uniform scale, which is what an instance is
  // for; a non-uniform instance scale skews the normal, and that is the
  // documented limit rather than an inverse transpose per vertex.
  mat3 rotation = mat3(instance);
  v_normal = mat3(frame_info.normal_matrix) * normalize(rotation * normal);
  v_texcoord = texcoord;
  v_tangent = vec4(mat3(frame_info.model) * (rotation * tangent.xyz), tangent.w);
  v_color = color * i_color;
  gl_Position = frame_info.mvp * local;
}
