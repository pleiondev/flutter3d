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

// The circle of confusion at [depth], as a radius in texels.
float CircleAt(float depth) {
  float focus = max(dof_info.lens.x, 1e-3);
  float focal = max(dof_info.lens.y, 1e-4);
  float fnumber = max(dof_info.lens.z, 1e-3);
  if (depth <= 0.0) return 0.0;

  // The thin-lens diameter, in metres on the sensor.
  float denominator = max(fnumber * (focus - focal), 1e-6);
  float diameter = abs(depth - focus) / depth * (focal * focal) / denominator;

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

  // The golden angle, so consecutive samples never line up into a spoke.
  const float kGolden = 2.39996323;
  for (int i = 1; i <= 64; i++) {
    if (i > samples) break;
    float t = float(i) / float(samples);
    // sqrt so the samples spread evenly over the disc's *area* rather than
    // bunching at the middle, which would leave the rim of a bokeh thin.
    float r = sqrt(t) * radius;
    float angle = float(i) * kGolden;
    vec2 at = v_uv + vec2(cos(angle), sin(angle)) * r * dof_info.params.xy;

    vec4 tap = textureLod(scene_texture, at, 0.0);
    float tapDepth = textureLod(surface_texture, at, 0.0).a;
    float tapRadius = CircleAt(tapDepth);

    // Would this sample's own disc have reached here? A sharp background
    // pixel behind a blurred foreground says no, and letting it in anyway is
    // the bleed that makes a distant object glow through a near one.
    float reach = r <= max(tapRadius, radius) ? 1.0 : 0.0;
    total += tap.rgb * reach;
    weight += reach;
  }

  frag_color = vec4(total / weight, centre.a);
}
