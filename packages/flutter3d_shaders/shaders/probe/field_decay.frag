#version 460 core

// One step of a decaying field — `H5`'s probe kernel.
//
// The smallest thing `FieldPass` can be held to: every texel becomes itself
// times a factor plus a constant, so after n steps from a known start the
// answer is written down in closed form, and a backend that cannot render
// into a float target, or read one back through a vertex stage, misses it
// by more than rounding.

precision highp float;

uniform sampler2D field_texture;

uniform FieldDecayInfo {
  /// x: the factor each step multiplies by. y: the constant each step adds.
  /// zw unused.
  vec4 params;
}
field_decay;

in vec2 v_uv;

out vec4 frag_color;

void main() {
  // `textureLod` at level zero: a field is a render target with one level,
  // and a sample the compiler cannot prove uniform is refused by WGSL when it
  // asks for an implicit derivative.
  frag_color = textureLod(field_texture, v_uv, 0.0) * field_decay.params.x +
               vec4(field_decay.params.y);
}
