// The fog, for the stages that share none of the lit shaders' headers:
// particles and splats — `P7`, `P5`.
//
// **The lit block's whole shape, where these stages used to declare its first
// two members.** With only the fog and the eye, a particle could not tell an
// orthographic camera from a perspective one, so it fogged in rings round a
// point nobody sees and faced a mesh particle towards it; and with the eye's
// `w` undeclared it could not thin upwards with a height fog, so it fogged at
// the camera's density whatever its height. The four members and their
// meanings are `color.glsl`'s, and the engine fills them the same way.
//
// Include after declaring `v_world_position`.

#ifndef PARTICLE_FOG_GLSL_
#define PARTICLE_FOG_GLSL_

uniform FogInfo {
  /// rgb: linear fog colour. w: density per metre at the eye, zero for no
  /// fog.
  vec4 fog;

  /// xyz: camera position in world space. w: how fast the fog thins
  /// upwards, per metre; nought is flat fog.
  vec4 eye;

  /// xyz: the direction the camera looks, a unit vector in world space.
  /// w: unused here.
  vec4 forward;

  /// x: one when the camera's projection is orthographic, nought when it is
  /// perspective. y, z, w unused.
  vec4 projection;
}
fog_info;

/// Whether the camera is orthographic. See `Orthographic` in `color.glsl`.
bool ParticleOrthographic() { return fog_info.projection.x > 0.5; }

/// The air between the eye and this fragment, in metres: the distance from
/// the eye through a perspective lens, the depth from the eye's plane
/// through an orthographic one — `EyeDistance` in `color.glsl`.
float ParticleEyeDistance() {
  return ParticleOrthographic()
             ? max(dot(v_world_position - fog_info.eye.xyz,
                       fog_info.forward.xyz),
                   0.0)
             : distance(v_world_position, fog_info.eye.xyz);
}

/// The unit direction back along the ray that reached this fragment: to the
/// eye through a perspective lens, against the view axis through an
/// orthographic one. `TowardsEye` in `color.glsl`.
vec3 ParticleTowardsEye() {
  vec3 to_eye = fog_info.eye.xyz - v_world_position;
  float length_to_eye = length(to_eye);
  if (ParticleOrthographic()) return -fog_info.forward.xyz;
  return length_to_eye > 0.0 ? to_eye / length_to_eye : vec3(0.0);
}

/// How much of this fragment the fog leaves, from nought to one: `ApplyFog`'s
/// share in `color.glsl`, height fog and all, so a puff of smoke in a valley
/// fogs as the ground beside it does. One with no fog.
float ParticleFogTransmittance() {
  float density = fog_info.fog.w;
  if (density <= 0.0) return 1.0;
  float falloff = fog_info.eye.w;
  if (falloff > 0.0) {
    float k = falloff * (v_world_position.y - fog_info.eye.y);
    density *= abs(k) > 1e-3 ? (1.0 - exp(-k)) / k : 1.0 - 0.5 * k;
  }
  return clamp(exp(-density * ParticleEyeDistance()), 0.0, 1.0);
}

#endif  // PARTICLE_FOG_GLSL_
