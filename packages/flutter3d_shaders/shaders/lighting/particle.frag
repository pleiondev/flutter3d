#version 460 core

// Particles, as a procedural round sprite. The body, and why it has no
// sampler, is `lib/particle.glsl`; `particle_soft.frag` is the same body
// faded against the scene's depth.

#include <lib/particle.glsl>
