/// What a `KHR_animation_pointer` channel drives, resolved once at load.
///
/// **Resolved, not interpreted per frame.** The extension addresses its
/// target with a JSON pointer — `/materials/2/pbrMetallicRoughness/
/// roughnessFactor` — and walking that string every frame for every track is
/// the kind of work a player must not do inside the frame budget. So a
/// decoder parses it once into an [AnimationPointer]: which kind of object,
/// which one, which property. The player then hands the sampled value to a
/// setter by that triple, and never sees the string.
///
/// **A closed list of properties**, the ones this engine can actually move at
/// runtime: a material's base colour, emissive strength, roughness, metallic
/// and texture offset, a light's colour and intensity. A pointer to anything
/// else is decoded as nothing, with a warning naming it, rather than carried
/// as a track that plays and changes nothing.
library;

/// The kind of object a pointer lands on.
enum AnimationPointerTarget { material, light }

/// The property a pointer drives, with the number of floats in one value.
enum AnimationPointerProperty {
  /// glTF's `baseColorFactor`: linear RGBA, as the file keeps it. The sink
  /// converts to the authored tint `Material.baseColor` holds.
  baseColor(AnimationPointerTarget.material, 4),

  /// `KHR_materials_emissive_strength`'s multiplier.
  emissiveStrength(AnimationPointerTarget.material, 1),
  roughness(AnimationPointerTarget.material, 1),
  metallic(AnimationPointerTarget.material, 1),

  /// `KHR_texture_transform`'s `offset` on any of a material's textures.
  ///
  /// One property for all of them, because the engine keeps one transform
  /// per material — see `sharedTextureTransform` — so moving the base colour
  /// map's offset moves every map the material samples. The pointer string
  /// says which texture the file named, and a writer puts it back there.
  textureOffset(AnimationPointerTarget.material, 2),

  /// `KHR_lights_punctual`'s `color`, linear RGB.
  lightColor(AnimationPointerTarget.light, 3),
  lightIntensity(AnimationPointerTarget.light, 1);

  const AnimationPointerProperty(this.target, this.componentCount);

  final AnimationPointerTarget target;
  final int componentCount;
}

/// One resolved pointer: [property] of the [index]th object of its kind.
final class AnimationPointer {
  const AnimationPointer({
    required this.property,
    required this.index,
    required this.pointer,
  });

  /// Resolves [pointer] — a JSON pointer as `KHR_animation_pointer` writes
  /// it — or returns null when it names nothing this engine animates.
  ///
  /// Matches the whole path, not a suffix: `/materials/0/extensions/
  /// KHR_materials_emissive_strength/emissiveStrength` is a strength, and a
  /// path that merely ends in `emissiveStrength` somewhere else is not.
  static AnimationPointer? parse(String pointer) {
    final parts = pointer.split('/');
    // A JSON pointer starts with `/`, so the first part is always empty.
    if (parts.length < 4 || parts.first.isNotEmpty) return null;
    if (parts[1] == 'extensions') return _parseLight(parts, pointer);
    if (parts[1] != 'materials') return null;
    final index = _index(parts[2]);
    if (index == null) return null;

    final property = switch (parts.sublist(3).join('/')) {
      'pbrMetallicRoughness/baseColorFactor' =>
        AnimationPointerProperty.baseColor,
      'pbrMetallicRoughness/roughnessFactor' =>
        AnimationPointerProperty.roughness,
      'pbrMetallicRoughness/metallicFactor' =>
        AnimationPointerProperty.metallic,
      'extensions/KHR_materials_emissive_strength/emissiveStrength' =>
        AnimationPointerProperty.emissiveStrength,
      final rest when _textureOffset.hasMatch(rest) =>
        AnimationPointerProperty.textureOffset,
      _ => null,
    };
    return property == null
        ? null
        : AnimationPointer(property: property, index: index, pointer: pointer);
  }

