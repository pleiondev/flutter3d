import 'dart:typed_data';

/// A decoded source image: tightly packed RGBA8, row-major, top row first —
/// exactly what `ui.Image.toByteData(format: rawStraightRgba)` hands the
/// engine's own texture upload path, and what every encoder in `encode/`
/// takes in.
///
/// `ap-07` in `doc/asset-pipeline-plan.md`: the encoders live here rather
/// than in `flutter3d_build` because they are the other half of
/// `ktx2_loader.dart` — bytes in, bytes in a GPU format out — and neither
/// half needs the Flutter SDK to do it.
final class Rgba8Image {
  Rgba8Image({required this.width, required this.height, required Uint8List pixels})
    : pixels = pixels {
    if (pixels.length != width * height * 4) {
      throw ArgumentError(
        'Rgba8Image is ${width}x$height, which is ${width * height * 4} '
        'bytes of RGBA8, but ${pixels.length} were given.',
      );
    }
  }

  final int width;
  final int height;

  /// Row-major, four bytes per pixel, top row first.
  final Uint8List pixels;

  int _at(int x, int y) => (y * width + x) * 4;

  int red(int x, int y) => pixels[_at(x, y)];
  int green(int x, int y) => pixels[_at(x, y) + 1];
  int blue(int x, int y) => pixels[_at(x, y) + 2];
  int alpha(int x, int y) => pixels[_at(x, y) + 3];
}

/// Reads one 4×4 block of [image] starting at pixel ([blockX]*4, [blockY]*4)
/// as sixteen `(r, g, b, a)` tuples in row-major order — pixel 0 is the
/// block's top-left corner, pixel 15 its bottom-right.
///
/// [image]'s dimensions must be whole 4×4 blocks: every encoder in this
/// directory refuses a source that is not, by the same reasoning
/// `texture_upload.dart` refuses to *upload* a compressed texture that is
/// not whole blocks — a partial block is a decision (pad how, with what)
/// that belongs to whoever calls the encoder, not to the encoder itself.
List<(int, int, int, int)> readBlock(Rgba8Image image, int blockX, int blockY) {
  final block = <(int, int, int, int)>[];
  final x0 = blockX * 4;
  final y0 = blockY * 4;
  for (var dy = 0; dy < 4; dy++) {
    for (var dx = 0; dx < 4; dx++) {
      final x = x0 + dx;
      final y = y0 + dy;
      block.add((image.red(x, y), image.green(x, y), image.blue(x, y), image.alpha(x, y)));
    }
  }
  return block;
}

/// Throws [ArgumentError] unless [image]'s dimensions are whole 4×4 blocks.
void requireWholeBlocks(Rgba8Image image, String encoderName) {
  if (image.width % 4 != 0 || image.height % 4 != 0) {
    throw ArgumentError(
      '$encoderName needs whole 4x4 blocks; ${image.width}x${image.height} '
      'is not one.',
    );
  }
}
