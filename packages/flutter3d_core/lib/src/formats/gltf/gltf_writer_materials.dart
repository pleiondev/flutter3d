/// Encodes `document.materials` into glTF `materials`/`textures`/`samplers`,
/// the exact inverse of `gltf_loader_materials.dart`'s `_decodeMaterials`.
///
/// **A part of `gltf_writer.dart`**, so a texture reference can be built by
/// calling straight into the sampler/texture dedup tables kept here rather
/// than threading them through a public parameter list.
part of 'gltf_writer.dart';

extension _GltfWriterMaterials on GltfWriter {
  /// Builds `materials`, `samplers` and `textures`, in that dependency order
  /// so a material's texture reference can look up an index that already
  /// exists by the time it needs one.
  (
    List<Map<String, Object?>>,
    List<Map<String, Object?>>,
    List<Map<String, Object?>>,
  )
  _writeMaterials() {
    final samplers = <Map<String, Object?>>[];
    final samplerIndexByValue = <_SamplerKey, int>{};
    final textures = <Map<String, Object?>>[];
    final textureIndexByValue = <(int, int?), int>{};
    // Declared before `textureInfo` below, which adds to it whenever a
    // binding's own `KHR_texture_transform` needs recording — a texture
    // info's own extension, unlike every other one here, which are all a
    // material's.
    final extensionsUsed = <String>{};

    // `KHR_texture_basisu` is the only extension this writer ever needs
    // here: every other one degrades gracefully in a reader that ignores
    // it, but a texture with no core `source` has nothing to fall back to.
    final extensionsRequired = <String>{};

    int? samplerIndexFor(TextureSampling sampling) {
      // The all-default sampler needs no `samplers` entry at all — a texture
      // with no `sampler` key already means exactly this under the spec, and
      // every hand-built `SurfaceMaterial` in this repository's own tests
      // uses the default, so skipping it keeps their glTF output free of a
      // sampler nothing asked for.
      if (sampling == const TextureSampling()) return null;
      final key = _SamplerKey(sampling);
      final existing = samplerIndexByValue[key];
      if (existing != null) return existing;
      final (magFilter, minFilter) = toGltfFilters(sampling);
      samplers.add(<String, Object?>{
        'magFilter': magFilter,
        'minFilter': minFilter,
        'wrapS': _kGltfWrap[sampling.wrapS],
        'wrapT': _kGltfWrap[sampling.wrapT],
      });
      final index = samplers.length - 1;
      samplerIndexByValue[key] = index;
      return index;
    }

    int textureIndexFor(TextureBinding binding) {
      final samplerIndex = samplerIndexFor(binding.sampling);
      final key = (binding.imageIndex, samplerIndex);
      final existing = textureIndexByValue[key];
      if (existing != null) return existing;

      final image = document.images[binding.imageIndex];
      final isBasis = isKtx2BasisUniversal(image.bytes);
      textures.add(<String, Object?>{
        'sampler': ?samplerIndex,
        if (isBasis)
          'extensions': <String, Object?>{
            'KHR_texture_basisu': <String, Object?>{
              'source': binding.imageIndex,
            },
          }
        else
          'source': binding.imageIndex,
      });
      if (isBasis) {
        extensionsUsed.add('KHR_texture_basisu');
        extensionsRequired.add('KHR_texture_basisu');
      }

      final index = textures.length - 1;
      textureIndexByValue[key] = index;
      return index;
    }

    Map<String, Object?> textureInfo(TextureBinding binding) {
      final transform = binding.transform;
      final extensions = <String, Object?>{
        if (transform != null)
          'KHR_texture_transform': <String, Object?>{
            'offset': <double>[transform.offset.x, transform.offset.y],
            'scale': <double>[transform.scale.x, transform.scale.y],
            'rotation': transform.rotation,
          },
      };
      if (transform != null) extensionsUsed.add('KHR_texture_transform');
      return <String, Object?>{
        'index': textureIndexFor(binding),
        if (binding.texCoordSet != 0) 'texCoord': binding.texCoordSet,
        if (extensions.isNotEmpty) 'extensions': extensions,
      };
    }

    final materials = <Map<String, Object?>>[
      for (final material in document.materials)
        () {
          final extensions = <String, Object?>{};
          if (material.unlit) {
            extensions['KHR_materials_unlit'] = <String, Object?>{};
            extensionsUsed.add('KHR_materials_unlit');
          }
          if (material.emissiveStrength != 1.0) {
            extensions['KHR_materials_emissive_strength'] = <String, Object?>{
              'emissiveStrength': material.emissiveStrength,
            };
            extensionsUsed.add('KHR_materials_emissive_strength');
          }

          return <String, Object?>{
            if (material.name != null) 'name': material.name,
            'pbrMetallicRoughness': <String, Object?>{
              // Written unconditionally: glTF's own default for these two
              // (1.0) is not `SurfaceMaterial`'s (0.0 metallic, 0.5
              // roughness), so leaving either out on the strength of "that's
              // the default anyway" would read back as the wrong number.
              'baseColorFactor': <double>[
                material.baseColor.x,
                material.baseColor.y,
                material.baseColor.z,
                material.baseColor.w,
              ],
              'metallicFactor': material.metallic,
              'roughnessFactor': material.roughness,
              if (material.baseColorTexture case final t?)
                'baseColorTexture': textureInfo(t),
              if (material.metallicRoughnessTexture case final t?)
                'metallicRoughnessTexture': textureInfo(t),
            },
            if (material.normalTexture case final t?)
              'normalTexture': <String, Object?>{
                ...textureInfo(t),
                if (material.normalScale != 1.0) 'scale': material.normalScale,
              },
            if (material.occlusionTexture case final t?)
              'occlusionTexture': <String, Object?>{
                ...textureInfo(t),
                if (material.occlusionStrength != 1.0)
                  'strength': material.occlusionStrength,
              },
            if (material.emissiveTexture case final t?)
              'emissiveTexture': textureInfo(t),
            'emissiveFactor': <double>[
              material.emissive.x,
              material.emissive.y,
              material.emissive.z,
            ],
            if (material.alphaMode != SurfaceAlphaMode.opaque)
              'alphaMode': material.alphaMode == SurfaceAlphaMode.mask
                  ? 'MASK'
                  : 'BLEND',
            if (material.alphaMode == SurfaceAlphaMode.mask)
              'alphaCutoff': material.alphaCutoff,
            if (material.doubleSided) 'doubleSided': true,
            if (extensions.isNotEmpty) 'extensions': extensions,
            if (material.extras != null) 'extras': material.extras,
          };
        }(),
    ];

    if (extensionsUsed.isNotEmpty) {
      _extensionsUsed.addAll(extensionsUsed);
    }
    if (extensionsRequired.isNotEmpty) {
      _extensionsRequired.addAll(extensionsRequired);
    }
    return (materials, samplers, textures);
  }
}

const Map<TextureWrap, int> _kGltfWrap = <TextureWrap, int>{
  TextureWrap.repeat: 10497,
  TextureWrap.clampToEdge: 33071,
  TextureWrap.mirroredRepeat: 33648,
};

/// Structural-equality key for [TextureSampling], which has none of its own —
/// two textures that ask for the same filtering share one `samplers` entry
/// only if something can tell "the same" from "merely equal by chance".
final class _SamplerKey {
  _SamplerKey(this.sampling);

  final TextureSampling sampling;

  @override
  bool operator ==(Object other) =>
      other is _SamplerKey &&
      other.sampling.magLinear == sampling.magLinear &&
      other.sampling.minLinear == sampling.minLinear &&
      other.sampling.useMipmaps == sampling.useMipmaps &&
      other.sampling.mipLinear == sampling.mipLinear &&
      other.sampling.wrapS == sampling.wrapS &&
      other.sampling.wrapT == sampling.wrapT;

  @override
  int get hashCode => Object.hash(
    sampling.magLinear,
    sampling.minLinear,
    sampling.useMipmaps,
    sampling.mipLinear,
    sampling.wrapS,
    sampling.wrapT,
  );
}
