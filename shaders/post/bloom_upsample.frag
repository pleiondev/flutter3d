#version 460 core

// Doubles the resolution with a 3x3 tent filter, for the way back up the chain.
//
// The tent is what turns a stack of box-filtered halvings into something that
// looks like a Gaussian: each level is upsampled and added to the one above, so
// the widest level contributes the broad glow and the narrowest the tight core.
// A plain bilinear upsample instead leaves visible blocky steps where the
// levels meet.
precision highp float;

in vec2 v_uv;

out vec4 frag_color;

uniform sampler2D source_texture;

uniform BloomInfo {
  /// x: 1/width, y: 1/height of the SOURCE texture. z: filter radius in source
  /// texels. w unused.
  vec4 params;
}
bloom_info;

void main() {
  vec2 t = bloom_info.params.xy * max(bloom_info.params.z, 0.0);

  vec3 a = texture(source_texture, v_uv + vec2(-1.0, 1.0) * t).rgb;
  vec3 b = texture(source_texture, v_uv + vec2(0.0, 1.0) * t).rgb;
  vec3 c = texture(source_texture, v_uv + vec2(1.0, 1.0) * t).rgb;
  vec3 d = texture(source_texture, v_uv + vec2(-1.0, 0.0) * t).rgb;
  vec3 e = texture(source_texture, v_uv).rgb;
  vec3 f = texture(source_texture, v_uv + vec2(1.0, 0.0) * t).rgb;
  vec3 g = texture(source_texture, v_uv + vec2(-1.0, -1.0) * t).rgb;
  vec3 h = texture(source_texture, v_uv + vec2(0.0, -1.0) * t).rgb;
  vec3 i = texture(source_texture, v_uv + vec2(1.0, -1.0) * t).rgb;

  // 1 2 1 / 2 4 2 / 1 2 1, over sixteen.
  vec3 result = e * 4.0 + (b + d + f + h) * 2.0 + (a + c + g + i);
  frag_color = vec4(result * (1.0 / 16.0), 1.0);
}
