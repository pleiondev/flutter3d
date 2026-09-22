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
/// [mips] false keeps the base level alone — what `--no-mips` asks for, for a
/// caller measuring the difference or a texture that is only ever drawn at its
/// own size. The default is the chain `gfx-69n` added, since a compressed
/// texture with one level is the case where compressing makes the picture
/// worse.
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

  final images = <EncodedImage>[
    for (final image in document.images)
      _encodeOne(image, family, mips, report),
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

  final int vkFormat;
  final Uint8List Function(Rgba8Image) encode;
  // **The universal family writes no `vkFormat` at all — `gfx-83n`.** Its
  // blocks are not a GPU format, so the header says undefined and a key/value
  // entry says which layout they are; the load picks the real format from the
  // device. Handled before the switch because it is the one family whose
  // levels and header are written differently rather than encoded differently.
  if (family == TextureFamily.universal) {
    return _encodeUniversal(image, source, hasAlpha, mips, label, report);
  }
  switch (family) {
    case TextureFamily.bc:
      if (hasAlpha) {
        vkFormat = VkFormat.bc3UNormBlock;
        encode = encodeBc3;
      } else {
        vkFormat = VkFormat.bc1RgbaUNormBlock;
        encode = encodeBc1;
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
      encode = encodeEtc2Rgb8;
    default:
      // Unreachable: `none`/`auto` return before this function is called.
      return image;
  }

  final levels = _encodeLevels(source, encode, mips: mips);
  if (levels.length > 1) {
    report?.call(
      '$label: ${source.width}x${source.height}, ${levels.length} levels',
    );
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

/// The `universal` family — `gfx-83n`.
///
/// The header carries no format, because the blocks are not one: `vkFormat`
/// is undefined and [kUniversalBlockKey] says which layout they are and
/// whether alpha is meaningful in them. The alpha question is answered on the
/// base level here the same way it is for BC, and for the same reason: a
/// chain is one thing, and a level whose downsample happened to lose the last
/// translucent texel cannot change what the file says halfway down.
EncodedImage _encodeUniversal(
  EncodedImage image,
  Rgba8Image source,
  bool hasAlpha,
  bool mips,
  String label,
  void Function(String message)? report,
) {
  final levels = _encodeLevels(source, encodeUniversalBlocks, mips: mips);
  report?.call(
    '$label: ${source.width}x${source.height}, ${levels.length} '
    'level${levels.length == 1 ? '' : 's'} of universal blocks '
    '(${hasAlpha ? 'with' : 'without'} alpha)',
  );
  return EncodedImage(
    bytes: writeKtx2(
      vkFormat: VkFormat.undefined,
      pixelWidth: source.width,
      pixelHeight: source.height,
      levels: levels,
      keyValues: <String, String>{
        kUniversalBlockKey: hasAlpha ? kUniversalBlockRgba : kUniversalBlockRgb,
      },
    ),
    name: image.name,
    mimeType: 'image/ktx2',
    sourceUri: image.sourceUri,
  );
}

/// Every mip level of [source], each through [encode].
///
/// **A chain, not a level — `gfx-69n`.** One level was the case where
/// compressing makes the picture *worse*: a minified surface has nothing to
/// fall back to, so it samples the base at a stride and shimmers, and the
/// block artefacts shimmer with it. The uploader has always taken
/// `levels.sublist(1)` as the chain; nothing was giving it one.
///
/// [mips] false is the base level and nothing under it: the one place
/// `--no-mips` lands, so every family skips its chain the same way.
List<Uint8List> _encodeLevels(
  Rgba8Image source,
  Uint8List Function(Rgba8Image) encode, {
  required bool mips,
}) {
  if (!mips) return <Uint8List>[encode(source)];
  final levels = <Uint8List>[];
  var level = source;
  while (true) {
    levels.add(encode(level));
    // Four is the block, so a level below it cannot be encoded at all, and a
    // level that is not whole blocks is where the chain stops for the same
    // reason the base would have been refused: 96x96 goes 48, 24, 12, and then
    // 6 is not blocks, so the chain is four levels rather than an error.
    if (level.width <= 4 || level.height <= 4) break;
    final smaller = _halve(level);
    if (smaller.width % 4 != 0 || smaller.height % 4 != 0) break;
    level = smaller;
  }
  return levels;
}

/// [image] at half its size, each texel the average of the four it replaces.
///
/// A box filter rather than anything cleverer, and the reason is what a mip
/// level is for: it is the value a bilinear tap would have found had it been
/// able to read four texels at once, which is the average, exactly. A sharper
/// kernel makes a level that is not what the minified surface is showing, which
/// is aliasing put back by hand.
///
/// Averaged in the channel's own stored values, which is wrong for colour and
/// deliberately so: the engine's colour textures are uploaded as sRGB and the
/// hardware does the same thing between mip levels, so a gamma-correct average
/// here would disagree with the hardware's own between levels 0 and 1.
Rgba8Image _halve(Rgba8Image image) {
  final width = image.width ~/ 2;
  final height = image.height ~/ 2;
  final pixels = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final out = (y * width + x) * 4;
      for (var c = 0; c < 4; c++) {
        final a = image.pixels[((y * 2) * image.width + x * 2) * 4 + c];
        final b = image.pixels[((y * 2) * image.width + x * 2 + 1) * 4 + c];
        final d = image.pixels[((y * 2 + 1) * image.width + x * 2) * 4 + c];
        final e = image.pixels[((y * 2 + 1) * image.width + x * 2 + 1) * 4 + c];
        pixels[out + c] = (a + b + d + e + 2) ~/ 4;
      }
    }
  }
  return Rgba8Image(width: width, height: height, pixels: pixels);
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
