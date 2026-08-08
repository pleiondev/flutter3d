#version 460 core

// Cel shading: the diffuse response is quantized into bands and a rim term
// fakes a backlight.
//
// Included because a stylised model stresses the permutation design differently
// from the physical ones — it needs no camera-dependent specular but does need
// the view vector for the rim, so it proves the shared surface interface is
// genuinely model-agnostic.
#include <lib/surface.glsl>

void main() {
  Surface s = ReadSurface();

  // Fewer bands as roughness rises, so the slider still does something here.
  float bands = mix(5.0, 2.0, s.roughness);
  // smoothstep on the band edge keeps the step from aliasing into jagged
  // terminator lines.
  float quantized = floor(s.n_dot_l * bands) / bands;
  float fraction = fract(s.n_dot_l * bands);
  quantized += smoothstep(0.85, 1.0, fraction) / bands;

  float rim = pow(1.0 - s.n_dot_v, 3.0) * frag_info.material.w;

  vec3 shaded = s.albedo * (s.ambient + quantized) * s.light;
  WriteSurface(shaded + s.light * rim * 0.35, s.exposure);
}
