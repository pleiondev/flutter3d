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
  /// An image of [width] by [height] pixels over [pixels], not copied.
  /// Throws an [ArgumentError] unless [pixels] is `width * height * 4`
  /// bytes.
  Rgba8Image({
    required this.width,
    required this.height,
    required Uint8List pixels,
  }) : pixels = pixels {
    if (pixels.length != width * height * 4) {
      throw ArgumentError(
        'Rgba8Image is ${width}x$height, which is ${width * height * 4} '
        'bytes of RGBA8, but ${pixels.length} were given.',
      );
    }
  }

  /// Width in pixels.
  final int width;

  /// Height in pixels.
  final int height;

  /// Row-major, four bytes per pixel, top row first.
  final Uint8List pixels;

  int _at(int x, int y) => (y * width + x) * 4;

  /// Returns the red byte, 0 to 255, of pixel ([x], [y]); unchecked.
  int red(int x, int y) => pixels[_at(x, y)];

  /// Returns the green byte, 0 to 255, of pixel ([x], [y]); unchecked.
  int green(int x, int y) => pixels[_at(x, y) + 1];

  /// Returns the blue byte, 0 to 255, of pixel ([x], [y]); unchecked.
  int blue(int x, int y) => pixels[_at(x, y) + 2];

  /// Returns the alpha byte, 0 to 255, of pixel ([x], [y]), straight and
  /// not premultiplied; unchecked.
  int alpha(int x, int y) => pixels[_at(x, y) + 3];
}

/// Reads one 4×4 block of [image] starting at pixel ([blockX]*4, [blockY]*4)
/// as sixteen [Rgba8Texel]s in row-major order — pixel 0 is the
/// block's top-left corner, pixel 15 its bottom-right.
///
/// [image]'s dimensions must be whole 4×4 blocks: every encoder in this
/// directory refuses a source that is not, by the same reasoning
/// `texture_upload.dart` refuses to *upload* a compressed texture that is
/// not whole blocks — a partial block is a decision (pad how, with what)
/// that belongs to whoever calls the encoder, not to the encoder itself.
List<Rgba8Texel> readBlock(Rgba8Image image, int blockX, int blockY) {
  final block = <Rgba8Texel>[];
  final x0 = blockX * 4;
  final y0 = blockY * 4;
  for (var dy = 0; dy < 4; dy++) {
    for (var dx = 0; dx < 4; dx++) {
      final x = x0 + dx;
      final y = y0 + dy;
      block.add(
        Rgba8Texel(
          r: image.red(x, y),
          g: image.green(x, y),
          b: image.blue(x, y),
          a: image.alpha(x, y),
        ),
      );
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

/// One pixel of eight bits a channel: what a 4x4 block encoder takes sixteen
/// of, and what `decodeUniversalBlock` answers sixteen of.
final class Rgba8Texel {
  /// The texel with channels [r], [g], [b] and [a].
  const Rgba8Texel({
    required this.r,
    required this.g,
    required this.b,
    required this.a,
  });

  /// Red, 0 to 255.
  final int r;

  /// Green, 0 to 255.
  final int g;

  /// Blue, 0 to 255.
  final int b;

  /// Alpha, 0 to 255; 255 is opaque.
  final int a;

  @override
  bool operator ==(Object other) =>
      other is Rgba8Texel &&
      other.r == r &&
      other.g == g &&
      other.b == b &&
      other.a == a;

  @override
  int get hashCode => Object.hash(r, g, b, a);

  @override
  String toString() => 'Rgba8Texel($r, $g, $b, $a)';
}
