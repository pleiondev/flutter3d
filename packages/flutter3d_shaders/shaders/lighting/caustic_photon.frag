#version 460 core

// A photon's quad, added into the sun's atlas — `ShadowSettings.caustics`.
//
// The atlas's green and blue hold what was taken from red and green, and
// its alpha what was left of blue (`shadow_transmittance.frag`). The pass
// blends colour as destination minus source and alpha as destination plus
// source, so this gives back light: red comes in as nought and the depth in
// it is untouched.
//
// The falloff is (1 − r²)², whose integral over the quad is π/3 of its area;
// the vertex stage has already divided by that, so photons spread evenly add
// up to the light that fell on them.

precision highp float;

in vec4 v_color;
in vec2 v_uv;

out vec4 frag_color;

void main() {
  float r2 = dot(v_uv, v_uv);
  if (r2 >= 1.0) discard;
  float k = (1.0 - r2) * (1.0 - r2);
  vec3 e = v_color.rgb * k;
  frag_color = vec4(0.0, e.r, e.g, e.b);
}
