/// A width and a height in whole pixels, the shape of a size that is
/// answered rather than held.
library;

/// A width and a height in whole pixels: what a `ResourceSize` resolves to,
/// and the size of an image read from its header.
final class PixelExtent {
  /// The extent [width] by [height] pixels.
  const PixelExtent({required this.width, required this.height});

  /// How many pixels across.
  final int width;

  /// How many pixels down.
  final int height;

  @override
  bool operator ==(Object other) =>
      other is PixelExtent && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'PixelExtent(${width}x$height)';
}