  /// A non-negative index written the one way JSON pointer allows: no sign,
  /// no leading zero.
  static int? _index(String part) {
    final index = int.tryParse(part);
    return index != null && index >= 0 && part == '$index' ? index : null;
  }

  /// `/extensions/KHR_lights_punctual/lights/{i}/color|intensity` — the
  /// light array lives under the root's `extensions`, so its index sits two
  /// parts deeper than a material's.
  static AnimationPointer? _parseLight(List<String> parts, String pointer) {
    if (parts.length != 6 ||
        parts[1] != 'extensions' ||
        parts[2] != 'KHR_lights_punctual' ||
        parts[3] != 'lights') {
      return null;
    }
    final index = _index(parts[4]);
    if (index == null) return null;
    final property = switch (parts[5]) {
      'color' => AnimationPointerProperty.lightColor,
      'intensity' => AnimationPointerProperty.lightIntensity,
      _ => null,
    };
    return property == null
        ? null
        : AnimationPointer(property: property, index: index, pointer: pointer);
  }

  /// A texture's `KHR_texture_transform` offset, wherever in the material
  /// the texture sits: the three metal-rough slots, the normal, occlusion and
  /// emissive maps.
  static final RegExp _textureOffset = RegExp(
    r'^(pbrMetallicRoughness/(baseColorTexture|metallicRoughnessTexture)|'
    r'normalTexture|occlusionTexture|emissiveTexture)'
    r'/extensions/KHR_texture_transform/offset$',
  );

  /// The pointer a writer emits for [property] of object [index] when there
  /// is no source string to keep — a track built by hand.
  factory AnimationPointer.of(AnimationPointerProperty property, int index) =>
      AnimationPointer(
        property: property,
        index: index,
        pointer: switch (property) {
          AnimationPointerProperty.baseColor =>
            '/materials/$index/pbrMetallicRoughness/baseColorFactor',
          AnimationPointerProperty.emissiveStrength =>
            '/materials/$index/extensions/KHR_materials_emissive_strength/'
                'emissiveStrength',
          AnimationPointerProperty.roughness =>
            '/materials/$index/pbrMetallicRoughness/roughnessFactor',
          AnimationPointerProperty.metallic =>
            '/materials/$index/pbrMetallicRoughness/metallicFactor',
          AnimationPointerProperty.textureOffset =>
            '/materials/$index/pbrMetallicRoughness/baseColorTexture/'
                'extensions/KHR_texture_transform/offset',
          AnimationPointerProperty.lightColor =>
            '/extensions/KHR_lights_punctual/lights/$index/color',
          AnimationPointerProperty.lightIntensity =>
            '/extensions/KHR_lights_punctual/lights/$index/intensity',
        },
      );

  final AnimationPointerProperty property;

  /// Index into the document's materials or lights, by [property]'s target.
  final int index;

  /// The JSON pointer as the file wrote it, kept so a writer puts the track
  /// back on the texture it came from rather than on a canonical one.
  final String pointer;

  AnimationPointerTarget get target => property.target;

  @override
  bool operator ==(Object other) =>
      other is AnimationPointer &&
      other.property == property &&
      other.index == index &&
      other.pointer == pointer;

  @override
  int get hashCode => Object.hash(property, index, pointer);

  @override
  String toString() => 'AnimationPointer($pointer)';
}

/// Where a pointer track's sampled value goes.
///
/// **A third list beside the node targets and the morph sinks**, for the
/// reason `MorphSink` gives: `AnimationTarget` is a published interface of
/// three transform setters, and a material's roughness is not a transform.
/// A model instance implements it over the materials and lights it owns.
abstract interface class AnimationPointerSink {
  /// Writes [values] — [AnimationPointerProperty.componentCount] floats — to
  /// [pointer]'s property. A pointer to an object the sink does not have is
  /// ignored: a clip may outlive the material it was authored against.
  void setPointer(AnimationPointer pointer, List<double> values);
}
