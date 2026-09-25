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
#include <lib/irradiance.glsl>

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
  vec3 orm = texture(metallic_roughness_texture, MapUv(kMapMetallicRoughness), MaterialLodBias()).rgb;
  s.metallic = clamp(s.metallic * orm.b, 0.0, 1.0);
  s.roughness = clamp(s.roughness * orm.g, 0.02, 1.0);
}

void ApplyOcclusionMap(inout Surface s) {
  float occlusion = texture(occlusion_texture, MapUv(kMapOcclusion), MaterialLodBias()).r;
  // glTF's occlusionStrength lerps between "ignore the map" and "apply it in
  // full", which is why it is a mix and not a multiply.
  s.occlusion = mix(1.0, occlusion, clamp(frag_info.material2.z, 0.0, 1.0));
}

void ApplyEmissiveMap(inout Surface s) {
  vec3 emissive = SrgbToLinear(texture(emissive_texture, MapUv(kMapEmissive), MaterialLodBias()).rgb);
  s.emissive = emissive * frag_info.emissive.rgb * frag_info.material2.w;
}

/// Perturbs the surface normal by the tangent-space normal map.
void ApplyNormalMap(inout Surface s) {
  // **Sampled before the frame is tested, and that order is load-bearing.**
  // The test below is a branch on interpolated data, so the four invocations of
  // a quad can take different sides of it; a WGSL backend then refuses a
  // `texture` call underneath, because the mip level it derives is only defined
  // where the whole quad agrees. Unlike the shadow atlases, this map really is
  // mipped — a normal map read at full resolution on a surface turned away from
  // the camera is the aliasing that made this the widest disagreement between
  // backends — so pinning a level here would be a picture change, and hoisting
  // the sample is the cure that is not. A degenerate tangent is rare enough
  // that paying for its unused texel is nothing, and the texel it reads is the
  // same one the branch would have read.
  vec4 sampledTexel = texture(normal_texture, MapUv(kMapNormal), MaterialLodBias());

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
#ifdef F3D_TEXTURE_TRANSFORM
  // `C8`: a map turned or mirrored by its transform is read along axes the
  // vertex tangent no longer names, so the frame turns with it — the rule
  // `withTextureTransform` applies to a baked mesh, here at the sampler. The
  // new tangent is where the map's own `u` increases: the first column of the
  // matrix's inverse, times its determinant, whose sign a mirror flips and the
  // bitangent's sign with it. Measured on the front face's frame, which is
  // the frame the transform was authored on. A plain scale leaves the frame
  // as it was, bit for bit, which is why the test is on the matrix. That
  // column is `m11 dP/du - m10 dP/dv`, and dP/dv is **minus** the bitangent:
  // `v` runs down the texture, a normal map's green up it.
  vec4 m = MapMatrix(kMapNormal);
  float det = m.x * m.w - m.y * m.z;
  float flip = det < 0.0 ? -1.0 : 1.0;
  vec3 front = gl_FrontFacing ? b : -b;
  vec3 turned = (t * m.w + front * m.z) * flip;
  bool turns = (m.y != 0.0 || m.z != 0.0 || m.x < 0.0 || m.w < 0.0) &&
               dot(turned, turned) > 1e-12;
  t = turns ? normalize(turned) : t;
  b = turns ? cross(s.n, t) * v_tangent.w * flip : b;
#endif
  // On a back face `ReadSurface` has already turned the normal round, and
  // the bitangent above turned with it. The tangent has to follow, or the
  // frame is half-mirrored and relief along u lights from the wrong side —
  // glTF turns the whole frame, not the normal alone.
  if (!gl_FrontFacing) t = -t;

  vec3 sampled = sampledTexel.xyz * 2.0 - 1.0;
  // A two-channel map (BC5, RG8) stores only x and y and samples as
  // (x, y, 0, 1); read as it stands, blue 0 is z = -1 and the normal points
  // into the surface. z is rebuilt from the unit length instead, before the
  // scale, which glTF applies to the stored normal. `emissive.w` is the flag.
  if (frag_info.emissive.w > 0.5) {
    sampled.z = sqrt(max(1.0 - dot(sampled.xy, sampled.xy), 0.0));
  }
  // normalScale attenuates the tangent-space xy, per the glTF spec.
  sampled.xy *= frag_info.material2.y;

  s.n = normalize(t * sampled.x + b * sampled.y + s.n * sampled.z);
  s.n_dot_v = max(dot(s.n, s.v), 1e-4);
}

/// The three maps every lit model uses. Metal-rough is separate because only
/// the models that actually respond to metallic or roughness may sample it.
void ApplyCommonMaps(inout Surface s) {
  // `L3`: the field in place of the hemisphere, read before the normal map
  // for the reason the hemisphere is — which half of the room a face sees is
  // not a question about millimetres of relief. At the same strength the
  // hemisphere was.
  if (IrradianceEnabled()) {
    s.ambient = SampleIrradiance(v_world_position, s.n, s.v) *
                frag_info.material.z;
  }
  ApplyNormalMap(s);
  ApplyOcclusionMap(s);
  ApplyEmissiveMap(s);
}

#endif  // MATERIAL_MAPS_GLSL_
