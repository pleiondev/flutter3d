/// `ReadSurface` and the material maps, transcribed from `surface.glsl` and
/// `material_maps.glsl`.
///
/// Every lit model — `cpu_shaders_lit.dart` — starts by reading a [Surface]
/// out of the vertex varyings and the bound material, then asks the maps here
/// to perturb it. Split from the lighting math itself (`cpu_shaders_lighting.dart`)
/// because a surface is a question about *this fragment*, independent of which
/// lights see it.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';
import 'cpu_shaders_color.dart';
import 'cpu_shaders_layout.dart';

/// How far the texture coordinate moves per screen pixel, for mip selection.
///
/// **Every map below sampled the base level until this existed**, whatever mip
/// chain the texture had been uploaded with, because `CpuTexture.sample`
/// selects level zero when it is given no derivatives and nothing here was
/// giving it any. The particle stage had been passing them since it was
/// written; the lit path never adopted it, so a normal map read at full
/// resolution wherever the hardware backends read a blurred level. That shows
/// as the fine detail being sharper and darker than it should be — it made
/// `normal-mapping` the widest disagreement this backend had with Impeller —
/// and as aliasing that moves when the camera does.
///
/// The larger of the two directions per axis, which is what the particle stage
/// takes and for the same reason: a hardware sampler uses the longer side of
/// the footprint parallelogram, and the maximum of the axis-aligned components
/// is that for a surface facing the camera.
({double du, double dv}) uvFootprint(FragmentContext c) {
  final ddx = c.ddx;
  final ddy = c.ddy;
  if (ddx == null || ddy == null) return (du: 0.0, dv: 0.0);
  return (
    du: math.max(ddx[kVUv].abs(), ddy[kVUv].abs()),
    dv: math.max(ddx[kVUv + 1].abs(), ddy[kVUv + 1].abs()),
  );
}

/// What `ReadSurface` produces, for the models that need more than the albedo.
/// Mutable, because the GLSL passes it as `inout` to every map function and
/// each one modifies a field. A copy-returning version would read better and
/// would be a different program.
final class Surface {
  Surface(
    this.albedo,
    this.alpha,
    this.normal,
    this.world,
    this.ambient,
    this.metallic,
    this.roughness,
    this.view,
    this.nDotV,
    this.tangent,
  );
  Vector3 albedo;
  double alpha;
  Vector3 normal;
  final Vector3 world;

  /// Hemispheric and already scaled by the scene's strength: the sky above,
  /// the ground bounce below, blended by which way the surface faces.
  final Vector3 ambient;
  double metallic;
  double roughness;

  /// Towards the eye, which every specular term needs.
  final Vector3 view;

  /// Clamped away from zero: a grazing view otherwise divides by zero in the
  /// specular visibility term.
  double nDotV;

  /// xyz the tangent, w the bitangent sign — glTF's convention for a mirrored
  /// UV island.
  final Vector4 tangent;

  /// Neutral until a map says otherwise, so a model that samples nothing still
  /// has a complete surface.
  double occlusion = 1.0;
  Vector3 emissive = Vector3.zero();
}

/// `ReadSurface` from `surface.glsl`.
///
/// Alpha masking is not here: `material2.x` is negative for every material the
/// fixtures use, and a discard nothing exercises would be a guess.
Surface readSurface(Float32List v, ShaderBindings bindings, FragmentContext c) {
  final uv = uvFootprint(c);
  final tint = bindings.vec4('FragInfo', 'base_color', Vector4(1, 1, 1, 1));
  final texture = bindings.textures['base_color_texture'];
  final texel = texture == null
      ? Vector4(1, 1, 1, 1)
      : texture.sample(v[kVUv], v[kVUv + 1], du: uv.du, dv: uv.dv);

  // Texture and tint are sRGB; the vertex colour is authored linear, per glTF.
  final albedo = Vector3(
    toLinear(texel.x) * toLinear(tint.x) * v[kVColour],
    toLinear(texel.y) * toLinear(tint.y) * v[kVColour + 1],
    toLinear(texel.z) * toLinear(tint.z) * v[kVColour + 2],
  );
  final alpha = texel.w * tint.w * v[kVColour + 3];

  final normal = Vector3(v[kVNormal], v[kVNormal + 1], v[kVNormal + 2]);
  final length = normal.length;
  if (length > 1e-6) normal.scale(1.0 / length);

  final material = bindings.vec4('FragInfo', 'material', Vector4.zero());
  final camera = bindings.vec4('FragInfo', 'camera_position', Vector4.zero());
  final world = Vector3(v[kVWorld], v[kVWorld + 1], v[kVWorld + 2]);
  final view = Vector3(camera.x, camera.y, camera.z) - world;
  final viewLength = view.length;
  if (viewLength > 1e-6) view.scale(1.0 / viewLength);

  // Hemispheric, blended on the geometric normal before any map perturbs it:
  // ambient of this kind says which half of the world a face can see, and
  // millimetres of bump relief are not an answer to that.
  final sky = bindings.vec4('FragInfo', 'ambient_sky', Vector4(1, 1, 1, 1));
  final ground = bindings.vec4(
    'FragInfo',
    'ambient_ground',
    Vector4(1, 1, 1, 1),
  );
  final up = normal.y * 0.5 + 0.5;
  final ambient = Vector3(
    (ground.x + (sky.x - ground.x) * up) * material.z,
    (ground.y + (sky.y - ground.y) * up) * material.z,
    (ground.z + (sky.z - ground.z) * up) * material.z,
  );

  return Surface(
    albedo,
    alpha,
    normal,
    world,
    ambient,
    material.x.clamp(0.0, 1.0),
    material.y.clamp(0.02, 1.0),
    view,
    math.max(normal.dot(view), 1e-4),
    Vector4(v[kVTangent], v[kVTangent + 1], v[kVTangent + 2], v[kVTangent + 3]),
  );
}

