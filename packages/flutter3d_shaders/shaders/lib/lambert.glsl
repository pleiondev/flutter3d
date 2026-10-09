// The `Lambert` lighting model, for `lighting/lambert.frag` and its opaque variant
// `lighting/lambert_opaque.frag` — `A1.2`. A header rather than the stage itself
// so both stages are this text: the opaque one defines `F3D_OPAQUE` first,
// which takes the alpha cut's `discard` out of `ReadSurface`.

#ifndef LAMBERT_GLSL_
#define LAMBERT_GLSL_

// Pure diffuse. The cheapest model that still reads as three-dimensional, and
// the reference point for judging whether the fancier models are worth their
// cost on a given target.
#include <lib/material_maps.glsl>
#include <lib/shadow.glsl>

float LightVisibility(Surface s, LightSample light, int index) {
  return ShadowFactor(s, light, index);
}

vec3 ShadeLight(Surface s, LightSample light) {
  // The radiance and the N.L factor are applied by AccumulateLights, so the
  // model itself only says how the surface responds.
  return s.albedo;
}

void main() {
  Surface s = ReadSurface();
  // No ORM map: a purely diffuse model has no response to metallic or
  // roughness, so sampling it would leave a slot the compiler then drops.
  ApplyCommonMaps(s);
  vec3 ambient = s.albedo * (s.ambient + SampleLightmap()) * s.occlusion;
  vec3 lit = AccumulateLights(s) * s.occlusion + ambient + s.emissive;
  if (WriteDebugView(s, lit)) return;
  WriteSurface(lit, s.alpha, s.roughness);
}

#endif  // LAMBERT_GLSL_
