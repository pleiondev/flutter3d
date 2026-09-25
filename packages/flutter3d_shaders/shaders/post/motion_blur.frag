#version 460 core

// Motion blur: a gather along the motion that dominates each neighbourhood
// and along the pixel's own — `R6`, after McGuire, Hennessy, Bukowski and
// Osman's reconstruction filter (2012) with Guertin, McGuire and
// Nowrouzezahrai's refinements of it (2014).
//
// **Along the neighbourhood's motion, and the pixel's own.** A still pixel
// beside a moving object is still crossed by it for part of the exposure, so
// sampling only along each pixel's own velocity would leave the moving
// object's blur with a hard edge wherever it passes over the background.
// Half the samples therefore walk the longest motion within one tile of it —
// the `VelocityNeighborMax` pass's answer. The other half walk the pixel's
// own motion, or across the dominant one for a pixel too slow to have a
// direction: where a neighbourhood holds two motions — a wheel, a spinning
// prop, two things passing — a pixel sampled only along its neighbour's
// streak took that streak for its own, and the blur changed direction at
// every tile edge. Each sample asks whether its colour could have reached
// here, and a streak counts only as far as it runs along the line sampled.
//
// **The tile read is jittered by up to a quarter tile**, so a pixel near a
// tile's edge sometimes takes its neighbour tile's motion: the step between
// tiles becomes grain, and the temporal resolve smooths it.
//
// **Three ways a sample reaches a pixel**, weighed by which of the two is in
// front: a sample in front, blurred by its own motion far enough to cover
// here; a sample behind, seen because this pixel's own motion spread it
// across; and two samples moving together, where neither is in front and
// both are the same streak. The depth is the surface buffer's alpha, view
// distance in metres, and "in front" is soft over a few centimetres so a
// surface does not occlude itself.
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

// How much of a streak [span] pixels long covers a point [gap] away:
// all of it at the source, none at the streak's end.
float Cone(float gap, float span) {
  return clamp(1.0 - gap / span, 0.0, 1.0);
}

// Whether a point [gap] away is inside a streak [span] pixels long,
// with a tenth of a streak of soft edge.
float Cylinder(float gap, float span) {
  return 1.0 - smoothstep(0.95 * span, 1.05 * span, gap);
}

// How far along [line] a motion of [span] pixels runs, from nought across
// it to one along it. A motion under half a pixel has no direction to
// disagree with and runs along every line.
float Along(vec2 motion, float span, vec2 line) {
  return span < 0.5 ? 1.0 : abs(dot(motion / span, line));
}

void main() {
  // `textureLod` throughout, for `depth_of_field.frag`'s reason: the gather
  // sits behind an early return keyed on the neighbourhood's motion.
  vec4 centre = textureLod(scene_texture, v_uv, 0.0);
  vec2 here = v_uv * blur_info.scene.zw;
  vec2 pixel = TargetFragCoord();
  // Up to a quarter tile either way, per axis, from two reads of the noise
  // that do not land on the same cell of either pattern.
  float tileWidth = max(blur_info.tiles.z, 1.0);
  vec2 nudge = vec2(PixelNoise(pixel + vec2(2.0, 1.0)),
                    PixelNoise(pixel + vec2(1.0, 3.0))) -
               0.5;
  vec2 tile = clamp(floor((here + nudge * 0.5 * tileWidth) / tileWidth),
                    vec2(0.0), max(blur_info.tiles.xy - 1.0, vec2(0.0)));
  vec2 dominant =
      textureLod(neighbor_texture, (tile + 0.5) / blur_info.tiles.xy, 0.0).rg;
  int samples = int(blur_info.params.w + 0.5);
  float reachFar = length(dominant);
  // Under half a pixel of motion anywhere near: nothing here would move a
  // sample off this pixel.
  if (reachFar <= 0.5 || samples < 1) {
    frag_color = centre;
    return;
  }

  vec2 own = HalfMotion(textureLod(velocity_texture, v_uv, 0.0).rg);
  float ownLength = length(own);
  // Half a pixel at least, so a still pixel's own streak is the pixel it is
  // in, and the divisions below have something to divide by.
  float ownSpan = max(ownLength, 0.5);
  float ownDepth = Far(textureLod(surface_texture, v_uv, 0.0).a);
  float extent = max(blur_info.tiles.w, 1e-4);

  // The two lines sampled: the neighbourhood's motion, and the pixel's own.
  // A pixel too slow for its motion to be a direction samples across the
  // neighbourhood's instead, turning to its own over the next pixel and a
  // half of speed.
  vec2 across = dominant / reachFar;
  vec2 side = vec2(-across.y, across.x);
  if (dot(side, own) < 0.0) side = -side;
  vec2 ownLine = ownLength > 1e-6 ? own / ownLength : side;
  vec2 mine =
      normalize(mix(side, ownLine, clamp((ownLength - 0.5) / 1.5, 0.0, 1.0)));

  // The pixel itself, weighted by how little it moves: a still pixel keeps
  // most of its own colour, a fast one is mostly what streaks across it.
  // Forty is the paper's constant, which scales the centre to the number of
  // samples beside it.
  float weight = float(samples) / (40.0 * ownSpan);
  vec3 total = centre.rgb * weight;

  float jitter = PixelNoise(pixel) - 0.5;
  for (int i = 0; i < 64; i++) {
    if (i >= samples) break;
    // Every other sample on the pixel's own line. The middle one is kept:
    // jittered, it is a neighbour as often as it is the pixel.
    vec2 line = mod(float(i), 2.0) > 0.5 ? mine : across;
    float t = mix(-1.0, 1.0, (float(i) + jitter + 1.0) / float(samples + 1));
    vec2 there = floor(here + line * (t * reachFar)) + 0.5;
    vec2 at = there * blur_info.scene.xy;
    float gap = length(there - here);

    vec4 tap = textureLod(scene_texture, at, 0.0);
    vec2 tapMotion = HalfMotion(textureLod(velocity_texture, at, 0.0).rg);
    float tapLength = length(tapMotion);
    float tapSpan = max(tapLength, 0.5);
    float tapDepth = Far(textureLod(surface_texture, at, 0.0).a);

    // How far each streak runs along the line this sample is on: a sample
    // moving across it could not have been smeared here along it.
    float ownAlong = abs(dot(mine, line));
    float tapAlong = Along(tapMotion, tapLength, line);

    // Whether the sample is in front of this pixel, and whether this pixel
    // is in front of the sample: both are one within the soft extent.
    float front = clamp(1.0 - (tapDepth - ownDepth) / extent, 0.0, 1.0);
    float back = clamp(1.0 - (ownDepth - tapDepth) / extent, 0.0, 1.0);
    float reach =
        front * Cone(gap, tapSpan) * tapAlong +
        back * Cone(gap, ownSpan) * ownAlong +
        Cylinder(gap, tapSpan) * Cylinder(gap, ownSpan) *
            max(ownAlong, tapAlong) * 2.0;
    total += tap.rgb * reach;
    weight += reach;
  }

  frag_color = vec4(total / weight, centre.a);
}
