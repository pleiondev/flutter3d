#version 460 core

// The three well-exposedness weights, blurred wide along one axis — `R7`.
//
// Run twice, across and then down. Wide, because an exposure that changed
// from one texel to the next would be a halo round every edge: the weights
// are what fusion blends through its pyramid, and a blur this wide at an
// eighth of the frame stands in for the coarse levels of it. The second run
// turns the weights into the exposure itself, in stops: each exposure's
// shift weighted by how well it shows the place.

in vec2 v_uv;

out vec4 frag_color;

uniform sampler2D weight_texture;

uniform LocalExposureBlurInfo {
  /// xy: one step of the blur, in texture coordinates. z: one on the second
  /// run, which writes the exposure rather than the weights. w unused.
  vec4 step;
  /// x: the shadow exposure's lift in stops, y: the highlight's pull. zw
  /// unused.
  vec4 stops;
}
blur_info;

void main() {
  vec3 sum = vec3(0.0);
  float total = 0.0;
  for (int i = -6; i <= 6; i++) {
    float w = exp(-float(i * i) / 18.0);
    sum += texture(weight_texture, v_uv + blur_info.step.xy * float(i)).rgb * w;
    total += w;
  }
  vec3 weights = sum / total;
  float stops = (weights.x * blur_info.stops.x - weights.z * blur_info.stops.y) /
                max(weights.x + weights.y + weights.z, 1e-6);
  frag_color = blur_info.step.z > 0.5 ? vec4(stops, stops, stops, 1.0)
                                      : vec4(weights, 1.0);
}
