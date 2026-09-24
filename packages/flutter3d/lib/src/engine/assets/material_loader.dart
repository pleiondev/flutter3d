import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';

import 'default_image_decoder.dart';

// `Ktx2Texture` hidden: `flutter3d.dart` re-exports this package's own thin
// wrapper of the same name from `ktx2/ktx2.dart` instead — see its doc
// comment (`ap-01`).
export 'package:flutter3d_core/formats.dart' hide Ktx2Texture;

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
/// [lighting] is the scene's preferred model, used when neither the file nor
/// the material names one. [MaterialDocument.lighting] (the whole file's own
/// shader, which may be a custom one this engine does not ship) wins over
/// [SurfaceMaterial.lightingModel] (one material's own choice among the six
/// built-in models), which wins over [lighting]: each is more specific than
/// the one after it about what this material was authored against.
///
/// **An image that cannot be read is a warning, not a failure.** A missing
/// normal map should cost a normal map, not the level — the renderer binds a
/// neutral texture in its place, which is the same thing a model with an
/// undecodable image gets.
///
/// **An extra texture slot keeps its image and loses its sampler**, and says
/// so in [warnings] when the file asked for one. [Material.extraTextures] is
/// names to handles: a slot invented for an application's own shader has no
/// field here to hang a sampler off, so the encoder binds it with the
/// device's default. Only whether it carries a mip chain survives, because
/// that is part of the texture rather than of the sampler.
Future<Material> bindMaterial(
  MaterialDocument document, {
  required GraphicsDevice device,
  required AssetUriResolver resolveUri,
  LightingModel lighting = LightingModel.pbr,
  List<String>? warnings,
  ImageDecoder decodeImage = defaultImageDecoder,
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
        bytes = await resolveUri(AssetRequest(document.images[index]));
      } catch (_) {
        bytes = null;
      }
      final uploaded = bytes == null
          ? null
          : await uploadEncodedImage(
              device,
              bytes,
              decodeImage: decodeImage,
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
  // The layers' textures, decoded once each however many lanes they fill.
  final decoded = <int, Future<Rgba8Image?>>{};
  Future<Rgba8Image?> layerImage(TextureBinding binding) {
    final index = binding.imageIndex;
    if (index < 0 || index >= document.images.length) {
      return Future<Rgba8Image?>.value();
    }
    return decoded[index] ??= () async {
      try {
        final bytes = await resolveUri(AssetRequest(document.images[index]));
        return await decodeImage(bytes);
      } catch (_) {
        warnings?.add(
          '${document.images[index]} could not be read; the layer it packs '
          'into falls back to its factors.',
        );
        return null;
      }
    }();
  }

  final layers = surface.extensions;
  final coat = layers == null
      ? null
      : await uploadCoatMap(device, layers, image: layerImage);
  final sheen = layers == null
      ? null
      : await uploadSheenMap(device, layers, image: layerImage);
  final (albedo, albedoSampler) = await resolve(surface.baseColorTexture);
  final (normal, normalSampler) = await resolve(surface.normalTexture);
  final (orm, ormSampler) = await resolve(surface.metallicRoughnessTexture);
  final (occlusion, occlusionSampler) = await resolve(surface.occlusionTexture);
  final (emissive, emissiveSampler) = await resolve(surface.emissiveTexture);

  // Extras keep no sampler, and the file may ask for one. `Material`'s map is
  // `String -> TextureHandle`: the encoder binds these by name with the
  // device's default, because a slot named for an application's own shader
  // has no field here to hang a sampler off. A `.fmat` that writes
  // `{"path": ..., "wrapS": "clampToEdge"}` in such a slot therefore samples
  // repeating anyway — worth a sentence rather than a silent difference
  // between what the file says and what is drawn.
  const plain = TextureSampling();
  final extra = <String, TextureHandle>{};
  for (final entry in document.extraTextures.entries) {
    final (handle, _) = await resolve(entry.value);
    if (handle == null) continue;
    extra[entry.key] = handle;
    final sampling = entry.value.sampling;
    if (sampling.wrapS != plain.wrapS ||
        sampling.wrapT != plain.wrapT ||
        sampling.magLinear != plain.magLinear ||
        sampling.minLinear != plain.minLinear) {
      warnings?.add(
        'the "${entry.key}" texture asks for a sampler of its own, and an '
        'extra slot is bound with the device default; only the built-in '
        'slots keep one.',
      );
    }
  }

  return Material(
    name: surface.name,
    lighting:
        document.lighting ??
        (surface.lightingModel ??
                (surface.unlit ? LightingModel.unlit : lighting))
            .withLayers(surface.extensions),
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
    extensions: surface.extensions,
    coatMap: coat?.texture,
    coatMapSampler: coat?.sampler,
    sheenMap: sheen?.texture,
    sheenMapSampler: sheen?.sampler,
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
  ImageDecoder decodeImage = defaultImageDecoder,
}) async {
  final document = await loadMaterialDocument(source, decoders: decoders);
  warnings?.addAll(document.warnings);
  return bindMaterial(
    document,
    device: device,
    resolveUri: source.resolveUri,
    lighting: lighting,
    warnings: warnings,
    decodeImage: decodeImage,
  );
}

/// [source] as a material the renderer can draw with, uploading what it samples.
///
/// **The one conversion from a decoded material to a drawable one.** Every
/// decoder in the repository produces a [SurfaceMaterial] and the renderer takes
/// a [Material]; between them sits this, and there is one of it because the
/// mapping is long, dull and easy to get subtly wrong — an alpha mode dropped, a
/// sampler taken from the wrong slot — in a way that shows up as a picture
/// nobody can explain rather than as an error.
///
/// [layerImages] decodes the layers' textures on a device, so their channels
/// can be packed into the coat and sheen maps — see `uploadCoatMap`. Null
/// leaves both maps out, and the layers shade by their factors alone.
///
/// [textureFor] answers with an uploaded image for a slot, or null. Passing it
/// in rather than taking a list of images is what lets a caller cache: a model
/// whose nine materials sample one atlas uploads it once, and a modeller
/// rebuilding one material after an edit re-uploads nothing at all.
///
/// [transformsAtSampler] carries the maps' `KHR_texture_transform`s into
/// [Material.textureTransforms] and draws a metal-rough material with the
/// layered model, which reads them — `C8`. For a caller that does not bake
/// them into the coordinates; see `ModelAsset.fromDocument`, which decides.
/// A material another model draws gets none, since no other stage reads them.
Future<Material> bindSurfaceMaterial(
  SurfaceMaterial source, {
  LightingModel lighting = LightingModel.pbr,
  bool transformsAtSampler = false,
  required Future<TextureHandle?> Function(int, TextureSampling) textureFor,
  ({
    GraphicsDevice device,
    Future<Rgba8Image?> Function(TextureBinding binding) image,
  })?
  layerImages,
}) async {
  /// Resolves one texture slot, returning both the image and its sampler.
  ///
  /// A slot the file does not declare comes back null and the renderer binds
  /// a neutral texture instead, which is why nothing here has to record
  /// "this material has no normal map".
  Future<(TextureHandle?, SamplerOptions?)> resolve(
    TextureBinding? binding,
  ) async {
    if (binding == null) return (null, null);
    return (
      await textureFor(binding.imageIndex, binding.sampling),
      samplerOptionsFor(binding.sampling),
    );
  }

  final (albedo, albedoSampler) = await resolve(source.baseColorTexture);
  final (normal, normalSampler) = await resolve(source.normalTexture);
  final (orm, ormSampler) = await resolve(source.metallicRoughnessTexture);
  final (occlusion, occlusionSampler) = await resolve(source.occlusionTexture);
  final (emissive, emissiveSampler) = await resolve(source.emissiveTexture);
  final (coat, sheen) = switch ((source.extensions, layerImages)) {
    (final layers?, (:final device, :final image)) => (
      await uploadCoatMap(device, layers, image: image),
      await uploadSheenMap(device, layers, image: image),
    ),
    _ => (null, null),
  };

  // A material that names its own model wins outright; failing that, an
  // unlit material asks for unlit shading regardless of the scene's
  // preferred model, since ignoring the flag would light something
  // authored flat.
  //
  // `M1`: a metal-rough surface with layers is drawn by the layered model,
  // and so is one whose transforms are read at the sampler — `C8`.
  final model =
      (source.lightingModel ?? (source.unlit ? LightingModel.unlit : lighting))
          .withLayers(
            source.extensions,
            textureTransforms: transformsAtSampler,
          );
  final atSampler =
      transformsAtSampler && identical(model, LightingModel.pbrLayered);

  return Material(
    name: source.name,
    lighting: model,
    baseColor: source.baseColor.clone(),
    metallic: source.metallic,
    roughness: source.roughness,
    albedo: albedo,
    albedoSampler: albedoSampler,
    normal: normal,
    normalSampler: normalSampler,
    normalScale: source.normalScale,
    metallicRoughness: orm,
    metallicRoughnessSampler: ormSampler,
    occlusion: occlusion,
    occlusionSampler: occlusionSampler,
    occlusionStrength: source.occlusionStrength,
    emissiveTexture: emissive,
    emissiveSampler: emissiveSampler,
    emissive: source.emissive.clone(),
    emissiveStrength: source.emissiveStrength,
    alphaMode: switch (source.alphaMode) {
      SurfaceAlphaMode.opaque => MaterialAlphaMode.opaque,
      SurfaceAlphaMode.mask => MaterialAlphaMode.mask,
      SurfaceAlphaMode.blend => MaterialAlphaMode.blend,
    },
    alphaCutoff: source.alphaCutoff,
    doubleSided: source.doubleSided,
    extensions: source.extensions,
    coatMap: coat?.texture,
    coatMapSampler: coat?.sampler,
    sheenMap: sheen?.texture,
    sheenMapSampler: sheen?.sampler,
    textureTransforms: atSampler
        ? <MaterialMap, TextureTransform>{
            for (final map in MaterialMap.values)
              if (map.of(source)?.transform case final transform?)
                map: transform.clone(),
          }
        : null,
  );
}
