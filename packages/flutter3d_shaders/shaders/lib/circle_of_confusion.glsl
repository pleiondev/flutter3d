// The thin lens's circle of confusion — `gfx-34n`.
//
// One function for the two stages that need it, the depth of field's gather
// and the tile search in front of it: the tile's largest circle has to be the
// largest of the circles the gather will compute, to the bit.

#ifndef CIRCLE_OF_CONFUSION_GLSL_
#define CIRCLE_OF_CONFUSION_GLSL_

// The circle of confusion at [depth], as a radius in texels.
//
// [lens] x: focus distance in metres. y: focal length in metres. z: f-number.
// [params] z: the largest circle, in texels. w: texels per metre across the
// sensor.
float CircleOfConfusion(float depth, vec4 lens, vec4 params) {
  float focus = max(lens.x, 1e-3);
  float focal = max(lens.y, 1e-4);
  float fnumber = max(lens.z, 1e-3);

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
  return min(diameter * 0.5 * params.w, max(params.z, 0.0));
}

#endif  // CIRCLE_OF_CONFUSION_GLSL_
