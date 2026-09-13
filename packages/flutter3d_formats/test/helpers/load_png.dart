/// Decodes a PNG into an [Rgba8Image], test-only.
///
/// `package:image` is a `dev_dependency` — pure Dart, no Flutter SDK behind
/// it either, checked the same way `image` was added: `dart run
/// tool/structure.dart`'s "a flat Dart package resolves without the Flutter
/// SDK" rule scans `dev_dependencies` too. A PNG decoder belongs nowhere in
/// `lib/`: nothing this package ships needs to read one, only this test's
/// own ground truth does.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:image/image.dart' as img;

/// Reads [path], and crops to the largest whole-4×4-block size at or below
/// its own dimensions — every encoder in `lib/src/ktx2/encode/` refuses a
/// partial block, and a crop is a smaller change to a real photograph's
/// content than a pad would be.
Rgba8Image loadPngAsRgba8(String path) {
  final decoded = img.decodePng(File(path).readAsBytesSync());
  if (decoded == null) {
    throw StateError('$path is not a PNG this decoder reads');
  }
  final width = decoded.width - decoded.width % 4;
  final height = decoded.height - decoded.height % 4;
  final pixels = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final p = decoded.getPixel(x, y);
      final at = (y * width + x) * 4;
      pixels[at] = p.r.toInt();
      pixels[at + 1] = p.g.toInt();
      pixels[at + 2] = p.b.toInt();
      pixels[at + 3] = decoded.numChannels >= 4 ? p.a.toInt() : 255;
    }
  }
  return Rgba8Image(width: width, height: height, pixels: pixels);
}

/// Tiles [source] into a [times] x [times] grid — used only to build a large
/// benchmark image (2048² for `ap-07`'s timing acceptance) out of a real,
/// modestly sized fixture rather than vendoring a second, larger one just
/// for a timing number.
Rgba8Image tile(Rgba8Image source, int times) {
  final width = source.width * times;
  final height = source.height * times;
  final pixels = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    final sy = y % source.height;
    for (var x = 0; x < width; x++) {
      final sx = x % source.width;
      final dst = (y * width + x) * 4;
      final src = (sy * source.width + sx) * 4;
      pixels.setRange(dst, dst + 4, source.pixels, src);
    }
  }
  return Rgba8Image(width: width, height: height, pixels: pixels);
}
