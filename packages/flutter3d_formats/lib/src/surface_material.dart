import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

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
  /// **Carried, not applied.** No shader here samples a texture through
  /// this, so a material with one still draws sampling its whole image —
  /// `gltf_loader_materials.dart`'s own warning about that stays exactly
  /// where it was. What changes is that a round trip no longer drops the
  /// numbers a decoder already had in hand.
  final TextureTransform? transform;
}

/// `KHR_texture_transform`'s three fields, decoded but not acted on — see
/// [TextureBinding.transform].
final class TextureTransform {
  TextureTransform({Vector2? offset, Vector2? scale, this.rotation = 0.0})
    : offset = offset ?? Vector2.zero(),
      scale = scale ?? Vector2(1.0, 1.0);

  /// UV offset, applied before scale and rotation per the extension's own
  /// spec — not that anything here applies either.
  final Vector2 offset;

  final Vector2 scale;

  /// Radians, counter-clockwise, about the origin.
  final double rotation;

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
    Vector4? baseColor,
    this.metallic = 0.0,
    this.roughness = 0.5,
    this.baseColorTexture,
    this.metallicRoughnessTexture,
    this.normalTexture,
    this.normalScale = 1.0,
    this.occlusionTexture,
    this.occlusionStrength = 1.0,
    this.emissiveTexture,
    Vector3? emissive,
    this.emissiveStrength = 1.0,
    this.alphaMode = SurfaceAlphaMode.opaque,
    this.alphaCutoff = 0.5,
    this.doubleSided = false,
    this.unlit = false,
    this.extras,
  }) : baseColor = baseColor ?? Vector4(1.0, 1.0, 1.0, 1.0),
       emissive = emissive ?? Vector3.zero();

  final String? name;

  /// RGBA tint as authored, i.e. non-linear for the colour channels.
  final Vector4 baseColor;

  final double metallic;
  final double roughness;

  final TextureBinding? baseColorTexture;
  final TextureBinding? metallicRoughnessTexture;
  final TextureBinding? normalTexture;
  final double normalScale;
  final TextureBinding? occlusionTexture;
  final double occlusionStrength;
  final TextureBinding? emissiveTexture;
  final Vector3 emissive;
  final double emissiveStrength;

  final SurfaceAlphaMode alphaMode;
  final double alphaCutoff;
  final bool doubleSided;

  /// Shade with albedo only, from glTF's `KHR_materials_unlit` or an OBJ material
  /// with no specular response at all.
  final bool unlit;

  /// glTF's own `extras` on this material, carried opaquely — see
  /// [ModelNode.extras] for what that means and why.
  final Map<String, Object?>? extras;

  @override
  String toString() =>
      'SurfaceMaterial(${name ?? 'unnamed'}, '
      'metallic: $metallic, roughness: $roughness)';
}
