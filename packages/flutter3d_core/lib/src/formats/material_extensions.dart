import 'package:vector_math/vector_math.dart';

import 'surface_material.dart';

/// What a surface has beyond metal-rough: the `KHR_materials_*` layers glTF
/// adds on top of the core model — `M1`.
///
/// **One object rather than more fields on [SurfaceMaterial]**, because that
/// class is copied field by field in half a dozen places (a modeller's
/// command, a project file, an importer), and a layer the copy forgot is a
/// clear coat that disappears the first time an artist renames the material.
/// Here a copy carries every layer by carrying one reference.
///
/// **Linear colours**, unlike [SurfaceMaterial.baseColor]: glTF writes these
/// factors linear and nothing paints them, so there is no authored form to
/// keep.
///
/// Every default is the value that changes nothing: a material whose
/// extensions all sit at their defaults shades exactly as plain metal-rough,
/// which [shades] answers and the loaders use to decide whether a surface
/// needs the layered model at all.
///
/// The texture bindings are carried for the writers, and read by the renderer
/// only as far as `uploadCoatMap` and `uploadSheenMap` pack them: a coat map
/// holds the clear coat and its roughness, a sheen map the sheen's colour and
/// roughness, one texture each (the lit stages have no sampler to spare for
/// every one). The specular textures, the clear coat's own normal map and the
/// anisotropy texture are kept here so a round trip loses nothing, and not
/// drawn — a loader says so.
final class MaterialExtensions {
  MaterialExtensions({
    this.ior = 1.5,
    this.specular = 1.0,
    this.specularTexture,
    Vector3? specularColor,
    this.specularColorTexture,
    this.clearcoat = 0.0,
    this.clearcoatTexture,
    this.clearcoatRoughness = 0.0,
    this.clearcoatRoughnessTexture,
    this.clearcoatNormalTexture,
    this.clearcoatNormalScale = 1.0,
    Vector3? sheenColor,
    this.sheenColorTexture,
    this.sheenRoughness = 0.0,
    this.sheenRoughnessTexture,
    this.anisotropyStrength = 0.0,
    this.anisotropyRotation = 0.0,
    this.anisotropyTexture,
  }) : specularColor = specularColor ?? Vector3(1.0, 1.0, 1.0),
       sheenColor = sheenColor ?? Vector3.zero();

  /// `KHR_materials_ior`: the dielectric's index of refraction. 1.5 is the
  /// four per cent a plain metal-rough dielectric reflects head-on.
  final double ior;

  /// `KHR_materials_specular`'s strength: scales the dielectric reflection,
  /// head-on and at grazing both. Its texture is read from alpha.
  final double specular;
  final TextureBinding? specularTexture;

  /// `KHR_materials_specular`'s colour, linear: tints the head-on reflection
  /// of the dielectric part only. Its texture is sRGB.
  final Vector3 specularColor;
  final TextureBinding? specularColorTexture;

  /// `KHR_materials_clearcoat`: how much of a second, colourless GGX layer
  /// lies over the surface. Its texture is read from red.
  final double clearcoat;
  final TextureBinding? clearcoatTexture;

  /// The coat's own perceptual roughness. Its texture is read from green.
  final double clearcoatRoughness;
  final TextureBinding? clearcoatRoughnessTexture;

  /// The coat's own normal map. Carried, not drawn: the coat is lit on the
  /// geometric normal, which is what a lacquer over a bumpy base looks like.
  final TextureBinding? clearcoatNormalTexture;
  final double clearcoatNormalScale;

  /// `KHR_materials_sheen`'s colour, linear: the back-scattering of fibres
  /// that makes velvet bright at its edges. Black is no sheen. Its texture is
  /// sRGB, read from red, green and blue — `M2`.
  final Vector3 sheenColor;
  final TextureBinding? sheenColorTexture;

  /// The sheen's own perceptual roughness. Its texture is read from alpha.
  final double sheenRoughness;
  final TextureBinding? sheenRoughnessTexture;

  /// `KHR_materials_anisotropy`: how far the highlight stretches along the
  /// surface's tangent, nought to one — brushed metal.
  final double anisotropyStrength;

  /// Which way it stretches, in radians from the tangent towards the
  /// bitangent.
  final double anisotropyRotation;

  /// Direction in red and green, strength in blue. Carried, not drawn: the
  /// direction is the rotation alone.
  final TextureBinding? anisotropyTexture;

  /// Whether any of this changes how the surface is shaded.
  ///
  /// A texture alone does not: every map here multiplies its factor, so a
  /// clear coat map under a factor of nought is still no coat.
  bool get shades =>
      ior != 1.5 ||
      specular != 1.0 ||
      specularColor.x != 1.0 ||
      specularColor.y != 1.0 ||
      specularColor.z != 1.0 ||
      clearcoat != 0.0 ||
      sheenColor.x != 0.0 ||
      sheenColor.y != 0.0 ||
      sheenColor.z != 0.0 ||
      anisotropyStrength != 0.0;

