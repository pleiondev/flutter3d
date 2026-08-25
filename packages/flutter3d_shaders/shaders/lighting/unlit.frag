#version 460 core

// Albedo only. Useful as a baseline: whatever this shows is purely texture and
// tint, with no lighting term involved.
// This model has no shadow term, and `LightingModel.unlit` says so with
// `usesMaterialMaps: false` — so the engine binds no `PointShadow` block. The
// header must therefore not declare one: a block declared and unbound is a
// dropped draw on WebGL2 and a phantom bind on Impeller. See surface.glsl.
#define F3D_NO_POINT_SHADOW
#include <lib/surface.glsl>

// Never called — nothing here accumulates lights — but the prototype in
// surface.glsl has to be satisfied, and an unlit surface responding with its
// albedo is the honest answer to "what would this look like lit".
vec3 ShadeLight(Surface s, LightSample light) {
  return s.albedo;
}

// Never called either, and deliberately not routed through shadow.glsl: an
// unlit shader that declared the shadow sampler would lose it to the optimizer
// and leave the engine binding a slot Metal does not have.
float LightVisibility(Surface s, LightSample light, int index) {
  return 1.0;
}

void main() {
  Surface s = ReadSurface();
  // The albedo is already linear, and an unlit surface is best
  // understood as emitting exactly it, so it goes into the HDR
  // target as light like everything else.
  WriteSurface(s.albedo, s.alpha);
}
