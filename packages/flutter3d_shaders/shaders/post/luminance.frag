#version 460 core

// The scene's brightness at low resolution, for the exposure meter to read
// back.
//
// Drawn into a small target — 64×64 — so a readback of it is a few kilobytes
// rather than a frame, and encoded as **log luminance in eight bits**: linear
// values would spend most of the byte on the top stop and nothing on the
// shadows, and an exposure is a stops question. Each texel averages sixteen
// taps across its own footprint of the scene, so the estimate is the mean of
// what it covers rather than one point in it.
//
// What comes out is a picture only in the sense that a histogram is: nothing
// reads it as an image, so which way up it lands is nobody's concern — the
// meter counts texels. See `ExposureMeter` for the other end of the encoding.
precision highp float;

in vec2 v_uv;

out vec4 frag_color;

/// The lit scene, linear and unbounded.
uniform sampler2D scene_texture;

uniform LuminanceInfo {
  /// x, y: one texel of *this* target, in uv — the footprint each texel
  /// averages over. z: the stop the encoding starts at. w: one over how many
  /// stops the byte spans.
  vec4 params;
}
luminance_info;

/// Rec. 709 luma, the same weights the composite uses.
float Luma(vec3 color) { return dot(color, vec3(0.2126, 0.7152, 0.0722)); }

void main() {
  vec2 footprint = luminance_info.params.xy;
  float sum = 0.0;
  for (int j = 0; j < 4; j++) {
    for (int i = 0; i < 4; i++) {
      // Four by four, centred: from three eighths of a texel before the
      // middle to three eighths after it.
      vec2 offset = ((vec2(float(i), float(j)) + 0.5) / 4.0 - 0.5) * footprint;
      sum += Luma(texture(scene_texture, v_uv + offset).rgb);
    }
  }
  float mean = sum / 16.0;
  // A floor well below anything a scene lights, so black encodes as the first
  // stop rather than as minus infinity.
  float stops = log2(max(mean, 1e-6));
  float encoded =
      clamp((stops - luminance_info.params.z) * luminance_info.params.w, 0.0, 1.0);
  frag_color = vec4(encoded, encoded, encoded, 1.0);
}
