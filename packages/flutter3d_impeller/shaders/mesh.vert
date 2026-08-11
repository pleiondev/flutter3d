#version 460 core

// The order and types of the `in` variables define the vertex layout:
// flutter_gpu binds a vertex buffer as one blob, with no attribute descriptors.
// The Dart-side vertex struct must match this declaration byte for byte; see
// VertexLayout.standard.
//
// One layout for every model rather than a permutation per attribute set. The
// layout is structural — it is taken from these declarations — so a second one
// would mean a second vertex shader and a second pipeline per lighting model.
in vec3 position;
in vec3 normal;
in vec2 texcoord;

/// xyz is the tangent direction, w is the bitangent sign (glTF convention).
in vec4 tangent;

/// Vertex colour, multiplied into the albedo. Neutral is opaque white.
in vec4 color;

uniform FrameInfo {
  mat4 mvp;
  mat4 model;

  /// Inverse-transpose of the model matrix. Computed on the CPU because doing
  /// it per vertex would waste the ALU, and because mat3(model) is only correct
  /// while the scale stays uniform.
  mat4 normal_matrix;
}
frame_info;

// One varying set shared by every lighting model, matching shaders/lib/color.glsl.
out vec3 v_world_position;
out vec3 v_normal;
out vec2 v_texcoord;
out vec4 v_tangent;
out vec4 v_color;

void main() {
  vec4 world = frame_info.model * vec4(position, 1.0);
  v_world_position = world.xyz;
  v_normal = mat3(frame_info.normal_matrix) * normal;
  v_texcoord = texcoord;

  // The tangent transforms with the model matrix, not the normal matrix: it
  // lies *in* the surface, so it stretches with the geometry rather than
  // resisting it. Using the inverse transpose here is the classic way to get a
  // TBN that is subtly wrong under non-uniform scale.
  v_tangent = vec4(mat3(frame_info.model) * tangent.xyz, tangent.w);
  v_color = color;

  gl_Position = frame_info.mvp * vec4(position, 1.0);
}
