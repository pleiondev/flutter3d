#version 460 core

// The last pass: add the bloom, tone map, encode to sRGB.
//
// Tone mapping lives here rather than in each lighting model, which is the
// point of having an HDR target at all. Applying it per model meant every
// shader wrote display-referred colour into an 8-bit buffer, so anything above
// display white was gone before post-processing could see it — and bloom is
// entirely a function of what is above display white.
precision highp float;

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

/// The colour table, as a strip: N slices of N×N laid out left to right, so
/// the image is N² wide and N tall. Bound to whatever the engine has when no
/// table is set — the strength is zero then and nothing samples it, but a
/// sampler this shader declares and nobody binds is a native crash on Metal
/// rather than a black texture, which is the same rule `ao_texture` above
/// already follows.
uniform sampler2D lut_texture;

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
  /// off exactly. y, z, w: unclaimed.
  ///
  /// **A fifth block rather than a spare component of a fourth**, because the
  /// other four are full and because a number that means "one output step"
  /// does not belong beside three that mean "a look". Neutral is
  /// (0, 0, 0, 0) and must stay exactly that: every golden in the repository
  /// goes through this block.
  vec4 output_encode;
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

/// AgX, as a curve without the rotation matrices.
///
/// **What it is for: bright saturated light that does not turn into a flat
/// disc of colour.** A coloured lamp four stops over white comes out of ACES
/// with its channels 0.36 apart and out of this with 0.22 — the highlight
/// walks towards white rather than towards its own primary. And it keeps
/// separating values long after ACES has stopped: at 8 and at 40 ACES returns
/// one and one, where this returns 0.971 and 0.999, so the inside of a bright
/// patch still has shape in it.
///
/// **It is a much more exposed curve than the other three**, which is a
/// decision to make with open eyes rather than a side effect: 18% grey lands
/// at 0.50 here against 0.14 through the neutral curve, because AgX is built
/// to put middle grey at middle display and the log encoding below does
/// exactly that. A scene switched to this without re-lighting looks washed
/// out, and correctly so.
///
/// A log-encoded sigmoid on each channel, then a pull towards the luminance
/// by how far each channel climbed. The full transform rotates into and out
/// of a wider gamut first; that rotation is what keeps deep blues from going
/// purple, and it needs two matrices this pass has nowhere to keep. Named as
/// missing rather than implied: this is AgX's curve, not AgX.
vec3 TonemapAgx(vec3 color) {
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
  v = clamp(v, vec3(0.0), vec3(1.0));

  // The desaturation AgX is known for, applied where the curve lifted the
  // most. Without it the sigmoid alone leaves highlights as saturated as ACES
  // does and the point of the curve is lost.
  float luma = Luma(v);
  return mix(vec3(luma), v, 0.84);
}

/// AgX with the rotation this pass used to have nowhere to keep — `gfx-26n`.
///
/// **What the two matrices buy, and it is one specific thing.** [TonemapAgx]
/// compresses each channel on its own, so a channel that clips takes its hue
/// with it: a deep blue four stops over white loses blue last and arrives at
/// the display having drifted through purple, because red and green were
/// driven up towards it while blue was already at the ceiling. The inset
/// matrix mixes a little of each channel into the others *before* the curve,
/// which means no channel is ever compressed alone, and the outset matrix —
/// its inverse — takes the mixing back out afterwards. The hue that comes out
/// is the hue that went in. That is the whole of the rotation, and it is why
/// the comment on [TonemapAgx] named the absence rather than implying the
/// curve was the transform.
///
/// **A fifth curve rather than a correction to the fourth.** Every golden in
/// this repository that names a curve names one of the four codes, and 18%
/// grey lands in a different place through the rotation than through the bare
/// sigmoid — so quietly improving `agx` would move pictures somebody recorded
/// on purpose. `agx` stays exactly the curve it was, and this is the one to
/// reach for when a hue has to survive being over-bright.
///
/// The matrices are the published AgX ones, written out rather than derived,
/// and they are inverses to about six decimal places — checked as arithmetic
/// in `tonemap_curve_test.dart` rather than trusted, because a transposed row
/// here would look like a subtle grade rather than like a bug.
vec3 TonemapAgxFull(vec3 color) {
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

  vec3 v = kInset * color;
  v = TonemapAgx(v);
  // Out of the wider gamut, then clamped: the outset can push a channel a
  // little past one or a little below zero on a colour that was already at
  // the edge, and anything above display white is display white.
  return clamp(kOutset * v, vec3(0.0), vec3(1.0));
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

vec3 TonemapBy(vec3 color, int curve) {
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
  float ao = 0.25 * (texture(ao_texture, v_uv + vec2(half_texel.x, half_texel.y)).r +
                     texture(ao_texture, v_uv + vec2(-half_texel.x, half_texel.y)).r +
                     texture(ao_texture, v_uv + vec2(half_texel.x, -half_texel.y)).r +
                     texture(ao_texture, v_uv + vec2(-half_texel.x, -half_texel.y)).r);
  // Lerped towards one by the strength, so "off" is exactly one and multiplies
  // nothing — every golden in the repository depends on that being exact rather
  // than nearly so.
  ao = mix(1.0, ao, clamp(composite_info.params.w, 0.0, 1.0));

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

  // Pivoted about mid grey, so contrast does not double as an exposure knob.
  color = (color - vec3(0.5)) * contrast + vec3(0.5);
  color = mix(vec3(Luma(color)), color, saturation);
  // A gain on the ends against the middle. Not a white-balance conversion —
  // a scene lit at the wrong temperature is fixed at the light, not here.
  color *= vec3(1.0 + temperature * 0.1, 1.0, 1.0 - temperature * 0.1);

  // **The table goes after the grade and before the barrel**, which is where
  // a grading suite puts it: a LUT is somebody's finished look, so it should
  // see the contrast and saturation decisions rather than have them applied
  // on top of it — and it should not see the vignette or the grain, which
  // belong to the lens and the film rather than to the colour.
  //
  // Branched on the strength rather than mixed by it, so a frame with no
  // table does not sample one. The branch is on a uniform, so the whole draw
  // takes the same side of it.
  float lutStrength = composite_info.ao_texel.z;
  if (lutStrength > 0.0) {
    vec3 graded = SampleLut(color, max(composite_info.ao_texel.w, 2.0));
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

  float grain = composite_info.look_more.z;
  // Centred on zero so grain neither lifts nor lowers the average level, and
  // added rather than multiplied so it stays visible in the shadows, which is
  // where film grain lives.
  if (grain > 0.0) color += vec3((Hash(gl_FragCoord.xy) - 0.5) * grain);

  // **Dither is the last thing that happens, and it happens after the sRGB
  // encode on purpose.** Banding is a quantisation artefact of the 8-bit
  // target, so the noise that breaks it up has to be the size of one output
  // step — which is a fixed distance in display space and a wildly varying
  // one in linear space, where a step near black is a thousandth of a step
  // near white. Dithering before the encode would put most of the noise where
  // the banding is not.
  vec3 encoded = LinearToSrgb(max(color, vec3(0.0)));
  float dither = composite_info.output_encode.x;
  if (dither > 0.0) encoded += vec3(BayerCell(gl_FragCoord.xy) * dither);

  frag_color = vec4(encoded, scene.a);
}
