#version 460 core

// A Gaussian splat, as the falloff inside a quad — `gfx-80n`.
//
// **Why this is a fragment stage and nothing else.** A splat is an ellipsoid of
// fading opacity, and what reaches the screen is that ellipsoid's projection: an
// ellipse whose brightness falls off as a Gaussian from its middle. Two ways to
// draw one. Expand a point into an ellipse here, which needs a geometry stage
// flutter_gpu does not have; or hand the stage a quad already shaped and
// oriented, and evaluate the falloff across it. This engine already made that
// choice once, for particles, and `particle.vert`'s own comment says why — so
// splats reuse that vertex stage exactly rather than adding a second one that
// would read the same three attributes.
//
// The quad's `texcoord` is therefore not a texture coordinate. It is the
// fragment's position in the *Gaussian's own* space, in units of its standard
// deviation, centred at zero: the CPU builds the quad from the projected
// ellipse's axes, so `v_uv` arrives already in the frame where the falloff is
// round and the arithmetic here is one dot product.
//
// **Alpha blended, back to front, and that is the whole difference from a
// particle.** Particles are additive, which is why they need no sorting —
// addition does not care about order. A splat is translucent: two overlapping
// ones give a different colour depending on which was drawn first, so the cloud
// is sorted every time the camera moves and this stage writes straight alpha.

in vec4 v_color;
in vec2 v_uv;
in vec3 v_world_position;

out vec4 frag_color;

/// The same block the particle stage declares, for the same reason it declares
/// it: a different vertex layout and none of the lit shaders' varyings, so none
/// of their headers apply. Two members, not three — nothing here writes a
/// surface buffer, so there is no view axis to measure a depth along.
uniform FogInfo {
  /// rgb: linear fog colour. w: density per metre, zero for no fog.
  vec4 fog;

  /// xyz: camera position in world space.
  vec4 eye;
}
fog_info;

void main() {
  // `exp(-½ dᵀd)` with d already in standard deviations, which is what the
  // quad's own coordinates are. No matrix here: the inverse covariance was
  // applied when the corners were placed, because it is one ellipse per splat
  // and four corners, not one per fragment.
  float power = -0.5 * dot(v_uv, v_uv);

  // **Cut off rather than trailed to nothing.** A Gaussian never reaches zero,
  // so a quad sized to hold all of it would be infinite; the corners sit at
  // three standard deviations, where the falloff is under a hundredth, and
  // anything past that is discarded so the quad's own square edge can never
  // show. Without this the cloud reads as a field of faint rectangles.
  if (power < -4.5) discard;

  float alpha = v_color.a * exp(power);
  if (alpha < 1.0 / 255.0) discard;

  // Fog as a mix rather than as attenuation, which is the opposite of the
  // particle stage above and for the opposite reason: this is blended, so the
  // destination is *replaced* in proportion to alpha, and a distant splat that
  // faded toward black would put black into the wall behind it instead of
  // fading into the air.
  vec3 colour = v_color.rgb;
  if (fog_info.fog.w > 0.0) {
    float visibility = clamp(
        exp(-fog_info.fog.w * distance(v_world_position, fog_info.eye.xyz)),
        0.0,
        1.0);
    colour = mix(fog_info.fog.rgb, colour, visibility);
  }

  // Premultiplied, because that is what the blend state this is drawn under
  // expects: `one, one_minus_src_alpha` composites a stack of translucent
  // layers correctly in one pass, and straight alpha under the same state
  // double-counts the colour of everything in front.
  frag_color = vec4(colour * alpha, alpha);
}
