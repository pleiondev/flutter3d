/// Re-encodes a decoded document's images to a compressed KTX2 family —
/// `ap-07` in `doc/asset-pipeline-plan.md`, wired into the converter that was
/// waiting on it (`fmt-22`/`mat-30` in `doc/model-editor-plan.md`, the same
/// item under the editor plan's own numbering).
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:image/image.dart' as img;

import 'convert.dart';

/// Re-encodes every image in [document] that [family] can actually compress,
/// returning a document with only [ModelDocument.images] changed.
///
/// [family] `none` and `auto` both return [document] unchanged: `none` by
/// its own definition, and `auto` because choosing a family from the device
/// this CLI happens to run on would be a guess about the device the texture
/// is actually loaded on — `ap-09`'s own row is the one that resolves this
/// per target, and nothing here pre-empts it.
///
/// [report] hears why a specific image was left as it arrived — every
/// refusal here is a real, named gap (an odd size, an alpha channel `etc2`
/// cannot carry yet), never a silent skip.
Future<ModelDocument> encodeDocumentTextures(
  ModelDocument document,
  TextureFamily family, {
  void Function(String message)? report,
}) async {
  if (family == TextureFamily.none || family == TextureFamily.auto) {
    return document;
  }

  final images = <EncodedImage>[
    for (final image in document.images) _encodeOne(image, family, report),
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

EncodedImage _encodeOne(
  EncodedImage image,
  TextureFamily family,
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

  final int vkFormat;
  final Uint8List encoded;
  switch (family) {
    case TextureFamily.bc:
      if (hasAlpha) {
        vkFormat = VkFormat.bc3UNormBlock;
        encoded = encodeBc3(source);
      } else {
        vkFormat = VkFormat.bc1RgbaUNormBlock;
        encoded = encodeBc1(source);
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
      encoded = encodeEtc2Rgb8(source);
    default:
      // Unreachable: `none`/`auto` return before this function is called.
      return image;
  }

  final ktx2 = writeKtx2(
    vkFormat: vkFormat,
    pixelWidth: source.width,
    pixelHeight: source.height,
    levels: [encoded],
  );
  return EncodedImage(
    bytes: ktx2,
    name: image.name,
    mimeType: 'image/ktx2',
    sourceUri: image.sourceUri,
  );
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
  return Rgba8Image(
    width: decoded.width,
    height: decoded.height,
    pixels: pixels,
  );
}

bool _hasAlpha(Rgba8Image image) {
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (image.alpha(x, y) != 255) return true;
    }
  }
  return false;
}
