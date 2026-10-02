#version 460 core

// SMAA 1x, first of three passes — `P1`: where the luma steps.
//
// Red marks a step across a pixel's left side, green across its top. The
// other two passes read nothing else, so this is where the method decides
// what an edge is: a step of at least `params.z` in luma, and not much
// smaller than the largest step beside it. That second test is what keeps
// SMAA off the inside of a high-contrast texture, which FXAA would smooth as
// though it were a staircase.
//
// `flutter3d_cpu`'s `SmaaEdgesShader` is this, line for line.
precision highp float;

in vec2 v_uv;

out vec4 frag_color;

/// The finished picture, tone mapped and encoded.
uniform sampler2D source_texture;

uniform SmaaInfo {
  /// x, y: one texel. z: the smallest luma step that is an edge. w: how
  /// many times smaller than the largest step beside it a step may be and
  /// still count.
  vec4 params;
}
smaa_info;

/// Rec. 709 weights on the encoded picture.
float Luma(vec2 at) {
  vec3 c = textureLod(source_texture, at, 0.0).rgb;
  return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void main() {
  vec2 texel = smaa_info.params.xy;
  float middle = Luma(v_uv);
  float left = Luma(v_uv + vec2(-texel.x, 0.0));
  float top = Luma(v_uv + vec2(0.0, -texel.y));
  vec2 delta = abs(vec2(middle - left, middle - top));
  vec2 edges = step(vec2(smaa_info.params.z), delta);
  if (edges.x + edges.y == 0.0) {
    frag_color = vec4(0.0);
    return;
  }

  float right = abs(middle - Luma(v_uv + vec2(texel.x, 0.0)));
  float bottom = abs(middle - Luma(v_uv + vec2(0.0, texel.y)));
  float leftLeft = abs(left - Luma(v_uv + vec2(-2.0 * texel.x, 0.0)));
  float topTop = abs(top - Luma(v_uv + vec2(0.0, -2.0 * texel.y)));
  float largest = max(max(max(delta.x, delta.y), max(right, bottom)),
                      max(leftLeft, topTop));
  edges *= step(vec2(largest), smaa_info.params.w * delta);
  frag_color = vec4(edges, 0.0, 0.0);
}