  /// The textures a coat map packs, in its channel order: red the clear coat,
  /// green its roughness. Null where a channel keeps its neutral white.
  List<TextureBinding?> get coatMapSources => <TextureBinding?>[
    clearcoatTexture,
    clearcoatRoughnessTexture,
  ];

  /// The textures a sheen map packs: the colour's red, green and blue, and
  /// the roughness in alpha. Null where a lane keeps its neutral white.
  List<({TextureBinding binding, int channel})?> get sheenMapSources =>
      <({TextureBinding binding, int channel})?>[
        for (var channel = 0; channel < 3; channel++)
          if (sheenColorTexture case final binding?)
            (binding: binding, channel: channel)
          else
            null,
        if (sheenRoughnessTexture case final binding?)
          (binding: binding, channel: 3)
        else
          null,
      ];

  /// Every texture this carries, for a writer that has to know which images
  /// a material still refers to.
  List<TextureBinding> get textures => <TextureBinding>[
    ?specularTexture,
    ?specularColorTexture,
    ?clearcoatTexture,
    ?clearcoatRoughnessTexture,
    ?clearcoatNormalTexture,
    ?sheenColorTexture,
    ?sheenRoughnessTexture,
    ?anisotropyTexture,
  ];

  /// The same layers with each texture binding passed through [map] — for a
  /// document that renumbers its images.
  MaterialExtensions mapTextures(
    TextureBinding? Function(TextureBinding binding) map,
  ) {
    TextureBinding? each(TextureBinding? binding) =>
        binding == null ? null : map(binding);
    return MaterialExtensions(
      ior: ior,
      specular: specular,
      specularTexture: each(specularTexture),
      specularColor: specularColor.clone(),
      specularColorTexture: each(specularColorTexture),
      clearcoat: clearcoat,
      clearcoatTexture: each(clearcoatTexture),
      clearcoatRoughness: clearcoatRoughness,
      clearcoatRoughnessTexture: each(clearcoatRoughnessTexture),
      clearcoatNormalTexture: each(clearcoatNormalTexture),
      clearcoatNormalScale: clearcoatNormalScale,
      sheenColor: sheenColor.clone(),
      sheenColorTexture: each(sheenColorTexture),
      sheenRoughness: sheenRoughness,
      sheenRoughnessTexture: each(sheenRoughnessTexture),
      anisotropyStrength: anisotropyStrength,
      anisotropyRotation: anisotropyRotation,
      anisotropyTexture: each(anisotropyTexture),
    );
  }

  /// The glTF names of every extension this reads and writes.
  static const Set<String> gltfNames = <String>{
    'KHR_materials_ior',
    'KHR_materials_specular',
    'KHR_materials_clearcoat',
    'KHR_materials_sheen',
    'KHR_materials_anisotropy',
  };

  @override
  String toString() =>
      'MaterialExtensions(ior: $ior, specular: $specular, '
      'clearcoat: $clearcoat/$clearcoatRoughness)';
}

/// The layers [extensions] names — a glTF material's own `extensions`
/// object, or the same shape in a `.fmat` or a `.f3d` — or null when it names
/// none of [MaterialExtensions.gltfNames].
///
/// **One reader for three formats**, each passing its own [texture]: a glTF
/// texture info, a `.fmat` slot, a `.f3d` binding record. Only that differs;
/// the numbers, their names and their defaults are the extension's, so they
/// are spelled out once.
///
/// Textures the renderer does not draw are reported through [warnings],
/// once each, with [where] naming the material.
MaterialExtensions? materialExtensionsFromJson(
  Map<String, Object?> extensions, {
  required TextureBinding? Function(Object? info) texture,
  List<String>? warnings,
  String where = 'a material',
}) {
  Map<String, Object?>? object(String name) => switch (extensions[name]) {
    final Map<Object?, Object?> map => map.cast<String, Object?>(),
    _ => null,
  };
  final ior = object('KHR_materials_ior');
  final specular = object('KHR_materials_specular');
  final clearcoat = object('KHR_materials_clearcoat');
  final sheen = object('KHR_materials_sheen');
  final anisotropy = object('KHR_materials_anisotropy');
  if (ior == null &&
      specular == null &&
      clearcoat == null &&
      sheen == null &&
      anisotropy == null) {
    return null;
  }

  final read = MaterialExtensions(
    ior: _number(ior?['ior'], 1.5),
    specular: _number(specular?['specularFactor'], 1.0),
    specularTexture: texture(specular?['specularTexture']),
    specularColor: _vec3(specular?['specularColorFactor']),
    specularColorTexture: texture(specular?['specularColorTexture']),
    clearcoat: _number(clearcoat?['clearcoatFactor'], 0.0),
    clearcoatTexture: texture(clearcoat?['clearcoatTexture']),
    clearcoatRoughness: _number(clearcoat?['clearcoatRoughnessFactor'], 0.0),
    clearcoatRoughnessTexture: texture(clearcoat?['clearcoatRoughnessTexture']),
    clearcoatNormalTexture: texture(clearcoat?['clearcoatNormalTexture']),
    clearcoatNormalScale: switch (clearcoat?['clearcoatNormalTexture']) {
      {'scale': final num scale} => scale.toDouble(),
      _ => 1.0,
    },
    sheenColor: switch (sheen?['sheenColorFactor']) {
      final Object colour => _vec3(colour),
      null => null,
    },
    sheenColorTexture: texture(sheen?['sheenColorTexture']),
    sheenRoughness: _number(sheen?['sheenRoughnessFactor'], 0.0),
    sheenRoughnessTexture: texture(sheen?['sheenRoughnessTexture']),
    anisotropyStrength: _number(anisotropy?['anisotropyStrength'], 0.0),
    anisotropyRotation: _number(anisotropy?['anisotropyRotation'], 0.0),
    anisotropyTexture: texture(anisotropy?['anisotropyTexture']),
  );
  // The plan for 0.8: two packed maps and no more samplers, so these three
  // are carried and not drawn. Said once per material rather than silently.
  if (read.specularTexture != null || read.specularColorTexture != null) {
    warnings?.add(
      '$where: KHR_materials_specular\'s textures are kept for export and '
      'not drawn; only its factors shade the surface.',
    );
  }
  if (read.anisotropyTexture != null) {
    warnings?.add(
      '$where: KHR_materials_anisotropy\'s texture is kept for export and '
      'not drawn; its strength and rotation shade the surface.',
    );
  }
  if (read.clearcoatNormalTexture != null) {
    warnings?.add(
      '$where: the clear coat\'s normal map is kept for export and not '
      'drawn; the coat is lit on the geometric normal.',
    );
  }
  return read;
}

