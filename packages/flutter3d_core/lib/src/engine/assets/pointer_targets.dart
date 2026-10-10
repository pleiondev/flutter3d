import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';

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
/// [RenderMaterial.baseColor] is the authored sRGB tint. A light's intensity
/// is candela, or lux for a directional light, in the file and in
/// [LightNode.intensity] alike since 1.0, so it passes through unchanged.
final class PointerTargets with AnimationPointerSink {
  PointerTargets({
    Map<int, RenderMaterial>? materials,
    Map<int, LightNode>? lights,
  }) : materials = materials ?? <int, RenderMaterial>{},
       lights = lights ?? <int, LightNode>{};

  final Map<int, RenderMaterial> materials;
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
  /// the pointer names in [RenderMaterial.textureTransforms] — `C8`. A loader keeps
  /// such a material's transforms there, at the sampler, rather than baking
  /// them into the mesh, so the offset a clip moves is the one drawn; a map
  /// that named no transform gains one, the identity with this offset.
  static void applyToMaterial(
    RenderMaterial material,
    AnimationPointer pointer,
    List<double> values,
  ) {
    switch (pointer.property) {
      case AnimationPointerProperty.baseColor:
        material.baseColor = LinearColor(
          values[0],
          values[1],
          values[2],
          values[3],
        );
      case AnimationPointerProperty.emissiveStrength:
        // glTF animates a multiple of the factor; the material holds nits.
        material.emissiveStrength = values[0] * Photometric.legacyNits;
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
        light.color = LinearColor(values[0], values[1], values[2]);
      case AnimationPointerProperty.lightIntensity:
        // Candela for a point or spot, lux for a directional light — what
        // glTF animates and, since 1.0, what `LightNode.intensity` holds.
        light.intensity = values[0];
      case AnimationPointerProperty.baseColor:
      case AnimationPointerProperty.emissiveStrength:
      case AnimationPointerProperty.roughness:
      case AnimationPointerProperty.metallic:
      case AnimationPointerProperty.textureOffset:
        break;
    }
  }
}
