#version 460 core

// Pure diffuse. The cheapest model that still reads as three-dimensional, and
// the reference point for judging whether the fancier models are worth their
// cost on a given target.
#include <lib/surface.glsl>

vec3 ShadeLight(Surface s, LightSample light) {
  // The radiance and the N.L factor are applied by AccumulateLights, so the
  // model itself only says how the surface responds.
  return s.albedo;
}

void main() {
  Surface s = ReadSurface();
  vec3 ambient = s.albedo * s.ambient;
  WriteSurface(AccumulateLights(s) + ambient, s.exposure);
}
