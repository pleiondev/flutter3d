#version 460 core

// Pure diffuse. The cheapest model that still reads as three-dimensional, and
// the reference point for judging whether the fancier models are worth their
// cost on a given target.
#include <lib/surface.glsl>

void main() {
  Surface s = ReadSurface();

  vec3 diffuse = s.albedo * s.light * s.n_dot_l;
  vec3 ambient = s.albedo * s.ambient;

  WriteSurface(diffuse + ambient, s.exposure);
}
