#version 460 core

// The last pass: add the bloom, tone map, encode to sRGB.
//
// Tone mapping lives here rather than in each lighting model, which is the
// point of having an HDR target at all. Applying it per model meant every
// shader wrote display-referred colour into an 8-bit buffer, so anything above
// display white was gone before post-processing could see it — and bloom is
// entirely a function of what is above display white.
precision highp float;

#include <lib/frag_coord_info.glsl>

in vec2 v_uv;

out vec4 frag_color;

/// The scene, linear and unbounded.
uniform sampler2D scene_texture;

/// The bloom chain's top level, or a black texture when bloom is off.
uniform sampler2D bloom_texture;

/// Ambient occlusion at half resolution, or a white texture when it is off.
///
/// White rather than absent, because a sampler a shader declares and nobody
/// binds is a native crash on Metal rather than a black texture — the same rule
/// that kept the sky's cube map out of `sky.frag`. One white texel costs
/// nothing and removes the branch.
uniform sampler2D ao_texture;

/// The contact shadow's own factor — `gfx-76n`. Bound on every frame with a
/// white stand-in when the pass did not run, the same rule `ao_texture` above
/// follows and for the same reason: a declared sampler nobody binds is a native
/// crash on Metal rather than a black texture.
uniform sampler2D contact_shadow_texture;

/// The colour table, as a strip: N slices of N×N laid out left to right, so
/// the image is N² wide and N tall. Bound to whatever the engine has when no
/// table is set — the strength is zero then and nothing samples it, but a
/// sampler this shader declares and nobody binds is a native crash on Metal
/// rather than a black texture, which is the same rule `ao_texture` above
/// already follows.
uniform sampler2D lut_texture;

/// The display transform, as a strip in the colour table's shape but float
/// and indexed through a log2 shaper — `L2`. Read **instead of** a tone curve
/// when `params.z` is 6, bound to a stand-in otherwise, for the rule every
/// sampler here follows.
uniform sampler2D display_texture;

uniform CompositeInfo {
  /// x: exposure, y: bloom intensity, z: which tone curve, w: how much of the
  /// occlusion to apply, 0 for none.
  ///
  /// **z is a curve number, not a flag, and 1 is still the old flag's
  /// meaning.** 0 leaves the colour alone, 1 is Khronos PBR Neutral — what
  /// every golden in this repository was recorded with — 2 is ACES, 3 is AgX
  /// and 4 is Reinhard. Numbering the default 1 is what lets a `> 0.5` read
  /// of the old flag and an `int()` read of the new number agree about every
  /// scene already recorded.
  vec4 params;

  /// x, y: one texel of the ao texture. z: how much of the colour table to
  /// apply, 0 for none. w: how many slices the table has, its N.
  vec4 ao_texel;

  /// The look, half of it. x: contrast, y: saturation, z: temperature,
  /// w: chromatic aberration.
  ///
  /// **Neutral is (1, 1, 0, 0) and has to stay exactly that.** Every golden in
  /// the repository composites with this block; a default that only nearly
  /// cancels moves thirty reference images by a bit each.
  vec4 look;

  /// The look, the rest. x: vignette, y: vignette roundness, z: grain,
  /// w: the target's aspect, width over height.
  vec4 look_more;

  /// x: dither amount, in display units — 1/255 is one 8-bit step, and 0 is
  /// off exactly. y: white balance, warm above zero. z: tint, green against
  /// magenta. w: unclaimed.
  ///
  /// **A fifth block rather than a spare component of a fourth**, because the
  /// other four are full and because a number that means "one output step"
  /// does not belong beside three that mean "a look". Neutral is
  /// (0, 0, 0, 0) and must stay exactly that: every golden in the repository
  /// goes through this block.
  vec4 output_encode;

  /// Lift, in xyz — what is added, so it moves the shadows and leaves white
  /// where it was. w: unclaimed. Neutral is (0, 0, 0, 0).
  vec4 lift;

  /// Gamma, in xyz — the exponent, so it moves the midtones and leaves both
  /// ends. w: unclaimed. Neutral is (1, 1, 1, 0).
  vec4 gamma;

  /// Gain, in xyz — what is multiplied, so it moves the highlights and leaves
  /// black where it was. w: unclaimed. Neutral is (1, 1, 1, 0).
  vec4 gain;

  /// x: how much of the contact shadow reaches the picture, nought to one —
  /// `gfx-76n`. y: the display transform's entries per axis, its N — `L2`;
  /// read only when the curve is 6. z: one when the occlusion buffer carries
  /// indirect light in rgb as well — `L5`'s SSIL — nought otherwise.
  /// w unclaimed.
  ///
  /// Appended after everything else, the way this block has grown before: a
  /// std140 block is laid out in declaration order, so adding here leaves every
  /// offset above unchanged and the four backends do not have to agree about
  /// anything they had not already agreed on.
  vec4 contact;
}
composite_info;

