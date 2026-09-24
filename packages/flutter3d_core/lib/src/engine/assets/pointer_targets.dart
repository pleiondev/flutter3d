import 'package:flutter3d_core/formats.dart';

import '../../formats/srgb.dart';
import '../render/material.dart';
import '../scene/light_node.dart';

/// The materials and lights of one model instance, as a place for
/// `KHR_animation_pointer` tracks to land.
///
/// **Indexed the way the file indexes them**, because that is how a pointer
/// names its target: `/materials/2/...` is the document's third material
/// whichever parts wear it, and a light is the document's light, not a node.
/// A model instance fills [materials] as it binds them and leaves [lights]
/// for the caller — instantiating a model creates no lights, so a clip that
/// dims a lamp dims whichever [LightNode] the application bound to it.
///
/// Values arrive in the file's own units and spaces and are converted here,
/// at the one seam between the two: glTF's base colour is linear and
/// [Material.baseColor] is the authored sRGB tint; a light's intensity is
/// candela or lux and [LightNode.intensity] is the engine's own unit — see
/// [Photometric].
final class PointerTargets implements AnimationPointerSink {
  PointerTargets({Map<int, Material>? materials, Map<int, LightNode>? lights})
    : materials = materials ?? <int, Material>{},
      lights = lights ?? <int, LightNode>{};

  final Map<int, Material> materials;
  final Map<int, LightNode> lights;

  @override
  void setPointer(AnimationPointer pointer, List<double> values) {
    switch (pointer.target) {
      case AnimationPointerTarget.material:
        final material = materials[pointer.index];
        if (material != null) applyToMaterial(material, pointer, values);
      case AnimationPointerTarget.light:
        final light = lights[pointer.index];
        if (light != null) applyToLight(light, pointer, values);
    }
  }

  /// Writes [values] to [material]'s property named by [pointer].
  ///
  /// [AnimationPointerProperty.textureOffset] moves the offset of the map
  /// the pointer names in [Material.textureTransforms] — `C8`. A loader keeps
  /// such a material's transforms there, at the sampler, rather than baking
  /// them into the mesh, so the offset a clip moves is the one drawn; a map
  /// that named no transform gains one, the identity with this offset.
  static void applyToMaterial(
    Material material,
    AnimationPointer pointer,
    List<double> values,
  ) {
    switch (pointer.property) {
      case AnimationPointerProperty.baseColor:
        material.baseColor.setValues(
          linearToSrgb(values[0]),
          linearToSrgb(values[1]),
          linearToSrgb(values[2]),
          values[3],
        );
      case AnimationPointerProperty.emissiveStrength:
        material.emissiveStrength = values[0];
      case AnimationPointerProperty.roughness:
        material.roughness = values[0];
      case AnimationPointerProperty.metallic:
        material.metallic = values[0];
      case AnimationPointerProperty.textureOffset:
        final map = textureMapOf(pointer);
        if (map == null) return;
        (material.textureTransforms[map] ??= TextureTransform()).offset
            .setValues(values[0], values[1]);
      case AnimationPointerProperty.lightColor:
      case AnimationPointerProperty.lightIntensity:
        break;
    }
  }

  /// Which map a [AnimationPointerProperty.textureOffset] pointer names, from
  /// the texture info its string goes through.
  ///
  /// Read from the string rather than resolved into [AnimationPointer], which
  /// keeps the one property for all five maps a writer has always known. Five
  /// substring tests a track a frame, against a pointer whose shape
  /// `AnimationPointer.parse` has already checked.
  static MaterialMap? textureMapOf(AnimationPointer pointer) {
    final path = pointer.pointer;
    return path.contains('/baseColorTexture/')
        ? MaterialMap.baseColor
        : path.contains('/metallicRoughnessTexture/')
        ? MaterialMap.metallicRoughness
        : path.contains('/normalTexture/')
        ? MaterialMap.normal
        : path.contains('/occlusionTexture/')
        ? MaterialMap.occlusion
        : path.contains('/emissiveTexture/')
        ? MaterialMap.emissive
        : null;
  }

  /// Writes [values] to [light]'s property named by [pointer].
  static void applyToLight(
    LightNode light,
    AnimationPointer pointer,
    List<double> values,
  ) {
    switch (pointer.property) {
      case AnimationPointerProperty.lightColor:
        light.color.setValues(values[0], values[1], values[2]);
      case AnimationPointerProperty.lightIntensity:
        // Candela for a point or spot, lux for a directional light: the two
        // share one exchange rate, so one conversion serves every type.
        light.intensity = Photometric.fromCandela(values[0]);
      case AnimationPointerProperty.baseColor:
      case AnimationPointerProperty.emissiveStrength:
      case AnimationPointerProperty.roughness:
      case AnimationPointerProperty.metallic:
      case AnimationPointerProperty.textureOffset:
        break;
    }
  }
}
