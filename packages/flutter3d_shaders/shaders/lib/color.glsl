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

/// The surface's own colour, sRGB-encoded, alpha one where a surface was
/// drawn — `L5`. The third attachment, present only when a pass reads it (the
/// indirect light does) and the device opens three; like the surface buffer,
/// written unconditionally and discarded when absent. Stored in the surface
/// buffer's format rather than eight bits a channel, and `Renderer` says why.
layout(location = 2) out vec4 frag_albedo;
#endif

/// What [frag_albedo] carries: the lit models set it in `ReadSurface`, and a
/// stage that reflects nothing — unlit, the debug views — leaves it black,
/// which is what light bounced onto it would come to.
vec3 g_albedo = vec3(0.0);

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

/// Whether [WriteSurface] weights the colour by its alpha: set by
/// `ReadSurface` for a material that blends, and false for everything else.
///
/// **The blend takes its source as premultiplied**, so a blended surface has
/// to hand it the colour times the alpha — a pane at a fifth of opaque adds a
/// fifth of its light, not all of it. glTF's blend mode is Porter and Duff's
/// over on straight colour, and this is the one place that turns the lit
/// radiance into what that means. An opaque or masked surface keeps its
/// colour whole: its alpha is not a coverage, and nothing blends it.
/// A global for the reason [g_debug_surface] is one.
bool g_premultiply = false;

// **A stage that needs none of this must be able to declare none of it.** On
// Vulkan both stages' descriptors are merged into one set layout, and two
// bindings with the same number in it is not a layout the specification
// allows. A driver may accept it anyway; a Galaxy A55's refuses the pipeline
// with `ErrorUnknown` and no other word, which is how the shadow pass came to
// build everywhere except there — its only uniform block was this one, and it
// landed on the same binding as the vertex stage's first.
#ifndef F3D_NO_FOG

/// Distance fog, in its own block rather than folded into FragInfo.
///
/// Its own because color.glsl is included before FragInfo is declared, and
/// because appending to a block that half a dozen shaders already share is a
/// way to move offsets nobody expected to move. Three vec4s is a cheap price
/// for not touching any of that.
uniform FogInfo {
  /// rgb: linear fog colour. w: density per metre at the eye, zero for no
  /// fog.
  vec4 fog;

  /// xyz: camera position in world space. Duplicated from FragInfo so this
  /// block stands alone; a vec3 is cheaper than a coupling. w: how fast the
  /// fog thins upwards, per metre — `P5`, see [ApplyFog]; nought is flat fog.
  vec4 eye;

  /// xyz: the direction the camera looks, as a unit vector in world space.
  /// w: what a transparent draw writes under weighted blended transparency —
  /// `R8`, see `WriteWeightedBlended`. Zero for every other draw.
  ///
  /// Here rather than in a block of its own because it answers the same
  /// question [eye] does — where the camera is and which way it faces — and
  /// this is the block `color.glsl` can see.
  vec4 forward;

  /// x: one when the camera's projection is orthographic, nought when it is
  /// perspective — `P7`, see [Orthographic]. y, z, w unused. Appended, so
  /// every offset above stays where four backends agree on it.
  vec4 projection;
}
fog_info;

/// Whether the camera is orthographic — `P7`.
///
/// **What every eye-relative quantity has to ask first.** Through a
/// perspective lens the rays meet at the eye, so the way to the eye and the
/// distance to it are the fragment's own; through an orthographic one the
/// rays are parallel and the eye is only where the camera was put along its
/// axis, which moves nothing in the picture. Reading the eye's position as if
/// it were a point the light travels to slides highlights across the frame
/// as the camera pans and lays fog in rings round a point nobody sees.
bool Orthographic() { return fog_info.projection.x > 0.5; }

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

/// How far this fragment is from the eye, in world metres.
///
/// What the fog fades by. Distance rather than depth, because fog is a
/// property of the air between two points and does not care which way the
/// camera happens to face — through a perspective lens. Through an
/// orthographic one every ray starts on the eye's plane, so the air a ray
/// crosses is its depth from that plane, never less than nought.
float EyeDistance() {
  return Orthographic() ? max(ViewDepth(), 0.0)
                        : distance(v_world_position, fog_info.eye.xyz);
}

/// The unit direction from this fragment back along the ray that reached
/// it: to the eye through a perspective lens, against the view axis through
/// an orthographic one — `P7`. What a highlight, a Fresnel term and a
/// reflection are measured from.
vec3 TowardsEye() {
  return Orthographic() ? -fog_info.forward.xyz
                        : normalize(fog_info.eye.xyz - v_world_position);
}

#else  // F3D_NO_FOG

// The same two questions, answered without the block: a stage that declares no
// fog has no eye position to measure from either. Stubs rather than a guard at
// every call site, so that what includes this file reads the same whichever
// way it was compiled.
float EyeDistance() { return 0.0; }
float ViewDepth() { return 0.0; }

