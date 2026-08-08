#version 460 core

// Blinn-Phong: diffuse plus a half-vector specular lobe.
//
// Not energy conserving and not physically based, but it is what most older
// engines shipped, and it stays useful for stylised looks where a controllable
// highlight matters more than correctness.
#include <lib/surface.glsl>

void main() {
  Surface s = ReadSurface();

  // Map perceptual roughness onto a Phong exponent. The mapping is arbitrary;
  // it just has to feel monotonic as the roughness slider moves.
  float shininess = mix(256.0, 4.0, s.roughness);
  float specular = pow(s.n_dot_h, shininess) * frag_info.material.w;

  // Gate the highlight by N.L so it cannot appear on unlit facing-away parts.
  specular *= step(0.0001, s.n_dot_l);

  vec3 diffuse = s.albedo * s.light * s.n_dot_l;
  vec3 ambient = s.albedo * s.ambient;

  WriteSurface(diffuse + ambient + s.light * specular, s.exposure);
}