// ---------------------------------------------------------------------------
// material_maps.glsl
//
// Every map has a neutral fallback bound when the material has none, so there
// are no "has this map" flags to keep in sync: a white ORM texture multiplies
// by one and a flat normal map perturbs nothing. That is why each function
// below samples unconditionally.
// ---------------------------------------------------------------------------

/// glTF's ORM packing: roughness in g, metallic in b.
void applyMetallicRoughnessMap(
  Surface s,
  Float32List v,
  ShaderBindings b,
  FragmentContext c,
) {
  final orm = b.textures['metallic_roughness_texture'];
  if (orm == null) return;
  final uv = uvFootprint(c);
  final texel = orm.sample(v[kVUv], v[kVUv + 1], du: uv.du, dv: uv.dv);
  s.metallic = (s.metallic * texel.z).clamp(0.0, 1.0);
  s.roughness = (s.roughness * texel.y).clamp(0.02, 1.0);
}

/// glTF's `occlusionStrength` lerps between ignoring the map and applying it
/// in full, which is why this is a mix and not a multiply.
void applyOcclusionMap(
  Surface s,
  Float32List v,
  ShaderBindings b,
  FragmentContext c,
) {
  final map = b.textures['occlusion_texture'];
  if (map == null) return;
  final uv = uvFootprint(c);
  final occlusion = map.sample(v[kVUv], v[kVUv + 1], du: uv.du, dv: uv.dv).x;
  final strength = b
      .vec4('FragInfo', 'material2', Vector4.zero())
      .z
      .clamp(0.0, 1.0);
  s.occlusion = 1.0 + (occlusion - 1.0) * strength;
}

/// `SampleLightmap`: the baked irradiance at this fragment, RGBM-decoded as
/// `rgb × a × 8`, or black when the slot holds the renderer's one-texel
/// fallback — which is every material without a map.
Vector3 sampleLightmap(Float32List v, ShaderBindings b, FragmentContext c) {
  final map = b.textures['lightmap_texture'];
  if (map == null) return Vector3.zero();
  final texel = map.sample(v[kVLightmap], v[kVLightmap + 1]);
  final multiplier = texel.w * 8.0;
  return Vector3(
    texel.x * multiplier,
    texel.y * multiplier,
    texel.z * multiplier,
  );
}

void applyEmissiveMap(
  Surface s,
  Float32List v,
  ShaderBindings b,
  FragmentContext c,
) {
  final map = b.textures['emissive_texture'];
  if (map == null) return;
  final uv = uvFootprint(c);
  final texel = map.sample(v[kVUv], v[kVUv + 1], du: uv.du, dv: uv.dv);
  final factor = b.vec4('FragInfo', 'emissive', Vector4.zero());
  final strength = b.vec4('FragInfo', 'material2', Vector4.zero()).w;
  s.emissive = Vector3(
    toLinear(texel.x) * factor.x * strength,
    toLinear(texel.y) * factor.y * strength,
    toLinear(texel.z) * factor.z * strength,
  );
}

/// Perturbs the normal by the tangent-space map.
void applyNormalMap(
  Surface s,
  Float32List v,
  ShaderBindings b,
  FragmentContext c,
) {
  final map = b.textures['normal_texture'];
  if (map == null) return;

  // Re-orthogonalised against the normal: interpolating both across a triangle
  // does not preserve the right angle between them.
  final t = Vector3(s.tangent.x, s.tangent.y, s.tangent.z);
  t.sub(s.normal * s.normal.dot(t));
  if (t.length2 < 1e-12) return; // no usable frame; keep the vertex normal
  t.normalize();

  // The bitangent sign encodes a mirrored UV island. Dropping it lights every
  // mirrored half of a symmetric model from the wrong side.
  final bitangent = s.normal.cross(t)..scale(s.tangent.w);

  final uv = uvFootprint(c);
  final texel = map.sample(v[kVUv], v[kVUv + 1], du: uv.du, dv: uv.dv);
  final scale = b.vec4('FragInfo', 'material2', Vector4.zero()).y;
  final sx = (texel.x * 2.0 - 1.0) * scale;
  final sy = (texel.y * 2.0 - 1.0) * scale;
  final sz = texel.z * 2.0 - 1.0;

  s.normal = (t * sx + bitangent * sy + s.normal * sz)..normalize();
  s.nDotV = math.max(s.normal.dot(s.view), 1e-4);
}

/// The three every lit model uses. Metal-rough is separate because only the
/// models that respond to metallic or roughness may sample it.
void applyCommonMaps(
  Surface s,
  Float32List v,
  ShaderBindings b,
  FragmentContext c,
) {
  applyNormalMap(s, v, b, c);
  applyOcclusionMap(s, v, b, c);
  applyEmissiveMap(s, v, b, c);
}
