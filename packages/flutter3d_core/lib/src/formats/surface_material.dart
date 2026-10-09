import 'dart:typed_data';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show LinearColor;
import 'package:vector_math/vector_math.dart';

import 'lighting_model.dart';
import 'material_extensions.dart';

export 'material_extensions.dart';

/// How a surface treats the alpha channel.
enum SurfaceAlphaMode { opaque, mask, blend }

enum TextureWrap { repeat, clampToEdge, mirroredRepeat }

/// Filtering and wrapping requested for a texture.
final class TextureSampling {
  const TextureSampling({
    this.magLinear = true,
    this.minLinear = true,
    this.useMipmaps = true,
    this.mipLinear = true,
    this.wrapS = TextureWrap.repeat,
    this.wrapT = TextureWrap.repeat,
  });

  final bool magLinear;
  final bool minLinear;

  /// Assets almost always request mipmapped minification, and this is now
  /// acted on: `uploadEncodedImage` builds a chain when this is set, and
  /// `samplerOptionsFor` sets the mip filter from the same field so the chain
  /// is blended rather than merely allocated.
  ///
  /// Still not a fact about rendering on its own — a device is asked whether it
  /// samples a hand-built chain at all, because one that does not returns black
  /// rather than unfiltered. See `buildsMipChain`.
  final bool useMipmaps;

  /// Whether the mip level itself is chosen by interpolating between two
  /// (trilinear) rather than picked as the nearest one (bilinear-with-mips).
  ///
  /// **A separate bool from [minLinear] because GL's four mipmap filters are
  /// two independent choices, and one field cannot answer two questions.**
  /// `LINEAR_MIPMAP_NEAREST` (9985) and `LINEAR_MIPMAP_LINEAR` (9987) agree
  /// that a texel is sampled bilinearly and disagree about the mip; before
  /// this field they decoded to the same [TextureSampling], and a writer
  /// re-exporting either one had to guess. Meaningless when [useMipmaps] is
  /// false — nothing here changes what a sampler is built with yet, only what
  /// a decoder and a writer agree the file said.
  final bool mipLinear;

  final TextureWrap wrapS;
  final TextureWrap wrapT;
}

/// A reference from a material to one of the document's images.
///
/// Always an index, never a path: glTF addresses images by index while OBJ uses
/// relative filenames, and normalizing to an index in the decoder is what lets
/// consumers upload images without knowing which format they came from.
final class TextureBinding {
  const TextureBinding({
    required this.imageIndex,
    this.texCoordSet = 0,
    this.sampling = const TextureSampling(),
    this.transform,
  });

  final int imageIndex;

  /// Which texcoord set to sample with. Only set 0 is decoded today.
  final int texCoordSet;

  final TextureSampling sampling;

  /// `KHR_texture_transform`'s own offset/scale/rotation, when the source
  /// file named the extension — `fmt-19`'s own row. Null for a texture info
  /// with no such extension, which is every file before this one existed.
  ///
  /// **Carried here, and honoured by whoever draws the surface.** What draws —
  /// `ModelAsset` — moves the surface's texture coordinates when every
  /// texture of the material names the same transform, which is what an
  /// atlas export writes: see `texture_transform_bake.dart`. A material whose
  /// textures disagree, or whose offset a clip moves, is read through a
  /// matrix per map at the sampler instead — `C8`, `RenderMaterial.textureTransforms`.
  /// The document keeps the coordinates the file had beside the numbers it
  /// named, so a round trip gives the file back.
  final TextureTransform? transform;
}

/// The maps of a metal-rough material, in the order the layered stage keeps
/// their transforms — `C8`, `LayerInfo.uv_transform` and `kMapBaseColor` and
/// the rest in `lib/surface.glsl`.
enum MaterialMap {
  baseColor,
  metallicRoughness,
  normal,
  occlusion,
  emissive;

  /// [material]'s binding for this map, or null.
  TextureBinding? of(SurfaceMaterial material) => switch (this) {
    baseColor => material.baseColorTexture,
    metallicRoughness => material.metallicRoughnessTexture,
    normal => material.normalTexture,
    occlusion => material.occlusionTexture,
    emissive => material.emissiveTexture,
  };
}

/// `KHR_texture_transform`'s three fields — see [TextureBinding.transform].
final class TextureTransform {
  TextureTransform({Vector2? offset, Vector2? scale, this.rotation = 0.0})
    : offset = offset ?? Vector2.zero(),
      scale = scale ?? Vector2(1.0, 1.0);

  /// UV offset. The extension multiplies `translation * rotation * scale`, so
  /// a coordinate is scaled, then turned, then moved by this.
  final Vector2 offset;

  final Vector2 scale;

  /// Radians, counter-clockwise as the image is seen, about the origin. `v`
  /// runs down the image, so a quarter turn sends `+u` to `-v`.
  final double rotation;

  /// Whether this moves nothing, which is what a file that names the
  /// extension and gives it no fields has asked for.
  bool get isIdentity =>
      offset.x == 0.0 &&
      offset.y == 0.0 &&
      scale.x == 1.0 &&
      scale.y == 1.0 &&
      rotation == 0.0;

