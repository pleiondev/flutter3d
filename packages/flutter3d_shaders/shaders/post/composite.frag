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

uniform CompositeInfo {
  /// x: exposure, y: bloom intensity, z: 1 to tone map, w: how much of the
  /// occlusion to apply, 0 for none.
  vec4 params;

  /// x, y: one texel of the ao texture. z, w unused.
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

  if (composite_info.params.z > 0.5) color = TonemapNeutral(color);

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

  frag_color = vec4(LinearToSrgb(max(color, vec3(0.0))), scene.a);
}
