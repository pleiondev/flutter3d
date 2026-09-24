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
  /// [AnimationPointerProperty.textureOffset] is accepted and not applied:
  /// the offset is baked into a mesh's coordinates at upload and no stage
  /// reads a per-material offset, so moving one at runtime has nowhere to
  /// go yet. The track still loads, plays and round-trips.
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
      case AnimationPointerProperty.lightColor:
      case AnimationPointerProperty.lightIntensity:
        break;
    }
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
