import 'package:flutter_gpu/gpu.dart' as gpu;
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
/// [lighting], because flutter_gpu compiles shaders ahead of time and a material
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
    this.alphaMode = MaterialAlphaMode.opaque,
    this.alphaCutoff = 0.5,
    this.doubleSided = false,
    this.drawBucket = 0,
  }) : baseColor = baseColor ?? Vector4(1.0, 1.0, 1.0, 1.0);

  final String? name;

  /// Selects the pre-built fragment shader, and therefore the pipeline.
  LightingModel lighting;

  /// Linear RGBA tint applied on top of [albedo].
  final Vector4 baseColor;

  double metallic;
  double roughness;

  gpu.Texture? albedo;
  gpu.SamplerOptions? albedoSampler;

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
