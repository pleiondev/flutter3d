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
// Alpha also carries the block's **nearest** depth, as a fraction of the
// farthest: 128 + 127 × nearest / farthest, rounded down, so a block is
// never read as flatter than it is. A post in front of a doorway is one such
// block: the reading moves it as one plane at the doorway's depth, and the
// CPU needs the post's depth to know how far the two part when the camera
// moves — `HiZOcclusion.prepare` drops the block once they part by more
// than a fraction of a cell. Alpha below one half still means "not drawn".
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
  // One tap a source texel up to thirty-two across, then spread: a bound a
  // uniform cannot lengthen, for the reason `ssao_blur.frag` keeps one. Not
  // sixteen: a phone held upright is over 2 048 pixels tall, a block of it
  // is then more than sixteen rows, and a row no tap lands on is a gap of
  // sky or a far wall the reading would cover over.
  float tapsX = clamp(ceil(pyramid_info.block.z - 1e-3), 1.0, 32.0);
  float tapsY = clamp(ceil(pyramid_info.block.w - 1e-3), 1.0, 32.0);
  vec2 corner = v_uv - 0.5 * blockUv;
  vec2 stepUv = blockUv / vec2(tapsX, tapsY);

  float farthest = 0.0;
  float nearest = 3.0e38;
  float empty = 0.0;
  for (int j = 0; j < 32; j++) {
    if (float(j) >= tapsY) break;
    for (int i = 0; i < 32; i++) {
      if (float(i) >= tapsX) break;
      vec2 at = corner + (vec2(float(i), float(j)) + 0.5) * stepUv;
      float depth = textureLod(surface_texture, at, 0.0).a;
      empty = depth > 0.0 ? empty : 1.0;
      farthest = max(farthest, depth);
      nearest = min(nearest, depth);
    }
  }

  float steps = 16777215.0;
  float scaled = ceil(clamp(farthest * pyramid_info.range.x, 0.0, 1.0) * steps);
  float high = floor(scaled / 65536.0);
  float rest = scaled - high * 65536.0;
  float middle = floor(rest / 256.0);
  float low = rest - middle * 256.0;
  // A thousandth of a step up before the floor, so a block at one depth is
  // 255 on a GPU whose division lands an ulp short of one.
  float ratio = farthest > 0.0 ? clamp(nearest / farthest, 0.0, 1.0) : 0.0;
  float flatness = 128.0 + floor(ratio * 127.0 + 1e-3);
  frag_color = vec4(high / 255.0, middle / 255.0, low / 255.0,
                    empty > 0.0 ? 0.0 : flatness / 255.0);
}
