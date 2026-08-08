#version 460 core

// The last pass: add the bloom, tone map, encode to sRGB.
//
// Tone mapping lives here rather than in each lighting model, which is the
// point of having an HDR target at all. Applying it per model meant every
// shader wrote display-referred colour into an 8-bit buffer, so anything above
// display white was gone before post-processing could see it — and bloom is
// entirely a function of what is above display white.
precision highp float;

in vec2 v_uv;

out vec4 frag_color;

/// The scene, linear and unbounded.
uniform sampler2D scene_texture;

/// The bloom chain's top level, or a black texture when bloom is off.
uniform sampler2D bloom_texture;

uniform CompositeInfo {
  /// x: exposure, y: bloom intensity, z: 1 to tone map, w unused.
  vec4 params;
}
composite_info;

vec3 LinearToSrgb(vec3 linear) {
  return mix(
      linear * 12.92,
      1.055 * pow(max(linear, vec3(0.0)), vec3(1.0 / 2.4)) - vec3(0.055),
      step(vec3(0.0031308), linear));
}

/// Khronos PBR Neutral tone mapper.
///
/// The mapper the glTF ecosystem settled on, which matters because the renderer
/// targets glTF materials — the same asset should not look different here than
/// in a reference viewer. It leaves everything below the compression threshold
/// untouched, so midtones keep their values and only highlights roll off. That
/// is the property a filmic curve like ACES lacks: ACES would darken the whole
/// image to tame one highlight.
vec3 TonemapNeutral(vec3 color) {
  const float kStartCompression = 0.8 - 0.04;
  const float kDesaturation = 0.15;

  float minChannel = min(color.r, min(color.g, color.b));
  float offset =
      minChannel < 0.08 ? minChannel - 6.25 * minChannel * minChannel : 0.04;
  color -= offset;

  float peak = max(color.r, max(color.g, color.b));
  if (peak < kStartCompression) return color;

  const float d = 1.0 - kStartCompression;
  float newPeak = 1.0 - d * d / (peak + d - kStartCompression);
  color *= newPeak / peak;

  float desaturate = 1.0 - 1.0 / (kDesaturation * (peak - newPeak) + 1.0);
  return mix(color, vec3(newPeak), desaturate);
}

void main() {
  vec4 scene = texture(scene_texture, v_uv);
  vec3 bloom = texture(bloom_texture, v_uv).rgb;

  // Additive, because bloom is light that scattered inside the lens rather than
  // a filter over the image: it adds to what is already there.
  vec3 color = scene.rgb + bloom * composite_info.params.y;

  // Exposure before the tone map, so it behaves like a camera stop — it moves
  // which part of the scene's range lands in the mapper's shoulder instead of
  // stretching an already-compressed image.
  color *= max(composite_info.params.x, 0.0);

  if (composite_info.params.z > 0.5) color = TonemapNeutral(color);

  frag_color = vec4(LinearToSrgb(color), scene.a);
}
