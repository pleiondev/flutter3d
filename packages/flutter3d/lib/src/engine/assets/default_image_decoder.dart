import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter3d_core/flutter3d_core.dart';

/// The [ImageDecoder] every existing Flutter app gets for free.
///
/// `ModelAsset.fromDocument` and `bindMaterial` default to this — neither
/// takes it as a required parameter, so nothing that already calls either
/// one needs to change (mcp-03n). `dart:ui`'s `instantiateImageCodec` is
/// exactly what `uploadEncodedImage` called directly before this package's
/// rendering core moved to `flutter3d_core`; only where the call lives
/// changed.
Future<Rgba8Image?> defaultImageDecoder(Uint8List encoded) async {
  final ui.Codec codec;
  try {
    codec = await ui.instantiateImageCodec(encoded);
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
