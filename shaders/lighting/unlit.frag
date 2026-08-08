#version 460 core

// Albedo only. Useful as a baseline: whatever this shows is purely texture and
// tint, with no lighting term involved.
#include <lib/surface.glsl>

// Never called — nothing here accumulates lights — but the prototype in
// surface.glsl has to be satisfied, and an unlit surface responding with its
// albedo is the honest answer to "what would this look like lit".
vec3 ShadeLight(Surface s, LightSample light) {
  return s.albedo;
}

void main() {
  Surface s = ReadSurface();
  WriteDisplayColor(s.albedo, s.alpha);
}
