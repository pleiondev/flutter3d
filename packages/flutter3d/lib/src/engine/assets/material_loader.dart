import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import '../render/lighting_model.dart';
import '../render/material.dart';
import 'asset_source.dart';
import 'fmat/fmat.dart';
import 'gltf/gltf.dart' show AssetUriResolver;
import 'material_document.dart';
import 'surface_material.dart';
import 'texture_upload.dart';

export 'material_document.dart';

/// A reader for a material format the engine does not ship.
///
/// **The plugin boundary for looks, and the same shape as `ModelDecoder`.** The
/// engine ships `.fmat`; a studio with a material format of its own, or one that
/// wants to read another engine's, implements this and needs no change to this
/// package. Consulted before the built-in reader, so it can also replace it.
///
/// **Synchronous, and that is the difference from models.** A model decode runs
/// on a background isolate because it is megabytes of vertices and the frame it
/// would otherwise land in is being drawn; a material is a few hundred bytes of
/// text. Moving it to an isolate would cost more in sending than it saves, and
/// the isolate is what forces a model decoder to be sendable — a constraint
/// there is no reason to inherit here.
abstract interface class MaterialDecoder {
  /// Whether this decoder wants the file. [fileName] may be empty; [bytes] is
  /// the whole file, so a decoder with no useful suffix can sniff it.
  bool handles(String fileName, Uint8List bytes);

  /// Reads [bytes] into a document. Throws [FormatException] on a file it
  /// claimed and could not read.
  MaterialDocument decode(Uint8List bytes, String fileName);
}

/// Reads the material at [source], with no device involved.
///
/// Split from [bindMaterial] for the reason the model path is: reading is pure
/// and testable with no Flutter binding, and uploading is neither.
Future<MaterialDocument> loadMaterialDocument(
  AssetSource source, {
  List<MaterialDecoder> decoders = const <MaterialDecoder>[],
}) async {
  final bytes = await source.read();
  final fileName = source.fileName;
  for (final decoder in decoders) {
    if (decoder.handles(fileName, bytes)) {
      return decoder.decode(bytes, fileName);
    }
  }
  if (!fileName.toLowerCase().endsWith('.fmat') && !isFmat(bytes)) {
    throw FormatException(
      '$fileName is not a material this engine reads. Pass a MaterialDecoder '
      'for it, or convert it to .fmat.',
    );
  }
  return readFmat(bytes, name: fileName);
}

/// Turns a read material into one the renderer can draw with.
///
/// [resolveUri] fetches the images the document names — [AssetSource.resolveUri]
/// is the one to pass, and is what makes the paths relative to the material file
/// rather than to the working directory.
///
/// [lighting] is the scene's preferred model, used when the file names none. A
/// file that does name one wins: it knows which shader it was authored against,
/// and the scene does not.
///
/// **An image that cannot be read is a warning, not a failure.** A missing
/// normal map should cost a normal map, not the level — the renderer binds a
/// neutral texture in its place, which is the same thing a model with an
/// undecodable image gets.
Future<Material> bindMaterial(
  MaterialDocument document, {
  required GraphicsDevice device,
  required AssetUriResolver resolveUri,
  LightingModel lighting = LightingModel.pbr,
  List<String>? warnings,
}) async {
  // Keyed on the path **and on whether it carries a chain**, for the reason
  // spelled out where a model does the same: the chain is part of the texture,
  // not of the sampler, so two slots sampling one image differently must not be
  // handed whichever answer the first of them asked for.
  final cache = <(int, bool), TextureHandle?>{};

  Future<(TextureHandle?, SamplerOptions?)> resolve(
    TextureBinding? binding,
  ) async {
    if (binding == null) return (null, null);
    final index = binding.imageIndex;
    if (index < 0 || index >= document.images.length) return (null, null);

    final key = (index, binding.sampling.useMipmaps);
    if (!cache.containsKey(key)) {
      Uint8List? bytes;
      try {
        bytes = await resolveUri(document.images[index]);
      } catch (_) {
        bytes = null;
      }
      final uploaded = bytes == null
          ? null
          : await uploadEncodedImage(
              device,
              bytes,
              sampling: binding.sampling,
              report: (message) =>
                  warnings?.add('${document.images[index]}: $message'),
            );
      if (uploaded == null) {
        warnings?.add(
          '${document.images[index]} could not be read; the '
          'material falls back to its factors.',
        );
      }
      cache[key] = uploaded;
    }
    return (cache[key], samplerOptionsFor(binding.sampling));
  }

  final surface = document.surface;
  final (albedo, albedoSampler) = await resolve(surface.baseColorTexture);
  final (normal, normalSampler) = await resolve(surface.normalTexture);
  final (orm, ormSampler) = await resolve(surface.metallicRoughnessTexture);
  final (occlusion, occlusionSampler) = await resolve(surface.occlusionTexture);
  final (emissive, emissiveSampler) = await resolve(surface.emissiveTexture);

  final extra = <String, TextureHandle>{};
  for (final entry in document.extraTextures.entries) {
    final (handle, _) = await resolve(entry.value);
    if (handle != null) extra[entry.key] = handle;
  }

  return Material(
    name: surface.name,
    lighting:
        document.lighting ?? (surface.unlit ? LightingModel.unlit : lighting),
    baseColor: surface.baseColor.clone(),
    metallic: surface.metallic,
    roughness: surface.roughness,
    albedo: albedo,
    albedoSampler: albedoSampler,
    normal: normal,
    normalSampler: normalSampler,
    normalScale: surface.normalScale,
    metallicRoughness: orm,
    metallicRoughnessSampler: ormSampler,
    occlusion: occlusion,
    occlusionSampler: occlusionSampler,
    occlusionStrength: surface.occlusionStrength,
    emissiveTexture: emissive,
    emissiveSampler: emissiveSampler,
    emissive: surface.emissive.clone(),
    emissiveStrength: surface.emissiveStrength,
    alphaMode: switch (surface.alphaMode) {
      SurfaceAlphaMode.opaque => MaterialAlphaMode.opaque,
      SurfaceAlphaMode.mask => MaterialAlphaMode.mask,
      SurfaceAlphaMode.blend => MaterialAlphaMode.blend,
    },
    alphaCutoff: surface.alphaCutoff,
    doubleSided: surface.doubleSided,
    parameterBlock: document.parameterBlock,
    parameters: document.parameters,
    extraTextures: extra,
  );
}

/// Reads and binds in one call, which is what an application usually wants.
Future<Material> loadMaterial(
  AssetSource source, {
  required GraphicsDevice device,
  List<MaterialDecoder> decoders = const <MaterialDecoder>[],
  LightingModel lighting = LightingModel.pbr,
  List<String>? warnings,
}) async {
  final document = await loadMaterialDocument(source, decoders: decoders);
  warnings?.addAll(document.warnings);
  return bindMaterial(
    document,
    device: device,
    resolveUri: source.resolveUri,
    lighting: lighting,
    warnings: warnings,
  );
}
