#version 460 core

// A moved skinned mesh, drawn into the velocity buffer — `R1`.
//
// Skinned twice: by this frame's palette and by last frame's, which the
// renderer keeps in its frame history. A character standing still on a
// moving platform and a character running in place both move on screen,
// and only the two palettes together can tell those apart.
//
// **Last frame's palette is a texture**, four texels a joint and one joint a
// row, because a second 4 KB block beside `SkinInfo` is past the uniform
// space impellerc allows one stage. Read at texel centres through a nearest
// sampler, the way `lib/morph.glsl` reads its deltas and for its reason:
// `texelFetch` crashes impellerc in a vertex stage.

in vec3 position;

#include <lib/morph.glsl>

in vec4 joints;
in vec4 weights;

uniform FrameInfo {
  mat4 mvp;
  mat4 model;
  mat4 normal_matrix;
}
frame_info;

#define kMaxJoints 64

uniform SkinInfo {
  mat4 joint_matrices[kMaxJoints];
}
skin_info;

/// Last frame's `SkinInfo`: joint j's columns at texels (0..3, j) of a 4 ×
/// kMaxJoints float texture.
uniform sampler2D prev_joint_texture;

#include <lib/velocity.glsl>

mat4 PrevJoint(float joint) {
  float v = (joint + 0.5) / float(kMaxJoints);
  return mat4(texture(prev_joint_texture, vec2(0.125, v)),
              texture(prev_joint_texture, vec2(0.375, v)),
              texture(prev_joint_texture, vec2(0.625, v)),
              texture(prev_joint_texture, vec2(0.875, v)));
}

vec4 BlendWeights() {
  float total = weights.x + weights.y + weights.z + weights.w;
  return total > 1e-5 ? weights / total : vec4(1.0, 0.0, 0.0, 0.0);
}

void main() {
  vec4 w = BlendWeights();
  mat4 skin = w.x * skin_info.joint_matrices[int(joints.x)] +
              w.y * skin_info.joint_matrices[int(joints.y)] +
              w.z * skin_info.joint_matrices[int(joints.z)] +
              w.w * skin_info.joint_matrices[int(joints.w)];
  mat4 prevSkin = w.x * PrevJoint(joints.x) + w.y * PrevJoint(joints.y) +
                  w.z * PrevJoint(joints.z) + w.w * PrevJoint(joints.w);

  vec3 now = MorphPositionWith(position, morph_info.morph_weights[0],
                               morph_info.morph_weights[1]);
  vec3 then = MorphPositionWith(position, prev_info.previous_morph_weights[0],
                                prev_info.previous_morph_weights[1]);
  vec4 posed = skin * vec4(now, 1.0);
  v_current = prev_info.current_mvp * posed;
  v_depth = DepthAlongAxis(frame_info.model * posed);
  v_previous = prev_info.previous_mvp * (prevSkin * vec4(then, 1.0));
  gl_Position = frame_info.mvp * posed;
}
