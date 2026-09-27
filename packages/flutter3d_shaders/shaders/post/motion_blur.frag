#version 460 core

// Motion blur: a gather along the motion that dominates each neighbourhood
// — `R6`, after McGuire, Hennessy, Bukowski and Osman's reconstruction
// filter (2012), composited the way the exposure is.
//
// **Along the neighbourhood's motion, not the pixel's own.** A still pixel
// beside a moving object is still crossed by it for part of the exposure, so
// sampling only along each pixel's own velocity would leave the moving
// object's blur with a hard edge wherever it passes over the background.
// Each pixel therefore walks the longest motion within one tile of it — the
// `VelocityNeighborMax` pass's answer — and asks of every sample whether its
// colour could have reached here.
//
// **For how long, rather than whether.** A sample stands for one stride of
// the line, and a stride of surface sweeping a streak `2 × span` pixels long
// sits over any one pixel of it for `stride / (2 × span)` of the exposure.
// That is the sample's share of the time, and the shares say how much of the
// exposure something covered this pixel; what they leave over is time the
// pixel showed whatever was behind. The 2012 filter normalised its weights
// instead, and a still background has no weight there once a sample is half
// a pixel away, so where a spoke swept over the background the spoke was all
// that was left to normalise: it came out nearly opaque across its whole fan
// where the exposure shows it for the share of the time it was there.
//
// **Three layers, by depth against this pixel's.** Samples in front are
// occluders, over everything for their share. Samples level with it are
// this pixel's own surface, the pixel itself among them, over what is behind
// for their share. Samples behind are what shows where this pixel's surface
// is not: the pixel cannot see what its surface hid, so it borrows the
// nearest of what the line saw behind it, weighted by the inverse square of
// the distance. The depth is the surface buffer's alpha, view distance in
// metres, and "in front" is soft over a few centimetres so a surface does
// not occlude itself. The shares are summed in linear light, before the
// tone curve, which is where a camera integrates.
//
// Fifteen samples, offset along the line by the per-pixel noise so the
// steps between them are grain rather than fifteen copies of the object.
//
// The motion is half the exposed part of a frame's movement, either side of
// the pixel: a shutter open for half the frame blurs a quarter of the
// motion forward and a quarter back.

#include <lib/frag_coord_info.glsl>
#include <lib/blue_noise.glsl>

in vec2 v_uv;

out vec4 frag_color;

uniform sampler2D scene_texture;
uniform sampler2D velocity_texture;
uniform sampler2D surface_texture;
uniform sampler2D neighbor_texture;

uniform MotionBlurInfo {
  // xy: one texel of the scene. zw: its size in texels.
  vec4 scene;

  // xy: what a velocity is multiplied by to be a half-motion in pixels.
  // z: the longest a half-motion may be, in pixels. w: samples.
  vec4 params;

  // xy: the neighbourhood texture's size in tiles. z: a tile's width in
  // pixels. w: how far apart in metres two depths are before one is in
  // front of the other.
  vec4 tiles;
}
blur_info;

// [motion] scaled into pixels and no longer than the largest radius — the
// same arithmetic `velocity_tile_max.frag` applies on its first pass.
vec2 HalfMotion(vec2 motion) {
  vec2 pixels = motion * blur_info.params.xy;
  float span = length(pixels);
  float most = max(blur_info.params.z, 0.0);
  return span > most ? pixels * (most / span) : pixels;
}

// Nothing drawn is infinitely far.
float Far(float depth) {
  return depth <= 0.0 ? 1e9 : depth;
}

// Whether a point [gap] away is inside a streak [span] pixels long, with a
// pixel's width of soft edge.
float Reaches(float gap, float span) {
  return 1.0 - smoothstep(span - 0.5, span + 0.5, gap);
}

