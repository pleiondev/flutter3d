#version 460 core

// First step of the bloom chain: keep what is brighter than the threshold, at
// half resolution.
//
// The downsample and the threshold are one pass because the threshold has to
// happen *before* the blur — thresholding blurred pixels would spread the
// dimmer parts of a highlight into the bloom as well — and doing it while
// already reading four texels costs nothing extra.
precision highp float;

in vec2 v_uv;

out vec4 frag_color;

uniform sampler2D source_texture;

uniform BloomInfo {
  /// x: 1/width, y: 1/height of the SOURCE texture. z: threshold. w: knee.
  vec4 params;
}
bloom_info;

/// Rec. 709 luma, which is what "how bright does this look" means.
float Luminance(vec3 color) {
  return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

void main() {
  vec2 texel = bloom_info.params.xy;

  // A four-tap box at the corners of the source pixel quad: a plain single tap
  // would alias a one-pixel specular highlight in and out of existence as the
  // camera moves, which reads as flickering rather than as bloom.
  //
  // **Weighted by Karis's `1 / (1 + luma)`**, as Jimenez's Call of Duty chain
  // does on its first step down and nowhere after. A plain average lets one
  // texel of a glossy floor's highlight, a hundred times brighter than its
  // neighbours, own the whole quad, and it flickers as it crosses texels —
  // "fireflies". The weight takes the energy of a lone outlier down to about
  // its neighbours' and leaves a uniformly bright quad an exact average.
  vec3 s0 = texture(source_texture, v_uv + texel * vec2(-0.5, -0.5)).rgb;
  vec3 s1 = texture(source_texture, v_uv + texel * vec2(0.5, -0.5)).rgb;
  vec3 s2 = texture(source_texture, v_uv + texel * vec2(-0.5, 0.5)).rgb;
  vec3 s3 = texture(source_texture, v_uv + texel * vec2(0.5, 0.5)).rgb;
  float w0 = 1.0 / (1.0 + Luminance(s0));
  float w1 = 1.0 / (1.0 + Luminance(s1));
  float w2 = 1.0 / (1.0 + Luminance(s2));
  float w3 = 1.0 / (1.0 + Luminance(s3));
  vec3 color = (s0 * w0 + s1 * w1 + s2 * w2 + s3 * w3) / (w0 + w1 + w2 + w3);

  float threshold = bloom_info.params.z;
  float knee = max(bloom_info.params.w, 1e-4);

  // A soft knee rather than a hard step: a hard cut makes the bloom appear and
  // disappear along a visible contour as a highlight brightens through the
  // threshold.
  float brightness = Luminance(color);
  float soft = clamp(brightness - threshold + knee, 0.0, 2.0 * knee);
  soft = soft * soft / (4.0 * knee);
  float contribution =
      max(soft, brightness - threshold) / max(brightness, 1e-4);

  frag_color = vec4(color * contribution, 1.0);
}
