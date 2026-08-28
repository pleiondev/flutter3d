import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

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
    this.depthWrite,
    this.depthCompare,
    this.parameterBlock = 'MaterialParams',
    Map<String, Float32List>? parameters,
    Map<String, TextureHandle>? extraTextures,
  }) : parameters = parameters ?? const <String, Float32List>{},
       extraTextures = extraTextures ?? const <String, TextureHandle>{},
       baseColor = baseColor ?? Vector4(1.0, 1.0, 1.0, 1.0),
       emissive = emissive ?? Vector3.zero();

  final String? name;

  /// The uniform block an application's own shader reads its parameters from.
  ///
  /// Meaningless for the models this engine ships — they read `FragInfo` — and
  /// used only when [parameters] has something in it.
  final String parameterBlock;

  /// What an application's own shader is configured with.
  ///
  /// **This is the half of a custom material that is not the shader.** A
  /// [LightingModel] can already name a stage the engine never heard of; this
  /// is how that stage is told a wave height, a tint ramp or a scroll speed
  /// without the engine knowing what any of them mean.
  ///
  /// Safe to fill in even when the shader has no such block: the encoder skips
  /// members a compiled shader does not read and reports an absent block rather
  /// than taking the process down — see `CommandEncoder.bindUniformBlock`,
  /// where that distinction is spelled out.
  ///
  /// Every uniform in this engine is a float vector, a matrix or an array of
  /// either, so a `Float32List` is the only value there is. An integer or a
  /// boolean is encoded as a float, the same way the built-in shaders do it.
  final Map<String, Float32List> parameters;

  /// Textures an application's own shader samples, by slot name.
  ///
  /// **Unlike [parameters], a wrong name here is fatal**, and that asymmetry is
  /// the encoder's rather than this class's: binding a sampler slot a compiled
  /// shader does not have is a native crash with no Dart stack, while a missing
  /// uniform block is merely reported. The material that names the shader is
  /// the same object that lists these, so the two are the author's to keep in
  /// step — there is nothing here that could check it for them.
  final Map<String, TextureHandle> extraTextures;

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
  ///
  /// Signed, and negative is the useful half: ordinary materials sit at zero,
  /// so the only way to be drawn *before* the scene is to ask for less than it.
  /// The usable range is −128 to 127 and values outside it are clamped.
  int drawBucket;

  /// Overrides whether this surface writes depth. Null lets transparency
  /// decide, which is what every ordinary material wants.
  ///
  /// Null rather than `true` for the same reason [PassState]'s fields are
  /// optional: unset means *the pass's own answer*, and the pass's answer is
  /// "opaque writes, blended does not". Saying `false` here is a different
  /// statement from being transparent — it is a surface that is drawn and then
  /// stops existing as far as everything after it is concerned.
  ///
  /// What it is for: a backdrop. A sky drawn on a small dome around the camera
  /// is nearer than everything it is supposed to be behind, so it must be drawn
  /// first and leave the depth buffer untouched. Without this the dome writes a
  /// few metres of depth across the whole frame and the level behind it is
  /// clipped away.
  bool? depthWrite;

  /// Overrides the depth test. Null keeps the pass's own, which is
  /// [CompareFunction.less].
  ///
  /// The other half of a backdrop: with [depthWrite] off and this left alone a
  /// dome still has to *pass* the test to be drawn, which it does only where
  /// nothing has been drawn yet — fine when the sky goes first, wrong the
  /// moment anything wants to be drawn after the scene. [CompareFunction.always]
  /// is the honest statement for a surface whose depth is not a fact about the
  /// world.
  ///
  /// Applies to the scene pass only. The shadow pass draws casters with its own
  /// state and has no use for either of these — a surface that should not
  /// occlude in a shadow map says so with `MeshNode.castsShadow`.
  CompareFunction? depthCompare;

  bool get isTransparent => alphaMode == MaterialAlphaMode.blend;

  /// An independent copy: the vectors are cloned, the textures are shared.
  ///
  /// Here rather than where it is used, and that is the whole point of moving
  /// it. It lived in `ModelAsset` as a private helper listing every field by
  /// hand, so each new field was a field that copied silently as its default —
  /// `depthWrite` and `depthCompare` were lost the day they were added, and the
  /// symptom would have been a model whose materials behave differently from
  /// the ones it was built from, in one game, on one asset. A copy that lives
  /// beside the fields is a copy the next field is added next to.
  ///
  /// Textures are shared on purpose: they are device handles, and two materials
  /// pointing at one uploaded image is the arrangement everything downstream
  /// already assumes.
  Material copy() => Material(
    name: name,
    lighting: lighting,
    baseColor: baseColor.clone(),
    metallic: metallic,
    roughness: roughness,
    albedo: albedo,
    albedoSampler: albedoSampler,
    normal: normal,
    normalSampler: normalSampler,
    normalScale: normalScale,
    metallicRoughness: metallicRoughness,
    metallicRoughnessSampler: metallicRoughnessSampler,
    occlusion: occlusion,
    occlusionSampler: occlusionSampler,
    occlusionStrength: occlusionStrength,
    emissiveTexture: emissiveTexture,
    emissiveSampler: emissiveSampler,
    emissive: emissive.clone(),
    emissiveStrength: emissiveStrength,
    alphaMode: alphaMode,
    alphaCutoff: alphaCutoff,
    doubleSided: doubleSided,
    drawBucket: drawBucket,
    depthWrite: depthWrite,
    depthCompare: depthCompare,
  );
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