/// The inverse of [materialExtensionsFromJson]: each extension whose values
/// differ from its defaults, or that carries a texture, keyed by its glTF
/// name. [texture] writes one binding in the caller's format.
///
/// An extension at its defaults is left out, for the reason the glTF writer
/// leaves out `KHR_materials_emissive_strength` at one: it says nothing a
/// reader without it would not already draw.
Map<String, Object?> materialExtensionsToJson(
  MaterialExtensions e, {
  required Object? Function(TextureBinding binding) texture,
}) {
  Object? slot(TextureBinding? binding) =>
      binding == null ? null : texture(binding);
  final specularColor = e.specularColor;
  final specular = <String, Object?>{
    if (e.specular != 1.0) 'specularFactor': e.specular,
    'specularTexture': ?slot(e.specularTexture),
    if (specularColor.x != 1.0 ||
        specularColor.y != 1.0 ||
        specularColor.z != 1.0)
      'specularColorFactor': <double>[
        specularColor.x,
        specularColor.y,
        specularColor.z,
      ],
    'specularColorTexture': ?slot(e.specularColorTexture),
  };
  final coatNormal = slot(e.clearcoatNormalTexture);
  final clearcoat = <String, Object?>{
    if (e.clearcoat != 0.0) 'clearcoatFactor': e.clearcoat,
    'clearcoatTexture': ?slot(e.clearcoatTexture),
    if (e.clearcoatRoughness != 0.0)
      'clearcoatRoughnessFactor': e.clearcoatRoughness,
    'clearcoatRoughnessTexture': ?slot(e.clearcoatRoughnessTexture),
    if (coatNormal != null)
      'clearcoatNormalTexture':
          coatNormal is Map<String, Object?> && e.clearcoatNormalScale != 1.0
          ? <String, Object?>{...coatNormal, 'scale': e.clearcoatNormalScale}
          : coatNormal,
  };
  final sheenColor = e.sheenColor;
  final sheen = <String, Object?>{
    if (sheenColor.x != 0.0 || sheenColor.y != 0.0 || sheenColor.z != 0.0)
      'sheenColorFactor': <double>[sheenColor.x, sheenColor.y, sheenColor.z],
    'sheenColorTexture': ?slot(e.sheenColorTexture),
    if (e.sheenRoughness != 0.0) 'sheenRoughnessFactor': e.sheenRoughness,
    'sheenRoughnessTexture': ?slot(e.sheenRoughnessTexture),
  };
  final anisotropy = <String, Object?>{
    if (e.anisotropyStrength != 0.0) 'anisotropyStrength': e.anisotropyStrength,
    if (e.anisotropyRotation != 0.0) 'anisotropyRotation': e.anisotropyRotation,
    'anisotropyTexture': ?slot(e.anisotropyTexture),
  };
  return <String, Object?>{
    if (e.ior != 1.5) 'KHR_materials_ior': <String, Object?>{'ior': e.ior},
    if (specular.isNotEmpty) 'KHR_materials_specular': specular,
    if (clearcoat.isNotEmpty) 'KHR_materials_clearcoat': clearcoat,
    if (sheen.isNotEmpty) 'KHR_materials_sheen': sheen,
    if (anisotropy.isNotEmpty) 'KHR_materials_anisotropy': anisotropy,
  };
}

double _number(Object? value, double fallback) =>
    value is num ? value.toDouble() : fallback;

Vector3? _vec3(Object? value) => value is List<Object?> && value.length >= 3
    ? Vector3(
        _number(value[0], 1.0),
        _number(value[1], 1.0),
        _number(value[2], 1.0),
      )
    : null;
