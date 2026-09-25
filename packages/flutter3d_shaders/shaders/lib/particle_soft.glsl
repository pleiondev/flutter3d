// Soft particles: a sprite that fades as it nears the opaque scene behind it.
//
// **What this removes is a seam.** A particle is a flat quad, depth-tested and
// never depth-written, so where it passes through a floor or a wall the test
// cuts it along the line the two planes meet — a hard straight edge across a
// puff of smoke that has no edges anywhere else. Lorach's fix ("Soft
// Particles", 2007) scales the particle by how far the scene lies behind it:
//
//   fade = saturate((sceneDepth - particleDepth) / softness)
//
// so a fragment a softness or more in front of the scene is untouched, one
// touching it is gone, and the line becomes a ramp.
//
// Included by every particle stage, and empty unless the stage defines
// `F3D_SOFT_PARTICLE`: the soft stages are stages of their own, picked only by
// a contributor that was handed the scene's depth, so the ones every recorded
// frame goes through declare nothing new — no sampler to leave unbound, which
// on Metal is a native crash.

#ifndef PARTICLE_SOFT_GLSL_
#define PARTICLE_SOFT_GLSL_

#ifdef F3D_SOFT_PARTICLE

#include <lib/frag_coord.glsl>

/// The surface buffer: in `a`, the opaque scene's depth along the view axis,
/// in metres, and zero where nothing was drawn. Read with nearest filtering.
uniform sampler2D scene_depth_texture;

uniform SoftParticleInfo {
  /// xy: one over the target's size. z: the target's height where its row
  /// zero is the bottom, nought where it is the top — see `FragCoordFromTop`.
  /// w: one over the softness, in metres.
  vec4 target;

  /// xyz: the camera position in world space.
  vec4 eye;

  /// xyz: the direction the camera looks, a unit vector — the axis the
  /// surface buffer measures its depths along.
  vec4 forward;
}
soft_particle_info;

/// How much of a particle fragment at [world] is left once it nears the
/// scene: one a softness in front of it or further, nought at it.
///
/// One where nothing was drawn behind — the sky is infinitely far — and a
/// select rather than an early return, which a phi of constants would make
/// SPIRV-Cross refuse. `textureLod` for WGSL, which will not take an implicit
/// level where the caller's control flow may not be uniform.
float SoftParticleFade(vec3 world) {
  vec2 uv = FragCoordFromTop(soft_particle_info.target.z) *
            soft_particle_info.target.xy;
  float stored = textureLod(scene_depth_texture, uv, 0.0).a;
  float depth = dot(world - soft_particle_info.eye.xyz,
                    soft_particle_info.forward.xyz);
  float fade =
      clamp((stored - depth) * soft_particle_info.target.w, 0.0, 1.0);
  return stored > 0.0 ? fade : 1.0;
}

#endif  // F3D_SOFT_PARTICLE

#endif  // PARTICLE_SOFT_GLSL_
