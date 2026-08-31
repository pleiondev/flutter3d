#version 460 core

// Halves the resolution with a 13-tap filter.
//
// The kernel is the one from Jimenez's "Next Generation Post Processing in Call
// of Duty: Advanced Warfare": four 2x2 boxes at the corners plus one at the
// centre, weighted so the result is stable. It exists because the obvious
// bilinear halving pulses badly when a bright pixel crosses a texel boundary,
// and a bloom that pulses is worse than no bloom.
//
// Halving repeatedly is how the wide blur is built. flutter_gpu has no mip
// levels at all — no `mipCount` on `Texture`, no render-to-mip-level — so a
// mip pyramid is not available and the chain is a series of separate textures
// instead. That is the whole reason this file exists rather than a
// `textureLod` call.
precision highp float;

in vec2 v_uv;

out vec4 frag_color;

uniform sampler2D source_texture;

uniform BloomInfo {
  /// x: 1/width, y: 1/height of the SOURCE texture. z and w unused here.
  vec4 params;
}
bloom_info;

void main() {
  vec2 t = bloom_info.params.xy;

  vec3 a = texture(source_texture, v_uv + vec2(-2.0, 2.0) * t).rgb;
  vec3 b = texture(source_texture, v_uv + vec2(0.0, 2.0) * t).rgb;
  vec3 c = texture(source_texture, v_uv + vec2(2.0, 2.0) * t).rgb;
  vec3 d = texture(source_texture, v_uv + vec2(-2.0, 0.0) * t).rgb;
  vec3 e = texture(source_texture, v_uv).rgb;
  vec3 f = texture(source_texture, v_uv + vec2(2.0, 0.0) * t).rgb;
  vec3 g = texture(source_texture, v_uv + vec2(-2.0, -2.0) * t).rgb;
  vec3 h = texture(source_texture, v_uv + vec2(0.0, -2.0) * t).rgb;
  vec3 i = texture(source_texture, v_uv + vec2(2.0, -2.0) * t).rgb;

  vec3 j = texture(source_texture, v_uv + vec2(-1.0, 1.0) * t).rgb;
  vec3 k = texture(source_texture, v_uv + vec2(1.0, 1.0) * t).rgb;
  vec3 l = texture(source_texture, v_uv + vec2(-1.0, -1.0) * t).rgb;
  vec3 m = texture(source_texture, v_uv + vec2(1.0, -1.0) * t).rgb;

  // The inner four boxes carry half the weight between them; the five outer
  // ones share the rest.
  vec3 result = (j + k + l + m) * 0.5 * 0.25;
  result += (a + b + d + e) * 0.125 * 0.25;
  result += (b + c + e + f) * 0.125 * 0.25;
  result += (d + e + g + h) * 0.125 * 0.25;
  result += (e + f + h + i) * 0.125 * 0.25;

  frag_color = vec4(result, 1.0);
}
