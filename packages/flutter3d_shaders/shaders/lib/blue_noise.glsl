// A per-pixel offset for a march or a kernel rotation — `R3`.
//
// **The engine's blue noise while a temporal resolve runs, the fixed 4 × 4
// pattern otherwise.** A march jittered by a pattern that never changes puts
// the same dither on every frame, and the eye finds it; with the resolve on,
// each frame reads the next of 32 slices of blue noise and the history
// averages them into a smooth answer. Off, the pattern is exactly what the
// passes read before, so a frame without the resolve is the frame it was.
//
// The table is `EngineTables.blueNoise`: 32 slices of 64 × 64 in an 8 × 4
// atlas, one byte a texel. Read at texel centres through a nearest sampler.
//
// Include after `lib/frag_coord_info.glsl` or anything else that gives the
// pixel from the top.

#ifndef BLUE_NOISE_GLSL_
#define BLUE_NOISE_GLSL_

uniform sampler2D blue_noise_texture;

uniform NoiseInfo {
  /// x: one to read the blue noise, nought for the pattern. y: this frame's
  /// slice, the frame index modulo 32. zw unused.
  vec4 noise;
}
noise_info;

/// One cell of a 4 × 4 Bayer matrix, in [0, 1).
float BayerCell(vec2 at) {
  int x = int(mod(at.x, 4.0));
  int y = int(mod(at.y, 4.0));
  int index = y * 4 + x;
  float value = 0.0;
  if (index == 0) value = 0.0;
  else if (index == 1) value = 8.0;
  else if (index == 2) value = 2.0;
  else if (index == 3) value = 10.0;
  else if (index == 4) value = 12.0;
  else if (index == 5) value = 4.0;
  else if (index == 6) value = 14.0;
  else if (index == 7) value = 6.0;
  else if (index == 8) value = 3.0;
  else if (index == 9) value = 11.0;
  else if (index == 10) value = 1.0;
  else if (index == 11) value = 9.0;
  else if (index == 12) value = 15.0;
  else if (index == 13) value = 7.0;
  else if (index == 14) value = 13.0;
  else value = 5.0;
  return value / 16.0;
}

/// This frame's blue noise at the pixel [at], in [0, 1).
float BlueNoise(vec2 at) {
  float slice = noise_info.noise.y;
  vec2 cell = mod(floor(at), 64.0);
  vec2 corner = vec2(mod(slice, 8.0), floor(slice / 8.0)) * 64.0;
  vec2 uv = (corner + cell + 0.5) / vec2(512.0, 256.0);
  return textureLod(blue_noise_texture, uv, 0.0).r * (255.0 / 256.0);
}

/// The offset for the pixel [at]: blue noise or the pattern, per `noise.x`.
float PixelNoise(vec2 at) {
  return noise_info.noise.x > 0.5 ? BlueNoise(at) : BayerCell(at);
}

#endif  // BLUE_NOISE_GLSL_
