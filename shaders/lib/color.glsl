// Colour space helpers and the fragment output interface.
//
// Split out of surface.glsl so a shader that needs no material inputs — the
// normals debug view — can avoid DECLARING the FragInfo uniform block at all.
// That matters more than it looks: reflection metadata reports a block as
// present merely because it was declared, even when the compiled shader binds
// no such buffer, so a declared-but-unused block is indistinguishable from a
// used one until Metal crashes on the bind.

#ifndef COLOR_GLSL_
#define COLOR_GLSL_

precision highp float;

const float kPi = 3.14159265359;

// One varying set shared by every fragment shader, matching mesh.vert.
//
// All five are declared here, including the two the debug models never read: a
// fragment shader whose `in` block disagrees with the vertex shader's `out`
// block fails to link, and there is no partial-match rule to lean on.
in vec3 v_world_position;
in vec3 v_normal;
in vec2 v_texcoord;
in vec4 v_tangent;
in vec4 v_color;

out vec4 frag_color;

/// sRGB to linear. Textures are authored in sRGB, but lighting is only correct
/// in linear space; skipping this is what makes naive renderers look muddy.
vec3 SrgbToLinear(vec3 srgb) {
  return mix(
      srgb / 12.92,
      pow((srgb + vec3(0.055)) / 1.055, vec3(2.4)),
      step(vec3(0.04045), srgb));
}

/// Linear to sRGB. The render target is a plain UNorm format rather than an
/// sRGB one, so the encode has to happen here.
vec3 LinearToSrgb(vec3 linear) {
  return mix(
      linear * 12.92,
      1.055 * pow(linear, vec3(1.0 / 2.4)) - vec3(0.055),
      step(vec3(0.0031308), linear));
}

/// Khronos PBR Neutral tone mapper.
///
/// Physically based shading produces values above 1: a specular highlight at a
/// grazing angle easily reaches 10x display white, and without tone mapping it
/// clips to a flat white patch. This is the mapper the glTF ecosystem settled on,
/// which matters because the renderer targets glTF materials — the same asset
/// should not look different here than in a reference viewer.
///
/// It leaves everything below the compression threshold untouched, so midtones
/// keep their values and only highlights roll off. That is the property a
/// filmic curve like ACES lacks: ACES would darken the whole image to tame one
/// highlight.
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

/// Writes a lit result: apply exposure, tone map, then encode to sRGB.
///
/// Alpha is passed through untouched. Tone mapping is a transform on light, and
/// coverage is not light — running opacity through the curve would make a
/// half-transparent surface change how transparent it is with the exposure
/// slider.
///
/// Exposure is a multiply in linear space applied *before* the tone map, which is
/// what makes it behave like a camera stop rather than a brightness slider: it
/// moves which part of the scene's range lands in the mapper's shoulder, instead
/// of stretching an already-compressed image.
///
/// Without it the mapper's headroom goes unused — a scene whose brightest value
/// sits at linear 0.6 never reaches display white, and the result reads as
/// under-exposed even though nothing is clipping.
void WriteSurface(vec3 linearColor, float exposure, float alpha) {
  frag_color =
      vec4(LinearToSrgb(TonemapNeutral(linearColor * exposure)), alpha);
}

/// Writes a colour that is already display-referred, skipping the tone map.
///
/// For unlit and debug output: an unlit albedo round-trips sRGB to linear and
/// back, so tone mapping it would change authored colours, and a normal encoded
/// as RGB is not a light value at all.
void WriteDisplayColor(vec3 linearColor, float alpha) {
  frag_color = vec4(LinearToSrgb(linearColor), alpha);
}

#endif  // COLOR_GLSL_