  /// Whether [other] asks for the same numbers.
  ///
  /// Exact, not within a tolerance: the question is whether two textures of
  /// one material were given one transform by whatever wrote the file, and a
  /// writer that did so wrote the same digits twice.
  bool sameAs(TextureTransform other) =>
      offset.x == other.offset.x &&
      offset.y == other.offset.y &&
      scale.x == other.scale.x &&
      scale.y == other.scale.y &&
      rotation == other.rotation;

  /// An independent copy, whose [offset] a clip may move without moving the
  /// document's.
  TextureTransform clone() => TextureTransform(
    offset: offset.clone(),
    scale: scale.clone(),
    rotation: rotation,
  );

  @override
  String toString() =>
      'TextureTransform(offset: $offset, scale: $scale, rotation: $rotation)';
}

/// An image still in its source encoding (PNG, JPEG, …).
///
/// Decoding is left to the caller because it needs `dart:ui`, and keeping that
/// out of the decoders is what lets the whole asset layer be unit tested with no
/// Flutter binding.
final class EncodedImage {
  const EncodedImage({
    required this.bytes,
    this.name,
    this.mimeType,
    this.sourceUri,
  });

  final Uint8List bytes;
  final String? name;
  final String? mimeType;

  /// Where the source file pointed to find this image, relative to the file
  /// itself — a glTF `uri` that named a sibling rather than a `data:` URI or a
  /// `bufferView`, or the path an OBJ `map_Kd` line gave. Null for an image
  /// that arrived embedded, since there was never a path to remember.
  ///
  /// A writer re-exporting the image reads this to decide whether to keep the
  /// original relative path or invent a new one; nothing here resolves it.
  final String? sourceUri;

  bool get isEmpty => bytes.isEmpty;
}

/// Format-neutral description of how a surface looks.
///
/// The single material abstraction every decoder produces. Metal-rough is the
/// target because it is what glTF defines and what the shaders implement; formats
/// that predate it (OBJ's Phong parameters) are approximated at decode time, with
/// the approximation documented where it happens rather than hidden.
final class SurfaceMaterial {
  SurfaceMaterial({
    this.name,
    this.baseColor = LinearColor.white,
    this.metallic = 0.0,
    this.roughness = 0.5,
    this.baseColorTexture,
    this.metallicRoughnessTexture,
    this.normalTexture,
    this.normalScale = 1.0,
    this.occlusionTexture,
    this.occlusionStrength = 1.0,
    this.emissiveTexture,
    this.emissive = LinearColor.black,
    this.emissiveStrength = 1.0,
    this.alphaMode = SurfaceAlphaMode.opaque,
    this.alphaCutoff = 0.5,
    this.doubleSided = false,
    this.unlit = false,
    this.lightingModel,
    this.extensions,
    this.extras,
  });

  final String? name;

  /// RGBA tint, linear with straight alpha, as every colour the engine
  /// holds. A format that stores it otherwise (OBJ's `Kd`, the `.f3d`
  /// material table) converts at its reader and writer.
  final LinearColor baseColor;

  /// A 0..1 fraction.
  final double metallic;

  /// Perceptual roughness, a 0..1 fraction.
  final double roughness;

  final TextureBinding? baseColorTexture;
  final TextureBinding? metallicRoughnessTexture;
  final TextureBinding? normalTexture;

  /// A unitless multiplier on the normal map's X and Y.
  final double normalScale;
  final TextureBinding? occlusionTexture;

  /// A 0..1 fraction of the occlusion texture applied.
  final double occlusionStrength;
  final TextureBinding? emissiveTexture;

  /// Linear; alpha is not read.
  final LinearColor emissive;

  /// A unitless multiplier on [emissive], as glTF's
  /// `KHR_materials_emissive_strength`; it becomes nits where the render
  /// material is made.
  final double emissiveStrength;

  final SurfaceAlphaMode alphaMode;

  /// A 0..1 fraction: in the mask mode, alpha below it is cut away.
  final double alphaCutoff;
  final bool doubleSided;

  /// Shade with albedo only, from glTF's `KHR_materials_unlit` or an OBJ material
  /// with no specular response at all.
  final bool unlit;

  /// Which of [LightingModel.builtIn] this surface asks the renderer to shade
  /// with, or null when the document never said — every decoder built before
  /// this field existed leaves it null, and a null reader falls back to
  /// [LightingModel.unlit] or [LightingModel.pbr] by [unlit] the same way the
  /// renderer's own default already did.
  ///
  /// Deliberately separate from [unlit] rather than replacing it: [unlit] is
  /// what glTF and OBJ can actually express on decode, while this field is
  /// the modeler's own richer choice among all six models — round-tripping
  /// through a format that has no such concept just drops it, the same way
  /// [extras] would.
  final LightingModel? lightingModel;

  /// The layers beyond metal-rough — clear coat, specular, index of
  /// refraction — or null for a surface that has none, which is every
  /// surface a format without them decodes. See [MaterialExtensions].
  final MaterialExtensions? extensions;

  /// glTF's own `extras` on this material, carried opaquely — see
  /// [ModelNode.extras] for what that means and why.
  final Map<String, Object?>? extras;

  @override
  String toString() =>
      'SurfaceMaterial(${name ?? 'unnamed'}, '
      'metallic: $metallic, roughness: $roughness)';
}
