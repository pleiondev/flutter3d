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
/// holds the clear coat, its roughness, the transmission and the thickness, a
/// sheen map the sheen's colour and roughness, one texture each (the lit
/// stages have no sampler to spare for every one). The specular textures, the
/// clear coat's own normal map, the anisotropy texture and the iridescence
/// textures are kept here so a round trip loses nothing, and not drawn — a
/// loader says so.
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
    this.transmission = 0.0,
    this.transmissionTexture,
    this.thickness = 0.0,
    this.thicknessTexture,
    this.attenuationDistance = double.infinity,
    Vector3? attenuationColor,
    this.dispersion = 0.0,
    this.iridescence = 0.0,
    this.iridescenceTexture,
    this.iridescenceIor = 1.3,
    this.iridescenceThicknessMinimum = 100.0,
    this.iridescenceThicknessMaximum = 400.0,
    this.iridescenceThicknessTexture,
  }) : specularColor = specularColor ?? Vector3(1.0, 1.0, 1.0),
       sheenColor = sheenColor ?? Vector3.zero(),
       attenuationColor = attenuationColor ?? Vector3(1.0, 1.0, 1.0);

  /// `KHR_materials_ior`: the dielectric's index of refraction. 1.5 is the
  /// four per cent a plain metal-rough dielectric reflects head-on. Nought is
  /// the extension's own special case, an infinite index: the surface reflects
  /// fully at every angle, tinted and scaled by the specular, which is how a
  /// specular-glossiness material migrates to this model.
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

  /// `KHR_materials_transmission`: how much of the light that is not
  /// reflected passes through the surface instead of scattering off it —
  /// glass, water, a thin film — `M3`. Its texture is read from red.
  final double transmission;
  final TextureBinding? transmissionTexture;

  /// `KHR_materials_volume`'s thickness, in the mesh's own units, over which
  /// the light passing through is attenuated. Its texture is read from green.
  final double thickness;
  final TextureBinding? thicknessTexture;

  /// How far light travels in the medium before it is [attenuationColor]:
  /// infinite, the default, is a medium that takes nothing away.
  final double attenuationDistance;
  final Vector3 attenuationColor;

  /// `KHR_materials_dispersion`: how far apart the index of refraction is
  /// spread over the spectrum, in the extension's own units (20 / Abbe
  /// number). Nought refracts every colour alike.
  final double dispersion;

  /// `KHR_materials_iridescence`: how much of the reflection is a thin film's
  /// interference — a soap bubble, an oil slick. Its texture is read from red,
  /// and carried rather than drawn, as is the thickness texture: the film is
  /// [iridescenceThicknessMaximum] thick everywhere, which is what the
  /// extension says a film without a thickness texture is.
  final double iridescence;
  final TextureBinding? iridescenceTexture;
  final double iridescenceIor;
  final double iridescenceThicknessMinimum;
  final double iridescenceThicknessMaximum;
  final TextureBinding? iridescenceThicknessTexture;

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
      anisotropyStrength != 0.0 ||
      transmission != 0.0 ||
      iridescence != 0.0;

  /// The textures a coat map packs, lane by lane, each with the channel of
  /// its own image the lane takes: red the clear coat (its red), green its
  /// roughness (its green), blue the transmission (its red), alpha the
  /// thickness (its green). Null where a lane keeps its neutral white.
  List<({TextureBinding binding, int channel})?> get coatMapSources =>
      <({TextureBinding binding, int channel})?>[
        for (final (binding, channel) in <(TextureBinding?, int)>[
          (clearcoatTexture, 0),
          (clearcoatRoughnessTexture, 1),
          (transmissionTexture, 0),
          (thicknessTexture, 1),
        ])
          binding == null ? null : (binding: binding, channel: channel),
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
    ?transmissionTexture,
    ?thicknessTexture,
    ?iridescenceTexture,
    ?iridescenceThicknessTexture,
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
      transmission: transmission,
      transmissionTexture: each(transmissionTexture),
      thickness: thickness,
      thicknessTexture: each(thicknessTexture),
      attenuationDistance: attenuationDistance,
      attenuationColor: attenuationColor.clone(),
      dispersion: dispersion,
      iridescence: iridescence,
      iridescenceTexture: each(iridescenceTexture),
      iridescenceIor: iridescenceIor,
      iridescenceThicknessMinimum: iridescenceThicknessMinimum,
      iridescenceThicknessMaximum: iridescenceThicknessMaximum,
      iridescenceThicknessTexture: each(iridescenceThicknessTexture),
    );
  }

  /// The glTF names of every extension this reads and writes — for a tool
  /// that lists what a file needs before it opens it, or a writer that
  /// fills `extensionsUsed` itself.
  static const Set<String> gltfNames = <String>{
    'KHR_materials_ior',
    'KHR_materials_specular',
    'KHR_materials_clearcoat',
    'KHR_materials_sheen',
    'KHR_materials_anisotropy',
    'KHR_materials_transmission',
    'KHR_materials_volume',
    'KHR_materials_dispersion',
    'KHR_materials_iridescence',
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
  final transmission = object('KHR_materials_transmission');
  final volume = object('KHR_materials_volume');
  final dispersion = object('KHR_materials_dispersion');
  final iridescence = object('KHR_materials_iridescence');
  if (ior == null &&
      specular == null &&
      clearcoat == null &&
      sheen == null &&
      anisotropy == null &&
      transmission == null &&
      volume == null &&
      dispersion == null &&
      iridescence == null) {
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
    transmission: _number(transmission?['transmissionFactor'], 0.0),
    transmissionTexture: texture(transmission?['transmissionTexture']),
    thickness: _number(volume?['thicknessFactor'], 0.0),
    thicknessTexture: texture(volume?['thicknessTexture']),
    attenuationDistance: _number(
      volume?['attenuationDistance'],
      double.infinity,
    ),
    attenuationColor: switch (volume?['attenuationColor']) {
      final Object colour => _vec3(colour),
      null => null,
    },
    dispersion: _number(dispersion?['dispersion'], 0.0),
    iridescence: _number(iridescence?['iridescenceFactor'], 0.0),
    iridescenceTexture: texture(iridescence?['iridescenceTexture']),
    iridescenceIor: _number(iridescence?['iridescenceIor'], 1.3),
    iridescenceThicknessMinimum: _number(
      iridescence?['iridescenceThicknessMinimum'],
      100.0,
    ),
    iridescenceThicknessMaximum: _number(
      iridescence?['iridescenceThicknessMaximum'],
      400.0,
    ),
    iridescenceThicknessTexture: texture(
      iridescence?['iridescenceThicknessTexture'],
    ),
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
  if (read.iridescenceTexture != null ||
      read.iridescenceThicknessTexture != null) {
    warnings?.add(
      '$where: KHR_materials_iridescence\'s textures are kept for export and '
      'not drawn; the film is its factor strong and its maximum thick.',
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
  final transmission = <String, Object?>{
    if (e.transmission != 0.0) 'transmissionFactor': e.transmission,
    'transmissionTexture': ?slot(e.transmissionTexture),
  };
  final attenuationColor = e.attenuationColor;
  final volume = <String, Object?>{
    if (e.thickness != 0.0) 'thicknessFactor': e.thickness,
    'thicknessTexture': ?slot(e.thicknessTexture),
    if (e.attenuationDistance.isFinite)
      'attenuationDistance': e.attenuationDistance,
    if (attenuationColor.x != 1.0 ||
        attenuationColor.y != 1.0 ||
        attenuationColor.z != 1.0)
      'attenuationColor': <double>[
        attenuationColor.x,
        attenuationColor.y,
        attenuationColor.z,
      ],
  };
  final iridescence = <String, Object?>{
    if (e.iridescence != 0.0) 'iridescenceFactor': e.iridescence,
    'iridescenceTexture': ?slot(e.iridescenceTexture),
    if (e.iridescenceIor != 1.3) 'iridescenceIor': e.iridescenceIor,
    if (e.iridescenceThicknessMinimum != 100.0)
      'iridescenceThicknessMinimum': e.iridescenceThicknessMinimum,
    if (e.iridescenceThicknessMaximum != 400.0)
      'iridescenceThicknessMaximum': e.iridescenceThicknessMaximum,
    'iridescenceThicknessTexture': ?slot(e.iridescenceThicknessTexture),
  };
  return <String, Object?>{
    if (e.ior != 1.5) 'KHR_materials_ior': <String, Object?>{'ior': e.ior},
    if (specular.isNotEmpty) 'KHR_materials_specular': specular,
    if (clearcoat.isNotEmpty) 'KHR_materials_clearcoat': clearcoat,
    if (sheen.isNotEmpty) 'KHR_materials_sheen': sheen,
    if (anisotropy.isNotEmpty) 'KHR_materials_anisotropy': anisotropy,
    if (transmission.isNotEmpty) 'KHR_materials_transmission': transmission,
    if (volume.isNotEmpty) 'KHR_materials_volume': volume,
    if (e.dispersion != 0.0)
      'KHR_materials_dispersion': <String, Object?>{'dispersion': e.dispersion},
    if (iridescence.isNotEmpty) 'KHR_materials_iridescence': iridescence,
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
