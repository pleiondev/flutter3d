#version 460 core

// Metal-rough physically based shading: Cook-Torrance specular with the GGX
// distribution, height-correlated Smith visibility and a Schlick Fresnel.
// Formulations follow Filament, which is also what the glTF spec describes, so
// imported glTF materials will land on the same look.
//
// There is no image-based lighting here: a prefiltered environment needs mip
// levels, and flutter_gpu on the stable channel exposes none. The ambient term
// below is a flat stand-in, which is exactly the gap IBL would fill.
#include <lib/material_maps.glsl>

float D_GGX(float n_dot_h, float alpha) {
  float a = n_dot_h * alpha;
  float k = alpha / max(1.0 - n_dot_h * n_dot_h + a * a, 1e-6);
  return k * k * (1.0 / kPi);
}

float V_SmithGGXCorrelated(float n_dot_v, float n_dot_l, float alpha) {
  float a2 = alpha * alpha;
  float lambda_v = n_dot_l * sqrt(n_dot_v * n_dot_v * (1.0 - a2) + a2);
  float lambda_l = n_dot_v * sqrt(n_dot_l * n_dot_l * (1.0 - a2) + a2);
  return 0.5 / max(lambda_v + lambda_l, 1e-5);
}

vec3 F_Schlick(vec3 f0, float v_dot_h) {
  float f = pow(1.0 - v_dot_h, 5.0);
  return f0 + (vec3(1.0) - f0) * f;
}

vec3 ShadeLight(Surface s, LightSample light) {
  // Perceptual roughness is squared to get the GGX alpha; this is what makes
  // the roughness slider feel linear.
  float alpha = s.roughness * s.roughness;

  // Dielectrics reflect ~4% at normal incidence; metals tint the reflection
  // with their own albedo and have no diffuse response.
  vec3 f0 = mix(vec3(0.04), s.albedo, s.metallic);
  vec3 diffuseColor = s.albedo * (1.0 - s.metallic);

  float d = D_GGX(light.n_dot_h, alpha);
  float vis = V_SmithGGXCorrelated(s.n_dot_v, light.n_dot_l, alpha);
  vec3 f = F_Schlick(f0, light.v_dot_h);

  vec3 specular = d * vis * f * frag_info.material.w;
  // Energy left over after reflection is what scatters diffusely.
  vec3 diffuse = diffuseColor * (vec3(1.0) - f) / kPi;

  // The pi puts the result back on the scale the tone mapper and the exposure
  // default were calibrated against.
  return (diffuse + specular) * kPi;
}

void main() {
  Surface s = ReadSurface();
  ApplyCommonMaps(s);
  ApplyMetallicRoughnessMap(s);

  vec3 diffuseColor = s.albedo * (1.0 - clamp(s.metallic, 0.0, 1.0));
  // Ambient occlusion darkens indirect light. It is applied to the direct term
  // too, which is not physical, but with no IBL the flat ambient is far too
  // weak for an occlusion map to be visible otherwise.
  vec3 ambient = diffuseColor * s.ambient * s.occlusion;

  WriteSurface(
      AccumulateLights(s) * s.occlusion + ambient + s.emissive,
      s.exposure,
      s.alpha);
}
