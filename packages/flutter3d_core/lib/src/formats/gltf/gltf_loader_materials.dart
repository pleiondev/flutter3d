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
      // The core image first, when there is one. `KHR_texture_basisu` says a
      // reader that supports it should prefer its KTX2 over the core PNG. This
      // reader does support it — ETC1S and, since `gfx-78n`, UASTC with its
      // Zstandard wrapper — but both are *unpacked* to RGBA8, so beside a PNG
      // the KTX2 buys no memory and is the lossier of the two. The PNG wins
      // while it exists, and the extension's source is what a file that ships
      // only the KTX2 falls back to — which is the file that used to lose its
      // texture here with a one-line warning.
      final imageIndex =
          _asInt(texture['source']) ?? _basisuSource(texture, warnings);
      if (imageIndex == null) {
        warnings.add(
          'textures[$textureIndex] has neither a core "source" image nor a '
          'KHR_texture_basisu one; ignored.',
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

      // A texture info's own extensions, not the material's. Only files that
      // put `KHR_texture_transform` in `extensionsRequired` were ever
      // refused, and the commoner atlas export lists it under
      // `extensionsUsed` only.
      //
      // `fmt-19` gave the numbers somewhere to go, and they are carried, not
      // applied: a writer gets back what the file said. Whether they can be
      // honoured is a question about the whole material rather than about
      // this texture, so it is asked once the material is built, below.
      final infoExtensions = value['extensions'];
      final transformExt = infoExtensions is Map
          ? infoExtensions['KHR_texture_transform']
          : null;
      final transformMap = transformExt is Map
          ? transformExt.cast<String, Object?>()
          : const <String, Object?>{};

      return TextureBinding(
        imageIndex: imageIndex,
        texCoordSet: texCoord,
        sampling: sampler,
        transform: transformExt == null
            ? null
            : TextureTransform(
                offset: _vec2(transformMap['offset']),
                scale: _vec2(transformMap['scale']),
                rotation: _asDouble(transformMap['rotation']) ?? 0.0,
              ),
      );
    }

    /// The material, and a warning when its textures cannot all be honoured.
    ///
    /// One transform shared by every texture of a material is what an atlas
    /// export writes, and a consumer honours it by moving the coordinates —
    /// see `texture_transform_bake.dart`. Textures that disagree would each
    /// need a matrix of their own at the sampler, which nothing here has, so
    /// that material draws untransformed and this is where it is said.
    SurfaceMaterial checked(SurfaceMaterial material, int index) {
      if (hasConflictingTextureTransforms(material)) {
        warnings.add(
          'materials[$index] gives its textures different '
          'KHR_texture_transform values; one set of coordinates cannot honour '
          'them all, so none is applied and each samples its whole image.',
        );
      }
      return material;
    }

    return <SurfaceMaterial>[
      for (final (index, material) in materials.indexed)
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

          return checked(
            SurfaceMaterial(
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
              extras: _extrasOf(material),
            ),
            index,
          );
        }(),
    ];
  }
}

TextureSampling _decodeSampler(Map<String, Object?> sampler) {
  // Filter codes: 9728 NEAREST, 9729 LINEAR, plus the four mipmap variants
  // (9984 NEAREST_MIPMAP_NEAREST, 9985 LINEAR_MIPMAP_NEAREST,
  // 9986 NEAREST_MIPMAP_LINEAR, 9987 LINEAR_MIPMAP_LINEAR). The two mipmap
  // pairs disagree only on whether the *mip level* is interpolated, which is
  // `mipLinear` below and is a separate question from `minLinear` — losing
  // that distinction is what let 9985 and 9987 decode identically before.
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
    mipLinear: minFilter != 9984 && minFilter != 9985,
    wrapS: wrap(sampler['wrapS']),
    wrapT: wrap(sampler['wrapT']),
  );
}

/// The `(magFilter, minFilter)` GL constant pair a glTF writer should emit
/// for [sampling] — the exact inverse of [_decodeSampler]'s filter half, so a
/// document decoded from glTF and written back out names the same constant it
/// arrived with, mipmap variant included.
(int magFilter, int minFilter) toGltfFilters(TextureSampling sampling) {
  final magFilter = sampling.magLinear ? 9729 : 9728;
  final minFilter = switch ((
    sampling.useMipmaps,
    sampling.minLinear,
    sampling.mipLinear,
  )) {
    (false, false, _) => 9728,
    (false, true, _) => 9729,
    (true, false, false) => 9984,
    (true, true, false) => 9985,
    (true, false, true) => 9986,
    (true, true, true) => 9987,
  };
  return (magFilter, minFilter);
}
