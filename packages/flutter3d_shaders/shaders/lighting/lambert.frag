#version 460 core

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
  WriteSurface(
      AccumulateLights(s) * s.occlusion + ambient + s.emissive,
      s.alpha,
      s.roughness);
}
