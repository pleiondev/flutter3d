#version 460 core

// Cel shading: the diffuse response is quantized into bands and a rim term
// fakes a backlight.
//
// Included because a stylised model stresses the permutation design differently
// from the physical ones — it needs no camera-dependent specular but does need
// the view vector for the rim, so it proves the shared surface interface is
// genuinely model-agnostic.
#include <lib/material_maps.glsl>
#include <lib/shadow.glsl>

float LightVisibility(Surface s, LightSample light, int index) {
  return ShadowFactor(s, light, index);
}

vec3 ShadeLight(Surface s, LightSample light) {
  // Fewer bands as roughness rises, so the slider still does something here.
  float bands = mix(5.0, 2.0, s.roughness);
  // smoothstep on the band edge keeps the step from aliasing into jagged
  // terminator lines.
  float quantized = floor(light.n_dot_l * bands) / bands;
  float fraction = fract(light.n_dot_l * bands);
  quantized += smoothstep(0.85, 1.0, fraction) / bands;

  // AccumulateLights multiplies by N.L, which is exactly what banding is meant
  // to replace, so divide it back out and keep the quantized ramp instead.
  float ramp = quantized / max(light.n_dot_l, 1e-3);

  return s.albedo * ramp;
}

void main() {
  Surface s = ReadSurface();
  ApplyCommonMaps(s);
  // Roughness sets the band count, so the ORM map matters here too.
  ApplyMetallicRoughnessMap(s);

  // The rim is a property of the view, not of any one light, so it belongs
  // outside the loop — adding it per light would make it brighten with the
  // number of lamps in the scene.
  float rim = pow(1.0 - s.n_dot_v, 3.0) * frag_info.material.w;
  vec3 ambient = s.albedo * s.ambient * s.occlusion;

  WriteSurface(
      AccumulateLights(s) * s.occlusion + ambient + vec3(rim * 0.35) +
          s.emissive,
      s.alpha);
}
