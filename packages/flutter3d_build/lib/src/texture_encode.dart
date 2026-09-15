/// Re-encodes a decoded document's images to a compressed KTX2 family —
/// `ap-07` in `doc/asset-pipeline-plan.md`, wired into the converter that was
/// waiting on it (`fmt-22`/`mat-30` in `doc/model-editor-plan.md`, the same
/// item under the editor plan's own numbering) — and, since `ap-09`, into
/// `ap-08`'s mip chain the same call encodes every level of.
library;

import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:image/image.dart' as img;

import 'convert.dart';

/// Re-encodes every image in [document] that [family] can actually compress,
/// returning a document with only [ModelDocument.images] changed.
///
/// [family] `none` and `auto` both return [document] unchanged: `none` by
/// its own definition, and `auto` because choosing a family from the device
/// this CLI happens to run on would be a guess about the device the texture
/// is actually loaded on — [familiesForTarget] is what resolves this per
/// target, at the call site that knows which target it is building for,
/// and nothing here pre-empts it.
///
/// [mips] builds each compressed image as a full chain through `ap-08`'s
/// [buildMipChain], reading [ModelDocument.materials] to choose `srgb`,
/// `isNormalMap` and `alphaTestThreshold` per image the same way the shader
/// this material feeds would treat it — see [rolesByImageIndex]. `false`
/// keeps today's single-level file, for a caller measuring the difference
/// or working around a decoder that cannot yet read a multi-level file.
///
/// [report] hears why a specific image was left as it arrived — every
/// refusal here is a real, named gap (an odd size, an alpha channel `etc2`
/// cannot carry yet), never a silent skip.
Future<ModelDocument> encodeDocumentTextures(
  ModelDocument document,
  TextureFamily family, {
  bool mips = true,
  void Function(String message)? report,
}) async {
  if (family == TextureFamily.none || family == TextureFamily.auto) {
    return document;
  }

  final roles = rolesByImageIndex(document);
  final images = <EncodedImage>[
    for (var i = 0; i < document.images.length; i++)
      _encodeOne(
        document.images[i],
        family,
        roles[i] ?? const ImageRole(),
        mips,
        report,
      ),
  ];

  return PlainModelDocument(
    surfaces: document.surfaces,
    materials: document.materials,
    images: images,
    nodes: document.nodes,
    animations: document.animations,
    skins: document.skins,
    lights: document.lights,
    cameras: document.cameras,
    warnings: document.warnings,
    asset: document.asset,
  );
}

/// What a texture is used for, as far as `ap-08`'s [buildMipChain] needs to
/// know — [srgb] for base colour/emissive, [isNormalMap] for a normal map,
/// [alphaTestThreshold] for a mask material's own cutoff.
final class ImageRole {
  const ImageRole({this.srgb = false, this.isNormalMap = false, this.alphaTestThreshold});

  final bool srgb;
  final bool isNormalMap;
  final double? alphaTestThreshold;
}

/// Reads every material's texture bindings to say what each `images` index
/// is used for — exact, from [SurfaceMaterial]'s own typed fields
/// (`baseColorTexture`, `normalTexture`, …), never guessed from the image's
/// own bytes: a normal map and a base colour map can be bitwise identical
/// four-channel PNGs and only the material that names one of them says
/// which it is.
///
/// **First material wins when two disagree.** An image two materials both
/// reference — one as base colour, one as a normal map — has no single
/// right treatment, and this picks the first one found in document order
/// rather than silently averaging the two or refusing the whole document;
/// no test document in this package does that today, and a real one that
/// does is a gap worth naming when it is found, not guarded against on
/// spec. An image no material references at all (an orphaned embedded
/// texture, or one only `metallicRoughnessTexture`/`occlusionTexture` name)
/// gets the default [ImageRole] — linear, no alpha test — which is exactly
/// right for a metallic-roughness or occlusion map and merely conservative
/// for an orphan.
Map<int, ImageRole> rolesByImageIndex(ModelDocument document) {
  final roles = <int, ImageRole>{};
  void claim(int? imageIndex, ImageRole role) {
    if (imageIndex == null) return;
    roles.putIfAbsent(imageIndex, () => role);
  }

  for (final material in document.materials) {
    final maskThreshold = material.alphaMode == SurfaceAlphaMode.mask
        ? material.alphaCutoff
        : null;
    claim(
      material.baseColorTexture?.imageIndex,
      ImageRole(srgb: true, alphaTestThreshold: maskThreshold),
    );
    claim(material.emissiveTexture?.imageIndex, const ImageRole(srgb: true));
    claim(material.normalTexture?.imageIndex, const ImageRole(isNormalMap: true));
    claim(material.metallicRoughnessTexture?.imageIndex, const ImageRole());
    claim(material.occlusionTexture?.imageIndex, const ImageRole());
  }
  return roles;
}

