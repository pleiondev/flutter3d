#version 460 core

// Depth of field: a thin lens, a circle of confusion, and a gather — `gfx-34n`.
//
// **The arithmetic is a lens rather than a curve somebody liked.** A point at
// distance `d` images to a disc whose diameter is
//
//     |d - focus| / d  *  f^2 / (N * (focus - f))
//
// where `f` is the focal length and `N` the f-number. That is the thin-lens
// formula, and the reason to use it rather than a hand-drawn ramp is that
// every number in it is one a photographer already knows: open the aperture
// and the background goes softer by an amount somebody can predict.
//
// **The depth is the surface buffer's alpha**, which carries view-axis
// distance in metres — so the circle is computed from a real distance rather
// than from a window depth, where the same blur would mean different things
// near and far. That channel is also why no depth attachment is needed:
// flutter_gpu cannot sample one.
//
// **A gather, not a scatter**, reaching as far as the largest circle nearby.
// Each output pixel reads the neighbourhood and asks which of those samples
// would have landed on it. How far it reads is the largest circle in its
// tile and the eight around it (`DofTileMax`, then the motion blur's column
// and neighbourhood passes), not its own: a sharp pixel beside a blurred
// foreground has a circle of nought, and a gather that stopped at its own
// circle never saw the foreground whose disc covers it, which left every
// out-of-focus foreground with a hard outline against a sharp background.
// Samples nearer than this pixel and more blurred than it are a layer of
// their own, laid over the rest by how much of this pixel their discs cover.
//
// Sampled on a spiral rather than a grid: a square kernel makes a square
// bokeh, and the shape of an out-of-focus highlight is the one thing anybody
// looks at in this effect.

#include <lib/circle_of_confusion.glsl>
#include <lib/frag_coord_info.glsl>

in vec2 v_uv;

out vec4 frag_color;

uniform sampler2D scene_texture;
uniform sampler2D surface_texture;

// The largest circle within a tile of here, in red, one texel a tile.
uniform sampler2D coc_tile_texture;

uniform DofInfo {
  // x: focus distance in metres. y: focal length in metres. z: f-number.
  // w: how many samples in the gather.
  vec4 lens;

  // x, y: one texel. z: the largest circle, in texels, whatever the lens
  // arithmetic says — a bound on the gather rather than on the optics.
  // w: texels per metre across the sensor, which is the frame's width in
  // texels over the sensor's width in metres.
  vec4 params;
}
dof_info;

// One cell of a 4x4 Bayer matrix, in [0, 1). The same table
// `reflections.frag` and `light_shafts.frag` keep.
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

// The circle of confusion at [depth], as a radius in texels.
float CircleAt(float depth) {
  return CircleOfConfusion(depth, dof_info.lens, dof_info.params);
}

void main() {
  // `textureLod` throughout this pass, for `shadow.glsl`'s own reason: the
  // gather below sits behind two early returns keyed on a per-fragment circle
  // of confusion, so a WGSL backend refuses the implicit derivative as
  // possibly non-uniform. All three textures are read at native size with no
  // mipmap of their own, so naming level zero directly changes no pixel.
  vec4 centre = textureLod(scene_texture, v_uv, 0.0);
  int samples = int(dof_info.lens.w + 0.5);
  if (samples < 1) {
    frag_color = centre;
    return;
  }

  float centreDepth = textureLod(surface_texture, v_uv, 0.0).a;
  float radius = CircleAt(centreDepth);
  // As far as anything nearby could spread, and never less than this
  // pixel's own circle.
  float gather = max(textureLod(coc_tile_texture, v_uv, 0.0).r, radius);
  if (gather < 0.5) {
    // Inside half a texel there is nothing to gather: no disc near here is
    // larger than the pixel it lands on, which is what "in focus" means.
    frag_color = centre;
    return;
  }

  vec3 total = centre.rgb;
  float weight = 1.0;
  // The nearer, more blurred layer: its colour, and how much of this pixel
  // its discs cover.
  vec3 nearTotal = vec3(0.0);
  float nearWeight = 0.0;
  float nearCover = 0.0;

  // Nothing drawn is infinitely far, for the comparison below as for the
  // circle above.
  float centreFar = centreDepth <= 0.0 ? 1e9 : centreDepth;

  // The spiral turned by a different angle at each pixel of a 4x4 block, so
  // twenty-odd taps across a wide disc read as grain rather than as twenty-odd
  // copies of a bright highlight. A Bayer cell rather than Jimenez's
  // interleaved gradient noise, which is a `fract` of a large product and
  // would not land on the same angle in the software backend's doubles.
  float turn = 6.2831853 * BayerCell(TargetFragCoord());

  // The golden angle, so consecutive samples never line up into a spoke.
  const float kGolden = 2.39996323;
  for (int i = 1; i <= 64; i++) {
    if (i > samples) break;
    // The middle of each ring's share of the area rather than its outer edge.
    float t = (float(i) - 0.5) / float(samples);
    // sqrt so the samples spread evenly over the disc's *area* rather than
    // bunching at the middle, which would leave the rim of a bokeh thin.
    float r = sqrt(t) * gather;
    float angle = float(i) * kGolden + turn;
    vec2 at = v_uv + vec2(cos(angle), sin(angle)) * r * dof_info.params.xy;

    vec4 tap = textureLod(scene_texture, at, 0.0);
    float tapDepth = textureLod(surface_texture, at, 0.0).a;
    float tapRadius = CircleAt(tapDepth);
    float tapFar = tapDepth <= 0.0 ? 1e9 : tapDepth;

    // Would this sample's own disc have reached here? A sharp pixel in front
    // of a blurred background says no — its disc is smaller than the
    // distance to here — and letting it in anyway is the bleed that makes a
    // sharp object glow into the blur behind it. A sample *behind* this pixel
    // reaches no further than this pixel's own disc either. Half a texel of
    // soft edge, so the reach does not step.
    float tapReach = tapFar > centreFar ? min(tapRadius, radius) : tapRadius;
    float reach = clamp(tapReach - r + 0.5, 0.0, 1.0);

    if (tapFar < centreFar && tapRadius > radius) {
      // In front and more blurred: a disc spread over this pixel. Each
      // sample stands for an equal share of the gather's area, and a disc
      // of radius c puts 1 / (pi c^2) of its light on each unit of it, so
      // the share it covers is reach * (gather / c)^2 / samples.
      float spread = gather / max(tapRadius, 0.5);
      nearTotal += tap.rgb * reach;
      nearWeight += reach;
      nearCover += reach * spread * spread;
    } else {
      total += tap.rgb * reach;
      weight += reach;
    }
  }

  vec3 far = total / weight;
  vec3 near = nearTotal / max(nearWeight, 1e-5);
  float cover = clamp(nearCover / float(samples), 0.0, 1.0);
  frag_color = vec4(mix(far, near, cover), centre.a);
}
