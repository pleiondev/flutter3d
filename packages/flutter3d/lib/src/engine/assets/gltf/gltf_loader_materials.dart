/// Decodes `materials`, `textures` and `samplers` into engine
/// [SurfaceMaterial]s.
///
/// **A part of `gltf_loader.dart`, not a file of its own**, for the same
/// reason as the rest of this pipeline's phases: it reads the private JSON
/// helpers (`_mapList`, `_asInt`, ...) declared at the bottom of
/// `gltf_loader.dart`, and those stay unexported by staying in the same
/// library.
part of 'gltf_loader.dart';

extension _GltfMaterials on GltfLoader {
  // ---------------------------------------------------------------- materials

  List<SurfaceMaterial> _decodeMaterials(
    Map<String, Object?> json,
    List<String> warnings,
  ) {
    final materials = _mapList(json['materials']);
    final textures = _mapList(json['textures']);
    final samplers = _mapList(json['samplers']);

    TextureBinding? textureRef(Object? value) {
      if (value is! Map) return null;
      final textureIndex = _asInt(value['index']);
      if (textureIndex == null ||
          textureIndex < 0 ||
          textureIndex >= textures.length) {
        return null;
      }
      final texture = textures[textureIndex];
      final imageIndex = _asInt(texture['source']);
      if (imageIndex == null) {
        // A texture may carry only an extension-provided source (e.g. KTX2),
        // which we do not decode.
        warnings.add(
          'textures[$textureIndex] has no core "source" image; ignored.',
        );
        return null;
      }

      final samplerIndex = _asInt(texture['sampler']);
      final sampler =
          samplerIndex != null &&
              samplerIndex >= 0 &&
              samplerIndex < samplers.length
          ? _decodeSampler(samplers[samplerIndex])
          : const TextureSampling();

      final texCoord = _asInt(value['texCoord']) ?? 0;
      if (texCoord != 0) {
        warnings.add(
          'A texture uses TEXCOORD_$texCoord; only set 0 is decoded.',
        );
      }

      return TextureBinding(
        imageIndex: imageIndex,
        texCoordSet: texCoord,
        sampling: sampler,
      );
    }

    return <SurfaceMaterial>[
      for (final material in materials)
        () {
          final pbr = material['pbrMetallicRoughness'];
          final pbrMap = pbr is Map
              ? pbr.cast<String, Object?>()
              : <String, Object?>{};
          final extensions = material['extensions'];
          final extensionsMap = extensions is Map
              ? extensions.cast<String, Object?>()
              : <String, Object?>{};

          final emissiveStrengthExt =
              extensionsMap['KHR_materials_emissive_strength'];
          final normalTex = material['normalTexture'];
          final occlusionTex = material['occlusionTexture'];

          final name = material['name'];
          final alphaMode = material['alphaMode'];

          return SurfaceMaterial(
            name: name is String ? name : null,
            baseColor: _vec4(pbrMap['baseColorFactor']),
            metallic: _asDouble(pbrMap['metallicFactor']) ?? 1.0,
            roughness: _asDouble(pbrMap['roughnessFactor']) ?? 1.0,
            baseColorTexture: textureRef(pbrMap['baseColorTexture']),
            metallicRoughnessTexture: textureRef(
              pbrMap['metallicRoughnessTexture'],
            ),
            normalTexture: textureRef(normalTex),
            normalScale: normalTex is Map
                ? (_asDouble(normalTex['scale']) ?? 1.0)
                : 1.0,
            occlusionTexture: textureRef(occlusionTex),
            occlusionStrength: occlusionTex is Map
                ? (_asDouble(occlusionTex['strength']) ?? 1.0)
                : 1.0,
            emissiveTexture: textureRef(material['emissiveTexture']),
            emissive: _vec3(material['emissiveFactor']),
            emissiveStrength: emissiveStrengthExt is Map
                ? (_asDouble(emissiveStrengthExt['emissiveStrength']) ?? 1.0)
                : 1.0,
            alphaMode: switch (alphaMode) {
              'MASK' => SurfaceAlphaMode.mask,
              'BLEND' => SurfaceAlphaMode.blend,
              _ => SurfaceAlphaMode.opaque,
            },
            alphaCutoff: _asDouble(material['alphaCutoff']) ?? 0.5,
            doubleSided: material['doubleSided'] == true,
            unlit: extensionsMap.containsKey('KHR_materials_unlit'),
          );
        }(),
    ];
  }
}

TextureSampling _decodeSampler(Map<String, Object?> sampler) {
  // Filter codes: 9728 NEAREST, 9729 LINEAR, plus the four mipmap variants.
  final magFilter = _asInt(sampler['magFilter']);
  final minFilter = _asInt(sampler['minFilter']);

  TextureWrap wrap(Object? code) => switch (_asInt(code)) {
    33071 => TextureWrap.clampToEdge,
    33648 => TextureWrap.mirroredRepeat,
    _ => TextureWrap.repeat,
  };

  return TextureSampling(
    magLinear: magFilter != 9728,
    minLinear: minFilter != 9728 && minFilter != 9984 && minFilter != 9986,
    useMipmaps: minFilter == null || minFilter >= 9984,
    wrapS: wrap(sampler['wrapS']),
    wrapT: wrap(sampler['wrapT']),
  );
}
