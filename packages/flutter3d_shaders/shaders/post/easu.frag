#version 460 core

// Edge-adaptive spatial upscale for the path without a temporal resolve —
// `R5`.
//
// When `renderScale` is below one and nothing reconstructs the frame over
// time, the scene is drawn small and this brings the finished, tone-mapped
// picture up to the size that was asked for. Twelve taps around the output
// pixel's position in the source: the luma gradient over the four nearest
// says which way an edge runs and how sharply, and each tap is weighted by an
// approximation of Lanczos-2 stretched along that edge and narrowed across
// it, so an edge stays an edge where a bilinear upscale would blur it. The
// result is held between the four nearest taps, which is what keeps the
// lobes from ringing.
//
// After the tone map, never before: in HDR a highlight is so far above its
// neighbours that the negative lobe rings around it however it is clamped.
// The grain the composite would have added comes here instead, so it lands
// on output pixels rather than being stretched with the picture.

#include <lib/frag_coord_info.glsl>

in vec2 v_uv;

out vec4 frag_color;

uniform sampler2D source_texture;

uniform EasuInfo {
  /// xy: the source's size in pixels. zw: one over it.
  vec4 source;
  /// x: the grain the composite left out, as `LookSettings.grain`. yzw unused.
  vec4 params;
}
easu_info;

float Hash(vec2 at) {
  return fract(sin(dot(at, vec2(12.9898, 78.233))) * 43758.5453);
}

vec3 Tap(vec2 pixel) {
  return textureLod(source_texture, (pixel + 0.5) * easu_info.source.zw, 0.0).rgb;
}

/// Luma as the filter weighs it: green twice, red and blue once.
float EasuLuma(vec3 c) { return c.g + 0.5 * (c.r + c.b); }

/// One of the four nearest taps' share of the edge's direction and length,
/// weighted by [w], its bilinear weight. [a] is above the centre [c], [b]
/// left of it, [d] right and [e] below.
void EdgeAt(inout vec2 dir, inout float len, float w, float a, float b, float c,
            float d, float e) {
  float lenX = max(abs(d - c), abs(c - b));
  float dirX = d - b;
  float stretchX = clamp(abs(dirX) / max(lenX, 1e-6), 0.0, 1.0);
  float lenY = max(abs(e - c), abs(c - a));
  float dirY = e - a;
  float stretchY = clamp(abs(dirY) / max(lenY, 1e-6), 0.0, 1.0);
  dir += vec2(dirX, dirY) * w;
  len += (stretchX * stretchX + stretchY * stretchY) * w;
}

/// One tap's weight at offset [off] from the sample position.
float TapWeight(vec2 off, vec2 dir, vec2 len2, float lob, float clp) {
  vec2 v = vec2(off.x * dir.x + off.y * dir.y, off.x * -dir.y + off.y * dir.x);
  v *= len2;
  float d2 = min(dot(v, v), clp);
  float wB = 0.4 * d2 - 1.0;
  float wA = lob * d2 - 1.0;
  wB *= wB;
  wA *= wA;
  wB = 1.5625 * wB - 0.5625;
  return wB * wA;
}

void main() {
  vec2 pp = v_uv * easu_info.source.xy - 0.5;
  vec2 fp = floor(pp);
  pp -= fp;

  vec3 b = Tap(fp + vec2(0.0, -1.0));
  vec3 c = Tap(fp + vec2(1.0, -1.0));
  vec3 e = Tap(fp + vec2(-1.0, 0.0));
  vec3 f = Tap(fp);
  vec3 g = Tap(fp + vec2(1.0, 0.0));
  vec3 h = Tap(fp + vec2(2.0, 0.0));
  vec3 i = Tap(fp + vec2(-1.0, 1.0));
  vec3 j = Tap(fp + vec2(0.0, 1.0));
  vec3 k = Tap(fp + vec2(1.0, 1.0));
  vec3 l = Tap(fp + vec2(2.0, 1.0));
  vec3 n = Tap(fp + vec2(0.0, 2.0));
  vec3 o = Tap(fp + vec2(1.0, 2.0));

  float bL = EasuLuma(b);
  float cL = EasuLuma(c);
  float eL = EasuLuma(e);
  float fL = EasuLuma(f);
  float gL = EasuLuma(g);
  float hL = EasuLuma(h);
  float iL = EasuLuma(i);
  float jL = EasuLuma(j);
  float kL = EasuLuma(k);
  float lL = EasuLuma(l);
  float nL = EasuLuma(n);
  float oL = EasuLuma(o);

  vec2 dir = vec2(0.0);
  float len = 0.0;
  EdgeAt(dir, len, (1.0 - pp.x) * (1.0 - pp.y), bL, eL, fL, gL, jL);
  EdgeAt(dir, len, pp.x * (1.0 - pp.y), cL, fL, gL, hL, kL);
  EdgeAt(dir, len, (1.0 - pp.x) * pp.y, fL, iL, jL, kL, nL);
  EdgeAt(dir, len, pp.x * pp.y, gL, jL, kL, lL, oL);

  // A flat patch has no direction; any will do, and x is as good as any.
  float dirR = dot(dir, dir);
  bool featureless = dirR < 1.0 / 32768.0;
  dir = featureless ? vec2(1.0, 0.0) : dir * inversesqrt(max(dirR, 1e-12));

  len *= 0.5;
  len *= len;
  float stretch = dot(dir, dir) / max(abs(dir.x), abs(dir.y));
  vec2 len2 = vec2(1.0 + (stretch - 1.0) * len, 1.0 - 0.5 * len);
  float lob = 0.5 - 0.29 * len;
  float clp = 1.0 / lob;

  vec3 sum = vec3(0.0);
  float weight = 0.0;
  float w;
  w = TapWeight(vec2(0.0, -1.0) - pp, dir, len2, lob, clp); sum += b * w; weight += w;
  w = TapWeight(vec2(1.0, -1.0) - pp, dir, len2, lob, clp); sum += c * w; weight += w;
  w = TapWeight(vec2(-1.0, 1.0) - pp, dir, len2, lob, clp); sum += i * w; weight += w;
  w = TapWeight(vec2(0.0, 1.0) - pp, dir, len2, lob, clp); sum += j * w; weight += w;
  w = TapWeight(vec2(0.0, 0.0) - pp, dir, len2, lob, clp); sum += f * w; weight += w;
  w = TapWeight(vec2(-1.0, 0.0) - pp, dir, len2, lob, clp); sum += e * w; weight += w;
  w = TapWeight(vec2(1.0, 1.0) - pp, dir, len2, lob, clp); sum += k * w; weight += w;
  w = TapWeight(vec2(2.0, 1.0) - pp, dir, len2, lob, clp); sum += l * w; weight += w;
  w = TapWeight(vec2(2.0, 0.0) - pp, dir, len2, lob, clp); sum += h * w; weight += w;
  w = TapWeight(vec2(1.0, 0.0) - pp, dir, len2, lob, clp); sum += g * w; weight += w;
  w = TapWeight(vec2(1.0, 2.0) - pp, dir, len2, lob, clp); sum += o * w; weight += w;
  w = TapWeight(vec2(0.0, 2.0) - pp, dir, len2, lob, clp); sum += n * w; weight += w;

  vec3 lo = min(min(f, g), min(j, k));
  vec3 hi = max(max(f, g), max(j, k));
  vec3 color = clamp(sum / max(weight, 1e-6), lo, hi);

  float grain = easu_info.params.x;
  color += vec3((Hash(TargetFragCoord()) - 0.5) * grain);
  frag_color = vec4(color, 1.0);
}
