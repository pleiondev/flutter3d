// What the three velocity vertex stages share — `R1`.
//
// A node that moved is drawn again over the camera's velocity, and each of
// its vertices is carried through two matrices: this frame's and last
// frame's. Both are unjittered and carry the framebuffer origin, the way
// `post/camera_velocity.frag`'s are; the fragment stage turns the two clip
// positions into a difference in UV. The pass's own `gl_Position` goes
// through the jittered `FrameInfo.mvp`, so a fragment lands on the pixel the
// scene drew it on.
//
// **Hidden parts are rejected against the surface buffer, not a depth
// attachment.** Every pass in this engine clears depth on entry, so the
// scene's depth is not there to test against; the surface buffer holds the
// same answer in metres along the camera's axis. Each vertex hands on its
// own distance along that axis, and the fragment stage drops a fragment
// that lies behind what the scene drew there.
//
// Included after `lib/morph.glsl`: the position is morphed twice, by this
// frame's weights and by last frame's, through the one texture of deltas.

#ifndef VELOCITY_GLSL_
#define VELOCITY_GLSL_

uniform PrevFrameInfo {
  /// World to clip for this frame, unjittered, times the model matrix.
  mat4 current_mvp;

  /// The same product as it stood last frame: last frame's camera, last
  /// frame's model matrix.
  mat4 previous_mvp;

  /// Last frame's morph weights, packed as `MorphInfo.morph_weights` is.
  vec4 previous_morph_weights[2];

  /// xyz: where the eye is now.
  vec4 camera;

  /// xyz: the direction the camera looks now — the axis the surface
  /// buffer's depths are measured along.
  vec4 forward;
}
prev_info;

out vec4 v_current;
out vec4 v_previous;

/// This vertex's distance along the camera's axis, in metres.
out float v_depth;

float DepthAlongAxis(vec4 world) {
  return dot(world.xyz - prev_info.camera.xyz, prev_info.forward.xyz);
}

/// [position] moved towards the mesh's targets by [w0] and [w1] — the
/// position half of `ApplyMorph`, with the weights passed in.
vec3 MorphPositionWith(vec3 position, vec4 w0, vec4 w1) {
  int count = MorphCount();
  if (count <= 0) return position;

  float column = MorphColumn();
  float rowStep = morph_info.morph_params.z;
  vec3 normal = vec3(0.0);
  vec4 tangent = vec4(0.0);
  for (int i = 0; i < kMorphMax; i++) {
    if (i >= count) break;
    float weight = i < 4 ? w0[i] : w1[i - 4];
    if (weight == 0.0) continue;
    AddMorphTargetAt(i, weight, column, rowStep, position, normal, tangent);
  }
  return position;
}

#endif  // VELOCITY_GLSL_
