#version 460 core

// `particle_textured.frag`, faded where it nears the opaque scene — soft
// particles. See `lib/particle_soft.glsl`.

#define F3D_SOFT_PARTICLE
#include <lib/particle_textured.glsl>
