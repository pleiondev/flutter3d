#version 460 core

// The skinned vertex stage.
//
// A second vertex shader rather than a branch inside mesh.vert, and the reason
// is structural rather than a performance guess: flutter_gpu takes the vertex
// layout from the `in` declarations, so joints and weights being attributes
// makes this a different layout, and a different layout is a different shader
// whatever the body does. Declaring the joint matrices in the static shader and
// leaving them unread would also be the phantom-uniform trap — reflection would
// report the block while the compiled function bound no buffer.
//
// The fragment side is untouched: skinning moves vertices, and every lighting
// model reads the same varyings either way.
in vec3 position;
in vec3 normal;
in vec2 texcoord;
in vec4 tangent;
in vec4 color;

/// Four joint indices, held as floats. See VertexLayout.joints.
in vec4 joints;

/// Their influences. Normalized here rather than trusted, because an exporter
/// that rounds to a normalized byte leaves sums a little off one, and the error
/// shows up as a mesh that breathes.
in vec4 weights;

uniform FrameInfo {
  mat4 mvp;
  mat4 model;
  mat4 normal_matrix;
}
frame_info;

/// Must match Skeleton.maxJoints on the Dart side.
///
/// A fixed array with the count implied by the data, the same shape the lights
/// use: shaders are compiled ahead of time, so a permutation per joint count is
/// not available even if it were desirable.
#define kMaxJoints 64

uniform SkinInfo {
  mat4 joint_matrices[kMaxJoints];
}
skin_info;

out vec3 v_world_position;
out vec3 v_normal;
out vec2 v_texcoord;
out vec4 v_tangent;
out vec4 v_color;
out vec2 v_lightmap_uv;

/// The blended bone transform for this vertex.
mat4 SkinMatrix() {
  // Renormalizing costs three adds and a divide, and it is what stops a mesh
  // from swelling or shrinking where the authored weights do not quite sum to
  // one. A zero sum means the vertex named no joints at all, and falling back
  // to full influence on the first one leaves it rigid instead of collapsing it
  // to the origin.
  float total = weights.x + weights.y + weights.z + weights.w;
  vec4 w = total > 1e-5 ? weights / total : vec4(1.0, 0.0, 0.0, 0.0);

  return w.x * skin_info.joint_matrices[int(joints.x)] +
         w.y * skin_info.joint_matrices[int(joints.y)] +
         w.z * skin_info.joint_matrices[int(joints.z)] +
         w.w * skin_info.joint_matrices[int(joints.w)];
}

void main() {
  mat4 skin = SkinMatrix();
  // Skin first, then place: the joint matrices work in the mesh's own space, so
  // the model matrix still has to carry the result into the world.
  mat4 skinnedModel = frame_info.model * skin;

  vec4 world = skinnedModel * vec4(position, 1.0);
  v_world_position = world.xyz;

  // The joint transform rotates and may scale, so the normal needs the same
  // treatment it gets from the model matrix. mat3(skin) is exact while the
  // joints only rotate and translate, which is the case for every rig in
  // practice; a non-uniformly scaled joint would need the inverse transpose,
  // and computing that per vertex is the trade this deliberately does not make.
  mat3 skinRotation = mat3(skin);
  v_normal = mat3(frame_info.normal_matrix) * (skinRotation * normal);
  v_tangent = vec4(
      mat3(frame_info.model) * (skinRotation * tangent.xyz), tangent.w);

  v_texcoord = texcoord;
  v_color = color;
  v_lightmap_uv = vec2(0.0);

  gl_Position = frame_info.mvp * (skin * vec4(position, 1.0));
}
