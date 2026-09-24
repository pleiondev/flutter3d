#version 460 core

// The surface buffer's depth, reduced to a small grid for the CPU to read
// back — `C3`, `HiZOcclusion` on the other end.
//
// Each texel of this target covers a block of the surface buffer and keeps
// the **farthest** view depth in it, because what the reading is for is
// saying "everything behind this is hidden", and only the farthest surface in
// a block is in front of all of it. A block with a single empty pixel — sky
// through a gap, the edge of the world — is no occluder at all and is written
// with alpha zero.
//
// Written into eight bits a channel, because that is what `readback` hands
// back on every backend: the depth as a 24-bit fraction of the far plane in
// red, green and blue, most significant first, rounded *up* so the reading is
// never nearer than the surface. Arithmetic rather than bit operations, which
// the OpenGL ES target does not have.
precision highp float;

in vec2 v_uv;

out vec4 frag_color;

/// The surface buffer: view depth in metres in alpha, zero where nothing was
/// drawn.
uniform sampler2D surface_texture;

uniform DepthPyramidInfo {
  /// x, y: one texel of this target, in uv — the block each texel reduces.
  /// z, w: how many surface texels that block spans, across and down.
  vec4 block;
  /// x: one over the far plane, which the depth is written as a fraction of.
  /// y, z, w: unused.
  vec4 range;
}
pyramid_info;

void main() {
  vec2 blockUv = pyramid_info.block.xy;
  // One tap a source texel up to sixteen across, then spread: a bound a
  // uniform cannot lengthen, for the reason `ssao_blur.frag` keeps one.
  float tapsX = clamp(ceil(pyramid_info.block.z - 1e-3), 1.0, 16.0);
  float tapsY = clamp(ceil(pyramid_info.block.w - 1e-3), 1.0, 16.0);
  vec2 corner = v_uv - 0.5 * blockUv;
  vec2 stepUv = blockUv / vec2(tapsX, tapsY);

  float farthest = 0.0;
  float empty = 0.0;
  for (int j = 0; j < 16; j++) {
    if (float(j) >= tapsY) break;
    for (int i = 0; i < 16; i++) {
      if (float(i) >= tapsX) break;
      vec2 at = corner + (vec2(float(i), float(j)) + 0.5) * stepUv;
      float depth = textureLod(surface_texture, at, 0.0).a;
      empty = depth > 0.0 ? empty : 1.0;
      farthest = max(farthest, depth);
    }
  }

  float steps = 16777215.0;
  float scaled = ceil(clamp(farthest * pyramid_info.range.x, 0.0, 1.0) * steps);
  float high = floor(scaled / 65536.0);
  float rest = scaled - high * 65536.0;
  float middle = floor(rest / 256.0);
  float low = rest - middle * 256.0;
  frag_color = vec4(high / 255.0, middle / 255.0, low / 255.0,
                    empty > 0.0 ? 0.0 : 1.0);
}