/// Rec. 709 luma, which is what the sRGB primaries weight to.
float Luma(vec3 color) { return dot(color, vec3(0.2126, 0.7152, 0.0722)); }

/// A value in [0, 1) from a screen position, with no state and no frame count.
///
/// Static by construction: a shader that read a frame counter would produce a
/// different golden on every run, so the grain is fixed to the pixel. See
/// `LookSettings.grain`, which says the same thing from the other side.
float Hash(vec2 at) {
  return fract(sin(dot(at, vec2(12.9898, 78.233))) * 43758.5453);
}

/// One cell of a 4x4 Bayer matrix, as a value in [-0.5, 0.5).
///
/// **Ordered rather than random, and that is the whole choice.** The grain
/// above already uses a hash, and a hash here would work — but blue-ish noise
/// on a flat gradient reads as noise, where an ordered matrix reads as a
/// gradient. The pattern repeats every four pixels and is fixed to screen
/// position, so it is as golden-stable as the grain is and for the same
/// reason: nothing here is a function of time.
///
/// The matrix is the standard recursive one, written out because computing it
/// costs more than reading it.
float BayerCell(vec2 at) {
  int x = int(mod(at.x, 4.0));
  int y = int(mod(at.y, 4.0));
  int index = y * 4 + x;
  // 0, 8, 2, 10 / 12, 4, 14, 6 / 3, 11, 1, 9 / 15, 7, 13, 5
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
  return value / 16.0 - 0.5;
}

vec3 LinearToSrgb(vec3 linear) {
  return mix(
      linear * 12.92,
      1.055 * pow(max(linear, vec3(0.0)), vec3(1.0 / 2.4)) - vec3(0.055),
      step(vec3(0.0031308), linear));
}

/// The inverse of [LinearToSrgb], for the colour a LUT hands back.
vec3 SrgbToLinear(vec3 encoded) {
  return mix(
      encoded / 12.92,
      pow((max(encoded, vec3(0.0)) + vec3(0.055)) / 1.055, vec3(2.4)),
      step(vec3(0.04045), encoded));
}

/// Khronos PBR Neutral tone mapper.
///
/// The mapper the glTF ecosystem settled on, which matters because the renderer
/// targets glTF materials — the same asset should not look different here than
/// in a reference viewer. It leaves everything below the compression threshold
/// untouched, so midtones keep their values and only highlights roll off. That
/// is the property a filmic curve like ACES lacks: ACES would darken the whole
/// image to tame one highlight.
vec3 TonemapNeutral(vec3 color) {
  const float kStartCompression = 0.8 - 0.04;
  const float kDesaturation = 0.15;

  float minChannel = min(color.r, min(color.g, color.b));
  float offset =
      minChannel < 0.08 ? minChannel - 6.25 * minChannel * minChannel : 0.04;
  color -= offset;

  float peak = max(color.r, max(color.g, color.b));
  if (peak < kStartCompression) return color;

  const float d = 1.0 - kStartCompression;
  float newPeak = 1.0 - d * d / (peak + d - kStartCompression);
  color *= newPeak / peak;

  float desaturate = 1.0 - 1.0 / (kDesaturation * (peak - newPeak) + 1.0);
  return mix(color, vec3(newPeak), desaturate);
}

