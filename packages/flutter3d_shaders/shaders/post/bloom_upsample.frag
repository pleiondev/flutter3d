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
  /// texels. w: unused.
  vec4 params;
  /// rgb: what this step multiplies the level it carries up by — the ratio of
  /// this level's weight and warmth to the one above's. w: unused.
  vec4 tint;
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
  result *= (1.0 / 16.0);

  // **Halation: the wide part of the glow goes red — `gfx-30n`.** On film the
  // halo around a highlight is warm, because light that made it through the
  // emulsion scatters off the backing and comes back, and the red layer sits
  // deepest so it catches the most of it. The same asymmetry is what stops a
  // digital bloom reading as a grey smear.
  //
  // Applied here rather than in the composite because here is where the
  // *levels* are: the caller hands each level its own amount, so the tight
  // core stays neutral and only the broad skirt warms. The composite sees one
  // glow and could not tell them apart.
  //
  // **A ratio, not the warmth itself.** On the way up this level already
  // holds every level below it, so multiplying it by its own warmth warmed
  // the narrower levels again at every step and the factors compounded. The
  // caller hands the ratio between this level's weight and the one above's,
  // and the product down the chain is each level's own, once. With no
  // halation and a scatter of one it is one on every channel, which keeps
  // every recorded frame where it is.
  result *= bloom_info.tint.rgb;

  frag_color = vec4(result, 1.0);
}
