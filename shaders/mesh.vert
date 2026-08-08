#version 460 core

// The order and types of the `in` variables define the vertex layout:
// flutter_gpu binds a vertex buffer as one blob, with no attribute descriptors.
// The Dart-side vertex struct must match this declaration byte for byte; see
// VertexLayout.positionNormalTexcoord.
in vec3 position;
in vec3 normal;
in vec2 texcoord;

uniform FrameInfo {
  mat4 mvp;
  mat4 model;

  /// Inverse-transpose of the model matrix. Computed on the CPU because doing
  /// it per vertex would waste the ALU, and because mat3(model) is only correct
  /// while the scale stays uniform.
  mat4 normal_matrix;
}
frame_info;

// One varying set shared by every lighting model, matching shaders/lib/surface.glsl.
out vec3 v_world_position;
out vec3 v_normal;
out vec2 v_texcoord;

void main() {
  vec4 world = frame_info.model * vec4(position, 1.0);
  v_world_position = world.xyz;
  v_normal = mat3(frame_info.normal_matrix) * normal;
  v_texcoord = texcoord;

  gl_Position = frame_info.mvp * vec4(position, 1.0);
}
