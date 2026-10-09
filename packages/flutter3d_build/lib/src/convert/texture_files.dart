/// Images a material names by path: copied as they are when the engine
/// reads them (PNG, JPEG), re-encoded as PNG when it does not (TGA, PSD,
/// TIFF, BMP), and repacked when an engine lays its channels out
/// differently from glTF's.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'materials.dart';
import 'output.dart';
import 'report.dart';

/// The image at [path] as a [MaterialImage], or null with the reason in
/// [report].
MaterialImage? loadTextureFile(String path, ConvertReport report) {
  final file = File(path);
  if (!file.existsSync()) {
    report.drop('image $path', 'the file was not found');
    return null;
  }
  final bytes = file.readAsBytesSync();
  final extension = extensionOf(path);
  if (const <String>{'.png', '.jpg', '.jpeg'}.contains(extension)) {
    return MaterialImage(_name(path), bytes);
  }
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    report.drop('image $path', 'its format ($extension) could not be read');
    return null;
  }
  report.warn('image ${_name(path)}: $extension re-encoded as PNG');
  return MaterialImage(
    '${stemOf(path)}.png',
    Uint8List.fromList(img.encodePng(decoded)),
  );
}

String _name(String path) =>
    path.substring(path.replaceAll(r'\', '/').lastIndexOf('/') + 1);

/// An image laid out as glTF's metal-rough map — roughness in green, metal
/// in blue, and occlusion in red when [occlusion] gives one — from images
/// that keep them elsewhere.
///
/// [metal] reads metalness from its red channel and smoothness from its
/// alpha (Unity's Standard and Lit `_MetallicGlossMap`, and HDRP's
/// `_MaskMap`, whose green is occlusion: pass the same image as
/// [occlusion] with [occlusionChannel] 1). Roughness is one minus
/// smoothness times [smoothnessScale]. Null when an image will not decode.
MaterialImage? repackMetalRough({
  required String name,
  MaterialImage? metal,
  MaterialImage? occlusion,
  int occlusionChannel = 0,

  /// A unitless multiplier on the smoothness read from [metal]'s alpha.
  double smoothnessScale = 1.0,

  /// A unitless multiplier on the metalness read from [metal]'s red.
  double metalScale = 1.0,
}) {
  final m = metal == null ? null : img.decodeImage(metal.bytes);
  final o = occlusion == null ? null : img.decodeImage(occlusion.bytes);
  if ((metal != null && m == null) || (occlusion != null && o == null)) {
    return null;
  }
  final width = m?.width ?? o?.width ?? 1;
  final height = m?.height ?? o?.height ?? 1;
  final out = img.Image(width: width, height: height, numChannels: 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final mp = m?.getPixel(x * m.width ~/ width, y * m.height ~/ height);
      final op = o?.getPixel(x * o.width ~/ width, y * o.height ~/ height);
      final metalness = mp == null ? 1.0 : mp.rNormalized * metalScale;
      final smoothness = mp == null
          ? 0.0
          : (mp.length > 3 ? mp.aNormalized : 1.0) * smoothnessScale;
      final ao = op == null
          ? 1.0
          : switch (occlusionChannel) {
              1 => op.gNormalized,
              2 => op.bNormalized,
              _ => op.rNormalized,
            };
      out.setPixelRgb(
        x,
        y,
        (ao.clamp(0.0, 1.0) * 255).round(),
        ((1.0 - smoothness).clamp(0.0, 1.0) * 255).round(),
        (metalness.clamp(0.0, 1.0) * 255).round(),
      );
    }
  }
  return MaterialImage(name, Uint8List.fromList(img.encodePng(out)));
}

/// One channel of an image: which image, which channel (0 red to 3 alpha),
/// and whether to store one minus it.
typedef ChannelSource = ({MaterialImage image, int channel, bool invert});

/// An RGB image whose channels are taken from [red], [green] and [blue];
/// a missing one is white. Null when an image will not decode.
MaterialImage? packChannels(
  String name, {
  ChannelSource? red,
  ChannelSource? green,
  ChannelSource? blue,
}) {
  final sources = <ChannelSource?>[red, green, blue];
  final decoded = <img.Image?>[
    for (final s in sources) s == null ? null : img.decodeImage(s.image.bytes),
  ];
  for (var i = 0; i < 3; i++) {
    if (sources[i] != null && decoded[i] == null) return null;
  }
  final first = decoded.whereType<img.Image>().firstOrNull;
  if (first == null) return null;
  final out = img.Image(
    width: first.width,
    height: first.height,
    numChannels: 3,
  );
  for (var y = 0; y < first.height; y++) {
    for (var x = 0; x < first.width; x++) {
      final values = <int>[
        for (var i = 0; i < 3; i++)
          () {
            final image = decoded[i];
            final source = sources[i];
            if (image == null || source == null) return 255;
            final p = image.getPixel(
              x * image.width ~/ first.width,
              y * image.height ~/ first.height,
            );
            final v = switch (source.channel) {
              1 => p.gNormalized,
              2 => p.bNormalized,
              3 => p.length > 3 ? p.aNormalized : 1.0,
              _ => p.rNormalized,
            }.toDouble();
            return ((source.invert ? 1.0 - v : v).clamp(0.0, 1.0) * 255)
                .round();
          }(),
      ];
      out.setPixelRgb(x, y, values[0], values[1], values[2]);
    }
  }
  return MaterialImage(name, Uint8List.fromList(img.encodePng(out)));
}