/// ACES, the Narkowicz fit.
///
/// **It lifts the midtones, and that is why it is offered rather than
/// imposed.** Measured rather than recited: 18% grey comes out at 0.267 where
/// the neutral curve leaves it at 0.140, because this fit carries roughly a
/// stop of exposure inside it — the RRT and ODT it approximates were never
/// meant to be fed display-referred values. The result is the brighter,
/// contrastier image people recognise from film, and it is also exactly why
/// it is wrong as a default here: a glTF asset is authored against a
/// reference viewer, and a curve that moves the midtones moves the asset away
/// from how its author saw it.
///
/// The three-term rational fit rather than the full RRT/ODT: the matrices in
/// front and behind cost more than the curve is worth at this end of the
/// pipeline. Its own ceiling arrives early — everything above about 7.2 comes
/// out at exactly one, so two different highlights an artist can tell apart
/// become one flat patch. [TonemapAgx] is the answer to that.
vec3 TonemapAces(vec3 color) {
  const float a = 2.51;
  const float b = 0.03;
  const float c = 2.43;
  const float d = 0.59;
  const float e = 0.14;
  return clamp((color * (a * color + b)) / (color * (c * color + d) + e),
               vec3(0.0), vec3(1.0));
}

/// AgX's log-encoded sigmoid, one channel at a time.
///
/// Its output is display-encoded (roughly a 2.2 gamma), not linear. That is
/// the fact the first version of this curve missed: it handed the sigmoid's
/// value straight to the sRGB encode at the end of `main`, so every AgX frame
/// was encoded twice — 18% grey arrived at 187/255 instead of 128/255 and a
/// saturated red came out pastel. [TonemapAgx] linearises it again.
vec3 AgxSigmoid(vec3 color) {
  const float kMinEv = -12.47393;
  const float kMaxEv = 4.026069;

  vec3 v = clamp(log2(max(color, vec3(1e-10))), vec3(kMinEv), vec3(kMaxEv));
  v = (v - vec3(kMinEv)) / (kMaxEv - kMinEv);

  // A sixth-order fit of AgX's own sigmoid, which is the part that does the
  // work: gentle through the middle, long shoulders at both ends.
  vec3 v2 = v * v;
  vec3 v4 = v2 * v2;
  v = 15.5 * v4 * v2 - 40.14 * v4 * v + 31.96 * v4 - 6.868 * v2 * v +
      0.4298 * v2 + 0.1191 * v - 0.00232;
  return clamp(v, vec3(0.0), vec3(1.0));
}

/// AgX: inset, sigmoid, outset, linearise — Wrensch's "Minimal AgX".
///
/// **What it is for: bright saturated light that does not turn into a flat
/// disc of colour.** The inset matrix mixes a little of each channel into the
/// others before the curve, so no channel is compressed alone and a hue that
/// is over-bright walks towards white rather than through another primary;
/// the outset matrix takes the mixing back out afterwards.
///
/// **Linear in, linear out**, like every other curve here, so the sRGB encode
/// at the end of `main` is the only encode. The `pow(2.2)` is the reference
/// implementation's own last step ("we're linearizing the output here"); the
/// default look is the identity, so there is no extra desaturation — the
/// `mix(luma, v, 0.84)` this curve used to end with was not AgX's and took a
/// sixth of the saturation off the whole frame.
///
/// The matrices are the published AgX ones, written out rather than derived,
/// and they are inverses to about six decimal places — checked as arithmetic
/// in `tonemap_curve_test.dart` rather than trusted, because a transposed row
/// here would look like a subtle grade rather than like a bug.
vec3 TonemapAgx(vec3 color) {
  // The published pair, written in the same layout and used in the same order
  // as the reference implementation — `M * v`, with the literals as that
  // implementation lists them. Taken as a matched pair on purpose: an inset
  // from one variant beside an outset from another is a matrix product that is
  // *nearly* the identity, which reads as a grade nobody asked for rather than
  // as a mistake.
  const mat3 kInset = mat3(
      0.842479062253094, 0.0423282422610123, 0.0423756549057051,
      0.0784335999999992, 0.878468636469772, 0.0784336,
      0.0792237451477643, 0.0791661274605434, 0.879142973793104);
  const mat3 kOutset = mat3(
      1.19687900512017, -0.0528968517574562, -0.0529716355144438,
      -0.0980208811401368, 1.15190312990417, -0.0980434501171241,
      -0.0990297440797205, -0.0989611768448433, 1.15107367264116);

  vec3 v = AgxSigmoid(kInset * max(color, vec3(0.0)));
  // Out of the wider gamut, then back to linear. The outset can push a
  // channel a little below zero on a colour that was already at the edge,
  // which the `max` keeps out of `pow`; anything above display white is
  // display white.
  v = kOutset * v;
  return clamp(pow(max(v, vec3(0.0)), vec3(2.2)), vec3(0.0), vec3(1.0));
}

