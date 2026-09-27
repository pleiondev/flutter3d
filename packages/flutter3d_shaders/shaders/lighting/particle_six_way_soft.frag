#version 460 core

// `particle_six_way.frag`, faded where it nears the opaque scene — soft
// particles, and the case they matter most for: smoke resting on the ground.
// See `lib/particle_soft.glsl`.

#define F3D_SOFT_PARTICLE
#include <lib/particle_six_way.glsl>
