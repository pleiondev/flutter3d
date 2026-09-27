#version 460 core

// Particles lit from six directions — `N6`. The body is
// `lib/particle_six_way.glsl`; `particle_six_way_soft.frag` is the same body
// faded against the scene's depth.

#include <lib/particle_six_way.glsl>