/// The same transform as [TonemapAgx], kept for code 5 — `gfx-26n`.
///
/// It was added as the rotated variant when [TonemapAgx] was the bare
/// sigmoid. Now that [TonemapAgx] is the whole of AgX, the two codes draw
/// the same picture; the code stays so a setting that names it keeps working.
vec3 TonemapAgxFull(vec3 color) {
  return TonemapAgx(color);
}

/// Reinhard, extended so that white maps to white.
///
/// The plain `c / (1 + c)` never reaches one, so a sky that should clip to
/// paper white comes out grey; the extension takes the value that *should*
/// become white and normalises to it. Here that value is 4 — two stops over
/// display white — which is the point past which this engine's bloom has
/// taken over anyway.
///
/// **Clamped, because the extension keeps climbing past its own white
/// point.** The curve maps 4 to exactly one and 40 to 3.4, which is not a
/// tone mapper's job: anything above white is white. Without the clamp the
/// only thing bounding the output is the sRGB encode at the very end, and a
/// curve whose contract is "this fits on a display" should be the thing that
/// makes it fit.
///
/// Kept because it is the plainest of the four and the one everything else
/// gets compared against.
vec3 TonemapReinhard(vec3 color) {
  const float kWhite = 4.0;
  vec3 numerator = color * (vec3(1.0) + color / vec3(kWhite * kWhite));
  return clamp(numerator / (vec3(1.0) + color), vec3(0.0), vec3(1.0));
}

/// [color] through whichever curve [curve] names.
///
/// A chain of comparisons rather than a `switch`: the number is a uniform,
/// so every backend takes the same branch for a whole frame, and `switch` on
/// a non-constant is the construct that has needed a workaround on one
/// backend or another every time it has been used here.
/// [color] looked up in the colour table, which holds `size` slices.
///
/// **A strip, not a 3D texture**, because three of the four backends this
/// engine runs on either have no 3D sampler or have one that costs a
/// capability check — and a strip is an ordinary 2D image an artist can open,
/// which is how every grading tool exports one anyway.
///
/// The blue axis picks a pair of neighbouring slices and mixes between them;
/// red and green come out of the sampler's own bilinear filtering inside a
/// slice. The half-texel inset on red is what keeps the first and last
/// entries reachable: without it the ends of the ramp are never sampled and a
/// table that should be an identity darkens white.
vec3 SampleLut(vec3 color, float size) {
  vec3 c = clamp(color, vec3(0.0), vec3(1.0));

  float sliceWidth = 1.0 / size;
  float texel = 1.0 / (size * size);
  float innerWidth = texel * (size - 1.0);

  float u = texel * 0.5 + c.r * innerWidth;
  float v = (0.5 / size) + c.g * ((size - 1.0) / size);

  float slice = c.b * (size - 1.0);
  float lower = floor(slice);
  float upper = min(lower + 1.0, size - 1.0);

  vec3 a = texture(lut_texture, vec2(lower * sliceWidth + u, v)).rgb;
  vec3 b = texture(lut_texture, vec2(upper * sliceWidth + u, v)).rgb;
  return mix(a, b, slice - lower);
}

/// [color] through the display transform — `L2`: shaped to log2 stops about
/// 0.18 over −10…+6, then looked up in the strip exactly as [SampleLut]
/// looks up the grade. Scene-linear in, display-linear out, which is what a
/// tone curve returns.
vec3 SampleDisplay(vec3 color) {
  float size = max(composite_info.contact.y, 2.0);
  vec3 c = clamp((log2(max(color, vec3(1e-10)) / 0.18) + 10.0) / 16.0,
                 vec3(0.0), vec3(1.0));

  float sliceWidth = 1.0 / size;
  float texel = 1.0 / (size * size);
  float innerWidth = texel * (size - 1.0);

  float u = texel * 0.5 + c.r * innerWidth;
  float v = (0.5 / size) + c.g * ((size - 1.0) / size);

  float slice = c.b * (size - 1.0);
  float lower = floor(slice);
  float upper = min(lower + 1.0, size - 1.0);

  vec3 a = texture(display_texture, vec2(lower * sliceWidth + u, v)).rgb;
  vec3 b = texture(display_texture, vec2(upper * sliceWidth + u, v)).rgb;
  return mix(a, b, slice - lower);
}

