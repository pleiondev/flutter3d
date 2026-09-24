#version 460 core

// One level of the copy of the scene that transmissive draws read — `M3`.
//
// Drawn once per level into its own rectangle of one texture: the base at
// the scene's size, and each level after it half the one before, side by
// side — see `SceneColourChain`. Every level is taken from the scene itself
// rather than from the level above it, because a pass cannot read the
// texture it draws into, and one texture is what the lit stage has a
// sampler left for.
//
// A texel of level k is the mean of the 2^k by 2^k block of the scene under
// it: (2^(k-1))² bilinear taps, each on the corner between four texels and so
// the mean of those four. Level zero takes one tap on a texel's centre, which
// is the texel. The work is about a quarter of the scene's texels a level,
// whatever the level.
precision highp float;

in vec2 v_uv;

out vec4 frag_color;

uniform sampler2D source_texture;

uniform SceneCopyInfo {
  /// x: the taps along each side, a power of two up to sixteen. y, z: one
  /// over the scene's width and height. w: unused.
  vec4 params;
}
copy_info;

void main() {
  float taps = copy_info.params.x;
  vec2 texel = copy_info.params.yz;
  // Offsets of 1 - n, 3 - n, … n - 1 texels: every corner inside the block.
  float first = 1.0 - taps;
  vec3 sum = vec3(0.0);
  for (int j = 0; j < 16; j++) {
    if (float(j) >= taps) break;
    for (int i = 0; i < 16; i++) {
      if (float(i) >= taps) break;
      vec2 offset =
          vec2(first + 2.0 * float(i), first + 2.0 * float(j)) * texel;
      sum += textureLod(source_texture, v_uv + offset, 0.0).rgb;
    }
  }
  frag_color = vec4(sum / (taps * taps), 1.0);
}