#endif  // F3D_NO_FOG

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
/// `flutter3d/test/surface_depth_test.dart`.
///
/// Zero still means nothing was drawn. The attachment is cleared to zero and
/// nothing is drawn in front of the near plane.
void WriteSurfaceGeometry(float roughness) {
#ifndef F3D_NO_SURFACE_BUFFER
  // `L5`: the surface's colour, whatever the surface buffer ends up holding.
  frag_albedo = vec4(LinearToSrgb(clamp(g_albedo, vec3(0.0), vec3(1.0))), 1.0);
  // A debug pass takes the buffer over rather than getting one of its own.
  // The surface buffer already has an attachment, a viewer and a golden; a
  // second one would need all three built before it could answer anything.
  if (g_debug_surface_on) {
    frag_surface = vec4(g_debug_surface, ViewDepth());
    return;
  }
  // Reversed on a back face, as the lit normal is, so the occlusion and
  // reflection passes see the side of a double-sided surface that faces them.
  vec3 geometric = normalize(v_normal);
  if (!gl_FrontFacing) geometric = -geometric;
  frag_surface = vec4(EncodeOctahedral(geometric),
                      clamp(roughness, 0.0, 1.0), ViewDepth());
#endif
}

/// Fades [color] toward the fog with distance from the eye.
///
/// Exponential rather than linear, because linear fog has a visible plane
/// where it starts and a dungeon corridor is exactly where that shows.
///
/// **Height fog — `P5`.** `fog_info.fog.w` is the density at the eye and
/// `fog_info.eye.w` how fast it falls off upwards, per metre. The density
/// along the ray is then `density · e^(−falloff · Δy · t)` for t from nought
/// to one, and its mean over the ray is `(1 − e^(−k)) / k` with
/// `k = falloff · Δy`: an exact integral, so a fog lying on the ground costs
/// one exponential here and no march. Below a thousandth `k` is answered by
/// the first two terms of the same series, because the quotient there is
/// two nearly equal numbers divided by a small one. A falloff of nought skips
/// all of it, which keeps a flat fog the same to the bit.
vec3 ApplyFog(vec3 color) {
#ifdef F3D_NO_FOG
  return color;
#else
  float density = fog_info.fog.w;
  if (density <= 0.0) return color;
  float d = EyeDistance();
  float falloff = fog_info.eye.w;
  if (falloff > 0.0) {
    float k = falloff * (v_world_position.y - fog_info.eye.y);
    density *= abs(k) > 1e-3 ? (1.0 - exp(-k)) / k : 1.0 - 0.5 * k;
  }
  return mix(fog_info.fog.rgb, color, clamp(exp(-density * d), 0.0, 1.0));
#endif
}

/// How much a transparent fragment counts for against the others over its
/// pixel — `R8`. McGuire and Bavoil's depth weight (their equation 9): a near
/// layer outweighs a far one, which is all the ordering a weighted average
/// can keep. [alpha] multiplies it, as theirs does, so a faint layer counts
/// faintly. Depth along the view axis, in metres, the surface buffer's.
float WeightedBlendedWeight(float alpha) {
  float z = abs(ViewDepth());
  float near = z / 5.0;
  float far = z / 200.0;
  float far3 = far * far * far;
  return alpha *
         clamp(10.0 / (1e-5 + near * near + far3 * far3), 1e-2, 3e3);
}

/// What a transparent draw writes when the frame composites transparency
/// order-independently — `R8`. `fog_info.forward.w` says which:
///
/// - 0: [frag_color] as it stands, the sorted blend's source. Every opaque
///   draw, and every draw in a frame that sorts.
/// - 1: the accumulation target's share — the colour, which the engine keeps
///   premultiplied, and the alpha, both times the weight. Added.
/// - 2: the revealage target's — the alpha alone, in every channel, which the
///   blend multiplies the target by one minus of.
/// - 3: both at once, the second into attachment one, where the surface
///   buffer would be; the pass that asks has no surface buffer attached.
///
/// Selects rather than returns, because a phi of constants is what
/// SPIRV-Cross refuses. At nought the branch is not taken and [frag_color]
/// is untouched, which is what keeps a sorting frame byte-identical.
void WriteWeightedBlended() {
#ifndef F3D_NO_FOG
  float mode = fog_info.forward.w;
  if (mode > 0.5) {
    float alpha = frag_color.a;
    float weight = WeightedBlendedWeight(alpha);
    vec4 accumulate = vec4(frag_color.rgb * weight, alpha * weight);
    bool revealage = mode > 1.5 && mode < 2.5;
    frag_color = revealage ? vec4(alpha) : accumulate;
#ifndef F3D_NO_SURFACE_BUFFER
    if (mode > 2.5) frag_surface = vec4(alpha);
#endif
  }
#endif
}

/// The fog is mixed in before the weight, so a thin distant pane adds a thin
/// share of the fog too rather than all of it. Times one when nothing blends,
/// which is exact, so an opaque draw writes what it always wrote.
void WriteSurface(vec3 linearColor, float alpha, float roughness) {
  float weight = g_premultiply ? alpha : 1.0;
  frag_color = vec4(ApplyFog(linearColor) * weight, alpha);
  WriteSurfaceGeometry(roughness);
  WriteWeightedBlended();
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