vec3 TonemapBy(vec3 color, int curve) {
  if (curve == 6) return SampleDisplay(color);
  if (curve == 1) return TonemapNeutral(color);
  if (curve == 2) return TonemapAces(color);
  if (curve == 3) return TonemapAgx(color);
  if (curve == 4) return TonemapReinhard(color);
  if (curve == 5) return TonemapAgxFull(color);
  return color;
}

void main() {
  // **Dispersion happens at the lens, so it happens at sampling.** Sampling the
  // scene three times at radially offset coordinates is the whole effect; doing
  // it after the tone map would smear an already-compressed image and could not
  // separate the channels of a highlight that had already clipped together.
  //
  // The offset grows from the centre outwards, which is what a real lens does:
  // a ray through the middle of the glass is not dispersed at all.
  float dispersion = composite_info.look.w;
  vec4 scene;
  if (dispersion > 0.0) {
    vec2 fromCentre = v_uv - vec2(0.5);
    vec2 step_uv = fromCentre * dispersion;
    scene = texture(scene_texture, v_uv);
    scene.r = texture(scene_texture, v_uv + step_uv).r;
    scene.b = texture(scene_texture, v_uv - step_uv).b;
  } else {
    scene = texture(scene_texture, v_uv);
  }
  vec3 bloom = texture(bloom_texture, v_uv).rgb;

  // Four taps in a 2×2, which is not a general-purpose blur: the occlusion pass
  // rotates its kernel by the parity of the pixel, leaving a 2×2 pattern, and
  // this averages exactly that away. The size is derived from the artefact
  // rather than tuned against it, so the two have to move together — widening
  // one without the other either leaves the pattern or smears the contact
  // shadows this whole pass exists to draw.
  vec2 half_texel = composite_info.ao_texel.xy * 0.5;
  vec4 occlusion = 0.25 * (texture(ao_texture, v_uv + vec2(half_texel.x, half_texel.y)) +
                           texture(ao_texture, v_uv + vec2(-half_texel.x, half_texel.y)) +
                           texture(ao_texture, v_uv + vec2(half_texel.x, -half_texel.y)) +
                           texture(ao_texture, v_uv + vec2(-half_texel.x, -half_texel.y)));
  // The share left open is in a; the occlusion methods write it into every
  // channel, and the indirect one keeps its light in rgb.
  float ao = occlusion.a;
  // Lerped towards one by the strength, so "off" is exactly one and multiplies
  // nothing — every golden in the repository depends on that being exact rather
  // than nearly so.
  ao = mix(1.0, ao, clamp(composite_info.params.w, 0.0, 1.0));

  // **The contact shadow, folded into the same multiplier — `gfx-76n`.** Its
  // own strength, because it answers a different question from the occlusion:
  // one is how enclosed a point is and the other is whether the sun reaches
  // it, and a scene wants them at different amounts. Its own `mix` for the
  // reason the line above has one — "off" has to be a multiplier of exactly
  // one, which every golden in this repository depends on.
  //
  // Full resolution rather than the occlusion's half, so no four-tap average:
  // the whole point of a contact shadow is the first few centimetres at the
  // join, and a half-resolution one is the seam it exists to draw, blurred
  // away.
  float contact = texture(contact_shadow_texture, v_uv).r;
  ao *= mix(1.0, contact, clamp(composite_info.contact.x, 0.0, 1.0));

  // Applied to the scene and **not** to the bloom, which is the whole reason
  // this lives in the composite rather than in a pass that reads and rewrites
  // the HDR colour. Multiplying before bloom would take the glow out of a lit
  // crack along with the ambient, and a crack that stops glowing is a worse
  // error than a crack that stays bright.
  //
  // The cost, stated rather than left to be discovered: this multiplies the
  // *sum* of the light, not the indirect part of it alone. Separating them
  // would mean a third attachment and rewriting all six lit stages. So an
  // emissive strip in a corner dims, which is physically wrong — the same
  // compromise `pbr.frag` already makes with the occlusion map from a glTF.
  vec3 color = scene.rgb * ao + bloom * composite_info.params.y;

  // `L5`: the light that bounced onto the point off what it sees, by the same
  // strength as the occlusion beside it, so a strength of nought is no light
  // added as it is no darkening.
  color += occlusion.rgb * composite_info.contact.z *
           clamp(composite_info.params.w, 0.0, 1.0);

  // Exposure before the tone map, so it behaves like a camera stop — it moves
  // which part of the scene's range lands in the mapper's shoulder instead of
  // stretching an already-compressed image.
  color *= max(composite_info.params.x, 0.0);

  color = TonemapBy(color, int(composite_info.params.z + 0.5));

  // **After the tone map, and that is the point.** Grading is a decision about
  // an image somebody can see; applied to unbounded scene-referred colour it
  // would be pulling on values the display will never show anyway.
  float contrast = composite_info.look.x;
  float saturation = composite_info.look.y;
  float temperature = composite_info.look.z;

  // Pivoted about mid grey, so contrast does not double as an exposure knob —
  // and mid grey here is 0.18, not 0.5: this is linear light, where 0.5 is a
  // bright highlight, and pivoting on it darkened a 1.2 contrast by about a
  // stop. A power about 0.18 rather than a line through it, so black stays
  // black and grey stays exactly where it was. One is the identity.
  if (contrast != 1.0) {
    color = vec3(0.18) * pow(max(color, vec3(0.0)) / 0.18, vec3(contrast));
  }
  color = mix(vec3(Luma(color)), color, saturation);
  // A gain on the ends against the middle. Not a white-balance conversion —
  // a scene lit at the wrong temperature is fixed at the light, not here.
  // `white_balance` below is the conversion, and the two are deliberately
  // separate: this one is a look, that one is a correction.
  color *= vec3(1.0 + temperature * 0.1, 1.0, 1.0 - temperature * 0.1);

  // **Lift, gamma, gain — `gfx-27n`, and the three ranges a colourist
  // actually reaches for.** Contrast and saturation move the whole picture at
  // once; these move one end of it. Lift raises black towards itself and
  // leaves white where it was — `c * (1 - lift) + lift`, the classic form;
  // it used to be a plain add, which moved white to one plus the lift and
  // clipped it. Gain multiplies, so it moves the highlights and
  // leaves black alone. Gamma is the exponent between them, so it moves the
  // midtones and leaves both ends. Applied in that order, which is the order
  // they are named in and the order a grading panel applies them.
  //
  // Each is a vec3, not a scalar: the whole reason to have them is a warm
  // highlight over a cool shadow, which one number per stage cannot say.
  vec3 lift = composite_info.lift.xyz;
  vec3 gammaCurve = composite_info.gamma.xyz;
  vec3 gain = composite_info.gain.xyz;
  color = color * (vec3(1.0) - lift) + lift;
  // Guarded, because a channel at zero under a fractional exponent is a
  // divide by zero on some drivers and a black pixel on others, and the
  // defaults have to be an exact identity rather than nearly one.
  color = max(color, vec3(0.0));
  if (gammaCurve != vec3(1.0)) color = pow(color, vec3(1.0) / gammaCurve);
  color *= gain;

  // **White balance, which the temperature above is not.** A gain on red
  // against blue is a look; this is the correction — a shift along the
  // warm-to-cool axis with a green-magenta tint across it, the pair every
  // camera and every grading panel offers together. Approximated in the
  // display space rather than converted through a chromatic adaptation
  // matrix: the exact transform wants the scene's own white point, and this
  // pass has the picture rather than the light that made it.
  float balance = composite_info.output_encode.y;
  float tint = composite_info.output_encode.z;
  if (balance != 0.0 || tint != 0.0) {
    color *= vec3(
        1.0 + balance * 0.20,
        1.0 + tint * 0.15,
        1.0 - balance * 0.20);
    // The tint takes its green out of the other two rather than adding light,
    // so a tint alone changes the hue and not the level.
    color.r -= tint * 0.075;
    color.b -= tint * 0.075;
  }

  // **The table goes after the grade and before the barrel**, which is where
  // a grading suite puts it: a LUT is somebody's finished look, so it should
  // see the contrast and saturation decisions rather than have them applied
  // on top of it — and it should not see the vignette or the grain, which
  // belong to the lens and the film rather than to the colour.
  //
  // Branched on the strength rather than mixed by it, so a frame with no
  // table does not sample one. The branch is on a uniform, so the whole draw
  // takes the same side of it.
  //
  // **Indexed and answered in sRGB**, which is the space a grading tool's
  // `.cube` is written in: Resolve and Photoshop export a table that takes a
  // display-encoded colour and gives one back. Looked up with linear values it
  // shifted every tone, and put nearly everything below a linear 0.03 into
  // the first of 33 slices.
  float lutStrength = composite_info.ao_texel.z;
  if (lutStrength > 0.0) {
    vec3 encodedIn = LinearToSrgb(clamp(color, vec3(0.0), vec3(1.0)));
    vec3 graded = SrgbToLinear(
        SampleLut(encodedIn, max(composite_info.ao_texel.w, 2.0)));
    color = mix(color, graded, clamp(lutStrength, 0.0, 1.0));
  }

  // The barrel and the film, last, and in that order: a vignette darkens what
  // the grain then lands on, which is the way round a camera does it.
  float vignette = composite_info.look_more.x;
  if (vignette > 0.0) {
    vec2 fromCentre = v_uv - vec2(0.5);
    // **The aspect has to be in the uniform for this to mean anything.** UV
    // space is square and the frame is not, so a falloff computed on UV alone
    // is an ellipse on screen. Roundness 1 undoes that and keeps the vignette
    // circular; 0 lets it follow the frame and reach the short edges first.
    float aspect = max(composite_info.look_more.w, 1e-4);
    fromCentre.x *= mix(1.0, aspect, composite_info.look_more.y);
    float radius = length(fromCentre) * 1.41421356;
    color *= mix(1.0, 1.0 - vignette, clamp(radius, 0.0, 1.0));
  }

  // **Grain and dither are both after the encode, and for the same reason.**
  // Banding is a quantisation artefact of the 8-bit target, so the noise that
  // breaks it up has to be the size of one output step: a fixed distance in
  // display space and a wildly varying one in linear space, where a step near
  // black is a thousandth of a step near white.
  vec3 encoded = LinearToSrgb(max(color, vec3(0.0)));

  // **This used to be added in linear light, and the comment on it was
  // wrong.** It said the noise was centred on zero so grain neither lifts nor
  // lowers the average level. Symmetric in linear it was; symmetric by the
  // time anybody saw it, it was not. `max(color, 0.0)` clipped the negative
  // half, and the sRGB encode then stretched what was left: at a grain of
  // 0.08 on black, the surviving half ran up to a linear 0.04, which encodes
  // to 56 of 255. Measured over the `look` parity fixture, the darkest cell
  // sat at 14 instead of 0, across a picture that is 188 cells of black.
  //
  // In display space the two halves are the same size, nothing is clipped
  // before the average is taken, and the sentence above is finally true. What
  // it costs is that the amount means something different: 0.08 is now eight
  // percent of the output range rather than of the light, which is what a
  // film grain control has always meant on every other tool.
  float grain = composite_info.look_more.z;
  if (grain > 0.0) encoded += vec3((Hash(TargetFragCoord()) - 0.5) * grain);

  // Dither last, because it is the one aimed at the quantiser itself.
  // **Centred exactly.** The cells run from -1/2 to 7/16, whose mean is
  // -1/32; the thirty-second puts it at nought, so with dithering on by
  // default (0.7.4) a flat colour stays the colour it was and only where a
  // gradient's bands fall changes.
  float dither = composite_info.output_encode.x;
  if (dither > 0.0) {
    encoded += vec3((BayerCell(TargetFragCoord()) + 0.03125) * dither);
  }

  frag_color = vec4(encoded, scene.a);
}
