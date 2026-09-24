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
// **A gather, not a scatter.** Each output pixel reads the neighbourhood and
// asks which of those samples would have landed on it. That gets the near
// field wrong in a way a scatter would not — a foreground blur cannot spread
// *over* a sharp background, because the sharp pixel never looks that far —
// and it is the trade every real-time implementation makes, because a scatter
// needs per-pixel splatting the hardware here has no path for. Written down
// rather than discovered: this is why a foreground bokeh has a hard outer
// edge where a photograph's would not.
//
// Sampled on a spiral rather than a grid: a square kernel makes a square
// bokeh, and the shape of an out-of-focus highlight is the one thing anybody
// looks at in this effect.

#include <lib/frag_coord_info.glsl>

in vec2 v_uv;

out vec4 frag_color;

uniform sampler2D scene_texture;
uniform sampler2D surface_texture;

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
  float focus = max(dof_info.lens.x, 1e-3);
  float focal = max(dof_info.lens.y, 1e-4);
  float fnumber = max(dof_info.lens.z, 1e-3);

  // The thin-lens diameter, in metres on the sensor. Nothing drawn — the sky,
  // the cleared background — is infinitely far, where `|d - s| / d` tends to
  // one and the circle to its largest: a lens focused on a face blurs the
  // horizon behind it. This used to answer zero there and kept the sky sharp.
  float denominator = max(fnumber * (focus - focal), 1e-6);
  float ratio = depth <= 0.0 ? 1.0 : abs(depth - focus) / depth;
  float diameter = ratio * (focal * focal) / denominator;

  // Metres on the sensor into texels on the screen, and a diameter into a
  // radius. The conversion needs a sensor size, which is what makes a
  // millimetre of focal length mean something; the frame's width supplies the
  // other half of it. **Derived rather than a constant**, because a constant
  // would mean a lens whose blur changed with the resolution — the same scene
  // rendered twice as wide would be a different photograph rather than a
  // larger one.
  return min(diameter * 0.5 * dof_info.params.w, max(dof_info.params.z, 0.0));
}

void main() {
  // `textureLod` throughout this pass, for `shadow.glsl`'s own reason: the
  // gather below sits behind two early returns keyed on a per-fragment circle
  // of confusion, so a WGSL backend refuses the implicit derivative as
  // possibly non-uniform. Both textures are read at native size with no
  // mipmap of their own, so naming level zero directly changes no pixel.
  vec4 centre = textureLod(scene_texture, v_uv, 0.0);
  int samples = int(dof_info.lens.w + 0.5);
  if (samples < 1) {
    frag_color = centre;
    return;
  }

  float centreDepth = textureLod(surface_texture, v_uv, 0.0).a;
  float radius = CircleAt(centreDepth);
  if (radius < 0.5) {
    // Inside half a texel there is nothing to gather: the disc this point
    // images to is smaller than the pixel it lands on, which is what "in
    // focus" means.
    frag_color = centre;
    return;
  }

  vec3 total = centre.rgb;
  float weight = 1.0;

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
    float r = sqrt(t) * radius;
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
    // reaches no further than this pixel's own disc either. The test used to
    // be `r <= max(tapRadius, radius)`, which with `r <= radius` always held
    // and let every sample in. Half a texel of soft edge, so the reach does
    // not step.
    float tapReach = tapFar > centreFar ? min(tapRadius, radius) : tapRadius;
    float reach = clamp(tapReach - r + 0.5, 0.0, 1.0);
    total += tap.rgb * reach;
    weight += reach;
  }

  frag_color = vec4(total / weight, centre.a);
}
