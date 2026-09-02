// The texture maps a lit material can carry, beyond base colour.
//
// A separate header from surface.glsl on purpose. Declaring a sampler a shader
// never reads is the same trap as declaring an unused uniform block: the
// compiled function has no such slot, while the Dart side still has metadata
// saying it does. Unlit and the debug models include surface.glsl (or only
// color.glsl) and get none of this; the lit models include both, and
// LightingModel.usesMaterialTextures says which is which.
//
// Every map has a *neutral* fallback texture bound when the material has none,
// so there are no "has this map" flags to keep in sync — a white ORM texture
// multiplies the factors by one, and a flat normal map perturbs nothing. Flags
// would have to be right in two places; a neutral texel is right by
// construction.

#ifndef MATERIAL_MAPS_GLSL_
#define MATERIAL_MAPS_GLSL_

#include <lib/surface.glsl>

/// Tangent-space normal map. Neutral is (0.5, 0.5, 1.0).
uniform sampler2D normal_texture;

/// glTF's ORM packing: g is roughness, b is metallic. Neutral is white.
uniform sampler2D metallic_roughness_texture;

/// Ambient occlusion in r. Neutral is white.
uniform sampler2D occlusion_texture;

/// Emitted colour, multiplied by the emissive factor. Neutral is white, and the
/// factor defaults to black, so a material with neither emits nothing.
uniform sampler2D emissive_texture;

/// The level's baked lightmap, RGBM: colour over a shared multiplier, decoded
/// as `rgb × a × 8`. Sampled at the second coordinate, which every vertex
/// stage but the lightmapped one leaves at the atlas corner; neutral is
/// black, so a material without a map adds nothing.
uniform sampler2D lightmap_texture;

/// The irradiance the lightmap holds at this fragment, in the units a light's
/// `colour × intensity × attenuation × cos` arrives in.
vec3 SampleLightmap() {
  vec4 texel = texture(lightmap_texture, v_lightmap_uv);
  return texel.rgb * texel.a * 8.0;
}

/// One function per map, rather than one that applies all four.
///
/// Not a style choice. The compiler drops a sampler whose result never reaches
/// the output, so a model that samples the ORM map and then ignores metallic and
/// roughness — Lambert does exactly that — ends up with no
/// `metallic_roughness_texture` in its compiled signature at all, while the Dart
/// side still thinks there is one to bind. That is the phantom-binding trap
/// again, and binding a slot Metal does not have is a native crash.
///
/// Splitting them means a model calls only what it genuinely uses, so the
/// compiled signature matches the source, and `LightingModel` can declare the
/// same set truthfully. `tool/build_shaders.sh` prints the compiled slots so
/// the two cannot drift apart unnoticed.

/// glTF's ORM packing: roughness in g, metallic in b, both multiplying the
/// material factors.
void ApplyMetallicRoughnessMap(inout Surface s) {
  vec3 orm = texture(metallic_roughness_texture, v_texcoord).rgb;
  s.metallic = clamp(s.metallic * orm.b, 0.0, 1.0);
  s.roughness = clamp(s.roughness * orm.g, 0.02, 1.0);
}

void ApplyOcclusionMap(inout Surface s) {
  float occlusion = texture(occlusion_texture, v_texcoord).r;
  // glTF's occlusionStrength lerps between "ignore the map" and "apply it in
  // full", which is why it is a mix and not a multiply.
  s.occlusion = mix(1.0, occlusion, clamp(frag_info.material2.z, 0.0, 1.0));
}

void ApplyEmissiveMap(inout Surface s) {
  vec3 emissive = SrgbToLinear(texture(emissive_texture, v_texcoord).rgb);
  s.emissive = emissive * frag_info.emissive.rgb * frag_info.material2.w;
}

/// Perturbs the surface normal by the tangent-space normal map.
void ApplyNormalMap(inout Surface s) {
  // The tangent is re-orthogonalized against the normal because interpolating
  // both across a triangle does not preserve the right angle between them.
  vec3 t = v_tangent.xyz;
  t = t - s.n * dot(s.n, t);
  if (dot(t, t) < 1e-12) return;  // no usable frame; keep the vertex normal
  t = normalize(t);

  // The bitangent sign is what encodes a mirrored UV island. Dropping it makes
  // every mirrored half of a symmetric model light from the wrong side, which
  // is exactly what NormalTangentTest is built to show.
  vec3 b = cross(s.n, t) * v_tangent.w;

  vec3 sampled = texture(normal_texture, v_texcoord).xyz * 2.0 - 1.0;
  // normalScale attenuates the tangent-space xy, per the glTF spec.
  sampled.xy *= frag_info.material2.y;

  s.n = normalize(t * sampled.x + b * sampled.y + s.n * sampled.z);
  s.n_dot_v = max(dot(s.n, s.v), 1e-4);
}

/// The three maps every lit model uses. Metal-rough is separate because only
/// the models that actually respond to metallic or roughness may sample it.
void ApplyCommonMaps(inout Surface s) {
  ApplyNormalMap(s);
  ApplyOcclusionMap(s);
  ApplyEmissiveMap(s);
}

#endif  // MATERIAL_MAPS_GLSL_
