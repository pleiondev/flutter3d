#version 460 core

// `P4`: a planar reflector's surface, drawn a second time over itself with
// the picture a mirrored camera took of the world above it.
//
// **Laid over the surface rather than inside its lighting.** The reflection
// is read by the pixel's place on screen, not by anything the material
// knows, so the stage that reads it needs nothing a lit model has: no maps,
// no lights, no shadows. Putting it inside the lit models would have been a
// sampler and a block added to six stages that every other draw pays to
// declare, and a seventh header permutation to keep byte-identical. As a
// draw of its own it costs only the surfaces that reflect, and a frame
// without a reflector compiles and binds exactly what it did.
//
// Drawn with the depth test `lessEqual` and no depth write, straight after
// the opaque half, so it lands on exactly the pixels the surface itself won
// and nothing in front of the surface is painted. Blended source-over with
// the colour premultiplied, as every blended draw here is.
//
// **No second output**, for the reason `xray.frag` gives at length: a blend
// protects attachment zero only, and only on the backends whose `setBlend`
// honours an attachment index. The surface buffer keeps describing the
// surface underneath, which is the truth about it.
//
// **And not `lib/surface.glsl`**, which `xray.frag` does include: that header
// declares the base colour sampler for every stage that takes it, and a stage
// that never reads it has it dropped from the Metal function while reflection
// still reports it, which is the slot `metal_bindings_test.dart` exists to
// catch. The two things wanted from `FragInfo` come another way: the eye is
// `FogInfo`'s, and the target's rows ride in this stage's own block.
#define F3D_NO_SURFACE_BUFFER
#include <lib/color.glsl>
#include <lib/frag_coord.glsl>

/// What the mirrored camera saw, in linear light, the size of the view it
/// was taken for or a fraction of it.
uniform sampler2D reflection_texture;

uniform PlanarReflectionInfo {
  /// xy: the view's top-left corner in pixels of the target, counted from
  /// the top. zw: the view's size in pixels.
  vec4 view;

  /// x: the reflectance straight on, Schlick's F0 — one for a mirror, about
  /// 0.02 for water. y: the strength the reflection is laid on with, which
  /// scales the whole Fresnel term. z: the target's rows where its first row
  /// is the bottom of the picture, nought where it is the top — see
  /// `FragCoordFromTop`. w unused.
  vec4 params;

  /// rgb: a linear tint the reflected light is multiplied by. w unused.
  vec4 tint;
}
planar_info;

void main() {
  // The same pixel the mirrored camera drew, by place on screen: its
  // projection is the view's own, so the texel under this fragment is the
  // reflected point behind it. Counted from the top on every backend, and
  // turned back where the texture's first row is the bottom of the picture.
  float rows = planar_info.params.z;
  vec2 pixel = FragCoordFromTop(rows);
  vec2 uv = (pixel - planar_info.view.xy) / planar_info.view.zw;
  if (rows > 0.0) uv.y = 1.0 - uv.y;
  vec3 reflected =
      textureLod(reflection_texture, uv, 0.0).rgb * planar_info.tint.rgb;

  // Schlick's Fresnel on the geometric normal, facing the eye: water reflects
  // a little looking down into it and nearly everything at a grazing angle,
  // and a mirror's F0 of one makes the term one everywhere.
  vec3 n = normalize(v_normal);
  if (!gl_FrontFacing) n = -n;
  vec3 v = normalize(fog_info.eye.xyz - v_world_position);
  float cosine = clamp(dot(n, v), 0.0, 1.0);
  float f0 = planar_info.params.x;
  float grazing = 1.0 - cosine;
  float grazing2 = grazing * grazing;
  float fresnel = f0 + (1.0 - f0) * grazing2 * grazing2 * grazing;
  float alpha = clamp(fresnel * planar_info.params.y, 0.0, 1.0);

  // Fogged as the surface is: the reflection is light leaving the surface
  // and crosses the same air to the eye. Premultiplied for the blend.
  frag_color = vec4(ApplyFog(reflected) * alpha, alpha);
}
