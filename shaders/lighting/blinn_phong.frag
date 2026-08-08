#version 460 core

// Blinn-Phong: diffuse plus a half-vector specular lobe.
//
// Not energy conserving and not physically based, but it is what most older
// engines shipped, and it stays useful for stylised looks where a controllable
// highlight matters more than correctness.
#include <lib/surface.glsl>

vec3 ShadeLight(Surface s, LightSample light) {
  // Map perceptual roughness onto a Phong exponent. The mapping is arbitrary;
  // it just has to feel monotonic as the roughness slider moves.
  float shininess = mix(256.0, 4.0, s.roughness);
  float specular = pow(light.n_dot_h, shininess) * frag_info.material.w;

  // The caller already dropped lights with N.L at zero, so no separate gate is
  // needed to keep the highlight off facing-away geometry.
  return s.albedo + vec3(specular);
}

void main() {
  Surface s = ReadSurface();
  vec3 ambient = s.albedo * s.ambient;
  WriteSurface(AccumulateLights(s) + ambient, s.exposure);
}
