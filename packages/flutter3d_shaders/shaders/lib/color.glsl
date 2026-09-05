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

/// Where this fragment is in the level's lightmap. Zero from every vertex
/// stage but `mesh_lightmapped.vert`, and read only by the lit models, which
/// sample a one-texel black there when a material has no map.
in vec2 v_lightmap_uv;

out vec4 frag_color;

// The second attachment: what a screen-space effect needs to know about the
// surface it is looking at. World-space normal in rgb, and in a the depth along
// the view axis in world metres — not a window depth; `WriteSurfaceGeometry`
// says at length why not.
//
// Depth travels here rather than in a depth texture because flutter_gpu cannot
// sample one — the same reason the shadow pass writes its depth into a colour
// target. See ARCHITECTURE.md §2.
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

/// Where a debug pass leaves the picture it wants shown instead of the normal.
///
/// Declared here, in the header every lit shader includes **first**, and
/// written from surface.glsl, which is included after. The alternative was a
/// new member on a shared uniform block; a global costs nothing and moves no
/// offsets. It is read at the moment the surface buffer is written, which
/// happens after the lighting loop has run, so the value is there by then.
vec3 g_debug_surface = vec3(0.0);
bool g_debug_surface_on = false;

/// Distance fog, in its own block rather than folded into FragInfo.
///
/// Its own because color.glsl is included before FragInfo is declared, and
/// because appending to a block that half a dozen shaders already share is a
/// way to move offsets nobody expected to move. Three vec4s is a cheap price
/// for not touching any of that.
uniform FogInfo {
  /// rgb: linear fog colour. w: density per metre, zero for no fog.
  vec4 fog;

  /// xyz: camera position in world space. Duplicated from FragInfo so this
  /// block stands alone; a vec3 is cheaper than a coupling.
  vec4 eye;

  /// xyz: the direction the camera looks, as a unit vector in world space.
  /// w unused.
  ///
  /// Here rather than in a block of its own because it answers the same
  /// question [eye] does — where the camera is and which way it faces — and
  /// this is the block `color.glsl` can see.
  vec4 forward;
}
fog_info;

/// How far this fragment is from the eye, in world metres.
///
/// What the fog fades by. Distance rather than depth, because fog is a
/// property of the air between two points and does not care which way the
/// camera happens to face.
float EyeDistance() { return distance(v_world_position, fog_info.eye.xyz); }

/// How far this fragment is *along the view axis*, in world metres.
///
/// What the surface buffer's alpha holds. Depth rather than distance, and the
/// difference only shows on an orthographic camera — where the rays through
/// the pixels are parallel instead of meeting at the eye, so a distance from
/// the eye names a sphere that the pixel's ray crosses somewhere the reader
/// cannot solve for. A depth along the axis names a plane, which every ray
/// crosses exactly once. See `WorldAtDepth` in `post/ssao.frag` for the
/// reconstruction both projections share.
float ViewDepth() {
  return dot(v_world_position - fog_info.eye.xyz, fog_info.forward.xyz);
}

/// Records the geometry of this fragment for whatever runs after the scene.
///
/// Called from the same place that writes colour, so a surface cannot be lit
/// into the frame without also describing itself — which is the failure that
/// leaves a screen-space effect reflecting whatever was in the buffer before.
///
/// rg: octahedral normal. b: perceptual roughness. a: **depth along the view
/// axis, in world metres** — see [ViewDepth].
///
/// **Not `gl_FragCoord.z`, and that is a defect this channel carried until it
/// was looked at.** Window depth crowds every distant surface into the top of
/// its range — with a near plane of a tenth of a metre, everything past twenty
/// metres lives in the last half a hundredth of `[0, 1]` — and this attachment
/// is a half float, whose steps up there are about five ten-thousandths. So two
/// surfaces half a metre apart at twenty metres stored the *same* number, and
/// every screen-space pass that compares against this channel decided whole
/// bands of pixels by rounding. The occlusion pass drew them: vertical stripes
/// along the lines of constant depth on any wall receding from the camera, on
/// both GPU backends. The software rasteriser kept the channel at full
/// precision and drew the effect correctly, so it was the one that looked
/// wrong against the other two.
///
/// A depth in metres has none of that: the exponent carries the range and the
/// mantissa carries the same relative precision everywhere, which at twenty
/// metres is a centimetre. Both numbers are measured in
/// `flutter3d_cpu/test/surface_depth_test.dart`.
///
/// Zero still means nothing was drawn. The attachment is cleared to zero and
/// nothing is drawn in front of the near plane.
void WriteSurfaceGeometry(float roughness) {
#ifndef F3D_NO_SURFACE_BUFFER
  // A debug pass takes the buffer over rather than getting one of its own.
  // The surface buffer already has an attachment, a viewer and a golden; a
  // second one would need all three built before it could answer anything.
  if (g_debug_surface_on) {
    frag_surface = vec4(g_debug_surface, ViewDepth());
    return;
  }
  frag_surface = vec4(EncodeOctahedral(normalize(v_normal)),
                      clamp(roughness, 0.0, 1.0), ViewDepth());
#endif
}

/// Fades [color] toward the fog with distance from the eye.
///
/// Exponential rather than linear, because linear fog has a visible plane
/// where it starts and a dungeon corridor is exactly where that shows.
vec3 ApplyFog(vec3 color) {
  float density = fog_info.fog.w;
  if (density <= 0.0) return color;
  float d = EyeDistance();
  return mix(fog_info.fog.rgb, color, clamp(exp(-density * d), 0.0, 1.0));
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
  frag_color = vec4(ApplyFog(linearColor), alpha);
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
