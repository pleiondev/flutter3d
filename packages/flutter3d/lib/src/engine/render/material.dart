import 'package:vector_math/vector_math.dart';

import 'package:flutter3d_graphics/flutter3d_graphics.dart';
import 'lighting_model.dart';

/// How a material treats the alpha channel, mirroring glTF's `alphaMode`.
///
/// The renderer uses this to split draws into the opaque and transparent halves
/// of the render list, in the manner of PlayCanvas sub-layers.
enum MaterialAlphaMode { opaque, mask, blend }

/// Surface appearance as plain data.
///
/// Materials carry no GPU objects beyond textures: the shader is selected by
/// [lighting], because shaders are compiled ahead of time and a material
/// cannot assemble one at runtime. That makes [lighting] the pipeline key, and
/// the pipeline the most expensive state change in a pass — which is why it is
/// the high-order term when the render list is sorted.
final class Material {
  Material({
    this.name,
    this.lighting = LightingModel.pbr,
    Vector4? baseColor,
    this.metallic = 0.0,
    this.roughness = 0.5,
    this.albedo,
    this.albedoSampler,
    this.normal,
    this.normalSampler,
    this.normalScale = 1.0,
    this.metallicRoughness,
    this.metallicRoughnessSampler,
    this.occlusion,
    this.occlusionSampler,
    this.occlusionStrength = 1.0,
    this.emissiveTexture,
    this.emissiveSampler,
    Vector3? emissive,
    this.emissiveStrength = 1.0,
    this.alphaMode = MaterialAlphaMode.opaque,
    this.alphaCutoff = 0.5,
    this.doubleSided = false,
    this.drawBucket = 0,
  })  : baseColor = baseColor ?? Vector4(1.0, 1.0, 1.0, 1.0),
        emissive = emissive ?? Vector3.zero();

  final String? name;

  /// Selects the pre-built fragment shader, and therefore the pipeline.
  LightingModel lighting;

  /// Linear RGBA tint applied on top of [albedo].
  final Vector4 baseColor;

  double metallic;
  double roughness;

  TextureHandle? albedo;
  SamplerOptions? albedoSampler;

  /// Tangent-space normal map. Null means the geometric normal is used.
  ///
  /// A missing map is a *neutral* texture at bind time, not a flag: the renderer
  /// binds a flat 1x1 normal, a white ORM, a white occlusion and a white
  /// emissive when a slot is empty. Flags would have to agree with the shader in
  /// two places; a neutral texel is right by construction, and the branch it
  /// would have cost is worth more than the sample.
  TextureHandle? normal;
  SamplerOptions? normalSampler;

  /// Scales the tangent-space xy of the normal map, per glTF's `normalScale`.
  double normalScale;

  /// glTF's ORM packing: roughness in green, metallic in blue.
  TextureHandle? metallicRoughness;
  SamplerOptions? metallicRoughnessSampler;

  /// Ambient occlusion in red.
  TextureHandle? occlusion;
  SamplerOptions? occlusionSampler;

  /// How much of the occlusion map to apply, from 0 (ignore) to 1 (in full).
  double occlusionStrength;

  TextureHandle? emissiveTexture;
  SamplerOptions? emissiveSampler;

  /// Linear emissive factor, multiplied by the emissive map. Black by default,
  /// so a material with a map but no factor emits nothing — which is what glTF
  /// specifies.
  final Vector3 emissive;

  /// `KHR_materials_emissive_strength`, a multiplier on top of the factor.
  double emissiveStrength;

  MaterialAlphaMode alphaMode;
  double alphaCutoff;
  bool doubleSided;

  /// Coarse manual ordering, borrowed from PlayCanvas: it outranks every other
  /// sort term, so a skybox or an overlay can be forced to a fixed position
  /// without touching the sorting policy.
  int drawBucket;

  bool get isTransparent => alphaMode == MaterialAlphaMode.blend;
}

/// Assigns small dense integers to materials for use as a sort key.
///
/// An owned registry rather than a static counter on [Material]: global mutable
/// state is the least testable kind of static, and ids only need to be unique
/// within the thing that sorts by them. The renderer owns one.
final class MaterialSortIds {
  final Map<Material, int> _ids = <Material, int>{};

  int get length => _ids.length;

  /// Id for [material], assigning one on first sight.
  ///
  /// Bounded by [limit] because the id is packed into a bit field; wrapping is
  /// better than corrupting neighbouring fields, and a collision only costs
  /// sort quality, never correctness.
  int idOf(Material material, {int limit = 0x7FFFFF}) {
    final existing = _ids[material];
    if (existing != null) return existing;
    final id = (_ids.length + 1) % limit;
    _ids[material] = id;
    return id;
  }

  void clear() => _ids.clear();
}
