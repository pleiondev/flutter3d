// The eye and the fog, for the stages that share none of the lit path's
// headers — particles, mesh particles, splats.
//
// They have a vertex layout of their own and none of the lit shaders'
// varyings, so `color.glsl` does not apply; this is the part of it they need:
// the `FogInfo` block as the lit stages declare it, and the two eye-relative
// questions asked of a world position passed in rather than of a varying.
//
// **All four members, `P7`.** The block used to stop after `eye`, and through
// an orthographic camera the fog then lay in rings round the eye's position
// — a point the picture does not depend on — and a mesh particle's faces were
// lit by how squarely they faced it. A stage that declares this block has to
// be bound all four, which is what the contributors do.

#ifndef CONTRIBUTOR_EYE_GLSL_
#define CONTRIBUTOR_EYE_GLSL_

uniform FogInfo {
  /// rgb: linear fog colour. w: density per metre at the eye, zero for no
  /// fog.
  vec4 fog;

  /// xyz: camera position in world space.
  vec4 eye;

  /// xyz: the direction the camera looks, as a unit vector in world space.
  vec4 forward;

  /// x: one when the camera's projection is orthographic, nought when it is
  /// perspective.
  vec4 projection;
}
fog_info;

/// How much air lies between [world] and the eye, in world metres: the
/// distance to it through a perspective lens, the depth from its plane
/// through an orthographic one, where every ray starts on that plane.
float FogDistance(vec3 world) {
  return fog_info.projection.x > 0.5
      ? max(dot(world - fog_info.eye.xyz, fog_info.forward.xyz), 0.0)
      : distance(world, fog_info.eye.xyz);
}

/// The unit direction from [world] back along the ray that reached it: to
/// the eye through a perspective lens, against the view axis through an
/// orthographic one. Nought where [world] is the eye.
vec3 TowardsEyeFrom(vec3 world) {
  if (fog_info.projection.x > 0.5) return -fog_info.forward.xyz;
  vec3 to_eye = fog_info.eye.xyz - world;
  float length_to_eye = length(to_eye);
  return length_to_eye > 0.0 ? to_eye / length_to_eye : vec3(0.0);
}

#endif  // CONTRIBUTOR_EYE_GLSL_