void main() {
  // `textureLod` throughout, for `depth_of_field.frag`'s reason: the gather
  // sits behind an early return keyed on the neighbourhood's motion.
  vec4 centre = textureLod(scene_texture, v_uv, 0.0);
  vec2 here = v_uv * blur_info.scene.zw;
  vec2 tile = floor(here / max(blur_info.tiles.z, 1.0));
  vec2 dominant =
      textureLod(neighbor_texture, (tile + 0.5) / blur_info.tiles.xy, 0.0).rg;
  float reach = length(dominant);
  int samples = int(blur_info.params.w + 0.5);
  // Under half a pixel of motion anywhere near: nothing here would move a
  // sample off this pixel.
  if (reach <= 0.5 || samples < 1) {
    frag_color = centre;
    return;
  }

  // Half a pixel at least, so a still pixel's own streak is the pixel it is
  // in, and the division below has something to divide by.
  float ownSpan =
      max(length(HalfMotion(textureLod(velocity_texture, v_uv, 0.0).rg)), 0.5);
  float ownDepth = Far(textureLod(surface_texture, v_uv, 0.0).a);
  float extent = max(blur_info.tiles.w, 1e-4);
  // The length of line each sample stands for.
  float stride = 2.0 * reach / float(samples + 1);

  // The pixel itself is level with itself, and covers itself for its share:
  // all of the exposure when it is still, little of it when it is fast. It
  // stands for a pixel at least, so a short line whose samples crowd closer
  // than a pixel does not leave a still pixel partly see-through.
  float ownShare = min(max(stride, 1.0) / (2.0 * ownSpan), 1.0);
  vec3 front = vec3(0.0);
  float frontCover = 0.0;
  vec3 level = centre.rgb * ownShare;
  float levelCover = ownShare;
  vec3 back = vec3(0.0);
  float backWeight = 0.0;

  float jitter = PixelNoise(TargetFragCoord()) - 0.5;
  int middle = (samples - 1) / 2;
  for (int i = 0; i < 64; i++) {
    if (i >= samples) break;
    // The middle sample is the pixel itself, counted above.
    if (i == middle) continue;
    float t = mix(-1.0, 1.0, (float(i) + jitter + 1.0) / float(samples + 1));
    vec2 there = floor(here + dominant * t) + 0.5;
    vec2 at = there * blur_info.scene.xy;
    float gap = length(there - here);

    vec3 tap = textureLod(scene_texture, at, 0.0).rgb;
    float tapSpan =
        max(length(HalfMotion(textureLod(velocity_texture, at, 0.0).rg)), 0.5);
    float tapDepth = Far(textureLod(surface_texture, at, 0.0).a);

    // How far the sample is in front of this pixel, and how far behind:
    // each is one past the soft extent, and neither is level.
    float nearer = clamp((ownDepth - tapDepth) / extent, 0.0, 1.0);
    float behind = clamp((tapDepth - ownDepth) / extent, 0.0, 1.0);
    // The share of the exposure the sample's stride spends over this pixel.
    float share = Reaches(gap, tapSpan) * min(stride / (2.0 * tapSpan), 1.0);
    front += tap * (nearer * share);
    frontCover += nearer * share;
    level += tap * ((1.0 - nearer - behind) * share);
    levelCover += (1.0 - nearer - behind) * share;
    // A sample on this very pixel is no nearer than one a pixel away.
    float nearness = behind / max(gap * gap, 1.0);
    back += tap * nearness;
    backWeight += nearness;
  }

  // Behind, under this pixel's surface, under what passed in front — each
  // layer for the part of the exposure the one above it left over, and the
  // average of a layer standing for it when it covers more than the whole.
  vec3 own = level / levelCover;
  vec3 behindColor = backWeight > 0.0 ? back / backWeight : own;
  vec3 under = mix(behindColor, own, min(levelCover, 1.0));
  vec3 over = frontCover > 0.0 ? front / frontCover : under;
  frag_color = vec4(mix(under, over, min(frontCover, 1.0)), centre.a);
}
