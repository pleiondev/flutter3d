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

// The second attachment: what a screen-space effect needs to know about the
// surface it is looking at. World-space normal in rgb, window-space depth in a.
//
// Depth travels here rather than in a depth texture because flutter_gpu cannot
// sample one — the same reason the shadow pass writes its depth into a colour
// target. See RESEARCH.md.
//
// Guarded, because not every stage that includes this header draws into a
// two-attachment target. The shadow pass draws into one, and a pipeline
// declaring an output its target has no slot for is a mismatch worth avoiding
// rather than discovering.
#ifndef F3D_NO_SURFACE_BUFFER
layout(location = 1) out vec4 frag_surface;
#endif

/// Octahedral encoding: a unit vector in two channels instead of three.
///
/// Worth the arithmetic because the fourth channel is already spent on depth,
/// and without a free channel there is nowhere to put roughness — which is the
/// difference between a reflection that knows stone from a mirror and one that
/// does not. The error is well under a degree, far below anything a reflection
/// off rough stone would show.
vec2 EncodeOctahedral(vec3 n) {
  n /= abs(n.x) + abs(n.y) + abs(n.z);
  vec2 e = n.xy;
  if (n.z < 0.0) {
    e = (1.0 - abs(n.yx)) * vec2(n.x >= 0.0 ? 1.0 : -1.0,
                                 n.y >= 0.0 ? 1.0 : -1.0);
  }
  return e * 0.5 + 0.5;
}

/// Records the geometry of this fragment for whatever runs after the scene.
///
/// Called from the same place that writes colour, so a surface cannot be lit
/// into the frame without also describing itself — which is the failure that
/// leaves a screen-space effect reflecting whatever was in the buffer before.
///
/// rg: octahedral normal. b: perceptual roughness. a: window depth.
void WriteSurfaceGeometry(float roughness) {
#ifndef F3D_NO_SURFACE_BUFFER
  frag_surface = vec4(EncodeOctahedral(normalize(v_normal)),
                      clamp(roughness, 0.0, 1.0), gl_FragCoord.z);
#endif
}

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

/// Writes scene-referred linear light into the HDR target.
///
/// No tone map and no sRGB encode: those moved into the composite pass, which
/// is the entire point of rendering into `r16g16b16a16Float` first. Applying
/// them here meant every model wrote display-referred colour into an 8-bit
/// buffer, so anything above display white was gone before post-processing
/// could see it — and bloom is a function of exactly that.
///
/// Exposure moved with them, for the same reason: it belongs on the same side
/// of the display transform as the tone map.
void WriteSurface(vec3 linearColor, float alpha, float roughness) {
  frag_color = vec4(linearColor, alpha);
  WriteSurfaceGeometry(roughness);
}

/// For a stage with no material to speak of.
///
/// Fully rough, which is the honest default: a surface that cannot say how
/// polished it is should not be reflected off.
void WriteSurface(vec3 linearColor, float alpha) {
  WriteSurface(linearColor, alpha, 1.0);
}

/// Writes a value that is already display-referred.
///
/// For debug output, where the colour is not a light value at all: a normal
/// encoded as RGB means nothing after a tone curve. Converting to linear here
/// means the composite pass's sRGB encode hands the original back unchanged,
/// provided the view also turns tone mapping and exposure off — which is what
/// `RenderSettings.tonemap` is for.
void WriteDisplayColor(vec3 displayColor, float alpha) {
  frag_color = vec4(SrgbToLinear(displayColor), alpha);
  WriteSurfaceGeometry(1.0);
}

#endif  // COLOR_GLSL_
