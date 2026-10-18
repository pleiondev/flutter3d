import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart'
    show cappedImageSize;

/// The [ImageDecoder] every existing Flutter app gets for free.
///
/// `ModelAsset.fromDocument` and `bindMaterial` default to this — neither
/// takes it as a required parameter, so nothing that already calls either
/// one needs to change (mcp-03n). `dart:ui`'s `instantiateImageCodec` is
/// exactly what `uploadEncodedImage` called directly before this package's
/// rendering core moved to `flutter3d_core`; only where the call lives
/// changed.
///
/// **A [SizedImageDecoder] — `A4.17`.** [maxDimension] caps the longer side,
/// and the codec is asked for that size up front (`getTargetSize`), so a
/// 8192² photograph meant for a phone is decoded at 2048² rather than decoded
/// whole and then thrown three quarters away. Null decodes at the file's own
/// size, as before.
Future<Rgba8Image?> defaultImageDecoder(
  Uint8List encoded, {
  int? maxDimension,
}) async {
  final ui.Codec codec;
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(encoded);
    codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (int width, int height) {
        final target = cappedImageSize(
          width,
          height,
          maxDimension: maxDimension,
        );
        return target.width == width && target.height == height
            ? ui.TargetImageSize()
            : ui.TargetImageSize(width: target.width, height: target.height);
      },
    );
  } catch (_) {
    return null;
  }

  final frame = await codec.getNextFrame();
  final image = frame.image;
  try {
    // Straight, not premultiplied: base-colour textures are sampled and then
    // multiplied by the material factor, so premultiplied alpha would darken
    // translucent texels twice.
    final data = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (data == null) return null;
    return Rgba8Image(
      width: image.width,
      height: image.height,
      pixels: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  } finally {
    // Both halves of the decode: the frame image, and the codec it came from.
    // The codec is a native decoder instance, and leaking one per texture is
    // exactly the kind of leak the image's own dispose was added to prevent.
    image.dispose();
    codec.dispose();
  }
}
