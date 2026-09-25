#version 460 core

// `particle.frag`, faded where it nears the opaque scene — soft particles.
// See `lib/particle_soft.glsl`.

#define F3D_SOFT_PARTICLE
#include <lib/particle.glsl>