EncodedImage _encodeOne(
  EncodedImage image,
  TextureFamily family,
  ImageRole role,
  bool mips,
  void Function(String message)? report,
) {
  if (image.isEmpty || isKtx2File(image.bytes)) return image;

  final label = image.name ?? image.sourceUri ?? '(embedded image)';
  final decoded = img.decodeImage(image.bytes);
  if (decoded == null) {
    report?.call('$label: not a format this encoder reads, left as it arrived');
    return image;
  }

  if (decoded.width % 4 != 0 || decoded.height % 4 != 0) {
    report?.call(
      '$label: ${decoded.width}x${decoded.height} is not whole 4x4 blocks, '
      'left as it arrived',
    );
    return image;
  }

  final source = _toRgba8(decoded);
  final hasAlpha = _hasAlpha(source);

  // `ap-08`: the base level alone when `mips` is off, otherwise every level
  // down to 1x1 — `chain.length == 1` either way lets the rest of this
  // function not branch on [mips] again below.
  final chain = mips
      ? buildMipChain(
          source,
          srgb: role.srgb,
          isNormalMap: role.isNormalMap,
          alphaTestThreshold: role.alphaTestThreshold,
        )
      : [source];

  final int vkFormat;
  final List<Uint8List> levels;
  switch (family) {
    case TextureFamily.bc:
      if (hasAlpha) {
        vkFormat = VkFormat.bc3UNormBlock;
        levels = [for (final level in chain) encodeBc3(_padToBlock(level))];
      } else {
        vkFormat = VkFormat.bc1RgbaUNormBlock;
        levels = [for (final level in chain) encodeBc1(_padToBlock(level))];
      }
    case TextureFamily.etc2:
      if (hasAlpha) {
        report?.call(
          '$label: has alpha, and ETC2 RGBA8 (EAC) is not encoded yet — '
          'left as it arrived',
        );
        return image;
      }
      vkFormat = VkFormat.etc2R8g8b8UNormBlock;
      levels = [for (final level in chain) encodeEtc2Rgb8(_padToBlock(level))];
    default:
      // Unreachable: `none`/`auto` return before this function is called.
      return image;
  }

  final ktx2 = writeKtx2(
    vkFormat: vkFormat,
    pixelWidth: source.width,
    pixelHeight: source.height,
    levels: levels,
  );
  return EncodedImage(
    bytes: ktx2,
    name: image.name,
    mimeType: 'image/ktx2',
    sourceUri: image.sourceUri,
  );
}

/// Pads [image] up to whole 4×4 blocks by repeating its last row and column
/// — clamp-to-edge, the same policy [buildMipChain] itself already commits
/// to for filtering (its own doc comment: "Clamp-to-edge only").
///
/// **Whose job this is, named rather than assumed.** `rgba8_image.dart`'s
/// own [requireWholeBlocks] doc comment says padding "belongs to whoever
/// calls the encoder, not to the encoder itself" — every BC/ETC2 encoder in
/// `flutter3d_formats` refuses a non-block-multiple source outright, on
/// purpose, because *how* to pad is a policy question a texture format has
/// no one right answer to. A full-size source is already validated to be
/// whole blocks before this file ever calls an encoder; a mip level is not
/// — `ap-08`'s own chain shrinks to 2×2 and 1×1, and this is where that
/// policy question gets its one answer, for this pipeline, honestly
/// written down rather than left for the next caller to rediscover as a
/// thrown [ArgumentError].
///
/// A level already whole returns unchanged — every full-size base image,
/// so this never allocates a second copy of the common case.
Rgba8Image _padToBlock(Rgba8Image image) {
  final paddedWidth = (image.width / 4).ceil() * 4;
  final paddedHeight = (image.height / 4).ceil() * 4;
  if (paddedWidth == image.width && paddedHeight == image.height) return image;

  final out = Uint8List(paddedWidth * paddedHeight * 4);
  for (var y = 0; y < paddedHeight; y++) {
    final srcY = y < image.height ? y : image.height - 1;
    for (var x = 0; x < paddedWidth; x++) {
      final srcX = x < image.width ? x : image.width - 1;
      final srcAt = (srcY * image.width + srcX) * 4;
      final dstAt = (y * paddedWidth + x) * 4;
      out[dstAt] = image.pixels[srcAt];
      out[dstAt + 1] = image.pixels[srcAt + 1];
      out[dstAt + 2] = image.pixels[srcAt + 2];
      out[dstAt + 3] = image.pixels[srcAt + 3];
    }
  }
  return Rgba8Image(width: paddedWidth, height: paddedHeight, pixels: out);
}

Rgba8Image _toRgba8(img.Image decoded) {
  final pixels = Uint8List(decoded.width * decoded.height * 4);
  var at = 0;
  for (var y = 0; y < decoded.height; y++) {
    for (var x = 0; x < decoded.width; x++) {
      final pixel = decoded.getPixel(x, y);
      pixels[at] = pixel.r.toInt();
      pixels[at + 1] = pixel.g.toInt();
      pixels[at + 2] = pixel.b.toInt();
      pixels[at + 3] = decoded.numChannels >= 4 ? pixel.a.toInt() : 255;
      at += 4;
    }
  }
  return Rgba8Image(width: decoded.width, height: decoded.height, pixels: pixels);
}

bool _hasAlpha(Rgba8Image image) {
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (image.alpha(x, y) != 255) return true;
    }
  }
  return false;
}
